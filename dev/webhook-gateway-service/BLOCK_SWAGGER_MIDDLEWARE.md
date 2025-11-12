# Block /swagger on Public Domain - Application Middleware

## Problem
The public gateway (`webhooks.dev.ourritual.com`) needs to be fully open for webhook endpoints like `/zoom-webhook`, `/env`, etc., but the `/swagger` path should be blocked and only accessible via `swagger.dev.ourritual.com` with IAP.

## Solution
Add FastAPI middleware to check the `Host` header and block `/swagger` access on the public domain.

## Implementation

Add this middleware to `/Users/nadavsvirsky/Documents/Ritual/webhook-gateway-service/src/main.py`:

```python
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
import logging

logger = logging.getLogger(__name__)

# ... existing code ...

# 🔒 Middleware to block /swagger on public domain
@app.middleware("http")
async def block_public_swagger(request: Request, call_next):
    """
    Block /swagger path on public domain (webhooks.dev.ourritual.com).
    Only allow swagger access via swagger.dev.ourritual.com with IAP.
    """
    host = request.headers.get("host", "").lower()
    path = request.url.path
    
    # Block /swagger and /openapi.json on public domain
    if host.startswith("webhooks.") and (path == "/swagger" or path == "/openapi.json" or path.startswith("/swagger/")):
        logger.warning(f"Blocked swagger access on public domain: {host}{path}")
        return JSONResponse(
            status_code=403,
            content={
                "detail": "Swagger UI is not available on this domain. "
                         "Please use swagger.dev.ourritual.com for API documentation."
            }
        )
    
    # Allow all other requests
    response = await call_next(request)
    return response

# ... rest of the code ...
```

## Testing

After deploying, test the following:

1. ✅ Public webhooks should work:
```bash
curl https://webhooks.dev.ourritual.com/env
curl https://webhooks.dev.ourritual.com/zoom-webhook
curl https://webhooks.dev.ourritual.com/info
```

2. ❌ Swagger on public domain should be blocked:
```bash
curl https://webhooks.dev.ourritual.com/swagger
# Expected: 403 Forbidden with message
```

3. ✅ Swagger via IAP should work:
```bash
# Visit in browser (requires IAP authentication):
https://swagger.dev.ourritual.com/webhook-gateway-service/swagger
```

## Deployment Steps

1. Add the middleware to `main.py` (before route definitions)
2. Test locally if possible
3. Commit and push to trigger CI/CD:
```bash
cd /Users/nadavsvirsky/Documents/Ritual/webhook-gateway-service
git add src/main.py
git commit -m "feat: Add middleware to block /swagger on public domain"
git push
```

4. Verify in dev environment once deployed
5. Apply same pattern to other services if needed

## Notes

- The middleware checks the `Host` header to determine which domain is being accessed
- It blocks `/swagger`, `/openapi.json`, and any paths starting with `/swagger/`
- All other paths on the public domain remain fully open
- Swagger remains accessible only via `swagger.dev.ourritual.com` with IAP protection

