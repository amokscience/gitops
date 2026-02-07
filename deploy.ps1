#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Deploy CFB app to specified environment using Helm
  
.DESCRIPTION
  Renders Helm chart with environment-specific values and deploys to Kubernetes.
  
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

$repoRoot = $PSScriptRoot
$helmChart = Join-Path $repoRoot "cfb\helm"
$valuesFile = Join-Path $repoRoot "cfb\helm\values-$Environment.yaml"

Write-Host "Deploying CFB to $Environment environment..." -ForegroundColor Cyan

# Check if environment values file exists
if (-not (Test-Path $valuesFile)) {
    Write-Host "Error: Values file not found: $valuesFile" -ForegroundColor Red
    exit 1
}

# Render Helm chart with environment-specific values
Write-Host "Rendering Helm chart for $Environment..." -ForegroundColor Yellow
$finalManifest = helm template cfb $helmChart -f $valuesFile 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error rendering Helm chart:" -ForegroundColor Red
    Write-Host $finalManifest
    exit 1
}

# Display or apply
if ($Apply) {
    Write-Host "Applying to cluster..." -ForegroundColor Yellow
    $finalManifest | kubectl apply -f -
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully deployed to $Environment!" -ForegroundColor Green
    } else {
        Write-Host "Error applying manifests to cluster:" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Generated manifests (use -Apply flag to deploy):" -ForegroundColor Yellow
    Write-Host "---" -ForegroundColor Cyan
    $finalManifest
}
