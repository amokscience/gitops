# ============================================================================
# Monitoring Stack Removal Script
# ============================================================================
# This script cleanly removes the Prometheus/Grafana monitoring stack from
# the cluster. It handles finalizers and resource cleanup properly.
#
# WARNING: This will delete:
# - Prometheus instance and all metrics history
# - Grafana dashboards and configuration
# - Alertmanager configuration
# - Monitoring namespace and all resources
# - ArgoCD monitoring AppProject
# ============================================================================

Write-Host "=== ArgoCD Monitoring Stack Removal ===" -ForegroundColor Red

Write-Host "`n⚠️  WARNING: This will permanently delete the monitoring stack!" -ForegroundColor Red
Write-Host "   - All Prometheus metrics (15 days of data)" -ForegroundColor Red
Write-Host "   - All Grafana dashboards and user data" -ForegroundColor Red
Write-Host "   - Alertmanager configuration" -ForegroundColor Red
Write-Host ""
Write-Host "Type 'delete-monitoring' to confirm, or press Ctrl+C to abort:" -ForegroundColor Yellow
$confirmation = Read-Host

if ($confirmation -ne "delete-monitoring") {
    Write-Host "❌ Aborted." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nProceeding with removal..." -ForegroundColor Red

# ============================================================================
# STEP 1: Remove ArgoCD Applications managing monitoring
# ============================================================================
Write-Host "`n1. Removing monitoring ArgoCD Applications..." -ForegroundColor Yellow

$apps = @(
    "kube-prometheus-stack",
    "argocd-alerts"
)

foreach ($app in $apps) {
    Write-Host "   - Removing $app finalizers..."
    kubectl patch application $app -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>$null
    
    Write-Host "   - Deleting $app..."
    kubectl delete application $app -n argocd --force --grace-period=0 2>$null
}

# ============================================================================
# STEP 2: Delete monitoring namespace and all resources
# ============================================================================
Write-Host "`n2. Deleting monitoring namespace..." -ForegroundColor Yellow

# Try graceful deletion first
kubectl delete namespace monitoring --timeout=30s 2>$null

# Force remove if stuck
$status = kubectl get namespace monitoring -o jsonpath='{.status.phase}' 2>$null
if ($status -eq "Terminating") {
    Write-Host "   Namespace stuck in Terminating, force-removing finalizers..."
    kubectl get namespace monitoring -o json | ConvertFrom-Json | ForEach-Object {
        $_.spec.finalizers = @()
        $_ | ConvertTo-Json -Depth 100 | kubectl replace --raw /api/v1/namespaces/monitoring/finalize -f - 2>$null
    }
}

# ============================================================================
# STEP 3: Remove Prometheus CRDs (if not needed for other monitoring)
# ============================================================================
Write-Host "`n3. Cleaning up Prometheus Custom Resource Definitions..." -ForegroundColor Yellow

$promCrds = @(
    "prometheuses.monitoring.coreos.com",
    "prometheusrules.monitoring.coreos.com",
    "servicemonitors.monitoring.coreos.com",
    "alertmanagers.monitoring.coreos.com",
    "alertmanagerrules.monitoring.coreos.com",
    "podmonitors.monitoring.coreos.com"
)

foreach ($crd in $promCrds) {
    $exists = kubectl get crd $crd 2>$null
    if ($exists) {
        Write-Host "   - $crd"
        kubectl patch crd $crd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
        kubectl delete crd $crd --force --grace-period=0 2>$null
    }
}

# ============================================================================
# STEP 4: Remove monitoring AppProject
# ============================================================================
Write-Host "`n4. Removing monitoring AppProject..." -ForegroundColor Yellow

$projectFile = "argocd/projects/monitoring-project.yaml"
if (Test-Path $projectFile) {
    kubectl delete -f $projectFile 2>$null
    Write-Host "   ✓ Deleted from cluster" -ForegroundColor Green
} else {
    Write-Host "   (File not found in repo, manually checking cluster)" -ForegroundColor Gray
}

# Manual deletion as backup
kubectl delete appproject monitoring -n argocd 2>$null

# ============================================================================
# STEP 5: Remove git references (optional)
# ============================================================================
Write-Host "`n5. Cleaning up git repository..." -ForegroundColor Yellow

$monitoringFiles = @(
    "argocd/projects/monitoring-project.yaml",
    "argocd/applications/infrastructure/kube-prometheus-stack-app.yaml",
    "argocd/applications/infrastructure/argocd-alerts-app.yaml",
    "monitoring/"
)

Write-Host "   Files that can be removed from git:" -ForegroundColor Gray
foreach ($file in $monitoringFiles) {
    if (Test-Path $file) {
        Write-Host "   - $file" -ForegroundColor Gray
    }
}

Write-Host "`n   To remove from git:" -ForegroundColor Yellow
Write-Host "   git rm -r argocd/projects/monitoring-project.yaml" -ForegroundColor Cyan
Write-Host "   git rm -r argocd/applications/infrastructure/kube-prometheus-stack-app.yaml" -ForegroundColor Cyan
Write-Host "   git rm -r argocd/applications/infrastructure/argocd-alerts-app.yaml" -ForegroundColor Cyan
Write-Host "   git rm -r monitoring/" -ForegroundColor Cyan
Write-Host "   git commit -m 'Remove monitoring stack'" -ForegroundColor Cyan
Write-Host "   git push" -ForegroundColor Cyan

# ============================================================================
# STEP 6: Verify removal
# ============================================================================
Write-Host "`n6. Verifying removal..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$monitoringNs = kubectl get namespace monitoring 2>$null
$prometheusApp = kubectl get application kube-prometheus-stack -n argocd 2>$null
$monitoringProject = kubectl get appproject monitoring -n argocd 2>$null

if ($monitoringNs) {
    Write-Host "   ⚠ Monitoring namespace still exists" -ForegroundColor Yellow
    kubectl get namespace monitoring
} else {
    Write-Host "   ✓ Monitoring namespace removed" -ForegroundColor Green
}

if ($prometheusApp) {
    Write-Host "   ⚠ Prometheus application still exists" -ForegroundColor Yellow
} else {
    Write-Host "   ✓ Prometheus application removed" -ForegroundColor Green
}

if ($monitoringProject) {
    Write-Host "   ⚠ Monitoring project still exists" -ForegroundColor Yellow
} else {
    Write-Host "   ✓ Monitoring project removed" -ForegroundColor Green
}

# ============================================================================
# REMOVAL COMPLETE
# ============================================================================
Write-Host "`n" + "="*70 -ForegroundColor Red
Write-Host "✓ Monitoring Stack Removal Complete!" -ForegroundColor Green
Write-Host "="*70 -ForegroundColor Red

Write-Host "`nRemaining tasks:" -ForegroundColor Yellow
Write-Host "  1. Remove monitoring files from git (see above)"
Write-Host "  2. Commit and push: git push"
Write-Host "  3. Remove 'grafana.local' from your hosts file (if desired)"
Write-Host "  4. Root app will auto-sync and remove monitoring from ArgoCD"

Write-Host "`nVerify final state:" -ForegroundColor Yellow
Write-Host "  kubectl get namespace monitoring"
Write-Host "  kubectl get applications -n argocd"
Write-Host "  kubectl get appproject -n argocd"

Write-Host "`n" + "="*70 -ForegroundColor Red
