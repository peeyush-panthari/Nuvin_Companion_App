import math
import re
from typing import List, Dict, Any, Tuple, Optional
from collections import Counter

def tokenize(text: str) -> List[str]:
    """
    Multilingual, punctuation-stripping tokenizer that supports English, Hindi (Devanagari),
    European scripts, and numeric entities (e.g. '21', 'MG', 'Rohit', 'अमित').
    """
    if not text:
        return []
    # Replace punctuation characters with spaces while preserving letters, numbers, and Unicode word characters
    cleaned = re.sub(r"""[.,!?:;"'()\[\]{}<>/\\|\-=_+*~`@#$%^&]+""", " ", text.lower())
    return [token for token in cleaned.split() if token]


class BM25Okapi:
    """
    Okapi BM25 scoring algorithm for sparse lexical retrieval.
    Computes exact keyword term frequency and inverse document frequency (IDF)
    with document length normalization.
    
    Formula:
      Score(D, Q) = sum_{q in Q} IDF(q) * (f(q, D) * (k1 + 1)) / (f(q, D) + k1 * (1 - b + b * (|D| / avgdl)))
    
    Where:
      - k1: Term frequency saturation parameter (default: 1.5)
      - b: Document length normalization parameter (default: 0.75)
      - IDF(q) = ln(1 + (N - n(q) + 0.5) / (n(q) + 0.5)) (Lucene non-negative formulation)
    """

    def __init__(self, corpus: List[Dict[str, Any]], k1: float = 1.5, b: float = 0.75):
        """
        corpus: List of dicts, each with at least 'id' and 'text'.
        """
        self.k1 = k1
        self.b = b
        self.corpus = corpus
        self.doc_ids = [doc["id"] for doc in corpus]
        self.doc_tokens = [tokenize(doc.get("text", "")) for doc in corpus]
        self.doc_lengths = [len(tokens) for tokens in self.doc_tokens]
        self.doc_len_map = {doc["id"]: len(tokens) for doc, tokens in zip(corpus, self.doc_tokens)}
        
        self.corpus_size = len(corpus)
        self.avg_doc_len = sum(self.doc_lengths) / self.corpus_size if self.corpus_size > 0 else 0.0

        # Term frequencies per document
        self.doc_freqs: List[Counter] = [Counter(tokens) for tokens in self.doc_tokens]
        self.doc_freq_map: Dict[str, Counter] = {doc["id"]: Counter(tokens) for doc, tokens in zip(corpus, self.doc_tokens)}

        # Document frequency per term: in how many docs does term t appear
        self.df: Dict[str, int] = Counter()
        for tokens in self.doc_tokens:
            for term in set(tokens):
                self.df[term] += 1

        # Precompute IDF for all observed terms
        self.idf: Dict[str, float] = {}
        for term, freq in self.df.items():
            # Non-negative Robertson-Spärck Jones IDF / Lucene BM25
            self.idf[term] = math.log(1.0 + (self.corpus_size - freq + 0.5) / (freq + 0.5))

    def get_idf(self, term: str) -> float:
        """
        Returns IDF for term. If term was not in indexed corpus, uses standard unseen term penalty.
        """
        if term in self.idf:
            return self.idf[term]
        # For unseen query terms
        return math.log(1.0 + (self.corpus_size + 0.5) / 0.5)

    def score_doc(self, doc_id: str, query_tokens: List[str]) -> float:
        """
        Computes BM25 score for a specific document against query tokens.
        """
        if self.corpus_size == 0 or self.avg_doc_len == 0:
            return 0.0

        tf_map = self.doc_freq_map.get(doc_id)
        if not tf_map:
            return 0.0

        doc_len = self.doc_len_map.get(doc_id, 0)
        len_norm = 1.0 - self.b + self.b * (doc_len / self.avg_doc_len)

        score = 0.0
        for term in query_tokens:
            tf = tf_map.get(term, 0)
            if tf == 0:
                continue
            idf = self.get_idf(term)
            numerator = tf * (self.k1 + 1.0)
            denominator = tf + self.k1 * len_norm
            score += idf * (numerator / denominator)

        return score

    def search(self, query: str, top_k: int = 10) -> List[Tuple[str, float]]:
        """
        Ranks all documents in corpus against query.
        Returns List of (doc_id, score) sorted descending by score.
        Only returns documents with score > 0.
        """
        query_tokens = tokenize(query)
        if not query_tokens or self.corpus_size == 0:
            return []

        results: List[Tuple[str, float]] = []
        for doc_id in self.doc_ids:
            score = self.score_doc(doc_id, query_tokens)
            if score > 0.0:
                results.append((doc_id, round(score, 4)))

        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]
