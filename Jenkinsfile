pipeline {
    agent any

    options {
        // Prevent build from getting stuck indefinitely
        timeout(time: 1, unit: 'HOURS')
        // Prevent multiple builds from running at the same time
        disableConcurrentBuilds()
    }

    environment {
        // --- 1. CREDENTIALS (Must exist in Jenkins) ---
        AWS_CREDS_ID    = 'aws-credentials'     // Type: AWS Credentials or Secret Text
        GIT_CREDS_ID    = 'github-credentials'  // Type: Username with Password (PAT)
        DOCKER_CREDS_ID = 'docker-creds'        // Type: Username with Password

        // --- 2. CONFIGURATION ---
        DOCKER_USER     = "dockervarun432"
        IMAGE_NAME      = "python-webapp-flask"
        DOCKER_TAG      = "${BUILD_NUMBER}"
        REPO_URL        = "github.com/arunprakash432/end-to-end-multicloud-gitops-project.git"
        GIT_BRANCH      = "main"

        // --- 3. CLUSTERS (Must match Terraform main.tf names) ---
        AWS_REGION      = "ap-south-1"
        CLUSTER_A_NAME  = "eks-cluster-monitoring-1" // Management Cluster
        CLUSTER_B_NAME  = "aws-app-eks-2"            // Workload Cluster (AWS)
    }

    stages {
        stage('Checkout & Setup') {
            steps {
                checkout scm
            }
        }

        stage('Prevent GitOps Loop') {
            steps {
                script {
                    // Stop the build if the commit was made by our own Jenkins Bot
                    def author = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
                    if (author.contains("Jenkins Bot")) {
                        error("🛑 Aborting: Commit by Jenkins Bot. Stopping GitOps loop.")
                    }
                }
            }
        }

        stage('Provision Infrastructure') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDS_ID]]) {
                    dir('infrastructure') {
                        sh 'terraform init'
                        sh 'terraform validate'
                        sh 'terraform apply -auto-approve'
                        
                        // --- CAPTURE OUTPUTS (Critical Step) ---
                        // These match the names we fixed in outputs.tf
                        script {
                            env.CLUSTER_B_IP   = sh(script: "terraform output -raw cluster_b_public_ip", returnStdout: true).trim()
                            env.CLUSTER_C_DNS  = sh(script: "terraform output -raw cluster_c_loadbalancer_dns", returnStdout: true).trim()
                            env.AZURE_RG       = sh(script: "terraform output -raw aks_resource_group", returnStdout: true).trim()
                            env.AZURE_AKS_NAME = sh(script: "terraform output -raw aks_cluster_name", returnStdout: true).trim()
                            
                            echo "✅ Captured Infrastructure Details:"
                            echo "   AWS App IP: ${env.CLUSTER_B_IP}"
                            echo "   Azure DNS:  ${env.CLUSTER_C_DNS}"
                        }
                    }
                }
            }
        }

        stage('Build & Push Docker') {
            steps {
                withCredentials([usernamePassword(credentialsId: env.DOCKER_CREDS_ID, usernameVariable: 'DUSER', passwordVariable: 'DPASS')]) {
                    sh """
                        echo "$DPASS" | docker login -u "$DUSER" --password-stdin
                        
                        # Build with unique tag
                        docker build -t ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ./app
                        docker push ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG}
                        
                        # Update latest tag
                        docker tag ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ${DOCKER_USER}/${IMAGE_NAME}:latest
                        docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('GitOps: Update Code') {
            steps {
                script {
                    // 1. Update Application Tag in Helm
                    sh "sed -i 's/tag: .*/tag: \"${DOCKER_TAG}\"/' k8s/helm-charts/python-app/values.yaml"

                    // 2. Update Monitoring IPs in Prometheus Config
                    dir('k8s/monitoring') {
                        // Replace Placeholders with Real IPs from Terraform
                        sh "sed -i \"s|<CLUSTER-B-IP>|${env.CLUSTER_B_IP}|g\" central-prometheus.yaml"
                        sh "sed -i \"s|<CLUSTER-C-IP>|${env.CLUSTER_C_DNS}|g\" central-prometheus.yaml"
                        
                        // Failsafe: If placeholders were already overwritten, update the existing values
                        sh "sed -i \"s|targets: \\['.*:9100'\\]|targets: \\['${env.CLUSTER_B_IP}:9100'\\]|g\" central-prometheus.yaml"
                        sh "sed -i \"s|targets: \\['.*:9100'\\]|targets: \\['${env.CLUSTER_C_DNS}:9100'\\]|g\" central-prometheus.yaml"
                    }
                }

                // 3. Commit & Push to GitHub
                withCredentials([usernamePassword(credentialsId: env.GIT_CREDS_ID, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh """
                        git config user.name "Jenkins Bot"
                        git config user.email "jenkins@ci.local"
                        git add .
                        
                        # Only commit if something changed
                        if ! git diff-index --quiet HEAD; then
                             git commit -m "GitOps: Update App to ${DOCKER_TAG} & Monitor IPs [skip ci]"
                             git push https://${GIT_USER}:${GIT_PASS}@${REPO_URL} ${GIT_BRANCH}
                        else
                             echo "No changes to commit."
                        fi
                    """
                }
            }
        }

        stage('Deploy Agents & Register Clusters') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDS_ID]]) {
                    script {
                        // --- 1. AWS Workload (Cluster B) ---
                        sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                        sh "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true"
                        sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                        
                        // Save context name for later
                        def ctxB = sh(script: "kubectl config current-context", returnStdout: true).trim()

                        // --- 2. Azure Workload (Cluster C) ---
                        sh "az aks get-credentials --resource-group ${env.AZURE_RG} --name ${env.AZURE_AKS_NAME} --overwrite-existing"
                        sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
                        def ctxC = sh(script: "kubectl config current-context", returnStdout: true).trim()

                        // --- 3. Management Cluster (Cluster A) ---
                        sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                        
                        // Install ArgoCD
                        sh "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -"
                        sh "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
                        
                        // Wait for ArgoCD server
                        sh "kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true"

                        // Register Clusters to ArgoCD (Requires 'argocd' CLI installed on agent)
                        // If 'argocd' CLI is missing, install it or comment these lines out
                        sh "argocd cluster add ${ctxB} --name aws-cluster-b --yes --upsert || echo '⚠️ ArgoCD CLI issue or cluster already added'"
                        sh "argocd cluster add ${ctxC} --name azure-cluster-c --yes --upsert || echo '⚠️ ArgoCD CLI issue or cluster already added'"

                        // Trigger Deployment
                        sh "kubectl apply -f k8s/argocd-apps/"
                    }
                }
            }
        }
    }

    post {
        always { cleanWs() }
        success { 
            script {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDS_ID]]) {
                    echo "🔍 Generating Deployment Report..."

                    // Get Cluster A URLs
                    sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                    def argoUrl = sh(script: "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                    
                    // Note: If Grafana/Prometheus are not LoadBalancers, these might be empty.
                    // Assuming you deployed them as LoadBalancers in 'monitoring' namespace:
                    def grafUrl = sh(script: "kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()
                    def promUrl = sh(script: "kubectl get svc prometheus-server -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()

                    // Get Cluster B App URL
                    sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                    def awsAppUrl = sh(script: "kubectl get svc python-webapp-flask -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()

                    // Get Cluster C App URL
                    sh "az aks get-credentials --resource-group ${env.AZURE_RG} --name ${env.AZURE_AKS_NAME} --overwrite-existing"
                    def azureAppUrl = sh(script: "kubectl get svc python-webapp-flask -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || echo 'Pending'", returnStdout: true).trim()

                    echo """
                    ==========================================================
                    ✅ DEPLOYMENT SUCCESSFUL
                    ==========================================================
                    🚀 ArgoCD UI:      https://${argoUrl}
                    📊 Grafana UI:     http://${grafUrl} (admin/admin)
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
}