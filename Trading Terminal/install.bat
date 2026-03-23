@echo off
echo.
echo ============================================================
echo  TRADING TERMINAL - Installation Script
echo ============================================================
echo.

:: Create virtual environment
echo [1/4] Creating Python virtual environment...
python -m venv venv
call venv\Scripts\activate.bat

:: Install Python dependencies
echo.
echo [2/4] Installing Python dependencies...
pip install -r backend\requirements.txt

:: Install Node dependencies
echo.
echo [3/4] Installing Node.js dependencies...
cd frontend
npm install --legacy-peer-deps
cd ..

:: Create required directories
echo.
echo [4/4] Creating directories...
mkdir logs 2>nul
mkdir data\chromadb 2>nul
mkdir data\exports 2>nul

echo.
echo ============================================================
echo  Installation complete!
echo.
echo  NEXT STEPS:
echo  1. Edit backend\config\settings.yaml with your MT5 account
echo  2. Run: python run.py --paper
echo  3. Open: http://localhost:3000
echo ============================================================
pause
