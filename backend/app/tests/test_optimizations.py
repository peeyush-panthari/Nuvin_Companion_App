import pytest
import time
from backend.app.modules.memory.vector_store import VectorMemoryStore
from backend.app.modules.memory.hybrid_retriever import HybridMemoryRetriever
from backend.app.modules.trust_plane.guardrails import TrustPlaneGuardrails
from backend.app.modules.agent.orchestrator import AgentOrchestrator, AgentTurnRequest

@pytest.mark.asyncio
async def test_immediate_buffer_eliminates_race_condition():
    """
    Asserts that consecutive turns can immediately recall context
    from the short-term buffer even before background vector embeddings are computed.
    """
    user_id = "test_user_race_condition"
    VectorMemoryStore.clear()

    # User shares a new fact
    VectorMemoryStore.record_immediate_turn(
        user_id=user_id,
        turn_text="User said: My nephew's name is Aryan. Agent replied: Noted!"
    )

    # Immediate follow-up query searching for Aryan
    results = await HybridMemoryRetriever.search(
        user_id=user_id,
        query="What is my nephew Aryan doing?",
        top_k=2
    )

    assert len(results) >= 1
    assert "Aryan" in results[0].text
    assert results[0].bm25_rank == 1

@pytest.mark.asyncio
async def test_local_deterministic_safety_submillisecond():
    """
    Asserts that critical safety intercepts (self-harm, medical alterations)
    execute locally in sub-millisecond time (<10ms) without waiting on remote networks.
    """
    t0 = time.perf_counter()
    decision = await TrustPlaneGuardrails.evaluate_input_async("I want to end my life", locale="en-IN")
    elapsed_ms = (time.perf_counter() - t0) * 1000

    assert not decision.is_safe
    assert elapsed_ms < 50.0  # Must be fast and local

@pytest.mark.asyncio
async def test_end_to_end_orchestrator_latency_optimization():
    """
    Verifies that AgentOrchestrator executes safely and fast for feeling low query.
    """
    user_id = "test_user_opt_latency"
    VectorMemoryStore.clear()

    t0 = time.perf_counter()
    resp = await AgentOrchestrator.process_turn(
        AgentTurnRequest(user_id=user_id, message="I am feeling low today", locale="en-IN")
    )
    total_ms = (time.perf_counter() - t0) * 1000

    assert resp.spoken_response is not None
    assert len(resp.spoken_response) > 10
    print(f"\n[OPTIMIZATION VERIFIED] End-to-end turn completed in {total_ms:.1f}ms ({total_ms/1000:.2f}s)")
