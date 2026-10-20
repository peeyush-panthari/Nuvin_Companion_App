import re
import json
import logging
import asyncio
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

from backend.app.modules.memory.vector_store import VectorMemoryStore, VectorMemoryCategory
from backend.app.modules.memory.service import _memory_items_db
from backend.app.config import settings

logger = logging.getLogger(__name__)

class MemoryCategorizationPipeline:
    """
    Background Asynchronous Categorization Pipeline for Nuvin:
    Executes AFTER the LLM has already responded to the user (zero latency impact).
    
    Partitions context into 3 distinct vector database categories:
    1. CHAT_HISTORY: Full turn conversation (chats and voice chats). Saved for last 1 month (30-day retention).
    2. PERSONAL_INFO: Personal facts shared organically by user (e.g. brother's name, nephew's name,
       office address, favorite color, pet, occupation). Permanent (NO expiry).
    3. USER_DIRECTED: Facts/notes user specifically asked Nuvin to remember. Permanent (NO expiry).
    """

    # --- CATEGORY 3: EXPLICIT REMEMBRANCE PATTERNS ---
    _REMEMBER_PATTERNS = [
        # English
        r"(?:please\s+)?remember(?:\s+that)?\s+(.+)",
        r"(?:make\s+a\s+note(?:\s+that)?|note\s+down(?:\s+that)?)\s+(.+)",
        r"(?:don'?t\s+forget(?:\s+that)?)\s+(.+)",
        r"(?:keep\s+in\s+mind(?:\s+that)?)\s+(.+)",
        r"^(?:save|record)\s+(?:this:\s*)?(.+)",
        # Hindi / Hinglish
        r"(?:yaad\s+rakhna|yaad\s+rakho)(?:\s+ki)?\s+(.+)",
        r"(?:yeh\s+yaad\s+rakhna|yeh\s+bhoolna\s+mat)\s+(.+)",
        r"(?:note\s+kar\s+lo|note\s+karna)\s+(.+)",
        # Spanish
        r"(?:por\s+favor\s+)?recuerda(?:\s+que)?\s+(.+)",
        r"(?:no\s+olvides(?:\s+que)?)\s+(.+)",
        # French
        r"(?:s'il\s+te\s+pla[iî]t\s+)?(?:rappelle-toi|souviens-toi)(?:\s+que)?\s+(.+)",
        r"(?:n'oublie\s+pas(?:\s+que)?)\s+(.+)",
        # German
        r"(?:erinnere\s+dich(?:\s+daran)?|vergiss\s+nicht(?:\s+dass)?)\s+(.+)"
    ]

    # --- CATEGORY 2: PERSONAL INFORMATION DETERMINISTIC PATTERNS ---
    _FAMILY_PATTERNS = [
        # Brother, sister, nephew, niece, son, daughter, father, mother, spouse
        (r"\bmy\s+(brother|sister|nephew|niece|son|daughter|father|mother|dad|mom|wife|husband|grandson|granddaughter)(?:'s)?\s+(?:name\s+is\s+|is\s+named\s+|is\s+)([A-Z][a-zA-Z]+|\w+)", "family"),
        (r"\bmere?\s+(bhai|behen|bhatija|bhatiji|beta|beti|pita|maa|patni|pati)(?:\s+ka\s+naam)?\s+([A-Z][a-zA-Z]+|\w+)\s+hai", "family"),
        (r"\bmi\s+(hermano|hermana|sobrino|sobrina|hijo|hija|esposo|esposa)\s+se\s+llama\s+([A-Z][a-zA-Z]+|\w+)", "family"),
    ]

    _OFFICE_PATTERNS = [
        # Office address, workplace, company
        (r"\bmy\s+office\s+(?:address\s+)?(?:is\s+at\s+|is\s+in\s+|is\s+)([^\.\,\n]+)", "office_address"),
        (r"\bi\s+work\s+(?:at|for|in)\s+([^\.\,\n]+)", "workplace"),
        (r"\bmera\s+office\s+([^\.\,\n]+)\s+mein\s+hai", "office_address"),
    ]

    _PREFERENCE_PATTERNS = [
        # Favorite color, food, drink, hobby
        (r"\bmy\s+favou?rite\s+(color|colour|food|dish|sport|song|movie|book|drink)\s+is\s+([^\.\,\n]+)", "preference"),
        (r"\bmera\s+pasandida\s+(rang|khana|gaana)\s+([^\.\,\n]+)\s+hai", "preference"),
        (r"\bmi\s+(color|comida|música)\s+favorit[oa]\s+es\s+([^\.\,\n]+)", "preference"),
    ]

    _PET_PATTERNS = [
        # Pets
        (r"\bmy\s+(dog|cat|pet|puppy)(?:'s)?\s+(?:name\s+is\s+|is\s+named\s+|is\s+)([A-Z][a-zA-Z]+|\w+)", "pet"),
        (r"\bmere?\s+(kutta|billi|pet)(?:\s+ka\s+naam)?\s+([A-Z][a-zA-Z]+|\w+)\s+hai", "pet"),
    ]

    @classmethod
    async def categorize_and_index_turn(
        cls,
        user_id: str,
        user_message: str,
        agent_response: str,
        session_id: str,
        channel: str = "chat",
        locale: str = "en-IN"
    ):
        """
        Main background entrypoint:
        Executes without holding back the user's turn response.
        """
        try:
            # 1. CATEGORY 1: Save All Chats & Voice Turns with 30-Day (1 Month) Retention
            turn_text = f"User said: {user_message}. Agent replied: {agent_response}"
            chat_id = await VectorMemoryStore.add_memory(
                user_id=user_id,
                text=turn_text,
                category=VectorMemoryCategory.CHAT_HISTORY.value,
                metadata={
                    "session_id": session_id,
                    "channel": channel,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "retention": "30_days",
                    "user_message": user_message,
                    "agent_response": agent_response
                },
                ttl_days=30 # 1 Month Retention
            )
            logger.info("Category 1 (Chat History) indexed for user %s: id=%s (TTL: 30d)", user_id, chat_id)

            # 2. CATEGORY 3: Detect Explicit User-Directed Remembrances (NO EXPIRY)
            explicit_remembrances = cls.extract_explicit_remembrances(user_message)
            for item in explicit_remembrances:
                rem_id = await VectorMemoryStore.add_memory(
                    user_id=user_id,
                    text=f"User asked to remember: {item}",
                    category=VectorMemoryCategory.USER_DIRECTED.value,
                    metadata={
                        "source": "explicit_user_request",
                        "raw_query": user_message,
                        "session_id": session_id,
                        "retention": "permanent"
                    },
                    ttl_days=None # Permanent (No Expiry)
                )
                logger.info("Category 3 (User Directed) indexed for user %s: '%s' (Permanent)", user_id, item)
                cls._sync_to_vault(user_id=user_id, category="explicit", label="User Reminder", detail=item)

            # 3. CATEGORY 2: Extract Personal Information (NO EXPIRY)
            personal_facts = await cls.extract_personal_information(user_message, locale)
            for fact in personal_facts:
                # Deduplicate if already saved under explicit remembrances
                if any(fact.lower() in r.lower() for r in explicit_remembrances):
                    continue

                fact_id = await VectorMemoryStore.add_memory(
                    user_id=user_id,
                    text=fact,
                    category=VectorMemoryCategory.PERSONAL_INFO.value,
                    metadata={
                        "source": "personal_info_extraction",
                        "raw_query": user_message,
                        "session_id": session_id,
                        "retention": "permanent"
                    },
                    ttl_days=None # Permanent (No Expiry)
                )
                logger.info("Category 2 (Personal Info) indexed for user %s: '%s' (Permanent)", user_id, fact)
                cls._sync_to_vault(user_id=user_id, category="personal", label="Personal Detail", detail=fact)

        except Exception as e:
            logger.error("Error in background memory categorization: %s", e, exc_info=True)

    @classmethod
    def extract_explicit_remembrances(cls, message: str) -> List[str]:
        """
        Detects explicit instructions where the user asks the assistant to remember something.
        E.g., 'Please remember that my passport renewal is next March'
        """
        extracted = []
        msg_clean = message.strip()
        for pat in cls._REMEMBER_PATTERNS:
            match = re.search(pat, msg_clean, flags=re.IGNORECASE)
            if match:
                fact = match.group(1).strip(" .?!,")
                if len(fact) > 2 and fact not in extracted:
                    extracted.append(fact)
        return extracted

    @classmethod
    def _extract_heuristics_personal_info(cls, message: str) -> List[str]:
        """
        Fast deterministic heuristic patterns for immediate entity extraction
        (Family, Brother, Nephew, Office, Favorites, Pets).
        """
        facts: List[str] = []
        clean = message.strip()

        # Family & Relatives
        for pat, cat in cls._FAMILY_PATTERNS:
            m = re.search(pat, clean, flags=re.IGNORECASE)
            if m:
                relation, name = m.group(1), m.group(2)
                facts.append(f"User's {relation} is named {name.capitalize()}")

        # Office & Workplace
        for pat, cat in cls._OFFICE_PATTERNS:
            m = re.search(pat, clean, flags=re.IGNORECASE)
            if m:
                place = m.group(1).strip(" .?!,")
                facts.append(f"User's office / workplace is at {place}")

        # Preferences & Favorites
        for pat, cat in cls._PREFERENCE_PATTERNS:
            m = re.search(pat, clean, flags=re.IGNORECASE)
            if m:
                pref_item, pref_val = m.group(1), m.group(2).strip(" .?!,")
                facts.append(f"User's favorite {pref_item} is {pref_val}")

        # Pets
        for pat, cat in cls._PET_PATTERNS:
            m = re.search(pat, clean, flags=re.IGNORECASE)
            if m:
                pet_type, pet_name = m.group(1), m.group(2).strip(" .?!,")
                facts.append(f"User has a {pet_type} named {pet_name.capitalize()}")

        return facts

    @classmethod
    async def extract_personal_information(cls, message: str, locale: str = "en-IN") -> List[str]:
        """
        Extracts personal information using fast heuristics + LLM assistance in background.
        Examples: Brother name, nephew name, office address, favorite color, hobbies, relationships.
        """
        # 1. Deterministic heuristic extraction (sub-millisecond)
        heuristic_facts = cls._extract_heuristics_personal_info(message)
        if heuristic_facts:
            return heuristic_facts

        # 2. LLM-Assisted Background Extractor for complex or multilingual sentences
        # Checks if sentence conveys personal facts (brother, nephew, office, favorites, home, health condition)
        lower_msg = message.lower()
        personal_keywords = [
            "brother", "sister", "nephew", "niece", "son", "daughter", "wife", "husband",
            "father", "mother", "office", "work at", "favorite", "favourite", "color", "colour",
            "live in", "living in", "pet", "dog", "cat", "bhai", "behen", "bhatija", "office",
            "pasand", "hermano", "sobrino", "oficina", "frère", "neveu", "bruder", "neffe"
        ]

        if not any(k in lower_msg for k in personal_keywords):
            return []

        # If keyword exists, run fast structured extraction via Gemini in background
        gemini_key = settings.GEMINI_API_KEY
        if gemini_key:
            import httpx
            prompt = (
                "You are an accurate, privacy-respecting personal information extractor for a personal companion.\n"
                f"User Message: \"{message}\"\n\n"
                "Task: Did the user share any personal information about themselves, their family members (e.g. brother's name, nephew's name), "
                "office address, workplace, favorite color, pet, or personal preferences?\n"
                "- If YES: Output a JSON list of 1 to 3 concise declarative statements, e.g. [\"User's brother is named Amit\", \"User's office is in Cyber City\"].\n"
                "- If NO: Output exactly: []\n"
                "JSON Output:"
            )
            for model_name in [settings.GEMINI_FALLBACK_MODEL, "gemini-3.5-flash", "gemini-flash-lite-latest"]:
                try:
                    async with httpx.AsyncClient(timeout=8.0) as client:
                        resp = await client.post(
                            f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={gemini_key}",
                            json={
                                "contents": [{"parts": [{"text": prompt}]}],
                                "generationConfig": {"temperature": 0.1, "maxOutputTokens": 150}
                            }
                        )
                        if resp.status_code == 200:
                            data = resp.json()
                            raw_txt = data.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text", "")
                            # Parse JSON
                            cleaned_json = raw_txt.strip()
                            if "[" in cleaned_json and "]" in cleaned_json:
                                start = cleaned_json.find("[")
                                end = cleaned_json.rfind("]") + 1
                                parsed = json.loads(cleaned_json[start:end])
                                if isinstance(parsed, list):
                                    return [str(p) for p in parsed if isinstance(p, str) and len(p) > 3]
                            break
                except Exception as e:
                    logger.debug("Background LLM personal info extractor (%s) exception: %s", model_name, e)
                    continue

        return heuristic_facts

    @staticmethod
    def _sync_to_vault(user_id: str, category: str, label: str, detail: str):
        """
        Syncs extracted persistent memory into the user-inspectable Memory Vault (_memory_items_db).
        Fulfills Dignity Over Surveillance: user can inspect and delete at any time.
        """
        import uuid
        item_id = str(uuid.uuid4())
        _memory_items_db[item_id] = {
            "id": item_id,
            "user_id": user_id,
            "category": category,
            "key": label,
            "value": detail,
            "sensitivity": 1,
            "source_type": "conversation_extraction",
            "confidence": 1.0,
            "created_at": datetime.now(timezone.utc),
            "deleted_at": None
        }
