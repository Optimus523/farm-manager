from dataclasses import dataclass, field
from datetime import date, datetime, timedelta


@dataclass
class HealthFeatures:
    # Health score (composite 0-100)
    health_score: float = 50.0

    # Treatment history
    treatment_count_7d: int = 0
    treatment_count_30d: int = 0
    treatment_count_90d: int = 0
    days_since_last_treatment: int | None = None

    # Vaccination status
    vaccination_count_total: int = 0
    overdue_vaccinations: int = 0
    vaccination_compliance_rate: float = 1.0
    days_since_last_vaccination: int | None = None

    # Health events
    sick_days_30d: int = 0
    checkup_count_90d: int = 0
    days_since_last_checkup: int | None = None

    # Risk indicators
    has_chronic_condition: bool = False
    active_treatment: bool = False
    in_withdrawal_period: bool = False

    # Recent health event types (one-hot encoded counts)
    recent_medication_count: int = 0
    recent_vaccination_count: int = 0
    recent_observation_count: int = 0

    def to_dict(self) -> dict:
        return {k: v for k, v in self.__dict__.items()}


class HealthFeatureEngineer:
    CHRONIC_INDICATORS = ["chronic", "recurring", "persistent", "long-term"]

    def compute_features(
        self,
        health_records: list[dict],
        weight_features: dict | None = None,
        feeding_features: dict | None = None,
        as_of_date: date | None = None,
    ) -> HealthFeatures:
        """
        Compute all health features for an animal.

        Args:
            health_records: List of health records for the animal
            weight_features: Pre-computed weight features (optional)
            feeding_features: Pre-computed feeding features (optional)
            as_of_date: Reference date for feature computation

        Returns:
            HealthFeatures dataclass with computed values
        """
        if as_of_date is None:
            as_of_date = date.today()

        features = HealthFeatures()

        if not health_records:
            return features

        records = self._parse_records(health_records, as_of_date)

        if not records:
            return features

        features.treatment_count_7d = self._count_by_type_and_window(
            records, ["treatment", "medication"], as_of_date, days=7
        )
        features.treatment_count_30d = self._count_by_type_and_window(
            records, ["treatment", "medication"], as_of_date, days=30
        )
        features.treatment_count_90d = self._count_by_type_and_window(
            records, ["treatment", "medication"], as_of_date, days=90
        )
        
        last_treatment = self._get_last_record_of_type(
            records, ["treatment", "medication"]
        )
        if last_treatment:
            features.days_since_last_treatment = (
                as_of_date - last_treatment["date"]
            ).days

        vaccinations = [r for r in records if r["type"] == "vaccination"]
        features.vaccination_count_total = len(vaccinations)

        if vaccinations:
            last_vax = max(vaccinations, key=lambda x: x["date"])
            features.days_since_last_vaccination = (as_of_date - last_vax["date"]).days

            features.overdue_vaccinations = sum(
                1
                for v in vaccinations
                if v.get("next_due_date")
                and v["next_due_date"] < as_of_date
            )

        features.checkup_count_90d = self._count_by_type_and_window(
            records, ["checkup"], as_of_date, days=90
        )

        last_checkup = self._get_last_record_of_type(records, ["checkup"])
        if last_checkup:
            features.days_since_last_checkup = (as_of_date - last_checkup["date"]).days

        recent_records = [
            r for r in records if (as_of_date - r["date"]).days <= 30
        ]
        features.recent_medication_count = sum(
            1 for r in recent_records if r["type"] == "medication"
        )
        features.recent_vaccination_count = sum(
            1 for r in recent_records if r["type"] == "vaccination"
        )
        features.recent_observation_count = sum(
            1 for r in recent_records if r["type"] == "observation"
        )

        # Risk indicators
        features.has_chronic_condition = self._detect_chronic_condition(records)
        features.active_treatment = self._has_active_treatment(records, as_of_date)
        features.in_withdrawal_period = self._in_withdrawal_period(records, as_of_date)

        # Compute composite health score
        features.health_score = self._compute_health_score(
            features, weight_features, feeding_features
        )

        return features

    def _parse_records(
        self, records: list[dict], as_of_date: date
    ) -> list[dict]:
        """Parse and normalize health records."""
        parsed = []
        for r in records:
            record_date = r.get("date")
            if isinstance(record_date, str):
                record_date = datetime.fromisoformat(record_date.replace("Z", "+00:00")).date()
            elif isinstance(record_date, datetime):
                record_date = record_date.date()

            if record_date and record_date <= as_of_date:
                next_due = r.get("next_due_date")
                if isinstance(next_due, str):
                    next_due = datetime.fromisoformat(next_due.replace("Z", "+00:00")).date()
                elif isinstance(next_due, datetime):
                    next_due = next_due.date()

                withdrawal_end = r.get("withdrawal_end_date")
                if isinstance(withdrawal_end, str):
                    withdrawal_end = datetime.fromisoformat(
                        withdrawal_end.replace("Z", "+00:00")
                    ).date()
                elif isinstance(withdrawal_end, datetime):
                    withdrawal_end = withdrawal_end.date()

                parsed.append({
                    **r,
                    "date": record_date,
                    "next_due_date": next_due,
                    "withdrawal_end_date": withdrawal_end,
                })

        return parsed

    def _count_by_type_and_window(
        self,
        records: list[dict],
        types: list[str],
        as_of_date: date,
        days: int,
    ) -> int:
        """Count records of specific types within a time window."""
        cutoff = as_of_date - timedelta(days=days)
        return sum(
            1
            for r in records
            if r["type"] in types and r["date"] > cutoff
        )

    def _get_last_record_of_type(
        self, records: list[dict], types: list[str]
    ) -> dict | None:
        """Get the most recent record of specified types."""
        matching = [r for r in records if r["type"] in types]
        if not matching:
            return None
        return max(matching, key=lambda x: x["date"])

    def _detect_chronic_condition(self, records: list[dict]) -> bool:
        """Detect if animal has chronic conditions based on record history."""
        for r in records:
            diagnosis = r.get("diagnosis") or ""
            notes = r.get("notes") or ""
            text = f"{diagnosis} {notes}".lower()
            if any(indicator in text for indicator in self.CHRONIC_INDICATORS):
                return True

        medications = [r.get("medication") for r in records if r.get("medication")]
        if medications:
            from collections import Counter

            med_counts = Counter(medications)
            if any(count >= 3 for count in med_counts.values()):
                return True

        return False

    def _has_active_treatment(self, records: list[dict], as_of_date: date) -> bool:
        """Check if animal has active ongoing treatment."""
        for r in records:
            if r["type"] in ["treatment", "medication"]:
                follow_up = r.get("follow_up_date")
                if follow_up and follow_up >= as_of_date:
                    return True
        return False

    def _in_withdrawal_period(self, records: list[dict], as_of_date: date) -> bool:
        """Check if animal is in medication withdrawal period."""
        for r in records:
            withdrawal_end = r.get("withdrawal_end_date")
            if withdrawal_end and withdrawal_end >= as_of_date:
                return True
        return False

    def _compute_health_score(
        self,
        features: HealthFeatures,
        weight_features: dict | None,
        feeding_features: dict | None,
    ) -> float:
        """
        Compute composite health score (0-100).

        Higher is better. Considers multiple factors with different weights.
        """
        score = 100.0

        score -= features.treatment_count_7d * 10
        score -= features.treatment_count_30d * 2

        score -= features.overdue_vaccinations * 5

        if features.checkup_count_90d >= 1:
            score += 5

        if features.has_chronic_condition:
            score -= 15

        if features.active_treatment:
            score -= 10

        if weight_features:
            weight_velocity = weight_features.get("weight_velocity_7d")
            if weight_velocity is not None:
                if weight_velocity < -0.5:   
                    score -= 20
                elif weight_velocity < 0:   
                    score -= 10
                elif weight_velocity > 0:  
                    score += 5

        if feeding_features:
            feeding_regularity = feeding_features.get("feeding_regularity_score")
            if feeding_regularity is not None:
                score += (feeding_regularity - 0.5) * 20 

        return max(0.0, min(100.0, score))
