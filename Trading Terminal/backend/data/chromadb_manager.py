"""
ChromaDB Vector Memory Manager
Stores trade contexts, patterns, and learnings for the Memory Agent.
"""
import json
import hashlib
from datetime import datetime
from typing import Optional, List, Dict, Any
from loguru import logger

try:
    import chromadb
    from chromadb.utils import embedding_functions
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False
    logger.warning("ChromaDB not installed - memory features disabled")


class ChromaMemoryManager:
    """
    Persistent vector memory for:
    - Trade contexts (what was happening when we entered/exited)
    - Pattern recognition (dangerous vs profitable scenarios)
    - Strategy performance embeddings
    - Market regime memory
    """

    def __init__(self, config: dict):
        self.cfg = config
        self.client = None
        self.collection = None
        self._initialized = False

    async def initialize(self):
        if not CHROMA_AVAILABLE:
            logger.warning("ChromaDB unavailable - memory disabled")
            return

        try:
            path = self.cfg.get("path", "./data/chromadb")
            self.client = chromadb.PersistentClient(path=path)
            model_name = self.cfg.get("embedding_model", "all-MiniLM-L6-v2")
            try:
                ef = embedding_functions.SentenceTransformerEmbeddingFunction(
                    model_name=model_name)
            except Exception:
                ef = embedding_functions.DefaultEmbeddingFunction()

            collection_name = self.cfg.get("collection_name", "trading_memory")
            self.collection = self.client.get_or_create_collection(
                name=collection_name,
                embedding_function=ef,
                metadata={"hnsw:space": "cosine"},
            )
            self._initialized = True
            count = self.collection.count()
            logger.info(f"✅ ChromaDB initialized | Collection: {collection_name} | "
                        f"Memories: {count}")
        except Exception as e:
            logger.error(f"ChromaDB init failed: {e}")

    def _make_id(self, data: dict) -> str:
        content = json.dumps(data, sort_keys=True, default=str)
        return hashlib.md5(content.encode()).hexdigest()[:16]

    def _context_to_text(self, context: dict) -> str:
        """Convert trade context to natural language for embedding."""
        parts = []
        if "symbol" in context:
            parts.append(f"Symbol: {context['symbol']}")
        if "timeframe" in context:
            parts.append(f"Timeframe: {context['timeframe']}")
        if "session" in context:
            parts.append(f"Session: {context['session']}")
        if "indicators" in context:
            ind = context["indicators"]
            if "rsi" in ind:
                parts.append(f"RSI: {ind['rsi']:.1f}")
            if "atr_pct" in ind:
                parts.append(f"ATR%: {ind['atr_pct']:.3f}")
            if "regime" in ind:
                parts.append(f"Market regime: {ind['regime']}")
            if "trend" in ind:
                parts.append(f"Trend: {ind['trend']}")
        if "news_sentiment" in context:
            parts.append(f"News sentiment: {context['news_sentiment']}")
        if "outcome" in context:
            parts.append(f"Trade outcome: {context['outcome']}")
            parts.append(f"P/L: {context.get('profit', 0):.2f}")
        return " | ".join(parts)

    async def store_trade_context(
        self,
        trade_id: str,
        context: dict,
        outcome: str,
        profit: float,
        metadata_extra: Optional[dict] = None,
    ):
        """Store a completed trade with full context for future learning."""
        if not self._initialized:
            return

        context["outcome"] = outcome
        context["profit"] = profit
        text = self._context_to_text(context)
        metadata = {
            "trade_id": str(trade_id),
            "outcome": outcome,
            "profit": float(profit),
            "timestamp": datetime.now().isoformat(),
            "dangerous": profit < 0,
            **(metadata_extra or {}),
        }
        doc_id = f"trade_{trade_id}_{self._make_id(context)}"
        try:
            self.collection.upsert(
                ids=[doc_id],
                documents=[text],
                metadatas=[metadata],
            )
            logger.debug(f"Memory stored: {doc_id} | outcome={outcome} | P/L={profit:.2f}")
        except Exception as e:
            logger.error(f"Memory store failed: {e}")

    async def query_similar_contexts(
        self,
        current_context: dict,
        n_results: int = 5,
        dangerous_only: bool = False,
    ) -> List[Dict]:
        """Find similar historical contexts for pattern matching."""
        if not self._initialized:
            return []

        query_text = self._context_to_text(current_context)
        where = {"dangerous": True} if dangerous_only else None

        try:
            kwargs: Dict[str, Any] = {
                "query_texts": [query_text],
                "n_results": min(n_results, max(self.collection.count(), 1)),
                "include": ["metadatas", "documents", "distances"],
            }
            if where:
                kwargs["where"] = where

            results = self.collection.query(**kwargs)
            memories = []
            for i, doc in enumerate(results["documents"][0]):
                memories.append({
                    "text": doc,
                    "metadata": results["metadatas"][0][i],
                    "similarity": 1 - results["distances"][0][i],
                })
            return memories
        except Exception as e:
            logger.error(f"Memory query failed: {e}")
            return []

    async def get_pattern_risk(self, context: dict) -> Dict:
        """
        Evaluate if current context resembles past losses.
        Returns risk assessment for the Orchestrator.
        """
        similar = await self.query_similar_contexts(context, n_results=10)
        if not similar:
            return {"risk_score": 0.5, "similar_losses": 0,
                    "similar_wins": 0, "recommendation": "neutral"}

        losses = [m for m in similar if m["metadata"].get("profit", 0) < 0]
        wins = [m for m in similar if m["metadata"].get("profit", 0) >= 0]
        high_similarity_losses = [
            m for m in losses if m["similarity"] > 0.8
        ]
        n_losses = len(losses)
        n_wins = len(wins)
        n_total = len(similar)
        risk_score = n_losses / n_total if n_total > 0 else 0.5
        if high_similarity_losses:
            risk_score = min(0.95, risk_score + 0.2)
        if risk_score > 0.6:
            recommendation = "avoid"
        elif risk_score < 0.35:
            recommendation = "favorable"
        else:
            recommendation = "caution"

        avg_loss = (sum(m["metadata"].get("profit", 0) for m in losses) /
                    len(losses)) if losses else 0
        return {
            "risk_score": round(risk_score, 3),
            "similar_losses": n_losses,
            "similar_wins": n_wins,
            "high_similarity_danger": len(high_similarity_losses),
            "avg_similar_loss": round(avg_loss, 2),
            "recommendation": recommendation,
            "memories": similar[:3],
        }

    async def store_strategy_performance(self, strategy_name: str,
                                          metrics: dict):
        """Store strategy backtest/live metrics for comparison."""
        if not self._initialized:
            return
        text = (f"Strategy {strategy_name}: "
                f"WinRate={metrics.get('win_rate', 0):.1f}% "
                f"Sharpe={metrics.get('sharpe_ratio', 0):.2f} "
                f"PF={metrics.get('profit_factor', 0):.2f} "
                f"Trades={metrics.get('total_trades', 0)}")
        doc_id = f"strategy_{strategy_name}_{datetime.now().strftime('%Y%m%d_%H%M')}"
        try:
            self.collection.upsert(
                ids=[doc_id],
                documents=[text],
                metadatas={"type": "strategy", "name": strategy_name,
                            "timestamp": datetime.now().isoformat(), **metrics},
            )
        except Exception as e:
            logger.error(f"Strategy store failed: {e}")

    async def get_stats(self) -> Dict:
        if not self._initialized:
            return {"initialized": False}
        count = self.collection.count()
        return {"initialized": True, "total_memories": count}
