from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any

from backend.app.config import settings
from backend.app.modules.trust_plane.guardrails import TrustPlaneGuardrails, GuardrailDecision
from backend.app.modules.trust_plane.audit import AuditLogger
from backend.app.modules.users.router import router as users_router
from backend.app.modules.memory.service import router as memory_router
from backend.app.modules.reminders.service import router as reminders_router
from backend.app.modules.sos.service import router as sos_router
from backend.app.modules.voice.router import router as voice_router

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Nuvin: A Trusted, Consent-First AI Companion & Assistant for Everyday Life"
)

# Enable CORS for Mobile Client & Admin Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Domain Routers
app.include_router(users_router, prefix=settings.API_V1_STR)
app.include_router(memory_router, prefix=settings.API_V1_STR)
app.include_router(reminders_router, prefix=settings.API_V1_STR)
app.include_router(sos_router, prefix=settings.API_V1_STR)
app.include_router(sos_router) # Also mount /sos/live directly for clean URLs
app.include_router(voice_router)

class GuardrailCheckRequest(BaseModel):
    user_id: Optional[str] = None
    text: str
    locale: str = "en-IN"

@app.post(f"{settings.API_V1_STR}/trust-plane/evaluate", response_model=GuardrailDecision)
async def evaluate_text_safety(req: GuardrailCheckRequest):
    """
    Sub-15ms deterministic Trust Plane evaluation.
    Blocks porn, self-harm, violence, scams, and illegal requests before reaching the LLM.
    """
    decision = await TrustPlaneGuardrails.evaluate_input_async(req.text, req.locale)
    
    if req.user_id and not decision.is_safe:
        await AuditLogger.log_event(
            subject_user_id=req.user_id,
            action=f"safety_violation_{decision.category.value}",
            resource="trust_plane",
            result="denied",
            metadata={
                "tier": decision.tier.value,
                "action_taken": decision.action_taken,
                "snippet": req.text[:100]
            }
        )
    return decision

@app.get(f"{settings.API_V1_STR}/trust-plane/audit/{{user_id}}")
async def get_user_audit_events(user_id: str):
    """
    Returns user-inspectable audit trail (Dignity over surveillance principle).
    """
    events = AuditLogger.get_user_audit_trail(user_id)
    return {"user_id": user_id, "total_events": len(events), "audit_trail": events}

from backend.app.modules.trust_plane.stealth_pause import (
    StealthPauseService, StealthPauseRequest, StealthPauseStatus
)

@app.post(f"{settings.API_V1_STR}/trust-plane/stealth-pause", response_model=StealthPauseStatus)
async def activate_stealth_pause_coercion_defense(req: StealthPauseRequest):
    """
    Triggers stealth pause: withholds sensitive updates from contacts,
    serves benign status, and alerts safety operations queue silently.
    """
    return await StealthPauseService.activate_stealth_pause(req)

@app.get(f"{settings.API_V1_STR}/trust-plane/stealth-pause/{{user_id}}/contact-view")
async def get_contact_view_for_user(user_id: str):
    """
    Returns data masked under stealth pause for potentially coercive contacts.
    """
    return StealthPauseService.get_contact_view_status(user_id)

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "trust_plane": "active"
    }

from fastapi.staticfiles import StaticFiles
import os

flutter_web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../mobile/build/web"))
if os.path.exists(flutter_web_dir):
    app.mount("/flutter", StaticFiles(directory=flutter_web_dir, html=True), name="flutter")

static_dir = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(static_dir):
    app.mount("/", StaticFiles(directory=static_dir, html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.app.main:app", host="0.0.0.0", port=8000, reload=True)
