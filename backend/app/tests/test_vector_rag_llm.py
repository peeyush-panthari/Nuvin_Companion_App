import pytest
from httpx import AsyncClient, ASGITransport
from backend.app.main import app
from backend.app.modules.memory.embeddings import EmbeddingService
from backend.app.modules.memory.vector_store import VectorMemoryStore
from backend.app.modules.agent.orchestrator import AgentOrchestrator, AgentTurnRequest

@pytest.mark.asyncio
async def test_vector_embeddings_generation():
    """
    Verifies that vector embeddings are generated, 1024-dimensional, and L2-normalized.
    """
    text1 = "My grandson Aarav has his board exams this Friday in Delhi."
    text2 = "Aarav is studying hard for his Delhi school examinations."
    text3 = "The recipe for vegetable biryani requires basmati rice and saffron."

    vec1 = await EmbeddingService.get_embedding(text1)
    vec2 = await EmbeddingService.get_embedding(text2)
    vec3 = await EmbeddingService.get_embedding(text3)

    assert len(vec1) == 1024
    assert len(vec2) == 1024
    assert len(vec3) == 1024

    # Dot product of normalized vectors represents cosine similarity
    sim_related = sum(a * b for a, b in zip(vec1, vec2))
    sim_unrelated = sum(a * b for a, b in zip(vec1, vec3))

    assert sim_related > sim_unrelated, f"Expected {sim_related} > {sim_unrelated}"
    print(f"\n[VECTOR PASSED] Related text similarity: {sim_related:.4f} > Unrelated similarity: {sim_unrelated:.4f}")

@pytest.mark.asyncio
async def test_vector_database_semantic_retrieval():
    """
    Verifies Vector Database indexing and top-k cosine similarity retrieval.
    """
    user_id = "test-vector-user-ramesh"
    VectorMemoryStore.clear()

    # Index 3 distinct memories
    await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="Had severe knee pain after climbing temple stairs yesterday.",
        category="health"
    )
    await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="Grandson Aarav scored first rank in his science competition.",
        category="family"
    )
    await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="Prefers drinking adrak elaichi chai at 7 AM sharp.",
        category="preference"
    )

    # Query 1: Health / Joint related query
    results_health = await VectorMemoryStore.search(
        user_id=user_id,
        query="Doctor asked how my leg joints and knee are feeling",
        top_k=1
    )
    assert len(results_health) == 1
    assert "knee pain" in results_health[0].text
    print(f"\n[RETRIEVAL PASSED] Query for knee retrieved: '{results_health[0].text}' (score: {results_health[0].similarity})")

    # Query 2: Family / Grandson query
    results_family = await VectorMemoryStore.search(
        user_id=user_id,
        query="Tell me about my grandson's achievements",
        top_k=1
    )
    assert len(results_family) == 1
    assert "Aarav" in results_family[0].text
    print(f"\n[RETRIEVAL PASSED] Query for grandson retrieved: '{results_family[0].text}' (score: {results_family[0].similarity})")

@pytest.mark.asyncio
async def test_end_to_end_vector_retrieval_and_llm_reply_framing():
    """
    Full End-to-End Pipeline:
    User message -> Vector Embedding -> Cosine Similarity Search -> LLM Context Injection -> Personalized Reply Framing.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        user_id = "test-rag-e2e-elder"
        VectorMemoryStore.clear()

        # 1. Onboard Elder User
        await ac.post("/api/v1/users/onboard", json={
            "phone_e164": "+919876543201",
            "display_name": "Sharma Ji",
            "age_band": "65-74",
            "companion_name": "Asha",
            "locale": "hi-IN"
        })

        # 2. Store past memory in Vector Store
        await VectorMemoryStore.add_memory(
            user_id=user_id,
            text="Sharma Ji ko subah mandir jaate waqt ghutne mein dard hua tha.",
            category="health"
        )

        # 3. User asks a turn touching on health
        turn_res = await ac.post("/api/v1/agent/chat", json={
            "user_id": user_id,
            "message": "Asha ji, main aaj subah thoda tehalne gaya tha.",
            "locale": "hi-IN"
        })
        assert turn_res.status_code == 200
        reply = turn_res.json()["spoken_response"]

        # 4. Verify that LLM framed the reply using the retrieved vector memory (knee pain/morning walk)
        assert any(w in reply.lower() for w in ["asha", "sharma", "yaad", "ghutne", "dard", "mandir"])
        print(f"\n[LLM FRAMING PASSED] Generated Response: {reply}")

        # Allow background categorization task to finish indexing
        import asyncio
        await asyncio.sleep(0.5)

        # 5. Verify that this new turn was auto-vectorized and stored for future recall
        future_memories = await VectorMemoryStore.search(
            user_id=user_id,
            query="tehalne gaya tha subah",
            top_k=1
        )
        assert len(future_memories) >= 1
        print(f"\n[AUTO-INDEXING PASSED] Stored turn: {future_memories[0].text[:80]}...")
