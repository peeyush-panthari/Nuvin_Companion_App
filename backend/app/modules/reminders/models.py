from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel
from datetime import datetime

class ReminderType(str, Enum):
    MEDICINE = "medicine"
    APPOINTMENT = "appointment"
    DATE = "date"
    ROUTINE = "routine"
    HABIT = "habit"
    BILL = "bill"
    OTHER = "other"

class ReminderCreate(BaseModel):
    type: ReminderType
    title: str
    schedule: str # e.g. "08:00 daily", "every Tuesday 17:00", or ISO datetime "2026-10-20T10:00:00"
    is_recurring: bool = True
    details: Optional[str] = None
    timezone: str = "Asia/Kolkata"
    source: str = "voice" # voice or ui

class ReminderResponse(BaseModel):
    id: str
    user_id: str
    type: ReminderType
    title: str
    details: Optional[str]
    schedule: str
    is_recurring: bool
    timezone: str
    status: str
    next_fire_at: Optional[datetime]
    source: str
    created_at: datetime

class ReminderAction(str, Enum):
    TAKEN = "taken"
    SNOOZE = "snooze"
    SKIP = "skip"
    HELP = "help"

class AcknowledgeOccurrence(BaseModel):
    occurrence_id: str
    reminder_id: str
    action: ReminderAction
    snooze_minutes: Optional[int] = 15
    client_timestamp: datetime
