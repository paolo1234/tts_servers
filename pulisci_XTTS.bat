@echo off
echo Pulizia ambiente XTTSv2 in corso...

if exist "XTTSv2\.venv"    rmdir /s /q "XTTSv2\.venv"
if exist "XTTSv2\venv"     rmdir /s /q "XTTSv2\venv"
if exist "XTTSv2\uv.exe"   del "XTTSv2\uv.exe"
if exist "XTTSv2\uvx.exe"  del "XTTSv2\uvx.exe"
if exist "XTTSv2\uvw.exe"  del "XTTSv2\uvw.exe"
if exist "XTTSv2\huggingface_cache" rmdir /s /q "XTTSv2\huggingface_cache"
if exist "XTTSv2\assets"   rmdir /s /q "XTTSv2\assets"

echo Fatto. L'ambiente XTTSv2 è stato resettato.
pause
