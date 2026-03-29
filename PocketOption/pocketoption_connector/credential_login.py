"""
Obtain the Pocket Option **SSID** session cookie by signing in with **email and password**.

Pocket Option does not publish a supported password grant for third-party scripts. The
websocket client still expects an SSID-shaped session string. This module automates a
real browser (Playwright) once so you do not have to copy cookies by hand.

**Limitations:** CAPTCHA, 2FA, unusual regional flows, or layout changes can break
automation. If login fails, fall back to setting ``POCKETOPTION_SSID`` manually or run
with ``headless=False`` so you can complete challenges interactively.
"""

from __future__ import annotations

import os
import re
import time
from typing import Callable, List, Optional

from pocketoption_connector.exceptions import DependencyMissingError, LoginFailedError

DEFAULT_LOGIN_URL = "https://pocketoption.com/en/login"


def _ensure_playwright():
    try:
        from playwright.sync_api import sync_playwright  # noqa: F401
    except ImportError as exc:  # pragma: no cover - environment specific
        raise DependencyMissingError(
            "Playwright is required for email/password login. Install with:\n"
            "  pip install 'pocketoption-connector[credentials]'\n"
            "  playwright install chromium"
        ) from exc


def _try_cookie_ssid(context) -> Optional[str]:
    for cookie in context.cookies():
        if cookie.get("name") == "ssid" and (cookie.get("value") or "").strip():
            return str(cookie["value"]).strip()
    return None


def _poll_ssid(context, *, timeout_s: float, interval_s: float = 0.4) -> Optional[str]:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        found = _try_cookie_ssid(context)
        if found:
            return found
        time.sleep(interval_s)
    return _try_cookie_ssid(context)


def _dismiss_common_banners(page) -> None:
    for pattern in (
        r"accept",
        r"agree",
        r"ok",
        r"got it",
        r"allow all",
    ):
        try:
            page.get_by_role("button", name=re.compile(pattern, re.I)).first.click(timeout=2500)
            time.sleep(0.3)
        except Exception:
            continue


def _fill_first_working(page, attempts: List[Callable[[], None]]) -> bool:
    for fn in attempts:
        try:
            fn()
            return True
        except Exception:
            continue
    return False


def _fill_credentials(page, email: str, password: str) -> None:
    email_ok = _fill_first_working(
        page,
        [
            lambda: page.get_by_label(re.compile(r"email", re.I)).first.fill(email, timeout=8000),
            lambda: page.locator('input[type="email"]').first.fill(email, timeout=8000),
            lambda: page.locator('input[name="email"]').first.fill(email, timeout=8000),
            lambda: page.locator('input[autocomplete="email"]').first.fill(email, timeout=8000),
        ],
    )
    if not email_ok:
        raise LoginFailedError("Could not locate the email field (site layout may have changed).")

    pass_ok = _fill_first_working(
        page,
        [
            lambda: page.get_by_label(re.compile(r"password", re.I)).first.fill(password, timeout=8000),
            lambda: page.locator('input[type="password"]').first.fill(password, timeout=8000),
            lambda: page.locator('input[name="password"]').first.fill(password, timeout=8000),
        ],
    )
    if not pass_ok:
        raise LoginFailedError("Could not locate the password field (site layout may have changed).")


def _submit_login(page) -> None:
    clicked = _fill_first_working(
        page,
        [
            lambda: page.get_by_role("button", name=re.compile(r"sign\s*in", re.I))
            .first.click(timeout=8000),
            lambda: page.locator('button[type="submit"]').first.click(timeout=8000),
            lambda: page.locator('form button').first.click(timeout=8000),
        ],
    )
    if not clicked:
        page.keyboard.press("Enter")


def obtain_ssid_via_browser(
    email: str,
    password: str,
    *,
    login_url: Optional[str] = None,
    headless: bool = True,
    slow_mo_ms: int = 0,
    navigation_timeout_ms: int = 90_000,
    post_submit_grace_s: float = 1.5,
) -> str:
    """
    Launch Chromium, submit the web login form, and return the ``ssid`` cookie value.

    You must install browsers once: ``playwright install chromium``.
    """
    _ensure_playwright()
    from playwright.sync_api import sync_playwright

    url = (login_url or os.environ.get("POCKETOPTION_LOGIN_URL") or DEFAULT_LOGIN_URL).strip()
    email = email.strip()
    password = str(password)
    if not email or not password:
        raise LoginFailedError("Email and password must be non-empty.")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=headless, slow_mo=slow_mo_ms)
        context = browser.new_context()
        page = context.new_page()
        page.set_default_timeout(navigation_timeout_ms)
        try:
            page.goto(url, wait_until="domcontentloaded")
            _dismiss_common_banners(page)
            _fill_credentials(page, email, password)
            _submit_login(page)
            time.sleep(post_submit_grace_s)
            ssid = _poll_ssid(context, timeout_s=navigation_timeout_ms / 1000.0)
            if not ssid:
                raise LoginFailedError(
                    "SSID cookie was not set after login. Common causes: wrong password, "
                    "CAPTCHA/2FA, geo block, or UI changes. Try headless=False, complete any "
                    "challenge in the opened window, or set POCKETOPTION_SSID manually."
                )
            return ssid
        finally:
            context.close()
            browser.close()


def resolve_ssid(
    *,
    email: Optional[str] = None,
    password: Optional[str] = None,
    load_dotenv: bool = True,
    prefer_env_ssid: bool = True,
    **browser_kwargs,
) -> str:
    """
    Return SSID from ``POCKETOPTION_SSID`` when present; otherwise log in via browser.

    Reads ``POCKETOPTION_EMAIL`` / ``POCKETOPTION_PASSWORD`` when arguments are omitted.
    """
    if load_dotenv:
        try:
            from dotenv import load_dotenv

            load_dotenv()
        except ImportError:
            pass

    if prefer_env_ssid:
        env_ssid = os.environ.get("POCKETOPTION_SSID", "").strip()
        if env_ssid:
            return env_ssid

    em = (email or os.environ.get("POCKETOPTION_EMAIL", "")).strip()
    pw = password if password is not None else os.environ.get("POCKETOPTION_PASSWORD", "")
    if not em or not str(pw):
        raise LoginFailedError(
            "No SSID in POCKETOPTION_SSID and no email/password. "
            "Provide arguments or set POCKETOPTION_EMAIL and POCKETOPTION_PASSWORD."
        )
    return obtain_ssid_via_browser(em, str(pw), **browser_kwargs)


def headless_from_env(default: bool = True) -> bool:
    raw = os.environ.get("POCKETOPTION_HEADLESS", "").strip().lower()
    if raw in ("0", "false", "no"):
        return False
    if raw in ("1", "true", "yes"):
        return True
    return default
