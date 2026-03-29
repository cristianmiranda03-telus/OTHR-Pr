"""
Polymarket Trader - Main Entry Point
Launches the FastAPI backend and Next.js frontend simultaneously.
"""
import subprocess
import sys
import os
import configparser
import signal
import time
import socket
import logging
from pathlib import Path

BASE_DIR = Path(__file__).parent
CONFIG_PATH = BASE_DIR / "config.ini"
BACKEND_DIR = BASE_DIR / "backend"
FRONTEND_DIR = BASE_DIR / "frontend"


def load_config() -> configparser.ConfigParser:
    config = configparser.ConfigParser()
    if not CONFIG_PATH.exists():
        print(f"[ERROR] config.ini not found at {CONFIG_PATH}")
        print("[INFO]  Copy config.ini.example to config.ini and fill in your credentials.")
        sys.exit(1)
    config.read(CONFIG_PATH)
    return config


def setup_logging(log_level: str = "INFO"):
    numeric_level = getattr(logging, log_level.upper(), logging.INFO)
    logging.basicConfig(
        level=numeric_level,
        format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def check_dependencies():
    """Verify Python packages and Node modules are installed."""
    try:
        import fastapi
        import uvicorn
    except ImportError:
        print("[ERROR] Python dependencies missing. Run: pip install -r requirements.txt")
        sys.exit(1)

    node_modules = FRONTEND_DIR / "node_modules"
    if not node_modules.exists():
        print("[INFO]  Installing frontend dependencies...")
        result = subprocess.run(
            ["npm", "install"],
            cwd=FRONTEND_DIR,
            shell=True,
        )
        if result.returncode != 0:
            print("[ERROR] npm install failed. Make sure Node.js is installed.")
            sys.exit(1)


def is_port_open(host: str, port: int) -> bool:
    """Check if a TCP port is open (backend listening)."""
    try:
        with socket.create_connection((host if host != "0.0.0.0" else "127.0.0.1", port), timeout=1):
            return True
    except (socket.error, OSError):
        return False


def wait_for_backend(host: str, port: int, timeout: float = 30.0) -> bool:
    """Wait until the backend is accepting connections."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if is_port_open(host, port):
            return True
        time.sleep(0.4)
    return False


def start_backend(config: configparser.ConfigParser) -> subprocess.Popen:
    log_level = config.get("app_settings", "log_level", fallback="info").lower()
    host = config.get("app_settings", "host", fallback="0.0.0.0")
    port = config.getint("app_settings", "backend_port", fallback=8000)

    env = os.environ.copy()
    env["POLYMARKET_API_KEY"] = config.get("polymarket_api", "api_key", fallback="")
    env["POLYMARKET_API_SECRET"] = config.get("polymarket_api", "api_secret", fallback="")
    env["POLYMARKET_API_PASSPHRASE"] = config.get("polymarket_api", "api_passphrase", fallback="")
    env["POLYMARKET_PRIVATE_KEY"] = config.get("polymarket_api", "private_key", fallback="")
    env["POLYMARKET_PROXY_WALLET"] = config.get("polymarket_api", "proxy_wallet", fallback="")
    env["POLYMARKET_SIGNATURE_TYPE"] = config.get("polymarket_api", "signature_type", fallback="0")
    env["FUELXI_API_URL"] = config.get("fuelxi", "api_url", fallback="https://api.fuelix.ai/v1")
    env["FUELXI_API_KEY"] = config.get("fuelxi", "api_key", fallback="")
    env["FUELXI_MODEL"] = config.get("fuelxi", "model", fallback="claude-sonnet-4-5")
    env["LLM_PROVIDER"] = config.get("llm", "provider", fallback="fuelxi")
    env["OPENAI_API_KEY"] = config.get("openai", "api_key", fallback="")
    env["UPDATE_INTERVAL"] = config.get("app_settings", "update_interval_seconds", fallback="300")
    env["TAVILY_API_KEY"] = config.get("search", "tavily_api_key", fallback="")
    env["PYTHONPATH"] = str(BASE_DIR)

    cmd = [
        sys.executable, "-m", "uvicorn",
        "backend.main:app",
        "--host", host,
        "--port", str(port),
        "--reload",
        "--log-level", log_level,
    ]

    print(f"[BOOT]  Starting FastAPI backend on http://localhost:{port}")
    return subprocess.Popen(cmd, cwd=BASE_DIR, env=env)


def start_frontend(config: configparser.ConfigParser) -> subprocess.Popen:
    port = config.getint("app_settings", "frontend_port", fallback=3000)
    backend_port = config.getint("app_settings", "backend_port", fallback=8000)

    env = os.environ.copy()
    env["NEXT_PUBLIC_API_URL"] = f"http://localhost:{backend_port}"
    env["NEXT_PUBLIC_WS_URL"] = f"ws://localhost:{backend_port}"
    env["PORT"] = str(port)

    cmd = "npm run dev" if sys.platform == "win32" else ["npm", "run", "dev"]
    print(f"[BOOT]  Starting Next.js frontend on http://localhost:{port}")
    return subprocess.Popen(cmd, cwd=FRONTEND_DIR, env=env, shell=True if sys.platform == "win32" else False)


def main():
    print("=" * 60)
    print("  ██████╗  ██████╗ ██╗  ██╗███████╗██████╗ ")
    print("  ██╔══██╗██╔═══██╗██║ ██╔╝██╔════╝██╔══██╗")
    print("  ██████╔╝██║   ██║█████╔╝ █████╗  ██████╔╝")
    print("  ██╔═══╝ ██║   ██║██╔═██╗ ██╔══╝  ██╔══██╗")
    print("  ██║     ╚██████╔╝██║  ██╗███████╗██║  ██║")
    print("  ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝")
    print("  Polymarket Multi-Agent Trading Terminal")
    print("=" * 60)

    config = load_config()
    setup_logging(config.get("app_settings", "log_level", fallback="INFO"))

    print("[INIT]  Checking dependencies...")
    check_dependencies()

    backend_port = config.getint("app_settings", "backend_port", fallback=8000)
    frontend_port = config.getint("app_settings", "frontend_port", fallback=3000)
    host = config.get("app_settings", "host", fallback="0.0.0.0")

    processes = []
    try:
        backend_proc = start_backend(config)
        processes.append(backend_proc)

        print("[BOOT]  Waiting for backend to be ready...")
        if backend_proc.poll() is not None:
            print("[ERROR] Backend exited immediately (check logs above). Fix errors and run again.")
            sys.exit(1)
        if not wait_for_backend(host, backend_port):
            print("[ERROR] Backend did not start in time. Check for port conflicts or errors above.")
            backend_proc.terminate()
            try:
                backend_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                backend_proc.kill()
            sys.exit(1)
        print("[BOOT]  Backend is ready.")

        frontend_proc = start_frontend(config)
        processes.append(frontend_proc)

        print("\n" + "=" * 60)
        print(f"  [OK] Backend API:  http://localhost:{backend_port}")
        print(f"  [OK] Frontend UI:  http://localhost:{frontend_port}")
        print(f"  [OK] API Docs:     http://localhost:{backend_port}/docs")
        print(f"  [OK] WebSocket:    ws://localhost:{backend_port}/ws/updates")
        print("=" * 60)
        print("  Press Ctrl+C to stop all services.")
        print("=" * 60 + "\n")

        while True:
            for proc in processes:
                if proc.poll() is not None:
                    print(f"[WARN]  A process exited with code {proc.returncode}.")
                    # To prevent infinite loop if a process dies, we exit.
                    sys.exit(1)
            time.sleep(5)

    except KeyboardInterrupt:
        print("\n[STOP]  Shutting down Polymarket Trader...")
        for proc in processes:
            try:
                proc.send_signal(signal.SIGTERM)
            except Exception:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        print("[STOP]  All services stopped. Goodbye.")


if __name__ == "__main__":
    main()
