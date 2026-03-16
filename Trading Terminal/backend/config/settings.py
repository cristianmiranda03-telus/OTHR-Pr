"""Quant-Joker Trader - Configuration."""
from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    """Application settings."""
    APP_NAME: str = "Quant-Joker Trader"
    DEBUG: bool = False
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    FRONTEND_URL: str = "http://localhost:3000"
    MT5_PATH: str | None = None

    # AI Provider - Fuelix (default), can switch to openai / gemini
    AI_PROVIDER: str = "fuelix"
    FUELIX_API_KEY: str = "ak-qyAEobQmiMYfw2MXXq4ibOzioIql"
    FUELIX_BASE_URL: str = "https://api.fuelix.ai/v1"
    FUELIX_MODEL: str = "gemini-3-pro"

    # Alternative providers (set via .env to switch)
    OPENAI_API_KEY: str = ""
    OPENAI_MODEL: str = "gpt-4o"
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-pro"

    # Agent orchestration
    AGENT_LOOP_INTERVAL: int = 60       # seconds between orchestrator cycles
    NEWS_REFRESH_INTERVAL: int = 300    # 5 min
    BACKTEST_MAX_BARS: int = 5000
    MAX_CONCURRENT_TRADES: int = 5
    MAX_RISK_PCT: float = 2.0           # max risk % per trade
    MIN_PROFIT_FACTOR: float = 1.5      # min profit factor to activate strategy
    MIN_SHARPE: float = 0.8             # min Sharpe ratio to consider strategy valid

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
