# ArgoCD Deployment Guide

This document covers the deployment and management of ArgoCD and its resources.

## Prerequisites

- Kubernetes cluster (Docker Desktop, Kind, or cloud provider)
- kubectl configured to access your cluster
- Helm 3+

## ArgoCD Installation

ArgoCD is installed via Helm using the chart in `argocd/argocd-install/`.

```powershell
# Add ArgoCD Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install or upgrade ArgoCD
helm upgrade --install argocd argo/argo-cd `
  --namespace argocd `
  --create-namespace `
  --values c:\code\gitops\argocd\argocd-install\values.yaml
```

## Critical: AppProject Deployment

**AppProject resources must be deployed manually to the cluster.** They are cluster-scoped ArgoCD resources that cannot be auto-discovered by root-app.

### Why?
- AppProjects define the scope and constraints for Applications
- Applications must reference an existing AppProject
- ArgoCD needs the project to exist before it can sync any app that uses it
- Projects are infrastructure resources that change rarely

### How to Deploy AppProjects

After installing ArgoCD, deploy all projects:

```powershell
# Deploy all AppProjects
kubectl apply -f c:\code\gitops\argocd\projects/

# Verify projects are created
kubectl get appproject -n argocd
```

### Available Projects

Located in `argocd/projects/`:

- **default** - Default ArgoCD project (auto-created)
- **monitoring** - For monitoring stack applications (Prometheus, Grafana, etc.)
- **devtest** - For development and testing applications with isolation

## Application Auto-Discovery

Once AppProjects exist, Applications in `argocd/applications/` are automatically discovered and synced by root-app.

### How It Works

1. root-app watches `argocd/applications/` recursively
2. New Application YAML files are automatically detected
3. Files are applied to the cluster within ~30 seconds
4. Applications deploy according to their configuration

### Deploying New Applications

1. Create an Application YAML in `argocd/applications/` (in appropriate subdirectory)
2. Reference an existing AppProject
3. Commit and push to git
4. root-app automatically syncs

Example:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: devtest  # Must reference existing project
  source:
    repoURL: https://github.com/amokscience/gitops
    targetRevision: main
    path: my-app/helm
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Deployment Order

1. **Install ArgoCD** - `helm upgrade --install argocd ...`
2. **Deploy AppProjects** - `kubectl apply -f argocd/projects/`
3. **Deploy root-app** - Apply root-app manifest
4. **Create Applications** - Place in `argocd/applications/` and push to git

## Troubleshooting

### Application shows error: "referencing project X which does not exist"

**Solution:** The AppProject hasn't been deployed. Run:
```powershell
kubectl apply -f c:\code\gitops\argocd\projects/
```

### Applications not syncing

**Verify root-app is running:**
```powershell
kubectl get application root-app -n argocd
kubectl describe application root-app -n argocd
```

**Check root-app logs:**
```powershell
argocd app logs root-app
```

### New applications not appearing

**Check git status:**
```powershell
cd c:\code\gitops
git status
git log --oneline -5
```

**Ensure changes are committed and pushed:**
```powershell
git add argocd/applications/
git commit -m "Add new application"
git push
```

ArgoCD syncs every 3 minutes by default. Check again after a few minutes.

## RBAC and Access Control

See `argocd/keycloak/KEYCLOAK_ARGOCD_SETUP.md` for complete Keycloak SSO integration guide.

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/best_practices/)
- Local deployment scripts in `scripts/`
