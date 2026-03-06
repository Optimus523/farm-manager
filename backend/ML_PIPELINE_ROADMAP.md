# Farm Manager - ML Analytics Pipeline

A comprehensive plan for building a production-grade machine learning pipeline for livestock management analytics.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Data Infrastructure](#3-data-infrastructure)
4. [Feature Engineering Platform](#4-feature-engineering-platform)
5. [Model Development](#5-model-development)
6. [Training Infrastructure](#6-training-infrastructure)
7. [Model Serving & Deployment](#7-model-serving--deployment)
8. [On-Device Inference (Edge ML)](#8-on-device-inference-edge-ml)
9. [Monitoring & MLOps](#9-monitoring--mlops)
10. [Model Catalog](#10-model-catalog)
11. [Implementation Roadmap](#11-implementation-roadmap)
12. [Technical Stack](#12-technical-stack)

---

## 1. Executive Summary

### Vision
Build an intelligent, self-improving ML system that transforms raw farm data into actionable insights, predictions, and automated recommendations—working both online and offline.

### Key Objectives
- **Predictive Analytics**: Forecast animal growth, health risks, breeding outcomes
- **Prescriptive Analytics**: Recommend optimal actions (feed amounts, breeding times, treatments)
- **Anomaly Detection**: Early warning system for health issues, abnormal patterns
- **Optimization**: Maximize profitability through resource optimization
- **Automation**: Reduce manual decision-making with intelligent defaults

### Success Metrics
| Metric | Target |
|--------|--------|
| Weight prediction accuracy (MAPE) | < 5% |
| Health risk detection recall | > 90% |
| Breeding success prediction AUC | > 0.85 |
| Feed optimization cost savings | > 15% |
| Model inference latency (on-device) | < 100ms |
| Offline model availability | 100% |

---

## 2. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER APP                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Data Entry  │  │ Predictions │  │   Alerts    │  │   Recommendations   │ │
│  │   Screens   │  │  Dashboard  │  │   Center    │  │      Engine         │ │
│  └──────┬──────┘  └──────▲──────┘  └──────▲──────┘  └──────────▲──────────┘ │
│         │                │                │                     │           │
│  ┌──────▼────────────────┴────────────────┴─────────────────────┴─────────┐ │
│  │                      ML INFERENCE LAYER (TFLite)                        │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐  │ │
│  │  │   Weight    │  │   Health    │  │  Breeding   │  │     Feed      │  │ │
│  │  │  Predictor  │  │ Risk Model  │  │  Optimizer  │  │   Optimizer   │  │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                     FEATURE STORE (Local SQLite)                        │ │
│  │  • Pre-computed features  • Historical aggregations  • Model inputs     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Sync (when online)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLOUD ML PLATFORM                                  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        DATA LAKE (Supabase + S3)                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │  Raw Data   │  │  Processed  │  │  Features   │  │   Model     │  │   │
│  │  │   (Bronze)  │  │   (Silver)  │  │   (Gold)    │  │  Artifacts  │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                      FEATURE ENGINEERING PIPELINE                       │ │
│  │  Apache Spark / Pandas │ dbt transformations │ Scheduled jobs           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                        MODEL TRAINING PLATFORM                          │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐  │ │
│  │  │  Experiment │  │   Model     │  │  Hyperopt   │  │    Model      │  │ │
│  │  │  Tracking   │  │  Registry   │  │   Tuning    │  │   Validation  │  │ │
│  │  │  (MLflow)   │  │  (MLflow)   │  │  (Optuna)   │  │   Pipeline    │  │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                         MODEL SERVING LAYER                             │ │
│  │  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐ │ │
│  │  │   REST API          │  │   Batch Inference   │  │  TFLite Export  │ │ │
│  │  │   (FastAPI)         │  │   (Scheduled)       │  │  (Edge Deploy)  │ │ │
│  │  └─────────────────────┘  └─────────────────────┘  └─────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌─────────────────────────────────▼──────────────────────────────────────┐ │
│  │                         MONITORING & ALERTING                           │ │
│  │  Model drift detection │ Performance dashboards │ Automated retraining  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Design Principles
1. **Offline-First**: All critical models run on-device via TensorFlow Lite
2. **Continuous Learning**: Models improve with new data automatically
3. **Explainability**: Provide interpretable predictions (feature importance, confidence)
4. **Scalability**: Handle farms from 10 to 10,000+ animals
5. **Privacy-Preserving**: Federated learning options for sensitive data

---

## 3. Data Infrastructure

### 3.1 Data Sources

| Source | Data Type | Volume | Frequency |
|--------|-----------|--------|-----------|
| Weight Records | Numeric | ~10 records/animal/month | Daily-Weekly |
| Feeding Records | Numeric + Categorical | ~30 records/animal/month | Daily |
| Health Records | Text + Categorical | ~2-5 records/animal/month | Event-driven |
| Breeding Records | Categorical + Date | ~1-2 records/animal/year | Event-driven |
| Environmental | Time-series | Continuous | Real-time (IoT) |
| Financial | Numeric | ~50-100 transactions/month | Event-driven |
| Images | Binary (BLOB) | ~1-5 per animal | Periodic |

### 3.2 Data Lake Architecture (Medallion Architecture)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           BRONZE LAYER (Raw)                             │
│  • Raw Supabase CDC streams                                              │
│  • Unprocessed sensor data                                               │
│  • Original images                                                       │
│  • Schema: JSON/Parquet, partitioned by date                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ Cleansing, Validation, Deduplication
┌─────────────────────────────────────────────────────────────────────────┐
│                          SILVER LAYER (Cleaned)                          │
│  • Validated records with data quality scores                            │
│  • Standardized schemas                                                  │
│  • Linked entities (animal ↔ farm ↔ user)                               │
│  • Schema: Parquet, partitioned by farm_id + date                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ Aggregation, Feature Computation
┌─────────────────────────────────────────────────────────────────────────┐
│                           GOLD LAYER (Features)                          │
│  • Pre-computed ML features                                              │
│  • Aggregated metrics (daily, weekly, monthly)                          │
│  • Model-ready datasets                                                  │
│  • Schema: Parquet, optimized for ML training                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Data Quality Framework

```python
# Data quality checks for each record type
class DataQualityConfig:
    weight_records = {
        "completeness": ["animal_id", "weight", "date", "farm_id"],
        "validity": {
            "weight": (0.1, 2000),  # kg range
            "date": "not_future",
        },
        "consistency": {
            "weight_change_rate": (-20, 20),  # max % change per day
        },
        "uniqueness": ["animal_id", "date", "measurement_type"],
    }
    
    health_records = {
        "completeness": ["animal_id", "date", "type"],
        "validity": {
            "type": ["vaccination", "medication", "checkup", "treatment", "observation"],
        },
        "timeliness": {
            "max_delay_hours": 72,  # Record should be entered within 72h
        },
    }
```

### 3.4 Real-time Data Pipeline

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Supabase   │────▶│   Kafka/    │────▶│   Stream    │────▶│   Feature   │
│  Realtime   │     │  Pub/Sub    │     │  Processor  │     │   Store     │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │   Trigger   │
                                        │  Inference  │
                                        └─────────────┘
```

---

## 4. Feature Engineering Platform

### 4.1 Feature Categories

#### Animal Static Features
```python
animal_static_features = {
    # Identity
    "animal_id": "string",
    "species": "categorical",  # cattle, goat, sheep, pig, poultry, rabbit
    "breed": "categorical",
    "gender": "binary",
    
    # Birth/Acquisition
    "birth_date": "date",
    "acquisition_date": "date",
    "acquisition_type": "categorical",  # born, purchased
    "acquisition_price": "numeric",
    
    # Genetics
    "mother_id": "string",
    "father_id": "string",
    "inbreeding_coefficient": "numeric",
    "genetic_merit_score": "numeric",  # computed from lineage
}
```

#### Animal Dynamic Features (Time-Series)
```python
animal_time_series_features = {
    # Weight trajectory
    "current_weight": "numeric",
    "weight_7d_ago": "numeric",
    "weight_30d_ago": "numeric",
    "weight_90d_ago": "numeric",
    "weight_change_7d": "numeric",
    "weight_change_30d": "numeric",
    "weight_velocity": "numeric",  # kg/day
    "weight_acceleration": "numeric",  # kg/day²
    "weight_percentile_by_age": "numeric",
    "weight_percentile_by_breed": "numeric",
    "days_since_last_weight": "numeric",
    
    # Growth metrics
    "average_daily_gain_7d": "numeric",
    "average_daily_gain_30d": "numeric",
    "average_daily_gain_lifetime": "numeric",
    "growth_curve_deviation": "numeric",  # vs expected
    
    # Feed metrics
    "feed_intake_7d_avg": "numeric",
    "feed_intake_30d_avg": "numeric",
    "feed_conversion_ratio_7d": "numeric",
    "feed_conversion_ratio_30d": "numeric",
    "feed_cost_per_kg_gain": "numeric",
    "days_since_last_feeding": "numeric",
    "feeding_regularity_score": "numeric",
    
    # Health metrics
    "health_score": "numeric",  # composite 0-100
    "days_since_last_health_check": "numeric",
    "vaccination_compliance_rate": "numeric",
    "treatment_count_30d": "numeric",
    "treatment_count_90d": "numeric",
    "sick_days_30d": "numeric",
    "recovery_rate": "numeric",
    
    # Status
    "current_status": "categorical",
    "days_in_current_status": "numeric",
    "status_change_count_90d": "numeric",
}
```

#### Breeding Features
```python
breeding_features = {
    # Reproductive history
    "total_breeding_attempts": "numeric",
    "successful_breedings": "numeric",
    "breeding_success_rate": "numeric",
    "avg_litter_size": "numeric",
    "total_offspring": "numeric",
    "live_offspring_rate": "numeric",
    
    # Current cycle (females)
    "days_since_last_heat": "numeric",
    "predicted_next_heat": "date",
    "heat_cycle_regularity": "numeric",
    "is_pregnant": "binary",
    "days_pregnant": "numeric",
    "expected_birth_date": "date",
    "pregnancy_risk_score": "numeric",
    
    # Sire metrics (males)
    "conception_rate_as_sire": "numeric",
    "offspring_survival_rate": "numeric",
    "offspring_avg_weight_at_weaning": "numeric",
}
```

#### Environmental Features
```python
environmental_features = {
    # Current conditions
    "temperature_current": "numeric",
    "humidity_current": "numeric",
    "heat_index": "numeric",
    
    # Historical
    "temperature_7d_avg": "numeric",
    "temperature_7d_min": "numeric",
    "temperature_7d_max": "numeric",
    "temperature_volatility_7d": "numeric",
    
    # Seasonal
    "season": "categorical",
    "day_of_year": "numeric",
    "is_extreme_weather": "binary",
    
    # Housing
    "stocking_density": "numeric",
    "pen_id": "categorical",
}
```

#### Farm-Level Features
```python
farm_features = {
    # Scale
    "total_animals": "numeric",
    "animals_by_species": "dict",
    "animals_by_status": "dict",
    
    # Performance
    "farm_avg_daily_gain": "numeric",
    "farm_mortality_rate_30d": "numeric",
    "farm_feed_efficiency": "numeric",
    
    # Financial
    "revenue_per_animal_30d": "numeric",
    "cost_per_animal_30d": "numeric",
    "profit_margin_30d": "numeric",
}
```

### 4.2 Feature Store Implementation

```python
# Feature Store Schema (SQLite for on-device, PostgreSQL for cloud)

class FeatureStore:
    """
    Dual-layer feature store:
    - Cloud: Full historical features in PostgreSQL/BigQuery
    - Device: Recent features in SQLite for offline inference
    """
    
    # On-device feature tables
    tables = {
        "animal_features": """
            CREATE TABLE animal_features (
                animal_id TEXT PRIMARY KEY,
                farm_id TEXT,
                feature_vector BLOB,  -- Serialized numpy array
                feature_version TEXT,
                computed_at TIMESTAMP,
                expires_at TIMESTAMP
            )
        """,
        
        "feature_metadata": """
            CREATE TABLE feature_metadata (
                feature_name TEXT PRIMARY KEY,
                feature_type TEXT,
                mean REAL,
                std REAL,
                min REAL,
                max REAL,
                null_rate REAL,
                updated_at TIMESTAMP
            )
        """,
    }
```

### 4.3 Feature Computation Pipeline

```python
# Scheduled feature computation (runs daily)

class FeatureComputationPipeline:
    
    def compute_weight_features(self, animal_id: str, as_of_date: date) -> dict:
        """Compute all weight-related features for an animal."""
        
        # Get historical weights
        weights = self.get_weight_history(animal_id, lookback_days=365)
        
        if len(weights) < 2:
            return self.default_weight_features()
        
        # Current and historical values
        features = {
            "current_weight": weights[-1].weight,
            "weight_7d_ago": self.get_weight_at(weights, as_of_date - timedelta(days=7)),
            "weight_30d_ago": self.get_weight_at(weights, as_of_date - timedelta(days=30)),
            "weight_90d_ago": self.get_weight_at(weights, as_of_date - timedelta(days=90)),
        }
        
        # Compute deltas
        features["weight_change_7d"] = features["current_weight"] - features["weight_7d_ago"]
        features["weight_change_30d"] = features["current_weight"] - features["weight_30d_ago"]
        
        # Compute velocity (kg/day) using linear regression
        recent_weights = [w for w in weights if w.date >= as_of_date - timedelta(days=14)]
        if len(recent_weights) >= 2:
            features["weight_velocity"] = self.compute_slope(recent_weights)
        
        # Compute acceleration (change in velocity)
        features["weight_acceleration"] = self.compute_acceleration(weights, as_of_date)
        
        # Average daily gain
        features["average_daily_gain_7d"] = features["weight_change_7d"] / 7
        features["average_daily_gain_30d"] = features["weight_change_30d"] / 30
        
        # Percentile calculations
        features["weight_percentile_by_age"] = self.compute_percentile(
            animal_id, features["current_weight"], groupby="age"
        )
        features["weight_percentile_by_breed"] = self.compute_percentile(
            animal_id, features["current_weight"], groupby="breed"
        )
        
        # Growth curve deviation
        expected_weight = self.get_expected_weight(animal_id, as_of_date)
        features["growth_curve_deviation"] = (
            (features["current_weight"] - expected_weight) / expected_weight * 100
        )
        
        return features
    
    def compute_health_score(self, animal_id: str, as_of_date: date) -> float:
        """
        Composite health score (0-100) based on multiple factors.
        """
        scores = []
        weights = []
        
        # Weight trajectory score (0-100)
        weight_features = self.compute_weight_features(animal_id, as_of_date)
        if weight_features["weight_velocity"] > 0:
            weight_score = min(100, 50 + weight_features["weight_velocity"] * 10)
        else:
            weight_score = max(0, 50 + weight_features["weight_velocity"] * 20)
        scores.append(weight_score)
        weights.append(0.3)
        
        # Vaccination compliance (0-100)
        vax_score = self.get_vaccination_compliance(animal_id) * 100
        scores.append(vax_score)
        weights.append(0.2)
        
        # Recent health events penalty
        recent_treatments = self.get_treatment_count(animal_id, days=30)
        health_event_score = max(0, 100 - recent_treatments * 15)
        scores.append(health_event_score)
        weights.append(0.3)
        
        # Feed consumption regularity
        feed_score = self.get_feeding_regularity_score(animal_id) * 100
        scores.append(feed_score)
        weights.append(0.2)
        
        # Weighted average
        return sum(s * w for s, w in zip(scores, weights))
```

---

## 5. Model Development

### 5.1 Weight Prediction Model

#### Objective
Predict animal weight at future dates (7, 14, 30, 90 days) with confidence intervals.

#### Model Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     WEIGHT PREDICTION ENSEMBLE                               │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    INPUT FEATURES (52 features)                      │    │
│  │  Animal: age, breed, gender, genetics (12)                          │    │
│  │  Weight history: velocities, percentiles, deviations (15)           │    │
│  │  Feed: intake, FCR, costs (8)                                       │    │
│  │  Health: score, treatments, vaccinations (10)                       │    │
│  │  Environment: temperature, season, housing (7)                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│           ┌────────────────────────┼────────────────────────┐               │
│           ▼                        ▼                        ▼               │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │   XGBoost       │    │   LightGBM      │    │   Neural Net    │         │
│  │   Regressor     │    │   Regressor     │    │   (MLP)         │         │
│  │                 │    │                 │    │                 │         │
│  │  • 500 trees    │    │  • 300 trees    │    │  • 3 layers     │         │
│  │  • depth 8      │    │  • leaves 64    │    │  • 128-64-32    │         │
│  │  • lr 0.05      │    │  • lr 0.1       │    │  • dropout 0.2  │         │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘         │
│           │                      │                      │                   │
│           └──────────────────────┼──────────────────────┘                   │
│                                  ▼                                          │
│                    ┌─────────────────────────┐                              │
│                    │   Meta-Learner          │                              │
│                    │   (Weighted Average)    │                              │
│                    │   Weights learned via   │                              │
│                    │   cross-validation      │                              │
│                    └────────────┬────────────┘                              │
│                                 │                                           │
│                                 ▼                                           │
│              ┌─────────────────────────────────────┐                       │
│              │  OUTPUT: weight_t+horizon ± CI      │                       │
│              │  Horizons: 7d, 14d, 30d, 90d        │                       │
│              │  Confidence: 80%, 95%               │                       │
│              └─────────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Training Strategy

```python
class WeightPredictionTrainer:
    
    def prepare_training_data(self):
        """
        Create training dataset with multiple prediction horizons.
        Each row: features at time t → weight at time t+horizon
        """
        horizons = [7, 14, 30, 90]  # days
        
        training_data = []
        
        for animal in self.get_all_animals():
            weights = self.get_weight_history(animal.id)
            
            for i, current_weight in enumerate(weights[:-max(horizons)]):
                features = self.compute_features(animal.id, current_weight.date)
                
                for horizon in horizons:
                    future_idx = i + horizon
                    if future_idx < len(weights):
                        target = weights[future_idx].weight
                        
                        training_data.append({
                            **features,
                            "horizon_days": horizon,
                            "target_weight": target,
                        })
        
        return pd.DataFrame(training_data)
    
    def train_with_cross_validation(self, df: pd.DataFrame):
        """
        Time-series aware cross-validation.
        """
        # Time-based split (no future leakage)
        tscv = TimeSeriesSplit(n_splits=5, gap=7)
        
        models = {
            "xgboost": XGBRegressor(**self.xgb_params),
            "lightgbm": LGBMRegressor(**self.lgbm_params),
            "neural_net": self.build_neural_net(),
        }
        
        cv_scores = {name: [] for name in models}
        
        for train_idx, val_idx in tscv.split(df):
            X_train, X_val = df.iloc[train_idx], df.iloc[val_idx]
            y_train, y_val = X_train["target_weight"], X_val["target_weight"]
            
            for name, model in models.items():
                model.fit(X_train.drop("target_weight", axis=1), y_train)
                preds = model.predict(X_val.drop("target_weight", axis=1))
                mape = mean_absolute_percentage_error(y_val, preds)
                cv_scores[name].append(mape)
        
        # Learn ensemble weights
        self.ensemble_weights = self.optimize_ensemble_weights(cv_scores)
        
        return cv_scores
```

#### Confidence Intervals

```python
class ConfidenceEstimator:
    """
    Quantile regression for prediction intervals.
    """
    
    def __init__(self):
        self.quantile_models = {
            0.025: LGBMRegressor(objective="quantile", alpha=0.025),
            0.10: LGBMRegressor(objective="quantile", alpha=0.10),
            0.90: LGBMRegressor(objective="quantile", alpha=0.90),
            0.975: LGBMRegressor(objective="quantile", alpha=0.975),
        }
    
    def predict_with_intervals(self, X) -> dict:
        point_estimate = self.main_model.predict(X)
        
        return {
            "prediction": point_estimate,
            "ci_80_lower": self.quantile_models[0.10].predict(X),
            "ci_80_upper": self.quantile_models[0.90].predict(X),
            "ci_95_lower": self.quantile_models[0.025].predict(X),
            "ci_95_upper": self.quantile_models[0.975].predict(X),
        }
```

### 5.2 Health Risk Prediction Model

#### Objective
Predict probability of health issues in the next 7/14/30 days with risk factors.

#### Model Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    HEALTH RISK PREDICTION SYSTEM                             │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    MULTI-TASK LEARNING MODEL                         │    │
│  │                                                                      │    │
│  │  Shared Encoder (Transformer-based)                                 │    │
│  │  ┌────────────────────────────────────────────────────────────┐     │    │
│  │  │  Time-series embedding │ Attention over history │ 256-dim  │     │    │
│  │  └────────────────────────────────────────────────────────────┘     │    │
│  │                              │                                       │    │
│  │         ┌────────────────────┼────────────────────┐                 │    │
│  │         ▼                    ▼                    ▼                 │    │
│  │  ┌─────────────┐    ┌─────────────────┐    ┌─────────────────┐     │    │
│  │  │ Risk Head   │    │ Diagnosis Head  │    │ Severity Head   │     │    │
│  │  │ (Binary)    │    │ (Multi-label)   │    │ (Ordinal)       │     │    │
│  │  │             │    │                 │    │                 │     │    │
│  │  │ P(sick in   │    │ P(respiratory)  │    │ Severity 1-5    │     │    │
│  │  │ next 7d)    │    │ P(digestive)    │    │ if sick         │     │    │
│  │  │             │    │ P(injury)       │    │                 │     │    │
│  │  │             │    │ P(parasites)    │    │                 │     │    │
│  │  └─────────────┘    └─────────────────┘    └─────────────────┘     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    EXPLAINABILITY MODULE (SHAP)                      │    │
│  │  • Top 5 risk factors with contribution scores                      │    │
│  │  • Counterfactual explanations ("if weight increased by 5kg...")    │    │
│  │  • Similar historical cases for reference                           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Feature Engineering for Health

```python
class HealthFeatureEngineer:
    
    def compute_risk_features(self, animal_id: str, as_of_date: date) -> dict:
        """
        Features specifically designed for health risk prediction.
        """
        features = {}
        
        # Weight anomalies (strong health indicator)
        weight_features = self.compute_weight_features(animal_id, as_of_date)
        features["weight_loss_7d"] = max(0, -weight_features["weight_change_7d"])
        features["weight_loss_14d"] = max(0, -weight_features.get("weight_change_14d", 0))
        features["is_underweight"] = weight_features["weight_percentile_by_age"] < 0.1
        features["rapid_weight_change"] = abs(weight_features["weight_velocity"]) > 0.5
        
        # Feed anomalies
        feed_history = self.get_feeding_history(animal_id, days=14)
        features["feed_intake_decline"] = self.compute_trend(feed_history, "amount")
        features["missed_feedings_7d"] = self.count_missed_feedings(animal_id, days=7)
        features["appetite_score"] = self.compute_appetite_score(feed_history)
        
        # Recent health events
        health_history = self.get_health_history(animal_id, days=90)
        features["treatments_30d"] = len([h for h in health_history if h.days_ago <= 30])
        features["treatments_7d"] = len([h for h in health_history if h.days_ago <= 7])
        features["days_since_last_treatment"] = self.days_since_last_treatment(health_history)
        features["chronic_condition_flag"] = self.has_chronic_condition(health_history)
        
        # Vaccination status
        features["overdue_vaccinations"] = self.count_overdue_vaccinations(animal_id)
        features["vaccination_coverage"] = self.compute_vaccination_coverage(animal_id)
        
        # Age-related risk
        animal = self.get_animal(animal_id)
        features["age_days"] = (as_of_date - animal.birth_date).days
        features["is_juvenile"] = features["age_days"] < 90
        features["is_geriatric"] = features["age_days"] > 2000  # varies by species
        
        # Environmental stress
        env = self.get_environment_data(animal.farm_id, as_of_date)
        features["heat_stress_index"] = self.compute_heat_stress(env)
        features["cold_stress_index"] = self.compute_cold_stress(env)
        features["weather_volatility_7d"] = env.get("temperature_volatility_7d", 0)
        
        # Herd-level risk
        features["farm_disease_outbreak"] = self.check_outbreak_status(animal.farm_id)
        features["pen_infection_rate"] = self.compute_pen_infection_rate(animal.pen_id)
        features["recent_new_arrivals"] = self.count_new_arrivals(animal.farm_id, days=14)
        
        # Behavioral patterns (if available from sensors)
        if self.has_activity_data(animal_id):
            activity = self.get_activity_data(animal_id, days=7)
            features["activity_decline"] = self.compute_trend(activity, "steps")
            features["lying_time_increase"] = self.compute_trend(activity, "lying_time")
            features["rumination_time"] = activity.get("avg_rumination_minutes", None)
        
        return features
```

#### Anomaly Detection Component

```python
class HealthAnomalyDetector:
    """
    Unsupervised anomaly detection for unusual patterns.
    """
    
    def __init__(self):
        self.isolation_forest = IsolationForest(
            n_estimators=200,
            contamination=0.05,  # expect ~5% anomalies
            random_state=42
        )
        self.autoencoder = self.build_autoencoder()
    
    def build_autoencoder(self):
        """
        Autoencoder for reconstruction-based anomaly detection.
        """
        input_dim = 40  # number of health features
        
        encoder = tf.keras.Sequential([
            tf.keras.layers.Dense(32, activation='relu'),
            tf.keras.layers.Dense(16, activation='relu'),
            tf.keras.layers.Dense(8, activation='relu'),  # bottleneck
        ])
        
        decoder = tf.keras.Sequential([
            tf.keras.layers.Dense(16, activation='relu'),
            tf.keras.layers.Dense(32, activation='relu'),
            tf.keras.layers.Dense(input_dim, activation='linear'),
        ])
        
        return tf.keras.Model(
            inputs=encoder.input,
            outputs=decoder(encoder.output)
        )
    
    def compute_anomaly_score(self, features: np.ndarray) -> dict:
        """
        Ensemble anomaly score from multiple methods.
        """
        # Isolation Forest score
        if_score = -self.isolation_forest.score_samples(features.reshape(1, -1))[0]
        
        # Autoencoder reconstruction error
        reconstructed = self.autoencoder.predict(features.reshape(1, -1))
        ae_score = np.mean((features - reconstructed) ** 2)
        
        # Statistical z-scores for key features
        z_scores = self.compute_z_scores(features)
        max_z = np.max(np.abs(z_scores))
        
        # Combined score
        combined_score = 0.4 * if_score + 0.3 * ae_score + 0.3 * max_z
        
        return {
            "anomaly_score": combined_score,
            "is_anomaly": combined_score > self.threshold,
            "isolation_forest_score": if_score,
            "reconstruction_error": ae_score,
            "max_z_score": max_z,
            "anomalous_features": self.get_anomalous_features(z_scores),
        }
```

### 5.3 Breeding Optimization Model

#### Objective
Optimize breeding decisions: timing, partner selection, and outcome prediction.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     BREEDING OPTIMIZATION SYSTEM                             │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      MODEL 1: HEAT DETECTION                         │    │
│  │  Input: Behavioral patterns, hormonal cycles, history               │    │
│  │  Output: P(in heat), optimal insemination window                    │    │
│  │  Architecture: LSTM for cycle prediction                            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────▼───────────────────────────────────┐    │
│  │                    MODEL 2: CONCEPTION PREDICTOR                     │    │
│  │  Input: Female features, sire features, timing, environment         │    │
│  │  Output: P(conception), expected litter size distribution           │    │
│  │  Architecture: Gradient Boosting + Bayesian inference               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────▼───────────────────────────────────┐    │
│  │                     MODEL 3: SIRE RECOMMENDER                        │    │
│  │  Input: Female genetics, breeding goals, available sires            │    │
│  │  Output: Ranked sire list with expected outcomes                    │    │
│  │  Architecture: Learning-to-Rank (LambdaMART)                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────▼───────────────────────────────────┐    │
│  │                   MODEL 4: GESTATION MONITOR                         │    │
│  │  Input: Pregnancy day, weight trajectory, health indicators         │    │
│  │  Output: Risk score, expected birth date refinement, litter health  │    │
│  │  Architecture: Survival analysis + risk regression                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────▼───────────────────────────────────┐    │
│  │                    GENETIC MERIT CALCULATOR                          │    │
│  │  • Inbreeding coefficient computation                               │    │
│  │  • Expected Progeny Differences (EPD)                               │    │
│  │  • Breeding value estimation (BLUP)                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Genetic Merit Computation

```python
class GeneticMeritCalculator:
    """
    Compute genetic merit scores using pedigree data.
    """
    
    def compute_inbreeding_coefficient(self, animal_id: str) -> float:
        """
        Wright's coefficient of inbreeding using pedigree traversal.
        """
        pedigree = self.build_pedigree_graph(animal_id, depth=6)
        
        # Find common ancestors
        common_ancestors = self.find_common_ancestors(
            pedigree, 
            animal_id
        )
        
        # Calculate F using path method
        F = 0
        for ancestor_id, paths in common_ancestors.items():
            ancestor_F = self.get_inbreeding_coefficient(ancestor_id)
            for path_sire, path_dam in paths:
                n = len(path_sire) + len(path_dam) - 1
                F += (0.5 ** n) * (1 + ancestor_F)
        
        return F
    
    def compute_breeding_value(self, animal_id: str, trait: str) -> float:
        """
        Estimated Breeding Value using BLUP methodology.
        """
        # Simplified BLUP (full implementation requires linear algebra)
        own_performance = self.get_trait_performance(animal_id, trait)
        parent_avg = self.get_parent_average(animal_id, trait)
        progeny_avg = self.get_progeny_average(animal_id, trait)
        
        # Weights based on heritability and data availability
        h2 = self.heritability[trait]
        
        if progeny_avg is not None:
            n_progeny = self.count_progeny(animal_id)
            progeny_weight = (n_progeny * h2) / (4 + (n_progeny - 1) * h2)
            return progeny_weight * progeny_avg + (1 - progeny_weight) * parent_avg
        elif own_performance is not None:
            return h2 * own_performance + (1 - h2) * parent_avg
        else:
            return parent_avg
    
    def recommend_sire(
        self, 
        female_id: str, 
        breeding_goals: dict,
        candidate_sires: List[str]
    ) -> List[dict]:
        """
        Rank sires by expected genetic merit of offspring.
        """
        female_ebv = {
            trait: self.compute_breeding_value(female_id, trait)
            for trait in breeding_goals.keys()
        }
        
        recommendations = []
        
        for sire_id in candidate_sires:
            sire_ebv = {
                trait: self.compute_breeding_value(sire_id, trait)
                for trait in breeding_goals.keys()
            }
            
            # Expected offspring value
            offspring_ebv = {
                trait: (female_ebv[trait] + sire_ebv[trait]) / 2
                for trait in breeding_goals.keys()
            }
            
            # Inbreeding risk
            hypothetical_F = self.compute_hypothetical_inbreeding(
                female_id, sire_id
            )
            
            # Score based on goals
            score = sum(
                offspring_ebv[trait] * weight
                for trait, weight in breeding_goals.items()
            )
            score -= hypothetical_F * 100  # Penalty for inbreeding
            
            recommendations.append({
                "sire_id": sire_id,
                "score": score,
                "expected_offspring_ebv": offspring_ebv,
                "inbreeding_coefficient": hypothetical_F,
                "conception_probability": self.predict_conception(
                    female_id, sire_id
                ),
            })
        
        return sorted(recommendations, key=lambda x: -x["score"])
```

### 5.4 Feed Optimization Model

#### Objective
Minimize feed costs while maximizing growth and maintaining health.

```python
class FeedOptimizer:
    """
    Multi-objective optimization for feed management.
    """
    
    def __init__(self):
        self.growth_model = self.load_model("weight_predictor")
        self.health_model = self.load_model("health_risk")
        self.fcr_model = self.load_model("feed_conversion")
    
    def optimize_feed_plan(
        self, 
        animal_id: str,
        target_weight: float,
        target_date: date,
        constraints: dict
    ) -> dict:
        """
        Find optimal feeding plan using constrained optimization.
        """
        current_state = self.get_current_state(animal_id)
        
        # Decision variables
        # x[0]: daily_feed_amount (kg)
        # x[1]: feed_type_idx
        # x[2]: feeding_frequency
        
        def objective(x):
            """
            Minimize: cost - growth_value + health_risk_penalty
            """
            feed_amount, feed_type_idx, frequency = x
            feed_type = self.feed_types[int(feed_type_idx)]
            
            # Predict growth with this feed plan
            predicted_weight = self.growth_model.predict(
                current_state, 
                feed_amount=feed_amount,
                feed_type=feed_type,
                days=(target_date - date.today()).days
            )
            
            # Calculate cost
            total_cost = feed_amount * feed_type.price_per_kg * days
            
            # Health risk with this plan
            health_risk = self.health_model.predict(
                current_state,
                feed_amount=feed_amount
            )
            
            # Multi-objective: minimize cost, maximize growth, minimize risk
            growth_gap = max(0, target_weight - predicted_weight)
            
            return (
                total_cost * 1.0 +           # Cost weight
                growth_gap * 50.0 +          # Growth penalty
                health_risk * 100.0          # Health risk penalty
            )
        
        # Constraints
        bounds = [
            (constraints["min_feed"], constraints["max_feed"]),  # feed amount
            (0, len(self.feed_types) - 1),                       # feed type
            (1, 4),                                               # frequency
        ]
        
        # Optimize
        result = scipy.optimize.minimize(
            objective,
            x0=[current_state["current_feed"], 0, 2],
            bounds=bounds,
            method='SLSQP'
        )
        
        optimal_feed, optimal_type_idx, optimal_freq = result.x
        
        return {
            "recommended_daily_feed": round(optimal_feed, 2),
            "recommended_feed_type": self.feed_types[int(optimal_type_idx)].name,
            "recommended_frequency": int(optimal_freq),
            "estimated_cost": self.calculate_total_cost(result.x, target_date),
            "estimated_weight_at_target": self.growth_model.predict(
                current_state, *result.x, (target_date - date.today()).days
            ),
            "health_risk_score": self.health_model.predict(current_state, result.x),
            "cost_savings_vs_current": self.calculate_savings(
                current_state, result.x
            ),
        }
```

### 5.5 Financial Forecasting Model

#### Objective
Predict revenue, expenses, and profitability with scenario analysis.

```python
class FinancialForecaster:
    """
    Time-series forecasting for farm financials.
    """
    
    def __init__(self):
        # Revenue forecasting (Prophet + ML hybrid)
        self.revenue_model = Prophet(
            yearly_seasonality=True,
            weekly_seasonality=False,
            daily_seasonality=False
        )
        
        # Expense prediction (category-wise)
        self.expense_models = {
            category: LGBMRegressor()
            for category in ExpenseCategory
        }
        
        # Profitability model (combines all)
        self.profitability_model = XGBRegressor()
    
    def forecast(
        self, 
        farm_id: str, 
        horizon_months: int = 12
    ) -> dict:
        """
        Generate financial forecast with confidence intervals.
        """
        historical = self.get_financial_history(farm_id)
        
        # Revenue forecast
        revenue_forecast = self.forecast_revenue(historical, horizon_months)
        
        # Expense forecast by category
        expense_forecast = {}
        for category in ExpenseCategory:
            expense_forecast[category] = self.forecast_expense(
                historical, category, horizon_months
            )
        
        # Combine for profitability
        monthly_forecasts = []
        for month in range(horizon_months):
            month_date = date.today() + relativedelta(months=month)
            
            revenue = revenue_forecast[month]
            expenses = sum(
                expense_forecast[cat][month] 
                for cat in ExpenseCategory
            )
            
            monthly_forecasts.append({
                "month": month_date.strftime("%Y-%m"),
                "revenue": revenue["mean"],
                "revenue_ci_lower": revenue["ci_lower"],
                "revenue_ci_upper": revenue["ci_upper"],
                "expenses": expenses["mean"],
                "profit": revenue["mean"] - expenses["mean"],
                "profit_margin": (revenue["mean"] - expenses["mean"]) / revenue["mean"]
                    if revenue["mean"] > 0 else 0,
            })
        
        return {
            "forecast": monthly_forecasts,
            "summary": self.compute_forecast_summary(monthly_forecasts),
            "scenarios": self.generate_scenarios(farm_id, horizon_months),
        }
    
    def generate_scenarios(self, farm_id: str, horizon_months: int) -> dict:
        """
        Generate best/base/worst case scenarios.
        """
        base_forecast = self.forecast(farm_id, horizon_months)
        
        scenarios = {
            "best_case": self.apply_scenario_multipliers(
                base_forecast, 
                revenue_mult=1.15, 
                expense_mult=0.90
            ),
            "base_case": base_forecast,
            "worst_case": self.apply_scenario_multipliers(
                base_forecast,
                revenue_mult=0.85,
                expense_mult=1.15
            ),
            "disease_outbreak": self.simulate_disease_impact(base_forecast),
            "market_price_drop": self.simulate_price_drop(base_forecast, -20),
        }
        
        return scenarios
```

---

## 6. Training Infrastructure

### 6.1 Training Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TRAINING PIPELINE                                   │
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   Trigger   │    │    Data     │    │   Feature   │    │   Train     │  │
│  │  (Schedule/ │───▶│  Snapshot   │───▶│  Pipeline   │───▶│   Job       │  │
│  │   Manual)   │    │             │    │             │    │             │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘  │
│                                                                   │         │
│  ┌─────────────────────────────────────────────────────────────────┘         │
│  │                                                                          │
│  ▼                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │  Hyperopt   │    │   Model     │    │  Validate   │    │  Register   │  │
│  │  (Optuna)   │───▶│  Training   │───▶│  & Test     │───▶│  (MLflow)   │  │
│  │             │    │             │    │             │    │             │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └──────┬──────┘  │
│                                                                   │         │
│  ┌─────────────────────────────────────────────────────────────────┘         │
│  │                                                                          │
│  ▼                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │  Champion   │    │   Export    │    │   Deploy    │    │   Monitor   │  │
│  │  Selection  │───▶│  to TFLite  │───▶│  to Edge    │───▶│  & Alert    │  │
│  │             │    │             │    │             │    │             │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Hyperparameter Optimization

```python
class HyperparameterOptimizer:
    """
    Automated hyperparameter tuning using Optuna.
    """
    
    def optimize(
        self, 
        model_type: str, 
        X_train, y_train, 
        X_val, y_val,
        n_trials: int = 100
    ) -> dict:
        
        def objective(trial):
            if model_type == "xgboost":
                params = {
                    "n_estimators": trial.suggest_int("n_estimators", 100, 1000),
                    "max_depth": trial.suggest_int("max_depth", 3, 12),
                    "learning_rate": trial.suggest_float("learning_rate", 0.01, 0.3, log=True),
                    "subsample": trial.suggest_float("subsample", 0.6, 1.0),
                    "colsample_bytree": trial.suggest_float("colsample_bytree", 0.6, 1.0),
                    "min_child_weight": trial.suggest_int("min_child_weight", 1, 10),
                    "reg_alpha": trial.suggest_float("reg_alpha", 1e-8, 10.0, log=True),
                    "reg_lambda": trial.suggest_float("reg_lambda", 1e-8, 10.0, log=True),
                }
                model = XGBRegressor(**params)
            
            elif model_type == "lightgbm":
                params = {
                    "n_estimators": trial.suggest_int("n_estimators", 100, 1000),
                    "num_leaves": trial.suggest_int("num_leaves", 16, 256),
                    "learning_rate": trial.suggest_float("learning_rate", 0.01, 0.3, log=True),
                    "feature_fraction": trial.suggest_float("feature_fraction", 0.6, 1.0),
                    "bagging_fraction": trial.suggest_float("bagging_fraction", 0.6, 1.0),
                    "min_child_samples": trial.suggest_int("min_child_samples", 5, 100),
                }
                model = LGBMRegressor(**params)
            
            elif model_type == "neural_net":
                params = {
                    "layers": trial.suggest_int("layers", 2, 5),
                    "units": trial.suggest_categorical("units", [32, 64, 128, 256]),
                    "dropout": trial.suggest_float("dropout", 0.1, 0.5),
                    "learning_rate": trial.suggest_float("learning_rate", 1e-4, 1e-2, log=True),
                }
                model = self.build_neural_net(**params)
            
            # Train and validate
            model.fit(X_train, y_train)
            predictions = model.predict(X_val)
            
            # Return validation metric
            return mean_absolute_percentage_error(y_val, predictions)
        
        study = optuna.create_study(direction="minimize")
        study.optimize(objective, n_trials=n_trials, n_jobs=-1)
        
        return {
            "best_params": study.best_params,
            "best_value": study.best_value,
            "study": study,
        }
```

### 6.3 Model Validation Framework

```python
class ModelValidator:
    """
    Comprehensive model validation before deployment.
    """
    
    def validate(self, model, test_data: dict) -> dict:
        """
        Run all validation checks.
        """
        results = {
            "performance_metrics": self.compute_metrics(model, test_data),
            "fairness_analysis": self.check_fairness(model, test_data),
            "stability_tests": self.test_stability(model, test_data),
            "edge_case_tests": self.test_edge_cases(model),
            "latency_tests": self.measure_latency(model),
            "memory_tests": self.measure_memory(model),
        }
        
        results["passed"] = self.evaluate_gates(results)
        
        return results
    
    def compute_metrics(self, model, test_data: dict) -> dict:
        """
        Standard ML metrics.
        """
        predictions = model.predict(test_data["X"])
        actuals = test_data["y"]
        
        return {
            "mape": mean_absolute_percentage_error(actuals, predictions),
            "mae": mean_absolute_error(actuals, predictions),
            "rmse": np.sqrt(mean_squared_error(actuals, predictions)),
            "r2": r2_score(actuals, predictions),
            "mape_by_segment": self.compute_metrics_by_segment(
                predictions, actuals, test_data["segments"]
            ),
        }
    
    def check_fairness(self, model, test_data: dict) -> dict:
        """
        Ensure model doesn't discriminate by protected attributes.
        """
        fairness_report = {}
        
        for attribute in ["breed", "farm_id", "gender"]:
            if attribute in test_data:
                groups = test_data[attribute].unique()
                metrics_by_group = {}
                
                for group in groups:
                    mask = test_data[attribute] == group
                    group_preds = model.predict(test_data["X"][mask])
                    group_actuals = test_data["y"][mask]
                    
                    metrics_by_group[group] = {
                        "mape": mean_absolute_percentage_error(group_actuals, group_preds),
                        "count": mask.sum(),
                    }
                
                # Check for disparate impact
                mapes = [m["mape"] for m in metrics_by_group.values()]
                fairness_report[attribute] = {
                    "metrics_by_group": metrics_by_group,
                    "max_disparity": max(mapes) - min(mapes),
                    "is_fair": max(mapes) / min(mapes) < 1.25,  # 25% tolerance
                }
        
        return fairness_report
    
    def test_stability(self, model, test_data: dict) -> dict:
        """
        Test model stability under perturbations.
        """
        base_predictions = model.predict(test_data["X"])
        
        stability_results = []
        
        for feature in test_data["X"].columns:
            # Add small noise to feature
            perturbed_X = test_data["X"].copy()
            noise = np.random.normal(0, 0.01, size=len(perturbed_X))
            perturbed_X[feature] = perturbed_X[feature] * (1 + noise)
            
            perturbed_predictions = model.predict(perturbed_X)
            
            # Measure prediction change
            prediction_change = np.abs(
                perturbed_predictions - base_predictions
            ).mean()
            
            stability_results.append({
                "feature": feature,
                "avg_prediction_change": prediction_change,
                "is_stable": prediction_change < 0.05 * np.abs(base_predictions).mean(),
            })
        
        return {
            "feature_stability": stability_results,
            "overall_stable": all(r["is_stable"] for r in stability_results),
        }
    
    def evaluate_gates(self, results: dict) -> bool:
        """
        Quality gates for deployment.
        """
        gates = {
            "mape_threshold": results["performance_metrics"]["mape"] < 0.05,
            "fairness_pass": all(
                r["is_fair"] for r in results["fairness_analysis"].values()
            ),
            "stability_pass": results["stability_tests"]["overall_stable"],
            "latency_pass": results["latency_tests"]["p99_ms"] < 100,
            "memory_pass": results["memory_tests"]["peak_mb"] < 50,
        }
        
        return all(gates.values())
```

---

## 7. Model Serving & Deployment

### 7.1 Cloud API Server

```python
# FastAPI server for model inference

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import mlflow

app = FastAPI(title="Farm ML API", version="1.0.0")

# Load models at startup
models = {
    "weight_predictor": mlflow.pyfunc.load_model("models:/weight_predictor/Production"),
    "health_risk": mlflow.pyfunc.load_model("models:/health_risk/Production"),
    "breeding_optimizer": mlflow.pyfunc.load_model("models:/breeding_optimizer/Production"),
    "feed_optimizer": mlflow.pyfunc.load_model("models:/feed_optimizer/Production"),
}


class WeightPredictionRequest(BaseModel):
    animal_id: str
    farm_id: str
    horizon_days: int = 30
    include_confidence: bool = True


class WeightPredictionResponse(BaseModel):
    animal_id: str
    current_weight: float
    predictions: List[dict]
    feature_importance: dict
    model_version: str


@app.post("/predict/weight", response_model=WeightPredictionResponse)
async def predict_weight(request: WeightPredictionRequest):
    try:
        # Get features
        features = feature_store.get_features(
            request.animal_id, 
            request.farm_id
        )
        
        if features is None:
            raise HTTPException(404, "Animal not found")
        
        # Predict
        predictions = []
        for horizon in [7, 14, 30, 90]:
            if horizon <= request.horizon_days:
                pred = models["weight_predictor"].predict(
                    features, 
                    horizon=horizon,
                    return_confidence=request.include_confidence
                )
                predictions.append({
                    "horizon_days": horizon,
                    "predicted_weight": pred["point_estimate"],
                    "confidence_interval_80": pred.get("ci_80"),
                    "confidence_interval_95": pred.get("ci_95"),
                })
        
        return WeightPredictionResponse(
            animal_id=request.animal_id,
            current_weight=features["current_weight"],
            predictions=predictions,
            feature_importance=models["weight_predictor"].get_feature_importance(),
            model_version=models["weight_predictor"].metadata.run_id,
        )
    
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/predict/health-risk")
async def predict_health_risk(request: HealthRiskRequest):
    # Similar implementation
    pass


@app.post("/optimize/feed")
async def optimize_feed(request: FeedOptimizationRequest):
    # Similar implementation  
    pass


@app.post("/recommend/breeding")
async def recommend_breeding(request: BreedingRecommendationRequest):
    # Similar implementation
    pass


# Batch inference endpoint
@app.post("/batch/predict")
async def batch_predict(request: BatchPredictionRequest):
    """
    Process multiple predictions in a single request.
    Optimized for efficiency.
    """
    results = []
    
    # Batch feature retrieval
    features_batch = feature_store.get_features_batch(
        request.animal_ids, 
        request.farm_id
    )
    
    # Batch inference
    predictions_batch = models[request.model_type].predict_batch(
        features_batch
    )
    
    return {"predictions": predictions_batch}
```

### 7.2 Model Registry (MLflow)

```python
class ModelRegistry:
    """
    MLflow-based model registry for versioning and deployment.
    """
    
    def __init__(self, tracking_uri: str):
        mlflow.set_tracking_uri(tracking_uri)
    
    def register_model(
        self, 
        model, 
        model_name: str, 
        metrics: dict,
        artifacts: dict
    ):
        """
        Register a trained model with full lineage tracking.
        """
        with mlflow.start_run():
            # Log parameters
            mlflow.log_params(model.get_params())
            
            # Log metrics
            mlflow.log_metrics(metrics)
            
            # Log model
            mlflow.sklearn.log_model(
                model,
                artifact_path="model",
                registered_model_name=model_name,
            )
            
            # Log additional artifacts
            for name, artifact in artifacts.items():
                mlflow.log_artifact(artifact, name)
            
            # Log feature schema
            mlflow.log_dict(
                self.get_feature_schema(model),
                "feature_schema.json"
            )
    
    def promote_model(
        self, 
        model_name: str, 
        version: int, 
        stage: str  # "Staging" or "Production"
    ):
        """
        Promote a model version to a deployment stage.
        """
        client = mlflow.tracking.MlflowClient()
        
        # Archive current production model
        if stage == "Production":
            current_prod = client.get_latest_versions(model_name, stages=["Production"])
            for model in current_prod:
                client.transition_model_version_stage(
                    model_name, model.version, "Archived"
                )
        
        # Promote new version
        client.transition_model_version_stage(
            model_name, version, stage
        )
    
    def get_production_model(self, model_name: str):
        """
        Load the current production model.
        """
        return mlflow.pyfunc.load_model(f"models:/{model_name}/Production")
```

---

## 8. On-Device Inference (Edge ML)

### 8.1 TensorFlow Lite Conversion

```python
class TFLiteConverter:
    """
    Convert trained models to TensorFlow Lite for on-device inference.
    """
    
    def convert_sklearn_model(self, model, feature_names: List[str]) -> bytes:
        """
        Convert sklearn model to TFLite via ONNX.
        """
        # Convert to ONNX first
        onnx_model = convert_sklearn(
            model,
            initial_types=[
                ("input", FloatTensorType([None, len(feature_names)]))
            ]
        )
        
        # Convert ONNX to TensorFlow
        tf_rep = prepare(onnx_model)
        tf_rep.export_graph("temp_model")
        
        # Convert TensorFlow to TFLite
        converter = tf.lite.TFLiteConverter.from_saved_model("temp_model")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]  # Quantization
        
        tflite_model = converter.convert()
        
        return tflite_model
    
    def convert_keras_model(self, model: tf.keras.Model) -> bytes:
        """
        Convert Keras model to TFLite with quantization.
        """
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        
        # Optimization settings
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        
        # Full integer quantization for smaller size
        def representative_dataset():
            for _ in range(100):
                yield [np.random.randn(1, model.input_shape[1]).astype(np.float32)]
        
        converter.representative_dataset = representative_dataset
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8
        ]
        converter.inference_input_type = tf.int8
        converter.inference_output_type = tf.int8
        
        return converter.convert()
    
    def validate_tflite_model(
        self, 
        tflite_model: bytes, 
        test_inputs: np.ndarray,
        original_outputs: np.ndarray
    ) -> dict:
        """
        Validate TFLite model matches original model outputs.
        """
        interpreter = tf.lite.Interpreter(model_content=tflite_model)
        interpreter.allocate_tensors()
        
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        
        tflite_outputs = []
        
        for test_input in test_inputs:
            interpreter.set_tensor(
                input_details[0]["index"], 
                test_input.reshape(1, -1).astype(np.float32)
            )
            interpreter.invoke()
            output = interpreter.get_tensor(output_details[0]["index"])
            tflite_outputs.append(output[0])
        
        tflite_outputs = np.array(tflite_outputs)
        
        return {
            "max_diff": np.max(np.abs(tflite_outputs - original_outputs)),
            "mean_diff": np.mean(np.abs(tflite_outputs - original_outputs)),
            "correlation": np.corrcoef(tflite_outputs.flatten(), original_outputs.flatten())[0, 1],
            "model_size_bytes": len(tflite_model),
        }
```

### 8.2 Flutter Integration

```dart
// lib/services/ml_inference_service.dart

import 'package:tflite_flutter/tflite_flutter.dart';

class MLInferenceService {
  late Interpreter _weightPredictor;
  late Interpreter _healthRiskModel;
  late Interpreter _feedOptimizer;
  
  bool _isInitialized = false;
  
  /// Initialize all ML models
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Load models from assets
    _weightPredictor = await Interpreter.fromAsset(
      'assets/models/weight_predictor.tflite',
      options: InterpreterOptions()..threads = 4,
    );
    
    _healthRiskModel = await Interpreter.fromAsset(
      'assets/models/health_risk.tflite',
    );
    
    _feedOptimizer = await Interpreter.fromAsset(
      'assets/models/feed_optimizer.tflite',
    );
    
    _isInitialized = true;
  }
  
  /// Predict weight for an animal
  Future<WeightPrediction> predictWeight({
    required Animal animal,
    required List<WeightRecord> weightHistory,
    required List<FeedingRecord> feedingHistory,
    required int horizonDays,
  }) async {
    await initialize();
    
    // Compute features
    final features = _computeWeightFeatures(
      animal: animal,
      weightHistory: weightHistory,
      feedingHistory: feedingHistory,
      horizonDays: horizonDays,
    );
    
    // Run inference
    final inputBuffer = Float32List.fromList(features);
    final outputBuffer = Float32List(3); // [prediction, ci_lower, ci_upper]
    
    _weightPredictor.run(inputBuffer, outputBuffer);
    
    return WeightPrediction(
      predictedWeight: outputBuffer[0],
      confidenceIntervalLower: outputBuffer[1],
      confidenceIntervalUpper: outputBuffer[2],
      horizonDays: horizonDays,
      computedAt: DateTime.now(),
    );
  }
  
  /// Predict health risk
  Future<HealthRiskPrediction> predictHealthRisk({
    required Animal animal,
    required List<WeightRecord> weightHistory,
    required List<HealthRecord> healthHistory,
    required List<FeedingRecord> feedingHistory,
  }) async {
    await initialize();
    
    final features = _computeHealthFeatures(
      animal: animal,
      weightHistory: weightHistory,
      healthHistory: healthHistory,
      feedingHistory: feedingHistory,
    );
    
    final inputBuffer = Float32List.fromList(features);
    final outputBuffer = Float32List(5); // [risk_7d, risk_14d, risk_30d, severity, category]
    
    _healthRiskModel.run(inputBuffer, outputBuffer);
    
    return HealthRiskPrediction(
      risk7Day: outputBuffer[0],
      risk14Day: outputBuffer[1],
      risk30Day: outputBuffer[2],
      severity: outputBuffer[3],
      riskCategory: _decodeRiskCategory(outputBuffer[4]),
      topRiskFactors: _computeTopRiskFactors(features),
    );
  }
  
  /// Optimize feed recommendation
  Future<FeedRecommendation> optimizeFeed({
    required Animal animal,
    required double targetWeight,
    required DateTime targetDate,
    required List<FeedType> availableFeedTypes,
  }) async {
    await initialize();
    
    // Run optimization for each feed type
    final recommendations = <FeedTypeRecommendation>[];
    
    for (final feedType in availableFeedTypes) {
      final features = _computeFeedOptimizationFeatures(
        animal: animal,
        feedType: feedType,
        targetWeight: targetWeight,
        targetDate: targetDate,
      );
      
      final inputBuffer = Float32List.fromList(features);
      final outputBuffer = Float32List(4); // [daily_amount, projected_weight, cost, health_risk]
      
      _feedOptimizer.run(inputBuffer, outputBuffer);
      
      recommendations.add(FeedTypeRecommendation(
        feedType: feedType,
        dailyAmount: outputBuffer[0],
        projectedWeight: outputBuffer[1],
        totalCost: outputBuffer[2],
        healthRisk: outputBuffer[3],
      ));
    }
    
    // Select best recommendation
    recommendations.sort((a, b) => _scoreFeedRecommendation(a).compareTo(_scoreFeedRecommendation(b)));
    
    return FeedRecommendation(
      bestRecommendation: recommendations.first,
      alternatives: recommendations.skip(1).take(2).toList(),
      targetWeight: targetWeight,
      targetDate: targetDate,
    );
  }
  
  /// Feature computation for weight prediction
  List<double> _computeWeightFeatures({
    required Animal animal,
    required List<WeightRecord> weightHistory,
    required List<FeedingRecord> feedingHistory,
    required int horizonDays,
  }) {
    final features = <double>[];
    
    // Animal static features
    features.add(animal.ageInDays?.toDouble() ?? 0);
    features.add(_encodeSpecies(animal.species));
    features.add(_encodeGender(animal.gender));
    features.add(_encodeBreed(animal.breed ?? ''));
    
    // Current weight
    final currentWeight = weightHistory.isNotEmpty 
        ? weightHistory.last.weight 
        : 0.0;
    features.add(currentWeight);
    
    // Weight history features
    features.addAll(_computeWeightHistoryFeatures(weightHistory));
    
    // Feed features
    features.addAll(_computeFeedFeatures(feedingHistory));
    
    // Horizon
    features.add(horizonDays.toDouble());
    
    // Ensure correct feature count (pad or truncate)
    while (features.length < 52) {
      features.add(0.0);
    }
    
    return features.sublist(0, 52);
  }
  
  List<double> _computeWeightHistoryFeatures(List<WeightRecord> history) {
    if (history.isEmpty) {
      return List.filled(15, 0.0);
    }
    
    // Sort by date
    history.sort((a, b) => a.date.compareTo(b.date));
    
    final features = <double>[];
    final now = DateTime.now();
    
    // Weight 7 days ago
    final weight7d = _getWeightAtDaysAgo(history, 7);
    features.add(weight7d);
    
    // Weight 30 days ago
    final weight30d = _getWeightAtDaysAgo(history, 30);
    features.add(weight30d);
    
    // Weight 90 days ago
    final weight90d = _getWeightAtDaysAgo(history, 90);
    features.add(weight90d);
    
    // Weight changes
    final currentWeight = history.last.weight;
    features.add(currentWeight - weight7d);  // 7d change
    features.add(currentWeight - weight30d); // 30d change
    
    // Velocity (kg/day)
    if (history.length >= 2) {
      final recentHistory = history.where(
        (w) => w.date.isAfter(now.subtract(Duration(days: 14)))
      ).toList();
      
      if (recentHistory.length >= 2) {
        final velocity = _computeLinearSlope(recentHistory);
        features.add(velocity);
      } else {
        features.add(0.0);
      }
    } else {
      features.add(0.0);
    }
    
    // Average daily gain
    features.add((currentWeight - weight7d) / 7);
    features.add((currentWeight - weight30d) / 30);
    
    // More features...
    while (features.length < 15) {
      features.add(0.0);
    }
    
    return features;
  }
  
  double _computeLinearSlope(List<WeightRecord> records) {
    if (records.length < 2) return 0.0;
    
    final n = records.length;
    final firstDate = records.first.date;
    
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    
    for (final record in records) {
      final x = record.date.difference(firstDate).inDays.toDouble();
      final y = record.weight;
      
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    
    final denominator = n * sumX2 - sumX * sumX;
    if (denominator == 0) return 0.0;
    
    return (n * sumXY - sumX * sumY) / denominator;
  }
}


// Models
class WeightPrediction {
  final double predictedWeight;
  final double confidenceIntervalLower;
  final double confidenceIntervalUpper;
  final int horizonDays;
  final DateTime computedAt;
  
  WeightPrediction({
    required this.predictedWeight,
    required this.confidenceIntervalLower,
    required this.confidenceIntervalUpper,
    required this.horizonDays,
    required this.computedAt,
  });
  
  double get confidenceWidth => confidenceIntervalUpper - confidenceIntervalLower;
}

class HealthRiskPrediction {
  final double risk7Day;
  final double risk14Day;
  final double risk30Day;
  final double severity;
  final String riskCategory;
  final List<RiskFactor> topRiskFactors;
  
  HealthRiskPrediction({
    required this.risk7Day,
    required this.risk14Day,
    required this.risk30Day,
    required this.severity,
    required this.riskCategory,
    required this.topRiskFactors,
  });
  
  String get riskLevel {
    if (risk7Day > 0.7) return 'Critical';
    if (risk7Day > 0.5) return 'High';
    if (risk7Day > 0.3) return 'Medium';
    return 'Low';
  }
}

class RiskFactor {
  final String name;
  final double contribution;
  final String description;
  
  RiskFactor({
    required this.name,
    required this.contribution,
    required this.description,
  });
}
```

### 8.3 Model Update Mechanism

```dart
// lib/services/model_update_service.dart

class ModelUpdateService {
  final SupabaseClient _supabase;
  final SharedPreferences _prefs;
  
  static const _modelVersionKey = 'ml_model_versions';
  
  /// Check for model updates
  Future<bool> checkForUpdates() async {
    final localVersions = await _getLocalModelVersions();
    final remoteVersions = await _getRemoteModelVersions();
    
    for (final modelName in remoteVersions.keys) {
      if (localVersions[modelName] != remoteVersions[modelName]) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Download and update models
  Future<void> updateModels({void Function(double)? onProgress}) async {
    final remoteVersions = await _getRemoteModelVersions();
    final localVersions = await _getLocalModelVersions();
    
    final modelsToUpdate = <String>[];
    
    for (final entry in remoteVersions.entries) {
      if (localVersions[entry.key] != entry.value) {
        modelsToUpdate.add(entry.key);
      }
    }
    
    for (var i = 0; i < modelsToUpdate.length; i++) {
      final modelName = modelsToUpdate[i];
      
      // Download model from Supabase Storage
      final modelBytes = await _supabase.storage
          .from('ml-models')
          .download('$modelName.tflite');
      
      // Save to local storage
      final file = File(await _getModelPath(modelName));
      await file.writeAsBytes(modelBytes);
      
      // Update version
      localVersions[modelName] = remoteVersions[modelName]!;
      
      onProgress?.call((i + 1) / modelsToUpdate.length);
    }
    
    // Save updated versions
    await _prefs.setString(_modelVersionKey, jsonEncode(localVersions));
  }
  
  Future<Map<String, String>> _getRemoteModelVersions() async {
    final response = await _supabase
        .from('ml_model_metadata')
        .select('model_name, version')
        .eq('status', 'production');
    
    return Map.fromEntries(
      response.map((r) => MapEntry(r['model_name'], r['version']))
    );
  }
  
  Future<Map<String, String>> _getLocalModelVersions() async {
    final versionsJson = _prefs.getString(_modelVersionKey);
    if (versionsJson == null) return {};
    return Map<String, String>.from(jsonDecode(versionsJson));
  }
}
```

---

## 9. Monitoring & MLOps

### 9.1 Model Performance Monitoring

```python
class ModelMonitor:
    """
    Monitor model performance in production.
    """
    
    def __init__(self, model_name: str):
        self.model_name = model_name
        self.metrics_buffer = []
        self.drift_detector = DataDriftDetector()
    
    def log_prediction(
        self, 
        prediction_id: str,
        input_features: dict,
        prediction: float,
        confidence: float,
        latency_ms: float
    ):
        """
        Log every prediction for monitoring.
        """
        self.metrics_buffer.append({
            "prediction_id": prediction_id,
            "timestamp": datetime.now(),
            "input_features": input_features,
            "prediction": prediction,
            "confidence": confidence,
            "latency_ms": latency_ms,
        })
        
        # Flush buffer periodically
        if len(self.metrics_buffer) >= 100:
            self.flush_metrics()
    
    def log_actual(self, prediction_id: str, actual_value: float):
        """
        Log actual outcome when available (for accuracy tracking).
        """
        self.db.update_prediction(
            prediction_id,
            actual_value=actual_value,
            error=abs(actual_value - self.get_prediction(prediction_id))
        )
    
    def compute_metrics_window(self, window_hours: int = 24) -> dict:
        """
        Compute metrics for recent predictions.
        """
        predictions = self.db.get_predictions_with_actuals(
            model_name=self.model_name,
            since=datetime.now() - timedelta(hours=window_hours)
        )
        
        if not predictions:
            return {}
        
        errors = [p["error"] for p in predictions if p["actual"] is not None]
        latencies = [p["latency_ms"] for p in predictions]
        
        return {
            "mape": np.mean([e / p["actual"] for e, p in zip(errors, predictions) if p["actual"]]),
            "mae": np.mean(errors) if errors else None,
            "prediction_count": len(predictions),
            "actuals_received": len(errors),
            "latency_p50": np.percentile(latencies, 50),
            "latency_p95": np.percentile(latencies, 95),
            "latency_p99": np.percentile(latencies, 99),
        }
    
    def detect_drift(self) -> dict:
        """
        Detect data drift in input features.
        """
        recent_features = self.db.get_recent_features(
            model_name=self.model_name,
            since=datetime.now() - timedelta(hours=24)
        )
        
        training_features = self.get_training_feature_distribution()
        
        drift_report = {}
        
        for feature_name in recent_features.columns:
            drift_score = self.drift_detector.compute_drift(
                reference=training_features[feature_name],
                current=recent_features[feature_name]
            )
            
            drift_report[feature_name] = {
                "drift_score": drift_score,
                "is_drifted": drift_score > 0.1,  # threshold
                "reference_mean": training_features[feature_name].mean(),
                "current_mean": recent_features[feature_name].mean(),
            }
        
        return drift_report
    
    def check_alerts(self) -> List[Alert]:
        """
        Check for alerting conditions.
        """
        alerts = []
        metrics = self.compute_metrics_window(24)
        drift = self.detect_drift()
        
        # Performance degradation
        if metrics.get("mape", 0) > 0.1:  # 10% MAPE threshold
            alerts.append(Alert(
                severity="high",
                message=f"Model {self.model_name} MAPE exceeded threshold: {metrics['mape']:.2%}",
                metric="mape",
                value=metrics["mape"]
            ))
        
        # Latency spike
        if metrics.get("latency_p99", 0) > 200:  # 200ms threshold
            alerts.append(Alert(
                severity="medium",
                message=f"Model {self.model_name} p99 latency spike: {metrics['latency_p99']:.0f}ms",
                metric="latency_p99",
                value=metrics["latency_p99"]
            ))
        
        # Data drift
        drifted_features = [f for f, d in drift.items() if d["is_drifted"]]
        if len(drifted_features) > 3:
            alerts.append(Alert(
                severity="high",
                message=f"Significant data drift detected in {len(drifted_features)} features",
                metric="drift",
                value=len(drifted_features)
            ))
        
        return alerts


class DataDriftDetector:
    """
    Statistical tests for data drift detection.
    """
    
    def compute_drift(
        self, 
        reference: np.ndarray, 
        current: np.ndarray,
        method: str = "ks"
    ) -> float:
        """
        Compute drift score between reference and current distributions.
        """
        if method == "ks":
            # Kolmogorov-Smirnov test
            statistic, _ = ks_2samp(reference, current)
            return statistic
        
        elif method == "psi":
            # Population Stability Index
            return self.compute_psi(reference, current)
        
        elif method == "kl":
            # KL Divergence
            return self.compute_kl_divergence(reference, current)
    
    def compute_psi(self, reference: np.ndarray, current: np.ndarray) -> float:
        """
        Population Stability Index.
        PSI < 0.1: No change
        PSI 0.1-0.25: Moderate change
        PSI > 0.25: Significant change
        """
        # Create buckets from reference distribution
        buckets = np.percentile(reference, np.arange(0, 101, 10))
        
        # Compute proportions
        ref_counts, _ = np.histogram(reference, bins=buckets)
        cur_counts, _ = np.histogram(current, bins=buckets)
        
        ref_pct = ref_counts / len(reference)
        cur_pct = cur_counts / len(current)
        
        # Avoid division by zero
        ref_pct = np.clip(ref_pct, 0.0001, None)
        cur_pct = np.clip(cur_pct, 0.0001, None)
        
        psi = np.sum((cur_pct - ref_pct) * np.log(cur_pct / ref_pct))
        
        return psi
```

### 9.2 Automated Retraining Pipeline

```python
class AutoRetrainingPipeline:
    """
    Automatically retrain models when performance degrades.
    """
    
    def __init__(self, config: dict):
        self.config = config
        self.monitor = ModelMonitor(config["model_name"])
        self.trainer = ModelTrainer(config)
    
    def should_retrain(self) -> tuple[bool, str]:
        """
        Determine if retraining is needed.
        """
        metrics = self.monitor.compute_metrics_window(
            window_hours=self.config["evaluation_window_hours"]
        )
        
        drift = self.monitor.detect_drift()
        
        reasons = []
        
        # Performance degradation
        if metrics.get("mape", 0) > self.config["mape_threshold"]:
            reasons.append(f"MAPE {metrics['mape']:.2%} > {self.config['mape_threshold']:.2%}")
        
        # Significant drift
        drifted_count = sum(1 for d in drift.values() if d["is_drifted"])
        if drifted_count > self.config["max_drifted_features"]:
            reasons.append(f"{drifted_count} features drifted")
        
        # Time since last training
        last_trained = self.get_last_training_time()
        days_since = (datetime.now() - last_trained).days
        if days_since > self.config["max_days_without_training"]:
            reasons.append(f"{days_since} days since last training")
        
        # Minimum data for retraining
        new_data_count = self.count_new_training_data()
        if new_data_count < self.config["min_new_samples"]:
            return False, "Insufficient new data"
        
        return len(reasons) > 0, "; ".join(reasons)
    
    def run_retraining(self) -> dict:
        """
        Execute full retraining pipeline.
        """
        # 1. Snapshot data
        training_data = self.prepare_training_data()
        
        # 2. Train new model
        new_model, metrics = self.trainer.train(training_data)
        
        # 3. Validate against current production
        validation_result = self.validate_new_model(new_model)
        
        # 4. Deploy if better
        if validation_result["is_better"]:
            self.deploy_model(new_model)
            return {
                "status": "deployed",
                "new_metrics": metrics,
                "improvement": validation_result["improvement"],
            }
        else:
            return {
                "status": "rejected",
                "reason": "New model not significantly better",
                "new_metrics": metrics,
                "current_metrics": validation_result["current_metrics"],
            }
    
    def validate_new_model(self, new_model) -> dict:
        """
        Compare new model against current production.
        """
        test_data = self.get_holdout_test_data()
        
        # Current production model
        current_model = self.monitor.get_production_model()
        current_preds = current_model.predict(test_data["X"])
        current_mape = mean_absolute_percentage_error(
            test_data["y"], current_preds
        )
        
        # New model
        new_preds = new_model.predict(test_data["X"])
        new_mape = mean_absolute_percentage_error(test_data["y"], new_preds)
        
        # Statistical significance test
        is_significant = self.paired_t_test(
            np.abs(current_preds - test_data["y"]),
            np.abs(new_preds - test_data["y"])
        )
        
        improvement = (current_mape - new_mape) / current_mape
        
        return {
            "is_better": new_mape < current_mape and is_significant,
            "improvement": improvement,
            "current_metrics": {"mape": current_mape},
            "new_metrics": {"mape": new_mape},
            "is_significant": is_significant,
        }
```

### 9.3 A/B Testing Framework

```python
class ABTestingFramework:
    """
    Run A/B tests for model improvements.
    """
    
    def create_experiment(
        self,
        experiment_name: str,
        control_model: str,
        treatment_model: str,
        traffic_split: float = 0.1,  # 10% to treatment
        duration_days: int = 14,
    ) -> str:
        """
        Create a new A/B experiment.
        """
        experiment_id = str(uuid.uuid4())
        
        experiment = {
            "id": experiment_id,
            "name": experiment_name,
            "control_model": control_model,
            "treatment_model": treatment_model,
            "traffic_split": traffic_split,
            "start_date": datetime.now(),
            "end_date": datetime.now() + timedelta(days=duration_days),
            "status": "running",
        }
        
        self.db.create_experiment(experiment)
        
        return experiment_id
    
    def route_request(self, experiment_id: str, request_id: str) -> str:
        """
        Route request to control or treatment.
        """
        experiment = self.db.get_experiment(experiment_id)
        
        # Deterministic routing based on request_id
        hash_value = int(hashlib.md5(request_id.encode()).hexdigest(), 16)
        treatment_threshold = int(experiment["traffic_split"] * 1000)
        
        if hash_value % 1000 < treatment_threshold:
            variant = "treatment"
            model = experiment["treatment_model"]
        else:
            variant = "control"
            model = experiment["control_model"]
        
        # Log assignment
        self.db.log_assignment(experiment_id, request_id, variant)
        
        return model
    
    def analyze_experiment(self, experiment_id: str) -> dict:
        """
        Analyze experiment results.
        """
        experiment = self.db.get_experiment(experiment_id)
        
        control_results = self.db.get_experiment_results(
            experiment_id, variant="control"
        )
        treatment_results = self.db.get_experiment_results(
            experiment_id, variant="treatment"
        )
        
        # Compute metrics
        control_metrics = self.compute_variant_metrics(control_results)
        treatment_metrics = self.compute_variant_metrics(treatment_results)
        
        # Statistical significance
        significance = self.compute_significance(
            control_results, treatment_results
        )
        
        return {
            "experiment_id": experiment_id,
            "control": control_metrics,
            "treatment": treatment_metrics,
            "relative_improvement": {
                metric: (treatment_metrics[metric] - control_metrics[metric]) / control_metrics[metric]
                for metric in control_metrics.keys()
            },
            "significance": significance,
            "recommendation": self.get_recommendation(
                control_metrics, treatment_metrics, significance
            ),
        }
```

---

## 10. Model Catalog

### Complete Model Inventory

| Model | Type | Input | Output | Framework | On-Device |
|-------|------|-------|--------|-----------|-----------|
| Weight Predictor | Regression | 52 features | Weight + CI | XGBoost + LightGBM + NN | ✅ |
| Health Risk | Classification | 45 features | Risk scores + factors | Multi-task NN | ✅ |
| Anomaly Detector | Unsupervised | 40 features | Anomaly score | Isolation Forest + AE | ✅ |
| Breeding Optimizer | Multi-output | 35 features | Timing + sire ranking | Gradient Boosting | ✅ |
| Conception Predictor | Binary Classification | 28 features | Probability | Logistic + GBM | ✅ |
| Heat Detector | Time-series | Cycle history | Next heat date | LSTM | ✅ |
| Feed Optimizer | Optimization | Animal + goals | Feed plan | Constrained Optim | ❌ |
| Genetic Merit | Calculation | Pedigree | EBV scores | BLUP | ❌ |
| Financial Forecaster | Time-series | Transaction history | Revenue/expense | Prophet + ML | ❌ |
| Mortality Risk | Survival Analysis | Health features | Hazard rates | Cox + GBM | ✅ |
| Growth Curve | Regression | Age + history | Expected weight | Nonlinear regression | ✅ |
| Body Condition | Image Classification | Photo | BCS score | CNN (MobileNetV3) | ✅ |

---

## 11. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-4)

#### Week 1-2: Data Infrastructure
- [ ] Set up data lake (Bronze/Silver/Gold layers)
- [ ] Implement CDC pipeline from Supabase
- [ ] Create data quality framework
- [x] Build initial feature store schema ✅ (app/models/schemas.py)
- [x] Synthetic data generator ✅ (app/services/synthetic_data.py)
- [x] Job tracking storage ✅ (app/services/job_store.py)

#### Week 3-4: Feature Engineering
- [x] Implement weight feature computations ✅ (app/features/weight_features.py)
- [x] Implement health feature computations ✅ (app/features/health_features.py)
- [x] Create feature computation pipeline (scheduled) ✅ (app/services/feature_pipeline.py)
- [x] Feature API endpoints ✅ (app/api/features.py, app/api/pipeline.py)
- [ ] Deploy local feature store (SQLite)

### Phase 2: Core Models (Weeks 5-10)

#### Week 5-6: Weight Prediction
- [x] Prepare training dataset ✅ (app/services/feature_pipeline.py - TrainingDataGenerator)
- [x] Generate synthetic training data ✅ (298 samples with 7/14/30 day horizons)
- [x] Train LightGBM model ✅ (app/models/weight_model.py - MAE: 1.51kg, MAPE: 4.07%)
- [x] Train scikit-learn ensemble ✅ (LightGBM + RandomForest + GradientBoosting + Ridge)
- [x] Model API endpoints ✅ (app/api/models.py - train, predict, info)
- [ ] Quantile regression for confidence intervals
- [ ] Convert to ONNX/TFLite

#### Week 7-8: Health Risk
- [ ] Build multi-task learning architecture
- [ ] Train anomaly detection models
- [x] Implement SHAP explainability ✅ (app/models/weight_model.py - TreeExplainer, explain/global endpoints)
- [ ] Convert to ONNX/TFLite

#### Week 9-10: Breeding & Feed
- [ ] Implement genetic merit calculations
- [ ] Train conception predictor
- [ ] Build feed optimizer
- [ ] Convert on-device models to ONNX/TFLite

### Phase 3: Platform (Weeks 11-14)

#### Week 11-12: Serving Infrastructure
- [x] Deploy FastAPI inference server ✅ (app/main.py)
- [x] Set up MLflow model registry ✅ (app/core/mlflow_tracking.py, app/api/mlflow_api.py)
- [ ] Implement batch inference pipeline
- [ ] Build model update mechanism for app

#### Week 13-14: Monitoring & MLOps
- [x] Implement prediction logging ✅ (MLflow experiment tracking)
- [ ] Build drift detection
- [ ] Create alerting system
- [ ] Set up automated retraining pipeline

### Phase 4: Integration (Weeks 15-18)

#### Week 15-16: Flutter Integration
- [ ] Integrate TFLite models in app
- [ ] Build ML service layer
- [ ] Implement offline inference
- [ ] Add model update mechanism

#### Week 17-18: UI/UX
- [ ] Build predictions dashboard
- [ ] Create insights & recommendations UI
- [ ] Add explainability visualizations
- [ ] Implement notification integration

### Phase 5: Advanced (Weeks 19-24)

#### Week 19-20: Computer Vision
- [ ] Train body condition scoring model
- [ ] Implement photo-based health assessment
- [ ] Deploy on-device CV models

#### Week 21-22: Advanced Analytics
- [ ] Financial forecasting
- [ ] Scenario analysis
- [ ] Farm-level optimization

#### Week 23-24: Continuous Improvement
- [ ] A/B testing framework
- [ ] Federated learning exploration
- [ ] Performance optimization
- [ ] Documentation & handoff

---

## 12. Technical Stack

### Data & Feature Engineering
- **Storage**: Supabase (PostgreSQL), S3/GCS for data lake
- **Processing**: Apache Spark, Pandas, dbt
- **Feature Store**: Feast (cloud), SQLite (device)
- **Quality**: Great Expectations

### Model Development
- **Frameworks**: scikit-learn, XGBoost, LightGBM, pytorch
- **Optimization**: Optuna, scipy
- **Explainability**: SHAP, LIME
- **Experiment Tracking**: MLflow

### Serving & Deployment
- **API**: FastAPI
- **Model Registry**: MLflow
- **Edge**: TensorFlow Lite
- **Containerization**: Docker, Kubernetes

### Monitoring
- **Metrics**: Prometheus, Grafana
- **Logging**: ELK Stack
- **Alerting**: PagerDuty/Slack

### Flutter/Dart
- **Inference**: tflite_flutter
- **Storage**: drift (SQLite)
- **State**: Riverpod

---

## Appendix A: Data Schemas

### Feature Store Schema

```sql
-- Cloud Feature Store (PostgreSQL)

CREATE TABLE animal_features (
    id UUID PRIMARY KEY,
    animal_id UUID NOT NULL REFERENCES animals(id),
    farm_id UUID NOT NULL REFERENCES farms(id),
    feature_timestamp TIMESTAMPTZ NOT NULL,
    feature_vector JSONB NOT NULL,
    feature_version TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(animal_id, feature_timestamp, feature_version)
);

CREATE INDEX idx_animal_features_lookup 
ON animal_features(animal_id, feature_timestamp DESC);

CREATE TABLE feature_metadata (
    feature_name TEXT PRIMARY KEY,
    feature_type TEXT NOT NULL,
    description TEXT,
    computation_sql TEXT,
    mean FLOAT,
    std FLOAT,
    min FLOAT,
    max FLOAT,
    null_rate FLOAT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE model_predictions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_name TEXT NOT NULL,
    model_version TEXT NOT NULL,
    animal_id UUID REFERENCES animals(id),
    farm_id UUID NOT NULL,
    prediction_type TEXT NOT NULL,
    prediction_value JSONB NOT NULL,
    input_features JSONB,
    confidence FLOAT,
    actual_value FLOAT,
    error FLOAT,
    latency_ms FLOAT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_predictions_monitoring
ON model_predictions(model_name, created_at DESC);
```

---

## Appendix B: API Specifications

### Prediction API

```yaml
openapi: 3.0.0
info:
  title: Farm ML API
  version: 1.0.0

paths:
  /predict/weight:
    post:
      summary: Predict animal weight
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required:
                - animal_id
                - farm_id
              properties:
                animal_id:
                  type: string
                  format: uuid
                farm_id:
                  type: string
                  format: uuid
                horizon_days:
                  type: integer
                  default: 30
                include_confidence:
                  type: boolean
                  default: true
      responses:
        '200':
          description: Successful prediction
          content:
            application/json:
              schema:
                type: object
                properties:
                  animal_id:
                    type: string
                  current_weight:
                    type: number
                  predictions:
                    type: array
                    items:
                      type: object
                      properties:
                        horizon_days:
                          type: integer
                        predicted_weight:
                          type: number
                        confidence_interval_80:
                          type: array
                          items:
                            type: number
                        confidence_interval_95:
                          type: array
                          items:
                            type: number
                  feature_importance:
                    type: object
                  model_version:
                    type: string
```

---

*Last Updated: January 18, 2026*
*Version: 1.0.0*
