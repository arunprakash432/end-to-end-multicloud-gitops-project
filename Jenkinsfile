pipeline {
    agent any

    environment {
        // --- Configuration ---
        DOCKER_REGISTRY = "docker.io"
        DOCKER_USER     = "dockervarun432" 
        IMAGE_NAME      = "python-webapp-flask"
        DOCKER_TAG      = "${BUILD_NUMBER}"
        GIT_REPO_URL    = "https://github.com/arunprakash432/end-to-end-multicloud-gitops-project.git"
        GIT_BRANCH      = "main"
        
        // --- Cloud Config ---
        AWS_REGION      = "ap-south-1"
        AZURE_RG        = "azure-app-vnet-1-rg" 
        AKS_CLUSTER     = "azure-app-aks-1"
        
        // Updated as per your confirmation
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
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                        
                        env.CLUSTER_B_URL = sh(script: "terraform output -raw eks2_endpoint", returnStdout: true).trim()
                        env.CLUSTER_C_URL = sh(script: "terraform output -raw aks_endpoint", returnStdout: true).trim()
                    }
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                script {
                    // We use withCredentials to get the username/password and run manual docker commands
                    // This is more reliable than the docker.build plugin for scope errors
                    withCredentials([usernamePassword(credentialsId: 'docker-creds', usernameVariable: 'DUSER', passwordVariable: 'DPASS')]) {
                        
                        sh "docker login -u ${DUSER} -p ${DPASS}"
                        
                        // Build from the /app directory
                        sh "docker build -t ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ./app"
                        sh "docker tag ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ${DOCKER_USER}/${IMAGE_NAME}:latest"
                        
                        // Push to Docker Hub
                        sh "docker push ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG}"
                        sh "docker push ${DOCKER_USER}/${IMAGE_NAME}:latest"
                    }
                }
            }
        }

        stage('GitOps: Update Manifests & Registry') {
            steps {
                script {
                    // 1. Update files locally
                    sh "sed -i 's/tag: .*/tag: \"${DOCKER_TAG}\"/' k8s/helm-charts/python-app/values.yaml"
                    sh "sed -i 's|server:.*|server: \"${env.CLUSTER_B_URL}\"|' k8s/argocd-apps/app-cluster-b.yaml"
                    sh "sed -i 's|server:.*|server: \"${env.CLUSTER_C_URL}\"|' k8s/argocd-apps/app-cluster-c.yaml"

                    // 2. Commit and Push with "Checkout" fix
                    withCredentials([usernamePassword(credentialsId: 'git-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                        sh """
                            # This is the FIX: Ensure we are on the main branch
                            git checkout ${GIT_BRANCH} || git checkout -b ${GIT_BRANCH}
                            
                            git config user.email "prakasharun484@gmail.com"
                            git config user.name "arunprakash432"
                            
                            git add .
                            # The || true prevents failure if there are no changes to commit
                            git commit -m "CI: Build ${DOCKER_TAG} - Update tag and endpoints" || true
                            
                            # Push to the remote
                            git push https://${GIT_USER}:${GIT_PASS}@${GIT_REPO_URL.replace('https://', '')} ${GIT_BRANCH}
                        """
                    }
                }
            }
        }

        stage('ArgoCD: Register & Sync') {
            steps {
                script {
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_A_NAME} --region ${env.AWS_REGION}"
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_B_NAME} --region ${env.AWS_REGION}"
                    sh "az aks get-credentials --resource-group ${env.AZURE_RG} --name ${env.AKS_CLUSTER} --overwrite-existing"
                    
                    sh "kubectl config use-context \$(kubectl config contexts -o name | grep ${env.CLUSTER_A_NAME})"
                    
                    sh "argocd login --core"
                    sh "argocd cluster add \$(kubectl config contexts -o name | grep ${env.CLUSTER_B_NAME}) --name cluster-b --yes"
                    sh "argocd cluster add \$(kubectl config contexts -o name | grep ${env.AKS_CLUSTER}) --name cluster-c --yes"

                    sh "kubectl apply -f k8s/argocd-apps/"
                }
            }
        }

        stage('Monitoring: Federation Setup') {
            steps {
                script {
                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_B_NAME} --region ${env.AWS_REGION}"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    def B_DNS = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()

                    sh "az aks get-credentials --resource-group ${env.AZURE_RG} --name ${env.AKS_CLUSTER}"
                    sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                    def C_IP = sh(script: "kubectl get svc node-exporter-prometheus-node-exporter -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()

                    sh "aws eks update-kubeconfig --name ${env.CLUSTER_A_NAME} --region ${env.AWS_REGION}"
                    
                    dir('k8s/monitoring') {
                        sh "sed -i 's/<CLUSTER-B-IP>/${B_DNS}/g' central-prometheus.yaml"
                        sh "sed -i 's/<CLUSTER-C-IP>/${C_IP}/g' central-prometheus.yaml"
                        sh "helm upgrade --install prometheus prometheus-community/prometheus -f central-prometheus.yaml"
                    }
                }
            }
        }
    }

    post {
        always { cleanWs() }
        success { echo "Multi-cloud infrastructure and application successfully deployed!" }
    }
}