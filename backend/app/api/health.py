from datetime import datetime, timezone

from fastapi import APIRouter

from app.core.config import get_settings

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    """Basic health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/info")
async def system_info():
    """System information endpoint."""
    settings = get_settings()
    return {
        "name": settings.api_title,
        "version": settings.api_version,
        "debug": settings.debug,
    }
