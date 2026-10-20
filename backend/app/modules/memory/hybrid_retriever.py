import logging
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional, Tuple
from pydantic import BaseModel

from backend.app.modules.memory.vector_store import VectorMemoryStore, ScoredMemory
from backend.app.modules.memory.bm25 import BM25Okapi, tokenize
from backend.app.modules.memory.embeddings import EmbeddingService

logger = logging.getLogger(__name__)

class HybridScoredMemory(BaseModel):
    """
    Unified memory context item ranked via Reciprocal Rank Fusion (RRF).
    Contains both vector similarity and BM25 lexical relevance details.
    """
    id: str
    user_id: str
    category: str
    text: str
    rrf_score: float
    vector_rank: Optional[int] = None
    vector_similarity: Optional[float] = None
    bm25_rank: Optional[int] = None
    bm25_score: Optional[float] = None
    created_at: datetime
    expires_at: Optional[datetime] = None
    metadata: Dict[str, Any] = {}

class HybridMemoryRetriever:
    """
    Production Hybrid Search Engine:
    Combines:
      1. Dense Vector Semantic Search (Cosine Similarity over embeddings)
      2. Sparse BM25 Lexical Search (Token Frequency & Non-negative IDF)
      3. Reciprocal Rank Fusion (RRF) with configurable smoothing factor (default k=60)
    
    Enforces all context categories & expiration rules:
      - Excludes expired conversation turns (>30 days) by default.
      - Preserves permanent personal facts & explicit user-directed remembrances.
    """

    DEFAULT_RRF_K: int = 15
    DEFAULT_VECTOR_WEIGHT: float = 1.0
    DEFAULT_BM25_WEIGHT: float = 1.0

    @classmethod
    async def search(
        cls,
        user_id: str,
        query: str,
        top_k: int = 4,
        vector_weight: float = DEFAULT_VECTOR_WEIGHT,
        bm25_weight: float = DEFAULT_BM25_WEIGHT,
        rrf_k: int = DEFAULT_RRF_K,
        min_vector_similarity: float = 0.10,
        category: Optional[str] = None,
        categories: Optional[List[str]] = None,
        include_expired: bool = False
    ) -> List[HybridScoredMemory]:
        """
        Executes hybrid retrieval:
          1. Gathers active memory pool for user.
          2. Computes Dense Vector similarity rankings.
          3. Computes Sparse BM25 lexical rankings.
          4. Fuses rankings using Reciprocal Rank Fusion (RRF).
        """
        now = datetime.now(timezone.utc)

        # 1. Gather active candidate records for the user
        candidate_records = []
        for r in VectorMemoryStore._records:
            if r["user_id"] != user_id or r.get("deleted_at") is not None:
                continue

            # Expiry check
            if not include_expired and r.get("expires_at") is not None:
                if r["expires_at"] < now:
                    continue

            # Category filter
            if category and r["category"] != category:
                continue
            if categories and r["category"] not in categories:
                continue

            candidate_records.append(r)

        # 1b. Check immediate unindexed buffer to eliminate eventual consistency race condition
        recent_unindexed = VectorMemoryStore.get_recent_unindexed_turns(user_id)
        for idx, turn_txt in enumerate(recent_unindexed, start=1):
            temp_id = f"recent_buffer_{idx}"
            if not any(r["text"] == turn_txt for r in candidate_records):
                candidate_records.append({
                    "id": temp_id,
                    "user_id": user_id,
                    "category": "chat_history",
                    "text": turn_txt,
                    "embedding": None,
                    "created_at": now,
                    "expires_at": None,
                    "metadata": {"source": "immediate_recent_buffer"}
                })

        if not candidate_records:
            return []

        doc_map = {r["id"]: r for r in candidate_records}

        # 2. Dense Vector Semantic Search
        query_vec = await EmbeddingService.get_embedding(query)
        vector_candidates = []
        for r in candidate_records:
            mem_vec = r.get("embedding")
            if not mem_vec:
                continue
            dot_product = sum(q * m for q, m in zip(query_vec, mem_vec))
            if dot_product >= min_vector_similarity:
                vector_candidates.append((r["id"], round(dot_product, 4)))

        # Sort vector candidates descending by similarity
        vector_candidates.sort(key=lambda x: x[1], reverse=True)

        # Map doc_id -> (rank_1_based, similarity)
        vector_rank_map: Dict[str, Tuple[int, float]] = {}
        for rank, (doc_id, sim) in enumerate(vector_candidates, start=1):
            vector_rank_map[doc_id] = (rank, sim)

        # 3. Sparse BM25 Lexical Search
        bm25_engine = BM25Okapi(candidate_records)
        bm25_candidates = bm25_engine.search(query, top_k=len(candidate_records))

        # Map doc_id -> (rank_1_based, bm25_score)
        bm25_rank_map: Dict[str, Tuple[int, float]] = {}
        for rank, (doc_id, bm_score) in enumerate(bm25_candidates, start=1):
            bm25_rank_map[doc_id] = (rank, bm_score)

        # 4. Reciprocal Rank Fusion (RRF)
        # RRF(d) = sum_{m in models} weight_m / (k + rank_m(d))
        all_doc_ids = set(vector_rank_map.keys()) | set(bm25_rank_map.keys())
        
        # If neither search matched above threshold (e.g. extremely short/novel query),
        # fall back to all candidate records with default similarity
        if not all_doc_ids and candidate_records:
            all_doc_ids = set(doc_map.keys())

        scored_memories: List[HybridScoredMemory] = []
        for doc_id in all_doc_ids:
            doc = doc_map.get(doc_id)
            if not doc:
                continue

            v_info = vector_rank_map.get(doc_id)
            b_info = bm25_rank_map.get(doc_id)

            v_rank = v_info[0] if v_info else None
            v_sim = v_info[1] if v_info else None

            b_rank = b_info[0] if b_info else None
            b_score = b_info[1] if b_info else None

            # Calculate RRF score
            rrf_score = 0.0
            if v_rank is not None:
                rrf_score += vector_weight / (rrf_k + v_rank)
            if b_rank is not None:
                rrf_score += bm25_weight / (rrf_k + b_rank)

            scored_memories.append(HybridScoredMemory(
                id=doc["id"],
                user_id=doc["user_id"],
                category=doc["category"],
                text=doc["text"],
                rrf_score=round(rrf_score, 6),
                vector_rank=v_rank,
                vector_similarity=v_sim,
                bm25_rank=b_rank,
                bm25_score=b_score,
                created_at=doc["created_at"],
                expires_at=doc.get("expires_at"),
                metadata=doc.get("metadata", {})
            ))

        # Sort descending by RRF score
        scored_memories.sort(key=lambda x: x.rrf_score, reverse=True)
        return scored_memories[:top_k]
