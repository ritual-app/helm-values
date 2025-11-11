# Swagger Gateway Setup Guide

## Overview

This guide sets up a unified Swagger/API documentation endpoint at `swagger.dev.ourritual.com` with:
- **Path-based routing** to multiple services
- **GCP IAP protection** (only `gcp_developer@ourritual.com` members)
- **Future VPN IP allowlist** support

## Architecture

```
swagger.dev.ourritual.com
├── /webhook-gateway-service → webhook-gateway-service:8080/swagger
├── /transcriber → transcriber:8080/swagger
├── /recording-consumer → recording-consumer:8080/swagger
└── /insights-engine → insights-engine:8080/swagger
```

All traffic goes through:
1. **Shared Gateway** (`swagger-gateway`) - single L7 load balancer
2. **IAP** - authenticates users
3. **HTTPRoute** - routes to backend services based on path
4. **URL rewriting** - rewrites `/service-name/*` to `/swagger/*`

---

## Setup Steps

### Step 1: Create GCP Resources

#### 1.1 Create Static IP

```bash
gcloud compute addresses create swagger-dev-ip \
  --global \
  --project=ritual-app-dev-104fc

# Get the IP address
gcloud compute addresses describe swagger-dev-ip \
  --global \
  --project=ritual-app-dev-104fc \
  --format="get(address)"
```

#### 1.2 Create DNS Record

Create A record in Cloud DNS (or your DNS provider):
```
swagger.dev.ourritual.com → <static-ip-from-above>
```

#### 1.3 Create OAuth Credentials for IAP

1. Go to: https://console.cloud.google.com/apis/credentials?project=ritual-app-dev-104fc
2. Click **Create Credentials** → **OAuth client ID**
3. Application type: **Web application**
4. Name: `swagger-gateway-iap`
5. Authorized redirect URIs:
   ```
   https://swagger.dev.ourritual.com/_gcp_gatekeeper/authenticate
   ```
6. Click **Create**
7. Save the **Client ID** and **Client Secret**

#### 1.4 Create Kubernetes Secret for OAuth

```bash
kubectl create secret generic swagger-iap-oauth \
  --from-literal=client_id=<CLIENT_ID> \
  --from-literal=client_secret=<CLIENT_SECRET> \
  -n dev
```

---

### Step 2: Apply Shared Gateway

```bash
# Apply the shared gateway (one-time)
kubectl apply -f k8s-repos/helm-values/dev/_shared/swagger-gateway.yaml

# Wait for external IP assignment (~2-3 minutes)
kubectl get gateway swagger-gateway -n dev -w
```

---

### Step 3: Configure IAM for IAP

Add members to IAP access:

```bash
# Get the Backend Service name (created by Gateway)
# It will be something like: gkegw-<hash>-default-swagger-gateway-http
BACKEND_SERVICE=$(gcloud compute backend-services list \
  --project=ritual-app-dev-104fc \
  --filter="name~swagger-gateway" \
  --format="value(name)")

# Grant IAP access to gcp_developer@ourritual.com
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service=$BACKEND_SERVICE \
  --member=group:gcp_developer@ourritual.com \
  --role=roles/iap.httpsResourceAccessor \
  --project=ritual-app-dev-104fc
```

---

### Step 4: Update Each Service's values.yaml

For each service (webhook-gateway-service, transcriber, recording-consumer, insights-engine):

#### Option A: Merge swagger config into main values.yaml

Add to `helm-values/dev/<service>/values.yaml`:

```yaml
# Gateway configuration - attach to shared swagger gateway
gateway:
  enabled: true
  
  sharedGateway:
    name: swagger-gateway
    namespace: dev
  
  hosts:
    - host: swagger.dev.ourritual.com
  
  pathPrefix: /<service-name>  # e.g., /webhook-gateway-service
  
  urlRewrite:
    type: ReplacePrefixMatch
    path: /swagger
  
  staticIPName: null
  certificate:
    enabled: false

# BackendConfig for IAP
backendConfig:
  enabled: true
  iap:
    enabled: true
    oauthSecretName: swagger-iap-oauth
  healthCheck:
    checkIntervalSec: 10
    timeoutSec: 5
    healthyThreshold: 2
    unhealthyThreshold: 3
    type: HTTP
    requestPath: /health
    port: 8080
  sessionAffinity:
    affinityType: CLIENT_IP
    affinityCookieTtlSec: 3600
  timeoutSec: 30
```

#### Option B: Use separate values file (recommended for testing)

Create `values.swagger.yaml` for each service (already created example for webhook-gateway-service).

During CI/CD, merge with main values:
```bash
helm template <service> \
  --values values.yaml \
  --values values.swagger.yaml \
  ...
```

---

### Step 5: Update Helm Templates Version

Tag and release new helm-templates version:

```bash
cd k8s-repos/helm-templates
git add dev/templates/httproute.yaml
git add dev/templates/backendconfig.yaml
git add dev/templates/service.yaml
git commit -m "feat: Add shared gateway support with IAP and path-based routing"
git tag v1.3.0
git push && git push --tags
```

Update CI/CD to use v1.3.0:
```yaml
# shared-github-actions/.github/workflows/dev-deploy.yaml
HELM_TEMPLATES_VERSION: v1.3.0
```

---

### Step 6: Deploy Services

Trigger deployments for all 4 services to apply the new configuration.

---

## Testing

### Test Access (Without IAP)

First, verify routing works:

```bash
# Should redirect to OAuth login if IAP is enabled
curl -I https://swagger.dev.ourritual.com/webhook-gateway-service

# Test each service
curl -I https://swagger.dev.ourritual.com/transcriber
curl -I https://swagger.dev.ourritual.com/recording-consumer
curl -I https://swagger.dev.ourritual.com/insights-engine
```

### Test IAP Access

1. Open browser (logged in as member of `gcp_developer@ourritual.com`)
2. Navigate to: https://swagger.dev.ourritual.com/webhook-gateway-service
3. Should see Swagger UI
4. Test other services

### Test from Non-Authorized User

Use incognito window or different account:
- Should see "Access Denied" from IAP

---

## Troubleshooting

### Gateway not getting external IP

```bash
kubectl describe gateway swagger-gateway -n dev
# Check events for errors
```

### Certificate not provisioning

```bash
kubectl describe managedcertificate swagger-gateway-cert -n dev
# DNS must be pointing to Gateway IP
# Can take 15-60 minutes
```

### IAP not working

1. Check Backend Service has IAP enabled:
```bash
gcloud compute backend-services describe <backend-service> \
  --global \
  --project=ritual-app-dev-104fc \
  --format="get(iap)"
```

2. Check IAM bindings:
```bash
gcloud iap web get-iam-policy \
  --resource-type=backend-services \
  --service=<backend-service> \
  --project=ritual-app-dev-104fc
```

3. Check secret exists:
```bash
kubectl get secret swagger-iap-oauth -n dev
```

### Service not routing correctly

Check HTTPRoute status:
```bash
kubectl get httproute <service>-microservice -n dev -o yaml
```

Check if service exists:
```bash
kubectl get service <service>-microservice -n dev
```

---

## Adding VPN IP Allowlist (Future)

### Create Cloud Armor Policy

```bash
gcloud compute security-policies create swagger-vpn-policy \
  --description="Allow only VPN IPs to access swagger" \
  --project=ritual-app-dev-104fc

# Add VPN IP ranges
gcloud compute security-policies rules create 1000 \
  --security-policy=swagger-vpn-policy \
  --expression="inIpRange(origin.ip, '10.0.0.0/8')" \
  --action=allow \
  --description="Allow VPN IPs" \
  --project=ritual-app-dev-104fc

# Deny all other traffic
gcloud compute security-policies rules create 2147483647 \
  --security-policy=swagger-vpn-policy \
  --action=deny-403 \
  --description="Deny all other traffic" \
  --project=ritual-app-dev-104fc
```

### Update BackendConfig

Add to each service's values.yaml:
```yaml
backendConfig:
  enabled: true
  securityPolicy: swagger-vpn-policy
  iap:
    enabled: true
    oauthSecretName: swagger-iap-oauth
```

---

## Service-Specific Notes

### FastAPI Services (webhook-gateway-service, transcriber, recording-consumer, insights-engine)

- Swagger endpoint: `/swagger`
- Docs endpoint: `/docs`
- OpenAPI spec: `/openapi.json`

All work with the current configuration.

### Non-FastAPI Services

If you add services with different swagger paths (e.g., `/api-docs`):

Update `urlRewrite.path` in values.yaml:
```yaml
gateway:
  pathPrefix: /my-service
  urlRewrite:
    type: ReplacePrefixMatch
    path: /api-docs  # Custom path for this service
```

---

## Maintenance

### Adding New Service

1. Create `values.swagger.yaml` for the service
2. Set unique `pathPrefix` (e.g., `/new-service`)
3. Deploy service
4. Test access

### Updating IAP Members

```bash
# Add member
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service=$BACKEND_SERVICE \
  --member=user:email@example.com \
  --role=roles/iap.httpsResourceAccessor \
  --project=ritual-app-dev-104fc

# Remove member
gcloud iap web remove-iam-policy-binding \
  --resource-type=backend-services \
  --service=$BACKEND_SERVICE \
  --member=user:email@example.com \
  --role=roles/iap.httpsResourceAccessor \
  --project=ritual-app-dev-104fc
```

### Monitoring

Check Gateway metrics:
- https://console.cloud.google.com/net-services/gateways/list?project=ritual-app-dev-104fc

Check IAP access logs:
```bash
gcloud logging read "resource.type=k8s_service AND jsonPayload.iap_decision" \
  --project=ritual-app-dev-104fc \
  --limit=50
```

---

## Summary

✅ Single domain: `swagger.dev.ourritual.com`
✅ Path-based routing to multiple services
✅ IAP protection (gcp_developer@ourritual.com)
✅ Maintainable via Helm values
✅ Each service manages its own swagger configuration
✅ Ready for VPN IP allowlist

Questions? Contact the platform/DevOps team.

