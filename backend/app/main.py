from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import get_settings
from app.api import features, health, models, pipeline, mlflow_api, health_models, memory


class PrivateNetworkAccessMiddleware(BaseHTTPMiddleware):
    """Middleware to handle Chrome's Private Network Access (PNA) preflight.

    Chrome sends an extra CORS preflight header when a web page on localhost
    makes requests to private network IPs. The server must respond with
    Access-Control-Allow-Private-Network: true for the request to succeed.
    """

    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS" and request.headers.get(
            "access-control-request-private-network"
        ):
            response = Response(status_code=200)
            response.headers["Access-Control-Allow-Private-Network"] = "true"
            response.headers["Access-Control-Allow-Origin"] = request.headers.get(
                "origin", "*"
            )
            response.headers["Access-Control-Allow-Methods"] = "*"
            response.headers["Access-Control-Allow-Headers"] = "*"
            response.headers["Access-Control-Allow-Credentials"] = "true"
            return response

        response = await call_next(request)
        response.headers["Access-Control-Allow-Private-Network"] = "true"
        return response


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events."""
    settings = get_settings()
    print(f"Starting {settings.api_title} v{settings.api_version}")
    print(f"Debug mode: {settings.debug}")
    print(f"MLflow tracking: {settings.mlflow_tracking_uri}")

    yield

    print("Shutting down...")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.api_title,
        version=settings.api_version,
        description=(
            "## Farm ML Analytics API\n\n"
            "Machine learning pipeline for livestock management analytics.\n\n"
            "### Features\n"
            "- **Feature Engineering**: Compute ML features from farm data\n"
            "- **Pipeline**: Batch feature computation and training data generation\n"
            "- **Models**: Train and deploy ML models for predictions\n"
            "- **Memory**: Farm Assistant context management\n"
            "- **MLflow**: Experiment tracking and model registry\n"
            "- **Predictions**: Weight forecasting, health risk assessment\n\n"
            "### Endpoints\n"
            "- `/api/v1/features/*` - Real-time feature computation\n"
            "- `/api/v1/pipeline/*` - Batch processing and training data\n"
            "- `/api/v1/models/*` - Model training and predictions\n"
            "- `/api/v1/memory/*` - Farm Assistant memory management\n\n"
            "- `/api/v1/mlflow/*` - MLflow experiment tracking\n"
        ),
        lifespan=lifespan,
    )

    # Private Network Access middleware must be added BEFORE CORSMiddleware
    # so it can handle PNA preflight requests from Chrome
    app.add_middleware(PrivateNetworkAccessMiddleware)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    app.include_router(health.router)
    app.include_router(features.router, prefix="/api/v1")
    app.include_router(pipeline.router, prefix="/api/v1")
    app.include_router(models.router, prefix="/api/v1")
    app.include_router(health_models.router, prefix="/api/v1")
    app.include_router(memory.router, prefix="/api/v1")
    app.include_router(mlflow_api.router, prefix="/api/v1")
    
    
    return app

app = create_app()
