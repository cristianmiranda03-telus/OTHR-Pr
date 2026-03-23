"""
Logging configuration using Loguru.
"""
import sys
from loguru import logger
from typing import Optional


def setup_logging(config: Optional[dict] = None):
    config = config or {}
    level = config.get("level", "INFO")
    log_file = config.get("file", "./logs/trading.log")
    rotation = config.get("rotation", "100 MB")
    retention = config.get("retention", "30 days")
    fmt = config.get(
        "format",
        "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | "
        "<level>{level: <8}</level> | "
        "<cyan>{name}</cyan> | "
        "<level>{message}</level>"
    )
    logger.remove()
    logger.add(sys.stderr, level=level, format=fmt, colorize=True)
    try:
        logger.add(
            log_file, level=level, format=fmt,
            rotation=rotation, retention=retention,
            compression="zip", encoding="utf-8",
        )
    except Exception as e:
        logger.warning(f"Could not set up file logging: {e}")


def get_logger(name: str):
    return logger.bind(name=name)
