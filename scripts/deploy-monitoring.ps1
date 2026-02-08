# ============================================================================
# Prometheus/Grafana Monitoring Stack Deployment Script
# ============================================================================
# This script deploys a comprehensive monitoring solution for ArgoCD including:
# - Prometheus (metrics collection and storage)
# - Grafana (dashboards and visualization)
# - Alertmanager (alert routing and notification)
# - Pre-configured ArgoCD dashboards and alerts
#
# PREREQUISITES:
# 1. ArgoCD already installed and running
# 2. root-app deployed and syncing
# 3. Monitoring files committed to git and pushed
# ============================================================================

Write-Host "=== ArgoCD Monitoring Stack Deployment ===" -ForegroundColor Cyan

# ============================================================================
# STEP 1: Verify ArgoCD is running
# ============================================================================
Write-Host "`n1. Verifying ArgoCD installation..." -ForegroundColor Yellow

$argocdRunning = kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' 2>$null
if ($argocdRunning -ne "Running") {
    Write-Host "❌ ArgoCD is not running!" -ForegroundColor Red
    Write-Host "   Deploy ArgoCD first: .\scripts\deploy-argocd.ps1" -ForegroundColor Yellow
    exit 1
}
Write-Host "   ✓ ArgoCD is running" -ForegroundColor Green

# ============================================================================
# STEP 2: Install Prometheus Operator CRDs
# ============================================================================
Write-Host "`n2. Installing Prometheus Operator Custom Resource Definitions..." -ForegroundColor Yellow
Write-Host "   (This is required for Prometheus and Alertmanager resources)" -ForegroundColor Gray

$helmRepoAdded = helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>&1
helm repo update

Write-Host "   ✓ Helm repositories updated" -ForegroundColor Green

Write-Host "   Installing CRDs using server-side apply..." -ForegroundColor Gray
helm template kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 65.1.1 --namespace monitoring | kubectl apply --server-side -f - 2>&1 | Out-Null

$crdCheck = kubectl get crd prometheuses.monitoring.coreos.com 2>$null
if ($crdCheck) {
    Write-Host "   ✓ Prometheus Operator CRDs installed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to install CRDs!" -ForegroundColor Red
    Write-Host "   Verify helm is installed and accessible" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 3: Apply monitoring AppProject
# ============================================================================
Write-Host "`n3. Creating monitoring namespace..." -ForegroundColor Yellow
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
Write-Host "   ✓ Monitoring namespace created" -ForegroundColor Green

Write-Host "`n4. Creating monitoring AppProject..." -ForegroundColor Yellow

if (Test-Path "argocd/projects/monitoring-project.yaml") {
    kubectl apply -f argocd/projects/monitoring-project.yaml
    Write-Host "   ✓ Monitoring project created" -ForegroundColor Green
} else {
    Write-Host "❌ monitoring-project.yaml not found!" -ForegroundColor Red
    Write-Host "   Expected: argocd/projects/monitoring-project.yaml" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 4: Verify monitoring apps exist in git
# ============================================================================
Write-Host "`n5. Verifying monitoring application manifests..." -ForegroundColor Yellow
# ============================================================================
Write-Host "`n4. Verifying monitoring application manifests..." -ForegroundColor Yellow

$requiredFiles = @(
    "argocd/applications/infrastructure/kube-prometheus-stack-app.yaml",
    "argocd/applications/infrastructure/argocd-alerts-app.yaml",
    "monitoring/prometheus/argocd-alerts.yaml"
)

$allFilesExist = $true
foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "   ✓ $file" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Missing: $file" -ForegroundColor Red
        $allFilesExist = $false
    }
}

if (-not $allFilesExist) {
    Write-Host "`n❌ Missing required files. Ensure monitoring config is committed to git." -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 5: Wait for ArgoCD to sync monitoring apps
# ============================================================================
Write-Host "`n6. Waiting for ArgoCD to discover monitoring applications..." -ForegroundColor Yellow
Write-Host "   (This may take 1-2 minutes for ArgoCD to sync from git)" -ForegroundColor Gray

$maxWait = 120
$elapsed = 0
$found = $false

while ($elapsed -lt $maxWait -and -not $found) {
    $prometheusApp = kubectl get application kube-prometheus-stack -n argocd 2>$null
    if ($prometheusApp) {
        $found = $true
        Write-Host "   ✓ Monitoring applications discovered" -ForegroundColor Green
    } else {
        Write-Host "   Waiting... ($elapsed/$maxWait seconds)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
}

if (-not $found) {
    Write-Host "❌ Monitoring apps not discovered by ArgoCD" -ForegroundColor Red
    Write-Host "   Check if root-app is syncing: kubectl get application root-app -n argocd" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 6: Add grafana.local to hosts file reminder
# ============================================================================
Write-Host "`n7. Hosts file configuration..." -ForegroundColor Yellow
Write-Host "   Ensure this entry exists in your hosts file:" -ForegroundColor Gray
Write-Host "   127.0.0.1 grafana.local" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Windows: C:\Windows\System32\drivers\etc\hosts (requires admin)" -ForegroundColor Gray
Write-Host "   Linux/Mac: /etc/hosts" -ForegroundColor Gray

# ============================================================================
# STEP 7: Wait for monitoring namespace and pods
# ============================================================================
Write-Host "`n8. Waiting for monitoring stack to deploy..." -ForegroundColor Yellow
Write-Host "   (This will take 3-5 minutes - downloading images and starting pods)" -ForegroundColor Gray

# Wait for namespace
$elapsed = 0
while ($elapsed -lt 120) {
    $ns = kubectl get namespace monitoring 2>$null
    if ($ns) { break }
    Start-Sleep -Seconds 5
    $elapsed += 5
}

if (-not $ns) {
    Write-Host "   ⚠ Monitoring namespace not created yet, waiting longer..." -ForegroundColor Yellow
}

# Wait for Prometheus
Write-Host "   - Prometheus..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Prometheus ready" -ForegroundColor Green }

# Wait for Grafana
Write-Host "   - Grafana..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Grafana ready" -ForegroundColor Green }

# Wait for Alertmanager
Write-Host "   - Alertmanager..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n monitoring --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Alertmanager ready" -ForegroundColor Green }

# ============================================================================
# STEP 8: Verify dashboards and alerts loaded
# ============================================================================
Write-Host "`n9. Verifying configuration..." -ForegroundColor Yellow

$alertsConfigMap = kubectl get configmap argocd-alerts -n monitoring 2>$null
if ($alertsConfigMap) {
    Write-Host "   ✓ ArgoCD alert rules configured" -ForegroundColor Green
} else {
    Write-Host "   ⚠ ArgoCD alerts ConfigMap not found (may still be syncing)" -ForegroundColor Yellow
}

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "✓ Monitoring Stack Deployment Complete!" -ForegroundColor Green
Write-Host "="*70 -ForegroundColor Cyan

Write-Host "`nGrafana Credentials:" -ForegroundColor Yellow
Write-Host "  Username: admin"
Write-Host "  Password: admin"
Write-Host "  (⚠️  Change password after first login!)" -ForegroundColor Gray

Write-Host "`nAccess URLs:" -ForegroundColor Yellow
Write-Host "  Grafana:       http://grafana.local"
Write-Host "  Prometheus:    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
Write-Host "  Alertmanager:  kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093"

Write-Host "`nAvailable Dashboards:" -ForegroundColor Yellow
Write-Host "  - ArgoCD Dashboard (pre-loaded in 'ArgoCD' folder)"
Write-Host "  - Kubernetes cluster metrics"
Write-Host "  - Node exporter metrics"
Write-Host "  - Application metrics"

Write-Host "`nConfigured Alerts:" -ForegroundColor Yellow
Write-Host "  - ArgoCDAppOutOfSync: Apps out of sync > 5min"
Write-Host "  - ArgoCDAppUnhealthy: Apps unhealthy > 10min"
Write-Host "  - ArgoCDSyncFailure: Sync failures detected"
Write-Host "  - ArgoCDControllerErrors: Controller errors"
Write-Host "  - ArgoCDRepoConnectionFailure: Git repo connection issues"

Write-Host "`nVerify Status:" -ForegroundColor Yellow
Write-Host "  kubectl get applications -n argocd | Select-String monitoring"
Write-Host "  kubectl get pods -n monitoring"
Write-Host "  kubectl get prometheusrules -n monitoring"

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Login to Grafana at http://grafana.local"
Write-Host "  2. Navigate to Dashboards > ArgoCD folder"
Write-Host "  3. Check Alerting > Alert rules for ArgoCD alerts"
Write-Host "  4. Configure alert notifications (email, Slack, etc.) in Alertmanager"
Write-Host "  5. Change default Grafana password"

Write-Host "`n" + "="*70 -ForegroundColor Cyan
