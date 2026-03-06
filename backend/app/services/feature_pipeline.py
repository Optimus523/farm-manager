import json
import logging
import random
from datetime import date, datetime, timedelta
from pathlib import Path

from app.core.config import get_settings
from app.core.database import SupabaseRepository
from app.features.weight_features import WeightFeatureEngineer
from app.features.health_features import HealthFeatureEngineer
from app.features.health_risk_features import HealthRiskFeatureEngineer

logger = logging.getLogger(__name__)


class FeaturePipeline:
    """
    Pipeline for computing and storing features for all animals.
    
    This runs as a scheduled job to pre-compute features for:
    1. Real-time inference (features ready when needed)
    2. Training dataset generation
    3. Historical feature storage for model retraining
    """

    def __init__(self):
        self.repo = SupabaseRepository()
        self.weight_engineer = WeightFeatureEngineer()
        self.health_engineer = HealthFeatureEngineer()
        self.settings = get_settings()

    async def compute_all_features(
        self,
        farm_id: str | None = None,
        as_of_date: date | None = None,
        save_to_db: bool = True,
        save_to_file: bool = True,
    ) -> dict:
        """
        Compute features for all animals (or a specific farm).
        
        Args:
            farm_id: Optional farm ID to limit computation
            as_of_date: Date for feature computation (defaults to today)
            save_to_db: Whether to save features to Supabase
            save_to_file: Whether to save features to local JSON files
            
        Returns:
            Summary of computation results
        """
        if as_of_date is None:
            as_of_date = date.today()

        logger.info(f"Starting feature computation for date: {as_of_date}")

        if farm_id:
            animals = await self.repo.fetch_by_farm("animals", farm_id)
        else:
            animals = await self.repo.fetch_all("animals")

        logger.info(f"Computing features for {len(animals)} animals")

        results = {
            "computed_at": datetime.now().isoformat(),
            "as_of_date": as_of_date.isoformat(),
            "total_animals": len(animals),
            "successful": 0,
            "failed": 0,
            "features": [],
        }

        for animal in animals:
            try:
                features = await self._compute_animal_features(animal, as_of_date)
                results["features"].append(features)
                results["successful"] += 1
            except Exception as e:
                logger.error(f"Failed to compute features for {animal['id']}: {e}")
                results["failed"] += 1

        if save_to_file:
            self._save_to_file(results, as_of_date)

        if save_to_db:
            await self._save_to_database(results)

        logger.info(
            f"Feature computation complete: {results['successful']} successful, "
            f"{results['failed']} failed"
        )

        return results

    async def _compute_animal_features(
        self, animal: dict, as_of_date: date
    ) -> dict:
        """Compute all features for a single animal."""
        animal_id = animal["id"]

        weight_records = await self.repo.fetch_all(
            "weight_records", filters={"animal_id": animal_id}
        )
        health_records = await self.repo.fetch_all(
            "health_records", filters={"animal_id": animal_id}
        )
        feeding_records = await self.repo.fetch_all(
            "feeding_records", filters={"animal_id": animal_id}
        )

        weight_features = self.weight_engineer.compute_features(
            weight_records, animal, as_of_date=as_of_date
        )

        health_features = self.health_engineer.compute_features(
            health_records,
            weight_features=weight_features.to_dict(),
            as_of_date=as_of_date,
        )

        return {
            "animal_id": animal_id,
            "farm_id": animal["farm_id"],
            "tag_id": animal.get("tag_id"),
            "species": animal.get("species"),
            "computed_at": datetime.now().isoformat(),
            "as_of_date": as_of_date.isoformat(),
            "weight_features": weight_features.to_dict(),
            "health_features": health_features.to_dict(),
            "record_counts": {
                "weight_records": len(weight_records),
                "health_records": len(health_records),
                "feeding_records": len(feeding_records),
            },
        }

    def _save_to_file(self, results: dict, as_of_date: date) -> None:
        """Save computed features to local JSON file."""
        feature_dir = Path(self.settings.feature_store_path)
        feature_dir.mkdir(parents=True, exist_ok=True)

        filename = feature_dir / f"features_{as_of_date.isoformat()}.json"

        with open(filename, "w") as f:
            json.dump(results, f, indent=2, default=str)

        logger.info(f"Features saved to {filename}")

    async def _save_to_database(self, results: dict) -> None:
        """Save computed features to Supabase (future implementation)."""
        # TODO: Create feature_store table and save features
        pass


class TrainingDataGenerator:
    """
    Generate training datasets from historical data.
    
    Creates labeled datasets for model training:
    - Weight prediction: features at time T -> weight at time T+horizon
    - Health risk: features at time T -> health event in next N days
    """

    def __init__(self):
        self.repo = SupabaseRepository()
        self.weight_engineer = WeightFeatureEngineer()
        self.health_engineer = HealthFeatureEngineer()
        self.health_risk_engineer = HealthRiskFeatureEngineer()
        self.settings = get_settings()

    async def generate_weight_prediction_dataset(
        self,
        horizons: list[int] = [7, 14, 30],
        min_history_days: int = 14,
        output_path: str | None = None,
    ) -> list[dict]:
        """
        Generate training data for weight prediction model.
        
        For each animal with sufficient history, creates samples:
        - Features computed at time T
        - Target: actual weight at time T + horizon
        
        Args:
            horizons: Prediction horizons in days
            min_history_days: Minimum days of history required
            output_path: Path to save CSV (optional)
            
        Returns:
            List of training samples
        """
        logger.info(f"Generating weight prediction dataset with horizons: {horizons}")

        animals = await self.repo.fetch_all("animals")
        training_samples = []

        for animal in animals:
            animal_id = animal["id"]
            
            weight_records = await self.repo.fetch_all(
                "weight_records", filters={"animal_id": animal_id}
            )
            health_records = await self.repo.fetch_all(
                "health_records", filters={"animal_id": animal_id}
            )

            if len(weight_records) < 3:  # Need at least 3 measurements
                continue

            weight_records = sorted(weight_records, key=lambda x: x["date"])

            samples = self._generate_samples_for_animal(
                animal, weight_records, health_records, horizons, min_history_days
            )
            training_samples.extend(samples)

        logger.info(f"Generated {len(training_samples)} training samples")

        if output_path:
            self._save_dataset(training_samples, output_path)

        return training_samples

    def _generate_samples_for_animal(
        self,
        animal: dict,
        weight_records: list[dict],
        health_records: list[dict],
        horizons: list[int],
        min_history_days: int,
    ) -> list[dict]:
        """Generate training samples for a single animal."""
        samples = []

        for i, record in enumerate(weight_records):
            record_date = self._parse_date(record["date"])

            first_date = self._parse_date(weight_records[0]["date"])
            history_days = (record_date - first_date).days

            if history_days < min_history_days:
                continue

            for horizon in horizons:
                target_date = record_date + __import__("datetime").timedelta(days=horizon)
                target_weight = self._find_weight_near_date(
                    weight_records[i + 1 :], target_date, tolerance_days=3
                )

                if target_weight is None:
                    continue

                features = self.weight_engineer.compute_features(
                    weight_records[: i + 1], animal, as_of_date=record_date
                )

                health_features = self.health_engineer.compute_features(
                    [h for h in health_records if self._parse_date(h["date"]) <= record_date],
                    weight_features=features.to_dict(),
                    as_of_date=record_date,
                )

                sample = {
                    "animal_id": animal["id"],
                    "species": animal.get("species"),
                    "breed": animal.get("breed"),
                    "gender": animal.get("gender"),
                    "feature_date": record_date.isoformat(),
                    "horizon_days": horizon,
                    "target_weight": target_weight,
                    "current_weight": features.current_weight,
                    **{f"wf_{k}": v for k, v in features.to_dict().items()},
                    **{f"hf_{k}": v for k, v in health_features.to_dict().items()},
                }
                samples.append(sample)

        return samples

    def _parse_date(self, date_val) -> date:
        """Parse date from various formats."""
        if isinstance(date_val, date):
            return date_val
        if isinstance(date_val, datetime):
            return date_val.date()
        if isinstance(date_val, str):
            return datetime.fromisoformat(date_val.replace("Z", "+00:00")).date()
        raise ValueError(f"Cannot parse date: {date_val}")

    def _find_weight_near_date(
        self, records: list[dict], target_date: date, tolerance_days: int = 3
    ) -> float | None:
        """Find a weight record near the target date."""
        for record in records:
            record_date = self._parse_date(record["date"])
            diff = abs((record_date - target_date).days)
            if diff <= tolerance_days:
                return float(record["weight"])
        return None

    def _save_dataset(self, samples: list[dict], output_path: str) -> None:
        """Save dataset to CSV file."""
        import pandas as pd

        df = pd.DataFrame(samples)
        
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        
        df.to_csv(output_path, index=False)
        logger.info(f"Dataset saved to {output_path} ({len(df)} samples)")

    async def generate_health_risk_dataset(
        self,
        horizons: list[int] = [7, 14, 30],
        min_history_days: int = 14,
        output_path: str | None = None,
    ) -> list[dict]:
        """
        Generate training data for health risk prediction model.
        
        For each animal with sufficient history, creates samples:
        - Features computed at time T
        - Target: health events in next N days
        
        Targets:
        - target_risk_score: Computed risk score (0-100)
        - target_treatment_needed: 1 if treatment occurred in horizon, else 0
        - target_health_declined: 1 if health score dropped >10 points, else 0
        
        Args:
            horizons: Prediction horizons in days
            min_history_days: Minimum days of history required
            output_path: Path to save CSV (optional)
            
        Returns:
            List of training samples
        """
        logger.info(f"Generating health risk dataset with horizons: {horizons}")

        animals = await self.repo.fetch_all("animals")
        training_samples = []

        for animal in animals:
            animal_id = animal["id"]
            
            health_records = await self.repo.fetch_all(
                "health_records", filters={"animal_id": animal_id}
            )
            weight_records = await self.repo.fetch_all(
                "weight_records", filters={"animal_id": animal_id}
            )

            if len(health_records) < 2:  # Need some health history
                continue

            # Sort by date
            health_records = sorted(health_records, key=lambda x: x["date"])
            weight_records = sorted(weight_records, key=lambda x: x["date"])

            samples = self._generate_health_samples_for_animal(
                animal, health_records, weight_records, horizons, min_history_days
            )
            training_samples.extend(samples)

        logger.info(f"Generated {len(training_samples)} health risk training samples")
 
        if output_path:
            self._save_dataset(training_samples, output_path)

        return training_samples

    def _generate_health_samples_for_animal(
        self,
        animal: dict,
        health_records: list[dict],
        weight_records: list[dict],
        horizons: list[int],
        min_history_days: int,
    ) -> list[dict]:
        """Generate health risk training samples for a single animal."""
        samples = []
        
        if not health_records:
            return samples

        first_date = self._parse_date(health_records[0]["date"])
        last_date = self._parse_date(health_records[-1]["date"])
        

        current_date = first_date + timedelta(days=min_history_days)
        
        while current_date <= last_date - timedelta(days=max(horizons)):
            past_health = [
                h for h in health_records 
                if self._parse_date(h["date"]) <= current_date
            ]
            past_weight = [
                w for w in weight_records 
                if self._parse_date(w["date"]) <= current_date
            ]
            
            if len(past_health) < 2:
                current_date += timedelta(days=7)  # Move forward a week
                continue
            

            health_risk_features = self.health_risk_engineer.compute_features(
                past_health,
                past_weight,
                animal,
                as_of_date=current_date,
            )
            
            for horizon in horizons:
                future_date = current_date + timedelta(days=horizon)
                
                future_health = [
                    h for h in health_records
                    if current_date < self._parse_date(h["date"]) <= future_date
                ]
                
                # Target 1: Treatment needed
                treatment_needed = any(
                    h.get("type") in ["treatment", "medication"]
                    for h in future_health
                )
                
                # Target 2: Health declined (simulate based on future treatments)
                health_declined = len([
                    h for h in future_health
                    if h.get("type") in ["treatment", "medication", "illness"]
                ]) >= 2  # Multiple health events = decline
                
                # Target 3: Risk score (based on actual outcomes)
                actual_risk = self._compute_actual_risk(
                    future_health, 
                    health_risk_features.overall_risk_score
                )
                
                sample = {
                    "animal_id": animal["id"],
                    "species": animal.get("species"),
                    "breed": animal.get("breed"),
                    "gender": animal.get("gender"),
                    "feature_date": current_date.isoformat(),
                    "horizon_days": horizon,
                    # Targets
                    "target_risk_score": actual_risk,
                    "target_treatment_needed": int(treatment_needed),
                    "target_health_declined": int(health_declined),
                    # Health risk features
                    **{f"hrf_{k}": v for k, v in health_risk_features.to_dict().items()},
                }
                
                if past_weight:
                    weight_features = self.weight_engineer.compute_features(
                        past_weight, animal, as_of_date=current_date
                    )
                    sample.update({
                        f"wf_{k}": v for k, v in weight_features.to_dict().items()
                    })
                
                samples.append(sample)
            
            # Move forward (every 7 days to avoid too much overlap)
            current_date += timedelta(days=7)

        return samples

    def _compute_actual_risk(
        self,
        future_health: list[dict],
        predicted_risk: float,
    ) -> float:
        """
        Compute actual risk score based on what happened.
        
        This creates labels for supervised learning by looking at
        what actually occurred in the future period.
        """
        base_risk = 20.0  # Baseline risk
        
        # Add risk based on what happened
        for record in future_health:
            record_type = record.get("type", "")
            
            if record_type == "treatment":
                base_risk += 15
            elif record_type == "medication":
                base_risk += 10
            elif record_type == "illness":
                base_risk += 20
            elif record_type == "hospitalization":
                base_risk += 30
            elif record_type == "vaccination":
                base_risk -= 5  # Vaccinations reduce risk
            elif record_type == "checkup":
                pass  # Neutral
        
        noise = random.gauss(0, 5)
        
        return max(0, min(100, base_risk + noise))


# CLI interface for running pipeline
async def run_feature_pipeline(farm_id: str | None = None):
    """Run the feature computation pipeline."""
    pipeline = FeaturePipeline()
    results = await pipeline.compute_all_features(farm_id=farm_id)
    return results


async def generate_training_data(output_dir: str = "data/training"):
    """Generate training datasets."""
    generator = TrainingDataGenerator()
    
    await generator.generate_weight_prediction_dataset(
        horizons=[7, 14, 30],
        output_path=f"{output_dir}/weight_prediction.csv",
    )
