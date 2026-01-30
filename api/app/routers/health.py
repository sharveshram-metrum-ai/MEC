"""
Health check endpoints.
"""

from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health_check():
    """Basic health check."""
    return {"status": "healthy", "service": "mec-fastapi"}


@router.get("/ready")
async def readiness_check():
    """Readiness check - verify dependencies."""
    # TODO: Add database and redis connectivity checks
    return {
        "status": "ready",
        "checks": {
            "database": "ok",
            "redis": "ok",
        }
    }
