from typing import Dict, Any, Optional
from pydantic import BaseModel
from datetime import datetime, timezone
import uuid

from backend.app.modules.trust_plane.audit import AuditLogger

class StealthPauseRequest(BaseModel):
    user_id: str
    trigger_method: str # "duress_pin", "safe_phrase", "emergency_toggle"
    duress_pin: Optional[str] = None
    safe_phrase_detected: Optional[str] = None

class StealthPauseStatus(BaseModel):
    user_id: str
    stealth_paused: bool
    paused_at: Optional[datetime]
    safety_ops_alert_id: Optional[str]

class StealthPauseService:
    """
    Coercion & Elder Abuse Defense:
    Silently freezes data sharing with contacts while serving benign empty status,
    and alerts the Safety Operations queue without tipping off the coercive actor.
    """
    _status_db: Dict[str, Dict[str, Any]] = {}
    _safety_ops_queue: list = []

    @classmethod
    async def activate_stealth_pause(cls, req: StealthPauseRequest) -> StealthPauseStatus:
        alert_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc)

        cls._status_db[req.user_id] = {
            "stealth_paused": True,
            "paused_at": now,
            "safety_ops_alert_id": alert_id,
            "trigger_method": req.trigger_method
        }

        # Queue silent alert for human safety operator
        cls._safety_ops_queue.append({
            "alert_id": alert_id,
            "user_id": req.user_id,
            "priority": "HIGH",
            "trigger": req.trigger_method,
            "timestamp": now,
            "status": "awaiting_review"
        })

        await AuditLogger.log_event(
            subject_user_id=req.user_id,
            action="stealth_pause_activated",
            resource="coercion_defense",
            resource_id=alert_id,
            result="executed",
            metadata={"trigger": req.trigger_method}
        )

        return StealthPauseStatus(
            user_id=req.user_id,
            stealth_paused=True,
            paused_at=now,
            safety_ops_alert_id=alert_id
        )

    @classmethod
    def is_stealth_paused(cls, user_id: str) -> bool:
        record = cls._status_db.get(user_id)
        return record.get("stealth_paused", False) if record else False

    @classmethod
    def get_contact_view_status(cls, user_id: str) -> Dict[str, Any]:
        """
        When a contact requests user status or reports:
        If stealth paused, returns a benign normal status with sensitive details withheld!
        """
        if cls.is_stealth_paused(user_id):
            return {
                "user_id": user_id,
                "status": "normal",
                "summary": "User is having a peaceful, quiet day.",
                "details_withheld": True
            }
        return {
            "user_id": user_id,
            "status": "active",
            "summary": "Routine check-in normal.",
            "details_withheld": False
        }
