# Prometheus/Grafana Monitoring Stack Setup Guide

## Overview

This guide documents the correct deployment process for the kube-prometheus-stack with ArgoCD integration. The stack includes:
- **Prometheus** - Metrics collection and storage
- **Grafana** - Dashboards and visualization  
- **Alertmanager** - Alert routing and notifications
- **Node Exporter** - Hardware and OS metrics
- **Kube State Metrics** - Kubernetes object metrics

## Prerequisites

1. ✅ ArgoCD installed and running
2. ✅ ingress-nginx deployed (`kubectl get deployment -n ingress-nginx`)
3. ✅ Git repo synchronized with ArgoCD
4. ✅ Storage provisioner available (Docker Desktop has `hostpath` by default)

## Critical Issues & Solutions

### Issue 1: CRD Annotation Bloat
**Problem:** Helm's kube-prometheus-stack CRDs come with large annotations that exceed Kubernetes limits (>262KB)

**Solution:** 
- Install CRDs from prometheus-operator upstream repo (not from Helm chart)
- Use `ServerSideApply=true` in ArgoCD Application spec
- Never use `kubectl apply` directly on these CRDs

### Issue 2: Storage Class Not Found
**Problem:** Prometheus operator fails to create StatefulSets if storage class doesn't exist

**Solution:**
- Use existing `hostpath` storage class (available on Docker Desktop)
- Verify: `kubectl get storageclass`
- Configure in Prometheus spec: `storageClassName: hostpath`

### Issue 3: Node Exporter Mount Issues
**Problem:** Node exporter fails on Docker Desktop with "path / is mounted on / but it is not a shared or slave mount"

**Solution:**
- Set `hostNetwork: true` and `hostPID: true` in node-exporter config
- Disable `hostRootFsMount` (don't try to mount root filesystem)
- Add tolerations for all node taints

## Deployment Steps

### Step 1: Install Prometheus Operator CRDs

```bash
# Add prometheus-operator repo
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagerconfigs.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_scrapeconfigs.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusagents.yaml

# Verify
kubectl get crd | grep monitoring.coreos.com
```

### Step 2: Verify Storage Class

```bash
# Check default storage class
kubectl get storageclass

# Should see "hostpath" on Docker Desktop
# If missing, create it:
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hostpath
provisioner: docker.io/hostpath
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF
```

### Step 3: Create Monitoring Namespace & Project

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f argocd/projects/monitoring-project.yaml
```

### Step 4: Deploy kube-prometheus-stack Application

```bash
kubectl apply -f argocd/applications/infrastructure/kube-prometheus-stack-app.yaml
```

**Wait for sync to complete** (2-5 minutes):
```bash
kubectl get application kube-prometheus-stack -n argocd -w
# Status should change from "OutOfSync" to "Synced" and health to "Healthy"
```

### Step 5: Create ArgoCD ServiceMonitors

```bash
kubectl apply -f argocd/applications/infrastructure/argocd-servicemonitors.yaml
```

This enables Prometheus to scrape ArgoCD metrics.

### Step 6: Configure Hosts File

Add these entries to your hosts file:

**Windows:** `C:\Windows\System32\drivers\etc\hosts` (run as admin)
```
127.0.0.1 grafana.local
127.0.0.1 prometheus.local
127.0.0.1 alertmanager.local
```

**Linux/Mac:** `/etc/hosts`

### Step 7: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Expected pods:
# - kube-prometheus-stack-grafana-*
# - kube-prometheus-stack-operator-*
# - kube-prometheus-stack-kube-state-metrics-*
# - kube-prometheus-stack-prometheus-0 (StatefulSet)
# - kube-prometheus-stack-alertmanager-0 (StatefulSet)
# - kube-prometheus-stack-prometheus-node-exporter-*

# Check ingresses
kubectl get ingress -n monitoring
```

### Step 8: Access Monitoring Stack

- **Grafana:** http://grafana.local (admin/admin - **change password!**)
- **Prometheus:** http://prometheus.local
- **Alertmanager:** http://alertmanager.local

## Grafana Setup

### Add Prometheus Datasource

1. Login to http://grafana.local
2. Go **Configuration** → **Data Sources**
3. Click **Add data source**
4. Select **Prometheus**
5. Set URL: `http://kube-prometheus-stack-prometheus.monitoring:9090`
6. Click **Save & test**

### View ArgoCD Dashboard

1. Click **Dashboards** (left sidebar)
2. Navigate to **ArgoCD** folder
3. Open **ArgoCD Dashboard**

Data will populate automatically once Prometheus scrapes ArgoCD metrics (2-3 minutes).

## Troubleshooting

### Prometheus Pod Stuck in Pending

```bash
# Check PVC
kubectl get pvc -n monitoring
kubectl describe pvc -n monitoring

# If stuck, check storage class
kubectl get storageclass
# Should see "hostpath"

# Delete stuck PVC to retry
kubectl delete pvc -n monitoring <pvc-name>
```

### No Data in Grafana Dashboard

```bash
# Verify Prometheus is scraping
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090 → Status → Targets
# Search for "argocd" targets

# If no targets, verify ServiceMonitors exist
kubectl get servicemonitor -n argocd

# Check operator logs
kubectl logs -n monitoring -l app=kube-prometheus-stack-operator --tail=50
```

### CRD Annotation Errors

If you see errors about CRD annotation size:
```bash
# DO NOT use kubectl apply on Helm-rendered CRDs
# Instead, always use clean CRDs from upstream:
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml

# Or use ArgoCD with ServerSideApply=true sync option
```

## Maintenance

### Update Retention Policy

Edit `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml`:
```yaml
prometheus:
  prometheusSpec:
    retention: 30d  # Change from 15d to 30d
```

### Update Storage Size

```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 50Gi  # Increase from 10Gi
```

### Backup Metrics

```bash
# Export metrics for backup
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090 → Graph → Export
```

## Files Reference

- **Application:** `argocd/applications/infrastructure/kube-prometheus-stack-app.yaml`
- **ServiceMonitors:** `argocd/applications/infrastructure/argocd-servicemonitors.yaml`
- **Project:** `argocd/projects/monitoring-project.yaml`
- **Deployment Script:** `scripts/deploy-monitoring.ps1`

## Key Configuration Details

### Why `hostpath` storage class?
- Docker Desktop uses `hostpath` provisioner
- It mounts volumes from the host machine
- Simple but sufficient for development/testing
- For production, use cloud provider storage class

### Why `ServerSideApply=true`?
- Fixes Kubernetes API resource annotation size limits
- Allows Helm's large CRD annotations to be managed server-side
- Required for kube-prometheus-stack to work properly

### Why manual CRD installation?
- Helm's templated CRDs have bloated annotations
- Manual installation from prometheus-operator repo avoids annotation issues
- Cleaner separation between CRD management and Helm deployment

## Next Steps

1. ✅ Deploy monitoring stack (this guide)
2. ⬜ Configure alert notifications (email, Slack, PagerDuty)
3. ⬜ Create custom dashboards for your applications
4. ⬜ Set up PrometheusRules for custom alerts
5. ⬜ Configure persistent storage for production

