# External Secrets Operator (ESO) Setup

This directory contains the configuration for integrating with AWS Secrets Manager via External Secrets Operator.

## Architecture

1. **Manual Setup**: Create AWS credentials as a Kubernetes secret on the deployment machine
2. **ESO Installation**: ArgoCD deploys External Secrets Operator via Helm
3. **SecretStore**: ESO connects to AWS Secrets Manager using the manual credentials
4. **ExternalSecret**: ESO fetches secrets from AWS and syncs them to Kubernetes Secret
5. **Deployment**: CFB pods use the synced Secret

## Manual Steps to Enable

### 1. Create AWS IAM User

Create an IAM user with permissions to read from Secrets Manager:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:cfb/*"
    }
  ]
}
```

### 2. Create AWS Secrets in Secrets Manager

Create secrets with the following paths:

- `cfb/dev/cfbd-api-key` → Your dev API key
- `cfb/dev/redis-addr` → Your dev Redis address (e.g., `redis.local:6379`)
- `cfb/qa/cfbd-api-key` → Your QA API key
- `cfb/qa/redis-addr` → Your QA Redis address
- `cfb/staging/cfbd-api-key` → Your staging API key
- `cfb/staging/redis-addr` → Your staging Redis address
- `cfb/prod/cfbd-api-key` → Your prod API key
- `cfb/prod/redis-addr` → Your prod Redis address

### 3. Create Manual Kubernetes Secret with AWS Credentials

**On your deployment machine**, create the AWS credentials secret:

```powershell
kubectl create secret generic aws-credentials \
  --from-literal=accessKeyID=YOUR_AWS_ACCESS_KEY \
  --from-literal=secretAccessKey=YOUR_AWS_SECRET_KEY \
  -n external-secrets
```

This secret must exist **before** ESO can authenticate to AWS.

### 4. Enable ESO in your environment

Update the values file (e.g., `cfb/helm/values-dev.yaml`):

```yaml
externalSecrets:
  enabled: true
  awsRegion: us-east-1
  secretNames:
    cfbdApiKey: cfb/dev/cfbd-api-key
    redisAddr: cfb/dev/redis-addr
```

### 5. Deploy

```powershell
# Install ESO
kubectl apply -f argocd/external-secrets-operator-app.yaml

# Sync CFB applications (they will now use ESO)
kubectl patch application cfb-dev -n argocd --type merge -p '{"metadata":{"annotations":{"sync-trigger":"'$(Get-Date -Format 'yyyyMMddHHmmss')'"}}}'
```

## Verification

```powershell
# Check ESO is installed
kubectl get pods -n external-secrets

# Check SecretStore is configured
kubectl get secretstore -n dev

# Check ExternalSecret synced
kubectl get externalsecret -n dev

# Check the secret was created/synced
kubectl get secret cfb-secrets -n dev
kubectl describe secret cfb-secrets -n dev
```

## AWS Credentials Secret Format

The manual Kubernetes secret must contain:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: external-secrets
type: Opaque
stringData:
  accessKeyID: "YOUR_ACCESS_KEY"
  secretAccessKey: "YOUR_SECRET_KEY"
```

## Troubleshooting

**ExternalSecret stuck in "Pending":**
```powershell
kubectl describe externalsecret cfb-external-secrets -n dev
```

**SecretStore authentication failed:**
- Verify AWS credentials secret exists: `kubectl get secret aws-credentials -n external-secrets`
- Verify IAM user has Secrets Manager permissions
- Check ESO logs: `kubectl logs -n external-secrets -l app=external-secrets`

**Secret not updating:**
- ESO checks every 1 hour by default
- Force refresh by deleting the pod: `kubectl delete pod -n dev -l app=cfb`
