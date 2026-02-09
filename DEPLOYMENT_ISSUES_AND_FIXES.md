# Monitoring Stack - Deployment Process Summary

## Issues We Encountered & Solutions

### 1. CRD Annotation Bloat (CRITICAL ISSUE)
**Problem:** 
- Helm's kube-prometheus-stack CRDs come with massive annotations from Helm
- Total annotation size exceeded Kubernetes API limits (max 262KB)
- ArgoCD couldn't apply these CRDs due to validation errors

**Solution:**
- Download clean CRDs from prometheus-operator upstream repo (no Helm annotations)
- Use `ServerSideApply=true` in ArgoCD Application spec
- Avoids the annotation size problem entirely

**Files Updated:**
- `scripts/deploy-monitoring.ps1` - Now fetches CRDs from upstream URLs

### 2. Node Exporter Mount Issues
**Problem:**
- Docker Desktop/WSL2 limitation: root filesystem (/) not mounted as shared
- Node exporter tried to mount root filesystem and failed
- Error: "path / is mounted on / but it is not a shared or slave mount"

**Solution:**
- Set `hostNetwork: true` and `hostPID: true` in node-exporter Helm values
- Disable `hostRootFsMount: enabled: false` (don't try to mount root)
- Add tolerations for all node taints
- This gives node-exporter necessary access without requiring root mount

**Files Updated:**
- `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml` - Added node-exporter config

### 3. Storage Class Not Found
**Problem:**
- Prometheus operator couldn't create StatefulSet
- Operator logs showed: "storage class 'docker-desktop' does not exist"
- PVC creation was blocked

**Solution:**
- Use existing `hostpath` storage class on Docker Desktop
- Updated Prometheus spec: `storageClassName: hostpath`
- Added storage class creation step to deployment script

**Files Updated:**
- `scripts/deploy-monitoring.ps1` - Added storage class verification step
- `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml` - Changed storage class

### 4. ArgoCD Not Syncing Application
**Problem:**
- ArgoCD stuck in "OutOfSync" state for extended periods
- Couldn't apply Prometheus/Alertmanager resources

**Solution:**
- Added `ServerSideApply=true` sync option
- Enables server-side field management which handles large annotations
- Fixes API validation issues

**Files Updated:**
- `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml` - Added ServerSideApply sync option

### 5. Prometheus Metrics Not Visible
**Problem:**
- Grafana dashboard showed no data
- ArgoCD metrics not being scraped

**Solution:**
- Created ServiceMonitors to tell Prometheus where to scrape ArgoCD metrics
- ServiceMonitors must have label `release: kube-prometheus-stack` to be discovered
- Prometheus discovers ServiceMonitors automatically once they exist

**Files Created:**
- `argocd/applications/infrastructure/argocd-servicemonitors.yaml` - ServiceMonitors for ArgoCD

### 6. Ingress Not Configured
**Problem:**
- Had to use kubectl port-forward to access services
- Not practical for regular use

**Solution:**
- Added Ingress configuration for Prometheus, Grafana, and Alertmanager
- All three now accessible via ingress-nginx at *.local domains

**Files Updated:**
- `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml` - Added Ingress specs

## Final Working Configuration

### Key Configuration Values
```yaml
# Storage
storageClassName: hostpath          # Using Docker Desktop's hostpath provisioner

# Node Exporter (Docker Desktop fix)
hostNetwork: true
hostPID: true
hostRootFsMount:
  enabled: false                    # Don't try to mount root filesystem

# ArgoCD Sync
syncOptions:
  - ServerSideApply=true            # Handle large CRD annotations
  - PruneLast=true                  # Clean orphaned resources after sync
```

### CRD Source
- **Source:** https://github.com/prometheus-operator/prometheus-operator (upstream)
- **Why:** Clean CRDs without Helm's bloated annotations
- **Method:** Downloaded individually and applied with `kubectl apply`

### Service Access
```
Grafana:      http://grafana.local
Prometheus:   http://prometheus.local
Alertmanager: http://alertmanager.local
```

## Files Changed

### New Files Created
1. `MONITORING_SETUP.md` - Comprehensive setup guide
2. `argocd/applications/infrastructure/argocd-servicemonitors.yaml` - ArgoCD metrics scraping

### Files Modified
1. `scripts/deploy-monitoring.ps1` - Updated deployment script
2. `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml` - Fixed configuration

## Deployment Script Changes

The new script handles:
1. ✅ ArgoCD verification
2. ✅ CRD installation from upstream (not Helm)
3. ✅ Storage class verification/creation
4. ✅ Monitoring namespace and project creation
5. ✅ Application deployment with ServerSideApply
6. ✅ ServiceMonitor creation for ArgoCD metrics
7. ✅ Hosts file configuration instructions
8. ✅ Pod readiness verification
9. ✅ Ingress verification
10. ✅ Final status reporting with helpful next steps

## Testing the Configuration

Run the deployment script:
```bash
.\scripts\deploy-monitoring.ps1
```

Expected output:
- All CRDs installed
- Storage class verified
- Application deployed and synced
- All pods running
- Ingresses created

Then verify:
1. Go to `http://grafana.local` - login with admin/admin
2. Go to `http://prometheus.local` - should show metrics
3. Add Prometheus datasource to Grafana
4. View ArgoCD dashboard

## Lessons Learned

1. **CRD Management:** Never use Helm-rendered CRDs directly; use upstream source
2. **Annotation Limits:** Watch for large metadata in Kubernetes resources
3. **Storage Class:** Always verify storage provisioner is available before deploying
4. **Server-Side Apply:** Use for resources with complex metadata management
5. **ServiceMonitors:** Label matching is critical (`release: kube-prometheus-stack`)
6. **Docker Desktop:** Needs special handling for hostPath and mount propagation

## Future Improvements

- [ ] Configure persistent storage for production
- [ ] Set up alert notification channels (email, Slack, PagerDuty)
- [ ] Create custom dashboards for business metrics
- [ ] Implement PrometheusRules for application-specific alerts
- [ ] Set retention policies for metrics
- [ ] Add backup/restore procedures for Prometheus data
