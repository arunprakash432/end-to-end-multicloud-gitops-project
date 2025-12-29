pipeline {
    agent any

    options {
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }

    environment {
        // --- CREDENTIALS ---
        // Ensure these IDs exist in your Jenkins Credentials Dashboard
        AWS_CREDS_ID    = 'aws-credentials'     // Type: AWS Credentials (or Username/Password)
        GIT_CREDS_ID    = 'github-credentials'  // Type: Username with Password
        DOCKER_CREDS_ID = 'docker-creds'        // Type: Username with Password

        // --- CONFIGURATION ---
        DOCKER_USER     = "dockervarun432"
        IMAGE_NAME      = "python-webapp-flask"
        DOCKER_TAG      = "${BUILD_NUMBER}"
        REPO_URL        = "github.com/arunprakash432/end-to-end-multicloud-gitops-project.git"
        GIT_BRANCH      = "main"

        // --- CLUSTERS ---
        AWS_REGION      = "ap-south-1"
        CLUSTER_A_NAME  = "eks-cluster-monitoring-1"
        CLUSTER_B_NAME  = "aws-app-eks-2"
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
                    def author = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
                    if (author.contains("Jenkins Bot")) {
                        error("🛑 Aborting: Commit by Jenkins Bot. Stopping GitOps loop.")
                    }
                }
            }
        }

        stage('Provision Infrastructure') {
            steps {
                // FIXED: Replaced 'AmazonWebServicesCredentialsBinding' with 'usernamePassword'
                // This maps AccessKey -> Username and SecretKey -> Password
                withCredentials([usernamePassword(credentialsId: env.AWS_CREDS_ID, usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    dir('infrastructure') {
                        sh 'terraform init'
                        sh 'terraform validate'
                        sh 'terraform apply -auto-approve'
                        
                        // Capture Outputs
                        script {
                            env.CLUSTER_B_IP   = sh(script: "terraform output -raw cluster_b_public_ip", returnStdout: true).trim()
                            env.CLUSTER_C_DNS  = sh(script: "terraform output -raw cluster_c_loadbalancer_dns", returnStdout: true).trim()
                            env.AZURE_RG       = sh(script: "terraform output -raw aks_resource_group", returnStdout: true).trim()
                            env.AZURE_AKS_NAME = sh(script: "terraform output -raw aks_cluster_name", returnStdout: true).trim()
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
                        docker build -t ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ./app
                        docker push ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG}
                        docker tag ${DOCKER_USER}/${IMAGE_NAME}:${DOCKER_TAG} ${DOCKER_USER}/${IMAGE_NAME}:latest
                        docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('GitOps: Update Code') {
            steps {
                script {
                    // 1. Update Application Tag
                    sh "sed -i 's/tag: .*/tag: \"${DOCKER_TAG}\"/' k8s/helm-charts/python-app/values.yaml"

                    // 2. Update Monitoring IPs
                    dir('k8s/monitoring') {
                        sh "sed -i \"s|<CLUSTER-B-IP>|${env.CLUSTER_B_IP}|g\" central-prometheus.yaml"
                        sh "sed -i \"s|<CLUSTER-C-IP>|${env.CLUSTER_C_DNS}|g\" central-prometheus.yaml"
                        // Regex fallback
                        sh "sed -i \"s|targets: \\['.*:9100'\\]|targets: \\['${env.CLUSTER_B_IP}:9100'\\]|g\" central-prometheus.yaml"
                        sh "sed -i \"s|targets: \\['.*:9100'\\]|targets: \\['${env.CLUSTER_C_DNS}:9100'\\]|g\" central-prometheus.yaml"
                    }
                }

                withCredentials([usernamePassword(credentialsId: env.GIT_CREDS_ID, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh """
                        git config user.name "Jenkins Bot"
                        git config user.email "jenkins@ci.local"
                        git add .
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
                // FIXED: Using usernamePassword for AWS here as well
                withCredentials([usernamePassword(credentialsId: env.AWS_CREDS_ID, usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    script {
                        // --- 1. AWS Workload (Cluster B) ---
                        sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                        sh "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true"
                        sh "helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter -f k8s/monitoring/node-exporter-values.yaml"
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
                        sh "kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true"

                        // Register Clusters
                        sh "argocd cluster add ${ctxB} --name aws-cluster-b --yes --upsert || echo 'Cluster registration skipped'"
                        sh "argocd cluster add ${ctxC} --name azure-cluster-c --yes --upsert || echo 'Cluster registration skipped'"

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
                withCredentials([usernamePassword(credentialsId: env.AWS_CREDS_ID, usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    echo "🔍 Generating Report..."
                    sh "aws eks update-kubeconfig --name ${CLUSTER_A_NAME} --region ${AWS_REGION}"
                    def argoUrl = sh(script: "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                    
                    def grafUrl = sh(script: "kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()
                    def promUrl = sh(script: "kubectl get svc prometheus-server -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()

                    sh "aws eks update-kubeconfig --name ${CLUSTER_B_NAME} --region ${AWS_REGION}"
                    def awsAppUrl = sh(script: "kubectl get svc python-webapp-flask -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo 'Pending'", returnStdout: true).trim()

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