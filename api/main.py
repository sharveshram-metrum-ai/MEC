"""
MEC FastAPI Service - Webhooks & Admin

This is a minimal FastAPI service for operations that can't be handled by PostgREST:
- Stripe webhooks (signature verification, subscription events)
- Auth0 user sync (external API calls)
- Admin operations (complex multi-step workflows)

Most API traffic goes through PostgREST for maximum performance.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import webhooks, admin, health

# Configure logging
logging.basicConfig(
    level=logging.INFO if not settings.DEBUG else logging.DEBUG,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    logger.info("Starting MEC FastAPI service...")
    logger.info(f"Environment: {settings.ENVIRONMENT}")
    yield
    logger.info("Shutting down MEC FastAPI service...")


app = FastAPI(
    title="MEC Service - Webhooks & Admin",
    description="""
## MEC Webhooks & Admin API

This service handles operations requiring external integrations:

- **Webhooks**: Stripe subscription events, Auth0 user sync
- **Admin**: Complex administrative operations

For core MEC operations (metering, entitlements, controls), use the main API at `/api/`.
    """,
    version="3.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health.router, tags=["Health"])
app.include_router(webhooks.router, prefix="/webhooks", tags=["Webhooks"])
app.include_router(admin.router, prefix="/admin", tags=["Admin"])


@app.get("/")
async def root():
    """Service info."""
    return {
        "service": "MEC FastAPI (Webhooks & Admin)",
        "version": "3.0.0",
        "endpoints": {
            "webhooks": "/webhooks/",
            "admin": "/admin/",
            "docs": "/docs",
            "health": "/health",
        },
        "note": "For core MEC API, use /api/ (PostgREST)"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )
