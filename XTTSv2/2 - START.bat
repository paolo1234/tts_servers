@echo off
title XTTSv2 TTS Server
cd /d "%~dp0"
set HF_HOME=%~dp0huggingface_cache
set HUGGINGFACE_HUB_CACHE=%~dp0huggingface_cache\hub
set TRANSFORMERS_CACHE=%~dp0huggingface_cache\hub
set HF_DATASETS_CACHE=%~dp0huggingface_cache\hub

echo ========================================
echo  Avvio XTTSv2 Server...
echo  Attendere il caricamento del modello
echo  (Primo avvio: ~2GB da scaricare)
echo ========================================
echo.
if not exist ".venv\Scripts\python.exe" (
    echo [ERRORE CRITICO] L'ambiente virtuale non e' stato trovato!
    echo Devi prima eseguire "1 - INSTALL.bat" e completare l'installazione.
    pause
    exit /b 1
)

.venv\Scripts\python.exe -c "import torch" 2>nul
if errorlevel 1 (
    echo [ERRORE CRITICO] PyTorch non e' stato installato correttamente.
    echo L'installazione precedente ("1 - INSTALL.bat") e' fallita.
    echo Riprova ad eseguire "1 - INSTALL.bat" assicurandoti di avere connessione internet.
    pause
    exit /b 1
)

.venv\Scripts\python.exe xtts_api.py --host 0.0.0.0 --port 8020 --preload
pause
