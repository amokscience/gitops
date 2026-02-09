# Quick Start: Deploy Prometheus/Grafana Stack

## TL;DR - One Command Deployment

```powershell
.\scripts\deploy-monitoring.ps1
```

That's it! The script handles everything.

## After Deployment

### 1. Add to Hosts File
Edit `C:\Windows\System32\drivers\etc\hosts` (as admin):
```
127.0.0.1 grafana.local
127.0.0.1 prometheus.local
127.0.0.1 alertmanager.local
```

### 2. Access Services
- **Grafana:** http://grafana.local (admin/admin - **change password!**)
- **Prometheus:** http://prometheus.local
- **Alertmanager:** http://alertmanager.local

### 3. Add Prometheus to Grafana
1. Login to Grafana
2. **Configuration** → **Data Sources** → **Add data source**
3. Select **Prometheus**
4. URL: `http://kube-prometheus-stack-prometheus.monitoring:9090`
5. Click **Save & test**

### 4. View ArgoCD Dashboard
1. Click **Dashboards**
2. Find **ArgoCD** folder
3. Open **ArgoCD Dashboard**

Data will populate automatically once metrics are scraped (~2-3 minutes).

## Verification Commands

```powershell
# Check deployment status
kubectl get application kube-prometheus-stack -n argocd

# Check all pods
kubectl get pods -n monitoring

# Check ingresses
kubectl get ingress -n monitoring

# Check metrics are being scraped
kubectl get servicemonitor -n argocd

# View operator logs
kubectl logs -n monitoring -l app=kube-prometheus-stack-operator --tail=20
```

## Troubleshooting

### No data in dashboard?
```powershell
# Wait for metrics to be scraped (2-3 minutes)
# Then check in Prometheus: http://prometheus.local
# Search for: argocd_app_info
# Should return results
```

### Pods not starting?
```powershell
# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp' | tail -20

# Check pod logs
kubectl describe pod <pod-name> -n monitoring
```

### Application stuck syncing?
```powershell
# Force refresh
kubectl patch application kube-prometheus-stack -n argocd -p '{"status":{"operationState":null}}' --type merge
```

## Files Reference

| File | Purpose |
|------|---------|
| `scripts/deploy-monitoring.ps1` | Main deployment script |
| `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml` | Prometheus stack app |
| `argocd/applications/infrastructure/argocd-servicemonitors.yaml` | ArgoCD metrics scraping |
| `argocd/projects/monitoring-project.yaml` | ArgoCD project for monitoring |
| `MONITORING_SETUP.md` | Detailed setup guide |
| `DEPLOYMENT_ISSUES_AND_FIXES.md` | Issues encountered and solutions |

## Key Fixes Applied

✅ CRDs installed from upstream (avoids annotation bloat)
✅ Storage class configured (hostpath)
✅ Node exporter fixed (Docker Desktop compatibility)
✅ ServerSideApply enabled (handles large metadata)
✅ Ingresses configured (no port-forward needed)
✅ ServiceMonitors created (ArgoCD metrics)

See `DEPLOYMENT_ISSUES_AND_FIXES.md` for detailed explanation of each fix.
