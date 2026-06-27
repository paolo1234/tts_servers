@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title OmniVoice TTS Server - Installer
color 0f

echo ========================================
echo   OmniVoice TTS Server - Installer
echo   uv + Python 3.11 isolato
echo   Auto-detection NVIDIA serie
echo ========================================
echo.

:: ----- 1. SCARICA uv (se non presente) -----
if not exist "uv.exe" (
    echo [1] Download uv...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip' -OutFile '%TEMP%\uv.zip'" 2>&1
    if errorlevel 1 (
        echo ERRORE: download uv fallito. Verifica connessione internet.
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
        echo ERRORE: uv.exe non trovato dopo estrazione
        pause
        exit /b 1
    )
    echo   uv pronto
) else (
    echo   uv gia' presente
)

:: ----- 2. INSTALLA PYTHON 3.11 -----
echo.
echo [2] Installazione Python 3.11...
uv python install 3.11
if errorlevel 1 (
    echo ERRORE: installazione Python 3.11 fallita
    pause
    exit /b 1
)
echo   Python 3.11 pronto

:: ----- 3. CREA VENV -----
echo.
echo [3] Creazione ambiente virtuale...
if exist ".venv\" (
    echo   Ambiente gia' esistente.
    set /p CONFIRM="Ricreare da zero? (s/N): "
    if /i "!CONFIRM!"=="s" (
        echo   Ricreazione...
        rmdir /s /q .venv
        uv venv --python 3.11 .venv
        if errorlevel 1 (
            echo ERRORE: creazione venv fallita
            pause
            exit /b 1
        )
    )
) else (
    uv venv --python 3.11 .venv
    if errorlevel 1 (
        echo ERRORE: creazione venv fallita
        pause
        exit /b 1
    )
)
if not exist ".venv\Scripts\activate.bat" (
    echo ERRORE: .venv non creato correttamente
    pause
    exit /b 1
)
call .venv\Scripts\activate.bat

:: ----- 4. RILEVA GPU -----
echo.
echo [4] Rilevamento scheda video NVIDIA...
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -File "..\scripts\detect_nvidia.ps1" 2^>nul') do set "%%i" 2>nul
if "%GPU_SERIES%"=="NONE" (
    echo   NVIDIA non rilevata. Versione CPU.
    set DEVICE=cpu
    set CUDA_VERSION=cpu
    set GPU_NAME=
) else (
    echo   GPU: %GPU_NAME%
    echo   Serie: %GPU_SERIES%
    echo   VRAM: %VRAM_MB% MB
    echo   Dispositivo: %DEVICE%
)

:: ----- 5. INSTALLA DIPENDENZE -----
echo.
echo [5] Installazione PyTorch...

if "%CUDA_VERSION%"=="cpu" goto :INSTALL_CPU_TORCH

echo   Tentativo %CUDA_VERSION%...
uv pip install torch==2.8.0 torchaudio==2.8.0 --extra-index-url https://download.pytorch.org/whl/%CUDA_VERSION% && goto :TORCH_OK

echo   Fallback cu124...
uv pip install torch torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 && goto :TORCH_OK

echo   Fallback cu121...
uv pip install torch torchaudio --extra-index-url https://download.pytorch.org/whl/cu121 && goto :TORCH_OK

echo   Fallback cu118...
uv pip install torch torchaudio --extra-index-url https://download.pytorch.org/whl/cu118 && goto :TORCH_OK

:INSTALL_CPU_TORCH
echo   Versione CPU...
uv pip install torch torchaudio
if errorlevel 1 (
    echo ERRORE: installazione PyTorch fallita
    pause
    exit /b 1
)
set DEVICE=cpu
goto :TORCH_OK

:TORCH_OK
echo   PyTorch installato

echo.
echo [6] Installazione OmniVoice e dipendenze server...
uv pip install omnivoice fastapi uvicorn[standard] soundfile flask-cors

if errorlevel 1 (
    echo   Tentativo da GitHub (ultima versione)...
    uv pip install "omnivoice @ git+https://github.com/k2-fsa/OmniVoice.git" fastapi uvicorn[standard] soundfile flask-cors
    if errorlevel 1 (
        echo ERRORE: installazione OmniVoice fallita
        pause
        exit /b 1
    )
)
echo   OmniVoice installato

:: ----- 6. CREA CARTELLE SUPPORT -----
echo.
echo [7] Creazione cartella speakers...
if not exist "speakers\" mkdir speakers
echo   Fatto. Metti i file .wav reference in 'speakers\'

:: ----- 7. VERIFICA -----
echo.
echo [8] Verifica installazione...
.venv\Scripts\python.exe -c "from omnivoice import OmniVoice; print('OmniVoice OK')" 2>nul
if errorlevel 1 (
    echo   ATTENZIONE: verifica OmniVoice fallita (potrebbe servire connessione internet al primo avvio)
) else (
    echo   OmniVoice verificato
)

cls
echo ========================================
echo   INSTALLAZIONE COMPLETATA!
echo ========================================
echo.
if not "%GPU_NAME%"=="" (
    echo  GPU: %GPU_NAME%  (%GPU_SERIES%)
    echo  VRAM: %VRAM_MB% MB
)
echo.
echo  Esegui: 2 - START.bat
echo.
pause
