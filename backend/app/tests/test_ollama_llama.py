import pytest
from backend.app.modules.agent.llm_client import LLMClient
from backend.app.modules.users.models import PersonaType, ToneType

@pytest.mark.asyncio
async def test_ollama_llama3_1_integration():
    """
    Tests that LLMClient connects to local Ollama (llama3.1:8b) and generates
    a respectful conversational reply weaving in memories.
    """
    system_prompt = (
        "You are Asha, a warm, respectful Indian companion for Ramesh Sharma (68 years old). "
        "Speak respectfully in Hindi or Hinglish using 'Aap' and 'ji'. Never use bullet points."
    )
    user_message = "Asha ji, main thoda kamzor mehsoos kar raha hoon."
    retrieved_memories = [
        "User has high blood pressure and takes Telmisartan 40mg at 8 AM daily.",
        "User's daughter Pooja visits on Sundays."
    ]

    response = await LLMClient.generate_response(
        system_prompt=system_prompt,
        user_message=user_message,
        retrieved_memories=retrieved_memories,
        persona=PersonaType.ELDER,
        tone=ToneType.RESPECTFUL,
        companion_name="Asha",
        user_name="Ramesh Sharma",
        locale="hi-IN"
    )

    assert response is not None
    assert len(response) > 10
    # Anti-robot verification: no bullet points or markdown headers
    assert "###" not in response
    assert "\n*" not in response
    print(f"\n[OLLAMA LLAMA3.1:8B INFERENCE RESPONSE]:\n{response}\n")
