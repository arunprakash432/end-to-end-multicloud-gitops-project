#!/bin/bash

# Exit script on any error
set -e

echo "--- 1. Navigating to Infrastructure ---"
cd infrastructure

# --- 2. Extract Outputs from Terraform ---
# Note: Ensure your infrastructure/outputs.tf actually has these output names.
# If your output names are different, update them here.
CLUSTER_B_IP=$(terraform output -raw cluster_b_public_ip)
CLUSTER_C_DNS=$(terraform output -raw cluster_c_loadbalancer_dns)

echo "Retrieved Cluster B IP: $CLUSTER_B_IP"
echo "Retrieved Cluster C DNS: $CLUSTER_C_DNS"

# Go back to root
cd ..

# --- 3. Inject IPs into Prometheus Config ---
echo "--- Updating central-prometheus.yaml ---"

# We use sed to find the placeholder and replace it with the variable
# generic syntax: sed -i "s|SEARCH_TEXT|REPLACE_TEXT|g" filename

# Update Cluster B
sed -i "s|<CLUSTER-B-IP>|$CLUSTER_B_IP|g" k8s/monitoring/central-prometheus.yaml

# Update Cluster C
sed -i "s|<CLUSTER-C-IP>|$CLUSTER_C_DNS|g" k8s/monitoring/central-prometheus.yaml

echo "Yaml file updated successfully."

# --- 4. GitOps: Push changes to Repo ---
echo "--- Pushing changes to Git ---"

# Configure git if running in a CI environment (like Jenkins)
# git config user.email "jenkins-bot@example.com"
# git config user.name "Jenkins Bot"

git add k8s/monitoring/central-prometheus.yaml
git commit -m "Auto-fix: Update Prometheus targets from Terraform outputs [skip ci]"
git push origin main

echo "--- Done! ArgoCD will now detect the changes. ---"