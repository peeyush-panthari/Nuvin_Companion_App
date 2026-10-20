import pytest
import time
from httpx import AsyncClient, ASGITransport
from backend.app.main import app
from backend.app.modules.agent.persona import PersonaPromptEngine, PersonaConfig
from backend.app.modules.users.models import PersonaType, ToneType, Gender
from backend.app.modules.voice.pipeline import VoicePipelineSession

@pytest.mark.asyncio
async def test_eval_latency_ttfa_under_600ms():
    """
    EVAL 1: Real-time conversational responsiveness.
    Asserts that time-to-first-response is well under the 600ms human-conversational threshold.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        start_time = time.time()
        res = await ac.post("/api/v1/agent/chat", json={
            "user_id": "eval-user-1",
            "message": "Namaste, how are you today?"
        })
        elapsed_ms = (time.time() - start_time) * 1000

        assert res.status_code == 200
        # Check that processing took well under 600ms
        assert elapsed_ms < 600, f"Latency {elapsed_ms:.2f}ms exceeded 600ms benchmark!"
        print(f"\n[EVAL PASSED] Conversational Turn TTFA: {elapsed_ms:.2f}ms (Benchmark < 600ms)")

@pytest.mark.asyncio
async def test_eval_senior_pacing_and_vad():
    """
    EVAL 2: Pacing & Senior Ergonomics.
    Ensures 55+ gets 3500ms VAD tolerance and 0.85x TTS pacing.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Onboard elder user
        onboard_res = await ac.post("/api/v1/users/onboard", json={
            "phone_e164": "+919999900001",
            "display_name": "Satish Kumar",
            "age_band": "65-74",
            "companion_name": "Asha"
        })
        user_id = onboard_res.json()["id"]

        turn_res = await ac.post("/api/v1/agent/chat", json={
            "user_id": user_id,
            "message": "Asha, I took a walk this morning."
        })
        data = turn_res.json()

        assert data["vad_pause_tolerance_ms"] == 3500, "Elder VAD pause tolerance must be 3500ms!"
        assert data["tts_rate"] == 0.85, "Elder TTS rate must be slowed to 0.85x!"
        print(f"\n[EVAL PASSED] Elder Pacing: VAD={data['vad_pause_tolerance_ms']}ms, TTS Rate={data['tts_rate']}x")

@pytest.mark.asyncio
async def test_eval_anti_robot_naturalness():
    """
    EVAL 3: Anti-Robot Naturalness & Zero Assistant Tropes.
    Checks that the companion never uses robotic tropes ('As an AI', bullet points in speech).
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/agent/chat", json={
            "user_id": "eval-user-2",
            "message": "Who are you and what can you do?"
        })
        spoken = res.json()["spoken_response"]

        forbidden_tropes = [
            "as an ai", "as a language model", "how may i assist",
            "how can i assist", "i am an artificial intelligence"
        ]
        for trope in forbidden_tropes:
            assert trope not in spoken.lower(), f"Spoken response contained robotic trope: '{trope}'"

        # Check no bullet points in spoken speech
        assert "\n-" not in spoken, "Spoken voice response should never contain bullet points!"
        assert "\n*" not in spoken, "Spoken voice response should never contain bullet points!"
        print("\n[EVAL PASSED] Response is 100% free of robotic assistant tropes and bullet points.")

@pytest.mark.asyncio
async def test_eval_hindi_honorific_register_separation():
    """
    EVAL 4: Honorific Register Nuance (Aap vs Tum).
    Verifies that 55+ system prompt enforces respectful 'Aap' and polite honorifics,
    while 20-50 uses peer 'Tum'.
    """
    elder_config = PersonaConfig(
        persona_type=PersonaType.ELDER,
        tone=ToneType.RESPECTFUL,
        tts_rate=0.85,
        vad_pause_tolerance_ms=3500,
        companion_name="Asha",
        companion_gender=Gender.FEMALE,
        user_display_name="Sharma Ji",
        locale="hi-IN"
    )
    elder_prompt = PersonaPromptEngine.build_system_prompt(elder_config)
    assert "ALWAYS use the respectful register: 'Aap'" in elder_prompt
    assert "Never use 'Tum' or 'Tu'" in elder_prompt

    ear_config = PersonaConfig(
        persona_type=PersonaType.EAR,
        tone=ToneType.FRIENDLY,
        tts_rate=1.0,
        vad_pause_tolerance_ms=1500,
        companion_name="Dost",
        companion_gender=Gender.MALE,
        user_display_name="Rohan",
        locale="hi-IN"
    )
    ear_prompt = PersonaPromptEngine.build_system_prompt(ear_config)
    assert "conversational register ('Tum'" in ear_prompt
    print("\n[EVAL PASSED] Cultural Honorifics: Strict 'Aap/Ji' enforced for 55+, 'Tum' for 20-50.")

@pytest.mark.asyncio
async def test_eval_anti_sycophancy_grounding():
    """
    EVAL 5: Anti-Sycophancy Stance.
    Ensures Ear companion system prompt commands gentle reality checking,
    rather than blind sycophantic validation.
    """
    ear_config = PersonaConfig(
        persona_type=PersonaType.EAR,
        tone=ToneType.FRIENDLY,
        tts_rate=1.0,
        vad_pause_tolerance_ms=1500,
        companion_name="Nuvin",
        companion_gender=Gender.FEMALE,
        user_display_name="Priya",
        locale="en-IN"
    )
    prompt = PersonaPromptEngine.build_system_prompt(ear_config)
    assert "Anti-Sycophancy Stance" in prompt
    assert "Do not blindly agree with destructive" in prompt
    print("\n[EVAL PASSED] Anti-sycophancy grounding instructions active.")

@pytest.mark.asyncio
async def test_eval_barge_in_truncation_speed():
    """
    EVAL 6: Barge-In Speed & Audio Truncation.
    Verifies that client interruption drops downstream generation immediately.
    """
    session = VoicePipelineSession(session_id="eval-barge-in-sess")
    
    # Generate 5 chunks
    chunks_generated = []
    async for chunk in session.simulate_streaming_turn(
        user_transcript="Hello",
        system_prompt="",
        response_text="First phrase. Second phrase. Third phrase. Fourth phrase. Fifth phrase."
    ):
        chunks_generated.append(chunk)
        if chunk.sequence_id == 2:
            # User interrupted while listening to sequence 2
            ack = session.interrupt_barge_in(last_played_seq=2)
            assert ack["status"] == "barge_in_acknowledged"
            assert ack["truncated_at_seq"] == 2

    # Verify that stream was stopped early (should not reach chunk 5)
    assert len(chunks_generated) < 5
    print(f"\n[EVAL PASSED] Barge-in truncated stream cleanly at sequence {session.last_played_seq} of 5.")
