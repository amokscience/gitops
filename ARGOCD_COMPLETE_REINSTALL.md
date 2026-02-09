# ArgoCD Complete Reinstall Guide

This guide covers completely removing and reinstalling ArgoCD from scratch, with maximum configuration stored in git (GitOps).

## Prerequisites

- kubectl configured to access cluster
- Helm 3+
- Keycloak running at `https://keycloak.local:8443`
- This gitops repo cloned locally

## Step 1: Complete ArgoCD Removal

```powershell
# Delete ArgoCD namespace (removes everything)
kubectl delete namespace argocd

# Wait for namespace to fully delete
kubectl wait --for=delete namespace/argocd --timeout=60s

# Verify it's gone
kubectl get namespaces | grep argocd
# (should return no results)
```

## Step 2: Create Keycloak Client Secret (MANUAL - NOT IN REPO)

Create the secret in the cluster manually. This is the ONLY truly sensitive information:

```powershell
# Get your Keycloak client secret from Keycloak admin console
# https://keycloak.local:8443/admin → Select realm → Clients → argocd → Credentials

# Create the namespace first
kubectl create namespace argocd

# Create the secret (replace YOUR_SECRET_HERE with actual secret from Keycloak)
kubectl create secret generic argocd-oidc-keycloak `
  --from-literal=client-secret=YOUR_SECRET_HERE `
  -n argocd
```

## Step 3: Install ArgoCD with Helm (MANUAL - Initial Bootstrap)

```powershell
# Add Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD with values from repo
helm install argocd argo/argo-cd `
  --namespace argocd `
  --values c:\code\gitops\argocd\argocd-install\values.yaml
```

Wait for ArgoCD to be ready:
```powershell
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

## Step 4: Deploy root-app (MANUAL - Enables Auto-Discovery)

This is the bootstrapping application that enables all other resources to be auto-discovered:

```powershell
kubectl apply -f c:\code\gitops\argocd\argocd-self-app.yaml
```

Wait for root-app to sync:
```powershell
kubectl wait --for=condition=Synced application/root-app -n argocd --timeout=60s
```

**That's it for manual steps!**

---

## Step 5: Everything Else Auto-Syncs (GitOps)

Once root-app is running, it auto-discovers and deploys everything in the repo:

### What Gets Auto-Deployed (in order):

1. **AppProjects** (`argocd/projects/`)
   - monitoring
   - devtest
   
2. **Infrastructure** (`argocd/applications/infrastructure/`)
   - kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
   - argocd-servicemonitors (Prometheus scraping config)
   - argocd-ingress (if configured)
   - external-secrets-operator (if configured)

3. **Applications** (`argocd/applications/`)
   - counting-dev
   - hello-dev
   - cfb-dev
   - (and any other apps added to the repo)

4. **RBAC & SSO** (`argocd/`)
   - argocd-oidc-configmap.yaml (Keycloak config)
   - argocd-rbac-cm.yaml (Role mappings)

Verify auto-sync is working:
```powershell
# Watch applications sync
kubectl get applications -n argocd -w

# Or check in ArgoCD UI
# https://argocd.local
```

---

## What's in the Repo (Fully GitOps)

✅ **Stored in git and auto-synced:**

- `argocd/argocd-install/values.yaml` - Helm chart values (OIDC config included)
- `argocd/argocd-self-app.yaml` - Root app definition
- `argocd/argocd-oidc-configmap.yaml` - OIDC configuration
- `argocd/argocd-rbac-cm.yaml` - RBAC role mappings
- `argocd/projects/` - All AppProjects
- `argocd/applications/` - All Applications (with auto-discovery)
- `argocd/applications/infrastructure/` - Infrastructure apps
- All service monitors, ingress configs, etc.

❌ **NOT in git (created manually):**

- Keycloak client secret (`argocd-oidc-keycloak` Kubernetes secret)
- Docker credentials (if needed)
- Any other sensitive credentials

---

## Complete Reinstall Summary

```powershell
# 1. Delete everything
kubectl delete namespace argocd

# 2. Create secret (ONLY manual sensitive step)
kubectl create namespace argocd
kubectl create secret generic argocd-oidc-keycloak `
  --from-literal=client-secret=YOUR_SECRET_HERE `
  -n argocd

# 3. Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd `
  --namespace argocd `
  --values c:\code\gitops\argocd\argocd-install\values.yaml

# 4. Wait for ArgoCD server
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 5. Apply root-app (enables auto-discovery)
kubectl apply -f c:\code\gitops\argocd\argocd-self-app.yaml

# 6. Wait for root-app to sync
kubectl wait --for=condition=Synced application/root-app -n argocd --timeout=60s

# Done! Everything else auto-syncs from git
```

---

## Verification

After completion, verify everything is deployed:

```powershell
# Check all applications
kubectl get applications -n argocd

# Check Prometheus stack
kubectl get pods -n monitoring

# Check dev apps
kubectl get pods -n dev

# Check RBAC config
kubectl get configmap argocd-rbac-cm -n argocd

# Check OIDC config
kubectl get configmap -n argocd | grep oidc
```

Access ArgoCD:
```
https://argocd.local
```

You should see a **"LOGIN VIA KEYCLOAK"** button if OIDC is configured correctly.

---

## Key Principles

1. **Only secrets are manual** - Client secret created manually, never in git
2. **Everything else is in git** - Full GitOps for all configuration
3. **Root-app enables auto-discovery** - Once running, all changes in repo auto-sync
4. **No manual Application deployments** - Just push YAML to git, root-app discovers it

This means:
- Disaster recovery is easy (just run these 5 steps)
- All configuration is version-controlled
- No "undocumented manual steps"
- Secrets stay secure (not in repo)
