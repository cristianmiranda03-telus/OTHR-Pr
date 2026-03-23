@echo off
echo.
echo ============================================================
echo  TRADING TERMINAL - Starting System (PAPER MODE)
echo ============================================================
echo.
call venv\Scripts\activate.bat
python run.py --paper %*
pause
