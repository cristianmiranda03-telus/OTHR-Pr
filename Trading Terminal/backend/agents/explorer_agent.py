"""
Agent 7: Explorer Agent (The Strategy Researcher)
Continuously tests strategy variations in paper trading and proposes improvements.
"""
import asyncio
import json
import random
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from .base_agent import BaseAgent
from ..core.backtesting import Backtester
from ..ai.llm_client import LLMClient


class ExplorerAgent(BaseAgent):
    """
    Autonomous strategy evolution:
    - Runs paper trading in background with strategy variants
    - Compares performance vs live strategy
    - Proposes parameter changes to Orchestrator
    - Tracks all tested strategies with full metrics
    - Uses LLM to generate novel strategy ideas
    """

    def __init__(self, config: dict, backtester: Backtester, llm: LLMClient):
        super().__init__("ExplorerAgent", config)
        self.backtester = backtester
        self.llm = llm
        self.explorer_cfg = config.get("explorer", {})
        self._strategy_registry: List[Dict] = []
        self._current_champion: Optional[Dict] = None
        self._exploration_queue: List[Dict] = []
        self._paper_trades: List[Dict] = []

    async def _execute(self, context: Dict) -> Dict:
        action = context.get("action", "explore")
        if action == "explore":
            return await self._run_exploration(context)
        elif action == "propose":
            return await self._propose_strategy(context)
        elif action == "register":
            return await self._register_strategy(context)
        elif action == "generate_idea":
            return await self._generate_strategy_idea(context)
        else:
            return {"error": f"Unknown action: {action}"}

    async def _run_exploration(self, context: Dict) -> Dict:
        """Run paper trading exploration of strategy variants."""
        df = context.get("df")
        symbol = context.get("symbol", "EURUSD")
        timeframe = context.get("timeframe", "M1")
        base_params = context.get("base_params", {})
        strategy_name = context.get("strategy_name", "ScalpingV1")

        if df is None or len(df) < 100:
            return {"explored": False, "reason": "Insufficient data"}

        self._emit(f"🔬 Exploring strategy variants for {strategy_name}...")

        # Generate parameter variants
        variants = self._generate_variants(base_params)
        results = []

        for variant in variants[:5]:
            try:
                from ..strategies.scalping.order_flow import OrderFlowScalping
                strat = OrderFlowScalping(config=variant)
                result = self.backtester.run(
                    df=df.tail(500),
                    strategy_fn=strat.signal,
                    strategy_name=f"{strategy_name}_v{len(results)+1}",
                    symbol=symbol,
                    timeframe=timeframe,
                    parameters=variant,
                )
                result_dict = result.to_dict()
                result_dict["parameters"] = variant
                results.append(result_dict)
                await asyncio.sleep(0.01)
            except Exception as e:
                self._emit(f"Variant test failed: {e}", "warning")

        # Find best variant
        valid = [r for r in results if r.get("total_trades", 0) >= 5]
        if not valid:
            return {"explored": True, "variants_tested": len(variants),
                    "valid_results": 0}

        best = max(valid, key=lambda x: x.get("sharpe_ratio", 0))
        self._strategy_registry.extend(valid)

        # Compare with champion
        min_sharpe = self.explorer_cfg.get("promotion_sharpe_threshold", 1.2)
        min_winrate = self.explorer_cfg.get("promotion_winrate_threshold", 0.52)
        promotion_candidate = None

        if (best.get("sharpe_ratio", 0) > min_sharpe and
                best.get("win_rate", 0) / 100 > min_winrate):
            if (self._current_champion is None or
                    best.get("sharpe_ratio", 0) > self._current_champion.get("sharpe_ratio", 0)):
                promotion_candidate = best
                self._emit(f"🏆 New champion found! Sharpe={best.get('sharpe_ratio',0):.2f} | "
                           f"WR={best.get('win_rate',0):.1f}% | Trades={best.get('total_trades',0)}")

        self._emit(f"🔬 Exploration complete: {len(valid)}/{len(variants)} valid | "
                   f"Best Sharpe={best.get('sharpe_ratio',0):.2f}")

        return {
            "explored": True,
            "variants_tested": len(variants),
            "valid_results": len(valid),
            "best_result": {
                "strategy_name": best.get("strategy_name"),
                "sharpe_ratio": best.get("sharpe_ratio"),
                "win_rate": best.get("win_rate"),
                "total_trades": best.get("total_trades"),
                "total_return_pct": best.get("total_return_pct"),
            },
            "promotion_candidate": promotion_candidate,
            "all_results": [{
                "name": r.get("strategy_name"),
                "sharpe": r.get("sharpe_ratio"),
                "win_rate": r.get("win_rate"),
                "trades": r.get("total_trades"),
                "return_pct": r.get("total_return_pct"),
                "params": r.get("parameters", {}),
            } for r in valid],
        }

    async def _propose_strategy(self, context: Dict) -> Dict:
        """Propose the best strategy to the Orchestrator."""
        if not self._strategy_registry:
            return {"proposal": None, "reason": "No strategies evaluated yet"}

        valid = [s for s in self._strategy_registry if s.get("total_trades", 0) >= 10]
        if not valid:
            return {"proposal": None, "reason": "Need more trade data"}

        best = max(valid, key=lambda x: x.get("sharpe_ratio", 0))
        self._current_champion = best
        return {
            "proposal": best,
            "strategy_name": best.get("strategy_name"),
            "parameters": best.get("parameters"),
            "metrics": {
                "sharpe": best.get("sharpe_ratio"),
                "win_rate": best.get("win_rate"),
                "profit_factor": best.get("profit_factor"),
                "max_drawdown": best.get("max_drawdown_pct"),
            },
        }

    async def _register_strategy(self, context: Dict) -> Dict:
        """Register a new strategy in the registry."""
        strategy_data = context.get("strategy")
        if strategy_data:
            self._strategy_registry.append(strategy_data)
        return {"registered": True}

    async def _generate_strategy_idea(self, context: Dict) -> Dict:
        """Use LLM to generate a novel strategy concept."""
        market_regime = context.get("regime", "trending")
        symbol = context.get("symbol", "EURUSD")
        recent_results = self._strategy_registry[-5:] if self._strategy_registry else []

        prompt = f"""You are a quantitative trading researcher. Generate a novel scalping strategy idea.

Market: {symbol} | Regime: {market_regime}
Recent tested strategies: {json.dumps([r.get('strategy_name') for r in recent_results])}

Generate a strategy that:
1. Is NOT a common RSI/MACD crossover
2. Uses market microstructure (order flow, liquidity, momentum)
3. Works in {market_regime} market
4. Has specific entry/exit rules
5. Includes risk management

Return JSON:
{{
  "name": "StrategyName",
  "concept": "brief description",
  "entry_conditions": ["condition1", "condition2"],
  "exit_conditions": ["condition1"],
  "indicators": ["ind1", "ind2"],
  "parameters": {{"param1": value}},
  "risk_notes": "risk considerations"
}}"""

        try:
            response = await self.llm.chat(
                [{"role": "user", "content": prompt}],
                json_mode=True
            )
            idea = json.loads(response)
            self._emit(f"💡 New strategy idea: {idea.get('name', 'Unknown')}")
            return {"idea": idea}
        except Exception as e:
            return {"error": str(e)}

    def _generate_variants(self, base_params: Dict) -> List[Dict]:
        """Generate parameter perturbations for exploration."""
        variants = [base_params.copy()]
        param_ranges = {
            "fast_ema": [3, 5, 8, 13],
            "slow_ema": [13, 21, 34, 50],
            "rsi_period": [9, 14, 21],
            "rsi_oversold": [25, 30, 35],
            "rsi_overbought": [65, 70, 75],
            "atr_sl_mult": [1.0, 1.5, 2.0],
            "atr_tp_mult": [2.0, 2.5, 3.0],
            "volume_ratio": [1.1, 1.2, 1.5],
        }
        for i in range(8):
            variant = base_params.copy()
            for key, values in param_ranges.items():
                if random.random() > 0.5:
                    variant[key] = random.choice(values)
            variants.append(variant)
        return variants

    def get_strategy_leaderboard(self) -> List[Dict]:
        """Return ranked strategies for UI display."""
        valid = [s for s in self._strategy_registry if s.get("total_trades", 0) >= 5]
        return sorted(valid, key=lambda x: x.get("sharpe_ratio", 0), reverse=True)[:10]
