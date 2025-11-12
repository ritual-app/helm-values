# Setup GitHub Environment Variables for helm-values Repository

## Problem
The `render-manifests.yaml` workflow now fetches parameters from GCP Parameter Manager, but it needs GCP authentication credentials. These are configured as **environment variables** in the `dev` environment for individual service repositories, but the `helm-values` repository doesn't have this environment configured yet.

##  Solution: Configure `dev` Environment in helm-values Repository

You need to set up the `dev` environment in the `helm-values` repository with the same variables as your service repositories.

### Step 1: Create the `dev` Environment

1. Go to https://github.com/ritual-app/helm-values/settings/environments
2. Click **"New environment"**
3. Name it: `dev`
4. Click **"Configure environment"**

### Step 2: Add Environment Variables

Add the following variables to the `dev` environment:

| Variable Name | Value |
|---------------|-------|
| `WORKLOAD_IDENTITY_PROVIDER` | `projects/133792796607/locations/global/workloadIdentityPools/gh-actions/providers/gh-actions-provider` |
| `SERVICE_ACCOUNT` | `github-actions@infrastructure-422709.iam.gserviceaccount.com` |
| `PROJECT_ID` | `ritual-app-dev-104fc` |
| `REGION` | `us-east1` |
| `ARTIFACT_REGISTRY` | `us-east1-docker.pkg.dev/ritual-app-dev-104fc/docker` |

### Step 3: Verify the Setup

After configuring the environment:

1. Make a small change to any service's `values.yaml` in `helm-values/dev/`
2. Commit and push to trigger the `render-manifests` workflow
3. The workflow should now successfully:
   - Authenticate to GCP
   - Fetch parameters from Parameter Manager
   - Render Helm charts with both values.yaml and parameters
   - Push manifests to `rendered-manifests` repository

### Step 4: Test

```bash
cd /Users/nadavsvirsky/Documents/Ritual/k8s-repos/helm-values
echo "# Test parameter manager" >> dev/webhook-gateway-service/values.yaml
git add dev/webhook-gateway-service/values.yaml
git commit -m "test: Verify parameter manager integration"
git push
```

Then check the workflow: https://github.com/ritual-app/helm-values/actions

---

##  What Was Changed

✅ **Workflow updates:**
- Added GCP authentication step
- Added parameter fetching from GCP Parameter Manager
- Added YAML conversion for parameters
- Updated helm template command to use `--values ${PARAMS_FILE}`
- Added `environment: dev` to the job

✅ **Template version:**
- Updated `HELM_TEMPLATES_VERSION` from `v1.1.3` to `v1.3.2`
- New version includes `GCPBackendPolicy` support

✅ **Git handling:**
- Added `git pull --rebase` before pushing to handle parallel matrix jobs

---

##  Next Steps

After environment setup is complete:
1. Clean up test comments from values.yaml files
2. Trigger a deployment from one of the service repositories
3. Verify that ArgoCD picks up the updated manifests with parameters

---

## Reference Values

These are the same values configured in:
- `webhook-gateway-service` repository → Settings → Environments → dev
- `recording-consumer` repository → Settings → Environments → dev  
- `transcriber` repository → Settings → Environments → dev
- `insights-engine` repository → Settings → Environments → dev

