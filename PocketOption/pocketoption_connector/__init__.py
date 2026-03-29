"""
Pocket Option helper layer (unofficial, educational use).

Prefer :class:`PocketOption` for a synchronous, credential-friendly workflow.
Use :class:`PocketOptionConnector` when you need raw ``async`` control.
"""

from pocketoption_connector.client import PocketOptionConnector, run_async
from pocketoption_connector.config import ConnectorSettings, read_demo_from_env
from pocketoption_connector.credential_login import (
    headless_from_env,
    obtain_ssid_via_browser,
    resolve_ssid,
)
from pocketoption_connector.easy import PocketOption
from pocketoption_connector.exceptions import (
    ConnectorError,
    DependencyMissingError,
    LoginFailedError,
    UnsupportedFeatureError,
)

__all__ = [
    "PocketOption",
    "PocketOptionConnector",
    "run_async",
    "ConnectorSettings",
    "read_demo_from_env",
    "obtain_ssid_via_browser",
    "resolve_ssid",
    "headless_from_env",
    "ConnectorError",
    "DependencyMissingError",
    "LoginFailedError",
    "UnsupportedFeatureError",
]

__version__ = "0.3.0"
