import pytest
from httpx import AsyncClient, ASGITransport
from backend.app.main import app

@pytest.mark.asyncio
async def test_static_web_simulator():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/")
        assert res.status_code == 200
        assert "Nuvin: Trusted AI Companion" in res.text
        assert "Voice Orb" in res.text or "voice-orb" in res.text
        assert "mode-selector" in res.text
        assert "SOS" in res.text
