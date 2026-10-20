from fastapi import APIRouter, HTTPException
from typing import Dict, List, Any, Optional
import uuid
from datetime import datetime, timezone
from backend.app.modules.reminders.models import (
    ReminderCreate, ReminderResponse, AcknowledgeOccurrence, ReminderType
)
from backend.app.modules.trust_plane.audit import AuditLogger

router = APIRouter(prefix="/reminders", tags=["Reminders Engine (Offline-First)"])

# In-memory storage for development / testing
_reminders_db: Dict[str, Dict[str, Any]] = {}
_occurrences_db: Dict[str, Dict[str, Any]] = {}

@router.post("/{user_id}", response_model=ReminderResponse)
async def create_reminder(user_id: str, payload: ReminderCreate):
    """
    Creates a new reminder (medicine, routine, bill, etc.).
    Validated deterministically and queued for device sync.
    """
    reminder_id = str(uuid.uuid4())
    record = {
        "id": reminder_id,
        "user_id": user_id,
        "type": payload.type,
        "title": payload.title,
        "details": payload.details,
        "schedule": payload.schedule,
        "is_recurring": payload.is_recurring,
        "timezone": payload.timezone,
        "status": "active",
        "next_fire_at": datetime.now(timezone.utc),
        "source": payload.source,
        "created_at": datetime.now(timezone.utc)
    }
    _reminders_db[reminder_id] = record

    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="reminder_created",
        resource="reminders",
        resource_id=reminder_id,
        result="executed",
        metadata={"type": payload.type.value, "title": payload.title, "schedule": payload.schedule}
    )

    return ReminderResponse(**record)

@router.get("/{user_id}", response_model=List[ReminderResponse])
async def list_user_reminders(user_id: str, active_only: bool = True):
    results = [
        r for r in _reminders_db.values()
        if r["user_id"] == user_id and (not active_only or r["status"] == "active")
    ]
    return [ReminderResponse(**r) for r in results]

@router.get("/{user_id}/offline-sync-payload")
async def get_offline_sync_payload(user_id: str) -> Dict[str, Any]:
    """
    Returns complete local scheduling manifest for the mobile app SQLite DB.
    Allows the mobile app to function with 100% offline alarm fidelity.
    """
    user_reminders = [
        r for r in _reminders_db.values()
        if r["user_id"] == user_id and r["status"] == "active"
    ]
    
    return {
        "user_id": user_id,
        "sync_timestamp": datetime.now(timezone.utc).isoformat(),
        "total_active_reminders": len(user_reminders),
        "reminders": user_reminders,
        "actions_supported": ["taken", "snooze", "skip", "help"],
        "default_snooze_minutes": 15
    }

@router.post("/{user_id}/occurrences/ack")
async def acknowledge_reminder_occurrence(user_id: str, ack: AcknowledgeOccurrence):
    """
    Records Taken, Snooze, Skip, or Help response from voice or OpenUI card.
    """
    occ_id = ack.occurrence_id
    _occurrences_db[occ_id] = {
        "id": occ_id,
        "reminder_id": ack.reminder_id,
        "user_id": user_id,
        "action": ack.action.value,
        "snooze_minutes": ack.snooze_minutes,
        "client_timestamp": ack.client_timestamp,
        "acknowledged_at": datetime.now(timezone.utc)
    }

    await AuditLogger.log_event(
        subject_user_id=user_id,
        action=f"reminder_{ack.action.value}",
        resource="reminder_occurrences",
        resource_id=occ_id,
        result="executed",
        metadata={"reminder_id": ack.reminder_id}
    )

    return {
        "status": "success",
        "action_recorded": ack.action.value,
        "reminder_id": ack.reminder_id
    }
