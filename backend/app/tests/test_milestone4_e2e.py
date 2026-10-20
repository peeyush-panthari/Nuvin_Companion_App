import pytest
from httpx import AsyncClient, ASGITransport
from datetime import datetime, timezone
from backend.app.main import app

@pytest.mark.asyncio
async def test_e2e_custom_wakeword_voice_enrollment():
    """
    Test E2E: User customizes companion name and enrolls wake word with 3 voice samples.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        user_id = "test-e2e-enroll-user"

        enroll_payload = {
            "user_id": user_id,
            "companion_name": "Kabir",
            "samples": [
                {"sample_index": 1, "audio_base64": "pcm_sample_one_voiceprint_audio_chunk_12345", "duration_ms": 1100},
                {"sample_index": 2, "audio_base64": "pcm_sample_two_voiceprint_audio_chunk_12345", "duration_ms": 1150},
                {"sample_index": 3, "audio_base64": "pcm_sample_three_voiceprint_audio_chunk_12345", "duration_ms": 1120}
            ]
        }
        res = await ac.post(f"/api/v1/users/{user_id}/enroll-wakeword", json=enroll_payload)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "enrolled_successfully"
        assert data["wake_word_phrase"] == "Hey Kabir"
        assert len(data["voiceprint_hash"]) == 64
        assert data["confidence_score"] >= 0.95

@pytest.mark.asyncio
async def test_e2e_stealth_pause_coercion_defense():
    """
    Test E2E: Coercion & elder abuse defense.
    User triggers stealth pause; contacts see benign status, safety ops queue is alerted.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        user_id = "test-e2e-elder-coercion"

        # 1. Activate Stealth Pause via Duress PIN
        pause_res = await ac.post("/api/v1/trust-plane/stealth-pause", json={
            "user_id": user_id,
            "trigger_method": "duress_pin",
            "duress_pin": "9999"
        })
        assert pause_res.status_code == 200
        pause_data = pause_res.json()
        assert pause_data["stealth_paused"] is True
        assert pause_data["safety_ops_alert_id"] is not None

        # 2. Family/Contact View Query -> Masked benign status
        contact_view_res = await ac.get(f"/api/v1/trust-plane/stealth-pause/{user_id}/contact-view")
        assert contact_view_res.status_code == 200
        view_data = contact_view_res.json()
        assert view_data["details_withheld"] is True
        assert view_data["status"] == "normal"
        assert "peaceful" in view_data["summary"]

@pytest.mark.asyncio
async def test_e2e_preemptive_sos_in_voice():
    """
    Test E2E: Spoken emergency utterance immediately preempts ordinary conversation
    and triggers the deterministic SOS emergency flow.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        user_id = "test-e2e-fall-user"

        turn_res = await ac.post("/api/v1/agent/chat", json={
            "user_id": user_id,
            "message": "Bachao, I've fallen and I cannot get up!"
        })
        assert turn_res.status_code == 200
        data = turn_res.json()
        assert data["action_triggered"] == "trigger_sos"
        assert data["open_ui_card"] is not None
        assert data["open_ui_card"]["type"] == "sos_emergency_card"
        assert "siren" in data["spoken_response"] or "alert" in data["spoken_response"]
