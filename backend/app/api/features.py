from datetime import date

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.database import SupabaseRepository
from app.features.weight_features import WeightFeatureEngineer
from app.features.health_features import HealthFeatureEngineer

router = APIRouter(prefix="/features", tags=["features"])


class WeightFeaturesResponse(BaseModel):
    animal_id: str
    farm_id: str
    computed_at: date
    features: dict


class HealthFeaturesResponse(BaseModel):
    animal_id: str
    farm_id: str
    computed_at: date
    features: dict


class AnimalFeaturesResponse(BaseModel):
    animal_id: str
    farm_id: str
    computed_at: date
    weight_features: dict
    health_features: dict



@router.get("/weight/{animal_id}", response_model=WeightFeaturesResponse)
async def get_weight_features(animal_id: str):
    repo = SupabaseRepository()
    
    animal = await repo.fetch_by_id("animals", animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal not found")
    
    weight_records = await repo.fetch_all(
        "weight_records", 
        filters={"animal_id": animal_id}
    )
    
    engineer = WeightFeatureEngineer()
    today = date.today()
    features = engineer.compute_features(weight_records, animal, as_of_date=today)
    
    return WeightFeaturesResponse(
        animal_id=animal_id,
        farm_id=animal["farm_id"],
        computed_at=today,
        features=features.to_dict(),
    )


@router.get("/health/{animal_id}", response_model=HealthFeaturesResponse)
async def get_health_features(animal_id: str):
    repo = SupabaseRepository()
    
    animal = await repo.fetch_by_id("animals", animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal not found")
    
    health_records = await repo.fetch_all(
        "health_records",
        filters={"animal_id": animal_id}
    )
    
    weight_records = await repo.fetch_all(
        "weight_records",
        filters={"animal_id": animal_id}
    )
    
    weight_engineer = WeightFeatureEngineer()
    today = date.today()
    weight_features = weight_engineer.compute_features(
        weight_records, animal, as_of_date=today
    )
    
    health_engineer = HealthFeatureEngineer()
    features = health_engineer.compute_features(
        health_records,
        weight_features=weight_features.to_dict(),
        as_of_date=today,
    )
    
    return HealthFeaturesResponse(
        animal_id=animal_id,
        farm_id=animal["farm_id"],
        computed_at=today,
        features=features.to_dict(),
    )


@router.get("/animal/{animal_id}", response_model=AnimalFeaturesResponse)
async def get_all_animal_features(animal_id: str):
    """
    Compute all features for a specific animal.
    
    Returns both weight and health features in a single response.
    This is the primary endpoint for model inference preparation.
    """
    repo = SupabaseRepository()
    
    animal = await repo.fetch_by_id("animals", animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal not found")
    
    weight_records = await repo.fetch_all(
        "weight_records",
        filters={"animal_id": animal_id}
    )
    health_records = await repo.fetch_all(
        "health_records",
        filters={"animal_id": animal_id}
    )
    
    today = date.today()
    
    # Compute weight features
    weight_engineer = WeightFeatureEngineer()
    weight_features = weight_engineer.compute_features(
        weight_records, animal, as_of_date=today
    )
    
    # Compute health features
    health_engineer = HealthFeatureEngineer()
    health_features = health_engineer.compute_features(
        health_records,
        weight_features=weight_features.to_dict(),
        as_of_date=today,
    )
    
    return AnimalFeaturesResponse(
        animal_id=animal_id,
        farm_id=animal["farm_id"],
        computed_at=today,
        weight_features=weight_features.to_dict(),
        health_features=health_features.to_dict(),
    )


@router.get("/farm/{farm_id}/summary")
async def get_farm_features_summary(farm_id: str):
    """
    Compute summary statistics for all animals in a farm.
    
    Useful for farm-level analytics and dashboards.
    """
    repo = SupabaseRepository()
    
    # Fetch all animals for the farm
    animals = await repo.fetch_by_farm("animals", farm_id)
    
    if not animals:
        raise HTTPException(status_code=404, detail="No animals found for this farm")
    
    today = date.today()
    weight_engineer = WeightFeatureEngineer()
    health_engineer = HealthFeatureEngineer()
    
    summaries = []
    total_health_score = 0
    animals_with_weight = 0
    animals_with_health = 0
    
    for animal in animals:
        animal_id = animal["id"]
        
        weight_records = await repo.fetch_all(
            "weight_records",
            filters={"animal_id": animal_id}
        )
        health_records = await repo.fetch_all(
            "health_records",
            filters={"animal_id": animal_id}
        )
        
        weight_features = weight_engineer.compute_features(
            weight_records, animal, as_of_date=today
        )
        health_features = health_engineer.compute_features(
            health_records,
            weight_features=weight_features.to_dict(),
            as_of_date=today,
        )
        
        summary = {
            "animal_id": animal_id,
            "tag_id": animal.get("tag_id"),
            "name": animal.get("name"),
            "species": animal.get("species"),
            "current_weight": weight_features.current_weight,
            "adg_30d": weight_features.adg_30d,
            "health_score": health_features.health_score,
            "days_since_last_weight": weight_features.days_since_last_weight,
        }
        summaries.append(summary)
        
        if weight_features.current_weight is not None:
            animals_with_weight += 1
        
        total_health_score += health_features.health_score
        animals_with_health += 1
    
    avg_health_score = total_health_score / animals_with_health if animals_with_health > 0 else 0
    
    return {
        "farm_id": farm_id,
        "computed_at": today.isoformat(),
        "total_animals": len(animals),
        "animals_with_weight_data": animals_with_weight,
        "average_health_score": round(avg_health_score, 1),
        "animals": summaries,
    }
