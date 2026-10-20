import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport

from backend.app.main import app
from backend.app.modules.memory.vector_store import VectorMemoryStore, VectorMemoryCategory
from backend.app.modules.memory.bm25 import BM25Okapi, tokenize
from backend.app.modules.memory.hybrid_retriever import HybridMemoryRetriever, HybridScoredMemory

@pytest.mark.asyncio
async def test_bm25_lexical_search():
    """
    Verifies that BM25 provides exact keyword and entity recall
    even when vector embeddings might have semantic blur.
    """
    corpus = [
        {"id": "doc1", "text": "User's brother is named Rohit, who works as a doctor."},
        {"id": "doc2", "text": "User's office is at 21 MG Road, Bangalore."},
        {"id": "doc3", "text": "User takes Amlodipine 5mg every morning after breakfast."},
        {"id": "doc4", "text": "User's nephew is named Aryan."}
    ]

    bm25 = BM25Okapi(corpus)

    # 1. Exact entity: "Rohit"
    results_rohit = bm25.search("Who is Rohit?", top_k=2)
    assert len(results_rohit) >= 1
    assert results_rohit[0][0] == "doc1"
    assert results_rohit[0][1] > 0.0

    # 2. Exact address: "21 MG Road"
    results_office = bm25.search("Where is 21 MG Road?", top_k=2)
    assert len(results_office) >= 1
    assert results_office[0][0] == "doc2"

    # 3. Exact medicine: "Amlodipine"
    results_med = bm25.search("Did I take my Amlodipine?", top_k=2)
    assert len(results_med) >= 1
    assert results_med[0][0] == "doc3"


@pytest.mark.asyncio
async def test_hybrid_search_reciprocal_rank_fusion():
    """
    Verifies that Hybrid Retrieval combines Dense Vector + Sparse BM25 via RRF.
    Items matching both semantic intent and exact keywords get boosted to top rank.
    """
    user_id = "test_user_hybrid_rrf"
    VectorMemoryStore.clear()

    # Seed 3 memories:
    # 1. Brother fact with exact name Rohit
    id1 = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User's brother is named Rohit and he lives in Delhi.",
        category=VectorMemoryCategory.PERSONAL_INFO.value
    )

    # 2. Office address
    id2 = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User's office address is 21 MG Road, Bangalore.",
        category=VectorMemoryCategory.PERSONAL_INFO.value
    )

    # 3. Explicit reminder
    id3 = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User asked to remember: car is parked on basement level 2 near pillar B4.",
        category=VectorMemoryCategory.USER_DIRECTED.value
    )

    # Query: exact keyword "Rohit" + semantic question "brother"
    results = await HybridMemoryRetriever.search(
        user_id=user_id,
        query="What is my brother Rohit's city?",
        top_k=3,
        rrf_k=60
    )

    assert len(results) >= 1
    top_hit = results[0]
    assert top_hit.id == id1
    # Both vector rank and bm25 rank should be present
    assert top_hit.vector_rank is not None
    assert top_hit.bm25_rank is not None
    assert top_hit.rrf_score > 0.0

    # Also test VectorMemoryStore.hybrid_search wrapper
    direct_results = await VectorMemoryStore.hybrid_search(
        user_id=user_id,
        query="Where is my car parked?",
        top_k=2
    )
    assert len(direct_results) >= 1
    assert direct_results[0].id == id3
    assert "level 2" in direct_results[0].text


@pytest.mark.asyncio
async def test_hybrid_search_respects_30_day_expiration():
    """
    Verifies that hybrid search honors the 30-day sliding retention:
    - Active chats (<=30 days) are retrieved.
    - Expired chats (>30 days) are excluded.
    - Permanent personal facts (no expiry) are always retrieved.
    """
    user_id = "test_user_hybrid_expiry"
    VectorMemoryStore.clear()

    now = datetime.now(timezone.utc)

    # 1. Fresh chat (active, expires in 29 days)
    fresh_chat_id = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User said: I had lunch at Taj. Agent replied: Sounds delicious!",
        category=VectorMemoryCategory.CHAT_HISTORY.value,
        ttl_days=30
    )

    # 2. Expired chat (simulate chat from 35 days ago)
    expired_record_id = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User said: I bought a new blue jacket. Agent replied: Great color!",
        category=VectorMemoryCategory.CHAT_HISTORY.value,
        ttl_days=30
    )
    # Manually backdate expiration to 5 days ago
    for r in VectorMemoryStore._records:
        if r["id"] == expired_record_id:
            r["expires_at"] = now - timedelta(days=5)

    # 3. Permanent personal info (no expiry)
    personal_id = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User's favorite color is blue.",
        category=VectorMemoryCategory.PERSONAL_INFO.value
    )

    # Search for "blue"
    # The expired chat ("blue jacket") must be excluded
    # The permanent personal info ("favorite color is blue") must be retrieved!
    results = await HybridMemoryRetriever.search(
        user_id=user_id,
        query="What is my favorite blue item?",
        top_k=5,
        include_expired=False
    )

    retrieved_ids = [r.id for r in results]
    assert personal_id in retrieved_ids
    assert expired_record_id not in retrieved_ids


@pytest.mark.asyncio
async def test_hybrid_search_api_endpoint():
    """
    Tests the POST /api/v1/memory/{user_id}/hybrid-search endpoint.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        user_id = "test_user_api_hybrid"
        VectorMemoryStore.clear()

        await VectorMemoryStore.add_memory(
            user_id=user_id,
            text="User's office is at 21 MG Road Bangalore.",
            category=VectorMemoryCategory.PERSONAL_INFO.value
        )

        resp = await ac.post(f"/api/v1/memory/{user_id}/hybrid-search", json={
            "query": "Where is my office at 21 MG Road?",
            "top_k": 3,
            "rrf_k": 60
        })

        assert resp.status_code == 200
        data = resp.json()
        assert data["user_id"] == user_id
        assert data["count"] >= 1
        item = data["results"][0]
        assert "21 MG Road" in item["text"]
        assert "rrf_score" in item
        assert item["rrf_score"] > 0
        assert item["vector_rank"] is not None
        assert item["bm25_rank"] is not None
