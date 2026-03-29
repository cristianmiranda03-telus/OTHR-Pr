"""
Application configuration loaded from environment variables (set by run.py from config.ini).
"""
import os
from functools import lru_cache
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Polymarket
    polymarket_api_key: str = ""
    polymarket_api_secret: str = ""
    polymarket_api_passphrase: str = ""
    polymarket_private_key: str = ""
    # If Data API /positions is empty for your EOA, set your Polymarket proxy wallet here (profile address on polymarket.com)
    polymarket_proxy_wallet: str = ""
    # CLOB funder mode: 1 = POLY_PROXY, 2 = GNOSIS_SAFE. If 0 and proxy_wallet set, defaults to 1.
    polymarket_signature_type: int = 0
    clob_base_url: str = "https://clob.polymarket.com"

    # FuelXI (OpenAI-compatible)
    fuelxi_api_url: str = "https://api.fuelix.ai/v1"
    fuelxi_api_key: str = ""
    fuelxi_model: str = "claude-sonnet-4-5"

    # OpenAI (optional, future)
    openai_api_key: str = ""
    openai_model: str = "gpt-4o"

    # LLM Provider selector
    llm_provider: str = "fuelxi"  # "fuelxi" | "openai"

    # Search (optional)
    tavily_api_key: str = ""

    # App
    update_interval: int = 300
    min_confidence: float = 0.55
    max_parallel_agents: int = 6

    class Config:
        env_file = ".env"
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    return Settings()
