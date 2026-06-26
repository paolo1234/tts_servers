@echo off
echo Pulizia in corso...

:: XTTSv2
if exist "XTTSv2\.venv"    rmdir /s /q "XTTSv2\.venv"
if exist "XTTSv2\venv"     rmdir /s /q "XTTSv2\venv"
if exist "XTTSv2\uv.exe"   del "XTTSv2\uv.exe"
if exist "XTTSv2\uvx.exe"  del "XTTSv2\uvx.exe"
if exist "XTTSv2\uvw.exe"  del "XTTSv2\uvw.exe"
if exist "XTTSv2\start_server.bat" del "XTTSv2\start_server.bat"
if exist "XTTSv2\huggingface_cache" rmdir /s /q "XTTSv2\huggingface_cache"
if exist "XTTSv2\assets"   rmdir /s /q "XTTSv2\assets"
if exist "XTTSv2\python311" rmdir /s /q "XTTSv2\python311"

:: Qwen3-TTS
if exist "Qwen3-TTS\.venv"  rmdir /s /q "Qwen3-TTS\.venv"
if exist "Qwen3-TTS\venv"   rmdir /s /q "Qwen3-TTS\venv"
if exist "Qwen3-TTS\uv.exe" del "Qwen3-TTS\uv.exe"
if exist "Qwen3-TTS\uvx.exe" del "Qwen3-TTS\uvx.exe"
if exist "Qwen3-TTS\2 - START.bat" del "Qwen3-TTS\2 - START.bat"
if exist "Qwen3-TTS\2 - START GPU.bat" del "Qwen3-TTS\2 - START GPU.bat"
if exist "Qwen3-TTS\2 - START CPU.bat" del "Qwen3-TTS\2 - START CPU.bat"
if exist "Qwen3-TTS\huggingface_cache" rmdir /s /q "Qwen3-TTS\huggingface_cache"

:: scripts condivisi
if exist "scripts\detect_nvidia.ps1" del "scripts\detect_nvidia.ps1"
if exist "scripts\detect_nvidia.py"  del "scripts\detect_nvidia.py"
if exist "scripts\detect_nvidia.bat" del "scripts\detect_nvidia.bat"

echo Fatto. Cartella pronta per la condivisione.
pause
