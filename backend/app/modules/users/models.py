from enum import Enum
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field
import uuid
from datetime import datetime, timezone

class PersonaType(str, Enum):
    ELDER = "elder" # 55+
    EAR = "ear"     # 20-50

class AgeBand(str, Enum):
    BAND_18_34 = "18-34"
    BAND_35_54 = "35-54"
    BAND_55_64 = "55-64"
    BAND_65_74 = "65-74"
    BAND_75_PLUS = "75+"

class ToneType(str, Enum):
    RESPECTFUL = "respectful"
    FRIENDLY = "friendly"

class Gender(str, Enum):
    FEMALE = "female"
    MALE = "male"
    OTHER = "other"
    UNSPECIFIED = "unspecified"

class ContactCreate(BaseModel):
    display_name: str
    spoken_disambiguation: str
    relationship: str
    phone_e164: str
    kind: str = "emergency" # emergency, companion, trusted_circle, friend
    priority: int = 1

class UserProfileCreate(BaseModel):
    phone_e164: str
    display_name: str
    age_band: AgeBand
    gender: Gender = Gender.UNSPECIFIED
    companion_name: Optional[str] = "Nuvin"
    companion_gender: Optional[Gender] = None # Defaults to matching user gender
    preferred_tone: Optional[ToneType] = None # Defaults based on age band
    locale: str = "en-IN" # or "hi-IN"
    timezone: str = "Asia/Kolkata"
    emergency_contacts: List[ContactCreate] = []

class UserProfileResponse(BaseModel):
    id: str
    phone_e164: str
    display_name: str
    persona: PersonaType
    age_band: AgeBand
    gender: Gender
    companion_name: str
    companion_gender: Gender
    preferred_tone: ToneType
    locale: str
    timezone: str
    wake_word_phrase: str
    custom_wake_word_enrolled: bool
    status: str
    emergency_contacts: List[Dict[str, Any]]
    created_at: datetime
