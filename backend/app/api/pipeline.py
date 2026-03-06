import uuid
from datetime import date, datetime

from fastapi import APIRouter, BackgroundTasks, HTTPException
from pydantic import BaseModel

from app.services.feature_pipeline import FeaturePipeline, TrainingDataGenerator
from app.services.job_store import JobStatus, get_job_store
from app.services.synthetic_data import SyntheticDataGenerator

router = APIRouter(prefix="/pipeline", tags=["pipeline"])

class PipelineRunRequest(BaseModel):
    """Request to run feature computation pipeline."""
    farm_id: str | None = None
    as_of_date: date | None = None
    save_to_file: bool = True


class PipelineRunResponse(BaseModel):
    """Response from pipeline run."""
    status: str
    message: str
    job_id: str | None = None


class TrainingDataRequest(BaseModel):
    """Request to generate training data."""
    horizons: list[int] = [7, 14, 30]
    min_history_days: int = 14
    output_dir: str = "data/training"


class HealthTrainingDataRequest(BaseModel):
    """Request to generate health risk training data."""
    horizons: list[int] = [7, 14, 30]
    min_history_days: int = 14
    output_dir: str = "data/training"


class SyntheticDataRequest(BaseModel):
    """Request to generate synthetic training data."""
    count: int = 20
    species_distribution: dict[str, float] = {"pig": 0.6, "goat": 0.3, "cattle": 0.1}
    min_age_days: int = 30
    max_age_days: int = 180
    history_days: int = 90


class JobResponse(BaseModel):
    """Job status response."""
    id: str
    job_type: str
    status: str
    started_at: datetime
    completed_at: datetime | None = None
    result: dict | None = None
    error: str | None = None

@router.post("/features/run", response_model=PipelineRunResponse)
async def run_feature_pipeline(
    request: PipelineRunRequest,
    background_tasks: BackgroundTasks,
):
    """
    Trigger feature computation pipeline.
    
    Runs in the background and computes features for all animals.
    Results are saved to local files and optionally to the database.
    """
    job_store = get_job_store()
    job_id = str(uuid.uuid4())[:8]
    
    await job_store.create_job(
        job_id=job_id,
        job_type="feature_pipeline",
        metadata={
            "farm_id": request.farm_id,
            "as_of_date": request.as_of_date.isoformat() if request.as_of_date else None,
        },
    )
    
    async def run_pipeline():
        try:
            await job_store.update_job(job_id, JobStatus.RUNNING)
            
            pipeline = FeaturePipeline()
            results = await pipeline.compute_all_features(
                farm_id=request.farm_id,
                as_of_date=request.as_of_date,
                save_to_file=request.save_to_file,
            )
            
            await job_store.update_job(
                job_id,
                JobStatus.COMPLETED,
                result={
                    "total_animals": results["total_animals"],
                    "successful": results["successful"],
                    "failed": results["failed"],
                    "computed_at": results["computed_at"],
                },
            )
        except Exception as e:
            await job_store.update_job(job_id, JobStatus.FAILED, error=str(e))
    
    background_tasks.add_task(run_pipeline)
    
    return PipelineRunResponse(
        status="started",
        message="Feature pipeline started in background",
        job_id=job_id,
    )


@router.post("/features/run-sync")
async def run_feature_pipeline_sync(request: PipelineRunRequest):
    """
    Run feature computation pipeline synchronously.
    
    Waits for completion and returns results. Use for small farms or testing.
    """
    pipeline = FeaturePipeline()
    
    try:
        results = await pipeline.compute_all_features(
            farm_id=request.farm_id,
            as_of_date=request.as_of_date,
            save_to_file=request.save_to_file,
        )
        
        return {
            "status": "completed",
            "computed_at": results["computed_at"],
            "total_animals": results["total_animals"],
            "successful": results["successful"],
            "failed": results["failed"],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/jobs/{job_id}", response_model=JobResponse)
async def get_job_status(job_id: str):
    """Get status of a background pipeline job."""
    job_store = get_job_store()
    job = await job_store.get_job(job_id)
    
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    return JobResponse(
        id=job.id,
        job_type=job.job_type,
        status=job.status.value,
        started_at=job.started_at,
        completed_at=job.completed_at,
        result=job.result,
        error=job.error,
    )


@router.get("/jobs", response_model=list[JobResponse])
async def list_jobs(
    job_type: str | None = None,
    status: str | None = None,
    limit: int = 50,
):
    """List pipeline jobs with optional filters."""
    job_store = get_job_store()
    
    status_enum = JobStatus(status) if status else None
    jobs = await job_store.list_jobs(job_type=job_type, status=status_enum, limit=limit)
    
    return [
        JobResponse(
            id=job.id,
            job_type=job.job_type,
            status=job.status.value,
            started_at=job.started_at,
            completed_at=job.completed_at,
            result=job.result,
            error=job.error,
        )
        for job in jobs
    ]

@router.post("/training-data/generate")
async def generate_training_data(request: TrainingDataRequest):
    """
    Generate training datasets for ML models.
    
    Creates CSV files with features and targets for model training.
    """
    generator = TrainingDataGenerator()
    
    try:
        samples = await generator.generate_weight_prediction_dataset(
            horizons=request.horizons,
            min_history_days=request.min_history_days,
            output_path=f"{request.output_dir}/weight_prediction.csv",
        )
        
        return {
            "status": "completed",
            "samples_generated": len(samples),
            "output_path": f"{request.output_dir}/weight_prediction.csv",
            "horizons": request.horizons,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/training-data/generate-health")
async def generate_health_training_data(request: HealthTrainingDataRequest):
    """
    Generate health risk training datasets for ML models.
    
    Creates CSV files with health risk features and targets:
    - target_risk_score: Health risk score (0-100)
    - target_treatment_needed: Whether treatment was needed (0/1)
    - target_health_declined: Whether health declined (0/1)
    
    Use this data to train the health risk prediction model.
    """
    generator = TrainingDataGenerator()
    
    try:
        samples = await generator.generate_health_risk_dataset(
            horizons=request.horizons,
            min_history_days=request.min_history_days,
            output_path=f"{request.output_dir}/health_risk_prediction.csv",
        )
        
        return {
            "status": "completed",
            "samples_generated": len(samples),
            "output_path": f"{request.output_dir}/health_risk_prediction.csv",
            "horizons": request.horizons,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/synthetic-data/generate")
async def generate_synthetic_data(request: SyntheticDataRequest):
    """
    Generate synthetic animals with historical data for ML testing.
    
    Creates realistic weight curves and health events to train models
    when real data is insufficient.
    
    **Note**: Synthetic animals are tagged with 'SYN-' prefix for easy identification.
    """
    generator = SyntheticDataGenerator()
    
    try:
        results = await generator.generate_herd(
            count=request.count,
            species_distribution=request.species_distribution,
            min_age_days=request.min_age_days,
            max_age_days=request.max_age_days,
            history_days=request.history_days,
        )
        
        return {
            "status": "completed",
            "total_animals": results["total_animals"],
            "total_weight_records": results["total_weight_records"],
            "total_health_records": results["total_health_records"],
            "by_species": results["by_species"],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/synthetic-data/clear")
async def clear_synthetic_data():
    """
    Remove all synthetic data from the database.
    
    Deletes animals with 'SYN-' tag prefix and their associated records.
    """
    generator = SyntheticDataGenerator()
    
    try:
        deleted = await generator.clear_synthetic_data()
        
        return {
            "status": "completed",
            "deleted": deleted,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/synthetic-data/species")
async def get_supported_species():
    """Get list of supported species and their growth parameters."""
    return {
        "species": list(SyntheticDataGenerator.SPECIES_CONFIG.keys()),
        "config": SyntheticDataGenerator.SPECIES_CONFIG,
    }
