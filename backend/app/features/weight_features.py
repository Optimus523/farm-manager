from dataclasses import dataclass
from datetime import date, datetime, timedelta

import numpy as np 
import pandas as pd 

@dataclass
class WeightFeatures:

    # Current state
    current_weight: float | None = None
    days_since_last_weight: int | None = None

    # Historical values
    weight_7d_ago: float | None = None
    weight_30d_ago: float | None = None
    weight_90d_ago: float | None = None

    # Deltas
    weight_change_7d: float | None = None
    weight_change_30d: float | None = None
    weight_change_90d: float | None = None

    # Velocity (kg/day)
    weight_velocity_7d: float | None = None
    weight_velocity_30d: float | None = None

    # Average Daily Gain
    adg_7d: float | None = None
    adg_30d: float | None = None
    adg_lifetime: float | None = None

    # Statistics
    weight_std_30d: float | None = None
    weight_min_30d: float | None = None
    weight_max_30d: float | None = None
    measurement_count_30d: int = 0

    growth_curve_deviation: float | None = None  # % deviation from expected

    def to_dict(self) -> dict:
        return {k: v for k, v in self.__dict__.items()}

    def to_array(self) -> np.ndarray:
        values = list(self.to_dict().values())
        return np.array([v if v is not None else 0.0 for v in values], dtype=np.float32)


class WeightFeatureEngineer:
    def __init__(self):
        # Expected growth rates by species (kg/day) - rough estimates
        self.expected_adg = {
            "cattle": 1.0,
            "pig": 0.7,
            "goat": 0.15,
            "sheep": 0.2,
            "poultry": 0.05,
            "rabbit": 0.03,
        }

    def compute_features(
        self,
        weight_records: list[dict],
        animal: dict,
        as_of_date: date | None = None,
    ) -> WeightFeatures:
        """
        Compute all weight features for an animal.

        Args:
            weight_records: List of weight records sorted by date (oldest first)
            animal: Animal data including species, date_of_birth
            as_of_date: Reference date for feature computation (defaults to today)

        Returns:
            WeightFeatures dataclass with computed values
        """
        if as_of_date is None:
            as_of_date = date.today()

        features = WeightFeatures()

        if not weight_records:
            return features
        
        df = pd.DataFrame(weight_records)
        df["date"] = pd.to_datetime(df["date"]).dt.date
        df["weight"] = df["weight"].astype(float)
        df = df.sort_values("date")

        df = df[df["date"] <= as_of_date]

        if df.empty:
            return features

        latest = df.iloc[-1]
        features.current_weight = float(latest["weight"])
        features.days_since_last_weight = (as_of_date - latest["date"]).days

        features.weight_7d_ago = self._get_weight_at(df, as_of_date - timedelta(days=7))
        features.weight_30d_ago = self._get_weight_at(df, as_of_date - timedelta(days=30))
        features.weight_90d_ago = self._get_weight_at(df, as_of_date - timedelta(days=90))

        if features.weight_7d_ago is not None:
            features.weight_change_7d = features.current_weight - features.weight_7d_ago
            features.adg_7d = features.weight_change_7d / 7

        if features.weight_30d_ago is not None:
            features.weight_change_30d = features.current_weight - features.weight_30d_ago
            features.adg_30d = features.weight_change_30d / 30

        if features.weight_90d_ago is not None:
            features.weight_change_90d = features.current_weight - features.weight_90d_ago

        features.weight_velocity_7d = self._compute_velocity(df, as_of_date, days=7)
        features.weight_velocity_30d = self._compute_velocity(df, as_of_date, days=30)

        recent_df = df[df["date"] > as_of_date - timedelta(days=30)]
        if len(recent_df) > 0:
            features.weight_std_30d = float(recent_df["weight"].std()) if len(recent_df) > 1 else 0
            features.weight_min_30d = float(recent_df["weight"].min())
            features.weight_max_30d = float(recent_df["weight"].max())
            features.measurement_count_30d = len(recent_df)

        # Lifetime ADG
        if animal.get("date_of_birth"):
            dob = animal["date_of_birth"]
            if isinstance(dob, str):
                dob = datetime.fromisoformat(dob).date()
            age_days = (as_of_date - dob).days
            if age_days > 0:
                first_weight = float(df.iloc[0]["weight"])
                features.adg_lifetime = (features.current_weight - first_weight) / age_days

        features.growth_curve_deviation = self._compute_growth_deviation(
            features.current_weight,
            animal,
            as_of_date,
        )

        return features

    def _get_weight_at(self, df: pd.DataFrame, target_date: date) -> float | None:
        valid = df[df["date"] <= target_date]
        if valid.empty:
            return None
        return float(valid.iloc[-1]["weight"])

    def _compute_velocity(
        self, df: pd.DataFrame, as_of_date: date, days: int
    ) -> float | None:
        recent = df[df["date"] > as_of_date - timedelta(days=days)]

        if len(recent) < 2:
            return None

        x = np.array([(d - recent.iloc[0]["date"]).days for d in recent["date"]])
        y = recent["weight"].values.astype(float)

        # Linear regression slope
        if len(x) > 1 and x.std() > 0:
            slope = np.polyfit(x, y, 1)[0]
            return float(slope)

        return None

    def _compute_growth_deviation(
        self,
        current_weight: float,
        animal: dict,
        as_of_date: date,
    ) -> float | None:
        if not animal.get("date_of_birth"):
            return None

        dob = animal["date_of_birth"]
        if isinstance(dob, str):
            dob = datetime.fromisoformat(dob).date()

        age_days = (as_of_date - dob).days
        if age_days <= 0:
            return None

        species = (animal.get("species") or "cattle").lower()
        expected_adg = self.expected_adg.get(species, 0.5)

        # Simple linear growth model (can be improved with growth curves)
        # Assume birth weight based on species
        birth_weights = {
            "cattle": 35,
            "pig": 1.5,
            "goat": 3,
            "sheep": 4,
            "poultry": 0.04,
            "rabbit": 0.05,
        }
        birth_weight = birth_weights.get(species, 5)
        expected_weight = birth_weight + (expected_adg * age_days)

        if expected_weight > 0:
            deviation = ((current_weight - expected_weight) / expected_weight) * 100
            return float(deviation)

        return None
