# Helm Values

Service-specific Kubernetes configuration for all environments.

## 🎯 Purpose

This repository contains **complete Kubernetes configuration** for each service in each environment:
- `dev/` - Development environment configs
- `prod/` - Production environment configs
- `dynamic/` - PR/feature environment configs (auto-created by CI/CD)

## 📁 Structure

```
helm-values/
├── dev/
│   ├── recording-webhook/
│   │   └── values.yaml          # Complete K8s config for dev
│   ├── transcriber/
│   │   └── values.yaml
│   └── ...
│
├── prod/
│   ├── recording-webhook/
│   │   └── values.yaml          # Complete K8s config for prod
│   └── ...
│
└── dynamic/
    ├── recording-webhook-pr-123/
    │   └── values.yaml          # Auto-created by CI/CD
    └── ...
```

## 📝 What Goes in values.yaml?

**Everything** except the image tag:
- ✅ Resources (CPU, memory)
- ✅ Replicas, autoscaling
- ✅ Environment variables
- ✅ Secrets configuration
- ✅ Ingress, domains, certificates
- ✅ Service account
- ✅ Health checks
- ✅ Network policies
- ✅ Labels, annotations
- ❌ Image tag (injected by CI/CD)

## 🔄 How It Works

1. **Developer** updates `values.yaml` to change K8s configuration
2. **Developer** commits and pushes to `helm-values` repo
3. **CI/CD** renders templates:
   ```bash
   helm template recording-webhook helm-templates/dev \
     --values helm-values/dev/recording-webhook/values.yaml \
     --set image.tag=main-abc123 \          # CI/CD injects tag
     --set image.repository=us-east1-docker.pkg.dev/...
   ```
4. **CI/CD** pushes rendered manifests to `rendered-manifests` repo
5. **ArgoCD** syncs and deploys

## 🚫 What CI/CD Does NOT Change

CI/CD **only** injects the `image.tag` during rendering. It **never** commits to this repo.

### Before:
```yaml
image:
  repository: us-east1-docker.pkg.dev/ritual-app-dev-104fc/recording-webhook
  # tag is injected by CI/CD
```

### During Rendering:
```bash
--set image.tag=main-abc123
```

### Result (in rendered-manifests):
```yaml
image: us-east1-docker.pkg.dev/ritual-app-dev-104fc/recording-webhook:main-abc123
```

## 📦 Example: recording-webhook

### Dev (`dev/recording-webhook/values.yaml`):
```yaml
replicaCount: 1
resources:
  requests:
    cpu: 100m
    memory: 256Mi
env:
  - name: LOG_LEVEL
    value: debug
ingress:
  hosts:
    - host: recording-webhook.dev.ourritual.com
```

### Prod (`prod/recording-webhook/values.yaml`):
```yaml
replicaCount: 2
resources:
  requests:
    cpu: 500m
    memory: 512Mi
env:
  - name: LOG_LEVEL
    value: info
ingress:
  hosts:
    - host: recording-webhook.ourritual.com
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

## 🆕 Adding a New Service

1. Create directory structure:
   ```bash
   mkdir -p dev/my-service
   mkdir -p prod/my-service
   ```

2. Create `dev/my-service/values.yaml` (copy from existing service)

3. Create `prod/my-service/values.yaml` (adjust for prod)

4. Commit and push

5. CI/CD will automatically pick it up on next deployment

## ✏️ Modifying Configuration

To change a service's configuration:

1. Edit `dev/my-service/values.yaml` or `prod/my-service/values.yaml`
2. Commit and push
3. CI/CD will render new manifests on next deployment
4. ArgoCD will detect changes and sync

**Note**: Changes to this repo don't trigger deployments. Deployments are triggered by code pushes to service repos.

## 🔐 Secrets

Secrets are **not** stored in this repo. We use Google Secret Manager:

```yaml
secrets:
  - name: DATABASE_PASSWORD
    secretManagerRef:
      name: my-service-db-password
      version: latest
```

## 🧪 Testing Values Locally

```bash
# Clone repos
git clone https://github.com/ritual-app/helm-templates.git
git clone https://github.com/ritual-app/helm-values.git

# Render templates
helm template recording-webhook helm-templates/dev \
  --values helm-values/dev/recording-webhook/values.yaml \
  --set image.tag=test-123 \
  --set image.repository=us-east1-docker.pkg.dev/ritual-app-dev-104fc/recording-webhook \
  --namespace dev \
  --debug

# Validate output
helm template ... | kubectl apply --dry-run=client -f -
```

## 🔗 Related Repositories

- **helm-templates**: Generic Helm templates for dev/prod/dynamic
- **rendered-manifests**: Rendered K8s manifests (auto-generated)
- **shared-workflows**: CI/CD logic

## 📚 Service Documentation

Each service should have a README or wiki page documenting:
- What the service does
- Environment-specific configuration
- Required secrets
- Dependencies

---

**Maintained by**: Dev Teams (each team owns their service's values)

