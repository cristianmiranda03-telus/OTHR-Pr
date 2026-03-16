"""MT5 connection and validation."""
import os
from typing import Any
from pydantic import BaseModel


class MT5Credentials(BaseModel):
    """MetaTrader 5 login credentials."""
    login: int
    password: str
    server: str
    path: str | None = None  # Path to terminal64.exe


def _error_message(err: Any) -> str:
    """Get message from mt5.last_error() which may return dict or tuple."""
    if err is None:
        return ""
    if isinstance(err, dict):
        return err.get("desc", "") or ""
    if isinstance(err, (tuple, list)) and len(err) >= 2:
        return str(err[1]) if err[1] else ""
    if isinstance(err, (tuple, list)) and len(err) >= 1:
        return str(err[0]) or ""
    return str(err) if err else ""


def connect_mt5(credentials: MT5Credentials) -> dict[str, Any]:
    """
    Connect to MetaTrader 5 and validate.
    Returns dict with success, message, and account info if connected.
    """
    try:
        import MetaTrader5 as mt5
    except ImportError:
        return {
            "success": False,
            "message": "MetaTrader5 no está instalado. En la carpeta backend ejecuta: pip install MetaTrader5",
            "account": None,
        }

    # If path provided, try that first
    initialized = False
    if credentials.path and credentials.path.strip():
        path_str = credentials.path.strip()
        if os.path.isfile(path_str):
            if mt5.initialize(path=path_str):
                initialized = True
            else:
                return {
                    "success": False,
                    "message": "No se pudo iniciar MT5 con esa ruta. Comprueba que sea la ruta correcta a terminal64.exe y que el terminal no esté ya abierto por otro proceso.",
                    "account": None,
                }
        else:
            if not mt5.initialize():
                return {
                    "success": False,
                    "message": f"Ruta no encontrada: {path_str}. Deja el campo vacío para usar el terminal por defecto, o indica la ruta correcta a terminal64.exe.",
                    "account": None,
                }
            initialized = True

    if not initialized and not mt5.initialize():
        err = mt5.last_error()
        desc = _error_message(err)
        return {
            "success": False,
            "message": f"MT5 no pudo iniciarse. ¿Tienes el terminal MetaTrader 5 abierto? {desc}".strip(),
            "account": None,
        }

    try:
        authorized = mt5.login(
            login=credentials.login,
            password=credentials.password,
            server=credentials.server,
        )
    except Exception as e:
        mt5.shutdown()
        return {"success": False, "message": f"Error al conectar: {e}", "account": None}

    if not authorized:
        err = mt5.last_error()
        mt5.shutdown()
        msg = _error_message(err) or "Comprueba Login, Contraseña y Servidor (debe coincidir con el del terminal)."
        return {"success": False, "message": msg, "account": None}

    account = mt5.account_info()
    if account is None:
        mt5.shutdown()
        return {"success": False, "message": "Conectado pero no se pudo leer la cuenta. Prueba a desconectar y volver a conectar en el terminal.", "account": None}

    result = {
        "success": True,
        "message": "Conectado correctamente.",
        "account": {
            "login": account.login,
            "server": account.server,
            "balance": account.balance,
            "equity": account.equity,
            "margin": account.margin,
            "currency": account.currency,
            "name": account.name,
            "trade_allowed": account.trade_allowed,
            "investor": account.investor,
        },
    }
    return result


def disconnect_mt5() -> dict[str, Any]:
    """Disconnect MT5."""
    try:
        import MetaTrader5 as mt5
        mt5.shutdown()
        return {"success": True, "message": "Disconnected."}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_mt5_state() -> dict[str, Any]:
    """Return current MT5 connection state (without reconnecting)."""
    try:
        import MetaTrader5 as mt5
        if not mt5.initialize():
            return {"connected": False, "account": None}
        account = mt5.account_info()
        mt5.shutdown()
        if account is None:
            return {"connected": False, "account": None}
        return {
            "connected": True,
            "account": {
                "login": account.login,
                "server": account.server,
                "balance": account.balance,
                "equity": account.equity,
                "currency": account.currency,
                "name": account.name,
            },
        }
    except Exception:
        return {"connected": False, "account": None}
