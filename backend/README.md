# Farm Manager ML Backend

Machine learning analytics backend for livestock management. Provides weight prediction, health risk assessment, and AI-powered insights for farm operations.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Server](#running-the-server)
- [API Documentation](#api-documentation)
- [MLflow Experiment Tracking](#mlflow-experiment-tracking)
- [Model Training](#model-training)
- [Testing](#testing)
- [Roadmap](#roadmap)

---

## Overview

This backend service powers the Farm Manager application with machine learning capabilities. It connects to a Supabase PostgreSQL database containing farm data and provides:

- Real-time feature computation from raw farm data
- Weight prediction models with confidence intervals
- SHAP-based model explainability
- MLflow experiment tracking and model registry
- RESTful API for Flutter mobile app integration

## Features

### Feature Engineering
- Weight features: current weight, growth velocity, ADG, weight trends
- Health features: health score, treatment history, vaccination compliance
- Batch computation pipeline for training data generation

### Machine Learning Models
- LightGBM weight prediction (MAE: ~1.5kg, MAPE: ~4%)
- Ensemble models (LightGBM + RandomForest + GradientBoosting + Ridge)
- SHAP explainability for prediction transparency
- Support for 7, 14, and 30-day prediction horizons

### MLOps
- MLflow experiment tracking
- Model versioning and registry
- Stage management (Staging, Production)
- Hyperparameter tuning with Optuna

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | FastAPI |
| Database | Supabase (PostgreSQL) |
| ML Framework | LightGBM, scikit-learn |
| Explainability | SHAP |
| Experiment Tracking | MLflow |
| Hyperparameter Tuning | Optuna |
| Package Manager | uv |
| Python Version | 3.12 |

## Project Structure

```
backend/
├── app/
│   ├── api/                    # API route handlers
│   │   ├── features.py         # Feature computation endpoints
│   │   ├── health.py           # Health check endpoints
│   │   ├── mlflow_api.py       # MLflow tracking endpoints
│   │   ├── models.py           # Model training/prediction endpoints
│   │   └── pipeline.py         # Batch pipeline endpoints
│   ├── core/                   # Core configuration
│   │   ├── config.py           # Pydantic settings
│   │   ├── database.py         # Supabase repository
│   │   └── mlflow_tracking.py  # MLflow integration
│   ├── features/               # Feature computation logic
│   │   ├── health_features.py  # Health feature calculations
│   │   └── weight_features.py  # Weight feature calculations
│   ├── models/                 # ML models
│   │   ├── schemas.py          # Pydantic data models
│   │   └── weight_model.py     # Weight prediction model
│   ├── services/               # Business logic services
│   │   ├── feature_pipeline.py # Feature computation pipeline
│   │   ├── job_store.py        # Async job tracking
│   │   └── synthetic_data.py   # Synthetic data generator
│   └── main.py                 # FastAPI application factory
├── data/
│   └── training/               # Training datasets
├── models/                     # Saved model artifacts
├── docs/                       # Documentation
│   └── UI_DESIGN.md            # Flutter UI design specs
├── .env                        # Environment variables (not in git)
├── .env.example                # Environment template
├── pyproject.toml              # Project dependencies
├── mlflow.db                   # MLflow tracking database
└── ML_PIPELINE_ROADMAP.md      # Development roadmap
```

## Installation

### Prerequisites

- Python 3.12+
- uv package manager

### Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd farm-manager/backend
```

2. Install uv (if not installed):
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

3. Create virtual environment and install dependencies:
```bash
uv venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows
uv sync
```

## Configuration

Create a `.env` file in the backend directory:

```env
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-role-key

# API Settings
API_HOST=0.0.0.0
API_PORT=8000
DEBUG=true

# MLflow Settings
MLFLOW_TRACKING_URI=sqlite:///mlflow.db
MLFLOW_EXPERIMENT_NAME=farm-ml-pipeline

# Model Settings
MODEL_CACHE_DIR=models
FEATURE_STORE_PATH=data/features
```

**Note:** The service role key is required to bypass Row Level Security (RLS) for ML pipeline operations.

## Running the Server

### Development Mode

```bash
source .venv/bin/activate
uvicorn app.main:app --reload
```

The API will be available at `http://127.0.0.1:8000`

### View API Documentation

- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

## API Documentation

### Health Check

```
GET /health
GET /health/db
```

### Feature Computation

```
POST /api/v1/features/weight/{animal_id}    # Compute weight features
POST /api/v1/features/health/{animal_id}    # Compute health features
POST /api/v1/features/combined/{animal_id}  # Compute all features
```

### Pipeline Operations

```
POST /api/v1/pipeline/compute-batch         # Batch feature computation
POST /api/v1/pipeline/generate-training-data # Generate training dataset
POST /api/v1/pipeline/generate-synthetic    # Generate synthetic test data
GET  /api/v1/pipeline/jobs/{job_id}         # Check job status
```

### Model Operations

```
POST /api/v1/models/weight/train            # Train weight model
POST /api/v1/models/weight/predict          # Single prediction
POST /api/v1/models/weight/predict-batch    # Batch predictions
POST /api/v1/models/weight/explain          # SHAP explanation
GET  /api/v1/models/weight/explain/global   # Global feature importance
GET  /api/v1/models/weight/info             # Model information
GET  /api/v1/models/weight/feature-importance # Feature importance scores
```

### MLflow Operations

```
GET  /api/v1/mlflow/status                  # MLflow configuration
GET  /api/v1/mlflow/experiments             # List experiments
GET  /api/v1/mlflow/runs                    # List training runs
GET  /api/v1/mlflow/runs/{run_id}           # Get run details
POST /api/v1/mlflow/runs/compare            # Compare multiple runs
GET  /api/v1/mlflow/models                  # List registered models
POST /api/v1/mlflow/models/promote          # Promote model to stage
```

### Example: Train and Predict

```bash
# Train a model
curl -X POST http://127.0.0.1:8000/api/v1/models/weight/train \
  -H "Content-Type: application/json" \
  -d '{
    "n_estimators": 100,
    "learning_rate": 0.1,
    "max_depth": 6,
    "save_model": true
  }'

# Make a prediction
curl -X POST http://127.0.0.1:8000/api/v1/models/weight/predict \
  -H "Content-Type: application/json" \
  -d '{
    "features": {
      "species": "pig",
      "wf_current_weight": 60,
      "wf_adg_lifetime": 0.8,
      "hf_health_score": 85
    },
    "horizon_days": 14
  }'

# Get SHAP explanation
curl -X POST http://127.0.0.1:8000/api/v1/models/weight/explain \
  -H "Content-Type: application/json" \
  -d '{
    "features": {
      "species": "pig",
      "wf_current_weight": 60,
      "wf_adg_lifetime": 0.8
    },
    "horizon_days": 14
  }'
```

## MLflow Experiment Tracking

### Starting the MLflow UI

```bash
source .venv/bin/activate
mlflow ui --backend-store-uri sqlite:///mlflow.db --port 5000
```

Open http://127.0.0.1:5000 in your browser to view:
- Training run history with metrics
- Parameter comparison across runs
- Model registry and versioning
- Artifact storage (models, feature importance)

### Model Registry Workflow

1. Train multiple models with different hyperparameters
2. Compare runs in MLflow UI or via API
3. Promote best model to "Staging" for testing
4. Promote to "Production" for serving

```bash
# Promote model to production
curl -X POST http://127.0.0.1:8000/api/v1/mlflow/models/promote \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "weight-prediction-model",
    "version": 1,
    "stage": "Production"
  }'
```

## Model Training

### Generate Synthetic Data (Optional)

For testing without real data:

```bash
curl -X POST "http://127.0.0.1:8000/api/v1/pipeline/generate-synthetic?num_animals=20&days_of_history=90"
```

### Generate Training Data

```bash
curl -X POST http://127.0.0.1:8000/api/v1/pipeline/generate-training-data \
  -H "Content-Type: application/json" \
  -d '{
    "output_path": "data/training/weight_prediction.csv",
    "horizons": [7, 14, 30]
  }'
```

### Train Model

```bash
curl -X POST http://127.0.0.1:8000/api/v1/models/weight/train \
  -H "Content-Type: application/json" \
  -d '{
    "data_path": "data/training/weight_prediction.csv",
    "n_estimators": 100,
    "learning_rate": 0.1,
    "use_optuna": false,
    "save_model": true
  }'
```

### Train with Hyperparameter Tuning

```bash
curl -X POST http://127.0.0.1:8000/api/v1/models/weight/train \
  -H "Content-Type: application/json" \
  -d '{
    "use_optuna": true,
    "n_trials": 50,
    "save_model": true
  }'
```

## Testing

### Run Health Check

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/health/db
```

### Test Feature Computation

```bash
# Replace with a valid animal ID from your database
curl -X POST http://127.0.0.1:8000/api/v1/features/combined/{animal_id}
```

## Roadmap

See [ML_PIPELINE_ROADMAP.md](ML_PIPELINE_ROADMAP.md) for the full development plan.

### Completed

- [x] Feature engineering pipeline (weight and health features)
- [x] LightGBM weight prediction model
- [x] Ensemble models
- [x] SHAP explainability
- [x] MLflow experiment tracking and model registry
- [x] Synthetic data generator
- [x] REST API endpoints

### In Progress

- [ ] Health risk prediction model
- [ ] ONNX/TFLite model conversion for mobile
- [ ] Drift detection and monitoring
- [ ] Automated retraining pipeline

### Planned

- [ ] Flutter integration with TFLite models
- [ ] Offline inference support
- [ ] Computer vision for body condition scoring
- [ ] Financial forecasting

## License

Proprietary - All rights reserved.

---

For questions or issues, please contact the development team.
