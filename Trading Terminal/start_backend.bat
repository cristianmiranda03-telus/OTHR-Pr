@echo off
REM Start Project Quasar BACKEND only (port 8000).
REM Open another terminal for frontend: cd frontend && npm run dev
cd /d "%~dp0backend"
echo Starting backend on http://localhost:8000 ...
python -m uvicorn main:app --host 0.0.0.0 --port 8000
pause
