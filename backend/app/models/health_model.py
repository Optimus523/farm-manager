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
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    roc_auc_score,
    mean_absolute_error,
    mean_squared_error,
    r2_score,
    fbeta_score,
)
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

from app.core.mlflow_tracking import get_mlflow_tracker, MLflowTracker


class HealthRiskModel:
    """
    Health risk prediction model using LightGBM.
    
    Predicts health risk score and treatment probability.
    Supports multiple prediction horizons (7, 14, 30 days).
    
    Key design decisions:
    - Limited to 15 most predictive features
    - Class balancing for imbalanced targets
    - Low thresholds (0.3) to maximize recall
    - Domain rules override model predictions
    - Decline is regression (score delta), NOT classification
    """
     
    CORE_FEATURES = [
        # Treatment history (strongest predictors)
        "hrf_treatment_frequency_30d",      
        "hrf_days_since_last_treatment",    
        "hrf_severe_treatment_count_30d",   
        # Health status
        "hrf_current_health_score",         
        "hrf_has_chronic_condition",        
        # Vaccination status
        "hrf_overdue_vaccinations",         
        "hrf_vaccination_coverage",         
        # Weight indicators
        "wf_current_weight",               
        "wf_adg_7d",                        
        "hrf_weight_loss_flag",             
        # Time factors
        "hrf_days_since_last_checkup",      
        "hrf_age_risk_factor",              
        # Prediction horizon
        "horizon_days",                      
    ]
    
    CATEGORICAL_FEATURES = ["species", "gender"]
    
    TARGET_RISK_SCORE = "target_risk_score"
    TARGET_TREATMENT_NEEDED = "target_treatment_needed"
    TARGET_HEALTH_DECLINED = "target_health_declined"
    TARGET_SCORE_DELTA = "target_score_delta"   
    
    # Decision thresholds (LOW for high recall)
    TREATMENT_THRESHOLD = 0.3
    DECLINE_THRESHOLD = -5.0   
    
    # Domain rule thresholds
    CRITICAL_HEALTH_SCORE = 40
    HIGH_TREATMENT_FREQUENCY = 0.15   
    MAX_DAYS_WITHOUT_CHECKUP = 90
    OVERDUE_VACCINATIONS_CRITICAL = 2
    
    def __init__(self, model_dir: str = "models", use_mlflow: bool = True):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(parents=True, exist_ok=True)
        self.risk_model: lgb.LGBMRegressor | None = None
        
        self.treatment_model: lgb.LGBMClassifier | None = None
        
        self.decline_model: lgb.LGBMRegressor | None = None
        
        self.label_encoders: dict[str, LabelEncoder] = {}
        self.feature_columns: list[str] = []
        self.metadata: dict[str, Any] = {}
        
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
        
        bool_cols = ["hrf_has_chronic_condition", "hrf_weight_loss_flag"]
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

        for col in self.CATEGORICAL_FEATURES:
            encoded_col = f"{col}_encoded"
            if encoded_col in df.columns:
                feature_cols.append(encoded_col)
        
        if len(feature_cols) > 15:
            print(f"Warning: Truncating features from {len(feature_cols)} to 15")
            feature_cols = feature_cols[:15]
        
        return feature_cols
    
    def _compute_class_balance(self, y: pd.Series) -> float:
        """Compute scale_pos_weight for imbalanced classification."""
        n_pos = y.sum()
        n_neg = len(y) - n_pos
        if n_pos == 0:
            return 1.0
        return n_neg / n_pos
    
    def _apply_domain_rules(
        self,
        features: dict[str, Any],
        result: dict[str, Any],
    ) -> dict[str, Any]:
        """
        Apply domain rules to override/adjust model predictions.
        
        Domain rules ensure high recall for critical cases.
        """
        flags = []
        
        # Rule 1: Critical health score → auto-flag as high risk
        health_score = features.get("hrf_current_health_score", 50)
        if health_score < self.CRITICAL_HEALTH_SCORE:
            result["treatment_likely"] = True
            result["treatment_probability"] = max(
                result.get("treatment_probability", 0), 0.7
            )
            flags.append("critical_health_score")
        
        # Rule 2: High treatment frequency → likely needs treatment
        treatment_freq = features.get("hrf_treatment_frequency_30d", 0)
        if treatment_freq >= self.HIGH_TREATMENT_FREQUENCY:
            result["treatment_likely"] = True
            result["treatment_probability"] = max(
                result.get("treatment_probability", 0), 0.6
            )
            flags.append("high_treatment_frequency")
        
        # Rule 3: Overdue vaccinations → elevate risk
        overdue_vacc = features.get("hrf_overdue_vaccinations", 0)
        if overdue_vacc >= self.OVERDUE_VACCINATIONS_CRITICAL:
            result["predicted_risk_score"] = max(
                result.get("predicted_risk_score", 0),
                50 + (overdue_vacc * 5)
            )
            flags.append("overdue_vaccinations")
        
        # Rule 4: Long time since checkup → flag for attention
        days_since_checkup = features.get("hrf_days_since_last_checkup", 0)
        if days_since_checkup > self.MAX_DAYS_WITHOUT_CHECKUP:
            flags.append("overdue_checkup")
        
        # Rule 5: Chronic condition + weight loss → high decline risk
        if features.get("hrf_has_chronic_condition") and features.get("hrf_weight_loss_flag"):
            result["health_declining"] = True
            result["predicted_score_delta"] = min(
                result.get("predicted_score_delta", 0), -10
            )
            flags.append("chronic_plus_weight_loss")
        
        # Rule 6: Recent severe treatments → auto-flag
        severe_count = features.get("hrf_severe_treatment_count_30d", 0)
        if severe_count >= 2:
            result["treatment_likely"] = True
            flags.append("recent_severe_treatments")
        
        if flags:
            result["domain_rules_triggered"] = flags
        
        return result
    
    def train(
        self,
        data_path: str = "data/training/health_risk_prediction.csv",
        test_size: float = 0.2,
        n_estimators: int = 100,
        learning_rate: float = 0.1,
        max_depth: int = 6,
        num_leaves: int = 31,
        task: str = "all",  # "risk", "treatment", "decline", or "all"
    ) -> dict[str, Any]:
        """
        Train the health risk prediction models.
        
        Uses:
        - Class balancing for treatment classifier
        - Regression for decline (predicts score delta)
        - Recall-focused metrics (F2-score)
        
        Args:
            data_path: Path to training CSV
            test_size: Fraction for test split
            n_estimators: Number of boosting rounds
            learning_rate: Learning rate
            max_depth: Max tree depth
            num_leaves: Max leaves per tree
            task: Which model(s) to train
            
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
        
        X = df[self.feature_columns]
        
        results = {
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
            "thresholds": {
                "treatment": self.TREATMENT_THRESHOLD,
                "decline": self.DECLINE_THRESHOLD,
            },
        }
        
        if task in ["all", "risk"] and self.TARGET_RISK_SCORE in df.columns:
            y_risk = df[self.TARGET_RISK_SCORE]
            X_train, X_test, y_train, y_test = train_test_split(
                X, y_risk, test_size=test_size, random_state=42
            )
            
            self.risk_model = lgb.LGBMRegressor(
                n_estimators=n_estimators,
                learning_rate=learning_rate,
                max_depth=max_depth,
                num_leaves=num_leaves,
                random_state=42,
                verbose=-1,
            )
            
            self.risk_model.fit(
                X_train, y_train,
                eval_set=[(X_test, y_test)],
                callbacks=[lgb.early_stopping(stopping_rounds=10, verbose=False)],
            )
            
            y_pred = self.risk_model.predict(X_test)
            results["risk_model"] = {
                "mae": float(mean_absolute_error(y_test, y_pred)),
                "rmse": float(np.sqrt(mean_squared_error(y_test, y_pred))),
                "r2": float(r2_score(y_test, y_pred)),
            }
            print(f"✓ Risk model MAE: {results['risk_model']['mae']:.2f}")
        
        if task in ["all", "treatment"] and self.TARGET_TREATMENT_NEEDED in df.columns:
            y_treatment = df[self.TARGET_TREATMENT_NEEDED].astype(int)
            
            unique_classes = y_treatment.nunique()
            if unique_classes < 2:
                print(f"⚠ Treatment target has only {unique_classes} class(es), skipping")
                results["treatment_model"] = {
                    "warning": "Insufficient class diversity",
                }
            else:
                # Calculate class imbalance for scale_pos_weight
                scale_pos_weight = self._compute_class_balance(y_treatment)
                print(f"  Class balance: scale_pos_weight={scale_pos_weight:.2f}")
                
                X_train, X_test, y_train, y_test = train_test_split(
                    X, y_treatment, test_size=test_size, random_state=42, stratify=y_treatment
                )
                
                # LightGBM with class balancing
                self.treatment_model = lgb.LGBMClassifier(
                    n_estimators=n_estimators,
                    learning_rate=learning_rate,
                    max_depth=max_depth,
                    num_leaves=num_leaves,
                    scale_pos_weight=scale_pos_weight,  # Class balancing
                    random_state=42,
                    verbose=-1,
                )
                
                self.treatment_model.fit(
                    X_train, y_train,
                    eval_set=[(X_test, y_test)],
                    callbacks=[lgb.early_stopping(stopping_rounds=10, verbose=False)],
                )
                
                # Predictions with LOW threshold (0.3 instead of 0.5)
                y_pred_proba = self.treatment_model.predict_proba(X_test)[:, 1]
                y_pred = (y_pred_proba >= self.TREATMENT_THRESHOLD).astype(int)
                
                # Handle AUC calculation
                try:
                    auc_score = float(roc_auc_score(y_test, y_pred_proba))
                except ValueError:
                    auc_score = 0.0
                
                # Calculate recall-focused metrics
                recall = float(recall_score(y_test, y_pred, zero_division=0))
                precision = float(precision_score(y_test, y_pred, zero_division=0))
                f1 = float(f1_score(y_test, y_pred, zero_division=0))
                f2 = float(fbeta_score(y_test, y_pred, beta=2, zero_division=0))  # F2 weights recall 2x
                
                results["treatment_model"] = {
                    "recall": recall,        # PRIMARY METRIC
                    "f2_score": f2,          # Recall-weighted F-score
                    "precision": precision,
                    "f1": f1,
                    "accuracy": float(accuracy_score(y_test, y_pred)),
                    "auc_roc": auc_score,
                    "threshold": self.TREATMENT_THRESHOLD,
                    "class_balance": scale_pos_weight,
                }
                print(f"✓ Treatment model RECALL: {recall:.3f} (F2: {f2:.3f}, AUC: {auc_score:.3f})")
        
        # ===== TASK 3: Health Decline (REGRESSION - predicts score delta) =====
        # Instead of binary classification, predict how much the health score will change
        if task in ["all", "decline"]:
            # Create score delta target if not present
            if self.TARGET_SCORE_DELTA not in df.columns:
                if self.TARGET_HEALTH_DECLINED in df.columns:
                    # Synthesize: declined=-10, stable=0 (rough approximation)
                    df[self.TARGET_SCORE_DELTA] = df[self.TARGET_HEALTH_DECLINED].apply(
                        lambda x: -10 if x else 0
                    )
                    print("  Note: Synthesized score_delta from health_declined binary")
            
            if self.TARGET_SCORE_DELTA in df.columns:
                y_delta = df[self.TARGET_SCORE_DELTA]
                X_train, X_test, y_train, y_test = train_test_split(
                    X, y_delta, test_size=test_size, random_state=42
                )
                
                self.decline_model = lgb.LGBMRegressor(
                    n_estimators=n_estimators,
                    learning_rate=learning_rate,
                    max_depth=max_depth,
                    num_leaves=num_leaves,
                    random_state=42,
                    verbose=-1,
                )
                
                self.decline_model.fit(
                    X_train, y_train,
                    eval_set=[(X_test, y_test)],
                    callbacks=[lgb.early_stopping(stopping_rounds=10, verbose=False)],
                )
                
                y_pred = self.decline_model.predict(X_test)
                
                # Convert to binary for recall calculation
                y_test_binary = (y_test <= self.DECLINE_THRESHOLD).astype(int)
                y_pred_binary = (y_pred <= self.DECLINE_THRESHOLD).astype(int)
                
                recall = float(recall_score(y_test_binary, y_pred_binary, zero_division=0))
                
                results["decline_model"] = {
                    "mae": float(mean_absolute_error(y_test, y_pred)),
                    "rmse": float(np.sqrt(mean_squared_error(y_test, y_pred))),
                    "r2": float(r2_score(y_test, y_pred)),
                    "recall_at_threshold": recall,  # Recall for detecting declines
                    "threshold": self.DECLINE_THRESHOLD,
                    "model_type": "regression",  # NOT classification
                }
                print(f"✓ Decline model MAE: {results['decline_model']['mae']:.2f} (decline recall: {recall:.3f})")
            else:
                print("⚠ No decline target available, skipping")
        
        # Feature importance (from risk model)
        if self.risk_model:
            feature_importance = dict(zip(
                self.feature_columns,
                self.risk_model.feature_importances_.tolist()
            ))
            feature_importance = dict(sorted(
                feature_importance.items(),
                key=lambda x: x[1],
                reverse=True
            ))
            results["feature_importance"] = feature_importance
        
        self.metadata = results
        
        # Log to MLflow
        if self.use_mlflow and self.mlflow_tracker:
            try:
                self._log_to_mlflow(results)
            except Exception as e:
                print(f"Warning: MLflow logging failed: {e}")
        
        return results

    def _log_to_mlflow(self, results: dict[str, Any]) -> None:
        """Log training results to MLflow."""
        with self.mlflow_tracker.start_run(
            run_name=f"health-model-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}",
            tags={
                "model_type": "health_risk",
                "model_framework": "lightgbm",
                "design": "15-feature-recall-focused",
            }
        ) as run:
            # Log hyperparameters
            mlflow.log_params(results.get("hyperparameters", {}))
            mlflow.log_params({
                "training_samples": results.get("samples"),
                "feature_count": results.get("features"),
                "treatment_threshold": self.TREATMENT_THRESHOLD,
                "decline_threshold": self.DECLINE_THRESHOLD,
            })
            
            # Log metrics for each model (recall prominently)
            for model_name in ["risk_model", "treatment_model", "decline_model"]:
                if model_name in results:
                    for metric_name, value in results[model_name].items():
                        if isinstance(value, (int, float)) and not isinstance(value, bool):
                            mlflow.log_metric(f"{model_name}_{metric_name}", value)
            
            # Log feature importance
            if "feature_importance" in results:
                importance_path = "/tmp/health_feature_importance.json"
                with open(importance_path, "w") as f:
                    json.dump(results["feature_importance"], f, indent=2)
                mlflow.log_artifact(importance_path, "feature_importance")
            
            # Log the risk model
            if self.risk_model:
                mlflow.lightgbm.log_model(
                    self.risk_model,
                    artifact_path="risk_model",
                    registered_model_name="health-risk-model",
                )
            
            self.mlflow_run_id = run.info.run_id
            self.metadata["mlflow_run_id"] = self.mlflow_run_id
            print(f"Logged to MLflow (run_id: {self.mlflow_run_id})")
    
    def predict(
        self,
        features: dict[str, Any],
        horizon_days: int = 7,
    ) -> dict[str, Any]:
        """
        Predict health risk for an animal.
        
        Uses low thresholds (0.3) for high recall and applies domain rules.
        
        Args:
            features: Feature dictionary
            horizon_days: Prediction horizon in days
            
        Returns:
            Prediction results with domain rule adjustments
        """
        if self.risk_model is None and self.treatment_model is None:
            raise ValueError("No model trained. Call train() first.")
        
        # Create DataFrame
        features["horizon_days"] = horizon_days
        df = pd.DataFrame([features])
        
        # Prepare features
        df = self._prepare_features(df, fit_encoders=False)
        
        # Ensure all feature columns exist
        for col in self.feature_columns:
            if col not in df.columns:
                df[col] = 0
        
        X = df[self.feature_columns]
        
        result = {
            "horizon_days": horizon_days,
            "current_health_score": features.get("hrf_current_health_score", 50),
            "thresholds_used": {
                "treatment": self.TREATMENT_THRESHOLD,
                "decline": self.DECLINE_THRESHOLD,
            },
        }
        
        # Risk score prediction
        if self.risk_model:
            risk_score = float(self.risk_model.predict(X)[0])
            result["predicted_risk_score"] = round(max(0, min(100, risk_score)), 1)
            result["risk_level"] = self._get_risk_level(risk_score)
        
        # Treatment probability with LOW threshold (0.3)
        if self.treatment_model:
            treatment_proba = float(self.treatment_model.predict_proba(X)[0, 1])
            result["treatment_probability"] = round(treatment_proba, 3)
            result["treatment_likely"] = bool(treatment_proba >= self.TREATMENT_THRESHOLD)
        
        # Health decline (REGRESSION: predict score delta)
        if self.decline_model:
            score_delta = float(self.decline_model.predict(X)[0])
            result["predicted_score_delta"] = round(score_delta, 1)
            result["health_declining"] = bool(score_delta <= self.DECLINE_THRESHOLD)
            result["trend"] = self._get_trend(score_delta)
        
        # Apply domain rules (Step 7)
        result = self._apply_domain_rules(features, result)
        
        return result
    
    def _get_risk_level(self, risk_score: float) -> str:
        """Convert risk score to risk level."""
        if risk_score < 20:
            return "low"
        elif risk_score < 40:
            return "moderate"
        elif risk_score < 60:
            return "elevated"
        elif risk_score < 80:
            return "high"
        else:
            return "critical"
    
    def _get_trend(self, score_delta: float) -> str:
        """Convert score delta to trend label."""
        if score_delta <= -10:
            return "declining_rapidly"
        elif score_delta <= -5:
            return "declining"
        elif score_delta < 5:
            return "stable"
        elif score_delta < 10:
            return "improving"
        else:
            return "improving_rapidly"
    
    def predict_batch(
        self,
        features_list: list[dict[str, Any]],
        horizon_days: int = 7,
    ) -> list[dict[str, Any]]:
        """Predict health risk for multiple animals."""
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
        Explain a health risk prediction using SHAP.
        
        Args:
            features: Feature dictionary
            horizon_days: Prediction horizon
            
        Returns:
            Explanation with SHAP values
        """
        if self.risk_model is None:
            raise ValueError("No model trained. Call train() first.")
        
        # Get base prediction
        prediction = self.predict(features, horizon_days)
        
        # Prepare features for SHAP
        features["horizon_days"] = horizon_days
        df = pd.DataFrame([features])
        df = self._prepare_features(df, fit_encoders=False)
        
        for col in self.feature_columns:
            if col not in df.columns:
                df[col] = 0
        
        X = df[self.feature_columns]
        
        # Create SHAP explainer
        explainer = shap.TreeExplainer(self.risk_model)
        shap_values = explainer.shap_values(X)
        
        # Get SHAP values for this prediction
        shap_dict = dict(zip(self.feature_columns, shap_values[0]))
        
        # Separate positive and negative contributions
        positive_factors = []
        negative_factors = []
        
        for feature, shap_val in sorted(shap_dict.items(), key=lambda x: abs(x[1]), reverse=True):
            feature_val = X[feature].values[0]
            factor = {
                "feature": feature,
                "value": float(feature_val) if not pd.isna(feature_val) else None,
                "contribution": round(float(shap_val), 3),
                "direction": "increases_risk" if shap_val > 0 else "decreases_risk",
            }
            
            if shap_val > 0:
                positive_factors.append(factor)
            else:
                negative_factors.append(factor)
        
        # Build explanation summary
        top_risk_factors = [f["feature"] for f in positive_factors[:3]]
        top_protective_factors = [f["feature"] for f in negative_factors[:3]]
        
        summary = self._build_explanation_summary(
            prediction.get("predicted_risk_score", 0),
            prediction.get("risk_level", "unknown"),
            top_risk_factors,
            top_protective_factors,
            horizon_days,
        )
        
        return {
            **prediction,
            "base_value": float(explainer.expected_value),
            "explanation": {
                "summary": summary,
                "risk_factors": positive_factors[:5],
                "protective_factors": negative_factors[:5],
                "all_contributions": shap_dict,
            },
        }
    
    def _build_explanation_summary(
        self,
        risk_score: float,
        risk_level: str,
        risk_factors: list[str],
        protective_factors: list[str],
        horizon_days: int,
    ) -> str:
        """Build a human-readable explanation summary."""
        summary_parts = [
            f"Health risk assessment for the next {horizon_days} days: "
            f"{risk_level.upper()} risk (score: {risk_score:.1f}/100)."
        ]
        
        if risk_factors:
            risk_names = [self._friendly_feature_name(f) for f in risk_factors[:2]]
            summary_parts.append(f"Main risk factors: {', '.join(risk_names)}.")
        
        if protective_factors:
            protective_names = [self._friendly_feature_name(f) for f in protective_factors[:2]]
            summary_parts.append(f"Protective factors: {', '.join(protective_names)}.")
        
        return " ".join(summary_parts)
    
    def _friendly_feature_name(self, feature: str) -> str:
        """Convert feature name to user-friendly name."""
        name_map = {
            "hrf_treatment_frequency_30d": "recent treatment frequency",
            "hrf_severe_treatment_count_30d": "severe treatments",
            "hrf_overdue_vaccinations": "overdue vaccinations",
            "hrf_has_chronic_condition": "chronic condition",
            "hrf_weight_loss_flag": "weight loss",
            "hrf_vaccination_coverage": "vaccination coverage",
            "hrf_current_health_score": "current health score",
            "hrf_days_since_last_treatment": "time since treatment",
            "hrf_days_since_last_checkup": "time since checkup",
            "hrf_age_risk_factor": "age-related risk",
            "wf_adg_7d": "daily weight gain",
            "wf_current_weight": "current weight",
            "horizon_days": "prediction window",
        }
        return name_map.get(feature, feature.replace("hrf_", "").replace("wf_", "").replace("_", " "))
    
    def get_global_explanations(
        self,
        sample_size: int = 100,
    ) -> dict[str, Any]:
        """
        Get global feature importance using SHAP.
        
        Args:
            sample_size: Number of samples for SHAP analysis
            
        Returns:
            Global explanation data
        """
        if self.risk_model is None:
            raise ValueError("No model trained. Call train() first.")
        
        try:
            data_path = "data/training/health_risk_prediction.csv"
            df = pd.read_csv(data_path)
            df = self._prepare_features(df, fit_encoders=False)
            
            for col in self.feature_columns:
                if col not in df.columns:
                    df[col] = 0
            
            X = df[self.feature_columns]
            
            if len(X) > sample_size:
                X = X.sample(n=sample_size, random_state=42)
            
            explainer = shap.TreeExplainer(self.risk_model)
            shap_values = explainer.shap_values(X)
            
            mean_abs_shap = np.abs(shap_values).mean(axis=0)
            feature_importance = dict(zip(self.feature_columns, mean_abs_shap.tolist()))
            
            sorted_features = sorted(
                feature_importance.items(),
                key=lambda x: x[1],
                reverse=True
            )
            
            return {
                "sample_size": len(X),
                "base_value": float(explainer.expected_value),
                "top_features": [f[0] for f in sorted_features[:10]],
                "feature_importance": {
                    f: {
                        "mean_abs_shap": round(v, 4),
                        "friendly_name": self._friendly_feature_name(f),
                    }
                    for f, v in sorted_features[:15]
                },
                "summary": f"Top predictors: {', '.join([self._friendly_feature_name(f[0]) for f in sorted_features[:3]])}",
            }
        except FileNotFoundError:
            return {
                "feature_importance": self.metadata.get("feature_importance", {}),
                "note": "Using model's built-in feature importance",
            }
    
    def get_model_info(self) -> dict[str, Any]:
        """Get information about the loaded model."""
        info = {
            "status": "loaded" if self.risk_model else "not_loaded",
            "risk_model": self.risk_model is not None,
            "treatment_model": self.treatment_model is not None,
            "decline_model": self.decline_model is not None,
            "decline_model_type": "regression",  # NOT classification
            "feature_count": len(self.feature_columns),
            "features": self.feature_columns,
            "thresholds": {
                "treatment": self.TREATMENT_THRESHOLD,
                "decline": self.DECLINE_THRESHOLD,
            },
            "design": "15-feature-recall-focused",
        }
        
        if self.metadata:
            info.update({
                "trained_at": self.metadata.get("trained_at"),
                "samples": self.metadata.get("samples"),
                "metrics": {
                    k: v for k, v in self.metadata.items()
                    if k.endswith("_model") and isinstance(v, dict)
                },
            })
        
        return info
    
    def save(self, path: str | None = None) -> str:
        """Save models to disk."""
        if path is None:
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            path = str(self.model_dir / f"health_model_{timestamp}")
        
        Path(path).mkdir(parents=True, exist_ok=True)
        
        # Save main models
        if self.risk_model:
            with open(f"{path}/risk_model.pkl", "wb") as f:
                pickle.dump(self.risk_model, f)
        
        if self.treatment_model:
            with open(f"{path}/treatment_model.pkl", "wb") as f:
                pickle.dump(self.treatment_model, f)
        
        if self.decline_model:
            with open(f"{path}/decline_model.pkl", "wb") as f:
                pickle.dump(self.decline_model, f)
        
        # Save encoders
        with open(f"{path}/label_encoders.pkl", "wb") as f:
            pickle.dump(self.label_encoders, f)
        
        # Save metadata
        with open(f"{path}/metadata.json", "w") as f:
            json.dump({
                "feature_columns": self.feature_columns,
                "metadata": self.metadata,
                "thresholds": {
                    "treatment": self.TREATMENT_THRESHOLD,
                    "decline": self.DECLINE_THRESHOLD,
                },
            }, f, indent=2, default=str)
        
        # Update latest symlink
        latest_path = self.model_dir / "health_model_latest"
        if latest_path.exists():
            latest_path.unlink()
        latest_path.symlink_to(Path(path).name)
        
        print(f"Model saved to {path}")
        return path
    
    def load(self, path: str | None = None) -> None:
        """Load models from disk."""
        if path is None:
            path = str(self.model_dir / "health_model_latest")
        
        if not Path(path).exists():
            raise FileNotFoundError(f"Model not found at {path}")
        
        # Load main models
        risk_path = f"{path}/risk_model.pkl"
        if Path(risk_path).exists():
            with open(risk_path, "rb") as f:
                self.risk_model = pickle.load(f)
        
        treatment_path = f"{path}/treatment_model.pkl"
        if Path(treatment_path).exists():
            with open(treatment_path, "rb") as f:
                self.treatment_model = pickle.load(f)
        
        decline_path = f"{path}/decline_model.pkl"
        if Path(decline_path).exists():
            with open(decline_path, "rb") as f:
                self.decline_model = pickle.load(f)
        
        # Load encoders
        with open(f"{path}/label_encoders.pkl", "rb") as f:
            self.label_encoders = pickle.load(f)
        
        # Load metadata
        with open(f"{path}/metadata.json", "r") as f:
            data = json.load(f)
            self.feature_columns = data["feature_columns"]
            self.metadata = data["metadata"]
        
        print(f"Model loaded from {path}")
