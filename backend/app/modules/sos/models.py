from typing import Optional, List, Dict, Any
from pydantic import BaseModel
from datetime import datetime
from enum import Enum

class SOSTriggerType(str, Enum):
    BUTTON_HOLD = "button_hold"
    VOICE_KEYWORD = "voice_keyword"
    MANUAL = "manual"

class SOSTriggerRequest(BaseModel):
    trigger_type: SOSTriggerType = SOSTriggerType.BUTTON_HOLD
    latitude: float
    longitude: float
    accuracy_meters: Optional[float] = 10.0

class LocationPingRequest(BaseModel):
    latitude: float
    longitude: float
    accuracy_meters: Optional[float] = 10.0

class SOSIncidentResponse(BaseModel):
    incident_id: str
    user_id: str
    state: str
    initial_latitude: float
    initial_longitude: float
    google_maps_pin_url: str
    live_tracking_token: str
    live_tracking_url: str
    tracking_expires_at: datetime
    contacts_notified_count: int
    sms_notification_payloads: List[Dict[str, Any]]
