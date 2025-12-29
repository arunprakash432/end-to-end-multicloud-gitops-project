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
        CLUSTER_A_NAME = "eks-cluster-monitoring-1"   // ArgoCD + Central Prometheus
        CLUSTER_B_NAME = "aws-app-eks-2"               // App cluster (AWS)
    }

    stages {

        /* =====================================================
           CHECKOUT
        ===================================================== */
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        /* =====================================================
           PREVENT GITOPS LOOP
        ===================================================== */
        stage('Prevent GitOps Loop') {
            steps {
                script {
                    def author = sh(
                        script: "git log -1 --pretty=%an",
                        returnStdout: true
                    ).trim()

                    echo "Last commit author: ${author}"

                    if (author.toLowerCase().contains("jenkins")) {
                        currentBuild.result = 'ABORTED'
                        error("Stopping pipeline to prevent GitOps loop")
                    }
                }
            }
        }

        /* =====================================================
           TERRAFORM – PROVISION INFRA
        ===================================================== */
        stage('Provision Infrastructure') {
            steps {
                script {
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

                        env.REAL_AZURE_RG = sh(
                            script: "terraform output -raw resource_group_name",
                            returnStdout: true
                        ).trim()

                        env.REAL_AKS_NAME = sh(
                            script: "terraform output -raw aks_cluster_name",
                            returnStdout: true
                        ).trim()
                    }
                }
            }
        }

        /* =====================================================
           DOCKER BUILD & PUSH
        ===================================================== */
        stage('Build & Push Docker Image') {
            steps {
                script {
                    def IMAGE_TAG    = "${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER}"
                    def IMAGE_LATEST = "${DOCKER_USER}/${IMAGE_NAME}:latest"

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'docker-creds',
                            usernameVariable: 'DUSER',
                            passwordVariable: 'DPASS'
                        )
                    ]) {
                        sh """
                            docker login -u ${DUSER} -p ${DPASS}
                            docker build -t ${IMAGE_TAG} ./app
                            docker tag ${IMAGE_TAG} ${IMAGE_LATEST}
                            docker push ${IMAGE_TAG}
                            docker push ${IMAGE_LATEST}
                        """
                    }
                }
            }
        }

        /* =====================================================
           GITOPS – UPDATE HELM & ARGOCD FILES
        ===================================================== */
        stage('GitOps: Update Manifests') {
            steps {
                script {
                    sh """
                        sed -i 's/tag: .*/tag: "${BUILD_NUMBER}"/' k8s/helm-charts/python-app/values.yaml
                        sed -i 's|server:.*|server: "${CLUSTER_B_URL}"|' k8s/argocd-apps/app-cluster-b.yaml
                        sed -i 's|server:.*|server: "${CLUSTER_C_URL}"|' k8s/argocd-apps/app-cluster-c.yaml
                    """

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'git-creds',
                            usernameVariable: 'GIT_USER',
                            passwordVariable: 'GIT_PASS'
                        )
                    ]) {
                        sh """
                            git checkout ${GIT_BRANCH}
                            git config user.name "jenkins-bot"
                            git config user.email "jenkins@ci.local"

                            git add k8s/
                            git commit -m "CI: Update image tag ${BUILD_NUMBER} [skip ci]" || true
                            git push https://${GIT_USER}:${GIT_PASS}@github.com/arunprakash432/end-to-end-multicloud-gitops-project.git ${GIT_BRANCH}
                        """
                    }
                }
            }
        }

        /* =====================================================
           ARGOCD – INSTALL + REGISTER CLUSTERS
        ===================================================== */
        stage('ArgoCD: Install, Register & Sync') {
            steps {
                script {
                    sh """
                        aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}
                        aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}
                        az aks get-credentials --resource-group ${REAL_AZURE_RG} --name ${REAL_AKS_NAME} --overwrite-existing

                        kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
                        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

                        kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

                        kubectl -n argocd port-forward svc/argocd-server 8081:443 &
                        sleep 15

                        ARGO_PWD=\$(kubectl -n argocd get secret argocd-initial-admin-secret \
                          -o jsonpath="{.data.password}" | base64 -d)

                        argocd login localhost:8081 \
                          --username admin \
                          --password "\$ARGO_PWD" \
                          --insecure \
                          --grpc-web

                        argocd cluster add \$(kubectl config get-contexts -o name | grep ${CLUSTER_B_NAME}) \
                          --name cluster-b --yes --upsert

                        argocd cluster add \$(kubectl config get-contexts -o name | grep ${REAL_AKS_NAME}) \
                          --name cluster-c --yes --upsert

                        kubectl apply -f k8s/argocd-apps/
                    """
                }
            }
        }

        /* =====================================================
           MONITORING – PROMETHEUS FEDERATION
        ===================================================== */
        stage('Monitoring: Federation Setup') {
            steps {
                script {

                    // ---- Cluster B (AWS) ----
                    sh """
                        aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}

                        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
                        helm repo update

                        helm upgrade --install node-exporter \
                          prometheus-community/prometheus-node-exporter \
                          -f k8s/monitoring/node-exporter-values.yaml
                    """

                    sleep 60

                    def B_DNS = sh(
                        script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
                        returnStdout: true
                    ).trim()

                    // ---- Cluster C (Azure) ----
                    sh """
                        az aks get-credentials --resource-group ${REAL_AZURE_RG} --name ${REAL_AKS_NAME}

                        helm upgrade --install node-exporter \
                          prometheus-community/prometheus-node-exporter \
                          -f k8s/monitoring/node-exporter-values.yaml
                    """

                    sleep 60

                    def C_IP = sh(
                        script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].ip}'",
                        returnStdout: true
                    ).trim()

                    // ---- Cluster A (Central Prometheus) ----
                    sh """
                        aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}
                    """

                    dir('k8s/monitoring') {
                        sh """
                            sed -i 's/<CLUSTER-B-IP>/${B_DNS}/g' central-prometheus.yaml
                            sed -i 's/<CLUSTER-C-IP>/${C_IP}/g' central-prometheus.yaml

                            helm upgrade --install prometheus \
                              prometheus-community/prometheus \
                              -f central-prometheus.yaml
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            echo "✅ Multi-cloud GitOps pipeline completed successfully"
        }
    }
}