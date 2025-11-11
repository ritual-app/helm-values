# Swagger Security Middleware for FastAPI

## Problem

Services are accessible on multiple domains:
- **Public**: `webhooks.dev.ourritual.com` - Should NOT have /swagger access
- **Swagger Gateway**: `swagger.dev.ourritual.com` - Protected by IAP, should have /swagger access

Without protection, `/swagger` would be publicly accessible on both domains.

## Solution: FastAPI Middleware

Add this middleware to your FastAPI app to block `/swagger` access on non-swagger domains:

### Code

Add to `src/main.py` (or equivalent):

```python
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
import logging

logger = logging.getLogger(__name__)

# Allowed hosts for swagger/docs access
SWAGGER_ALLOWED_HOSTS = [
    "swagger.dev.ourritual.com",
    "localhost",
    "127.0.0.1",
]

@app.middleware("http")
async def swagger_security_middleware(request: Request, call_next):
    """
    Block access to /swagger, /docs, /redoc, /openapi.json on non-swagger domains.
    
    This ensures that API documentation is ONLY accessible via swagger.dev.ourritual.com
    which is protected by GCP IAP, not via public endpoints.
    """
    path = request.url.path.lower()
    
    # Check if accessing swagger/docs endpoints
    swagger_paths = ["/swagger", "/docs", "/redoc", "/openapi.json"]
    is_swagger_path = any(path.startswith(p) for p in swagger_paths)
    
    if is_swagger_path:
        # Get the Host header
        host = request.headers.get("host", "").lower()
        
        # Remove port if present
        host_without_port = host.split(":")[0]
        
        # Check if host is allowed
        if host_without_port not in SWAGGER_ALLOWED_HOSTS:
            logger.warning(
                f"Blocked swagger access from unauthorized host: {host} "
                f"(path: {path})"
            )
            return JSONResponse(
                status_code=403,
                content={
                    "detail": "Swagger/API documentation access is restricted. "
                              "Please use swagger.dev.ourritual.com"
                },
            )
    
    # Continue to the actual endpoint
    response = await call_next(request)
    return response
```

### Placement

Add this middleware **after** creating the FastAPI app but **before** including routers:

```python
from fastapi import FastAPI

app = FastAPI()

# Add swagger security middleware HERE
@app.middleware("http")
async def swagger_security_middleware(request: Request, call_next):
    # ... (code from above)

# Then add your routers
app.include_router(webhook_router)
# etc.
```

### Testing

```bash
# Should work (via swagger gateway)
curl https://swagger.dev.ourritual.com/webhook-gateway-service

# Should return 403 (public endpoint)
curl https://webhooks.dev.ourritual.com/swagger
# Response: {"detail": "Swagger/API documentation access is restricted..."}

# Normal webhook endpoints should still work
curl https://webhooks.dev.ourritual.com/webhook/endpoint
# Response: (normal webhook response)
```

## Alternative: Environment-Specific Configuration

If you want to enable/disable swagger dynamically:

```python
import os
from fastapi import FastAPI

# Read from environment
ENABLE_PUBLIC_SWAGGER = os.getenv("ENABLE_PUBLIC_SWAGGER", "false").lower() == "true"
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")

if ENVIRONMENT == "prod":
    # Production: Always block public swagger
    SWAGGER_ALLOWED_HOSTS = ["swagger.ourritual.com"]
else:
    # Dev: Allow swagger.dev and localhost
    SWAGGER_ALLOWED_HOSTS = ["swagger.dev.ourritual.com", "localhost", "127.0.0.1"]

@app.middleware("http")
async def swagger_security_middleware(request: Request, call_next):
    if ENABLE_PUBLIC_SWAGGER:
        # Bypass security if explicitly enabled (for testing)
        return await call_next(request)
    
    # ... (rest of middleware code)
```

## For Non-FastAPI Frameworks

### Flask

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

SWAGGER_ALLOWED_HOSTS = ["swagger.dev.ourritual.com", "localhost"]

@app.before_request
def swagger_security():
    path = request.path.lower()
    swagger_paths = ["/swagger", "/docs", "/api-docs", "/openapi.json"]
    
    if any(path.startswith(p) for p in swagger_paths):
        host = request.headers.get("Host", "").lower().split(":")[0]
        
        if host not in SWAGGER_ALLOWED_HOSTS:
            return jsonify({
                "detail": "Swagger/API documentation access is restricted"
            }), 403
```

### Express (Node.js)

```javascript
const SWAGGER_ALLOWED_HOSTS = ['swagger.dev.ourritual.com', 'localhost'];

app.use((req, res, next) => {
  const path = req.path.toLowerCase();
  const swaggerPaths = ['/swagger', '/docs', '/api-docs', '/openapi.json'];
  
  if (swaggerPaths.some(p => path.startsWith(p))) {
    const host = (req.headers.host || '').toLowerCase().split(':')[0];
    
    if (!SWAGGER_ALLOWED_HOSTS.includes(host)) {
      return res.status(403).json({
        detail: 'Swagger/API documentation access is restricted'
      });
    }
  }
  
  next();
});
```

## Security Layers

This solution provides defense-in-depth with multiple layers:

1. **Application-level** (this middleware): Blocks /swagger on wrong host
2. **GCP IAP**: Authenticates users on swagger.dev.ourritual.com
3. **HTTPRoute routing**: Separates public and swagger traffic
4. **Future: VPN IP allowlist**: Additional network-level protection

## Notes

- This middleware runs **before** IAP authentication (at the app level)
- IAP is configured via BackendConfig (only on swagger gateway)
- Public endpoints remain fully functional
- Swagger is only accessible via swagger.dev.ourritual.com with IAP

