#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Complete setup script for ArgoCD on Docker Desktop with CFB deployments
  
.DESCRIPTION
  Installs ArgoCD, configures it, deploys all 4 CFB environments, and provides access details
#>

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "ArgoCD Setup for Docker Desktop" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# Step 1: Create argocd namespace and install ArgoCD via Helm
Write-Host "`nStep 1: Installing ArgoCD via Helm..." -ForegroundColor Yellow
kubectl create namespace argocd 2>/dev/null

# Add ArgoCD Helm repo
helm repo add argocd https://argoproj.github.io/argo-helm 2>/dev/null
helm repo update

# Install ArgoCD using Helm
helm install argocd argocd/argo-cd `
  --namespace argocd `
  --set server.insecure=true `
  --set server.service.type=NodePort `
  --wait

Write-Host "Waiting for ArgoCD to be ready (this may take 2-3 minutes)..." -ForegroundColor Yellow
kubectl wait -n argocd deployment/argocd-server --for=condition=available --timeout=5m 2>/dev/null || `
  kubectl wait -n argocd pod -l app.kubernetes.io/name=argocd-server --for=condition=Ready --timeout=5m

# Step 2: Create namespaces for each environment
Write-Host "`nStep 2: Creating namespaces..." -ForegroundColor Yellow
kubectl create namespace dev 2>/dev/null
kubectl create namespace qa 2>/dev/null
kubectl create namespace staging 2>/dev/null
kubectl create namespace prod 2>/dev/null
Write-Host "✓ Namespaces created: dev, qa, staging, prod" -ForegroundColor Green

# Step 3: Deploy the 4 CFB Application manifests
Write-Host "`nStep 3: Deploying CFB Applications to ArgoCD..." -ForegroundColor Yellow
$scriptDir = Split-Path -Parent $PSScriptRoot
kubectl apply -f "$scriptDir/argocd/cfb-dev-app.yaml"
kubectl apply -f "$scriptDir/argocd/cfb-qa-app.yaml"
kubectl apply -f "$scriptDir/argocd/cfb-staging-app.yaml"
kubectl apply -f "$scriptDir/argocd/cfb-prod-app.yaml"

Write-Host "✓ Applications created" -ForegroundColor Green
kubectl get applications -n argocd

# Step 4: Get admin password
Write-Host "`nStep 4: Retrieving admin credentials..." -ForegroundColor Yellow
$password = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d
Write-Host "ArgoCD Admin Credentials:" -ForegroundColor Cyan
Write-Host "  Username: admin" -ForegroundColor Green
Write-Host "  Password: $password" -ForegroundColor Green

# Step 5: Port-forward instructions
Write-Host "`nStep 5: Port-forwarding to ArgoCD UI..." -ForegroundColor Yellow
Write-Host "`nRun this command in a NEW terminal:" -ForegroundColor Cyan
Write-Host "  kubectl port-forward -n argocd svc/argocd-server 8080:443" -ForegroundColor White

Write-Host "`nThen access ArgoCD:" -ForegroundColor Cyan
Write-Host "  URL: https://localhost:8080" -ForegroundColor White
Write-Host "  Username: admin" -ForegroundColor White
Write-Host "  Password: $password" -ForegroundColor White

# Step 6: Check application status
Write-Host "`nStep 6: Application Status" -ForegroundColor Yellow
Write-Host "Checking sync status (this may take a few moments)..." -ForegroundColor Gray
Start-Sleep -Seconds 5

$maxWait = 0
while ($maxWait -lt 60) {
    $status = kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.operationState.phase}{"\t"}{.status.health.status}{"\n"}{end}'
    if ($status) {
        Write-Host $status
        break
    }
    Start-Sleep -Seconds 2
    $maxWait += 2
}

# Step 7: Get service info
Write-Host "`nStep 7: Application Access Points" -ForegroundColor Yellow
Write-Host "`nServices in each namespace:" -ForegroundColor Cyan

@('dev', 'qa', 'staging', 'prod') | ForEach-Object {
    Write-Host "`n$($_):" -ForegroundColor White
    kubectl get svc -n $_ -o wide 2>/dev/null | Select-Object -Skip 1 | ForEach-Object {
        Write-Host "  $_"
    }
}

Write-Host "`nTo access CFB in each environment, use:" -ForegroundColor Cyan
Write-Host "  kubectl port-forward -n dev svc/cfb 8081:80" -ForegroundColor Gray
Write-Host "  kubectl port-forward -n qa svc/cfb 8082:80" -ForegroundColor Gray
Write-Host "  kubectl port-forward -n staging svc/cfb 8083:80" -ForegroundColor Gray
Write-Host "  kubectl port-forward -n prod svc/cfb 8084:80" -ForegroundColor Gray

Write-Host "`nThen visit:" -ForegroundColor Cyan
Write-Host "  Dev:     http://localhost:8081" -ForegroundColor Gray
Write-Host "  QA:      http://localhost:8082" -ForegroundColor Gray
Write-Host "  Staging: http://localhost:8083" -ForegroundColor Gray
Write-Host "  Prod:    http://localhost:8084" -ForegroundColor Gray

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Cyan
