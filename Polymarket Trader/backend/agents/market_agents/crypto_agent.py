from ..base_agent import BaseAgent
from ...models import AgentCategory
from ._market_base import MarketBaseAgent


class CryptoAgent(MarketBaseAgent):
    """
    Focuses on crypto/DeFi prediction markets:
    BTC/ETH price targets, protocol launches, regulatory events.
    """

    CATEGORY_TAG = "crypto"
    MAX_MARKETS = 10

    def __init__(self, **kwargs):
        super().__init__(
            name="CryptoAgent",
            category=AgentCategory.CRYPTO,
            **kwargs,
        )

    def _extra_search_terms(self) -> list[str]:
        return [
            "bitcoin price prediction", "ethereum", "crypto market",
            "DeFi", "blockchain regulation", "on-chain data", "crypto news 2025",
        ]
