from .base_strategy import BaseStrategy
from .scalping import OrderFlowScalping, VWAPMeanReversionScalp, MicrostructureScalping

STRATEGY_REGISTRY = {
    "OrderFlowScalping": OrderFlowScalping,
    "VWAPMeanReversionScalp": VWAPMeanReversionScalp,
    "MicrostructureScalping": MicrostructureScalping,
}

__all__ = ["BaseStrategy", "OrderFlowScalping", "VWAPMeanReversionScalp",
           "MicrostructureScalping", "STRATEGY_REGISTRY"]
