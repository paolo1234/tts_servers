@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Qwen3-TTS Server - Installer
color 0f

echo ========================================
echo   Qwen3-TTS TTS Server
echo   uv + Python 3.12 isolato
echo   Auto-detection NVIDIA serie
echo ========================================
echo.

:: ----- 1. SCARICA uv -----
if not exist "uv.exe" (
    echo [1] Download uv...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip' -OutFile '%TEMP%\uv.zip'" 2>&1
    if errorlevel 1 (
        echo ERRORE: download uv fallito. Verifica connessione.
        pause
        exit /b 1
    )
    powershell -Command "Expand-Archive -Path '%TEMP%\uv.zip' -DestinationPath '%~dp0'" 2>&1
    if errorlevel 1 (
        echo ERRORE: estrazione uv fallita
        pause
        exit /b 1
    )
    del "%TEMP%\uv.zip" 2>nul
    if not exist "uv.exe" (
        echo ERRORE: uv.exe non trovato
        pause
        exit /b 1
    )
)

:: ----- 2. INSTALLA PYTHON 3.12 -----
echo.
echo [2] Installazione Python 3.12...
uv python install 3.12
if errorlevel 1 (
    echo ERRORE: installazione Python 3.12 fallita
    pause
    exit /b 1
)

:: ----- 3. CREA VENV -----
echo.
echo [3] Creazione ambiente virtuale...
if exist ".venv\" (
    echo   Ambiente gia' esistente.
    set /p CONFIRM="Ricreare da zero? (s/N): "
    if /i "!CONFIRM!"=="s" (
        echo   Ricreazione...
        rmdir /s /q .venv
        uv venv --python 3.12 .venv
        if errorlevel 1 (
            echo ERRORE: creazione venv fallita
            pause
            exit /b 1
        )
    )
) else (
    uv venv --python 3.12 .venv
    if errorlevel 1 (
        echo ERRORE: creazione venv fallita
        pause
        exit /b 1
    )
)
if not exist ".venv\Scripts\activate.bat" (
    echo ERRORE: .venv non creato
    pause
    exit /b 1
)
call .venv\Scripts\activate.bat

:: ----- 4. RILEVA GPU -----
echo.
echo [4] Rilevamento scheda video NVIDIA...
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -File "..\scripts\detect_nvidia.ps1" 2^>nul') do set "%%i" 2>nul
if "%GPU_SERIES%"=="NONE" (
    echo   NVIDIA non rilevata. Verra' installata versione CPU.
    set DEVICE=cpu
    set DTYPE=float32
    set CUDA_VERSION=cpu
    set FLASH_ATTN=no-flash-attn
    set GPU_NAME=
    set GPU_SERIES=NONE
    set MODEL_SIZE=0.6B
) else (
    echo   GPU: %GPU_NAME%
    echo   Serie: %GPU_SERIES%
    echo   VRAM: %VRAM_MB% MB
    echo   Dispositivo: %DEVICE%
    echo   Precisione: %DTYPE%
    echo   Flash Attention: %FLASH_ATTN%
)

:: ----- 5. INSTALLA PyTorch (con fallback) -----
echo.
echo [5] Installazione PyTorch...

if "%CUDA_VERSION%"=="cpu" goto :INSTALL_CPU_TORCH

echo   Tentativo %CUDA_VERSION%...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/%CUDA_VERSION%
if !errorlevel! equ 0 goto :TORCH_OK

echo   Fallback cu124...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124
if !errorlevel! equ 0 (
    set CUDA_VERSION=cu124
    goto :TORCH_OK
)

echo   Fallback cu121...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121
if !errorlevel! equ 0 (
    set CUDA_VERSION=cu121
    goto :TORCH_OK
)

echo   Fallback cu118...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118
if !errorlevel! equ 0 (
    set CUDA_VERSION=cu118
    goto :TORCH_OK
)

:INSTALL_CPU_TORCH
echo   Versione CPU...
uv pip install torch torchvision torchaudio
if errorlevel 1 (
    echo ERRORE: installazione PyTorch fallita
    pause
    exit /b 1
)
set DEVICE=cpu
set DTYPE=float32
set FLASH_ATTN=no-flash-attn

:TORCH_OK
echo   PyTorch installato con %CUDA_VERSION%

:: ----- 6. INSTALLA QWEN-TTS + SERVER -----
echo.
echo [6] Installazione qwen-tts...
uv pip install -e .
if errorlevel 1 (
    echo ERRORE: installazione qwen-tts
    pause
    exit /b 1
)

uv pip install fastapi uvicorn python-multipart
if errorlevel 1 (
    echo ERRORE: installazione server
    pause
    exit /b 1
)

:: ----- 7. VERIFICA DISPOSITIVO ATTUALE -----
echo.
echo [7] Verifica dispositivo...
set DETECTED_DEVICE=cpu
set DETECTED_DTYPE=float32
set DETECTED_CUDA=cpu
for /f "tokens=1,2,3 delims=|" %%a in ('uv run python -c "import torch; d='cuda:0' if torch.cuda.is_available() else 'cpu'; t='bfloat16' if torch.cuda.is_available() and torch.cuda.get_device_capability(0)[0]>=8 else 'float16' if torch.cuda.is_available() else 'float32'; c='cu124' if torch.cuda.is_available() else 'cpu'; print(f'{d}|{t}|{c}')" 2^>nul') do (
    set DETECTED_DEVICE=%%a
    set DETECTED_DTYPE=%%b
    set DETECTED_CUDA=%%c
)
echo   Dispositivo: !DETECTED_DEVICE! (!DETECTED_DTYPE!)

:: Se la GPU rilevata e' piu' capace di quanto ipotizzato, aggiorna
if not "!DETECTED_DEVICE!"=="cpu" (
    if "!DEVICE!"=="cpu" set DEVICE=!DETECTED_DEVICE!
    if "!DTYPE!"=="float32" set DTYPE=!DETECTED_DTYPE!
)

:: ----- 8. GENERA START SCRIPTS -----
echo.
echo [8] Generazione script avvio...

:: GPU START script (auto-detection runtime)
(
echo @echo off
echo title Qwen3-TTS Server
echo cd /d "%%~dp0"
echo set HF_HOME=%%~dp0huggingface_cache
echo set HUGGINGFACE_HUB_CACHE=%%~dp0huggingface_cache\hub
echo.
echo :: Auto-detect GPU al runtime
echo for /f "tokens=1,2 delims=^|" %%%%a in ('uv run python -c "import torch; d='cuda:0' if torch.cuda.is_available() else 'cpu'; t='bfloat16' if torch.cuda.is_available() and torch.cuda.get_device_capability(0)[0]^>=8 else 'float16' if torch.cuda.is_available() else 'float32'; print(f'{d}^{|{t}')" 2^^^^nul') do (
echo     set DEVICE=%%%%a
echo     set DTYPE=%%%%b
echo )
echo if "%%DEVICE%%"=="" set DEVICE=%DEVICE%
echo if "%%DTYPE%%"=="" set DTYPE=%DTYPE%
echo.
echo echo [Qwen3-TTS] Device: %%DEVICE%% ^(%%DTYPE%%^)
echo echo [Qwen3-TTS] Server: http://0.0.0.0:8000
echo.
echo uv run python -m qwen_tts.server --models "cv=Qwen/Qwen3-TTS-12Hz-%MODEL_SIZE%-CustomVoice" --host 0.0.0.0 --port 8000 --device %%DEVICE%% --dtype %%DTYPE%% --%FLASH_ATTN%
echo pause
) > "2 - START GPU.bat"

:: CPU START script (forced CPU)
(
echo @echo off
echo title Qwen3-TTS Server ^(CPU^)
echo cd /d "%%~dp0"
echo set HF_HOME=%%~dp0huggingface_cache
echo set HUGGINGFACE_HUB_CACHE=%%~dp0huggingface_cache\hub
echo.
echo echo [Qwen3-TTS] Device: cpu
echo echo [Qwen3-TTS] Server: http://0.0.0.0:8000
echo echo [Qwen3-TTS] Modello leggero 0.6B per CPU
echo.
echo uv run python -m qwen_tts.server --models "cv=Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice" --host 0.0.0.0 --port 8000 --device cpu --dtype float32 --no-flash-attn
echo pause
) > "2 - START CPU.bat"

:: AUTO START script (smart auto-detect)
(
echo @echo off
echo title Qwen3-TTS Server ^(Auto^)
echo cd /d "%%~dp0"
echo set HF_HOME=%%~dp0huggingface_cache
echo set HUGGINGFACE_HUB_CACHE=%%~dp0huggingface_cache\hub
echo.
echo :: Rilevamento automatico GPU
echo for /f "tokens=1,2 delims=^|" %%%%a in ('uv run python -c "import torch; d='cuda:0' if torch.cuda.is_available() else 'cpu'; t='bfloat16' if torch.cuda.is_available() and torch.cuda.get_device_capability(0)[0]^>=8 else 'float16' if torch.cuda.is_available() else 'float32'; print(f'{d}^{|{t}')" 2^^^^nul') do (
echo     set DEVICE=%%%%a
echo     set DTYPE=%%%%b
echo )
echo if "%%DEVICE%%"=="" set DEVICE=cpu
echo if "%%DTYPE%%"=="" set DTYPE=float32
echo.
echo :: Scegli modello in base alla VRAM (se GPU rilevata)
echo set MODEL=cv=Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice
echo if not "%%DEVICE%%"=="cpu" (
echo     for /f "tokens=*" %%%%v in ('uv run python -c "import torch; v=torch.cuda.get_device_properties(0).total_memory//1024//1024; print('1.7B' if v^>=8000 else '0.6B')" 2^^^^nul') do set MODEL_SIZE=%%%%v
echo     if "%%MODEL_SIZE%%"=="" set MODEL_SIZE=%MODEL_SIZE%
echo     set MODEL=cv=Qwen/Qwen3-TTS-12Hz-%%MODEL_SIZE%%-CustomVoice
echo )
echo.
echo echo [Qwen3-TTS] Device: %%DEVICE%% ^(%%DTYPE%%^)  Modello: %%MODEL%%
echo echo [Qwen3-TTS] Server: http://0.0.0.0:8000
echo.
echo uv run python -m qwen_tts.server --models "%%MODEL%%" --host 0.0.0.0 --port 8000 --device %%DEVICE%% --dtype %%DTYPE%% --%FLASH_ATTN%
echo pause
) > "2 - START.bat"

cls
echo ========================================
echo   INSTALLAZIONE COMPLETATA!
echo ========================================
echo.
echo  GPU (%GPU_SERIES%): 2 - START GPU.bat
echo  CPU:             2 - START CPU.bat
echo  AUTO:            2 - START.bat
echo.
echo  GPU: %GPU_NAME%
echo  Device: %DEVICE%  |  Dtype: %DTYPE%
echo  Flash Attn: %FLASH_ATTN%  |  Modello: %MODEL_SIZE%
echo.
echo  Server: http://localhost:8000
echo.
echo  Il modello (~5-7GB) si scarica al primo avvio.
echo.
pause
