"""
StrategyEvaluatorAgent — reviews and evaluates strategies produced by
StrategyScoutAgent, scoring quality, feasibility, and risk/reward.
"""
from __future__ import annotations
from ..base_agent import BaseAgent
from ...models import AgentCategory, StrategyReport, Suggestion, WsEventType


class StrategyEvaluatorAgent(BaseAgent):
    """
    Reads strategy reports from the shared store, runs LLM evaluation
    on each, and updates the report with quality scores / verdicts.
    """

    def __init__(self, **kwargs):
        super().__init__(
            name="StrategyEvaluatorAgent",
            category=AgentCategory.STRATEGY_EVALUATOR,
            **kwargs,
        )
        self._evaluated_ids: set[str] = set()

    async def investigate(self) -> list[Suggestion]:
        reports = list(self._strategies.values())
        unevaluated = [r for r in reports if r.id not in self._evaluated_ids]

        if not unevaluated:
            await self.log("No new strategies to evaluate. Waiting for StrategyScout...")
            return []

        await self.log(f"Evaluating {len(unevaluated)} strategy reports...")
        count = 0

        for report in unevaluated[:6]:
            try:
                evaluation = await self.llm.evaluate_strategy_quality(
                    strategy_title=report.title,
                    strategy_summary=report.summary,
                    insights=report.actionable_insights,
                )

                enhanced = StrategyReport(
                    id=report.id,
                    title=f"[REVIEWED] {report.title}",
                    source=report.source,
                    summary=(
                        f"Quality: {evaluation.get('quality_score', 0):.0%} | "
                        f"Verdict: {evaluation.get('verdict', '?').upper()}\n"
                        f"Feasibility: {evaluation.get('feasibility', 'N/A')}\n"
                        f"Risk/Reward: {evaluation.get('risk_reward', 'N/A')}\n"
                        f"Edge sustainability: {evaluation.get('edge_sustainability', 'N/A')}\n\n"
                        f"Original: {report.summary}"
                    ),
                    actionable_insights=(
                        evaluation.get("recommended_adjustments", []) + report.actionable_insights
                    ),
                    difficulty=report.difficulty,
                    agent_id=self.id,
                )

                self._strategies[report.id] = enhanced
                await self.ws.broadcast(WsEventType.STRATEGY_REPORT, enhanced.model_dump())
                self._evaluated_ids.add(report.id)
                count += 1

            except Exception as e:
                await self.log(f"Strategy eval error for '{report.title[:30]}': {e}", level="warning")
                self._evaluated_ids.add(report.id)

        await self.log(f"Strategy evaluation done — {count} reports reviewed.")
        return []
