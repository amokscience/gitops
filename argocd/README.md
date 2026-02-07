# ArgoCD Setup for CFB GitOps

## Prerequisites

1. **Install ArgoCD:**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

2. **Install Helm and Kustomize:**
   - Both must be available in the ArgoCD container or install via init containers
   - Or use a custom ArgoCD image with these tools pre-installed

## Setup Steps

### 1. Register Your Git Repository
```bash
argocd repo add https://github.com/amokscience/gitops \
  --username <your-username> \
  --password <your-github-token>
```

### 2. Install the Helm-Kustomize Plugin
```bash
kubectl apply -f argocd/cmp-plugin-config.yaml
```

Note: This requires configuring ArgoCD to use Config Management Plugins. You may need to update the ArgoCD server deployment to mount the plugin ConfigMap.

### 3. Create the Applications
```bash
kubectl apply -f argocd/cfb-dev-app.yaml
kubectl apply -f argocd/cfb-qa-app.yaml
kubectl apply -f argocd/cfb-staging-app.yaml
kubectl apply -f argocd/cfb-prod-app.yaml
```

### 4. Access ArgoCD UI
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
Navigate to https://localhost:8080

## Environment-Specific Configuration

Each Application is configured to:
- **Source**: Point to the GitOps repo with an overlay path
- **Destination**: Deploy to the corresponding namespace (dev, qa, staging, prod)
- **Sync Policy**: Auto-sync with pruning enabled (deletes resources removed from Git)
- **Self Heal**: Automatically fixes drift from the desired state

## Manual Deployment (Without ArgoCD)

If you want to deploy without ArgoCD:
```powershell
# Deploy to dev
.\deploy.ps1 dev -Apply

# Deploy to prod
.\deploy.ps1 prod -Apply
```

## Updating Secrets

**IMPORTANT:** The API keys in the Kustomize overlays are placeholders:
```yaml
- cfbd-api-key=your_dev_api_key_here
```

For production, use one of these approaches:
1. **Sealed Secrets**: Encrypt secrets in Git
2. **External Secrets**: Reference secrets from external store (Vault, AWS Secrets Manager)
3. **Kustomize patches at deploy time**: Pass actual secrets when deploying

## Sync Policies Explained

- **Automated**: ArgoCD automatically syncs when Git changes
- **Prune**: Deletes resources from cluster if removed from Git
- **SelfHeal**: Corrects drift if someone changes cluster directly
- **Retry**: Retries failed syncs with backoff
