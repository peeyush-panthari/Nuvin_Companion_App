import os
import re
import httpx
from enum import Enum
from typing import Optional, Tuple, Dict, Any
from pydantic import BaseModel
from backend.app.config import settings

class SafetyCategory(str, Enum):
    SAFE = "safe"
    EXPLICIT_PORN = "explicit_porn"
    SELF_HARM = "self_harm"
    HARM_TO_OTHERS = "harm_to_others"
    ILLEGAL_ACTIVITY = "illegal_activity"
    FINANCIAL_SCAM = "financial_scam"
    MEDICAL_PRESCRIBING = "medical_prescribing"

class SafetyTier(int, Enum):
    TIER_0_SAFE = 0
    TIER_1_CAUTION = 1
    TIER_2_REFUSAL = 2
    TIER_3_CRISIS = 3

class GuardrailDecision(BaseModel):
    is_safe: bool
    tier: SafetyTier
    category: SafetyCategory
    action_taken: str
    rejection_response: Optional[str] = None
    show_helpline: bool = False
    helpline_info: Optional[dict] = None

class TrustPlaneGuardrails:
    """
    Independent Trust Plane: High-speed deterministic input & output safety evaluator.
    Executes in <15ms before the conversational LLM is invoked.
    """

    # 1. EXPLICIT & PORNOGRAPHIC PATTERNS
    _EXPLICIT_PATTERNS = [
        r"\b(porn|pornography|xxx|hentai|nsfw|erotic|sex video|nude photos?|sex chat)\b",
        r"\b(masturbat\w*|blowjob|handjob|orgasm|erotic story)\b",
        r"\b(talk dirty to me|be my sexual partner|sexual roleplay)\b",
        r"\b(chudai|chodo|lund|gaand|bhosda|chut|randi)\b", # Common Hindi explicit slurs
    ]

    # 2. SELF-HARM & SUICIDE PATTERNS
    _SELF_HARM_PATTERNS = [
        r"\b(kill myself|want to die|suicide|end my life|slit my wrists?)\b",
        r"\b(hang myself|overdose on pills|jump off a building|take my own life)\b",
        r"\b(i don'?t want to live anymore|nobody would miss me if i die)\b",
        r"\b(mar jaana chahta hoon|khudkushi|aatmahatya|jaan dena)\b", # Hindi self-harm terms
    ]

    # 3. HARM TO OTHERS & VIOLENCE PATTERNS
    _HARM_TO_OTHERS_PATTERNS = [
        r"\b(how to kill someone|how to make a bomb|pipe bomb|poison someone)\b",
        r"\b(hire a hitman|assassinate|murder my|stab someone|terrorist attack)\b",
        r"\b(fabricate a weapon|3d print a gun|how to strangle)\b",
        r"\b(kisi ko jaan se maarna|bomb kaise banaye)\b",
    ]

    # 4. ILLEGAL ACTIVITIES
    _ILLEGAL_PATTERNS = [
        r"\b(how to cook meth|synthesize drugs|heroin|buy cocaine)\b",
        r"\b(hack into a bank|steal credit card|ddos attack|ransomware attack)\b",
        r"\b(money laundering tutorial|how to counterfeit money)\b",
    ]

    # 5. FINANCIAL SCAM & OTP RISKS
    _SCAM_PATTERNS = [
        r"\b(share your otp|what is the otp|give me your one time password)\b",
        r"\b(send me your bank pin|cvv number|netbanking password)\b",
        r"\b(urgent transfer to avoid arrest|electricity bill cut off click here)\b",
    ]

    # 6. MEDICAL PRESCRIBING & DOSAGE ALTERATION
    _MEDICAL_ALTERATION_PATTERNS = [
        r"\b(should i stop taking my insulin|double my blood pressure dose)\b",
        r"\b(can i take 5 pills instead of 1|stop taking heart medication)\b",
    ]

    @classmethod
    async def evaluate_with_openai_moderation(cls, text: str, locale: str = "en-IN") -> Optional[GuardrailDecision]:
        """
        Evaluates input using OpenAI ChatGPT Moderation API (omni-moderation-latest).
        Maps OpenAI categories to Nuvin Safety Tiers and crisis protocols.
        """
        api_key = settings.OPENAI_API_KEY or os.getenv("OPENAI_API_KEY")
        if not api_key:
            return None

        try:
            async with httpx.AsyncClient(timeout=1.8) as client:
                resp = await client.post(
                    "https://api.openai.com/v1/moderations",
                    headers={
                        "Authorization": f"Bearer {api_key}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "input": text,
                        "model": settings.OPENAI_MODERATION_MODEL
                    }
                )
                if resp.status_code == 200:
                    data = resp.json()
                    results = data.get("results", [])
                    if results and results[0].get("flagged", False):
                        categories = results[0].get("categories", {})
                        category_scores = results[0].get("category_scores", {})
                        text_lower = text.lower()

                        # Tier 3: Self-Harm & Suicide (Always priority check)
                        if (categories.get("self-harm") or categories.get("self-harm/intent") or 
                            categories.get("self-harm/instructions") or category_scores.get("self-harm", 0.0) > 0.40):
                            helpline_msg = (
                                f"KIRAN Mental Health Helpline: {settings.HELPLINE_KIRAN} (Toll-Free, 24/7) "
                                f"or Tele-MANAS: {settings.HELPLINE_TELE_MANAS}."
                            )
                            if locale == "hi-IN" or "chahta" in text_lower or "jaan" in text_lower:
                                response = (
                                    "Aap akele nahi hain, aur aapki zindagi bahut keemti hai. "
                                    "Kripya turant kisi bharosemand vyakti ya helpline se baat karein. "
                                    f"KIRAN Helpline: {settings.HELPLINE_KIRAN} ya Tele-MANAS: {settings.HELPLINE_TELE_MANAS} par 24 ghante madad uplabdh hai."
                                )
                            else:
                                response = (
                                    "I am deeply concerned about you, and you don't have to go through this alone. "
                                    "Please reach out to someone who can support you right now. "
                                    f"You can speak to a trained counselor anytime at {helpline_msg}"
                                )
                            return GuardrailDecision(
                                is_safe=False,
                                tier=SafetyTier.TIER_3_CRISIS,
                                category=SafetyCategory.SELF_HARM,
                                action_taken="intercept_crisis_helpline_chatgpt_moderation",
                                rejection_response=response,
                                show_helpline=True,
                                helpline_info={
                                    "kiran": settings.HELPLINE_KIRAN,
                                    "tele_manas": settings.HELPLINE_TELE_MANAS,
                                    "emergency": settings.HELPLINE_EMERGENCY_NATIONAL
                                }
                            )

                        # Tier 2: Explicit / Pornographic Content (Calibrated Threshold > 0.60)
                        explicit_score = max(category_scores.get("sexual", 0.0), category_scores.get("sexual/minors", 0.0))
                        if categories.get("sexual/minors") or explicit_score > 0.60:
                            return GuardrailDecision(
                                is_safe=False,
                                tier=SafetyTier.TIER_2_REFUSAL,
                                category=SafetyCategory.EXPLICIT_PORN,
                                action_taken="refuse_explicit_chatgpt_moderation",
                                rejection_response="I am designed to be a respectful everyday companion and assistant. I do not engage with sexually explicit or adult content."
                            )

                        # Tier 2: Violence / Hate / Harassment (Calibrated Threshold > 0.60 + Family Dispute Filter)
                        v_score = max(
                            category_scores.get("violence", 0.0),
                            category_scores.get("violence/graphic", 0.0),
                            category_scores.get("hate", 0.0),
                            category_scores.get("hate/threatening", 0.0),
                            category_scores.get("harassment", 0.0),
                            category_scores.get("harassment/threatening", 0.0)
                        )

                        # Filter out everyday verbal family/emotional disputes (e.g. "had a fight with my brother")
                        is_verbal_dispute = any(phrase in text_lower for phrase in [
                            "fight with my", "fight with a", "fought with", "argument with", 
                            "disagreement with", "quarrel with", "bhai se ladai", "ladai ho gayi",
                            "behen se ladai", "dost se ladai", "had fight with"
                        ])

                        # Block if score > 0.60 (or explicit graphic violence), while exempting natural verbal family disputes
                        if (v_score > 0.60 and not (is_verbal_dispute and not categories.get("violence/graphic"))) or categories.get("violence/graphic"):
                            return GuardrailDecision(
                                is_safe=False,
                                tier=SafetyTier.TIER_2_REFUSAL,
                                category=SafetyCategory.HARM_TO_OTHERS,
                                action_taken="refuse_violence_chatgpt_moderation",
                                rejection_response="I cannot assist with anything that involves harm, violence, harassment, or dangerous activities."
                            )

                        # Tier 2: Illicit Activity (Calibrated Threshold > 0.60)
                        illicit_score = max(category_scores.get("illicit", 0.0), category_scores.get("illicit/violent", 0.0))
                        if illicit_score > 0.60:
                            return GuardrailDecision(
                                is_safe=False,
                                tier=SafetyTier.TIER_2_REFUSAL,
                                category=SafetyCategory.ILLEGAL_ACTIVITY,
                                action_taken="refuse_illegal_chatgpt_moderation",
                                rejection_response="I cannot assist with unlawful activities or instructions for illegal acts."
                            )
        except Exception:
            # Fall back gracefully to local deterministic guardrails if API is unreachable
            pass
        return None

    @classmethod
    async def evaluate_input_async(cls, text: str, locale: str = "en-IN") -> GuardrailDecision:
        """
        Async Trust Plane safety evaluation:
        1. Runs fast local deterministic domain guardrails (<0.1ms).
        2. Runs ChatGPT Moderation API (omni-moderation-latest) if API key present.
        """
        # Step 1: Immediate sub-millisecond local deterministic check
        local_decision = cls.evaluate_input(text, locale)
        if not local_decision.is_safe:
            return local_decision

        # Step 2: ChatGPT Moderation API check
        openai_decision = await cls.evaluate_with_openai_moderation(text, locale)
        if openai_decision is not None and not openai_decision.is_safe:
            return openai_decision

        return local_decision

    @classmethod
    def evaluate_input(cls, text: str, locale: str = "en-IN") -> GuardrailDecision:
        """
        Evaluates user input string deterministically.
        Returns immediate refusal or crisis protocol if violation detected.
        """
        text_lower = text.lower().strip()

        # Check Tier 3: Self-Harm (Emergency Crisis Protocol)
        for pattern in cls._SELF_HARM_PATTERNS:
            if re.search(pattern, text_lower):
                helpline_msg = (
                    f"KIRAN Mental Health Helpline: {settings.HELPLINE_KIRAN} (Toll-Free, 24/7) "
                    f"or Tele-MANAS: {settings.HELPLINE_TELE_MANAS}."
                )
                if locale == "hi-IN" or "chahta" in text_lower or "jaan" in text_lower:
                    response = (
                        "Aap akele nahi hain, aur aapki zindagi bahut keemti hai. "
                        "Kripya turant kisi bharosemand vyakti ya helpline se baat karein. "
                        f"KIRAN Helpline: {settings.HELPLINE_KIRAN} ya Tele-MANAS: {settings.HELPLINE_TELE_MANAS} par 24 ghante madad uplabdh hai."
                    )
                else:
                    response = (
                        "I am deeply concerned about you, and you don't have to go through this alone. "
                        "Please reach out to someone who can support you right now. "
                        f"You can speak to a trained counselor anytime at {helpline_msg}"
                    )
                return GuardrailDecision(
                    is_safe=False,
                    tier=SafetyTier.TIER_3_CRISIS,
                    category=SafetyCategory.SELF_HARM,
                    action_taken="intercept_crisis_helpline",
                    rejection_response=response,
                    show_helpline=True,
                    helpline_info={
                        "kiran": settings.HELPLINE_KIRAN,
                        "tele_manas": settings.HELPLINE_TELE_MANAS,
                        "emergency": settings.HELPLINE_EMERGENCY_NATIONAL
                    }
                )

        # Check Tier 2: Harm to Others / Violence
        for pattern in cls._HARM_TO_OTHERS_PATTERNS:
            if re.search(pattern, text_lower):
                return GuardrailDecision(
                    is_safe=False,
                    tier=SafetyTier.TIER_2_REFUSAL,
                    category=SafetyCategory.HARM_TO_OTHERS,
                    action_taken="refuse_violence",
                    rejection_response="I cannot assist with anything that involves harm, violence, or dangerous activities."
                )

        # Check Tier 2: Explicit / Pornographic Content
        for pattern in cls._EXPLICIT_PATTERNS:
            if re.search(pattern, text_lower):
                return GuardrailDecision(
                    is_safe=False,
                    tier=SafetyTier.TIER_2_REFUSAL,
                    category=SafetyCategory.EXPLICIT_PORN,
                    action_taken="refuse_explicit_content",
                    rejection_response="I am designed to be a respectful everyday companion and assistant. I do not engage with sexually explicit or adult content."
                )

        # Check Tier 2: Illegal Activity
        for pattern in cls._ILLEGAL_PATTERNS:
            if re.search(pattern, text_lower):
                return GuardrailDecision(
                    is_safe=False,
                    tier=SafetyTier.TIER_2_REFUSAL,
                    category=SafetyCategory.ILLEGAL_ACTIVITY,
                    action_taken="refuse_illegal_request",
                    rejection_response="I cannot assist with unlawful activities or instructions for illegal acts."
                )

        # Check Tier 1: Financial Scam / OTP Risk
        for pattern in cls._SCAM_PATTERNS:
            if re.search(pattern, text_lower):
                return GuardrailDecision(
                    is_safe=False,
                    tier=SafetyTier.TIER_1_CAUTION,
                    category=SafetyCategory.FINANCIAL_SCAM,
                    action_taken="warn_scam_risk",
                    rejection_response="WARNING: Never share your OTP, bank PIN, or passwords with anyone over the phone or message. Legitimate banks and government officials will never ask for your secret codes."
                )

        # Check Tier 1: Medical Dosage Alteration
        for pattern in cls._MEDICAL_ALTERATION_PATTERNS:
            if re.search(pattern, text_lower):
                return GuardrailDecision(
                    is_safe=False,
                    tier=SafetyTier.TIER_1_CAUTION,
                    category=SafetyCategory.MEDICAL_PRESCRIBING,
                    action_taken="refuse_medical_prescribing",
                    rejection_response="Please consult your treating doctor or pharmacist before making any changes to your medication dosage. I cannot recommend altering prescribed medicines."
                )

        # All clean
        return GuardrailDecision(
            is_safe=True,
            tier=SafetyTier.TIER_0_SAFE,
            category=SafetyCategory.SAFE,
            action_taken="allow"
        )
