from ..base_agent import BaseAgent
from ...models import AgentCategory
from ._market_base import MarketBaseAgent


class ScienceAgent(MarketBaseAgent):
    """
    Focuses on science & technology prediction markets:
    AI milestones, space missions, scientific discoveries, tech launches.
    """

    CATEGORY_TAG = "science"
    MAX_MARKETS = 8

    def __init__(self, **kwargs):
        super().__init__(
            name="ScienceAgent",
            category=AgentCategory.SCIENCE,
            **kwargs,
        )

    def _extra_search_terms(self) -> list[str]:
        return [
            "AI breakthrough", "space mission launch", "scientific study",
            "tech product release", "research paper", "NASA SpaceX 2025",
        ]
