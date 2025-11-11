#!/bin/bash

# Swagger IAP Setup Helper Script
# Run this after creating OAuth client

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 Swagger IAP Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if OAuth credentials are provided
if [ -z "$OAUTH_CLIENT_ID" ] || [ -z "$OAUTH_CLIENT_SECRET" ]; then
  echo "❌ Error: OAuth credentials not provided"
  echo ""
  echo "Usage:"
  echo "  OAUTH_CLIENT_ID=your-client-id \\"
  echo "  OAUTH_CLIENT_SECRET=your-client-secret \\"
  echo "  ./setup-swagger-iap.sh"
  echo ""
  exit 1
fi

echo "✅ OAuth credentials provided"
echo ""

# Step 1: Create Kubernetes secret
echo "📦 Step 1: Creating Kubernetes secret..."
kubectl create secret generic swagger-iap-oauth \
  --from-literal=client_id="$OAUTH_CLIENT_ID" \
  --from-literal=client_secret="$OAUTH_CLIENT_SECRET" \
  -n dev \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret created/updated"
echo ""

# Step 2: Wait for backend service
echo "⏳ Step 2: Waiting for backend service to be created..."
echo "   (This may take 3-5 minutes after gateway is provisioned)"
echo ""

MAX_WAIT=300  # 5 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  BACKEND_SERVICE=$(gcloud compute backend-services list \
    --project=ritual-app-dev-104fc \
    --filter="name~swagger-gateway" \
    --format="value(name)" 2>/dev/null || echo "")
  
  if [ -n "$BACKEND_SERVICE" ]; then
    echo "✅ Backend service found: $BACKEND_SERVICE"
    break
  fi
  
  echo "   Still waiting... (${ELAPSED}s elapsed)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [ -z "$BACKEND_SERVICE" ]; then
  echo "❌ Backend service not found after ${MAX_WAIT}s"
  echo "   The gateway may still be provisioning."
  echo "   Check status: kubectl get gateway swagger-gateway -n dev"
  exit 1
fi

echo ""

# Step 3: Configure IAM for gcp_admin@heyritual.com
echo "🔑 Step 3: Granting IAP access to gcp_admin@heyritual.com..."
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service="$BACKEND_SERVICE" \
  --member=group:gcp_admin@heyritual.com \
  --role=roles/iap.httpsResourceAccessor \
  --project=ritual-app-dev-104fc

echo "✅ Access granted to gcp_admin@heyritual.com"
echo ""

# Step 4: Configure IAM for gcp_developers@heyritual.com
echo "🔑 Step 4: Granting IAP access to gcp_developers@heyritual.com..."
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service="$BACKEND_SERVICE" \
  --member=group:gcp_developers@heyritual.com \
  --role=roles/iap.httpsResourceAccessor \
  --project=ritual-app-dev-104fc

echo "✅ Access granted to gcp_developers@heyritual.com"
echo ""

# Step 5: Verify setup
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ IAP SETUP COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Verification:"
echo ""
echo "1. Check IAM policy:"
echo "   gcloud iap web get-iam-policy \\"
echo "     --resource-type=backend-services \\"
echo "     --service=$BACKEND_SERVICE \\"
echo "     --project=ritual-app-dev-104fc"
echo ""
echo "2. Test swagger access:"
echo "   https://swagger.dev.ourritual.com/webhook-gateway-service"
echo ""
echo "3. Verify public endpoint blocks swagger:"
echo "   curl https://webhooks.dev.ourritual.com/swagger"
echo "   (Should return 403)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

