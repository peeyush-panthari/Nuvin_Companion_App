from fastapi import APIRouter, HTTPException, Query
from typing import Dict, List, Any, Optional
from pydantic import BaseModel
import uuid
from datetime import datetime, timezone
from backend.app.modules.memory.models import (
    MemoryItemCreate, MemoryItemResponse, LifeThreadCreate, LifeThreadResponse, OpenUIMemoryCard
)
from backend.app.modules.trust_plane.audit import AuditLogger

router = APIRouter(prefix="/memory", tags=["Longitudinal Memory & Recall"])

# In-memory storage backing for fast development / testing
_memory_items_db: Dict[str, Dict[str, Any]] = {}
_life_threads_db: Dict[str, Dict[str, Any]] = {}

@router.post("/{user_id}/items", response_model=MemoryItemResponse)
async def store_memory_item(user_id: str, payload: MemoryItemCreate):
    """
    Stores a discrete factual or preference memory extracted from conversation.
    """
    item_id = str(uuid.uuid4())
    record = {
        "id": item_id,
        "user_id": user_id,
        "category": payload.category,
        "key": payload.key,
        "value": payload.value,
        "sensitivity": payload.sensitivity,
        "source_type": payload.source_type,
        "confidence": 1.0,
        "created_at": datetime.now(timezone.utc),
        "deleted_at": None
    }
    _memory_items_db[item_id] = record

    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="memory_created",
        resource="memory_items",
        resource_id=item_id,
        result="executed",
        metadata={"category": payload.category, "key": payload.key}
    )

    return MemoryItemResponse(**record)

@router.post("/{user_id}/threads", response_model=LifeThreadResponse)
async def store_life_thread(user_id: str, payload: LifeThreadCreate):
    """
    Stores an ongoing longitudinal discussion thread (e.g., knee pain, grandson's exam, job search).
    """
    thread_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    record = {
        "id": thread_id,
        "user_id": user_id,
        "category": payload.category,
        "title": payload.title,
        "summary": payload.summary,
        "entities": payload.entities,
        "status": "active",
        "last_discussed_at": now,
        "created_at": now
    }
    _life_threads_db[thread_id] = record

    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="thread_created",
        resource="life_threads",
        resource_id=thread_id,
        result="executed",
        metadata={"category": payload.category, "title": payload.title}
    )

    return LifeThreadResponse(**record)

@router.get("/{user_id}/inspect", response_model=OpenUIMemoryCard)
async def inspect_user_memory(user_id: str, category: Optional[str] = None):
    """
    Allows user to inspect everything Nuvin remembers about them.
    Formatted as an OpenUI card ready for interactive mobile UI display.
    """
    active_items = [
        item for item in _memory_items_db.values()
        if item["user_id"] == user_id and item["deleted_at"] is None
    ]
    if category:
        active_items = [i for i in active_items if i["category"].lower() == category.lower()]

    formatted_items = []
    for item in active_items:
        formatted_items.append({
            "id": item["id"],
            "category": item["category"].capitalize(),
            "label": item["key"],
            "detail": item["value"],
            "recorded_date": item["created_at"].strftime("%d %b %Y"),
            "can_delete": True
        })

    return OpenUIMemoryCard(
        title="Memory Vault",
        subtitle="Everything I remember to assist and accompany you. You have full control.",
        items=formatted_items,
        total_count=len(formatted_items)
    )

@router.delete("/{user_id}/items/{item_id}")
async def forget_memory_item(user_id: str, item_id: str):
    """
    User command: 'Forget this'. Instantly soft-deletes/purges memory item.
    """
    item = _memory_items_db.get(item_id)
    if not item or item["user_id"] != user_id:
        raise HTTPException(status_code=404, detail="Memory item not found")

    item["deleted_at"] = datetime.now(timezone.utc)

    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="memory_forgotten",
        resource="memory_items",
        resource_id=item_id,
        result="executed",
        metadata={"key": item["key"]}
    )

    return {"message": "Memory successfully forgotten and removed from future conversations", "item_id": item_id}

@router.get("/{user_id}/context-for-turn")
async def get_context_for_turn(user_id: str) -> Dict[str, Any]:
    """
    Fast sub-10ms lookup of active life threads and verified facts to inject into LLM turn.
    """
    active_facts = [
        f"{item['key']}: {item['value']}"
        for item in _memory_items_db.values()
        if item["user_id"] == user_id and item["deleted_at"] is None
    ][:10]

    active_threads = [
        f"[{t['category'].upper()}] {t['title']}: {t['summary']}"
        for t in _life_threads_db.values()
        if t["user_id"] == user_id and t["status"] == "active"
    ][:5]

    return {
        "user_id": user_id,
        "facts": active_facts,
        "threads": active_threads
    }

@router.get("/{user_id}/categories")
async def get_categorized_vector_memories(
    user_id: str,
    include_expired: bool = Query(False, description="Whether to include expired chats (>30 days)")
) -> Dict[str, Any]:
    """
    Returns all vector context memories partitioned into the 3 official tiers:
    1. chat_history: All chats and voice turns (last 1 month / 30-day retention).
    2. personal_info: Personal facts shared by user (relatives, favorites, office, etc., NO expiry).
    3. user_directed: Facts user specifically asked Nuvin to remember (NO expiry).
    """
    from backend.app.modules.memory.vector_store import VectorMemoryStore
    return VectorMemoryStore.get_categorized_memories(user_id=user_id, include_expired=include_expired)

@router.post("/{user_id}/cleanup-expired")
async def cleanup_expired_chat_memories(user_id: str) -> Dict[str, Any]:
    """
    Prunes expired chat and voice history older than 30 days.
    """
    from backend.app.modules.memory.vector_store import VectorMemoryStore
    pruned = VectorMemoryStore.cleanup_expired_memories(user_id=user_id)
    return {
        "user_id": user_id,
        "pruned_count": pruned,
        "message": f"Successfully pruned {pruned} chat memory records older than 30 days."
    }

class HybridSearchRequest(BaseModel):
    query: str
    top_k: int = 4
    vector_weight: float = 1.0
    bm25_weight: float = 1.0
    rrf_k: int = 60
    category: Optional[str] = None
    include_expired: bool = False

@router.post("/{user_id}/hybrid-search")
async def search_hybrid_memories(user_id: str, request: HybridSearchRequest) -> Dict[str, Any]:
    """
    Hybrid Search API (Vector + BM25 + Reciprocal Rank Fusion)
    Returns fused memories, RRF scores, dense vector similarity, and sparse BM25 scores.
    """
    from backend.app.modules.memory.hybrid_retriever import HybridMemoryRetriever
    results = await HybridMemoryRetriever.search(
        user_id=user_id,
        query=request.query,
        top_k=request.top_k,
        vector_weight=request.vector_weight,
        bm25_weight=request.bm25_weight,
        rrf_k=request.rrf_k,
        category=request.category,
        include_expired=request.include_expired
    )
    return {
        "user_id": user_id,
        "query": request.query,
        "count": len(results),
        "results": [r.model_dump() for r in results]
    }


