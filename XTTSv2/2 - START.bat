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
uv run python xtts_api.py --host 0.0.0.0 --port 8020 --preload
pause
