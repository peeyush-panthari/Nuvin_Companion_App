import math
import uuid
from enum import Enum
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone, timedelta
from pydantic import BaseModel
from backend.app.modules.memory.embeddings import EmbeddingService

class VectorMemoryCategory(str, Enum):
    """
    Three distinct context categories for Nuvin Vector Database:
    1. CHAT_HISTORY: All user-agent turns (text & voice), saved for last 1 month (30-day retention).
    2. PERSONAL_INFO: Personal information shared by user (relatives, favorites, address, etc.), NO expiry.
    3. USER_DIRECTED: Facts/instructions user explicitly asked Nuvin to remember, NO expiry.
    """
    CHAT_HISTORY = "chat_history"      # 1 Month (30 Days) Retention
    PERSONAL_INFO = "personal_info"    # Permanent (No Expiry)
    USER_DIRECTED = "user_directed"    # Permanent (No Expiry)

class ScoredMemory(BaseModel):
    id: str
    user_id: str
    category: str
    text: str
    similarity: float
    created_at: datetime
    expires_at: Optional[datetime] = None
    metadata: Dict[str, Any] = {}

class VectorMemoryStore:
    """
    Vector Database Engine for Nuvin:
    - Stores 1024-dimensional memory vectors (compatible with PostgreSQL pgvector DDL).
    - Supports 3 distinct context tiers:
      * chat_history (30-day sliding retention)
      * personal_info (permanent, no expiry)
      * user_directed (permanent, no expiry)
    - Sub-10ms Cosine Similarity semantic retrieval.
    - Scoped strictly by user_id to enforce data isolation and consent.
    """
    _records: List[Dict[str, Any]] = []
    # Immediate short-term buffer preventing eventual consistency race conditions
    _recent_turn_buffer: Dict[str, List[Dict[str, Any]]] = {}

    # Default TTL for Category 1 (Chat turns): 30 days = 1 month
    CHAT_HISTORY_TTL_DAYS: int = 30

    @classmethod
    def record_immediate_turn(cls, user_id: str, turn_text: str, channel: str = "chat"):
        """
        Immediately saves recent turn to memory buffer (0.01ms) so follow-up queries
        can recall context immediately even before background embedding generation completes.
        """
        if user_id not in cls._recent_turn_buffer:
            cls._recent_turn_buffer[user_id] = []
        cls._recent_turn_buffer[user_id].append({
            "text": turn_text,
            "created_at": datetime.now(timezone.utc),
            "channel": channel
        })
        if len(cls._recent_turn_buffer[user_id]) > 5:
            cls._recent_turn_buffer[user_id].pop(0)

    @classmethod
    def get_recent_unindexed_turns(cls, user_id: str, max_age_seconds: int = 120) -> List[str]:
        """
        Retrieves recent turns from immediate buffer that may still be in-flight in background embedding.
        """
        now = datetime.now(timezone.utc)
        items = cls._recent_turn_buffer.get(user_id, [])
        valid = []
        for item in items:
            age = (now - item["created_at"]).total_seconds()
            if age <= max_age_seconds:
                valid.append(item["text"])
        return valid

    @classmethod
    async def add_memory(
        cls,
        user_id: str,
        text: str,
        category: str = VectorMemoryCategory.CHAT_HISTORY.value,
        metadata: Optional[Dict[str, Any]] = None,
        ttl_days: Optional[int] = None
    ) -> str:
        record_id = str(uuid.uuid4())
        embedding = await EmbeddingService.get_embedding(text)
        now = datetime.now(timezone.utc)

        # Standardize legacy category names
        norm_category = category
        if category in ("conversation_turn", "chat", "voice_turn", "conversation"):
            norm_category = VectorMemoryCategory.CHAT_HISTORY.value
        elif category in ("fact", "health", "preference", "person", "routine"):
            norm_category = VectorMemoryCategory.PERSONAL_INFO.value
        elif category in ("explicit", "user_instructed", "user_requested"):
            norm_category = VectorMemoryCategory.USER_DIRECTED.value

        # Calculate expiration date
        expires_at: Optional[datetime] = None
        if norm_category == VectorMemoryCategory.CHAT_HISTORY.value:
            effective_ttl = ttl_days if ttl_days is not None else cls.CHAT_HISTORY_TTL_DAYS
            expires_at = now + timedelta(days=effective_ttl)
        elif ttl_days is not None:
            expires_at = now + timedelta(days=ttl_days)
        # Categories personal_info and user_directed have expires_at = None (No Expiry)

        record = {
            "id": record_id,
            "user_id": user_id,
            "category": norm_category,
            "text": text,
            "embedding": embedding,
            "metadata": metadata or {},
            "created_at": now,
            "expires_at": expires_at,
            "deleted_at": None
        }
        cls._records.append(record)
        return record_id

    @classmethod
    async def search(
        cls,
        user_id: str,
        query: str,
        top_k: int = 4,
        min_similarity: float = 0.10,
        category: Optional[str] = None,
        categories: Optional[List[str]] = None,
        include_expired: bool = False
    ) -> List[ScoredMemory]:
        """
        Calculates cosine similarity between query vector and stored memory vectors for the user.
        Automatically filters out records that have expired (e.g. chat turns older than 1 month).
        """
        query_vec = await EmbeddingService.get_embedding(query)
        scored: List[ScoredMemory] = []
        now = datetime.now(timezone.utc)

        for r in cls._records:
            if r["user_id"] != user_id or r.get("deleted_at") is not None:
                continue

            # Expiration filter: exclude chats older than 1 month
            if not include_expired and r.get("expires_at") is not None:
                if r["expires_at"] < now:
                    continue

            # Category filter
            if category and r["category"] != category:
                continue
            if categories and r["category"] not in categories:
                continue

            mem_vec = r["embedding"]
            # Cosine similarity of normalized vectors is dot product
            dot_product = sum(q * m for q, m in zip(query_vec, mem_vec))

            if dot_product >= min_similarity:
                scored.append(ScoredMemory(
                    id=r["id"],
                    user_id=r["user_id"],
                    category=r["category"],
                    text=r["text"],
                    similarity=round(dot_product, 4),
                    created_at=r["created_at"],
                    expires_at=r.get("expires_at"),
                    metadata=r["metadata"]
                ))

        # Sort descending by similarity score
        scored.sort(key=lambda x: x.similarity, reverse=True)
        return scored[:top_k]

    @classmethod
    async def hybrid_search(
        cls,
        user_id: str,
        query: str,
        top_k: int = 4,
        vector_weight: float = 1.0,
        bm25_weight: float = 1.0,
        rrf_k: int = 60,
        min_vector_similarity: float = 0.10,
        category: Optional[str] = None,
        categories: Optional[List[str]] = None,
        include_expired: bool = False
    ):
        """
        Performs Hybrid Search (Dense Vector + Sparse BM25) with Reciprocal Rank Fusion (RRF).
        """
        from backend.app.modules.memory.hybrid_retriever import HybridMemoryRetriever
        return await HybridMemoryRetriever.search(
            user_id=user_id,
            query=query,
            top_k=top_k,
            vector_weight=vector_weight,
            bm25_weight=bm25_weight,
            rrf_k=rrf_k,
            min_vector_similarity=min_vector_similarity,
            category=category,
            categories=categories,
            include_expired=include_expired
        )

    @classmethod
    def get_categorized_memories(
        cls,
        user_id: str,
        include_expired: bool = False
    ) -> Dict[str, Any]:
        """
        Returns all memories for user partitioned into the 3 official categories.
        """
        now = datetime.now(timezone.utc)
        result: Dict[str, List[Dict[str, Any]]] = {
            VectorMemoryCategory.CHAT_HISTORY.value: [],
            VectorMemoryCategory.PERSONAL_INFO.value: [],
            VectorMemoryCategory.USER_DIRECTED.value: []
        }

        for r in cls._records:
            if r["user_id"] != user_id or r.get("deleted_at") is not None:
                continue

            is_expired = r.get("expires_at") is not None and r["expires_at"] < now
            if is_expired and not include_expired:
                continue

            cat = r["category"]
            if cat not in result:
                result[cat] = []

            days_remaining: Optional[int] = None
            if r.get("expires_at"):
                remaining = (r["expires_at"] - now).total_seconds()
                days_remaining = max(0, int(remaining // 86400))

            result[cat].append({
                "id": r["id"],
                "text": r["text"],
                "category": cat,
                "created_at": r["created_at"].isoformat(),
                "expires_at": r["expires_at"].isoformat() if r.get("expires_at") else None,
                "days_remaining": days_remaining,
                "is_expired": is_expired,
                "metadata": r.get("metadata", {})
            })

        return {
            "user_id": user_id,
            "counts": {k: len(v) for k, v in result.items()},
            "categories": result,
            VectorMemoryCategory.CHAT_HISTORY.value: result[VectorMemoryCategory.CHAT_HISTORY.value],
            VectorMemoryCategory.PERSONAL_INFO.value: result[VectorMemoryCategory.PERSONAL_INFO.value],
            VectorMemoryCategory.USER_DIRECTED.value: result[VectorMemoryCategory.USER_DIRECTED.value]
        }

    @classmethod
    def cleanup_expired_memories(cls, user_id: Optional[str] = None) -> int:
        """
        Removes or soft-deletes records whose 1-month retention period has elapsed.
        """
        now = datetime.now(timezone.utc)
        pruned_count = 0
        for r in cls._records:
            if user_id and r["user_id"] != user_id:
                continue
            if r.get("deleted_at") is None and r.get("expires_at") is not None:
                if r["expires_at"] < now:
                    r["deleted_at"] = now
                    pruned_count += 1
        return pruned_count

    @classmethod
    def delete_memory(cls, user_id: str, record_id: str) -> bool:
        now = datetime.now(timezone.utc)
        for r in cls._records:
            if r["id"] == record_id and r["user_id"] == user_id:
                r["deleted_at"] = now
                return True
        return False

    @classmethod
    def clear(cls):
        cls._records.clear()
        cls._recent_turn_buffer.clear()
