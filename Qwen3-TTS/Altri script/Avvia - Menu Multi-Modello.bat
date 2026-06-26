@echo off
setlocal
cd /d "%~dp0"

:MENU
cls
set choice=
set MODELS=
set DEVICE=
set DTYPE=
echo.
echo  ===========================================
echo     QWEN3-TTS API - Multi-Model
echo  ===========================================
echo   Seleziona quali modelli caricare
echo   (consiglio: 3 modelli ~ 21GB RAM)
echo.
echo   [1] Solo CustomVoice (leggero, 7GB)
echo   [2] Solo VoiceDesign (leggero, 7GB)
echo   [3] Solo Italiano Fine-Tune (leggero, 7GB)
echo   [4] CustomVoice + VoiceDesign (14GB)
echo   [5] TUTTI e 3 (21GB)
echo.
echo   [A] Avvia ultima configurazione
echo.
echo  ===========================================
set /p choice="Scegli [1-5/A]: "

if "%choice%"=="1" set MODELS=cv=Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice
if "%choice%"=="2" set MODELS=vd=Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign
if "%choice%"=="3" set MODELS=it=Aynursusuz/Qwen-TTS-Best-Model
if "%choice%"=="4" set MODELS=cv=Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice,vd=Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign
if "%choice%"=="5" set MODELS=cv=Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice,vd=Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign,it=Aynursusuz/Qwen-TTS-Best-Model
if "%choice%"=="A" (
    if exist "last_models.txt" (
        set /p MODELS=<last_models.txt
    ) else (
        echo Nessuna configurazione salvata.
        timeout /t 2 >nul
        goto MENU
    )
)
if not defined MODELS goto MENU
echo !MODELS!> last_models.txt

:DEVICE
cls
set dev=
echo.
echo  ===========================================
echo     Dispositivo
echo  ===========================================
echo.
echo   [1] CPU
echo   [2] GPU Auto-detect (NVIDIA)
echo   [3] Intel Arc A580 (DirectML, solo 1 modello)
echo.
set /p dev="Scegli [1/2/3]: "

if "%dev%"=="1" (
    set DEVICE=cpu
    set DTYPE=float32
) else if "%dev%"=="2" (
    :: Auto-detect GPU
    for /f "tokens=1,2 delims=|" %%a in ('uv run python -c "import torch; d='cuda:0' if torch.cuda.is_available() else 'cpu'; t='bfloat16' if torch.cuda.is_available() and torch.cuda.get_device_capability(0)[0]>=8 else 'float16' if torch.cuda.is_available() else 'float32'; print(f'{d}|{t}')" 2^>nul') do (
        set DEVICE=%%a
        set DTYPE=%%b
    )
    if "!DEVICE!"=="" set DEVICE=cpu
    if "!DTYPE!"=="" set DTYPE=float32
    echo   Rilevato: !DEVICE! (!DTYPE!)
    timeout /t 2 >nul
) else if "%dev%"=="3" (
    set DEVICE=directml:0
    set DTYPE=float16
    echo ATTENZIONE: DirectML richiede installazione manuale di torch-directml.
    echo Usa: uv pip install torch-directml
    timeout /t 3 >nul
) else (
    goto DEVICE
)

set HF_HOME=%~dp0huggingface_cache
set HUGGINGFACE_HUB_CACHE=%~dp0huggingface_cache\hub

:: Flash attention solo per GPU moderne (CC >= 8)
set FLASH=--no-flash-attn
if not "%DEVICE%"=="cpu" (
    for /f %%c in ('uv run python -c "import torch; print(torch.cuda.get_device_capability(0)[0])" 2^>nul') do if %%c geq 8 set FLASH=--flash-attn
)

echo.
echo  ===========================================
echo   Avvio server multi-modello...
echo.
echo   Usa ?model=NOME nelle richieste
echo   (es: model=cv, model=vd, model=it)
echo.
echo   GET  /health
echo   GET  /v1/models
echo   POST /v1/tts/custom-voice  (modelli: cv, it)
echo   POST /v1/tts/voice-design  (modelli: vd)
echo   POST /v1/tts/voice-clone   (modelli: nessuno senza Base)
echo  ===========================================
echo.

uv run python -m qwen_tts.server --models "%MODELS%" --host 0.0.0.0 --port 8000 --device %DEVICE% --dtype %DTYPE% %FLASH%

pause
