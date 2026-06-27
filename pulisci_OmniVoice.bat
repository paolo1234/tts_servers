@echo off
echo Pulizia ambiente OmniVoice in corso...

if exist "OmniVoice\.venv"  rmdir /s /q "OmniVoice\.venv"
if exist "OmniVoice\venv"   rmdir /s /q "OmniVoice\venv"
if exist "OmniVoice\uv.exe" del "OmniVoice\uv.exe"
if exist "OmniVoice\uvx.exe" del "OmniVoice\uvx.exe"
if exist "OmniVoice\huggingface_cache" rmdir /s /q "OmniVoice\huggingface_cache"

echo Fatto. L'ambiente OmniVoice e' stato resettato.
pause
