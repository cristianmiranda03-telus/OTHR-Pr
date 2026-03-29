from __future__ import annotations

import os
from dataclasses import dataclass


def read_demo_from_env() -> bool:
    """Return True for practice/demo when ``POCKETOPTION_DEMO`` is unset or truthy."""
    raw = os.environ.get("POCKETOPTION_DEMO", "1").strip().lower()
    return raw in ("1", "true", "yes", "demo")


@dataclass(frozen=True)
class ConnectorSettings:
    """
    Load a pre-captured SSID from the environment (optional ``python-dotenv``).

    Environment variables:

    - ``POCKETOPTION_SSID`` — session cookie string (required for this class).
    - ``POCKETOPTION_DEMO`` — ``1``/``true`` for demo (default), ``0``/``false`` for real.

    For **email/password** flows use :func:`pocketoption_connector.credential_login.resolve_ssid`
    or :meth:`PocketOption.from_env` / :meth:`PocketOption.session` instead of this class alone.
    """

    ssid: str
    is_demo: bool = True

    @classmethod
    def from_env(cls) -> "ConnectorSettings":
        ssid = os.environ.get("POCKETOPTION_SSID", "").strip()
        if not ssid:
            raise ValueError(
                "POCKETOPTION_SSID is not set. Either export the SSID cookie, or install "
                "the [credentials] extra and set POCKETOPTION_EMAIL / POCKETOPTION_PASSWORD, "
                "then use PocketOption.from_env() or PocketOption.session()."
            )
        return cls(ssid=ssid, is_demo=read_demo_from_env())
