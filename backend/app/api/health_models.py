from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.models.health_model import HealthRiskModel

router = APIRouter(prefix="/models/health", tags=["health-models"])

class HealthTrainRequest(BaseModel):
    """Request to train health model."""
    data_path: str = "data/training/health_risk_prediction.csv"
    test_size: float = 0.2
    n_estimators: int = 100
    learning_rate: float = 0.1
    max_depth: int = 6
    num_leaves: int = 31
    task: str = "all"  # "risk", "treatment", "decline", or "all"
    save_model: bool = True


class HealthPredictRequest(BaseModel):
    """Request to make a health prediction."""
    features: dict[str, Any]
    horizon_days: int = 7


class HealthBatchPredictRequest(BaseModel):
    """Request for batch health predictions."""
    features_list: list[dict[str, Any]]
    horizon_days: int = 7


_health_model: HealthRiskModel | None = None


def get_health_model() -> HealthRiskModel:
    """Get or create health model instance."""
    global _health_model
    if _health_model is None:
        _health_model = HealthRiskModel()
        try:
            _health_model.load()
        except FileNotFoundError:
            pass
    return _health_model

@router.post("/train")
async def train_health_model(request: HealthTrainRequest):
    """
    Train the health risk prediction model.
    
    Design: 15-feature max, recall-focused, domain rules.
    
    Trains up to 3 models:
    - Risk score model (regression): Predicts overall health risk 0-100
    - Treatment model (classification): Predicts if treatment will be needed
      - Uses class balancing (scale_pos_weight)
      - Low threshold (0.3) for high recall
      - Reports F2-score and recall prominently
    - Decline model (REGRESSION): Predicts health score change (delta)
      - NOT binary classification
      - Threshold of -5 points = declining
    
    Domain rules are applied during prediction for:
    - Critical health scores → auto-flag treatment
    - Overdue vaccinations → elevate risk
    - Chronic + weight loss → flag declining
    
    Use the 'task' parameter to train specific models or all.
    - risk
    - treatment
    - decline
    - all
    """
    model = get_health_model()
    
    try:
        results = model.train(
            data_path=request.data_path,
            test_size=request.test_size,
            n_estimators=request.n_estimators,
            learning_rate=request.learning_rate,
            max_depth=request.max_depth,
            num_leaves=request.num_leaves,
            task=request.task,
        )
        
        model_path = None
        if request.save_model:
            model_path = model.save()
        
        return {
            "status": "completed",
            "model_path": model_path,
            "design": "15-feature-recall-focused",
            "thresholds": results.get("thresholds"),
            "metrics": {
                k: v for k, v in results.items()
                if k.endswith("_model") and isinstance(v, dict)
            },
            "hyperparameters": results.get("hyperparameters"),
            "feature_count": results.get("features"),
            "top_features": dict(list(results.get("feature_importance", {}).items())[:10]),
        }
    except FileNotFoundError as e:
        raise HTTPException(
            status_code=404,
            detail=f"Training data not found: {e}. Run /pipeline/generate-health-training first."
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/predict")
async def predict_health_risk(request: HealthPredictRequest):
    """
    Predict health risk for an animal.
    
    Uses low thresholds (0.3) for high recall and applies domain rules.
    
    Returns:
    - predicted_risk_score: Health risk score (0-100, higher = more risk)
    - risk_level: Categorical risk level (low/moderate/elevated/high/critical)
    - treatment_probability: Probability of needing treatment
    - treatment_likely: Boolean if probability >= 0.3 (low threshold for recall)
    - predicted_score_delta: Predicted change in health score (negative = declining)
    - health_declining: Boolean if score delta <= -5
    - trend: Trend label (declining_rapidly/declining/stable/improving/improving_rapidly)
    - domain_rules_triggered: List of any domain rules that overrode predictions
    
    Requires model to be trained first.
    """
    model = get_health_model()
    
    if model.risk_model is None and model.treatment_model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/health/train first."
        )
    
    try:
        result = model.predict(
            features=request.features,
            horizon_days=request.horizon_days,
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/predict-batch")
async def predict_health_risk_batch(request: HealthBatchPredictRequest):
    """
    Predict health risk for multiple animals.
    """
    model = get_health_model()
    
    if model.risk_model is None and model.treatment_model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/health/train first."
        )
    
    try:
        results = model.predict_batch(
            features_list=request.features_list,
            horizon_days=request.horizon_days,
        )
        return {"predictions": results, "count": len(results)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/info")
async def get_health_model_info():
    """Get information about the loaded health prediction model."""
    model = get_health_model()
    return model.get_model_info()


@router.post("/load")
async def load_health_model(path: str | None = None):
    """Load a saved health model from disk."""
    model = get_health_model()
    
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


@router.get("/feature-importance")
async def get_health_feature_importance():
    """Get feature importance from the trained health model."""
    model = get_health_model()
    
    if model.risk_model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/health/train first."
        )
    
    return {
        "feature_importance": model.metadata.get("feature_importance", {}),
    }


@router.post("/explain")
async def explain_health_prediction(request: HealthPredictRequest):
    """
    Explain a health risk prediction using SHAP values.
    
    Returns feature contributions showing why the model predicted
    a specific risk level. Helps users understand:
    - Which factors are increasing health risk
    - Which factors are protective (reducing risk)
    - The relative importance of each factor
    
    The explanation includes:
    - Risk factors: Features that increase the predicted risk
    - Protective factors: Features that decrease the predicted risk
    - Human-readable summary of the main drivers
    """
    model = get_health_model()
    
    if model.risk_model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/health/train first."
        )
    
    try:
        result = model.explain_prediction(
            features=request.features,
            horizon_days=request.horizon_days,
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/explain/global")
async def get_global_health_explanations(sample_size: int = 100):
    """
    Get global feature importance using SHAP analysis.
    
    Analyzes the training data to show which features are
    most important for health risk predictions overall.
    This helps understand the model's behavior across all animals.
    """
    model = get_health_model()
    
    if model.risk_model is None:
        raise HTTPException(
            status_code=400,
            detail="No model trained. Call /models/health/train first."
        )
    
    try:
        result = model.get_global_explanations(sample_size=sample_size)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
