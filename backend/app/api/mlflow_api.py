"""MLflow experiment tracking and model registry API endpoints."""

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.mlflow_tracking import get_mlflow_tracker


router = APIRouter(prefix="/mlflow", tags=["MLflow"])

class PromoteModelRequest(BaseModel):
    """Request to promote a model version."""
    model_name: str
    version: int
    stage: str = "Staging"  # Staging, Production, Archived


class CompareRunsRequest(BaseModel):
    """Request to compare multiple runs."""
    run_ids: list[str]

@router.get("/experiments")
async def list_experiments() -> dict[str, Any]:
    """List all MLflow experiments."""
    tracker = get_mlflow_tracker()
    experiments = tracker.list_experiments()
    return {
        "experiments": experiments,
        "count": len(experiments),
    }


@router.get("/runs")
async def list_runs(max_results: int = 20) -> dict[str, Any]:
    """
    List recent training runs.
    
    Returns recent runs sorted by start time, including metrics and parameters.
    """
    tracker = get_mlflow_tracker()
    runs = tracker.list_runs(max_results=max_results)
    return {
        "runs": runs,
        "count": len(runs),
        "experiment": tracker.settings.mlflow_experiment_name,
    }


@router.get("/runs/{run_id}")
async def get_run(run_id: str) -> dict[str, Any]:
    """Get details for a specific run."""
    tracker = get_mlflow_tracker()
    try:
        return tracker.get_run_metrics(run_id)
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Run not found: {e}")


@router.post("/runs/compare")
async def compare_runs(request: CompareRunsRequest) -> dict[str, Any]:
    """
    Compare metrics across multiple training runs.
    
    Useful for analyzing which hyperparameters produce better results.
    """
    tracker = get_mlflow_tracker()
    
    if len(request.run_ids) < 2:
        raise HTTPException(status_code=400, detail="Need at least 2 run IDs to compare")
    
    try:
        comparison = tracker.compare_runs(request.run_ids)
        
        metrics_comparison = {}
        for run_id, data in comparison.items():
            for metric, value in data["metrics"].items():
                if metric not in metrics_comparison:
                    metrics_comparison[metric] = {}
                metrics_comparison[metric][run_id] = value
        
        best_runs = {}
        for metric, values in metrics_comparison.items(): 
            if "r2" in metric or "accuracy" in metric:
                best_run = max(values.items(), key=lambda x: x[1])
            else:
                best_run = min(values.items(), key=lambda x: x[1])
            best_runs[metric] = {"run_id": best_run[0], "value": best_run[1]}
        
        return {
            "runs": comparison,
            "metrics_comparison": metrics_comparison,
            "best_runs": best_runs,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error comparing runs: {e}")


@router.get("/models")
async def list_registered_models() -> dict[str, Any]:
    """List all registered models in the model registry."""
    tracker = get_mlflow_tracker()
    client = tracker.client
    
    try:
        models = client.search_registered_models()
        return {
            "models": [
                {
                    "name": m.name,
                    "description": m.description,
                    "latest_versions": [
                        {
                            "version": v.version,
                            "stage": v.current_stage,
                            "status": v.status,
                        }
                        for v in (m.latest_versions or [])
                    ],
                }
                for m in models
            ],
            "count": len(models),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing models: {e}")


@router.get("/models/{model_name}/versions")
async def list_model_versions(model_name: str) -> dict[str, Any]:
    """List all versions of a registered model."""
    tracker = get_mlflow_tracker()
    versions = tracker.list_model_versions(model_name)
    
    if not versions:
        raise HTTPException(status_code=404, detail=f"Model '{model_name}' not found")
    
    return {
        "model_name": model_name,
        "versions": versions,
        "count": len(versions),
    }


@router.get("/models/{model_name}/latest")
async def get_latest_model(model_name: str, stage: str = "None") -> dict[str, Any]:
    """
    Get the latest version of a model at a specific stage.
    
    Stages: None (default), Staging, Production, Archived
    """
    tracker = get_mlflow_tracker()
    version = tracker.get_latest_model_version(model_name, stage)
    
    if not version:
        raise HTTPException(
            status_code=404,
            detail=f"No version found for model '{model_name}' at stage '{stage}'"
        )
    
    return {
        "model_name": model_name,
        "stage": stage,
        "version": version,
    }


@router.post("/models/promote")
async def promote_model(request: PromoteModelRequest) -> dict[str, Any]:
    """
    Promote a model version to a new stage.
    
    Typical workflow:
    1. Train model → registered as "None" stage
    2. Promote to "Staging" for testing
    3. Promote to "Production" for serving
    
    Stages:
    - None: Just registered, not staged
    - Staging: Being tested
    - Production: Active in production
    - Archived: No longer in use
    """
    tracker = get_mlflow_tracker()
    
    valid_stages = ["None", "Staging", "Production", "Archived"]
    if request.stage not in valid_stages:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid stage. Must be one of: {valid_stages}"
        )
    
    success = tracker.promote_model(
        model_name=request.model_name,
        version=request.version,
        stage=request.stage,
    )
    
    if not success:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to promote model '{request.model_name}' v{request.version}"
        )
    
    return {
        "success": True,
        "model_name": request.model_name,
        "version": request.version,
        "new_stage": request.stage,
        "message": f"Model promoted to {request.stage}",
    }


@router.get("/status")
async def mlflow_status() -> dict[str, Any]:
    """Get MLflow configuration and status."""
    tracker = get_mlflow_tracker()
    
    return {
        "tracking_uri": tracker.settings.mlflow_tracking_uri,
        "experiment_name": tracker.settings.mlflow_experiment_name,
        "experiment_id": tracker.experiment_id,
        "status": "connected",
        "ui_hint": "Run 'mlflow ui' to view the MLflow dashboard",
    }
