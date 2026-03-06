from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # API Settings
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = False
    api_title: str = "Farm ML API"
    api_version: str = "0.1.0"

    # Supabase Settings
    supabase_url: str
    supabase_key: str
    supabase_service_key: str | None = None

    # MLflow Settings
    mlflow_tracking_uri: str = "sqlite:///mlflow.db"
    mlflow_experiment_name: str = "farm-ml-pipeline"
    
    # Gemini API Key
    gemini_api_key: str
    vertex_api_key: str

    # Model Settings
    model_cache_dir: str = "models"
    feature_store_path: str = "data/features"


@lru_cache
def get_settings() -> Settings:
    return Settings()

