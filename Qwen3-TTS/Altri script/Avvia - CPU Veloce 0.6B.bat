@echo off
cd /d "%~dp0"

set HF_HOME=%~dp0huggingface_cache
set HUGGINGFACE_HUB_CACHE=%~dp0huggingface_cache\hub

echo [Qwen3-TTS] CPU Mode - Modello leggero 0.6B
echo [Qwen3-TTS] Server: http://0.0.0.0:8000
uv run python -m qwen_tts.server --models "cv=Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice" --host 0.0.0.0 --port 8000 --device cpu --dtype float32 --no-flash-attn

pause
