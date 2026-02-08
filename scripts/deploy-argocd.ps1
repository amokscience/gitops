# ============================================================================
# ArgoCD Self-Managed GitOps Deployment Script
# ============================================================================
# This script deploys ArgoCD in a self-managing configuration where ArgoCD
# manages its own lifecycle and all applications through GitOps.
#
# PREREQUISITES:
# 1. Kubernetes cluster running (Docker Desktop, k3s, etc.)
# 2. kubectl configured and connected
# 3. Git repository cloned locally
# 4. TLS certificates generated (see CERTIFICATE SETUP below)
# 5. AWS credentials for External Secrets Operator (see AWS SETUP below)
# ============================================================================

Write-Host "=== ArgoCD Self-Managed Deployment ===" -ForegroundColor Cyan

# ============================================================================
# CERTIFICATE SETUP
# ============================================================================
# Generate TLS certificate for ArgoCD ingress using mkcert:
#   mkcert -install
#   mkcert argocd.local
# This creates: argocd.local.pem (cert) and argocd.local-key.pem (key)
#
# UPDATE THESE PATHS to point to your certificate files:
# ============================================================================
$CERT_FILE = "c:\code\argocd.crt"      # ⚠️ UPDATE THIS PATH
$KEY_FILE = "c:\code\argocd.key"       # ⚠️ UPDATE THIS PATH

if (-not (Test-Path $CERT_FILE) -or -not (Test-Path $KEY_FILE)) {
    Write-Host "❌ Certificate files not found!" -ForegroundColor Red
    Write-Host "   Expected: $CERT_FILE and $KEY_FILE" -ForegroundColor Yellow
    Write-Host "   Generate with: mkcert argocd.local" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# AWS CREDENTIALS SETUP
# ============================================================================
# External Secrets Operator needs AWS credentials to fetch secrets from
# AWS Secrets Manager. Create an IAM user with SecretsManagerReadWrite policy.
#
# UPDATE THESE VALUES with your AWS credentials:
# ============================================================================
$AWS_ACCESS_KEY_ID = "YOUR_AWS_ACCESS_KEY_ID"          # ⚠️ UPDATE THIS
$AWS_SECRET_ACCESS_KEY = "YOUR_AWS_SECRET_ACCESS_KEY"  # ⚠️ UPDATE THIS

if ($AWS_ACCESS_KEY_ID -eq "YOUR_AWS_ACCESS_KEY_ID") {
    Write-Host "❌ AWS credentials not configured!" -ForegroundColor Red
    Write-Host "   Update AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in this script" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# HOSTS FILE SETUP
# ============================================================================
# Add these entries to your hosts file (requires admin):
#   127.0.0.1 argocd.local
#   127.0.0.1 dev.cfb.local
#   127.0.0.1 dev.hello.local
#   127.0.0.1 grafana.local
#
# Windows: C:\Windows\System32\drivers\etc\hosts
# Linux/Mac: /etc/hosts
# ============================================================================

Write-Host "`n⚠️  Verify hosts file contains required entries before continuing" -ForegroundColor Yellow
Write-Host "Press any key to continue or Ctrl+C to abort..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# ============================================================================
# STEP 1: Clean up existing installation
# ============================================================================
Write-Host "`n1. Cleaning up existing namespaces..." -ForegroundColor Yellow
kubectl delete namespace argocd --ignore-not-found=true
kubectl delete namespace dev --ignore-not-found=true
kubectl delete namespace external-secrets --ignore-not-found=true
kubectl delete namespace ingress-nginx --ignore-not-found=true
kubectl delete namespace monitoring --ignore-not-found=true

Write-Host "   Waiting for namespaces to terminate..."
Start-Sleep -Seconds 10

# ============================================================================
# STEP 2: Install ArgoCD
# ============================================================================
Write-Host "`n2. Installing ArgoCD..." -ForegroundColor Yellow
kubectl create namespace argocd
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host "   Waiting for ArgoCD to be ready (may take 2-3 minutes)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# ============================================================================
# STEP 3: Configure TLS certificate
# ============================================================================
Write-Host "`n3. Creating TLS secret for ingress..." -ForegroundColor Yellow
kubectl create secret tls argocd-tls --cert=$CERT_FILE --key=$KEY_FILE -n argocd

# ============================================================================
# STEP 4: Bootstrap self-management
# ============================================================================
Write-Host "`n4. Bootstrapping GitOps (ArgoCD manages itself)..." -ForegroundColor Yellow
kubectl apply -f argocd/argocd-self-app.yaml
kubectl apply -f argocd/applications/root-app.yaml

Write-Host "   Waiting for ArgoCD to create application namespaces..."
Start-Sleep -Seconds 30

# ============================================================================
# STEP 5: Create namespaces (if not created by ArgoCD yet)
# ============================================================================
Write-Host "`n5. Ensuring required namespaces exist..." -ForegroundColor Yellow
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# ============================================================================
# STEP 6: Configure AWS credentials for External Secrets Operator
# ============================================================================
Write-Host "`n6. Creating AWS credentials secrets..." -ForegroundColor Yellow
kubectl create secret generic aws-credentials `
    --from-literal=accessKeyID=$AWS_ACCESS_KEY_ID `
    --from-literal=secretAccessKey=$AWS_SECRET_ACCESS_KEY `
    -n external-secrets `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic aws-credentials `
    --from-literal=accessKeyID=$AWS_ACCESS_KEY_ID `
    --from-literal=secretAccessKey=$AWS_SECRET_ACCESS_KEY `
    -n dev `
    --dry-run=client -o yaml | kubectl apply -f -

# ============================================================================
# STEP 7: Wait for deployments to complete
# ============================================================================
Write-Host "`n7. Waiting for all applications to deploy..." -ForegroundColor Yellow

Write-Host "   - Nginx Ingress Controller..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Ready" -ForegroundColor Green }

Write-Host "   - External Secrets Operator..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Ready" -ForegroundColor Green }

Write-Host "   - CFB Application..."
kubectl wait --for=condition=ready pod -l app=cfb-dev -n dev --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Ready" -ForegroundColor Green }

Write-Host "   - Hello Application..."
kubectl wait --for=condition=ready pod -l app=hello-dev -n dev --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Ready" -ForegroundColor Green }

# ============================================================================
# STEP 8: Retrieve admin credentials
# ============================================================================
Write-Host "`n8. Retrieving ArgoCD admin credentials..." -ForegroundColor Yellow
$ArgoPassword = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))
}

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "✓ ArgoCD Self-Managed Deployment Complete!" -ForegroundColor Green
Write-Host "="*70 -ForegroundColor Cyan

Write-Host "`nArgoCD Credentials:" -ForegroundColor Yellow
Write-Host "  Username: admin"
Write-Host "  Password: $ArgoPassword"
$ArgoPassword | clip
Write-Host "  (Password copied to clipboard)" -ForegroundColor Gray

Write-Host "`nAccess URLs:" -ForegroundColor Yellow
Write-Host "  ArgoCD UI:     https://argocd.local"
Write-Host "  CFB App:       http://dev.cfb.local"
Write-Host "  Hello App:     http://dev.hello.local"
Write-Host "  Grafana:       http://grafana.local (admin/admin)"

Write-Host "`nVerify Status:" -ForegroundColor Yellow
Write-Host "  kubectl get applications -n argocd"
Write-Host "  kubectl get pods -n dev"
Write-Host "  kubectl get pods -n monitoring"

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Login to ArgoCD at https://argocd.local"
Write-Host "  2. Verify all applications are Synced and Healthy"
Write-Host "  3. Check Grafana for ArgoCD monitoring dashboards"
Write-Host "  4. Update admin password: argocd account update-password"

Write-Host "`n" + "="*70 -ForegroundColor Cyan
