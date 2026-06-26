@echo off
echo Pulizia ambiente Qwen3-TTS in corso...

if exist "Qwen3-TTS\.venv"  rmdir /s /q "Qwen3-TTS\.venv"
if exist "Qwen3-TTS\venv"   rmdir /s /q "Qwen3-TTS\venv"
if exist "Qwen3-TTS\uv.exe" del "Qwen3-TTS\uv.exe"
if exist "Qwen3-TTS\uvx.exe" del "Qwen3-TTS\uvx.exe"
if exist "Qwen3-TTS\huggingface_cache" rmdir /s /q "Qwen3-TTS\huggingface_cache"

echo Fatto. L'ambiente Qwen3-TTS è stato resettato.
pause
