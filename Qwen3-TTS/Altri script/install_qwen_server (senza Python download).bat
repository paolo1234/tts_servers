@echo off
setlocal enabledelayedexpansion
title Qwen3-TTS Server - Installer
cd /d "%~dp0"

set "GREEN=[92m"
set "YELLOW=[93m"
set "RED=[91m"
set "RESET=[0m"

echo %GREEN%========================================%RESET%
echo %GREEN%  Qwen3-TTS Server - Installer%RESET%
echo %GREEN%  Tutto incluso - 1 click%RESET%
echo %GREEN%========================================%RESET%
echo.

:: ----- 1. CHECK / INSTALL PYTHON -----
:CHECK_PYTHON
python --version >nul 2>&1
if not errorlevel 1 goto PYTHON_OK

echo [1/5] Python non trovato. Scarico Python 3.12...
set "PY_URL=https://www.python.org/ftp/python/3.12.5/python-3.12.5-amd64.exe"
set "PY_INSTALLER=%TEMP%\python-3.12.5-amd64.exe"

echo   Download da python.org...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PY_URL%' -OutFile '%PY_INSTALLER%'" 2>&1
if errorlevel 1 (
    echo %RED%Errore download Python! Verifica la connessione internet.%RESET%
    pause
    exit /b 1
)

echo   Installazione Python (silenziosa)...
%PY_INSTALLER% /quiet InstallAllUsers=0 PrependPath=1 Include_test=0 Include_doc=0
if errorlevel 1 (
    echo %RED%Errore installazione Python%RESET%
    pause
    exit /b 1
)

echo   Aggiornamento PATH...
for /f "tokens=*" %%i in ('dir /s /b "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" 2^>nul') do set PYTHON_PATH=%%i
if defined PYTHON_PATH (
    set "PATH=%PYTHON_PATH%;%PATH%"
) else (
    echo %RED%Python installato ma non trovato nel PATH%RESET%
    echo   Prova a riavviare il CMD o esegui manualmente
    pause
    exit /b 1
)

python --version >nul 2>&1
if errorlevel 1 (
    echo %RED%Python non rilevato dopo installazione. Riavvia il computer e riprova.%RESET%
    pause
    exit /b 1
)

:PYTHON_OK
for /f "delims=" %%i in ('python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"') do set PY_VER=%%i
echo Python %PY_VER% trovato

:: ----- 2. CREATE VENV -----
if not exist "venv\" (
    echo [2/5] Creazione ambiente virtuale...
    python -m venv venv
    if errorlevel 1 (
        echo %RED%Errore creazione venv%RESET%
        pause
        exit /b 1
    )
) else (
    echo [2/5] Ambiente virtuale gia' esistente
)

call venv\Scripts\activate.bat
if errorlevel 1 (
    echo %RED%Errore attivazione venv%RESET%
    pause
    exit /b 1
)

:: ----- 3. UPGRADE PIP -----
echo [3/5] Aggiornamento pip...
python -m pip install --upgrade pip >nul 2>&1

:: ----- 4. INSTALL DEPENDENCIES -----
echo [4/5] Installazione dipendenze...

echo   Installazione PyTorch...
python -c "import torch; exit(0)" >nul 2>&1
if errorlevel 1 (
    python -m pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 2>&1 | findstr /V "WARNING\|already satisfied\|Successfully"
    if errorlevel 1 (
        echo   CUDA non disponibile, versione CPU...
        python -m pip install torch torchvision torchaudio 2>&1 | findstr /V "WARNING\|already satisfied\|Successfully"
    )
) else (
    echo   PyTorch gia' installato
)

echo   Installazione qwen-tts...
python -m pip install -e . --no-build-isolation 2>&1 | findstr /V "WARNING\|already satisfied"
if errorlevel 1 (
    echo %RED%Errore installazione qwen-tts%RESET%
    pause
    exit /b 1
)

echo   Installazione dipendenze server...
python -m pip install fastapi uvicorn python-multipart 2>&1 | findstr /V "WARNING\|already satisfied"
if errorlevel 1 (
    echo %RED%Errore installazione dipendenze server%RESET%
    pause
    exit /b 1
)

:: ----- 5. CREATE START SCRIPT -----
echo [5/5] Creazione script avvio...

for /f "delims=" %%i in ('python -c "import torch; print('cuda:0' if torch.cuda.is_available() else 'cpu')"') do set DEVICE=%%i
for /f "delims=" %%i in ('python -c "import torch; print('bfloat16' if torch.cuda.is_available() else 'float32')"') do set DTYPE=%%i
echo   Device: %DEVICE%  (%DTYPE%)

(
echo @echo off
echo title Qwen3-TTS Server
echo cd /d "%%~dp0"
echo call venv\Scripts\activate.bat
echo.
echo echo ========================================
echo echo  Qwen3-TTS API Server
echo echo  Device: %DEVICE%
echo echo ========================================
echo echo.
echo set HF_HOME=%%~dp0huggingface_cache
echo set HUGGINGFACE_HUB_CACHE=%%~dp0huggingface_cache\hub
echo.
echo python -m qwen_tts.server --models "cv=Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice" --host 0.0.0.0 --port 8000 --device %DEVICE% --dtype %DTYPE% --no-flash-attn
echo pause
) > start_qwen.bat

:: ----- OPTIONAL: CPU-ONLY START SCRIPT -----
(
echo @echo off
echo title Qwen3-TTS Server ^(CPU Mode^)
echo cd /d "%%~dp0"
echo call venv\Scripts\activate.bat
echo.
echo echo ========================================
echo echo  Qwen3-TTS API Server ^(CPU - 0.6B^)
echo echo ========================================
echo echo.
echo set HF_HOME=%%~dp0huggingface_cache
echo set HUGGINGFACE_HUB_CACHE=%%~dp0huggingface_cache\hub
echo.
echo python -m qwen_tts.server --models "cv=Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice" --host 0.0.0.0 --port 8000 --device cpu --dtype float32 --no-flash-attn
echo pause
) > start_qwen_cpu.bat

echo.
echo %GREEN%========================================%RESET%
echo %GREEN%  Installazione completata!%RESET%
echo %RED%  RIAVVIA IL COMPUTER se Python e' stato appena installato%RESET%
echo %GREEN%========================================%RESET%
echo.
echo  Ora fai doppio click su:
echo    start_qwen.bat      - modalita' GPU (se disponibile)
echo    start_qwen_cpu.bat  - modalita' CPU  (modello 0.6B)
echo.
echo  Server: http://0.0.0.0:8000
echo  POST /v1/tts/custom-voice  (text, model=cv, speaker=Vivian)
echo  POST /v1/tts/voice-design  (text, instruct=...)
echo.
echo  %YELLOW%NOTA: Il modello Qwen3-TTS (~7GB GPU / ~3GB CPU) viene scaricato
echo  automaticamente da HuggingFace al primo avvio.%RESET%
echo.
pause
