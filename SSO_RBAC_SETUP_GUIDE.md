# ArgoCD SSO + RBAC Setup Guide

## Current Status
✅ RBAC foundation created (argocd-rbac-cm.yaml)
✅ DevTest project created
✅ Counting-dev application created in DevTest project
⬜ SSO integration (pending)

## Architecture Overview

### Roles Defined
1. **role:admin** - Full access to all projects and applications
2. **role:viewer** - Read-only access to all projects
3. **role:devtest-viewer** - Can only view DevTest project applications
4. **role:readonly** - Minimal read-only access (default for unauthenticated)

## How It Will Work

### User Permissions After SSO Setup

**User A (Admin Group)**
- Maps to: `role:admin`
- Can: View/manage all applications across all projects
- Projects: default, monitoring, devtest, etc.

**User B (DevTest Group)**
- Maps to: `role:devtest-viewer`
- Can: Only view applications in the DevTest project
- Can access: counting-dev, and any future apps in devtest project
- Cannot: View apps in monitoring, default, or other projects

## SSO Integration Steps (To Do Later)

### Step 1: Configure ArgoCD to Use SSO

Update argocd-server deployment with SSO provider settings. Common providers:
- **OAuth2 (GitHub, GitLab, Google)**
- **SAML2 (Microsoft Entra, Okta)**
- **LDAP (Active Directory)**

Example for GitHub OAuth:
```yaml
# In argocd-cmd-params-cm ConfigMap
url: https://argocd.example.com
oidc.config: |
  name: GitHub
  issuer: https://token.actions.githubusercontent.com
  clientID: <YOUR_CLIENT_ID>
  clientSecret: <YOUR_CLIENT_SECRET>
  requestedScopes:
    - openid
    - profile
    - email
    - groups
```

### Step 2: Update RBAC ConfigMap with User Mappings

Uncomment and update the role bindings in argocd-rbac-cm.yaml:

```yaml
# For GitHub OAuth with org teams:
g, yourorg:admin-team, role:admin
g, yourorg:devtest-team, role:devtest-viewer

# For SAML with groups:
g, admin-group, role:admin
g, devtest-group, role:devtest-viewer

# For OIDC with email patterns:
g, admin@yourdomain.com, role:admin
g, devtest@yourdomain.com, role:devtest-viewer
```

### Step 3: Configure RBAC Scopes

In argocd-rbac-cm.yaml, uncomment and set:
```yaml
data:
  scopes: '[groups, email]'
```

This tells ArgoCD which JWT/SAML claims to use for RBAC lookups.

## Testing RBAC After SSO Setup

### Test as Admin User
```bash
# Should see all apps
argocd app list

# Should be able to modify any app
argocd app sync <any-app>
```

### Test as DevTest User
```bash
# Should only see counting-dev
argocd app list
# Output: counting-dev

# Should get error trying to access other projects
argocd app info hello-dev
# Error: application not found or permission denied
```

## Adding New Applications to Controlled Projects

### To add an app visible only to specific users:
1. Create the AppProject (like we did with devtest)
2. Create the Application in that project
3. Add a new role in RBAC:
   ```yaml
   p, role:myproject-viewer, applications, get, myproject/*, allow
   ```
4. Bind the role in SSO integration:
   ```yaml
   g, myproject-group, role:myproject-viewer
   ```

## Files Involved

- **argocd/argocd-rbac-cm.yaml** - RBAC policies and roles
- **argocd/projects/devtest-project.yaml** - DevTest project (existing)
- **argocd/applications/counting/counting-dev-app.yaml** - Counting app (existing)

## SSO Provider Options

### GitHub (Easiest for GitHub-based teams)
- Uses GitHub org teams for groups
- Requires: GitHub app, org membership
- Setup time: ~30 minutes

### GitLab
- Uses GitLab groups
- Requires: GitLab instance access, app token
- Setup time: ~30 minutes

### Microsoft Entra (Azure AD)
- Enterprise-grade SAML
- Requires: Azure tenant, app registration
- Setup time: ~1 hour

### Okta
- Enterprise SAML/OIDC
- Requires: Okta tenant, app setup
- Setup time: ~1 hour

## Current Files to Deploy

```bash
# Apply RBAC configuration
kubectl apply -f argocd/argocd-rbac-cm.yaml

# Verify
kubectl get configmap -n argocd | grep rbac
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
```

## Next Steps

1. ✅ RBAC foundation is ready
2. ⬜ Choose your SSO provider
3. ⬜ Configure SSO in ArgoCD
4. ⬜ Update RBAC ConfigMap with user/group mappings
5. ⬜ Test user access levels

## Documentation References

- ArgoCD SSO Docs: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/
- RBAC Docs: https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/
- OAuth2 Proxy: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#oauth2-proxy

## Questions to Answer When Choosing SSO

1. What's your existing identity provider? (GitHub, Azure AD, Okta, LDAP?)
2. Do you need group-based access control?
3. What's your team structure? (Org teams, AD groups, etc.)
4. Do you need audit logging of who accessed what?

Once you answer these, the SSO setup will be straightforward!
