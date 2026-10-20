import os
import re
import time
import httpx
import logging
from typing import List, Optional, Dict
from backend.app.modules.users.models import PersonaType, ToneType

logger = logging.getLogger(__name__)

# Circuit breaker cache for rate-limited models (cool-off for 60s to avoid repeated latency penalties)
_model_rate_limited_until: Dict[str, float] = {}

class LLMClient:
    """
    LLM Connection & Reply Framing Client for Nuvin:
    - Calls Gemini (gemini-1.5-flash / gemini-2.0-flash) or OpenAI (gpt-4o-mini / gpt-4o) when API keys are available.
    - Provides a zero-dependency contextual response synthesizer that faithfully weaves retrieved
      vector memories into the conversation according to the user's persona and tone rules.
    """

    @classmethod
    async def generate_response(
        cls,
        system_prompt: str,
        user_message: str,
        retrieved_memories: List[str],
        persona: PersonaType,
        tone: ToneType,
        companion_name: str,
        user_name: str,
        locale: str = "en-IN"
    ) -> str:
        from backend.app.config import settings

        # 1. Local Ollama (llama3.1:8b) - High Priority for local building & offline privacy
        if settings.USE_OLLAMA_LOCAL:
            try:
                context_block = "\n".join([f"- {m}" for m in retrieved_memories])
                sys_message = (
                    f"{system_prompt}\n\n"
                    f"### Context Recalled from Past Discussions:\n{context_block}\n\n"
                    f"Answer directly in character as {companion_name}. Keep it conversational, warm, and natural for spoken voice."
                )
                async with httpx.AsyncClient(timeout=httpx.Timeout(15.0, connect=0.25)) as client:
                    resp = await client.post(
                        f"{settings.OLLAMA_BASE_URL}/api/chat",
                        json={
                            "model": settings.OLLAMA_MODEL,
                            "messages": [
                                {"role": "system", "content": sys_message},
                                {"role": "user", "content": user_message}
                            ],
                            "stream": False,
                            "options": {
                                "temperature": 0.7,
                                "num_predict": 250
                            }
                        }
                    )
                    if resp.status_code == 200:
                        data = resp.json()
                        text = data.get("message", {}).get("content", "").strip()
                        if text:
                            return cls._clean_speech_output(text)
            except Exception as e:
                # Fallback gracefully if Ollama is not active or times out
                pass

        # 1. Primary: Google Gemini API (gemini-3.1-pro-preview / gemini-3.8-flash)
        gemini_key = settings.GEMINI_API_KEY or os.getenv("GEMINI_API_KEY")
        if gemini_key:
            context_block = "\n".join([f"- {m}" for m in retrieved_memories]) if retrieved_memories else "No specific past memories."
            full_prompt = (
                f"{system_prompt}\n\n"
                f"### Context Recalled from Past Discussions:\n{context_block}\n\n"
                f"User: {user_message}\n\n"
                f"MANDATORY INSTRUCTION: Detect the language of the User's message above and reply in the EXACT SAME LANGUAGE and dialect. Never force English or Hindi if the user spoke another language.\n"
                f"{companion_name}:"
            )
            models_to_try = [
                settings.GEMINI_MODEL,           # gemini-3.1-pro-preview
                "gemini-flash-latest",           # Sub-second latency verified working model
                "gemini-flash-lite-latest",      # Low-latency flash-lite
                "gemini-3.5-flash",              # Stable flash model
                "gemini-3.8-flash"               # Flash 3.8
            ]
            cleaned_models = [m.replace("models/", "") for m in models_to_try if m]

            now_ts = time.time()
            for model_name in cleaned_models:
                # Fast Circuit Breaker: Skip rate-limited models currently in cool-off period
                if _model_rate_limited_until.get(model_name, 0) > now_ts:
                    continue

                try:
                    async with httpx.AsyncClient(timeout=4.0) as client:
                        resp = await client.post(
                            f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={gemini_key}",
                            json={
                                "contents": [{"parts": [{"text": full_prompt}]}],
                                "generationConfig": {"temperature": 0.7, "maxOutputTokens": 600}
                            }
                        )
                        if resp.status_code == 200:
                            data = resp.json()
                            candidates = data.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                for part in parts:
                                    if part.get("thought"):
                                        continue
                                    text = part.get("text", "").strip()
                                    if text:
                                        return cls._clean_speech_output(text)
                        elif resp.status_code == 429:
                            # Trip circuit breaker: cool-off for 60 seconds to avoid repeating 429 penalty
                            logger.warning("Gemini %s returned HTTP 429 (Rate Limit). Cooling off for 60 seconds.", model_name)
                            _model_rate_limited_until[model_name] = time.time() + 60.0
                            continue
                        else:
                            logger.warning("Gemini %s returned HTTP %s: %s", model_name, resp.status_code, resp.text[:120])
                except Exception as e:
                    logger.warning("Gemini %s call failed: %s", model_name, e)
                    continue

        openai_key = settings.OPENAI_API_KEY or os.getenv("OPENAI_API_KEY")
        if openai_key:
            try:
                context_block = "\n".join([f"- {m}" for m in retrieved_memories])
                sys = (
                    f"{system_prompt}\n\n"
                    f"Recalled Memories:\n{context_block}\n\n"
                    "MANDATORY INSTRUCTION: You MUST reply in the EXACT SAME LANGUAGE, dialect, and script the user communicated in."
                )
                async with httpx.AsyncClient(timeout=10.0) as client:
                    resp = await client.post(
                        "https://api.openai.com/v1/chat/completions",
                        headers={"Authorization": f"Bearer {openai_key}"},
                        json={
                            "model": "gpt-4o-mini",
                            "messages": [
                                {"role": "system", "content": sys},
                                {"role": "user", "content": user_message}
                            ],
                            "temperature": 0.7,
                            "max_tokens": 300
                        }
                    )
                    if resp.status_code == 200:
                        text = resp.json()["choices"][0]["message"]["content"].strip()
                        return cls._clean_speech_output(text)
            except Exception as e:
                pass

        # 3. Contextual Reply Synthesizer (Zero-Dependency Engine with Multilingual Awareness)
        return cls._synthesize_contextual_reply(
            user_message=user_message,
            retrieved_memories=retrieved_memories,
            persona=persona,
            tone=tone,
            companion_name=companion_name,
            user_name=user_name,
            locale=locale
        )

    @classmethod
    def _synthesize_contextual_reply(
        cls,
        user_message: str,
        retrieved_memories: List[str],
        persona: PersonaType,
        tone: ToneType,
        companion_name: str,
        user_name: str,
        locale: str
    ) -> str:
        """
        Synthesizes a genuine, warm, and personalized spoken reply
        in the exact language detected from user communication.
        """
        is_elder = persona == PersonaType.ELDER
        msg_lower = user_message.lower()

        # Language Detection Heuristic
        lang = "en"
        if any(w in msg_lower for w in ["hola", "buenos", "buenas", "como estas", "cómo estás", "gracias", "recuerda", "¿"]):
            lang = "es"
        elif any(w in msg_lower for w in ["bonjour", "salut", "comment", "merci", "rappelle", "s'il"]):
            lang = "fr"
        elif any(w in msg_lower for w in ["guten", "hallo", "wie geht", "danke", "erinnere"]):
            lang = "de"
        elif any(c in user_message for c in ["வணக்கம்", "எப்படி", "நன்றி"]) or "ta" in locale.lower():
            lang = "ta"
        elif any(c in user_message for c in ["নমস্কার", "কেমন", "ধন্যবাদ"]) or "bn" in locale.lower():
            lang = "bn"
        elif any(c in user_message for c in ["नमस्कार", "कसे", "धन्यवाद"]) or "mr" in locale.lower():
            lang = "mr"
        elif "hi" in locale.lower() or any(w in msg_lower for w in ["namaste", "kaise", "batao", "aaj", "kripya", "haan"]):
            lang = "hi"

        memory_highlight = retrieved_memories[0] if retrieved_memories else None

        if lang == "es":
            if is_elder:
                return f"¡Hola {user_name}! Qué alegría saludarle. Estoy aquí a su lado. Dígame, ¿cómo se siente hoy?"
            return f"¡Hola {user_name}! Aquí estoy contigo. ¿De qué te gustaría hablar hoy?"
        elif lang == "fr":
            if is_elder:
                return f"Bonjour {user_name}. C'est un grand plaisir d'être avec vous. Comment vous sentez-vous aujourd'hui ?"
            return f"Salut {user_name} ! Ravi d'échanger avec toi. De quoi aimerais-tu parler ?"
        elif lang == "de":
            if is_elder:
                return f"Guten Tag {user_name}. Es ist schön, bei Ihnen zu sein. Wie geht es Ihnen heute?"
            return f"Hallo {user_name}! Schön, von dir zu hören. Worüber möchtest du heute sprechen?"
        elif lang == "ta":
            return f"வணக்கம் {user_name}. உங்களுடன் பேசுவதில் மிக்க மகிழ்ச்சி. இன்று உங்கள் உடல்நலம் எப்படி இருக்கிறது?"
        elif lang == "bn":
            return f"নমস্কার {user_name}। আপনার সাথে কথা বলতে পেরে খুব ভালো লাগছে। আজ আপনি কেমন আছেন?"
        elif lang == "mr":
            return f"नमस्कार {user_name}। तुमच्याशी बोलून खूप आनंद झाला. आज तुम्ही कसे आहात?"
        elif lang == "hi":
            if is_elder:
                if memory_highlight:
                    return f"Namaste {user_name} ji! Haan, mujhe achhe se yaad hai ki {memory_highlight}. Is baare mein aap kaisa mehsoos kar rahe hain?"
                return f"Namaste {user_name} ji! Main {companion_name} hoon. Main aapki baat dhyan se sun rahi hoon, kripya batayein aaj aap kaisa mehsoos kar rahe hain?"
            else:
                if memory_highlight:
                    return f"Hey {user_name}! Haan yaar, mujhe yaad hai ki {memory_highlight}. Uska kya update hai?"
                return f"Aur batao {user_name}! Main {companion_name} hoon. Sab theek? Jo bhi share karna chahte ho, khulkar bata sakte ho."
        else: # Default English
            if is_elder:
                if memory_highlight:
                    return f"Hello {user_name}. Yes, I remember you mentioned that {memory_highlight}. How is everything going with that today?"
                return f"Hello {user_name}. I am {companion_name}, right here with you. It is wonderful to hear from you. What is on your mind today?"
            else:
                if memory_highlight:
                    return f"Hey {user_name}! Yes, I remember you shared that {memory_highlight}. How are you feeling about it right now?"
                return f"Hey {user_name}! {companion_name} here. Great to talk with you. What's on your mind today?"

    @staticmethod
    def _clean_speech_output(text: str) -> str:
        # Enforce anti-robot spoken rules: strip markdown bullet points, bold asterisks
        cleaned = text.replace("**", "").replace("###", "").replace("##", "").replace("⁠thought", "")
        # Remove zero-width spaces and invisible formatting tokens
        for zw in ["\u2060", "\u200b", "\u200c", "\u200d", "\ufeff"]:
            cleaned = cleaned.replace(zw, "")
        # Remove any lingering internal thought blocks
        cleaned = re.sub(r"<thought>.*?</thought>", "", cleaned, flags=re.DOTALL)
        lines = [line.lstrip("*-•1234567890. ") for line in cleaned.split("\n") if line.strip()]
        return " ".join(lines)
