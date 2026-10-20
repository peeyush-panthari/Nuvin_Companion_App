import pytest
import asyncio
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport

from backend.app.main import app
from backend.app.modules.memory.vector_store import VectorMemoryStore, VectorMemoryCategory
from backend.app.modules.memory.categorizer import MemoryCategorizationPipeline

@pytest.mark.asyncio
async def test_category_1_chat_history_with_30_day_retention():
    """
    Tests Category 1: Chats (text and voice) are stored with 30-day retention.
    Chats within 30 days are searchable; chats older than 30 days expire and are excluded.
    """
    user_id = "test_user_cat1"
    VectorMemoryStore.clear()

    # 1. Add recent chat turn (today)
    recent_id = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User: How is the weather today? Nuvin: It is pleasant and breezy.",
        category=VectorMemoryCategory.CHAT_HISTORY.value,
        ttl_days=30
    )

    # 2. Add an expired chat turn (created 35 days ago, expired 5 days ago)
    old_id = await VectorMemoryStore.add_memory(
        user_id=user_id,
        text="User: What was the score of the match? Nuvin: India won by 6 wickets.",
        category=VectorMemoryCategory.CHAT_HISTORY.value,
        ttl_days=-5 # Simulates expired 5 days ago
    )

    # 3. Search vector store: only the active (non-expired) chat should be returned
    results = await VectorMemoryStore.search(
        user_id=user_id,
        query="weather",
        top_k=5
    )
    assert len(results) == 1
    assert results[0].id == recent_id
    assert results[0].category == VectorMemoryCategory.CHAT_HISTORY.value
    assert results[0].expires_at is not None

    # Search specifically for the old topic without include_expired: should return 0 results
    old_results = await VectorMemoryStore.search(
        user_id=user_id,
        query="cricket match score",
        top_k=5,
        include_expired=False
    )
    assert len(old_results) == 0

    # Prune expired memories
    pruned = VectorMemoryStore.cleanup_expired_memories(user_id=user_id)
    assert pruned == 1


@pytest.mark.asyncio
async def test_category_2_personal_info_no_expiry():
    """
    Tests Category 2: Personal information (brother, nephew, office address, favorite color)
    is extracted and stored with NO expiry (expires_at is None).
    """
    user_id = "test_user_cat2"
    VectorMemoryStore.clear()

    test_messages = [
        "My brother's name is Rahul and he lives in Delhi.",
        "My nephew's name is Aarav.",
        "My office address is Cyber City, Building 10, Gurgaon.",
        "My favorite color is teal blue."
    ]

    for msg in test_messages:
        await MemoryCategorizationPipeline.categorize_and_index_turn(
            user_id=user_id,
            user_message=msg,
            agent_response="That is wonderful to know.",
            session_id="test_sess_cat2",
            channel="chat"
        )

    # Retrieve categorized memories
    categorized = VectorMemoryStore.get_categorized_memories(user_id=user_id)
    personal_items = categorized[VectorMemoryCategory.PERSONAL_INFO.value]

    assert len(personal_items) >= 4
    for item in personal_items:
        # Crucial Requirement: NO expiry for personal info
        assert item["expires_at"] is None
        assert item["days_remaining"] is None
        assert item["is_expired"] is False

    # Check search retrieval on personal info
    brother_search = await VectorMemoryStore.search(user_id=user_id, query="What is my brother's name?")
    assert len(brother_search) > 0
    assert any("Rahul" in r.text for r in brother_search)

    office_search = await VectorMemoryStore.search(user_id=user_id, query="Where is my office?")
    assert len(office_search) > 0
    assert any("Cyber City" in r.text for r in office_search)


@pytest.mark.asyncio
async def test_category_3_user_directed_remember_no_expiry():
    """
    Tests Category 3: Explicit user instructions to remember something
    are extracted and stored with NO expiry (expires_at is None).
    """
    user_id = "test_user_cat3"
    VectorMemoryStore.clear()

    test_commands = [
        "Please remember that my passport renewal appointment is on 15th November.",
        "Remember I parked my car in slot B4 near pillar 12.",
        "Don't forget that Dr. Sharma's clinic is on the second floor."
    ]

    for cmd in test_commands:
        await MemoryCategorizationPipeline.categorize_and_index_turn(
            user_id=user_id,
            user_message=cmd,
            agent_response="I have made a note of that for you.",
            session_id="test_sess_cat3",
            channel="chat"
        )

    categorized = VectorMemoryStore.get_categorized_memories(user_id=user_id)
    user_directed = categorized[VectorMemoryCategory.USER_DIRECTED.value]

    assert len(user_directed) >= 3
    for item in user_directed:
        # Crucial Requirement: NO expiry for user-directed memories
        assert item["expires_at"] is None
        assert item["days_remaining"] is None
        assert item["is_expired"] is False

    # Semantic search on explicit memory
    car_search = await VectorMemoryStore.search(user_id=user_id, query="Where did I park my car?")
    assert len(car_search) > 0
    assert any("B4" in r.text for r in car_search)


@pytest.mark.asyncio
async def test_end_to_end_background_categorization_api():
    """
    Tests end-to-end API turn where user shares personal info + explicit remembrance:
    Verifies that the turn responds immediately, and background task populates the 3 categories.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        user_id = "test_e2e_categorization_user"
        VectorMemoryStore.clear()

        # User shares personal info and asks to remember something
        resp = await ac.post("/api/v1/agent/chat", json={
            "user_id": user_id,
            "message": "My brother's name is Amit, and please remember that my car is parked at level 2.",
            "locale": "en-IN"
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["spoken_response"] is not None

        # Wait for background categorization task to finish embedding and indexing
        cat_data = None
        for _ in range(15):
            cat_resp = await ac.get(f"/api/v1/memory/{user_id}/categories")
            assert cat_resp.status_code == 200
            cat_data = cat_resp.json()
            if (cat_data["counts"]["chat_history"] >= 1 and 
                cat_data["counts"]["personal_info"] >= 1 and 
                cat_data["counts"]["user_directed"] >= 1):
                break
            await asyncio.sleep(0.5)


        counts = cat_data["counts"]
        # Category 1: Chat history must be recorded
        assert counts["chat_history"] >= 1
        assert cat_data["categories"]["chat_history"][0]["expires_at"] is not None

        # Category 2: Personal info (brother Amit) must be recorded with NO expiry
        assert counts["personal_info"] >= 1
        assert any("Amit" in item["text"] for item in cat_data["categories"]["personal_info"])
        assert cat_data["categories"]["personal_info"][0]["expires_at"] is None

        # Category 3: User directed (car parked at level 2) must be recorded with NO expiry
        assert counts["user_directed"] >= 1
        assert any("level 2" in item["text"] for item in cat_data["categories"]["user_directed"])
        assert cat_data["categories"]["user_directed"][0]["expires_at"] is None
