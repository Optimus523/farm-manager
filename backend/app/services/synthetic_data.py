import random
from datetime import date, datetime, timedelta
from typing import Any
from uuid import uuid4

from app.core.database import SupabaseRepository


class SyntheticDataGenerator:
    """
    Generate realistic synthetic farm data for ML pipeline testing.
    
    Creates animals with historical weight records, health events,
    and other data needed to train and test ML models.
    """
    
    # Species-specific parameters
    SPECIES_CONFIG = {
        "pig": {
            "birth_weight": (1.0, 2.0),       # kg
            "mature_weight": (200, 350),       # kg
            "growth_rate": (0.6, 1.0),         # kg/day average
            "growth_variance": 0.1,            # daily variance
            "maturity_days": 180,              # days to market weight
        },
        "cattle": {
            "birth_weight": (25, 45),
            "mature_weight": (400, 700),
            "growth_rate": (0.8, 1.5),
            "growth_variance": 0.15,
            "maturity_days": 365,
        },
        "goat": {
            "birth_weight": (2.5, 4.5),
            "mature_weight": (40, 80),
            "growth_rate": (0.1, 0.2),
            "growth_variance": 0.08,
            "maturity_days": 270,
        },
        "sheep": {
            "birth_weight": (3.0, 5.0),
            "mature_weight": (50, 120),
            "growth_rate": (0.15, 0.3),
            "growth_variance": 0.1,
            "maturity_days": 240,
        },
        "chicken": {
            "birth_weight": (0.04, 0.05),
            "mature_weight": (2.0, 4.0),
            "growth_rate": (0.03, 0.06),
            "growth_variance": 0.05,
            "maturity_days": 56,
        },
    }
    
    HEALTH_EVENT_TYPES = ["vaccination", "treatment", "checkup", "observation", "medication"]
    
    COMMON_VACCINES = {
        "pig": ["PCV2", "PRRS", "Mycoplasma", "E.coli", "Erysipelas"],
        "cattle": ["BVD", "IBR", "Blackleg", "Anthrax", "Brucellosis"],
        "goat": ["CDT", "Rabies", "CL", "Soremouth"],
        "sheep": ["CDT", "Footrot", "Bluetongue", "Scrapie"],
        "chicken": ["Marek's", "Newcastle", "IBD", "IB"],
    }
    
    def __init__(self, farm_id: str | None = None):
        self.repo = SupabaseRepository()
        self.farm_id = farm_id
    
    async def get_or_create_farm(self) -> str:
        """Get existing farm or create a test farm."""
        if self.farm_id:
            return self.farm_id
        
        # Try to get existing farm
        response = self.repo.client.table("farms").select("id").limit(1).execute()
        
        if response.data:
            self.farm_id = response.data[0]["id"]
            return self.farm_id
        
        # Create a test farm
        farm_data = {
            "id": str(uuid4()),
            "name": "ML Test Farm",
            "location": "Test Location",
            "created_at": datetime.utcnow().isoformat(),
        }
        
        self.repo.client.table("farms").insert(farm_data).execute()
        self.farm_id = farm_data["id"]
        return self.farm_id
    
    def _generate_growth_curve(
        self,
        species: str,
        start_date: date,
        num_days: int,
        measurement_frequency: int = 7,
    ) -> list[tuple[date, float]]:
        """Generate realistic weight measurements following growth curve."""
        config = self.SPECIES_CONFIG.get(species, self.SPECIES_CONFIG["pig"])
        
        birth_weight = random.uniform(*config["birth_weight"])
        target_weight = random.uniform(*config["mature_weight"])
        base_growth_rate = random.uniform(*config["growth_rate"])
        variance = config["growth_variance"]
        maturity_days = config["maturity_days"]
        
        weights = []
        current_weight = birth_weight
        
        for day in range(0, num_days, measurement_frequency):
            record_date = start_date + timedelta(days=day)
            
            # Gompertz growth curve: rapid early growth, slowing as approaching maturity
            age_factor = day / maturity_days
            growth_factor = max(0.2, 1 - age_factor)  # Slower growth as animal ages
            
            # Add daily growth with variance
            days_since_last = measurement_frequency
            daily_growth = base_growth_rate * growth_factor
            
            for _ in range(days_since_last):
                growth = daily_growth * (1 + random.gauss(0, variance))
                growth = max(0, growth)  # No negative growth
                
                # Cap at mature weight
                if current_weight + growth > target_weight:
                    growth = max(0, target_weight - current_weight) * 0.1
                
                current_weight += growth
            
            # Add measurement noise (scale error ~2%)
            measured_weight = current_weight * (1 + random.gauss(0, 0.02))
            weights.append((record_date, round(measured_weight, 2)))
        
        return weights
    
    def _generate_health_events(
        self,
        species: str,
        start_date: date,
        num_days: int,
    ) -> list[dict[str, Any]]:
        """Generate realistic health events."""
        events = []
        current_date = start_date
        vaccines = self.COMMON_VACCINES.get(species, ["General Vaccine"])
        
        # Schedule vaccinations (typically at specific ages)
        vaccination_schedule = [7, 21, 42, 90, 180]  # Days after birth
        
        for vax_day in vaccination_schedule:
            if vax_day <= num_days:
                vax_date = start_date + timedelta(days=vax_day)
                events.append({
                    "date": vax_date,
                    "type": "vaccination",
                    "description": f"Administered {random.choice(vaccines)} vaccine",
                    "notes": f"Routine vaccination at day {vax_day}",
                })
        
        # Random health events
        while current_date < start_date + timedelta(days=num_days):
            # Checkups every 30-60 days
            if random.random() < 0.03:  # ~3% chance per day
                events.append({
                    "date": current_date,
                    "type": "checkup",
                    "description": "Routine health checkup",
                    "notes": "Animal appears healthy",
                })
            
            # Occasional treatments (illness ~5% of animals at some point)
            if random.random() < 0.005:  # ~0.5% chance per day
                treatment_duration = random.randint(3, 7)
                events.append({
                    "date": current_date,
                    "type": "treatment",
                    "description": random.choice([
                        "Treated for respiratory infection",
                        "Treated for digestive issues",
                        "Treated for lameness",
                        "Treated for skin condition",
                    ]),
                    "notes": f"Treatment duration: {treatment_duration} days",
                })
            
            current_date += timedelta(days=1)
        
        return sorted(events, key=lambda x: x["date"])
    
    async def generate_animal(
        self,
        species: str = "pig",
        age_days: int | None = None,
        history_days: int = 90,
    ) -> dict[str, Any]:
        """
        Generate a single animal with full history.
        
        Args:
            species: Animal species
            age_days: Age of animal in days (random if None)
            history_days: Days of historical data to generate
            
        Returns:
            Dict with animal_id and counts of generated records
        """
        farm_id = await self.get_or_create_farm()
        
        if age_days is None:
            config = self.SPECIES_CONFIG.get(species, self.SPECIES_CONFIG["pig"])
            age_days = random.randint(30, config["maturity_days"])
        
        # Generate animal
        animal_id = str(uuid4())
        birth_date = date.today() - timedelta(days=age_days)
        tag_id = f"SYN-{random.randint(10000, 99999)}"
        
        animal_data = {
            "id": animal_id,
            "farm_id": farm_id,
            "tag_id": tag_id,
            "species": species,
            "name": f"Test {species.title()} {tag_id[-4:]}",
            "date_of_birth": birth_date.isoformat(),
            "gender": random.choice(["male", "female"]),
            "breed": f"Test {species.title()} Breed",
            "status": "active",
            "created_at": datetime.utcnow().isoformat(),
        }
        
        # Insert animal
        self.repo.client.table("animals").insert(animal_data).execute()
        
        # Generate weight history
        history_start = max(birth_date, date.today() - timedelta(days=history_days))
        actual_history_days = (date.today() - history_start).days
        
        weight_records = self._generate_growth_curve(
            species=species,
            start_date=history_start,
            num_days=actual_history_days,
            measurement_frequency=random.choice([3, 5, 7]),  # Vary frequency
        )
        
        # Insert weight records
        weight_data = [
            {
                "id": str(uuid4()),
                "animal_id": animal_id,
                "farm_id": farm_id,
                "weight": weight,
                "date": datetime.combine(record_date, datetime.min.time()).isoformat(),
                "notes": "Synthetic data for ML testing",
                "created_at": datetime.utcnow().isoformat(),
            }
            for record_date, weight in weight_records
        ]
        
        if weight_data:
            self.repo.client.table("weight_records").insert(weight_data).execute()
        
        # Generate health events
        health_events = self._generate_health_events(
            species=species,
            start_date=history_start,
            num_days=actual_history_days,
        )
        
        # Insert health records - match actual schema (title required, use timestamptz)
        health_data = [
            {
                "id": str(uuid4()),
                "animal_id": animal_id,
                "farm_id": farm_id,
                "date": datetime.combine(event["date"], datetime.min.time()).isoformat(),
                "type": event["type"],
                "title": event["type"].title(),
                "description": event["description"],
                "notes": event["notes"],
                "created_at": datetime.utcnow().isoformat(),
            }
            for event in health_events
        ]
        
        if health_data:
            self.repo.client.table("health_records").insert(health_data).execute()
        
        return {
            "animal_id": animal_id,
            "tag_id": tag_id,
            "species": species,
            "age_days": age_days,
            "weight_records": len(weight_data),
            "health_records": len(health_data),
        }
    
    async def generate_herd(
        self,
        count: int = 20,
        species_distribution: dict[str, float] | None = None,
        min_age_days: int = 30,
        max_age_days: int = 180,
        history_days: int = 90,
    ) -> dict[str, Any]:
        """
        Generate a herd of animals with historical data.
        
        Args:
            count: Number of animals to generate
            species_distribution: Dict mapping species to proportion (e.g., {"pig": 0.7, "goat": 0.3})
            min_age_days: Minimum age of animals
            max_age_days: Maximum age of animals
            history_days: Days of historical data per animal
            
        Returns:
            Summary of generated data
        """
        if species_distribution is None:
            species_distribution = {"pig": 1.0}
        
        # Normalize distribution
        total = sum(species_distribution.values())
        species_distribution = {k: v / total for k, v in species_distribution.items()}
        
        results = {
            "total_animals": 0,
            "total_weight_records": 0,
            "total_health_records": 0,
            "by_species": {},
            "animals": [],
        }
        
        for species, proportion in species_distribution.items():
            species_count = max(1, int(count * proportion))
            results["by_species"][species] = {"count": 0, "weight_records": 0, "health_records": 0}
            
            for _ in range(species_count):
                if results["total_animals"] >= count:
                    break
                
                age = random.randint(min_age_days, max_age_days)
                animal = await self.generate_animal(
                    species=species,
                    age_days=age,
                    history_days=history_days,
                )
                
                results["animals"].append(animal)
                results["total_animals"] += 1
                results["total_weight_records"] += animal["weight_records"]
                results["total_health_records"] += animal["health_records"]
                results["by_species"][species]["count"] += 1
                results["by_species"][species]["weight_records"] += animal["weight_records"]
                results["by_species"][species]["health_records"] += animal["health_records"]
        
        return results
    
    async def clear_synthetic_data(self) -> dict[str, int]:
        """
        Remove all synthetic data (records with 'Synthetic' or 'SYN-' markers).
        
        Returns:
            Count of deleted records by type
        """
        deleted = {
            "health_records": 0,
            "weight_records": 0,
            "animals": 0,
        }
        
        # Find synthetic animals
        response = self.repo.client.table("animals").select(
            "id"
        ).like("tag_id", "SYN-%").execute()
        
        synthetic_ids = [r["id"] for r in response.data]
        
        if synthetic_ids:
            # Delete related records first (foreign key constraints)
            for animal_id in synthetic_ids:
                # Delete health records
                self.repo.client.table("health_records").delete().eq(
                    "animal_id", animal_id
                ).execute()
                
                # Delete weight records
                self.repo.client.table("weight_records").delete().eq(
                    "animal_id", animal_id
                ).execute()
            
            # Delete animals
            self.repo.client.table("animals").delete().in_(
                "id", synthetic_ids
            ).execute()
            
            deleted["animals"] = len(synthetic_ids)
        
        return deleted
