import json
import pickle
from datetime import datetime
from pathlib import Path
from typing import Any

import lightgbm as lgb
import mlflow
import mlflow.lightgbm
import numpy as np
import pandas as pd
import shap
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

from app.core.mlflow_tracking import get_mlflow_tracker, MLflowTracker


class WeightPredictionModel:
    """
    Weight prediction model using LightGBM.
    
    Predicts future animal weight based on current features.
    Supports multiple prediction horizons (7, 14, 30 days).
    
    Key design decisions:
    - Limited to 15 most predictive features
    - Single model (no ensemble complexity)
    - Domain rules for sanity checks
    """
     
    CORE_FEATURES = [
        # Weight history (most predictive)
        "wf_current_weight",               # Current weight (baseline)
        "wf_adg_7d",                        # Recent daily gain
        "wf_adg_30d",                       # 30-day daily gain
        "wf_weight_velocity_7d",           # Short-term momentum
        "wf_weight_change_30d",            # Monthly change
        "wf_growth_curve_deviation",       # Deviation from expected
        # Health factors
        "hf_health_score",                 # Overall health
        "hf_treatment_count_30d",          # Recent treatments
        "hf_has_chronic_condition",        # Persistent issues
        "hf_vaccination_compliance_rate",  # Compliance factor
        # Prediction context
        "horizon_days",                     # Prediction window
    ]

    CATEGORICAL_FEATURES = ["species", "gender"]
    
    # Meta feature for prediction input
    META_FEATURES = ["current_weight"]   
    
    TARGET = "target_weight"
    
    # Domain rule thresholds
    MAX_DAILY_GAIN_KG = 3.0    # Max reasonable daily gain
    MAX_DAILY_LOSS_KG = 1.5   # Max reasonable daily loss
    MIN_WEIGHT_KG = 0.5       # Minimum viable weight
    
    def __init__(self, model_dir: str = "models", use_mlflow: bool = True):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(parents=True, exist_ok=True)
        
        # Single LightGBM model
        self.model: lgb.LGBMRegressor | None = None
        
        self.label_encoders: dict[str, LabelEncoder] = {}
        self.feature_columns: list[str] = []
        self.metadata: dict[str, Any] = {}
        
        # MLflow integration
        self.use_mlflow = use_mlflow
        self.mlflow_tracker: MLflowTracker | None = None
        self.mlflow_run_id: str | None = None
        
        if use_mlflow:
            try:
                self.mlflow_tracker = get_mlflow_tracker()
            except Exception as e:
                print(f"Warning: MLflow initialization failed: {e}")
                self.use_mlflow = False
    
    def _prepare_features(
        self,
        df: pd.DataFrame,
        fit_encoders: bool = False,
    ) -> pd.DataFrame:
        """Prepare features for training/inference."""
        df = df.copy()
        
        # Handle categorical features
        for col in self.CATEGORICAL_FEATURES:
            if col in df.columns:
                if fit_encoders:
                    self.label_encoders[col] = LabelEncoder()
                    df[col] = df[col].fillna("unknown").astype(str)
                    self.label_encoders[col].fit(df[col])
                
                if col in self.label_encoders:
                    df[col] = df[col].fillna("unknown").astype(str)
                    known_classes = set(self.label_encoders[col].classes_)
                    df[col] = df[col].apply(lambda x: x if x in known_classes else "unknown")
                    df[f"{col}_encoded"] = self.label_encoders[col].transform(df[col])
        
        # Handle boolean features
        bool_cols = ["hf_has_chronic_condition"]
        for col in bool_cols:
            if col in df.columns:
                df[col] = df[col].fillna(False).astype(bool).astype(int)
        
        # Fill missing numeric values with median
        for col in self.CORE_FEATURES:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce")
                median_val = df[col].median()
                df[col] = df[col].fillna(median_val if pd.notna(median_val) else 0)
        
        return df
    
    def _get_feature_columns(self, df: pd.DataFrame) -> list[str]:
        """Get list of feature columns to use (max 15)."""
        feature_cols = []
        
        # Add core numeric features
        for col in self.CORE_FEATURES:
            if col in df.columns:
                feature_cols.append(col)
        
        # Add encoded categorical features
        for col in self.CATEGORICAL_FEATURES:
            encoded_col = f"{col}_encoded"
            if encoded_col in df.columns:
                feature_cols.append(encoded_col)
        
        # Enforce 15 feature limit
        if len(feature_cols) > 15:
            print(f"Warning: Truncating features from {len(feature_cols)} to 15")
            feature_cols = feature_cols[:15]
        
        return feature_cols
    
    def _apply_domain_rules(
        self,
        features: dict[str, Any],
        result: dict[str, Any],
    ) -> dict[str, Any]:
        """
        Apply domain rules to sanity-check predictions.
        
        Ensures predictions are biologically plausible.
        """
        flags = []
        
        current_weight = result.get("current_weight", 0)
        predicted_weight = result.get("predicted_weight", 0)
        horizon_days = result.get("horizon_days", 7)
        
        if current_weight > 0 and horizon_days > 0:
            daily_change = (predicted_weight - current_weight) / horizon_days
            
            # Rule 1: Cap excessive daily gain
            if daily_change > self.MAX_DAILY_GAIN_KG:
                old_pred = predicted_weight
                predicted_weight = current_weight + (self.MAX_DAILY_GAIN_KG * horizon_days)
                result["predicted_weight"] = round(predicted_weight, 1)
                result["predicted_gain"] = round(predicted_weight - current_weight, 1)
                flags.append(f"capped_daily_gain_from_{old_pred:.1f}")
            
            # Rule 2: Cap excessive daily loss
            if daily_change < -self.MAX_DAILY_LOSS_KG:
                old_pred = predicted_weight
                predicted_weight = current_weight - (self.MAX_DAILY_LOSS_KG * horizon_days)
                result["predicted_weight"] = round(predicted_weight, 1)
                result["predicted_gain"] = round(predicted_weight - current_weight, 1)
                flags.append(f"capped_daily_loss_from_{old_pred:.1f}")
        
        # Rule 3: Minimum weight floor
        if result.get("predicted_weight", 0) < self.MIN_WEIGHT_KG:
            result["predicted_weight"] = self.MIN_WEIGHT_KG
            flags.append("applied_minimum_weight")
        
        # Rule 4: Flag if health issues may affect prediction
        health_score = features.get("hf_health_score", 100)
        if health_score < 50:
            flags.append("low_health_score_warning")
        
        if flags:
            result["domain_rules_triggered"] = flags
        
        return result
    
    def train(
        self,
        data_path: str = "data/training/weight_prediction.csv",
        test_size: float = 0.2,
        n_estimators: int = 100,
        learning_rate: float = 0.1,
        max_depth: int = 6,
        num_leaves: int = 31,
    ) -> dict[str, Any]:
        """
        Train the weight prediction model.
        
        Single LightGBM model with limited features.
        
        Args:
            data_path: Path to training CSV
            test_size: Fraction for test split
            n_estimators: Number of boosting rounds
            learning_rate: Learning rate
            max_depth: Max tree depth
            num_leaves: Max leaves per tree
            
        Returns:
            Training results with metrics
        """
        # Load data
        df = pd.read_csv(data_path)
        print(f"Loaded {len(df)} training samples")
        
        # Prepare features
        df = self._prepare_features(df, fit_encoders=True)
        self.feature_columns = self._get_feature_columns(df)
        
        print(f"Using {len(self.feature_columns)} features (max 15)")
        print(f"Features: {self.feature_columns}")
        
        # Split data
        X = df[self.feature_columns]
        y = df[self.TARGET]
        
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42
        )
        
        # Train single LightGBM model
        self.model = lgb.LGBMRegressor(
            n_estimators=n_estimators,
            learning_rate=learning_rate,
            max_depth=max_depth,
            num_leaves=num_leaves,
            random_state=42,
            verbose=-1,
        )
        
        self.model.fit(
            X_train, y_train,
            eval_set=[(X_test, y_test)],
            callbacks=[lgb.early_stopping(stopping_rounds=10, verbose=False)],
        )
        
        # Evaluate
        y_pred_train = self.model.predict(X_train)
        y_pred_test = self.model.predict(X_test)
        
        train_metrics = self._calculate_metrics(y_train, y_pred_train)
        test_metrics = self._calculate_metrics(y_test, y_pred_test)
        
        # Feature importance
        feature_importance = dict(zip(
            self.feature_columns,
            self.model.feature_importances_.tolist()
        ))
        feature_importance = dict(sorted(
            feature_importance.items(),
            key=lambda x: x[1],
            reverse=True
        ))
        
        # Store metadata
        self.metadata = {
            "trained_at": datetime.utcnow().isoformat(),
            "samples": len(df),
            "features": len(self.feature_columns),
            "feature_list": self.feature_columns,
            "hyperparameters": {
                "n_estimators": n_estimators,
                "learning_rate": learning_rate,
                "max_depth": max_depth,
                "num_leaves": num_leaves,
            },
            "metrics": {
                "train": train_metrics,
                "test": test_metrics,
            },
            "feature_importance": feature_importance,
            "design": "15-feature-single-model",
        }
        
        print(f"Weight model MAE: {test_metrics['mae']:.2f} kg (R²: {test_metrics['r2']:.3f})")
        
        # Log to MLflow
        if self.use_mlflow and self.mlflow_tracker:
            try:
                self._log_to_mlflow()
            except Exception as e:
                print(f"Warning: MLflow logging failed: {e}")
        
        return self.metadata
    
    def _log_to_mlflow(self) -> None:
        """Log training results to MLflow."""
        with self.mlflow_tracker.start_run(
            run_name=f"weight-model-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}",
            tags={
                "model_type": "weight_prediction",
                "model_framework": "lightgbm",
                "design": "15-feature-single-model",
            }
        ) as run:
            # Log hyperparameters
            mlflow.log_params(self.metadata["hyperparameters"])
            mlflow.log_params({
                "training_samples": self.metadata["samples"],
                "feature_count": self.metadata["features"],
            })
            
            # Log metrics
            metrics = self.metadata.get("metrics", {})
            for split, split_metrics in metrics.items():
                if isinstance(split_metrics, dict):
                    for metric_name, value in split_metrics.items():
                        mlflow.log_metric(f"{split}_{metric_name}", value)
            
            # Log feature importance
            importance_path = "/tmp/weight_feature_importance.json"
            with open(importance_path, "w") as f:
                json.dump(self.metadata.get("feature_importance", {}), f, indent=2)
            mlflow.log_artifact(importance_path, "feature_importance")
            
            # Log the model
            mlflow.lightgbm.log_model(
                self.model,
                artifact_path="model",
                registered_model_name="weight-prediction-model",
            )
            
            self.mlflow_run_id = run.info.run_id
            self.metadata["mlflow_run_id"] = self.mlflow_run_id
            print(f"Logged to MLflow (run_id: {self.mlflow_run_id})")
    
    def _calculate_metrics(
        self,
        y_true: np.ndarray,
        y_pred: np.ndarray,
    ) -> dict[str, float]:
        """Calculate regression metrics."""
        # Avoid division by zero in MAPE
        mask = y_true != 0
        if mask.sum() > 0:
            mape = float(np.mean(np.abs((y_true[mask] - y_pred[mask]) / y_true[mask])) * 100)
        else:
            mape = 0.0
        
        return {
            "mae": float(mean_absolute_error(y_true, y_pred)),
            "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
            "r2": float(r2_score(y_true, y_pred)),
            "mape": mape,
        }
    
    def predict(
        self,
        features: dict[str, Any],
        horizon_days: int = 7,
    ) -> dict[str, Any]:
        """
        Predict future weight for a single animal.
        
        Applies domain rules for sanity checking.
        
        Args:
            features: Dict with feature values
            horizon_days: Days ahead to predict (7, 14, or 30)
            
        Returns:
            Prediction result with confidence
        """
        if self.model is None:
            raise ValueError("Model not trained. Call train() or load() first.")
        
        # Add horizon
        features["horizon_days"] = horizon_days
        
        # Handle current_weight alias
        if "current_weight" in features and "wf_current_weight" not in features:
            features["wf_current_weight"] = features["current_weight"]
        
        df = pd.DataFrame([features])
        df = self._prepare_features(df)
        
        # Ensure all feature columns exist
        for col in self.feature_columns:
            if col not in df.columns:
                df[col] = 0
        
        X = df[self.feature_columns].fillna(0)
        
        # Predict
        prediction = float(self.model.predict(X)[0])
        
        # Estimate confidence based on feature completeness
        provided_features = sum(
            1 for col in self.feature_columns
            if col in features and features.get(col) is not None
        )
        confidence = max(0.5, min(1.0, provided_features / len(self.feature_columns) + 0.3))
        
        current_weight = features.get("current_weight") or features.get("wf_current_weight") or 0
        
        result = {
            "predicted_weight": round(prediction, 1),
            "horizon_days": horizon_days,
            "confidence": round(confidence, 2),
            "current_weight": current_weight,
            "predicted_gain": round(prediction - current_weight, 1),
        }
        
        # Apply domain rules for sanity checks
        result = self._apply_domain_rules(features, result)
        
        return result
    
    def predict_batch(
        self,
        features_list: list[dict[str, Any]],
        horizon_days: int = 7,
    ) -> list[dict[str, Any]]:
        """Predict for multiple animals."""
        return [
            self.predict(features, horizon_days)
            for features in features_list
        ]
    
    def explain_prediction(
        self,
        features: dict[str, Any],
        horizon_days: int = 7,
    ) -> dict[str, Any]:
        """
        Explain a single prediction using SHAP values.
        
        Args:
            features: Dict with feature values
            horizon_days: Days ahead to predict
            
        Returns:
            Explanation with SHAP values and feature contributions
        """
        if self.model is None:
            raise ValueError("Model not trained. Call train() or load() first.")
        
        # Prepare input
        features["horizon_days"] = horizon_days
        if "current_weight" in features and "wf_current_weight" not in features:
            features["wf_current_weight"] = features["current_weight"]
        
        df = pd.DataFrame([features])
        df = self._prepare_features(df)
        
        for col in self.feature_columns:
            if col not in df.columns:
                df[col] = 0
        
        X = df[self.feature_columns].fillna(0)
        
        # Create SHAP explainer
        explainer = shap.TreeExplainer(self.model)
        shap_values = explainer.shap_values(X)
        
        # Get prediction
        prediction = float(self.model.predict(X)[0])
        base_value = float(explainer.expected_value)
        
        # Build explanation
        feature_contributions = {}
        for i, col in enumerate(self.feature_columns):
            contribution = float(shap_values[0][i])
            if abs(contribution) > 0.001:
                feature_contributions[col] = {
                    "value": float(X[col].iloc[0]),
                    "contribution": round(contribution, 3),
                    "direction": "increases" if contribution > 0 else "decreases",
                }
        
        # Sort by absolute contribution
        sorted_contributions = dict(sorted(
            feature_contributions.items(),
            key=lambda x: abs(x[1]["contribution"]),
            reverse=True
        ))
        
        # Get top positive and negative contributors
        positive_factors = [
            {"feature": k, **v}
            for k, v in sorted_contributions.items()
            if v["contribution"] > 0
        ][:5]
        
        negative_factors = [
            {"feature": k, **v}
            for k, v in sorted_contributions.items()
            if v["contribution"] < 0
        ][:5]
        
        current_weight = features.get("current_weight") or features.get("wf_current_weight") or 0
        
        return {
            "predicted_weight": round(prediction, 1),
            "horizon_days": horizon_days,
            "current_weight": current_weight,
            "predicted_gain": round(prediction - current_weight, 1),
            "base_value": base_value,
            "explanation": {
                "summary": self._generate_explanation_text(
                    prediction, current_weight, horizon_days, positive_factors, negative_factors
                ),
                "positive_factors": positive_factors,
                "negative_factors": negative_factors,
                "all_contributions": sorted_contributions,
            },
        }
    
    def _generate_explanation_text(
        self,
        prediction: float,
        current_weight: float,
        horizon_days: int,
        positive_factors: list[dict],
        negative_factors: list[dict],
    ) -> str:
        """Generate human-readable explanation text."""
        gain = prediction - current_weight
        direction = "gain" if gain > 0 else "lose"
        
        text = f"Predicted to {direction} {abs(gain):.1f} kg over {horizon_days} days "
        text += f"({current_weight:.1f} → {prediction:.1f} kg). "
        
        if positive_factors:
            top_positive = positive_factors[0]
            feature_name = self._format_feature_name(top_positive["feature"])
            text += f"Main driver: {feature_name}. "
        
        if negative_factors:
            top_negative = negative_factors[0]
            feature_name = self._format_feature_name(top_negative["feature"])
            text += f"Limiting factor: {feature_name}."
        
        return text
    
    def _format_feature_name(self, feature: str) -> str:
        """Convert feature column name to human-readable format."""
        name_map = {
            "horizon_days": "prediction timeframe",
            "wf_current_weight": "current weight",
            "wf_weight_velocity_7d": "recent growth rate",
            "wf_adg_7d": "7-day daily gain",
            "wf_adg_30d": "30-day daily gain",
            "wf_weight_change_30d": "monthly weight change",
            "wf_growth_curve_deviation": "growth curve deviation",
            "hf_health_score": "health score",
            "hf_treatment_count_30d": "recent treatments",
            "hf_has_chronic_condition": "chronic condition",
            "hf_vaccination_compliance_rate": "vaccination compliance",
            "species_encoded": "animal species",
            "gender_encoded": "gender",
        }
        return name_map.get(feature, feature.replace("wf_", "").replace("hf_", "").replace("_", " "))
    
    def get_global_explanations(
        self,
        data_path: str = "data/training/weight_prediction.csv",
        sample_size: int = 100,
    ) -> dict[str, Any]:
        """
        Get global feature importance using SHAP.
        
        Args:
            data_path: Path to training data
            sample_size: Number of samples to analyze
            
        Returns:
            Global SHAP summary statistics
        """
        if self.model is None:
            raise ValueError("Model not trained. Call train() or load() first.")
        
        try:
            df = pd.read_csv(data_path)
            df = self._prepare_features(df)
            
            for col in self.feature_columns:
                if col not in df.columns:
                    df[col] = 0
            
            X = df[self.feature_columns].fillna(0)
            
            if len(X) > sample_size:
                X = X.sample(n=sample_size, random_state=42)
            
            explainer = shap.TreeExplainer(self.model)
            shap_values = explainer.shap_values(X)
            
            mean_abs_shap = np.abs(shap_values).mean(axis=0)
            
            global_importance = {}
            for i, col in enumerate(self.feature_columns):
                global_importance[col] = {
                    "mean_abs_shap": round(float(mean_abs_shap[i]), 4),
                    "friendly_name": self._format_feature_name(col),
                }
            
            sorted_importance = dict(sorted(
                global_importance.items(),
                key=lambda x: x[1]["mean_abs_shap"],
                reverse=True
            ))
            
            top_features = list(sorted_importance.keys())[:10]
            
            return {
                "sample_size": len(X),
                "base_value": float(explainer.expected_value),
                "top_features": top_features,
                "feature_importance": sorted_importance,
                "summary": f"Top predictors: {', '.join([self._format_feature_name(f) for f in top_features[:3]])}",
            }
        except FileNotFoundError:
            return {
                "feature_importance": self.metadata.get("feature_importance", {}),
                "note": "Using model's built-in feature importance",
            }
    
    def get_model_info(self) -> dict[str, Any]:
        """Get information about the loaded model."""
        if self.model is None:
            return {"status": "no_model_loaded"}
        
        return {
            "status": "loaded",
            "trained_at": self.metadata.get("trained_at"),
            "samples": self.metadata.get("samples"),
            "features": self.metadata.get("features"),
            "feature_list": self.feature_columns,
            "metrics": self.metadata.get("metrics"),
            "top_features": dict(list(self.metadata.get("feature_importance", {}).items())[:10]),
            "design": "15-feature-single-model",
        }
    
    def save(self, name: str = "weight_model") -> str:
        """Save model to disk."""
        if self.model is None:
            raise ValueError("No model to save")
        
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        model_path = self.model_dir / f"{name}_{timestamp}"
        model_path.mkdir(parents=True, exist_ok=True)
        
        # Save model
        model_file = model_path / "model.pkl"
        with open(model_file, "wb") as f:
            pickle.dump(self.model, f)
        
        # Save label encoders
        encoders_file = model_path / "encoders.pkl"
        with open(encoders_file, "wb") as f:
            pickle.dump(self.label_encoders, f)
        
        # Save metadata
        metadata_file = model_path / "metadata.json"
        self.metadata["feature_columns"] = self.feature_columns
        with open(metadata_file, "w") as f:
            json.dump(self.metadata, f, indent=2, default=str)
        
        # Create "latest" symlink
        latest_link = self.model_dir / f"{name}_latest"
        if latest_link.exists():
            latest_link.unlink()
        latest_link.symlink_to(model_path.name)
        
        print(f"Model saved to {model_path}")
        return str(model_path)
    
    def load(self, path: str | None = None, name: str = "weight_model") -> None:
        """Load model from disk."""
        if path is None:
            path = self.model_dir / f"{name}_latest"
        
        path = Path(path)
        
        if not path.exists():
            raise FileNotFoundError(f"Model not found at {path}")
        
        # Load model
        model_file = path / "model.pkl"
        with open(model_file, "rb") as f:
            self.model = pickle.load(f)
        
        # Load label encoders
        encoders_file = path / "encoders.pkl"
        with open(encoders_file, "rb") as f:
            self.label_encoders = pickle.load(f)
        
        # Load metadata
        metadata_file = path / "metadata.json"
        with open(metadata_file, "r") as f:
            self.metadata = json.load(f)
        
        self.feature_columns = self.metadata.get("feature_columns", [])
        print(f"Model loaded from {path}")
