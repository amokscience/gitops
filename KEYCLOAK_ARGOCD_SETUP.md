# ArgoCD Keycloak SSO Setup Guide

## Overview

This guide covers integrating Keycloak with ArgoCD for SSO authentication. Users will log in with their Keycloak credentials and have permissions managed through Keycloak groups mapped to ArgoCD roles.

## Prerequisites

- Keycloak running at `https://keycloak.local:8443`
- ArgoCD installed (see ARGOCD_DEPLOYMENT.md)
- kubectl access to the cluster
- Keycloak admin access to create OIDC client

## Step 1: Create OIDC Client in Keycloak

### 1.1 Access Keycloak Admin Console
```
https://keycloak.local:8443/admin
```

### 1.2 Create a New Client

1. Select your realm (or use "master")
2. Go to **Clients** → **Create**
3. Set **Client ID** to: `argocd`
4. Choose **OpenID Connect** as the protocol
5. Click **Next** and then **Save**

### 1.3 Configure Client Settings

In the client details page:

**Access Settings:**
- **Root URL:** `https://argocd.local`
- **Valid Redirect URIs:** `https://argocd.local/auth/callback`
- **Web Origins:** `https://argocd.local`

**Capability Config:**
- ✅ Standard Flow Enabled
- ✅ Direct Access Grants Enabled
- ❌ Implicit Flow Enabled (disable)
- ❌ Service Accounts Enabled (disable unless needed)

**Authentication Flow:**
- Uncheck unnecessary flows, keep:
  - ✅ Browser
  - ✅ Direct Grant Flow

Click **Save**

### 1.4 Create Client Secret

Go to **Credentials** tab:
1. Copy the **Client Secret** value
2. This will be used in the next step

### 1.5 Add Groups Claim

Go to **Client Scopes** tab:
1. Click on `argocd-dedicated` (or the dedicated scope)
2. Go to **Mappers** → **Create**
3. Configure:
   - **Mapper Type:** Group Membership
   - **Name:** groups
   - **Token Claim Name:** groups
   - **Full group path:** ON (recommended)
4. Click **Save**

Alternatively, add to default scope:
1. Go to realm **Default Client Scopes**
2. Find `roles` scope
3. Go to **Mappers**
4. Create a Group Membership mapper if not present

## Step 2: Create Keycloak Groups

In Keycloak, create groups for ArgoCD role mapping:

1. **argocd-admins** - Users with admin access
2. **argocd-viewers** - Users with read-only access  
3. **devtest-developers** - Users with devtest project access

Go to **Groups** → **Create Group** for each.

## Step 3: Update ArgoCD Configuration

### 3.1 Create the Client Secret in Kubernetes

**⚠️ IMPORTANT: Do NOT commit secrets to git!**

Create the secret manually in the cluster:

```powershell
kubectl create secret generic argocd-oidc-keycloak `
  --from-literal=client-secret=YOUR_KEYCLOAK_CLIENT_SECRET_HERE `
  -n argocd
```

Replace `YOUR_KEYCLOAK_CLIENT_SECRET_HERE` with the secret from Step 1.4.

### 3.2 Deploy OIDC Configuration

```powershell
kubectl apply -f c:\code\gitops\argocd\argocd-oidc-configmap.yaml
kubectl apply -f c:\code\gitops\argocd\argocd-rbac-cm.yaml
```

### 3.3 Update ArgoCD Helm Values

Edit `argocd/argocd-install/values.yaml` and add under `configs`:

```yaml
configs:
  cm:
    oidc.config: |
      name: Keycloak
      issuer: https://keycloak.local:8443/realms/master
      clientID: argocd
      clientSecret: $argocd-oidc-keycloak:client-secret
      requestedScopes:
        - openid
        - profile
        - email
        - groups
      requestedIDTokenClaims:
        groups:
          essential: true
```

Also set the RBAC ConfigMap:

```yaml
  rbac:
    policy.default: role:viewer
    policy.csv: |
      # (see argocd-rbac-cm.yaml for full config)
      g, argocd-admins, role:admin
      g, argocd-viewers, role:viewer
      g, devtest-developers, role:devtest-viewer
```

### 3.4 Upgrade ArgoCD

```powershell
helm upgrade argocd argo/argo-cd `
  --namespace argocd `
  --values c:\code\gitops\argocd\argocd-install\values.yaml
```

## Step 4: Assign Users to Groups

In Keycloak:

1. Go to **Users**
2. Select a user
3. Go to **Groups** tab
4. Click **Join Group**
5. Select the appropriate group (argocd-admins, argocd-viewers, or devtest-developers)
6. Click **Join**

## Step 5: Test SSO Login

1. Open ArgoCD: `https://argocd.local`
2. Click **LOGIN VIA KEYCLOAK**
3. Enter Keycloak credentials
4. You should be redirected back to ArgoCD with appropriate permissions based on your group membership

## Troubleshooting

### "Login failed" or "Invalid client"

**Check:**
1. Client ID in Keycloak is `argocd`
2. Client secret in secret matches Keycloak
3. Redirect URI includes `https://argocd.local/auth/callback`

### Groups not appearing

**Check:**
1. Group mapper is configured in client scopes
2. User is assigned to groups in Keycloak
3. ArgoCD RBAC ConfigMap includes the group mappings

**Verify groups in token:**
```powershell
# Check OIDC token claims
# In ArgoCD UI: Settings → Users → [your user] → check "groups" claim
```

### RBAC not working

**Check:**
1. RBAC ConfigMap is deployed: `kubectl get cm argocd-rbac-cm -n argocd`
2. Group name in ConfigMap matches Keycloak group exactly
3. Restart ArgoCD server pods after ConfigMap changes:
```powershell
kubectl rollout restart deployment/argocd-server -n argocd
```

### Redirect loop or certificate errors

If using self-signed Keycloak cert:

```powershell
# Insecure mode (development only!)
kubectl set env deployment/argocd-server -n argocd \
  ARGOCD_INSECURE_SKIP_VERIFY=true
```

Better: Add Keycloak cert to ArgoCD trusted certs (see ArgoCD docs for production setup).

## RBAC Roles Reference

### role:admin
- Full access to all projects and resources
- Can create/delete applications
- Can sync and manage repositories
- Can manage clusters and accounts

### role:viewer
- Read-only access to all projects
- Cannot modify or sync applications
- Can view logs and application details

### role:devtest-viewer
- Read-only access to `devtest` project only
- Cannot access other projects
- Can view devtest application logs

## Adding New Groups

To add a new Keycloak group with ArgoCD access:

1. Create group in Keycloak under **Groups**
2. Update `argocd-rbac-cm.yaml` with group mapping
3. Deploy: `kubectl apply -f c:\code\gitops\argocd\argocd-rbac-cm.yaml`
4. Restart ArgoCD server: `kubectl rollout restart deployment/argocd-server -n argocd`

Example - add DevOps team with admin access:
```yaml
g, devops-team, role:admin
```

## Logout / Token Refresh

Users can log out from ArgoCD. Sessions are based on OIDC token lifetime configured in Keycloak (default 5 minutes for access token).

To change token lifetime in Keycloak:
1. Go to **Realm Settings** → **Tokens**
2. Adjust **Access Token Lifespan** (default 5 minutes)

## References

- [ArgoCD OIDC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/)
- [Keycloak Client Documentation](https://www.keycloak.org/docs/latest/server_admin/)
- [ArgoCD RBAC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)

## Files Modified/Created

- `argocd/secrets/keycloak-oidc-secret.yaml` - Client secret storage
- `argocd/argocd-oidc-configmap.yaml` - OIDC configuration
- `argocd/argocd-rbac-cm.yaml` - RBAC role mappings
- `argocd/argocd-install/values.yaml` - (update needed)
- `KEYCLOAK_ARGOCD_SETUP.md` - This documentation
