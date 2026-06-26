@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title XTTSv2 TTS Server - Installer
color 0f

echo ========================================
echo   XTTSv2 TTS Server - Installer
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
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/%CUDA_VERSION%
if !errorlevel! equ 0 goto :TORCH_OK

echo   Fallback cu124...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124
if !errorlevel! equ 0 goto :TORCH_OK

echo   Fallback cu121...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121
if !errorlevel! equ 0 goto :TORCH_OK

echo   Fallback cu118...
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118
if !errorlevel! equ 0 goto :TORCH_OK

:INSTALL_CPU_TORCH
echo   Versione CPU...
uv pip install torch torchvision torchaudio
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
echo [6] Installazione TTS + Flask + CORS...
uv pip install "TTS==0.22.0" Flask flask-cors
if errorlevel 1 (
    echo   Tenta versione recente...
    uv pip install TTS Flask flask-cors
    if errorlevel 1 (
        echo ERRORE: installazione TTS fallita
        pause
        exit /b 1
    )
)
echo   Fix compatibilita' transformers...
uv pip install "transformers==4.38.2" >nul 2>&1

:: ----- 6. VERIFICA REFERENCE WAV -----
echo.
echo [7] Verifica file audio...
set REF_OK=1
for %%f in ("isabella_ref.wav" "giuseppe_ref.wav" "elsa_ref.wav" "diego_ref.wav") do (
    if not exist "%%~f" (
        echo   ATTENZIONE: %%~f non trovato!
        set REF_OK=0
    )
)
if !REF_OK!==1 echo   Ok

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
echo.
if !REF_OK!==0 (
 echo  Mancano file .wav di riferimento!
 echo.
)
pause
