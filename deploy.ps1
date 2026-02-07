#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Deploy CFB app to specified environment using Helm + Kustomize pipeline
  
.DESCRIPTION
  Renders Helm chart with environment-specific values, applies Kustomize overlays,
  and optionally deploys to Kubernetes cluster.
  
.PARAMETER Environment
  Target environment: dev, qa, staging, or prod
  
.PARAMETER Apply
  If specified, applies the manifests to the cluster. Otherwise just displays them.
  
.EXAMPLE
  .\deploy.ps1 -Environment dev
  .\deploy.ps1 -Environment prod -Apply
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'qa', 'staging', 'prod')]
    [string]$Environment,
    
    [switch]$Apply
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$helmChart = Join-Path $repoRoot "cfb\helm"
$defaultsFile = Join-Path $repoRoot "helm-defaults\defaults.yaml"
$valuesFile = Join-Path $repoRoot "cfb\helm\values.yaml"
$overlayPath = Join-Path $repoRoot "cfb\overlays\$Environment"

Write-Host "Deploying CFB to $Environment environment..." -ForegroundColor Cyan

# Step 1: Template Helm chart with defaults and base values
Write-Host "Step 1: Rendering Helm chart..." -ForegroundColor Yellow
$helmOutput = helm template cfb $helmChart `
    -f $defaultsFile `
    -f $valuesFile 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error rendering Helm chart:" -ForegroundColor Red
    Write-Host $helmOutput
    exit 1
}

# Step 2: Pipe Helm output through Kustomize overlay
Write-Host "Step 2: Applying Kustomize overlays..." -ForegroundColor Yellow
$finalManifest = $helmOutput | kustomize build $overlayPath --load-restrictor LoadRestrictionsNone -f - 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error applying Kustomize overlays:" -ForegroundColor Red
    Write-Host $finalManifest
    exit 1
}

# Step 3: Display or apply
if ($Apply) {
    Write-Host "Step 3: Applying to cluster..." -ForegroundColor Yellow
    $finalManifest | kubectl apply -f -
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully deployed to $Environment!" -ForegroundColor Green
    } else {
        Write-Host "Error applying manifests to cluster:" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Step 3: Generated manifests (use -Apply flag to deploy):" -ForegroundColor Yellow
    Write-Host "---" -ForegroundColor Cyan
    $finalManifest
}
