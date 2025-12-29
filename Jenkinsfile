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
    GIT_BRANCH  = "main"

    // AWS
    AWS_REGION = "ap-south-1"

    // Clusters
    CLUSTER_A_MONITORING = "eks-cluster-monitoring-1"
    CLUSTER_B_AWS_APP    = "aws-app-eks-2"

    // Azure
    AZ_RESOURCE_GROUP = "rg-azure-app-vnet-1"
    AKS_CLUSTER_NAME  = "azure-app-aks-1"
  }

  stages {

    stage('Checkout Code') {
      steps {
        checkout scm
      }
    }

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

    stage('Provision Infrastructure') {
      steps {
        script {
          dir('infrastructure') {
            sh 'terraform init'
            sh 'terraform apply -auto-approve'
          }
        }
      }
    }

    stage('Build & Push Docker Image') {
      steps {
        script {
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
    }

    stage('GitOps: Update Manifests') {
      steps {
        script {
          withCredentials([
            usernamePassword(
              credentialsId: 'git-creds',
              usernameVariable: 'GIT_USER',
              passwordVariable: 'GIT_PASS'
            )
          ]) {
            sh """
              sed -i 's/tag: .*/tag: "${BUILD_NUMBER}"/' k8s/helm-charts/python-app/values.yaml

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
    }

    stage('ArgoCD Install & Sync') {
      steps {
        script {
          sh """
            aws eks update-kubeconfig --name ${CLUSTER_A_MONITORING} --region ${AWS_REGION}

            kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
            kubectl apply -n argocd \
              -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

            kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
            kubectl apply -f k8s/argocd-apps/
          """
        }
      }
    }

    stage('Monitoring Setup') {
      steps {
        script {
          // ---- Node Exporter on AWS App Cluster ----
          sh """
            aws eks update-kubeconfig --name ${CLUSTER_B_AWS_APP} --region ${AWS_REGION}

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

          // ---- Central Prometheus + Grafana on Monitoring Cluster ----
          sh """
            aws eks update-kubeconfig --name ${CLUSTER_A_MONITORING} --region ${AWS_REGION}

            helm repo add grafana https://grafana.github.io/helm-charts || true
            helm repo update

            sed -i 's/<CLUSTER-B-IP>/${CLUSTER_B_METRICS}/' k8s/monitoring/central-prometheus.yaml

            helm upgrade --install prometheus \
              prometheus-community/prometheus \
              -f k8s/monitoring/central-prometheus.yaml

            helm upgrade --install grafana grafana/grafana \
              --set service.type=LoadBalancer
          """
        }
      }
    }

    stage('Collect Browser URLs') {
      steps {
        script {
          // ---- AWS App ----
          sh "aws eks update-kubeconfig --name ${CLUSTER_B_AWS_APP} --region ${AWS_REGION}"
          env.APP_B_URL = sh(
            script: "kubectl get svc python-webapp-flask -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()

          // ---- Azure App ----
          sh "az aks get-credentials --resource-group ${AZ_RESOURCE_GROUP} --name ${AKS_CLUSTER_NAME} --overwrite-existing"
          sleep 60
          env.APP_C_URL = sh(
            script: "kubectl get svc python-webapp-flask -o jsonpath='{.status.loadBalancer.ingress[0].ip}'",
            returnStdout: true
          ).trim()

          // ---- Monitoring URLs ----
          sh "aws eks update-kubeconfig --name ${CLUSTER_A_MONITORING} --region ${AWS_REGION}"

          env.PROM_URL = sh(
            script: "kubectl get svc prometheus-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()

          env.GRAFANA_URL = sh(
            script: "kubectl get svc grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
            returnStdout: true
          ).trim()
        }
      }
    }
  }

  post {
    success {
      echo """
=================================================
✅ PIPELINE COMPLETED SUCCESSFULLY
=================================================

🚀 APPLICATION – AWS EKS
http://${APP_B_URL}

🚀 APPLICATION – AZURE AKS
http://${APP_C_URL}

📊 PROMETHEUS (CENTRAL)
http://${PROM_URL}

📈 GRAFANA
http://${GRAFANA_URL}
Username: admin
Password: admin

=================================================
🎉 MULTI-CLOUD GITOPS PIPELINE VERIFIED
=================================================
"""
    }
    always {
      cleanWs()
    }
  }
}
