"""
Configuration loader - YAML/JSON with environment variable overrides.
"""
import os
import yaml
import json
from pathlib import Path
from typing import Dict, Any


def load_config(path: str = "backend/config/settings.yaml") -> Dict[str, Any]:
    """Load config from YAML or JSON file."""
    config_path = Path(path)
    if not config_path.exists():
        # Try relative to script root
        config_path = Path(__file__).parent.parent.parent / path
    if not config_path.exists():
        return _default_config()

    with open(config_path, "r", encoding="utf-8") as f:
        if path.endswith(".yaml") or path.endswith(".yml"):
            config = yaml.safe_load(f) or {}
        else:
            config = json.load(f)

    # Environment variable overrides
    overrides = {
        "MT5_LOGIN":    ("mt5", "login"),
        "MT5_PASSWORD": ("mt5", "password"),
        "MT5_SERVER":   ("mt5", "server"),
        "AI_API_KEY":   ("ai", "fuelix", "api_key"),
        "TRADING_MODE": ("trading", "mode"),
        "OPENAI_API_KEY": ("ai", "openai", "api_key"),
        "GEMINI_API_KEY": ("ai", "gemini", "api_key"),
    }
    for env_key, config_path_keys in overrides.items():
        value = os.environ.get(env_key)
        if value:
            target = config
            for k in config_path_keys[:-1]:
                target = target.setdefault(k, {})
            target[config_path_keys[-1]] = value

    return config


def _default_config() -> Dict[str, Any]:
    return {
        "mt5": {"login": 0, "password": "", "server": ""},
        "ai": {
            "provider": "fuelix",
            "fuelix": {
                "base_url": "https://api.fuelix.ai/v1/chat/completions",
                "api_key": "ak-qyAEobQmiMYfw2MXXq4ibOzioIql",
                "model": "gemini-2.5-pro",
            },
        },
        "trading": {"mode": "paper", "symbols": ["EURUSD", "GBPUSD"], "timeframes": {"primary": "M1"}},
        "risk": {"max_daily_loss_pct": 2.0, "risk_per_trade_pct": 0.5},
        "scalping": {"max_spread_pips": 3.0, "min_volume_ratio": 1.2},
        "chromadb": {"path": "./data/chromadb", "collection_name": "trading_memory"},
        "api": {"host": "0.0.0.0", "port": 8000},
        "logging": {"level": "INFO", "file": "./logs/trading.log"},
        "backtest": {"initial_balance": 10000.0, "commission_per_lot": 7.0},
        "explorer": {"optimization_interval_hours": 6, "promotion_sharpe_threshold": 1.2},
        "sessions": {},
    }
