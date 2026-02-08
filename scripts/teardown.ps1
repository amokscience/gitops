# ArgoCD Complete Teardown Script
# Run this before reinstalling to avoid finalizer issues

Write-Host "=== ArgoCD Complete Teardown ===" -ForegroundColor Cyan

# 1. Delete all Applications (before deleting ArgoCD)
Write-Host "`n1. Removing Applications..." -ForegroundColor Yellow
$apps = kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>$null
if ($apps) {
    foreach ($app in $apps -split ' ') {
        Write-Host "  Removing finalizers from $app"
        kubectl patch application $app -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>$null
    }
    kubectl delete applications --all -n argocd --force --grace-period=0
}

# 2. Delete ArgoCD webhooks (prevents CRD deletion issues)
Write-Host "`n2. Removing webhooks..." -ForegroundColor Yellow
kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/part-of=argocd --ignore-not-found=true
kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/part-of=argocd --ignore-not-found=true

# 3. Delete namespaces
Write-Host "`n3. Deleting namespaces..." -ForegroundColor Yellow
kubectl delete namespace argocd dev external-secrets ingress-nginx --ignore-not-found=true --timeout=30s

# 4. Force-remove stuck namespaces
Write-Host "`n4. Checking for stuck namespaces..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
$stuckNamespaces = @("argocd", "dev", "external-secrets", "ingress-nginx")
foreach ($ns in $stuckNamespaces) {
    $status = kubectl get namespace $ns -o jsonpath='{.status.phase}' 2>$null
    if ($status -eq "Terminating") {
        Write-Host "  Force-removing finalizers from $ns namespace"
        kubectl get namespace $ns -o json | ConvertFrom-Json | ForEach-Object {
            $_.spec.finalizers = @()
            $_ | ConvertTo-Json -Depth 100 | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f -
        }
    }
}

# 5. Delete ArgoCD CRDs
Write-Host "`n5. Removing ArgoCD CRDs..." -ForegroundColor Yellow
$crds = @("applications.argoproj.io", "applicationsets.argoproj.io", "appprojects.argoproj.io")
foreach ($crd in $crds) {
    $exists = kubectl get crd $crd 2>$null
    if ($exists) {
        Write-Host "  Removing finalizers from $crd"
        kubectl patch crd $crd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
        kubectl delete crd $crd --force --grace-period=0 --ignore-not-found=true
    }
}

# 6. Verify cleanup
Write-Host "`n6. Verifying cleanup..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

$remainingNs = kubectl get namespace argocd,dev,external-secrets,ingress-nginx 2>$null
$remainingCrds = kubectl get crd | Select-String "argoproj"

if ($remainingNs -or $remainingCrds) {
    Write-Host "`n⚠ Warning: Some resources still exist" -ForegroundColor Red
    if ($remainingNs) { Write-Host "Namespaces: $remainingNs" }
    if ($remainingCrds) { Write-Host "CRDs: $remainingCrds" }
} else {
    Write-Host "`n✓ Cleanup complete! Ready for fresh install." -ForegroundColor Green
}

Write-Host "`n=== Teardown Complete ===" -ForegroundColor Cyan
