pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        DOCKER_USER = "dockervarun432"
        IMAGE_NAME  = "python-webapp-flask"
        DOCKER_TAG  = "${BUILD_NUMBER}"
        GIT_BRANCH  = "main"
        
        AWS_REGION      = "ap-south-1"
        CLUSTER_A_NAME  = "eks-cluster-monitoring-1" // Central Monitoring
        CLUSTER_B_NAME  = "aws-app-eks-2"            // AWS App Cluster
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Prevent GitOps Loop') {
            steps {
                script {
                    def author = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
                    if (author.toLowerCase().contains("jenkins")) {
                        error("Aborted to prevent GitOps loop")
                    }
                }
            }
        }

        stage('Provision Infrastructure') {
            steps {
                dir('infrastructure') {
                    sh 'terraform init'
                    sh 'terraform apply -auto-approve'
                    script {
                        // Capture Cloud Outputs
                        env.REAL_AZURE_RG = sh(script: "terraform output -raw resource_group_name", returnStdout: true).trim()
                        env.REAL_AKS_NAME = sh(script: "terraform output -raw aks_cluster_name", returnStdout: true).trim()
                        env.CLUSTER_B_URL = sh(script: "terraform output -raw eks2_endpoint", returnStdout: true).trim()
                        env.CLUSTER_C_URL = sh(script: "terraform output -raw aks_endpoint", returnStdout: true).trim()
                    }
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-creds', usernameVariable: 'DUSER', passwordVariable: 'DPASS')]) {
                    sh """
                        echo "$DPASS" | docker login -u "$DUSER" --password-stdin
                        docker build -t ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ./app
                        docker tag ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ${DOCKER_USER}/${IMAGE_NAME}:latest
                        docker push ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG}
                        docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('GitOps Update') {
            steps {
                // Only update the Image Tag. Cluster mapping is handled by Logical Names.
                sh "sed -i 's/tag: .*/tag: \"${DOCKER_TAG}\"/' k8s/helm-charts/python-app/values.yaml"

                withCredentials([usernamePassword(credentialsId: 'git-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh """
                        git checkout ${GIT_BRANCH}
                        git config user.name "jenkins-bot"
                        git config user.email "jenkins@ci.local"
                        git add k8s/helm-charts/python-app/values.yaml
                        git commit -m "CI: update image tag ${DOCKER_TAG} [skip ci]" || true
                        git push https://${GIT_USER}:${GIT_PASS}@github.com/arunprakash432/end-to-end-multicloud-gitops-project.git ${GIT_BRANCH}
                    """
                }
            }
        }

        stage('ArgoCD Setup') {
            steps {
                sh """
                    # 1. Update Kubeconfigs
                    aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}
                    aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}
                    az aks get-credentials --resource-group "${env.REAL_AZURE_RG}" --name "${env.REAL_AKS_NAME}" --overwrite-existing
                    
                    # 2. Switch to Monitoring Cluster
                    kubectl config use-context \$(kubectl config get-contexts -o name | grep ${CLUSTER_A_NAME})
                    kubectl config set-context --current --namespace=argocd

                    # 3. Install ArgoCD
                    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
                    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
                    
                    # 4. Expose ArgoCD
                    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
                    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

                    # 5. Register Clusters (Using Fixed Logical Names)
                    argocd cluster add \$(kubectl config get-contexts -o name | grep ${CLUSTER_B_NAME}) --name aws-app-cluster --yes --upsert --core
                    argocd cluster add \$(kubectl config get-contexts -o name | grep ${env.REAL_AKS_NAME}) --name azure-app-cluster --yes --upsert --core

                    # 6. Apply ArgoCD Apps
                    kubectl apply -f k8s/argocd-apps/
                """
            }
        }

        stage('Monitoring Setup') {
            steps {
                script {
                    // --- 1. AWS Cluster Node Exporter ---
                    sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                    sh "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true"
                    sh "helm repo update"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    
                    echo "⏳ Waiting for AWS Node Exporter LoadBalancer..."
                    sh "timeout 300s bash -c 'until kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath=\"{.status.loadBalancer.ingress[0].hostname}\" > /dev/null 2>&1; do sleep 10; done'"
                    def B_DNS = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                    // --- 2. Azure Cluster Node Exporter ---
                    sh "az aks get-credentials --resource-group ${env.REAL_AZURE_RG} --name ${env.REAL_AKS_NAME}"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    
                    echo "⏳ Waiting for Azure Node Exporter IP..."
                    sh "timeout 300s bash -c 'until kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" > /dev/null 2>&1; do sleep 10; done'"
                    def C_IP = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()

                    // --- 3. Central Monitoring (Grafana/Prometheus) ---
                    sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                    sh "helm repo add grafana https://grafana.github.io/helm-charts || true"
                    sh "helm repo update"

                    // DYNAMICALLY GENERATE PROMETHEUS CONFIG
                    // This ensures we always have the FRESH IPs and fixes the "sed" error.
                    def promValues = """
extraScrapeConfigs: |
  - job_name: 'aws-node-exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['${B_DNS}:9100']
  - job_name: 'azure-node-exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['${C_IP}:9100']
server:
  service:
    type: LoadBalancer
"""
                    writeFile file: 'k8s/monitoring/central-prometheus-generated.yaml', text: promValues

                    // Install Prometheus using the GENERATED file
                    sh "helm upgrade --install prometheus prometheus-community/prometheus -f k8s/monitoring/central-prometheus-generated.yaml"
                    
                    // Install Grafana
                    sh "helm upgrade --install grafana grafana/grafana --set service.type=LoadBalancer --set adminPassword=admin"
                }
            }
        }
    }

    post {
        always { cleanWs() }
        success { 
            script {
                // --- 1. Fetch Monitoring URLs (Cluster A) ---
                sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                
                def argoUrl = sh(script: "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                def promUrl = sh(script: "kubectl get svc prometheus-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                def grafUrl = sh(script: "kubectl get svc grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                // --- 2. Fetch App URLs (Wait for them to appear) ---
                
                // AWS App
                sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                echo "⏳ Waiting for AWS App Deployment..."
                sh "timeout 300s bash -c 'until kubectl get svc python-app-service -o jsonpath=\"{.status.loadBalancer.ingress[0].hostname}\" > /dev/null 2>&1; do echo waiting for AWS app...; sleep 10; done'"
                def awsAppUrl = sh(script: "kubectl get svc python-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                // Azure App
                sh "az aks get-credentials --resource-group ${env.REAL_AZURE_RG} --name ${env.REAL_AKS_NAME}"
                echo "⏳ Waiting for Azure App Deployment..."
                sh "timeout 300s bash -c 'until kubectl get svc python-app-service -o jsonpath=\"{.status.loadBalancer.ingress[0].ip}\" > /dev/null 2>&1; do echo waiting for Azure app...; sleep 10; done'"
                def azureAppUrl = sh(script: "kubectl get svc python-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()

                echo """
                ==========================================================
                ✅ DEPLOYMENT SUCCESSFUL
                ==========================================================
                🚀 ArgoCD UI:      https://${argoUrl}
                📊 Grafana UI:     http://${grafUrl} (User: admin / Pass: admin)
                📈 Prometheus UI:  http://${promUrl}
                
                📱 APPLICATIONS
                ☁️  AWS App:       http://${awsAppUrl}
                ☁️  Azure App:     http://${azureAppUrl}
                ==========================================================
                """
            }
        }
    }
}