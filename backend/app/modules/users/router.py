from fastapi import APIRouter, HTTPException, Depends
from typing import Dict, Any, List
import uuid
from datetime import datetime, timezone
from backend.app.modules.users.models import (
    UserProfileCreate, UserProfileResponse, PersonaType, AgeBand, ToneType, Gender
)
from backend.app.modules.trust_plane.audit import AuditLogger

router = APIRouter(prefix="/users", tags=["Users & Companion Profiles"])

# Pre-populated dummy accounts for immediate dev & testing usage
_contacts_db: Dict[str, List[Dict[str, Any]]] = {
    "asha_sharma": [
        {
            "id": "c-aarav",
            "display_name": "Aarav Sharma (Son)",
            "spoken_disambiguation": "Mera beta Aarav",
            "relationship": "Kin",
            "phone_e164": "+919876543211",
            "kind": "kin",
            "priority": 1
        },
        {
            "id": "c-mehta",
            "display_name": "Dr. Mehta (Cardiologist)",
            "spoken_disambiguation": "Doctor Mehta",
            "relationship": "Doctor",
            "phone_e164": "+919820012345",
            "kind": "doctor",
            "priority": 2
        }
    ],
    "rohan_mehta": [
        {
            "id": "c-priya",
            "display_name": "Priya (Partner)",
            "spoken_disambiguation": "Priya",
            "relationship": "Kin",
            "phone_e164": "+919811122234",
            "kind": "kin",
            "priority": 1
        }
    ]
}

_users_db: Dict[str, Dict[str, Any]] = {
    "asha_sharma": {
        "id": "asha_sharma",
        "phone_e164": "+919876543210",
        "display_name": "Asha Sharma",
        "persona": PersonaType.ELDER,
        "age_band": AgeBand.BAND_55_64,
        "gender": Gender.FEMALE,
        "companion_name": "Nuvin",
        "companion_gender": Gender.FEMALE,
        "preferred_tone": ToneType.RESPECTFUL,
        "locale": "hi-IN",
        "timezone": "Asia/Kolkata",
        "wake_word_phrase": "Hey Nuvin",
        "custom_wake_word_enrolled": True,
        "status": "active",
        "emergency_contacts": _contacts_db["asha_sharma"],
        "created_at": datetime.now(timezone.utc)
    },
    "rohan_mehta": {
        "id": "rohan_mehta",
        "phone_e164": "+919811122233",
        "display_name": "Rohan Mehta",
        "persona": PersonaType.EAR,
        "age_band": AgeBand.BAND_18_34,
        "gender": Gender.MALE,
        "companion_name": "Saathi",
        "companion_gender": Gender.FEMALE,
        "preferred_tone": ToneType.FRIENDLY,
        "locale": "en-IN",
        "timezone": "Asia/Kolkata",
        "wake_word_phrase": "Hey Saathi",
        "custom_wake_word_enrolled": True,
        "status": "active",
        "emergency_contacts": _contacts_db["rohan_mehta"],
        "created_at": datetime.now(timezone.utc)
    }
}

@router.post("/onboard", response_model=UserProfileResponse)
async def onboard_user(payload: UserProfileCreate):
    """
    Onboards a user with automatic persona determination (55+ vs 20-50),
    companion name assignment, gender-matching defaults, and wake-word generation.
    """
    user_id = str(uuid.uuid4())
    
    # 1. Determine Persona based on Age Band
    is_elder = payload.age_band in [AgeBand.BAND_55_64, AgeBand.BAND_65_74, AgeBand.BAND_75_PLUS]
    persona = PersonaType.ELDER if is_elder else PersonaType.EAR
    
    # 2. Derive Tone Default (respectful for 55+, friendly for 20-50)
    if payload.preferred_tone is not None:
        tone = payload.preferred_tone
    else:
        tone = ToneType.RESPECTFUL if is_elder else ToneType.FRIENDLY
        
    # 3. Derive Companion Gender Default (matches user gender if known, else female)
    if payload.companion_gender is not None:
        comp_gender = payload.companion_gender
    else:
        comp_gender = payload.gender if payload.gender in [Gender.FEMALE, Gender.MALE] else Gender.FEMALE
        
    # 4. Companion Name & Wake Word
    companion_name = payload.companion_name.strip() if payload.companion_name else "Nuvin"
    wake_word = f"Hey {companion_name}"

    # 5. Format Emergency Contacts
    contacts_list = []
    for c in payload.emergency_contacts:
        contact_id = str(uuid.uuid4())
        contact_record = {
            "id": contact_id,
            "display_name": c.display_name,
            "spoken_disambiguation": c.spoken_disambiguation,
            "relationship": c.relationship,
            "phone_e164": c.phone_e164,
            "kind": c.kind,
            "priority": c.priority
        }
        contacts_list.append(contact_record)
        
    _contacts_db[user_id] = contacts_list

    user_record = {
        "id": user_id,
        "phone_e164": payload.phone_e164,
        "display_name": payload.display_name,
        "persona": persona,
        "age_band": payload.age_band,
        "gender": payload.gender,
        "companion_name": companion_name,
        "companion_gender": comp_gender,
        "preferred_tone": tone,
        "locale": payload.locale,
        "timezone": payload.timezone,
        "wake_word_phrase": wake_word,
        "custom_wake_word_enrolled": False,
        "status": "active",
        "emergency_contacts": contacts_list,
        "created_at": datetime.now(timezone.utc)
    }
    _users_db[user_id] = user_record

    # Log audit event
    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="user_onboarded",
        resource="users",
        resource_id=user_id,
        result="executed",
        metadata={"persona": persona.value, "companion_name": companion_name, "tone": tone.value}
    )

    return UserProfileResponse(**user_record)

@router.get("/{user_id}", response_model=UserProfileResponse)
async def get_user_profile(user_id: str):
    user = _users_db.get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user["emergency_contacts"] = _contacts_db.get(user_id, [])
    return UserProfileResponse(**user)

@router.patch("/{user_id}/companion-name")
async def update_companion_name(user_id: str, new_name: str):
    user = _users_db.get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    clean_name = new_name.strip()
    user["companion_name"] = clean_name
    user["wake_word_phrase"] = f"Hey {clean_name}"
    
    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="update_companion_name",
        resource="users",
        resource_id=user_id,
        result="executed",
        metadata={"new_name": clean_name}
    )
    return {"message": "Companion name updated successfully", "companion_name": clean_name, "wake_word_phrase": user["wake_word_phrase"]}

from backend.app.modules.users.wakeword import WakeWordService, VoiceEnrollmentRequest, VoiceEnrollmentResponse

@router.post("/{user_id}/enroll-wakeword", response_model=VoiceEnrollmentResponse)
async def enroll_wakeword(user_id: str, req: VoiceEnrollmentRequest):
    """
    Enrolls custom wake word ('Hey <CompanionName>') with 3 user voice samples
    so that Nuvin wakes up only to the enrolled user's voice.
    """
    if req.user_id != user_id:
        req.user_id = user_id
    try:
        return await WakeWordService.enroll_user_voiceprint(req)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
