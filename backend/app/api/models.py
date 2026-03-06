from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.models.weight_model import WeightPredictionModel
from app.services.job_store import JobStatus, get_job_store

router = APIRouter(prefix="/models", tags=["weight-models"])

class TrainRequest(BaseModel):
    """Request to train a model."""
    data_path: str = "data/training/weight_prediction.csv"
    test_size: float = 0.2
    n_estimators: int = 100
    learning_rate: float = 0.1
    max_depth: int = 6
    num_leaves: int = 31
    save_model: bool = True


class PredictRequest(BaseModel):
    """Request to make a prediction."""
    features: dict[str, Any]
    horizon_days: int = 7


class BatchPredictRequest(BaseModel):
    """Request for batch predictions."""
    features_list: list[dict[str, Any]]
    horizon_days: int = 7


_weight_model: WeightPredictionModel | None = None


def get_weight_model() -> WeightPredictionModel:
    """Get or create weight model instance."""
    global _weight_model
    if _weight_model is None:
        _weight_model = WeightPredictionModel()
        try:
            _weight_model.load()
        except FileNotFoundError:
            pass
    return _weight_model


@router.post("/weight/train")
async def train_weight_model(request: TrainRequest):
    """
    Train the weight prediction model.
    
    Uses LightGBM with 15-feature limit for interpretability.
    """
    model = get_weight_model()
    
    try:
        results = model.train(
            data_path=request.data_path,
            test_size=request.test_size,
            n_estimators=request.n_estimators,
            learning_rate=request.learning_rate,
            max_depth=request.max_depth,
            num_leaves=request.num_leaves,
        )
        
        model_path = None
        if request.save_model:
            model_path = model.save()
        
        return {
            "status": "completed",
            "model_path": model_path,
            "metrics": results.get("metrics"),
            "hyperparameters": results.get("hyperparameters"),
            "feature_count": results.get("features"),
            "top_features": dict(list(results.get("feature_importance", {}).items())[:10]),
            "design": "15-feature-single-model",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/weight/predict")
async def predict_weight(request: PredictRequest):
    """
    Predict future weight for an animal.
    
    Requires model to be trained first.
    """
    model = get_weight_model()
    
    if model.model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/weight/train first."
        )
    
    try:
        result = model.predict(
            features=request.features,
            horizon_days=request.horizon_days,
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/weight/predict-batch")
async def predict_weight_batch(request: BatchPredictRequest):
    """
    Predict future weight for multiple animals.
    """
    model = get_weight_model()
    
    if model.model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/weight/train first."
        )
    
    try:
        results = model.predict_batch(
            features_list=request.features_list,
            horizon_days=request.horizon_days,
        )
        return {"predictions": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/weight/info")
async def get_model_info():
    """Get information about the loaded weight prediction model."""
    model = get_weight_model()
    return model.get_model_info()


@router.post("/weight/load")
async def load_model(path: str | None = None):
    """Load a saved model from disk."""
    model = get_weight_model()
    
    try:
        model.load(path=path)
        return {
            "status": "loaded",
            "model_info": model.get_model_info(),
        }
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/weight/feature-importance")
async def get_feature_importance():
    """Get feature importance from the trained model."""
    model = get_weight_model()
    
    if model.model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/weight/train first."
        )
    
    return {
        "feature_importance": model.metadata.get("feature_importance", {}),
    }

@router.post("/weight/explain")
async def explain_prediction(request: PredictRequest):
    """
    Explain a weight prediction using SHAP values.
    
    Returns feature contributions showing why the model made
    a specific prediction. Helps users understand:
    - Which features are driving the prediction up
    - Which features are limiting growth
    - The relative importance of each factor
    """
    model = get_weight_model()
    
    if model.model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/weight/train first."
        )
    
    try:
        result = model.explain_prediction(
            features=request.features,
            horizon_days=request.horizon_days,
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/weight/explain/global")
async def get_global_explanations(sample_size: int = 100):
    """
    Get global feature importance using SHAP analysis.
    
    Analyzes the training data to show which features are
    most important for predictions overall. This helps understand
    the model's behavior across all animals.
    """
    model = get_weight_model()
    
    if model.model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/weight/train first."
        )
    
    try:
        result = model.get_global_explanations(sample_size=sample_size)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
