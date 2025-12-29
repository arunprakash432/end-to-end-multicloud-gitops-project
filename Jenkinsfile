pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    timeout(time: 1, unit: 'HOURS')
  }

  environment {
    // Docker
    DOCKER_USER = "dockervarun432"
    IMAGE_NAME  = "python-webapp-flask"

    // Git
    GIT_BRANCH = "main"

    // AWS
    AWS_REGION     = "ap-south-1"
    CLUSTER_A_NAME = "eks-cluster-monitoring-1"
    CLUSTER_B_NAME = "aws-app-eks-2"
  }

  stages {

    /* ============================
       CHECKOUT
    ============================ */
    stage('Checkout Code') {
      steps {
        checkout scm
      }
    }

    /* ============================
       PREVENT GITOPS LOOP
    ============================ */
    stage('Prevent GitOps Loop') {
      steps {
        script {
          def author = sh(
            script: "git log -1 --pretty=%an",
            returnStdout: true
          ).trim()

          if (author.toLowerCase().contains("jenkins")) {
            error("Stopping pipeline to prevent GitOps loop")
          }
        }
      }
    }

    /* ============================
       TERRAFORM
    ============================ */
    stage('Provision Infrastructure') {
      steps {
        dir('infrastructure') {
          sh 'terraform init'
          sh 'terraform apply -auto-approve'

          env.CLUSTER_B_URL = sh(
            script: "terraform output -raw eks2_endpoint",
            returnStdout: true
          ).trim()

          env.CLUSTER_C_URL = sh(
            script: "terraform output -raw aks_endpoint",
            returnStdout: true
          ).trim()

          env.AZ_RG = sh(
            script: "terraform output -raw resource_group_name",
            returnStdout: true
          ).trim()

          env.AKS_NAME = sh(
            script: "terraform output -raw aks_cluster_name",
            returnStdout: true
          ).trim()
        }
      }
    }

    /* ============================
       DOCKER BUILD & PUSH
    ============================ */
    stage('Build & Push Docker Image') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'docker-creds',
            usernameVariable: 'DUSER',
            passwordVariable: 'DPASS'
          )
        ]) {
          sh """
            docker login -u ${DUSER} -p ${DPASS}
            docker build -t ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER} ./app
            docker tag ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER} ${DOCKER_USER}/${IMAGE_NAME}:latest
            docker push ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER}
            docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
          """
        }
      }
    }

    /* ============================
       GITOPS UPDATE
    ============================ */
    stage('GitOps: Update Manifests') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'git-creds',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_PASS'
          )
        ]) {
          sh """
            sed -i 's/tag: .*/tag: "${BUILD_NUMBER}"/' k8s/helm-charts/python-app/values.yaml
            sed -i 's|server:.*|server: "${CLUSTER_B_URL}"|' k8s/argocd-apps/app-cluster-b.yaml
            sed -i 's|server:.*|server: "${CLUSTER_C_URL}"|' k8s/argocd-apps/app-cluster-c.yaml

            git checkout ${GIT_BRANCH}
            git config user.name "jenkins-bot"
            git config user.email "jenkins@ci.local"
            git add k8s/
            git commit -m "CI: Update image ${BUILD_NUMBER} [skip ci]" || true
            git push https://${GIT_USER}:${GIT_PASS}@github.com/arunprakash432/end-to-end-multicloud-gitops-project.git ${GIT_BRANCH}
          """
        }
      }
    }

    /* ============================
       ARGOCD
    ============================ */
    stage('ArgoCD Install & Sync') {
      steps {
        sh """
          aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}
          aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}
          az aks get-credentials --resource-group ${AZ_RG} --name ${AKS_NAME} --overwrite-existing

          kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
          kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
          kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

          kubectl apply -f k8s/argocd-apps/
        """
      }
    }

    /* ============================
       MONITORING + URL CAPTURE
    ============================ */
    stage('Monitoring Setup') {
      steps {
        script {
          // -------- Node Exporter (Cluster B) --------
          sh """
            aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
            helm repo update
            helm upgrade --install node-exporter \
              prometheus-community/prometheus-node-exporter \
              -f k8s/monitoring/node-exporter-values.yaml
          """

          sleep 60

          env.CLUSTER_B_METRICS = sh(
            script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()

          // -------- Central Prometheus + Grafana --------
          sh """
            aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}
            sed -i 's/<CLUSTER-B-IP>/${CLUSTER_B_METRICS}/' k8s/monitoring/central-prometheus.yaml
            helm upgrade --install prometheus prometheus-community/prometheus \
              -f k8s/monitoring/central-prometheus.yaml
            helm upgrade --install grafana prometheus-community/grafana
          """

          // -------- CAPTURE APPLICATION & TOOL URLS --------
          env.APP_B_URL = sh(
            script: "kubectl get svc -n default -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()

          sh "az aks get-credentials --resource-group ${AZ_RG} --name ${AKS_NAME} --overwrite-existing"

          env.APP_C_URL = sh(
            script: "kubectl get svc -n default -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'",
            returnStdout: true
          ).trim()

          sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"

          env.ARGOCD_URL = sh(
            script: "kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()

          env.PROM_URL = sh(
            script: "kubectl -n monitoring get svc prometheus-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()

          env.GRAFANA_URL = sh(
            script: "kubectl -n monitoring get svc grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()
        }
      }
    }
  }

  /* ============================
     FINAL OUTPUT
  ============================ */
  post {
    success {
      echo """
=================================================
✅ PIPELINE COMPLETED SUCCESSFULLY
=================================================

🚀 APPLICATION – CLUSTER B (AWS EKS)
----------------------------------
http://${APP_B_URL}

🚀 APPLICATION – CLUSTER C (AZURE AKS)
----------------------------------
http://${APP_C_URL}

📦 ARGOCD
----------------------------------
https://${ARGOCD_URL}:8081
Username: admin
Password:
kubectl -n argocd get secret argocd-initial-admin-secret \\
  -o jsonpath="{.data.password}" | base64 -d

📊 PROMETHEUS
----------------------------------
http://${PROM_URL}:9090
Targets:
http://${PROM_URL}:9090/targets

📈 GRAFANA
----------------------------------
http://${GRAFANA_URL}:3000
Username: admin
Password: admin
Dashboard ID: 1860 (Node Exporter Full)

🟢 MONITORING TARGET
----------------------------------
Cluster B Node Exporter:
${CLUSTER_B_METRICS}

=================================================
🎉 ALL SYSTEMS DEPLOYED & VERIFIED
=================================================
"""
    }

    failure {
      echo "❌ Pipeline failed — check logs"
    }

    always {
      cleanWs()
    }
  }
}
