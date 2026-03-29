from ..base_agent import BaseAgent
from ...models import AgentCategory
from ._market_base import MarketBaseAgent


class PoliticsAgent(MarketBaseAgent):
    """
    Focuses on political prediction markets:
    elections, legislation, geopolitics, government decisions.
    """

    CATEGORY_TAG = "politics"
    MAX_MARKETS = 8

    def __init__(self, **kwargs):
        super().__init__(
            name="PoliticsAgent",
            category=AgentCategory.POLITICS,
            **kwargs,
        )

    def _extra_search_terms(self) -> list[str]:
        return ["election", "poll", "approval rating", "legislation", "political news 2025"]
