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
# STEP 2: Install Prometheus Operator CRDs (from upstream, not Helm)
# ============================================================================
Write-Host "`n2. Installing Prometheus Operator Custom Resource Definitions..." -ForegroundColor Yellow
Write-Host "   (Using clean CRDs from prometheus-operator repo to avoid annotation bloat)" -ForegroundColor Gray

$crdUrls = @(
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagerconfigs.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_scrapeconfigs.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml",
    "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusagents.yaml"
)

foreach ($url in $crdUrls) {
    $crdName = $url.Split('_')[1].Split('.')[0]
    Write-Host "   Installing $crdName..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $url -OutFile $env:TEMP\crd.yaml -ErrorAction Stop
    kubectl apply -f $env:TEMP\crd.yaml 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
}

$crdCheck = kubectl get crd prometheuses.monitoring.coreos.com 2>$null
if ($crdCheck) {
    Write-Host "   ✓ All Prometheus Operator CRDs installed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to install CRDs!" -ForegroundColor Red
    Write-Host "   Check your internet connection and try again" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 3: Verify and Create Storage Class
# ============================================================================
Write-Host "`n3. Verifying storage class..." -ForegroundColor Yellow

$storageClass = kubectl get storageclass hostpath 2>$null
if ($storageClass) {
    Write-Host "   ✓ Storage class 'hostpath' exists" -ForegroundColor Green
} else {
    Write-Host "   ℹ Creating hostpath storage class..." -ForegroundColor Gray
    kubectl apply -f - @"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hostpath
provisioner: docker.io/hostpath
allowVolumeExpansion: true
volumeBindingMode: Immediate
"@ 2>&1 | Out-Null
    Write-Host "   ✓ Storage class created" -ForegroundColor Green
}

# ============================================================================
# STEP 4: Apply monitoring AppProject
# ============================================================================
Write-Host "`n4. Creating monitoring namespace..." -ForegroundColor Yellow
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
Write-Host "   ✓ Monitoring namespace created" -ForegroundColor Green

Write-Host "`n5. Creating monitoring AppProject..." -ForegroundColor Yellow

if (Test-Path "argocd/projects/monitoring-project.yaml") {
    kubectl apply -f argocd/projects/monitoring-project.yaml
    Write-Host "   ✓ Monitoring project created" -ForegroundColor Green
} else {
    Write-Host "❌ monitoring-project.yaml not found!" -ForegroundColor Red
    Write-Host "   Expected: argocd/projects/monitoring-project.yaml" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 5: Verify monitoring apps exist in git
# ============================================================================
Write-Host "`n6. Verifying monitoring application manifests..." -ForegroundColor Yellow

$requiredFiles = @(
    "argocd/applications/infrastructure/kube-prometheus-stack-app.yaml",
    "argocd/applications/infrastructure/argocd-servicemonitors.yaml"
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
# STEP 6: Deploy kube-prometheus-stack Application
# ============================================================================
Write-Host "`n7. Deploying kube-prometheus-stack via ArgoCD..." -ForegroundColor Yellow

kubectl apply -f argocd/applications/infrastructure/kube-prometheus-stack-app.yaml
Write-Host "   ✓ Application created" -ForegroundColor Green

Write-Host "`n8. Waiting for application to sync..." -ForegroundColor Yellow
Write-Host "   (This may take 3-5 minutes - pulling images and starting pods)" -ForegroundColor Gray

$maxWait = 300
$elapsed = 0
$synced = $false

while ($elapsed -lt $maxWait -and -not $synced) {
    $appStatus = kubectl get application kube-prometheus-stack -n argocd -o jsonpath='{.status.operationState.phase}' 2>$null
    $healthStatus = kubectl get application kube-prometheus-stack -n argocd -o jsonpath='{.status.health.status}' 2>$null
    
    if ($healthStatus -eq "Healthy" -and $appStatus -ne "Running") {
        $synced = $true
        Write-Host "   ✓ Application synced successfully" -ForegroundColor Green
        break
    }
    
    Write-Host "   Status: $appStatus | Health: $healthStatus ($elapsed/$maxWait seconds)" -ForegroundColor Gray
    Start-Sleep -Seconds 10
    $elapsed += 10
}

if (-not $synced) {
    Write-Host "⚠ Still syncing (taking longer than expected)" -ForegroundColor Yellow
    Write-Host "   You can monitor progress: kubectl get application kube-prometheus-stack -n argocd -w" -ForegroundColor Gray
}

# ============================================================================
# STEP 7: Create ServiceMonitors for ArgoCD Metrics
# ============================================================================
Write-Host "`n9. Creating ArgoCD ServiceMonitors for Prometheus scraping..." -ForegroundColor Yellow

if (Test-Path "argocd/applications/infrastructure/argocd-servicemonitors.yaml") {
    kubectl apply -f argocd/applications/infrastructure/argocd-servicemonitors.yaml
    Write-Host "   ✓ ServiceMonitors created" -ForegroundColor Green
    Write-Host "   (Prometheus will start scraping ArgoCD metrics in ~2 minutes)" -ForegroundColor Gray
} else {
    Write-Host "⚠ argocd-servicemonitors.yaml not found - ArgoCD metrics may not be available" -ForegroundColor Yellow
}

# ============================================================================
# STEP 8: Configure Hosts File
# ============================================================================
Write-Host "`n10. Configuring hosts file..." -ForegroundColor Yellow
Write-Host "   Add these entries to your hosts file:" -ForegroundColor Gray
Write-Host "   127.0.0.1 grafana.local" -ForegroundColor Cyan
Write-Host "   127.0.0.1 prometheus.local" -ForegroundColor Cyan
Write-Host "   127.0.0.1 alertmanager.local" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Windows: C:\Windows\System32\drivers\etc\hosts (requires admin)" -ForegroundColor Gray
Write-Host "   Linux/Mac: /etc/hosts" -ForegroundColor Gray

# ============================================================================
# STEP 9: Wait for all pods to be ready
# ============================================================================
Write-Host "`n8. Waiting for monitoring stack to deploy..." -ForegroundColor Yellow
Write-Host "`n11. Waiting for pods to be ready..." -ForegroundColor Yellow
Write-Host "   (This will take 3-5 minutes)" -ForegroundColor Gray

# Wait for Grafana
Write-Host "   - Grafana..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Grafana ready" -ForegroundColor Green }

# Wait for Prometheus
Write-Host "   - Prometheus..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Prometheus ready" -ForegroundColor Green }

# Wait for Alertmanager
Write-Host "   - Alertmanager..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=alertmanager -n monitoring --timeout=300s 2>$null
if ($?) { Write-Host "     ✓ Alertmanager ready" -ForegroundColor Green }

# ============================================================================
# STEP 10: Verify Ingresses
# ============================================================================
Write-Host "`n12. Verifying ingress routes..." -ForegroundColor Yellow

$ingresses = kubectl get ingress -n monitoring 2>$null
if ($ingresses) {
    Write-Host "   ✓ Ingresses created:" -ForegroundColor Green
    kubectl get ingress -n monitoring | Select-Object NAME, CLASS, HOSTS | Format-Table
} else {
    Write-Host "   ⚠ No ingresses found" -ForegroundColor Yellow
}
# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "✓ Monitoring Stack Deployment Complete!" -ForegroundColor Green
Write-Host "="*70 -ForegroundColor Cyan

Write-Host "`nGrafana Login:" -ForegroundColor Yellow
Write-Host "  URL:      http://grafana.local"
Write-Host "  Username: admin"
Write-Host "  Password: admin"
Write-Host "  ⚠️  Change the password after first login!" -ForegroundColor Red

Write-Host "`nMonitoring URLs:" -ForegroundColor Yellow
Write-Host "  Grafana:      http://grafana.local (dashboards and visualization)"
Write-Host "  Prometheus:   http://prometheus.local (metrics database)"
Write-Host "  Alertmanager: http://alertmanager.local (alerts and notifications)"

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Login to http://grafana.local with admin/admin"
Write-Host "  2. Add Prometheus datasource (Configuration → Data Sources)"
Write-Host "     URL: http://kube-prometheus-stack-prometheus.monitoring:9090"
Write-Host "  3. View ArgoCD Dashboard (Dashboards → ArgoCD folder)"
Write-Host "  4. Configure alert notifications (Alertmanager)"
Write-Host "  5. Create custom dashboards for your applications"

Write-Host "`nMetrics Available:" -ForegroundColor Yellow
Write-Host "  - ArgoCD metrics (applications, syncs, repository status)"
Write-Host "  - Kubernetes metrics (nodes, pods, containers)"
Write-Host "  - Node metrics (CPU, memory, disk, network)"
Write-Host "  - Custom metrics from your deployed apps"

Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
Write-Host "  Monitor application status:"
Write-Host "    kubectl get application kube-prometheus-stack -n argocd -w"
Write-Host "  Check pod status:"
Write-Host "    kubectl get pods -n monitoring"
Write-Host "  View operator logs:"
Write-Host "    kubectl logs -n monitoring -l app=kube-prometheus-stack-operator --tail=50"

Write-Host "`nDocumentation:" -ForegroundColor Yellow
Write-Host "  See MONITORING_SETUP.md for detailed configuration and troubleshooting"

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
