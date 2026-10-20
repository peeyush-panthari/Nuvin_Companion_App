from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime
import uuid

class MemoryItemCreate(BaseModel):
    category: str # fact, preference, routine, health, person, story
    key: str
    value: str
    sensitivity: int = 2
    source_type: str = "conversation" # conversation, onboarding, user_edit

class MemoryItemResponse(BaseModel):
    id: str
    user_id: str
    category: str
    key: str
    value: str
    sensitivity: int
    source_type: str
    confidence: float
    created_at: datetime
    deleted_at: Optional[datetime] = None

class LifeThreadCreate(BaseModel):
    category: str # career, relationship, grief, caregiving, health_routine, family, goal, preference, other
    title: str
    summary: str
    entities: List[str] = []

class LifeThreadResponse(BaseModel):
    id: str
    user_id: str
    category: str
    title: str
    summary: str
    entities: List[str]
    status: str
    last_discussed_at: datetime
    created_at: datetime

class OpenUIMemoryCard(BaseModel):
    title: str
    subtitle: str
    items: List[Dict[str, Any]]
    total_count: int
