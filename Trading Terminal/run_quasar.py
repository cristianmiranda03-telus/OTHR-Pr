#!/usr/bin/env python3
"""
Quant-Joker Trader - Single launcher.
Runs backend (FastAPI + AI Agents) and frontend (Next.js) from one script.

First time setup:
  pip install -r backend/requirements.txt
  cd frontend && npm install

Usage:
  python run_quasar.py
"""
import os
import sys
import time
import subprocess
import webbrowser
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BACKEND_DIR = ROOT / "backend"
FRONTEND_DIR = ROOT / "frontend"

BANNER = """
╔══════════════════════════════════════════════════════════╗
║           ♠  QUANT-JOKER TRADER  v2.0  ♠                ║
║         AI-Powered Agentic Trading Platform              ║
║                                                          ║
║  Agents: News · Strategy · Backtest · Performance ·     ║
║          Trade Manager · Orchestrator                    ║
║                                                          ║
║  Backend:  http://localhost:8000                         ║
║  Frontend: http://localhost:3000                         ║
║  API Docs: http://localhost:8000/docs                    ║
╚══════════════════════════════════════════════════════════╝
"""

def main():
    os.chdir(ROOT)
    print(BANNER)

    # Start backend
    backend_cmd = [
        sys.executable, "-m", "uvicorn", "main:app",
        "--host", "0.0.0.0", "--port", "8000", "--reload"
    ]
    backend_proc = subprocess.Popen(
        backend_cmd,
        cwd=str(BACKEND_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        shell=False,
        env={**os.environ, "PYTHONUNBUFFERED": "1"},
    )
    time.sleep(2)
    if backend_proc.poll() is not None:
        out, _ = backend_proc.communicate()
        print("[ERROR] Backend failed to start:")
        print(out.decode() if out else "No output")
        print("\nFix: cd backend && pip install -r requirements.txt")
        sys.exit(1)
    print("[✓] Backend running on http://localhost:8000")

    # Ensure frontend deps
    node_modules = FRONTEND_DIR / "node_modules"
    if not node_modules.is_dir():
        print("[Frontend] Installing dependencies (first run)...")
        subprocess.run(["npm", "install"], cwd=str(FRONTEND_DIR), shell=True, check=True)

    # Clean .next cache
    next_dir = FRONTEND_DIR / ".next"
    if next_dir.is_dir():
        try:
            shutil.rmtree(next_dir)
            print("[Frontend] Cleared .next cache.")
        except Exception:
            pass

    # Start frontend
    next_bin = FRONTEND_DIR / "node_modules" / "next" / "dist" / "bin" / "next"
    next_js  = FRONTEND_DIR / "node_modules" / "next" / "dist" / "bin" / "next.js"
    script   = next_bin if next_bin.is_file() else (next_js if next_js.is_file() else None)

    if script is not None:
        node_cmd = shutil.which("node") or "node"
        frontend_proc = subprocess.Popen(
            [node_cmd, str(script), "dev"],
            cwd=str(FRONTEND_DIR),
            shell=False,
            env={**os.environ},
        )
    else:
        frontend_proc = subprocess.Popen(
            "npm run dev",
            cwd=str(FRONTEND_DIR),
            shell=True,
            env={**os.environ},
        )

    time.sleep(4)
    if frontend_proc.poll() is not None:
        print("[ERROR] Frontend process exited unexpectedly.")
    else:
        print("[✓] Frontend running on http://localhost:3000")

    print()
    print("Press Ctrl+C to stop.\n")

    try:
        time.sleep(2)
        webbrowser.open("http://localhost:3000")
    except Exception:
        pass

    try:
        backend_proc.wait()
    except KeyboardInterrupt:
        print("\nShutting down Quant-Joker Trader...")
        backend_proc.terminate()
        frontend_proc.terminate()
        backend_proc.wait()
        frontend_proc.wait()
        print("Stopped. Good luck trading! ♠")

if __name__ == "__main__":
    main()
