import asyncio
import uuid
import re
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List
from pydantic import BaseModel

from backend.app.modules.trust_plane.guardrails import TrustPlaneGuardrails, GuardrailDecision
from backend.app.modules.trust_plane.audit import AuditLogger
from backend.app.modules.users.router import _users_db
from backend.app.modules.users.models import PersonaType, ToneType, Gender
from backend.app.modules.agent.persona import PersonaPromptEngine, PersonaConfig
from backend.app.modules.memory.service import _memory_items_db, _life_threads_db

class AgentTurnRequest(BaseModel):
    user_id: str
    message: str
    locale: Optional[str] = None # Defaults to user's saved locale
    channel: str = "chat" # "chat" or "voice"

class AgentTurnResponse(BaseModel):
    session_id: str
    spoken_response: str
    reply: Optional[str] = None
    response: Optional[str] = None
    open_ui_card: Optional[Dict[str, Any]] = None
    action_triggered: Optional[str] = None
    action_payload: Optional[Dict[str, Any]] = None
    tts_rate: float
    vad_pause_tolerance_ms: int
    guardrail_decision: GuardrailDecision

    def __init__(self, **data):
        if "spoken_response" in data:
            data.setdefault("reply", data["spoken_response"])
            data.setdefault("response", data["spoken_response"])
        super().__init__(**data)

class AgentOrchestrator:
    """
    Coordinates real-time conversation turns:
    Trust Plane Safety -> Memory Context Injection -> Persona Prompting -> Tool Execution -> OpenUI Generation.
    """

    @classmethod
    async def process_turn(cls, req: AgentTurnRequest) -> AgentTurnResponse:
        session_id = str(uuid.uuid4())
        user = _users_db.get(req.user_id)
        
        # Default profile if not yet onboarded
        if not user:
            user = {
                "id": req.user_id,
                "display_name": "Friend",
                "persona": PersonaType.ELDER,
                "age_band": "65-74",
                "companion_name": "Nuvin",
                "companion_gender": Gender.FEMALE,
                "preferred_tone": ToneType.RESPECTFUL,
                "locale": req.locale or "en-IN",
                "timezone": "Asia/Kolkata"
            }

        locale = req.locale or user.get("locale", "en-IN")
        companion_name = user.get("companion_name", "Nuvin")
        persona_type = user.get("persona", PersonaType.ELDER)
        tone = user.get("preferred_tone", ToneType.RESPECTFUL)
        is_elder = persona_type == PersonaType.ELDER
        is_hindi = "hi" in locale.lower()

        # STEP 1 (OUTSIDE LANGCHAIN): Fast Local Ingress Check for RED-Line Violations (<0.02ms)
        local_decision = TrustPlaneGuardrails.evaluate_input(req.message, locale=locale)
        if not local_decision.is_safe:
            # 🛑 Hard Block Immediately: 0ms network delay, 0 tokens sent to LLM
            await AuditLogger.log_event(
                subject_user_id=req.user_id,
                action=f"safety_intercept_{local_decision.category.value}",
                resource="agent_turn",
                result="denied",
                metadata={"category": local_decision.category.value, "tier": local_decision.tier.value}
            )
            return AgentTurnResponse(
                session_id=session_id,
                spoken_response=local_decision.rejection_response,
                open_ui_card=None,
                action_triggered=local_decision.action_taken,
                action_payload={"show_helpline": local_decision.show_helpline, "helplines": local_decision.helpline_info},
                tts_rate=0.85 if is_elder else 1.0,
                vad_pause_tolerance_ms=3500 if is_elder else 1500,
                guardrail_decision=local_decision
            )

        # STEP 2: Parallel Concurrency for Yellow & Green Traffic
        # Concurrently launches:
        # A) Cloud Moderation API (OpenAI omni-moderation-latest)
        # B) Guarded LangChain Agent (Hybrid Retrieval + Persona Prompting + Gemini generation)
        from backend.app.modules.agent.langchain_agent import GuardedLangChainRunner

        moderation_task = asyncio.create_task(
            TrustPlaneGuardrails.evaluate_with_openai_moderation(req.message, locale=locale)
        )
        agent_task = asyncio.create_task(
            GuardedLangChainRunner.run_guarded_chain(
                user_id=req.user_id,
                user_message=req.message,
                locale=locale,
                persona_type=persona_type,
                tone=tone,
                companion_name=companion_name,
                user_name=user.get("display_name", "Friend")
            )
        )

        # Both tasks run concurrently — OpenAI network roundtrip is absorbed in parallel with LLM generation!
        remote_decision, chain_result = await asyncio.gather(moderation_task, agent_task)

        # If Cloud Moderation detected a violation, intercept output before publishing to user
        if remote_decision is not None and not remote_decision.is_safe:
            await AuditLogger.log_event(
                subject_user_id=req.user_id,
                action=f"safety_intercept_remote_{remote_decision.category.value}",
                resource="agent_turn",
                result="denied",
                metadata={"category": remote_decision.category.value, "tier": remote_decision.tier.value}
            )
            return AgentTurnResponse(
                session_id=session_id,
                spoken_response=remote_decision.rejection_response,
                open_ui_card=None,
                action_triggered=remote_decision.action_taken,
                action_payload={"show_helpline": remote_decision.show_helpline, "helplines": remote_decision.helpline_info},
                tts_rate=0.85 if is_elder else 1.0,
                vad_pause_tolerance_ms=3500 if is_elder else 1500,
                guardrail_decision=remote_decision
            )

        spoken = chain_result["spoken_response"]
        action_triggered = chain_result.get("action_triggered")
        action_payload = chain_result.get("action_payload")
        open_ui_card = chain_result.get("open_ui_card")
        decision = local_decision

        # 4. Immediate Buffer + Asynchronous Background Memory Categorization (Zero Latency Delay)
        from backend.app.modules.memory.vector_store import VectorMemoryStore
        VectorMemoryStore.record_immediate_turn(
            user_id=req.user_id,
            turn_text=f"User said: {req.message}. Agent replied: {spoken}",
            channel=getattr(req, "channel", "chat")
        )

        from backend.app.modules.memory.categorizer import MemoryCategorizationPipeline
        asyncio.create_task(
            MemoryCategorizationPipeline.categorize_and_index_turn(
                user_id=req.user_id,
                user_message=req.message,
                agent_response=spoken,
                session_id=session_id,
                channel=getattr(req, "channel", "chat"),
                locale=locale
            )
        )

        pacing = PersonaPromptEngine.get_pacing_config(persona_type)
        return AgentTurnResponse(
            session_id=session_id,
            spoken_response=spoken,
            open_ui_card=open_ui_card,
            action_triggered=action_triggered,
            action_payload=action_payload,
            tts_rate=pacing["tts_rate"],
            vad_pause_tolerance_ms=pacing["vad_pause_tolerance_ms"],
            guardrail_decision=decision
        )
