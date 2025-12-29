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
        CLUSTER_A_NAME  = "eks-cluster-monitoring-1" // Central
        CLUSTER_B_NAME  = "aws-app-eks-2"            // App Cluster
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
                        env.CLUSTER_B_URL = sh(script: "terraform output -raw eks2_endpoint", returnStdout: true).trim()
                        env.CLUSTER_C_URL = sh(script: "terraform output -raw aks_endpoint", returnStdout: true).trim()
                        env.REAL_AZURE_RG = sh(script: "terraform output -raw resource_group_name", returnStdout: true).trim()
                        env.REAL_AKS_NAME = sh(script: "terraform output -raw aks_cluster_name", returnStdout: true).trim()
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
                sh """
                    sed -i 's/tag: .*/tag: "${DOCKER_TAG}"/' k8s/helm-charts/python-app/values.yaml
                    sed -i 's|server:.*|server: "${env.CLUSTER_B_URL}"|' k8s/argocd-apps/app-cluster-b.yaml
                    sed -i 's|server:.*|server: "${env.CLUSTER_C_URL}"|' k8s/argocd-apps/app-cluster-c.yaml
                """

                withCredentials([usernamePassword(credentialsId: 'git-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh """
                        git checkout ${GIT_BRANCH}
                        git config user.name "jenkins-bot"
                        git config user.email "jenkins@ci.local"
                        git add k8s/
                        git commit -m "CI: update image tag ${DOCKER_TAG} [skip ci]" || true
                        git push https://${GIT_USER}:${GIT_PASS}@github.com/arunprakash432/end-to-end-multicloud-gitops-project.git ${GIT_BRANCH}
                    """
                }
            }
        }

        stage('ArgoCD Setup (Public Exposure)') {
            steps {
                sh """
                    aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}
                    aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}
                    az aks get-credentials --resource-group "${env.REAL_AZURE_RG}" --name "${env.REAL_AKS_NAME}" --overwrite-existing
                    
                    # Switch to Monitoring Cluster
                    kubectl config use-context \$(kubectl config get-contexts -o name | grep ${CLUSTER_A_NAME})

                    # CRITICAL FIX: Explicitly set namespace to 'argocd'
                    kubectl config set-context --current --namespace=argocd

                    # Install ArgoCD
                    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
                    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
                    
                    # EXPOSE ARGOCD TO INTERNET (LoadBalancer)
                    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
                    
                    # Wait for ArgoCD Server
                    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

                    # Register Clusters (Core Mode)
                    argocd cluster add \$(kubectl config get-contexts -o name | grep ${CLUSTER_B_NAME}) --yes --upsert --core
                    argocd cluster add \$(kubectl config get-contexts -o name | grep ${env.REAL_AKS_NAME}) --yes --upsert --core

                    kubectl apply -f k8s/argocd-apps/
                """
            }
        }

        stage('Monitoring Setup (Public Exposure)') {
            steps {
                script {
                    // 1. Cluster B (AWS) Node Exporter
                    sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                    sh "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true"
                    sh "helm repo update"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    
                    echo "⏳ Waiting for AWS DNS..."
                    sleep 30
                    def B_DNS = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                    // 2. Cluster C (Azure) Node Exporter
                    sh "az aks get-credentials --resource-group ${env.REAL_AZURE_RG} --name ${env.REAL_AKS_NAME}"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    
                    echo "⏳ Waiting for Azure IP..."
                    sleep 30
                    def C_IP = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()

                    // 3. Central Cluster (Prometheus & Grafana)
                    sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                    
                    // Add Grafana Repo (Fix for 'chart not found' error)
                    sh "helm repo add grafana https://grafana.github.io/helm-charts || true"
                    sh "helm repo update"

                    dir('k8s/monitoring') {
                        // Update Config
                        sh "sed -i 's/<CLUSTER-B-IP>/${B_DNS}/g' central-prometheus.yaml"
                        sh "sed -i 's/<CLUSTER-C-IP>/${C_IP}/g' central-prometheus.yaml"
                        
                        // EXPOSE PROMETHEUS (LoadBalancer)
                        sh "helm upgrade --install prometheus prometheus-community/prometheus -f central-prometheus.yaml"

                        // EXPOSE GRAFANA (LoadBalancer)
                        sh """
                            helm upgrade --install grafana grafana/grafana \
                            --set service.type=LoadBalancer \
                            --set adminPassword=admin
                        """
                    }
                }
            }
        }
    }

    post {
        always { cleanWs() }
        success { 
            script {
                // --- 1. Fetch Monitoring URLs ---
                sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                
                def argoUrl = sh(script: "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                def promUrl = sh(script: "kubectl get svc prometheus-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                def grafUrl = sh(script: "kubectl get svc grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                // --- 2. Fetch Application URLs (AWS Cluster B) ---
                sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                
                echo "⏳ Waiting for AWS Application to be deployed by ArgoCD..."
                // Loop to wait for service creation
                sh """
                    timeout=300
                    elapsed=0
                    while ! kubectl get svc python-app-service >/dev/null 2>&1; do
                        echo "Waiting for python-app-service on AWS..."
                        sleep 10
                        elapsed=\$((elapsed+10))
                        if [ \$elapsed -ge \$timeout ]; then echo "Timeout waiting for AWS app"; break; fi
                    done
                """
                def awsAppUrl = sh(script: "kubectl get svc python-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Not-Found'", returnStdout: true).trim()

                // --- 3. Fetch Application URLs (Azure Cluster C) ---
                sh "az aks get-credentials --resource-group ${env.REAL_AZURE_RG} --name ${env.REAL_AKS_NAME}"
                
                echo "⏳ Waiting for Azure Application to be deployed by ArgoCD..."
                sh """
                    timeout=300
                    elapsed=0
                    while ! kubectl get svc python-app-service >/dev/null 2>&1; do
                        echo "Waiting for python-app-service on Azure..."
                        sleep 10
                        elapsed=\$((elapsed+10))
                        if [ \$elapsed -ge \$timeout ]; then echo "Timeout waiting for Azure app"; break; fi
                    done
                """
                def azureAppUrl = sh(script: "kubectl get svc python-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || echo 'Not-Found'", returnStdout: true).trim()

                echo """
                ==========================================================
                ✅ DEPLOYMENT SUCCESSFUL
                ==========================================================
                🛠️  INFRASTRUCTURE & MONITORING (Cluster A)
                🚀 ArgoCD UI:      https://${argoUrl}
                📊 Grafana UI:     http://${grafUrl} (User: admin / Pass: admin)
                📈 Prometheus UI:  http://${promUrl}
                
                📱 APPLICATIONS
                ☁️  AWS App (Cluster B):   http://${awsAppUrl}
                ☁️  Azure App (Cluster C): http://${azureAppUrl}
                ==========================================================
                """
            }
        }
    }
}