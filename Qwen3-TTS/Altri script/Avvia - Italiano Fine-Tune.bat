@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set HF_HOME=%~dp0huggingface_cache
set HUGGINGFACE_HUB_CACHE=%~dp0huggingface_cache\hub

:: Auto-detect GPU con precisione appropriata
for /f "tokens=1,2 delims=|" %%a in ('uv run python -c "import torch; d='cuda:0' if torch.cuda.is_available() else 'cpu'; t='bfloat16' if torch.cuda.is_available() and torch.cuda.get_device_capability(0)[0]>=8 else 'float16' if torch.cuda.is_available() else 'float32'; print(f'{d}|{t}')" 2^>nul') do (
    set DEVICE=%%a
    set DTYPE=%%b
)
if "%DEVICE%"=="" set DEVICE=cpu
if "%DTYPE%"=="" set DTYPE=float32

:: Flash attention solo per GPU moderne (CC >= 8)
set FLASH=--no-flash-attn
if not "%DEVICE%"=="cpu" (
    for /f %%c in ('uv run python -c "import torch; print(torch.cuda.get_device_capability(0)[0])" 2^>nul') do if %%c geq 8 set FLASH=--flash-attn
)

echo [Qwen3-TTS] GPU: %DEVICE%  Precisione: %DTYPE%  %FLASH%
echo [Qwen3-TTS] Modello: Italiano (fine-tuned su 115.000 campioni)
uv run python -m qwen_tts.server --models "it=Aynursusuz/Qwen-TTS-Best-Model" --host 0.0.0.0 --port 8000 --device %DEVICE% --dtype %DTYPE% %FLASH%

pause
