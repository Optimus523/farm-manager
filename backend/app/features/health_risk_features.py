from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any


@dataclass
class HealthRiskFeatures:
    """Features engineered for health risk prediction."""
    
    # Current health state
    current_health_score: float = 50.0
    days_since_last_health_event: int | None = None
    
    # Treatment history patterns
    treatment_frequency_7d: float = 0.0  # treatments per day
    treatment_frequency_30d: float = 0.0
    treatment_frequency_90d: float = 0.0
    treatment_trend: float = 0.0  # positive = increasing treatments
    days_since_last_treatment: int | None = None
    
    # Treatment severity indicators
    severe_treatment_count_30d: int = 0
    antibiotic_count_30d: int = 0
    hospitalization_count_90d: int = 0
    
    # Vaccination status
    vaccination_count_total: int = 0
    overdue_vaccinations: int = 0
    days_until_next_vaccination: int | None = None
    vaccination_coverage: float = 1.0  # 0-1, higher is better
    
    # Recurring issues
    recurring_condition_count: int = 0
    same_treatment_repeat_count_90d: int = 0
    has_chronic_condition: bool = False
    
    # Weight-health correlation
    weight_loss_flag: bool = False
    rapid_weight_change: bool = False
    weight_below_expected: bool = False
    
    # Feeding-health correlation  
    appetite_decline_flag: bool = False
    irregular_feeding_pattern: bool = False
    
    # Environmental/seasonal risk
    season_risk_factor: float = 1.0  # multiplier based on season
    herd_outbreak_risk: float = 0.0  # risk from other animals
    
    # Age-related risk
    age_risk_factor: float = 1.0   
    days_since_birth: int | None = None
    
    # Checkup patterns
    days_since_last_checkup: int | None = None
    missed_checkup_count: int = 0
    checkup_frequency_score: float = 1.0
    
    # Computed risk indicators
    treatment_risk_score: float = 0.0
    vaccination_risk_score: float = 0.0
    chronic_risk_score: float = 0.0
    overall_risk_score: float = 0.0

    def to_dict(self) -> dict:
        """Convert to dictionary for ML model input."""
        return {k: v for k, v in self.__dict__.items()}


class HealthRiskFeatureEngineer:
    """Engineer features for health risk prediction model."""
    SEVERE_INDICATORS = ["severe", "critical", "emergency", "hospitalization", "surgery"]
    ANTIBIOTIC_KEYWORDS = ["antibiotic", "amoxicillin", "penicillin", "tetracycline", "sulfa"]
    CHRONIC_INDICATORS = ["chronic", "recurring", "persistent", "long-term", "ongoing"]
    
    # Dry seasons: Dec-Feb, Jun-Aug | Wet seasons: Mar-May, Sep-Nov
    SEASON_RISK = {
        "dry": 1.0,      # Baseline - lower disease transmission
        "wet": 1.3,      # Higher risk - parasites, waterborne diseases, hoof issues
        "transition": 1.15,  # Transitional periods
    }

    def compute_features(
        self,
        health_records: list[dict],
        weight_records: list[dict] | None = None,
        animal_info: dict | None = None,
        herd_health_stats: dict | None = None,
        as_of_date: date | None = None,
    ) -> HealthRiskFeatures:
        """
        Compute health risk features for ML model input.
        
        Args:
            health_records: Animal's health history
            weight_records: Animal's weight history (for correlation)
            animal_info: Animal metadata (species, breed, birth_date)
            herd_health_stats: Aggregate health stats from the herd
            as_of_date: Reference date for computation
            
        Returns:
            HealthRiskFeatures dataclass
        """
        if as_of_date is None:
            as_of_date = date.today()
            
        features = HealthRiskFeatures()
        
        if not health_records:
            features.overall_risk_score = self._compute_baseline_risk(animal_info, as_of_date)
            return features
        
        # Parse and filter records
        records = self._parse_records(health_records, as_of_date)
        
        if not records:
            features.overall_risk_score = self._compute_baseline_risk(animal_info, as_of_date)
            return features
        
        # Compute treatment features
        self._compute_treatment_features(features, records, as_of_date)
        
        # Compute vaccination features
        self._compute_vaccination_features(features, records, as_of_date)
        
        # Compute chronic/recurring features
        self._compute_chronic_features(features, records, as_of_date)
        
        # Compute checkup features
        self._compute_checkup_features(features, records, as_of_date)
        
        # Compute weight correlation features
        if weight_records:
            self._compute_weight_correlation(features, weight_records, as_of_date)
        
        # Compute age risk
        if animal_info:
            self._compute_age_risk(features, animal_info, as_of_date)
        
        # Compute seasonal risk
        self._compute_seasonal_risk(features, as_of_date)
        
        # Compute herd risk
        if herd_health_stats:
            self._compute_herd_risk(features, herd_health_stats)
        
        # Compute current health score
        features.current_health_score = self._compute_health_score(features, records)
        
        # Compute component risk scores
        features.treatment_risk_score = self._compute_treatment_risk(features)
        features.vaccination_risk_score = self._compute_vaccination_risk(features)
        features.chronic_risk_score = self._compute_chronic_risk(features)
        
        # Compute overall risk score
        features.overall_risk_score = self._compute_overall_risk(features)
        
        return features
    
    def _parse_records(self, records: list[dict], as_of_date: date) -> list[dict]:
        """Parse and normalize health records."""
        parsed = []
        for r in records:
            record_date = r.get("date")
            if isinstance(record_date, str):
                record_date = datetime.fromisoformat(
                    record_date.replace("Z", "+00:00")
                ).date()
            elif isinstance(record_date, datetime):
                record_date = record_date.date()
            
            if record_date and record_date <= as_of_date:
                parsed.append({
                    **r,
                    "date": record_date,
                    "next_due_date": self._parse_optional_date(r.get("next_due_date")),
                    "withdrawal_end_date": self._parse_optional_date(r.get("withdrawal_end_date")),
                })
        
        return sorted(parsed, key=lambda x: x["date"], reverse=True)
    
    def _parse_optional_date(self, date_val) -> date | None:
        """Parse optional date field."""
        if date_val is None:
            return None
        if isinstance(date_val, date):
            return date_val
        if isinstance(date_val, datetime):
            return date_val.date()
        if isinstance(date_val, str):
            return datetime.fromisoformat(date_val.replace("Z", "+00:00")).date()
        return None
    
    def _compute_treatment_features(
        self,
        features: HealthRiskFeatures,
        records: list[dict],
        as_of_date: date,
    ) -> None:
        """Compute treatment-related features."""
        treatments = [r for r in records if r.get("type") in ["treatment", "medication"]]
        
        if treatments:
            # Days since last treatment
            last_treatment = treatments[0]
            features.days_since_last_treatment = (as_of_date - last_treatment["date"]).days
            features.days_since_last_health_event = features.days_since_last_treatment
        
        # Treatment counts by window
        t_7d = self._count_in_window(treatments, as_of_date, 7)
        t_30d = self._count_in_window(treatments, as_of_date, 30)
        t_90d = self._count_in_window(treatments, as_of_date, 90)
        
        features.treatment_frequency_7d = t_7d / 7.0
        features.treatment_frequency_30d = t_30d / 30.0
        features.treatment_frequency_90d = t_90d / 90.0
        
        # Treatment trend (increasing or decreasing)
        if t_90d > 0:
            recent_rate = t_30d / 30.0
            older_rate = (t_90d - t_30d) / 60.0
            features.treatment_trend = recent_rate - older_rate
        
        # Severity indicators
        for t in treatments:
            text = f"{t.get('diagnosis', '')} {t.get('notes', '')} {t.get('medication', '')}".lower()
            record_date = t["date"]
            days_ago = (as_of_date - record_date).days
            
            if days_ago <= 30:
                if any(kw in text for kw in self.SEVERE_INDICATORS):
                    features.severe_treatment_count_30d += 1
                if any(kw in text for kw in self.ANTIBIOTIC_KEYWORDS):
                    features.antibiotic_count_30d += 1
            
            if days_ago <= 90:
                if "hospitalization" in text or "hospital" in text:
                    features.hospitalization_count_90d += 1
    
    def _compute_vaccination_features(
        self,
        features: HealthRiskFeatures,
        records: list[dict],
        as_of_date: date,
    ) -> None:
        """Compute vaccination-related features."""
        vaccinations = [r for r in records if r.get("type") == "vaccination"]
        
        features.vaccination_count_total = len(vaccinations)
        
        if vaccinations:
            # Find overdue vaccinations
            for v in vaccinations:
                next_due = v.get("next_due_date")
                if next_due and next_due < as_of_date:
                    features.overdue_vaccinations += 1
            
            # Find next upcoming vaccination
            upcoming = [
                v for v in vaccinations
                if v.get("next_due_date") and v["next_due_date"] >= as_of_date
            ]
            if upcoming:
                next_vax = min(upcoming, key=lambda x: x["next_due_date"])
                features.days_until_next_vaccination = (next_vax["next_due_date"] - as_of_date).days
            
            # Vaccination coverage (simplified - ratio of on-time vaccinations)
            if features.vaccination_count_total > 0:
                on_time = features.vaccination_count_total - features.overdue_vaccinations
                features.vaccination_coverage = on_time / features.vaccination_count_total
    
    def _compute_chronic_features(
        self,
        features: HealthRiskFeatures,
        records: list[dict],
        as_of_date: date,
    ) -> None:
        """Compute chronic/recurring condition features."""
        # Check for chronic condition indicators
        for r in records:
            text = f"{r.get('diagnosis', '')} {r.get('notes', '')}".lower()
            if any(indicator in text for indicator in self.CHRONIC_INDICATORS):
                features.has_chronic_condition = True
                features.recurring_condition_count += 1
        
        # Check for repeated same treatments (indicates recurring issue)
        treatments_90d = [
            r for r in records
            if r.get("type") in ["treatment", "medication"]
            and (as_of_date - r["date"]).days <= 90
        ]
        
        medication_counts: dict[str, int] = {}
        for t in treatments_90d:
            med = (t.get("medication") or "").lower()
            if med:
                medication_counts[med] = medication_counts.get(med, 0) + 1
        
        # Count medications used 2+ times
        features.same_treatment_repeat_count_90d = sum(
            1 for count in medication_counts.values() if count >= 2
        )
    
    def _compute_checkup_features(
        self,
        features: HealthRiskFeatures,
        records: list[dict],
        as_of_date: date,
    ) -> None:
        """Compute checkup-related features."""
        checkups = [r for r in records if r.get("type") == "checkup"]
        
        if checkups:
            last_checkup = checkups[0]
            features.days_since_last_checkup = (as_of_date - last_checkup["date"]).days
            
            # Check frequency - ideal is every 90 days
            checkups_180d = self._count_in_window(checkups, as_of_date, 180)
            expected_checkups = 2  # 180 days / 90 day ideal interval
            features.checkup_frequency_score = min(1.0, checkups_180d / expected_checkups)
    
    def _compute_weight_correlation(
        self,
        features: HealthRiskFeatures,
        weight_records: list[dict],
        as_of_date: date,
    ) -> None:
        """Compute weight-health correlation features."""
        if not weight_records:
            return
        
        # Parse and sort weight records
        weights = []
        for w in weight_records:
            w_date = w.get("date")
            if isinstance(w_date, str):
                w_date = datetime.fromisoformat(w_date.replace("Z", "+00:00")).date()
            elif isinstance(w_date, datetime):
                w_date = w_date.date()
            if w_date and w_date <= as_of_date:
                weights.append({"date": w_date, "weight": float(w.get("weight", 0))})
        
        if len(weights) < 2:
            return
        
        weights = sorted(weights, key=lambda x: x["date"], reverse=True)
        
        # Get recent weights
        recent = [w for w in weights if (as_of_date - w["date"]).days <= 14]
        older = [w for w in weights if 14 < (as_of_date - w["date"]).days <= 30]
        
        if recent and older:
            recent_avg = sum(w["weight"] for w in recent) / len(recent)
            older_avg = sum(w["weight"] for w in older) / len(older)
            
            weight_change = recent_avg - older_avg
            change_pct = (weight_change / older_avg) * 100 if older_avg > 0 else 0
            
            # Weight loss flag
            if weight_change < 0:
                features.weight_loss_flag = True
            
            # Rapid weight change (>5% in 2 weeks)
            if abs(change_pct) > 5:
                features.rapid_weight_change = True
    
    def _compute_age_risk(
        self,
        features: HealthRiskFeatures,
        animal_info: dict,
        as_of_date: date,
    ) -> None:
        """Compute age-related risk factor."""
        birth_date = animal_info.get("birth_date")
        if birth_date:
            if isinstance(birth_date, str):
                birth_date = datetime.fromisoformat(birth_date.replace("Z", "+00:00")).date()
            elif isinstance(birth_date, datetime):
                birth_date = birth_date.date()
            
            features.days_since_birth = (as_of_date - birth_date).days
            age_months = features.days_since_birth / 30
            
            # Young and old animals have higher risk
            if age_months < 3:
                features.age_risk_factor = 1.5  # Very young
            elif age_months < 6:
                features.age_risk_factor = 1.2  # Young
            elif age_months > 60:  # 5 years
                features.age_risk_factor = 1.3  # Old
            else:
                features.age_risk_factor = 1.0  # Prime age
    
    def _compute_seasonal_risk(
        self,
        features: HealthRiskFeatures,
        as_of_date: date,
    ) -> None:
        """
        Compute seasonal risk factor for Uganda's climate.
        
        Uganda has two main seasons:
        - Dry Season: December-February, June-August
        - Wet Season (Long Rains): March-May
        - Wet Season (Short Rains): September-November
        
        Wet seasons have higher disease risk due to:
        - Increased parasites (ticks, worms)
        - Waterborne diseases
        - Mud causing hoof problems
        - Higher humidity stress
        """
        month = as_of_date.month
        
        # Dry seasons: Dec-Feb, Jun-Aug
        if month in [12, 1, 2, 6, 7, 8]:
            features.season_risk_factor = self.SEASON_RISK["dry"]
        # Wet seasons: Mar-May (long rains), Sep-Nov (short rains)
        elif month in [3, 4, 5, 9, 10, 11]:
            features.season_risk_factor = self.SEASON_RISK["wet"]
    
    def _compute_herd_risk(
        self,
        features: HealthRiskFeatures,
        herd_stats: dict,
    ) -> None:
        """Compute risk from herd health conditions."""
        # If there's an outbreak or high treatment rate in the herd
        herd_treatment_rate = herd_stats.get("treatment_rate_7d", 0)
        outbreak_flag = herd_stats.get("outbreak_flag", False)
        
        if outbreak_flag:
            features.herd_outbreak_risk = 0.5
        elif herd_treatment_rate > 0.1:  # >10% of herd treated recently
            features.herd_outbreak_risk = 0.3
        elif herd_treatment_rate > 0.05:
            features.herd_outbreak_risk = 0.1
    
    def _count_in_window(
        self,
        records: list[dict],
        as_of_date: date,
        days: int,
    ) -> int:
        """Count records within a time window."""
        cutoff = as_of_date - timedelta(days=days)
        return sum(1 for r in records if r["date"] > cutoff)
    
    def _compute_baseline_risk(
        self,
        animal_info: dict | None,
        as_of_date: date,
    ) -> float:
        """Compute baseline risk when no health records exist."""
        base_risk = 20.0  # Default risk for no records
        
        # Increase if no records at all (unknown health status)
        if animal_info:
            birth_date = animal_info.get("birth_date")
            if birth_date:
                if isinstance(birth_date, str):
                    birth_date = datetime.fromisoformat(birth_date.replace("Z", "+00:00")).date()
                age_days = (as_of_date - birth_date).days
                
                # Young animals without health records = higher concern
                if age_days < 90:
                    base_risk = 35.0
        
        return base_risk
    
    def _compute_health_score(
        self,
        features: HealthRiskFeatures,
        records: list[dict],
    ) -> float:
        """Compute current health score (0-100, higher is healthier)."""
        score = 100.0
        
        # Recent treatments reduce score
        score -= features.treatment_frequency_7d * 70  # Up to -10 for daily treatments
        score -= features.treatment_frequency_30d * 30
        
        # Severe treatments reduce score more
        score -= features.severe_treatment_count_30d * 10
        score -= features.antibiotic_count_30d * 5
        score -= features.hospitalization_count_90d * 15
        
        # Overdue vaccinations reduce score
        score -= features.overdue_vaccinations * 5
        
        # Chronic conditions reduce score
        if features.has_chronic_condition:
            score -= 15
        
        # Weight issues reduce score
        if features.weight_loss_flag:
            score -= 10
        if features.rapid_weight_change:
            score -= 5
        
        # Missed checkups reduce score
        if features.days_since_last_checkup and features.days_since_last_checkup > 120:
            score -= 10
        
        return max(0.0, min(100.0, score))
    
    def _compute_treatment_risk(self, features: HealthRiskFeatures) -> float:
        """Compute treatment-based risk score (0-100)."""
        risk = 0.0
        
        # Higher treatment frequency = higher risk
        risk += features.treatment_frequency_30d * 200
        
        # Increasing trend = higher risk
        if features.treatment_trend > 0:
            risk += features.treatment_trend * 50
        
        # Severe treatments indicate higher risk
        risk += features.severe_treatment_count_30d * 15
        risk += features.antibiotic_count_30d * 10
        risk += features.hospitalization_count_90d * 20
        
        return min(100.0, risk)
    
    def _compute_vaccination_risk(self, features: HealthRiskFeatures) -> float:
        """Compute vaccination-based risk score (0-100)."""
        risk = 0.0
        
        # Overdue vaccinations increase risk
        risk += features.overdue_vaccinations * 15
        
        # Low coverage increases risk
        risk += (1.0 - features.vaccination_coverage) * 30
        
        # No vaccinations at all is risky
        if features.vaccination_count_total == 0:
            risk += 20
        
        return min(100.0, risk)
    
    def _compute_chronic_risk(self, features: HealthRiskFeatures) -> float:
        """Compute chronic condition risk score (0-100)."""
        risk = 0.0
        
        if features.has_chronic_condition:
            risk += 30
        
        risk += features.recurring_condition_count * 10
        risk += features.same_treatment_repeat_count_90d * 15
        
        return min(100.0, risk)
    
    def _compute_overall_risk(self, features: HealthRiskFeatures) -> float:
        """Compute overall health risk score (0-100)."""
        # Weighted combination of component risks
        risk = (
            features.treatment_risk_score * 0.35 +
            features.vaccination_risk_score * 0.20 +
            features.chronic_risk_score * 0.25 +
            (100.0 - features.current_health_score) * 0.20
        )
        
        # Apply multipliers
        risk *= features.age_risk_factor
        risk *= features.season_risk_factor
        risk += features.herd_outbreak_risk * 20
        
        # Weight correlation adjustments
        if features.weight_loss_flag:
            risk += 10
        if features.rapid_weight_change:
            risk += 5
        
        return min(100.0, max(0.0, risk))
