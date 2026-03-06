import json
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Any, Generator

import mlflow
from mlflow.tracking import MlflowClient

from app.core.config import get_settings


class MLflowTracker:
    """
    MLflow integration for experiment tracking and model registry.
    
    Provides:
    - Experiment tracking (parameters, metrics, artifacts)
    - Model versioning and registry
    - Model stage management (staging -> production)
    """
    
    def __init__(self):
        self.settings = get_settings()
        self._setup_mlflow()
        self.client = MlflowClient()
    
    def _setup_mlflow(self) -> None:
        mlflow.set_tracking_uri(self.settings.mlflow_tracking_uri)
        
        experiment = mlflow.get_experiment_by_name(self.settings.mlflow_experiment_name)
        if experiment is None:
            self.experiment_id = mlflow.create_experiment(
                self.settings.mlflow_experiment_name,
                tags={"project": "farm-manager", "domain": "livestock-ml"}
            )
        else:
            self.experiment_id = experiment.experiment_id
        
        mlflow.set_experiment(self.settings.mlflow_experiment_name)
        print(f"MLflow tracking URI: {self.settings.mlflow_tracking_uri}")
        print(f"MLflow experiment: {self.settings.mlflow_experiment_name}")
    
    @contextmanager
    def start_run(
        self,
        run_name: str | None = None,
        tags: dict[str, str] | None = None,
    ) -> Generator[mlflow.ActiveRun, None, None]:
        """
        Start an MLflow run context.
        
        Usage:
            with tracker.start_run("weight-model-v1") as run:
                mlflow.log_param("n_estimators", 100)
                mlflow.log_metric("mae", 1.5)
        """
        default_tags = {
            "model_type": "weight_prediction",
            "framework": "lightgbm",
        }
        if tags:
            default_tags.update(tags)
        
        with mlflow.start_run(run_name=run_name, tags=default_tags) as run:
            yield run
    
    def log_training_run(
        self,
        model_name: str,
        hyperparameters: dict[str, Any],
        metrics: dict[str, Any],
        feature_importance: dict[str, float],
        training_data_info: dict[str, Any],
        model_artifact_path: str | None = None,
        tags: dict[str, str] | None = None,
    ) -> str:
        """
        Log a complete training run to MLflow.
        
        Args:
            model_name: Name for the run
            hyperparameters: Model hyperparameters
            metrics: Training and test metrics
            feature_importance: Feature importance scores
            training_data_info: Info about training data
            model_artifact_path: Local path to model artifacts
            tags: Additional tags
            
        Returns:
            Run ID
        """
        with self.start_run(run_name=model_name, tags=tags) as run:
            mlflow.log_params(hyperparameters)
            
            mlflow.log_params({
                "training_samples": training_data_info.get("samples", 0),
                "feature_count": training_data_info.get("features", 0),
                "test_size": training_data_info.get("test_size", 0.2),
            })
            
            for split, split_metrics in metrics.items():
                if isinstance(split_metrics, dict):
                    for metric_name, value in split_metrics.items():
                        mlflow.log_metric(f"{split}_{metric_name}", value)
                else:
                    mlflow.log_metric(split, split_metrics)
            
            importance_path = "/tmp/feature_importance.json"
            with open(importance_path, "w") as f:
                json.dump(feature_importance, f, indent=2)
            mlflow.log_artifact(importance_path, "feature_importance")
            
            if model_artifact_path and Path(model_artifact_path).exists():
                mlflow.log_artifacts(model_artifact_path, "model")
            
            return run.info.run_id
    
    def log_lightgbm_model(
        self,
        model,
        model_name: str,
        signature=None,
        input_example=None,
    ) -> str | None:
        """
        Log a LightGBM model to MLflow with proper model registry.
        
        Args:
            model: Trained LightGBM model
            model_name: Name for the registered model
            signature: MLflow model signature
            input_example: Example input for the model
            
        Returns:
            Model URI or None
        """
        try:
            import mlflow.lightgbm
            
            model_info = mlflow.lightgbm.log_model(
                model,
                artifact_path="model",
                registered_model_name=model_name,
                signature=signature,
            )
            print(f"Model logged and registered: {model_name}")
            return model_info.model_uri
        except Exception as e:
            print(f"Warning: Could not log LightGBM model: {e}")
            return None
    
    def get_latest_model_version(
        self,
        model_name: str,
        stage: str = "Staging",
    ) -> dict[str, Any] | None:
        """
        Get the latest model version from registry.
        
        Args:
            model_name: Name of registered model
            stage: Model stage (None, Staging, Production, Archived)
            
        Returns:
            Model version info or None
        """
        try:
            versions = self.client.get_latest_versions(model_name, stages=[stage])
            if versions:
                v = versions[0]
                return {
                    "version": v.version,
                    "stage": v.current_stage,
                    "run_id": v.run_id,
                    "source": v.source,
                    "status": v.status,
                    "created_at": datetime.fromtimestamp(v.creation_timestamp / 1000).isoformat(),
                }
            return None
        except Exception as e:
            print(f"Error getting model version: {e}")
            return None
    
    def promote_model(
        self,
        model_name: str,
        version: int,
        stage: str = "Staging",
    ) -> bool:
        """
        Promote a model version to a new stage.
        
        Args:
            model_name: Name of registered model
            version: Version number to promote
            stage: Target stage (Staging, Production, Archived)
            
        Returns:
            Success status
        """
        try:
            self.client.transition_model_version_stage(
                name=model_name,
                version=str(version),
                stage=stage,
            )
            print(f"Model {model_name} v{version} promoted to {stage}")
            return True
        except Exception as e:
            print(f"Error promoting model: {e}")
            return False
    
    def get_run_metrics(self, run_id: str) -> dict[str, Any]:
        """Get metrics for a specific run."""
        run = self.client.get_run(run_id)
        return {
            "run_id": run_id,
            "status": run.info.status,
            "start_time": datetime.fromtimestamp(run.info.start_time / 1000).isoformat(),
            "end_time": datetime.fromtimestamp(run.info.end_time / 1000).isoformat() if run.info.end_time else None,
            "metrics": run.data.metrics,
            "params": run.data.params,
            "tags": run.data.tags,
        }
    
    def list_experiments(self) -> list[dict[str, Any]]:
        """List all experiments."""
        experiments = self.client.search_experiments()
        return [
            {
                "id": exp.experiment_id,
                "name": exp.name,
                "artifact_location": exp.artifact_location,
                "lifecycle_stage": exp.lifecycle_stage,
            }
            for exp in experiments
        ]
    
    def list_runs(
        self,
        max_results: int = 10,
        order_by: str = "start_time DESC",
    ) -> list[dict[str, Any]]:
        """List recent runs in the experiment."""
        runs = self.client.search_runs(
            experiment_ids=[self.experiment_id],
            max_results=max_results,
            order_by=[order_by],
        )
        return [
            {
                "run_id": run.info.run_id,
                "run_name": run.info.run_name,
                "status": run.info.status,
                "start_time": datetime.fromtimestamp(run.info.start_time / 1000).isoformat(),
                "metrics": run.data.metrics,
            }
            for run in runs
        ]
    
    def list_model_versions(self, model_name: str) -> list[dict[str, Any]]:
        """List all versions of a registered model."""
        try:
            versions = self.client.search_model_versions(f"name='{model_name}'")
            return [
                {
                    "version": v.version,
                    "stage": v.current_stage,
                    "run_id": v.run_id,
                    "status": v.status,
                    "created_at": datetime.fromtimestamp(v.creation_timestamp / 1000).isoformat(),
                }
                for v in versions
            ]
        except Exception as e:
            print(f"Error listing model versions: {e}")
            return []
    
    def compare_runs(self, run_ids: list[str]) -> dict[str, Any]:
        """Compare metrics across multiple runs."""
        comparison = {}
        for run_id in run_ids:
            run = self.client.get_run(run_id)
            comparison[run_id] = {
                "run_name": run.info.run_name,
                "metrics": run.data.metrics,
                "params": run.data.params,
            }
        return comparison

_tracker: MLflowTracker | None = None


def get_mlflow_tracker() -> MLflowTracker:
    """Get or create MLflow tracker singleton."""
    global _tracker
    if _tracker is None:
        _tracker = MLflowTracker()
    return _tracker
