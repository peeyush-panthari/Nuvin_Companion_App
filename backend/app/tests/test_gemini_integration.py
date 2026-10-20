import pytest
from backend.app.modules.agent.llm_client import LLMClient
from backend.app.modules.agent.orchestrator import AgentOrchestrator, AgentTurnRequest
from backend.app.modules.users.models import PersonaType, ToneType

@pytest.mark.asyncio
async def test_gemini_llm_client_generation():
    """
    Tests that LLMClient calls Gemini (gemini-3.1-pro-preview with fallback to gemini-3.8-flash)
    and successfully generates a natural spoken response.
    """
    response = await LLMClient.generate_response(
        system_prompt="You are Nuvin, a warm and empathetic companion for an elder.",
        user_message="Hello Nuvin, I am feeling a bit tired today after my morning walk.",
        retrieved_memories=["User walks in the park every morning at 7am"],
        persona=PersonaType.ELDER,
        tone=ToneType.RESPECTFUL,
        companion_name="Nuvin",
        user_name="Rajesh Ji",
        locale="en-IN"
    )
    assert response is not None
    assert len(response) > 5
    print(f"\n[GEMINI LLM RESPONSE]: {response}")

@pytest.mark.asyncio
async def test_gemini_agent_orchestrator_end_to_end():
    """
    Tests the full end-to-end turn: Trust Plane safety -> Vector context -> Gemini generation -> Response.
    """
    req = AgentTurnRequest(
        user_id="test_user_gemini",
        message="Good evening Nuvin, can you share something peaceful?",
        locale="en-IN"
    )
    res = await AgentOrchestrator.process_turn(req)
    assert res.spoken_response is not None
    assert len(res.spoken_response) > 5
    assert res.guardrail_decision.is_safe is True
    print(f"\n[GEMINI ORCHESTRATOR RESPONSE]: {res.spoken_response}")
