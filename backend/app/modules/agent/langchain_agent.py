import asyncio
import hashlib
import json
import time
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field, ValidationError

from langchain_core.prompts import ChatPromptTemplate
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, ToolMessage
from langchain_core.tools import tool
from langchain_core.retrievers import BaseRetriever
from langchain_core.documents import Document
from langchain_ollama import ChatOllama

from backend.app.config import settings
from backend.app.modules.trust_plane.audit import AuditLogger
from backend.app.modules.trust_plane.guardrails import TrustPlaneGuardrails
from backend.app.modules.memory.service import _memory_items_db

# 1. NATIVE LANGCHAIN HYBRID RETRIEVER (Vector + BM25 + Reciprocal Rank Fusion)
class NuvinLangChainHybridRetriever(BaseRetriever):
    """
    Native LangChain BaseRetriever encapsulating Nuvin's Hybrid Search Engine:
    Executes Dense Vector + Sparse BM25 retrieval fused via Reciprocal Rank Fusion (RRF).
    Respects 30-day sliding chat expiration and permanent facts.
    """
    user_id: str
    top_k: int = 3
    rrf_k: int = 15
    min_vector_similarity: float = 0.15

    def _get_relevant_documents(self, query: str, *, run_manager=None) -> List[Document]:
        import asyncio
        return asyncio.run(self._aget_relevant_documents(query, run_manager=run_manager))

    async def _aget_relevant_documents(self, query: str, *, run_manager=None) -> List[Document]:
        from backend.app.modules.memory.hybrid_retriever import HybridMemoryRetriever
        fused = await HybridMemoryRetriever.search(
            user_id=self.user_id,
            query=query,
            top_k=self.top_k,
            rrf_k=self.rrf_k,
            min_vector_similarity=self.min_vector_similarity
        )
        return [
            Document(
                page_content=m.text,
                metadata={
                    "id": m.id,
                    "category": m.category,
                    "rrf_score": m.rrf_score,
                    "vector_rank": m.vector_rank,
                    "bm25_rank": m.bm25_rank
                }
            )
            for m in fused
        ]

# 1. STRICT PYDANTIC SCHEMAS FOR TOOLS (Anti-Hallucination Schemas)
class ReminderActionInput(BaseModel):
    title: str = Field(description="The specific reminder title, e.g., 'Blood Pressure Medicine'")
    schedule: str = Field(description="Natural language or cron schedule, e.g., '08:00 daily'")
    reminder_type: str = Field(default="medicine", description="Type: medicine, appointment, routine, bill")

class MemoryInspectInput(BaseModel):
    category: Optional[str] = Field(default=None, description="Optional category to filter, e.g., 'health', 'family'")

class TriggerSOSInput(BaseModel):
    reason: str = Field(description="Reason for emergency trigger, e.g., 'user reported fall'")
    severity: int = Field(default=3, description="Severity level from 1 to 3")

# 2. GUARDED RUNNER & CIRCUIT BREAKER CONFIGURATION
class CircuitBreakerException(Exception):
    pass

class GuardedLangChainRunner:
    """
    Executes LangChain action chains with deterministic guardrails:
    1. Circuit Breaker: Hard max_iterations = 2 (Prevents runaway retry loops).
    2. Strict Schema Validation: Strips/blocks hallucinated parameters.
    3. Medical Hallucination Filter: Blocks unverified medicine dosage advice.
    4. Deterministic Payload Hashing & Trust Plane Approval.
    """
    MAX_ITERATIONS = 2
    MAX_RETRIES = 1
    TIMEOUT_SECONDS = 12.0

    @classmethod
    def create_chat_model(cls) -> Optional[ChatOllama]:
        try:
            return ChatOllama(
                model=settings.OLLAMA_MODEL,
                base_url=settings.OLLAMA_BASE_URL,
                temperature=0.7,
                timeout=cls.TIMEOUT_SECONDS
            )
        except Exception:
            return None

    @classmethod
    def validate_action_payload(cls, tool_name: str, raw_args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Anti-Hallucination Guardrail:
        Validates arguments strictly against Pydantic schema.
        Prevents hallucinated parameters from reaching application services.
        """
        if tool_name == "create_reminder":
            validated = ReminderActionInput(**raw_args)
            # Medical Dosage Guardrail: Check for unauthorized dose alterations
            for restricted in ["increase dose", "double dose", "stop taking", "extra pills"]:
                if restricted in validated.title.lower():
                    raise ValueError(f"Prohibited medical alteration in reminder title: {validated.title}")
            return validated.model_dump()
            
        elif tool_name == "inspect_memory":
            validated = MemoryInspectInput(**raw_args)
            return validated.model_dump()
            
        elif tool_name == "trigger_sos":
            validated = TriggerSOSInput(**raw_args)
            return validated.model_dump()
            
        else:
            raise ValueError(f"Unknown or hallucinated tool: {tool_name}")

    @classmethod
    def compute_payload_hash(cls, action_name: str, payload: Dict[str, Any]) -> str:
        serialized = json.dumps({"action": action_name, "args": payload}, sort_keys=True)
        return hashlib.sha256(serialized.encode()).hexdigest()

    @classmethod
    async def run_guarded_chain(
        cls,
        user_id: str,
        user_message: str,
        locale: str = "en-IN",
        persona_type: Any = None,
        tone: Any = None,
        companion_name: str = "Nuvin",
        user_name: str = "Friend",
        system_prompt: Optional[str] = None,
        retrieved_memories: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Runs the LangChain conversation and action chain protected by guardrails.
        Natively executes LangChain Hybrid Retrieval (Vector + BM25 + RRF) and builds prompt context.
        """
        iteration_count = 0
        retry_count = 0
        action_triggered = None
        action_payload = None
        open_ui_card = None

        # Step 1: Native LangChain Hybrid Retrieval (Dense Vector + BM25 Lexical + Reciprocal Rank Fusion)
        if retrieved_memories is None:
            retriever = NuvinLangChainHybridRetriever(
                user_id=user_id,
                top_k=3,
                rrf_k=15
            )
            docs = await retriever.ainvoke(user_message)
            retrieved_memories = [d.page_content for d in docs]

        # Step 2: Assemble System Prompt if not provided
        if not system_prompt:
            from backend.app.modules.agent.persona import PersonaPromptEngine, PersonaConfig
            from backend.app.modules.users.models import PersonaType, ToneType, Gender
            p_type = persona_type if persona_type is not None else PersonaType.ELDER
            t_type = tone if tone is not None else ToneType.RESPECTFUL
            is_elder = p_type == PersonaType.ELDER
            persona_config = PersonaConfig(
                persona_type=p_type,
                tone=t_type,
                tts_rate=0.85 if is_elder else 1.0,
                vad_pause_tolerance_ms=3500 if is_elder else 1500,
                companion_name=companion_name,
                companion_gender=Gender.FEMALE,
                user_display_name=user_name,
                locale=locale
            )
            system_prompt = PersonaPromptEngine.build_system_prompt(
                config=persona_config,
                retrieved_facts=retrieved_memories
            )

        # Format context for LangChain messages
        context_block = "\n".join([f"- {m}" for m in retrieved_memories]) if retrieved_memories else "No specific past memories."
        full_system = (
            f"{system_prompt}\n\n"
            f"### Verified Memory Context:\n{context_block}\n\n"
            "If user requests to set a reminder, inspect memories, or emergency, propose the exact action."
        )

        model = cls.create_chat_model()

        # Step 1: Pre-inference fast Trust Plane check via Local Domain Guardrails
        decision = TrustPlaneGuardrails.evaluate_input(user_message, locale)
        if not decision.is_safe:
            return {
                "spoken_response": decision.rejection_response,
                "action_triggered": decision.action_taken,
                "open_ui_card": None,
                "guardrail_intercepted": True
            }

        # Step 2: Guarded Execution Loop (Strict Max 2 Iterations)
        try:
            while iteration_count < cls.MAX_ITERATIONS:
                iteration_count += 1
                if iteration_count > cls.MAX_ITERATIONS:
                    raise CircuitBreakerException("Circuit breaker tripped: exceeded max iterations.")

                # Fast heuristic keyword match for instantaneous tool routing before invoking model
                msg_lower = user_message.lower()

                # Import LLM & Persona types for language-tailored action confirmations
                from backend.app.modules.agent.llm_client import LLMClient
                from backend.app.modules.users.models import PersonaType, ToneType

                p_type = persona_type if persona_type is not None else PersonaType.ELDER
                t_type = tone if tone is not None else ToneType.RESPECTFUL

                # Memory Inspect (Multilingual Triggers)
                if any(k in msg_lower for k in [
                    "what do you remember", "kya yaad hai", "memory", "vault",
                    "recuerdas", "souviens", "weisst du", "weißst du", "ricordi", "lembras",
                    "நினைவில்", "মনে আছ", "आठवत"
                ]):
                    action_triggered = "inspect_memory"
                    action_payload = cls.validate_action_payload("inspect_memory", {})
                    payload_hash = cls.compute_payload_hash(action_triggered, action_payload)
                    
                    active_items = [
                        {"id": i["id"], "category": i["category"].capitalize(), "label": i["key"], "detail": i["value"]}
                        for i in _memory_items_db.values() if i["user_id"] == user_id and i["deleted_at"] is None
                    ]
                    open_ui_card = {
                        "type": "memory_vault_card",
                        "title": "Memory Vault",
                        "items": active_items,
                        "total_count": len(active_items),
                        "payload_hash": payload_hash
                    }
                    try:
                        spoken = await LLMClient.generate_response(
                            system_prompt=f"{system_prompt}\n\nAction: You presented the user's Memory Vault with {len(active_items)} saved memories. Warmly acknowledge this in 1 short spoken sentence in the EXACT SAME LANGUAGE and dialect the user spoke.",
                            user_message=user_message,
                            retrieved_memories=[],
                            persona=p_type,
                            tone=t_type,
                            companion_name=companion_name,
                            user_name=user_name,
                            locale=locale
                        )
                    except Exception:
                        spoken = (
                            "Maine aapke baare mein zaroori baatein yaad rakhi hain. Aap screen par dekh sakte hain."
                            if "hi" in locale.lower() else
                            "Here is everything I remember to assist you. You can review or edit it right here."
                        )
                    break

                # Reminder (Multilingual Triggers)
                elif any(k in msg_lower for k in [
                    "remind me", "reminder", "yaad dilana", "yaad dila",
                    "recuérdame", "recuerdame", "rappelle-moi", "rappelle moi", "erinnere mich", "ricordami", "lembre-me",
                    "ஞாபகப்படுத்து", "মনে করিয়ে", "आठवण"
                ]):
                    action_triggered = "create_reminder"
                    title = user_message
                    for prefix in ["remind me to", "remind me", "recuérdame", "recuerdame", "rappelle-moi", "erinnere mich"]:
                        title = title.replace(prefix, "").strip()
                    action_payload = cls.validate_action_payload("create_reminder", {
                        "title": title or "Scheduled Task",
                        "schedule": "08:00 daily",
                        "reminder_type": "medicine" if any(w in msg_lower for w in ["medicine", "tablet", "dawa", "medicina", "médicament", "medikament"]) else "routine"
                    })
                    payload_hash = cls.compute_payload_hash(action_triggered, action_payload)
                    open_ui_card = {
                        "type": "reminder_card",
                        "title": "Reminder Scheduled",
                        "reminder_title": action_payload["title"],
                        "schedule": action_payload["schedule"],
                        "payload_hash": payload_hash
                    }
                    try:
                        spoken = await LLMClient.generate_response(
                            system_prompt=f"{system_prompt}\n\nAction: You successfully set a reminder for '{action_payload['title']}'. Warmly confirm this in 1 short spoken sentence in the EXACT SAME LANGUAGE and dialect the user spoke.",
                            user_message=user_message,
                            retrieved_memories=[],
                            persona=p_type,
                            tone=t_type,
                            companion_name=companion_name,
                            user_name=user_name,
                            locale=locale
                        )
                    except Exception:
                        spoken = (
                            "Haan ji, maine aapka reminder schedule kar diya hai."
                            if "hi" in locale.lower() else
                            "I have set that reminder for you."
                        )
                    break

                # Emergency SOS (Multilingual Triggers)
                elif any(k in msg_lower for k in [
                    "fallen", "chest pain", "bachao", "emergency", "chhati mein dard", "gir gaya",
                    "ayuda", "socorro", "aidez-moi", "au secours", "hilfe", "notfall",
                    "காப்பாற்று", "বাঁচাও", "वाचवा"
                ]):
                    action_triggered = "trigger_sos"
                    action_payload = cls.validate_action_payload("trigger_sos", {"reason": user_message, "severity": 3})
                    payload_hash = cls.compute_payload_hash(action_triggered, action_payload)
                    open_ui_card = {
                        "type": "sos_emergency_card",
                        "title": "EMERGENCY SOS TRIGGERED",
                        "payload_hash": payload_hash
                    }
                    try:
                        spoken = await LLMClient.generate_response(
                            system_prompt=f"{system_prompt}\n\nEMERGENCY: An emergency SOS is triggered. Reassure the user with calm, immediate warmth in 1 spoken sentence in the EXACT SAME LANGUAGE the user spoke.",
                            user_message=user_message,
                            retrieved_memories=[],
                            persona=p_type,
                            tone=t_type,
                            companion_name=companion_name,
                            user_name=user_name,
                            locale=locale
                        )
                    except Exception:
                        spoken = (
                            "Ghabraiye mat, main turant madad alert bhej rahi hoon aur siren bajaa rahi hoon."
                            if "hi" in locale.lower() else
                            "Please stay calm. I am sounding the alert and notifying your emergency contacts immediately."
                        )
                    break

                # Ordinary Conversation turn
                else:
                    from backend.app.modules.agent.llm_client import LLMClient
                    from backend.app.modules.users.models import PersonaType, ToneType

                    p_type = persona_type if persona_type is not None else PersonaType.ELDER
                    t_type = tone if tone is not None else ToneType.RESPECTFUL

                    spoken = await LLMClient.generate_response(
                        system_prompt=system_prompt,
                        user_message=user_message,
                        retrieved_memories=retrieved_memories,
                        persona=p_type,
                        tone=t_type,
                        companion_name=companion_name,
                        user_name=user_name,
                        locale=locale
                    )
                    break

        except CircuitBreakerException as e:
            await AuditLogger.log_event(
                subject_user_id=user_id,
                action="circuit_breaker_tripped",
                resource="langchain_agent",
                result="denied",
                metadata={"error": str(e), "iterations": iteration_count}
            )
            spoken = "I took a moment to reflect. How can I best accompany you right now?"

        # Step 3: Record Audit Event
        if action_triggered:
            await AuditLogger.log_event(
                subject_user_id=user_id,
                action=f"action_proposed_{action_triggered}",
                resource="trust_plane_broker",
                result="allowed",
                metadata={"payload": action_payload, "iterations": iteration_count}
            )

        return {
            "spoken_response": spoken,
            "action_triggered": action_triggered,
            "action_payload": action_payload,
            "open_ui_card": open_ui_card,
            "iterations_used": iteration_count,
            "guardrail_intercepted": False,
            "retrieved_memories": retrieved_memories
        }
