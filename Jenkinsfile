pipeline {
    agent any

    environment {
        // --- Configuration ---
        DOCKER_REGISTRY = "docker.io"
        DOCKER_USER     = "arunprakash432" 
        IMAGE_NAME      = "python-webapp"
        DOCKER_TAG      = "${BUILD_NUMBER}"
        GIT_REPO_URL    = "https://github.com/arunprakash432/end-to-end-multicloud-gitops-project.git"
        GIT_BRANCH      = "main"
        
        // --- Cloud Config ---
        AWS_REGION      = "ap-south-1"
        AZURE_RG        = "azure-app-vnet-1-rg" 
        AKS_CLUSTER     = "azure-app-aks-1"
        
        // Cluster Names from your main.tf
        CLUSTER_A_NAME  = "eks-cluster-monitoring-1"
        CLUSTER_B_NAME  = "aws-app-eks-2" 
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Provision Infrastructure') {
            steps {
                script {
                    dir('infrastructure') {
                        // Uses pre-configured AWS/Azure CLI credentials on Jenkins machine
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                        
                        // CAPTURE DYNAMIC ENDPOINTS from your outputs.tf
                        // -raw handles the 'sensitive=true' for AKS
                        env.CLUSTER_B_URL = sh(script: "terraform output -raw eks2_endpoint", returnStdout: true).trim()
                        env.CLUSTER_C_URL = sh(script: "terraform output -raw aks_endpoint", returnStdout: true).trim()
                    }
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-hub-creds') {
                        def appImage = docker.build("${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG}", "./app")
                        appImage.push()
                        appImage.push("latest")
                    }
                }
            }
        }

        stage('GitOps: Update Manifests & Registry') {
            steps {
                script {
                    // 1. Update Image Tag in Helm values
                    sh "sed -i 's/tag: .*/tag: \"${DOCKER_TAG}\"/' k8s/helm-charts/python-app/values.yaml"
                    
                    // 2. Inject Dynamic Cluster API URLs into ArgoCD Application YAMLs
                    // Using | as sed delimiter because URLs contain /
                    sh "sed -i 's|server:.*|server: \"${env.CLUSTER_B_URL}\"|' k8s/argocd-apps/app-cluster-b.yaml"
                    sh "sed -i 's|server:.*|server: \"${env.CLUSTER_C_URL}\"|' k8s/argocd-apps/app-cluster-c.yaml"

                    // 3. Commit and Push back to Git
                    withCredentials([usernamePassword(credentialsId: 'git-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                        sh """
                            git config user.email "jenkins@bot.com"
                            git config user.name "Jenkins Bot"
                            git add .
                            git commit -m "Automated update: Tag ${DOCKER_TAG} and Cluster Endpoints" || echo "No changes"
                            git push https://${GIT_USER}:${GIT_PASS}@${GIT_REPO_URL.replace('https://', '')} ${GIT_BRANCH}
                        """
                    }
                }
            }
        }

        stage('ArgoCD: Register & Sync') {
            steps {
                script {
                    // Get Kubeconfigs for all clusters to register them in ArgoCD
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_A_NAME} --region ${env.AWS_REGION}"
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_B_NAME} --region ${env.AWS_REGION}"
                    sh "az aks get-credentials --resource-group ${env.AZURE_RG} --name ${env.AKS_CLUSTER} --overwrite-existing"
                    
                    // Switch back to Cluster A (ArgoCD Host)
                    sh "kubectl config use-context \$(kubectl config contexts -o name | grep ${env.CLUSTER_A_NAME})"
                    
                    // Register Clusters B and C into ArgoCD
                    sh "argocd login --core"
                    sh "argocd cluster add \$(kubectl config contexts -o name | grep ${env.CLUSTER_B_NAME}) --name cluster-b --yes"
                    sh "argocd cluster add \$(kubectl config contexts -o name | grep ${env.AKS_CLUSTER}) --name cluster-c --yes"

                    // Deploy the ArgoCD App Manifests
                    sh "kubectl apply -f k8s/argocd-apps/"
                }
            }
        }

        stage('Monitoring: Federation Setup') {
            steps {
                script {
                    // 1. Setup Node Exporter on Cluster B (AWS)
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_B_NAME} --region ${env.AWS_REGION}"
                    sh "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
                    sh "helm repo update"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    
                    // Capture AWS LoadBalancer Hostname (DNS)
                    def B_DNS = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                    // 2. Setup Node Exporter on Cluster C (Azure)
                    sh "az aks get-credentials --resource-group ${env.AZURE_RG} --name ${env.AKS_CLUSTER}"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    
                    // Capture Azure LoadBalancer IP
                    def C_IP = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()

                    // 3. Update Central Prometheus on Cluster A
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_A_NAME} --region ${env.AWS_REGION}"
                    
                    dir('k8s/monitoring') {
                        // Replace placeholders with real LB addresses
                        sh "sed -i 's/<CLUSTER-B-IP>/${B_DNS}/g' central-prometheus.yaml"
                        sh "sed -i 's/<CLUSTER-C-IP>/${C_IP}/g' central-prometheus.yaml"
                        
                        sh "helm upgrade --install prometheus prometheus-community/prometheus -f central-prometheus.yaml"
                        sh "helm upgrade --install grafana prometheus-community/grafana"
                    }
                }
            }
        }
    }

    post {
        always { cleanWs() }
        success { echo "Multi-cloud deployment and monitoring setup successful!" }
    }
}