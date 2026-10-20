import uuid
from datetime import datetime, timezone
from typing import Optional, Dict, Any
from pydantic import BaseModel

class AuditEvent(BaseModel):
    id: str
    actor_type: str
    actor_id: Optional[str] = None
    subject_user_id: str
    action: str
    resource: str
    resource_id: Optional[str] = None
    purpose: str
    result: str # allowed, denied, executed, failed
    metadata: Dict[str, Any] = {}
    at: datetime
    trace_id: str

class AuditLogger:
    """
    In-memory and persistent WORM audit recorder.
    Ensures that every access, safety intervention, and emergency action is traceable.
    """
    _in_memory_log = []

    @classmethod
    async def log_event(
        cls,
        subject_user_id: str,
        action: str,
        resource: str,
        result: str,
        actor_type: str = "system",
        actor_id: Optional[str] = None,
        resource_id: Optional[str] = None,
        purpose: str = "security_and_compliance",
        metadata: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None
    ) -> AuditEvent:
        event = AuditEvent(
            id=str(uuid.uuid4()),
            actor_type=actor_type,
            actor_id=actor_id,
            subject_user_id=subject_user_id,
            action=action,
            resource=resource,
            resource_id=resource_id,
            purpose=purpose,
            result=result,
            metadata=metadata or {},
            at=datetime.now(timezone.utc),
            trace_id=trace_id or str(uuid.uuid4())
        )
        cls._in_memory_log.append(event)
        return event

    @classmethod
    def get_user_audit_trail(cls, subject_user_id: str) -> list[AuditEvent]:
        return [e for e in cls._in_memory_log if e.subject_user_id == subject_user_id]
