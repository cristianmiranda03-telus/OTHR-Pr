from ..base_agent import BaseAgent
from ...models import AgentCategory
from ._market_base import MarketBaseAgent


class SportsAgent(MarketBaseAgent):
    """
    Focuses on sports prediction markets:
    match outcomes, championships, player milestones.
    """

    CATEGORY_TAG = "sports"
    MAX_MARKETS = 10

    def __init__(self, **kwargs):
        super().__init__(
            name="SportsAgent",
            category=AgentCategory.SPORTS,
            **kwargs,
        )

    def _extra_search_terms(self) -> list[str]:
        return [
            "sports betting odds", "team form", "injury report",
            "match preview", "sports analytics", "season standings 2025",
        ]
