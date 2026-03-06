from datetime import date, datetime
from decimal import Decimal
from enum import Enum

from pydantic import BaseModel, Field


class Species(str, Enum):
    """Animal species supported by the system."""

    CATTLE = "cattle"
    GOAT = "goat"
    SHEEP = "sheep"
    PIG = "pig"
    POULTRY = "poultry"
    RABBIT = "rabbit"


class Gender(str, Enum):
    """Animal gender."""

    MALE = "male"
    FEMALE = "female"


class AnimalStatus(str, Enum):
    """Current status of an animal."""

    ACTIVE = "active"
    SOLD = "sold"
    DECEASED = "deceased"
    QUARANTINED = "quarantined"


class BreedingStatus(str, Enum):
    """Breeding record status."""

    IN_HEAT = "in_heat"
    BRED = "bred"
    CONFIRMED_PREGNANT = "confirmed_pregnant"
    FARROWED = "farrowed"
    FAILED = "failed"


class HealthRecordType(str, Enum):
    """Type of health record."""

    VACCINATION = "vaccination"
    MEDICATION = "medication"
    CHECKUP = "checkup"
    TREATMENT = "treatment"
    OBSERVATION = "observation"


class TimestampMixin(BaseModel):
    """Mixin for timestamp fields."""

    created_at: datetime | None = None
    updated_at: datetime | None = None

class AnimalBase(BaseModel):
    """Base animal model with common fields."""

    tag_id: str
    name: str | None = None
    species: Species
    breed: str | None = None
    gender: Gender
    status: AnimalStatus = AnimalStatus.ACTIVE
    date_of_birth: date | None = None
    current_weight: Decimal | None = None
    purchase_price: Decimal | None = None
    purchase_date: date | None = None
    mother_id: str | None = None
    father_id: str | None = None
    notes: str | None = None


class Animal(AnimalBase, TimestampMixin):
    """Full animal model with ID and timestamps."""

    id: str
    farm_id: str
    photo_url: str | None = None
    photo_gallery: list[str] = Field(default_factory=list)
    rfid_tag_id: str | None = None

class WeightRecordBase(BaseModel):
    """Base weight record model."""

    weight: Decimal
    date: datetime
    notes: str | None = None


class WeightRecord(WeightRecordBase):
    """Full weight record with IDs."""

    id: str
    farm_id: str
    animal_id: str
    created_at: datetime | None = None


class HealthRecordBase(BaseModel):
    """Base health record model."""

    type: HealthRecordType
    title: str
    description: str | None = None
    date: datetime
    status: str = "pending"
    veterinarian: str | None = None
    diagnosis: str | None = None
    treatment: str | None = None
    medication: str | None = None
    dosage: str | None = None
    vaccine_name: str | None = None
    next_due_date: datetime | None = None
    follow_up_date: datetime | None = None
    withdrawal_end_date: datetime | None = None
    cost: Decimal | None = None
    notes: str | None = None


class HealthRecord(HealthRecordBase, TimestampMixin):
    """Full health record with IDs."""

    id: str
    farm_id: str
    animal_id: str

class FeedingRecordBase(BaseModel):
    """Base feeding record model."""

    feed_type: str
    quantity: Decimal
    unit: str = "kg"
    cost: Decimal | None = None
    date: datetime
    notes: str | None = None


class FeedingRecord(FeedingRecordBase, TimestampMixin):
    """Full feeding record with IDs."""

    id: str
    farm_id: str
    animal_id: str | None = None

class BreedingRecordBase(BaseModel):
    """Base breeding record model."""

    status: BreedingStatus = BreedingStatus.IN_HEAT
    heat_date: datetime
    breeding_date: datetime | None = None
    expected_farrow_date: datetime | None = None
    actual_farrow_date: datetime | None = None
    litter_size: int | None = None
    notes: str | None = None


class BreedingRecord(BreedingRecordBase, TimestampMixin):
    """Full breeding record with IDs."""

    id: str
    farm_id: str
    animal_id: str
    sire_id: str | None = None


class TransactionBase(BaseModel):
    """Base transaction model."""

    type: str  # income, expense
    category: str
    amount: Decimal
    date: datetime
    description: str | None = None
    payment_method: str | None = None
    reference_number: str | None = None
    notes: str | None = None


class Transaction(TransactionBase, TimestampMixin):
    """Full transaction with IDs."""

    id: str
    farm_id: str
    animal_id: str | None = None
