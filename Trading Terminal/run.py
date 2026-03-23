#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════╗
║          TRADING TERMINAL - AI Multi-Agent System               ║
║         Run this file to start the complete system              ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
    python run.py                    # Start backend + frontend
    python run.py --backend-only     # Backend API only
    python run.py --paper            # Force paper trading mode
    python run.py --live             # Enable live trading (⚠ CAUTION)
    python run.py --symbols EURUSD GBPUSD   # Override symbols
    python run.py --login 12345 --password secret --server ICMarkets-Demo

Requirements:
    pip install -r backend/requirements.txt
    (Frontend) npm install in ./frontend/
"""
import sys
import os

# Force UTF-8 output on Windows to avoid cp1252 encoding errors
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
    os.environ["PYTHONIOENCODING"] = "utf-8"

import asyncio
import subprocess
import threading
import signal
import argparse
from pathlib import Path

# Ensure backend is importable
ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

from loguru import logger


def parse_args():
    parser = argparse.ArgumentParser(description="Trading Terminal Launcher")
    parser.add_argument("--backend-only", action="store_true",
                        help="Start backend API only (no frontend)")
    parser.add_argument("--paper", action="store_true",
                        help="Force paper trading mode")
    parser.add_argument("--live", action="store_true",
                        help="Enable live trading (⚠ use with caution)")
    parser.add_argument("--port", type=int, default=8000,
                        help="Backend API port (default: 8000)")
    parser.add_argument("--host", type=str, default="0.0.0.0",
                        help="Backend host (default: 0.0.0.0)")
    parser.add_argument("--login", type=int, default=None,
                        help="MT5 account login")
    parser.add_argument("--password", type=str, default=None,
                        help="MT5 account password")
    parser.add_argument("--server", type=str, default=None,
                        help="MT5 broker server")
    parser.add_argument("--symbols", nargs="+", default=None,
                        help="Trading symbols")
    parser.add_argument("--config", type=str,
                        default="backend/config/settings.yaml",
                        help="Config file path")
    parser.add_argument("--auto-start", action="store_true",
                        help="Auto-start trading on launch")
    return parser.parse_args()


def update_config(args):
    """Apply CLI overrides to config file."""
    import yaml
    config_path = ROOT / args.config
    if not config_path.exists():
        logger.warning(f"Config not found at {config_path}, using defaults")
        return

    with open(config_path, "r") as f:
        config = yaml.safe_load(f) or {}

    changed = False
    if args.login:
        config.setdefault("mt5", {})["login"] = args.login
        changed = True
    if args.password:
        config.setdefault("mt5", {})["password"] = args.password
        changed = True
    if args.server:
        config.setdefault("mt5", {})["server"] = args.server
        changed = True
    if args.symbols:
        config.setdefault("trading", {})["symbols"] = args.symbols
        changed = True
    if args.live:
        config.setdefault("trading", {})["mode"] = "live"
        changed = True
    elif args.paper:
        config.setdefault("trading", {})["mode"] = "paper"
        changed = True

    if changed:
        with open(config_path, "w") as f:
            yaml.dump(config, f, default_flow_style=False)
        logger.info(f"Config updated: {config_path}")


def start_frontend():
    """Start Next.js frontend in a subprocess."""
    frontend_dir = ROOT / "frontend"
    if not (frontend_dir / "node_modules").exists():
        logger.info("Installing frontend dependencies (npm install --legacy-peer-deps)...")
        subprocess.run(
            ["npm", "install", "--legacy-peer-deps"],
            cwd=frontend_dir, check=True,
            shell=True if sys.platform == "win32" else False,
        )

    logger.info("🌐 Starting Next.js frontend on http://localhost:3000")
    proc = subprocess.Popen(
        ["npm", "run", "dev"],
        cwd=frontend_dir,
        shell=True if sys.platform == "win32" else False,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    for line in proc.stdout:
        decoded = line.decode("utf-8", errors="replace").strip()
        if decoded:
            logger.info(f"[Frontend] {decoded}")
    return proc


def print_banner(args):
    mode = "LIVE (!)" if args.live else "PAPER"
    sep = "=" * 66
    print(f"\n{sep}")
    print("   TRADING TERMINAL - AI MULTI-AGENT SYSTEM")
    print(sep)
    print("   Agents:  8 AI Agents (Orchestrator, Quant, Sentinel,")
    print("            Risk Officer, Executor, Auditor, Researcher, Cleaner)")
    print("   Stack:   Python (FastAPI) + Next.js + ChromaDB + FuelIX")
    print("   Focus:   Scalping | NYSE, LSE, TSE Sessions")
    print(sep)
    print(f"   Mode:    {mode}")
    print(f"   API:     http://localhost:{args.port}")
    if not args.backend_only:
        print("   UI:      http://localhost:3000")
    print(sep)
    print("   IMPORTANT: Review settings.yaml before live trading")
    print("   Start in PAPER mode to validate strategy performance")
    print(f"{sep}\n")


async def start_backend(args):
    """Start FastAPI backend with uvicorn."""
    import uvicorn
    config = uvicorn.Config(
        "backend.api.main:app",
        host=args.host,
        port=args.port,
        log_level="info",
        reload=False,
        access_log=True,
        loop="asyncio",
    )
    server = uvicorn.Server(config)
    logger.info(f"🚀 Backend API starting on http://{args.host}:{args.port}")
    await server.serve()


def main():
    args = parse_args()
    print_banner(args)

    # Safety confirmation for live mode
    if args.live:
        print("\n⚠️  WARNING: You are about to start LIVE trading!")
        print("   Real money will be at risk. Ensure your settings are correct.")
        confirm = input("   Type 'CONFIRM LIVE' to proceed: ")
        if confirm != "CONFIRM LIVE":
            print("Live trading aborted.")
            sys.exit(0)

    # Create required directories
    for d in ["logs", "data/chromadb", "data/exports"]:
        (ROOT / d).mkdir(parents=True, exist_ok=True)

    # Update config from CLI args
    update_config(args)

    frontend_thread = None
    if not args.backend_only:
        frontend_thread = threading.Thread(target=start_frontend, daemon=True)
        frontend_thread.start()

    # Auto-start trading after backend ready
    if args.auto_start:
        async def auto_start():
            import httpx
            await asyncio.sleep(5)  # Wait for backend to initialize
            try:
                async with httpx.AsyncClient() as client:
                    mode = "live" if args.live else "paper"
                    resp = await client.post(
                        f"http://localhost:{args.port}/api/trading/start",
                        json={"mode": mode, "interval": 30},
                        timeout=10
                    )
                    if resp.status_code == 200:
                        logger.info(f"✅ Auto-started trading in {mode.upper()} mode")
            except Exception as e:
                logger.warning(f"Auto-start failed: {e}")

        asyncio.get_event_loop().create_task(auto_start())

    # Handle shutdown
    def shutdown(sig, frame):
        logger.info("Shutdown signal received...")
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, shutdown)

    # Run backend
    try:
        asyncio.run(start_backend(args))
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt - shutting down")
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
