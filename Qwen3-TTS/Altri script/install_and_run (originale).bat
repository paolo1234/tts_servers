@echo off
setlocal enabledelayedexpansion
title Qwen3-TTS API Server Installer
cd /d "%~dp0"

set "GREEN=[92m"
set "YELLOW=[93m"
set "RESET=[0m"

echo %GREEN%========================================%RESET%
echo %GREEN%  Qwen3-TTS API Server - Installer%RESET%
echo %GREEN%========================================%RESET%
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo Python non trovato! Installa Python 3.12 da https://www.python.org/downloads/
    pause
    exit /b 1
)

:: 1. Create venv
if not exist "venv\" (
    echo [1/5] Creazione ambiente virtuale...
    python -m venv venv
) else (
    echo [1/5] Ambiente virtuale gia' esistente
)

:: 2. Activate and upgrade pip
echo [2/5] Attivazione ambiente...
call venv\Scripts\activate.bat
python -m pip install --upgrade pip >nul 2>&1

:: 3. Install torch (default Windows = with CUDA runtime, works on all systems)
echo [3/5] Installazione PyTorch...
python -m pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 2>&1 | findstr /V "WARNING\|already satisfied"

:: 4. Install qwen-tts + server
echo [4/5] Installazione qwen-tts e dipendenze server...
python -m pip install -e . --no-build-isolation 2>&1 | findstr /V "WARNING\|already satisfied"
python -m pip install fastapi uvicorn python-multipart 2>&1 | findstr /V "WARNING\|already satisfied"

:: 5. Detect device
echo [5/5] Rilevamento hardware...
for /f "delims=" %%i in ('python -c "import torch; print('cuda:0' if torch.cuda.is_available() else 'cpu')"') do set DEVICE=%%i
for /f "delims=" %%i in ('python -c "import torch; print('bfloat16' if torch.cuda.is_available() else 'float32')"') do set DTYPE=%%i

echo.
echo %GREEN%========================================%RESET%
echo %GREEN%  Device: %DEVICE%  (%DTYPE%)%RESET%
echo %GREEN%  Server: http://0.0.0.0:8000%RESET%
echo %GREEN%========================================%RESET%
echo.

python -m qwen_tts.server --models "cv=Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice" --host 0.0.0.0 --port 8000 --device %DEVICE% --dtype %DTYPE% --no-flash-attn

pause
