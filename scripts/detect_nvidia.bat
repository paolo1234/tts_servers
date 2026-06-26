@echo off
setlocal enabledelayedexpansion

:: ==========================================
:: detect_nvidia.bat - GPU Detection Utility
:: ==========================================
:: Sets these environment variables for the caller:
::   GPU_NAME, GPU_SERIES, VRAM_MB, DEVICE,
::   DTYPE, FLASH_ATTN, CUDA_VERSION, MODEL_SIZE
:: ==========================================

set GPU_NAME=
set GPU_SERIES=NONE
set VRAM_MB=0
set DEVICE=cpu
set DTYPE=float32
set FLASH_ATTN=no-flash-attn
set CUDA_VERSION=cpu
set MODEL_SIZE=0.6B

:: Try nvidia-smi
where nvidia-smi >nul 2>nul
if errorlevel 1 goto :NO_GPU

for /f "tokens=*" %%a in ('nvidia-smi --query-gpu^=name --format^=csv^,noheader 2^>nul') do set "GPU_NAME=%%a"
if "%GPU_NAME%"=="" goto :NO_GPU

for /f "tokens=*" %%a in ('nvidia-smi --query-gpu^=compute_cap --format^=csv^,noheader^,nounits 2^>nul') do set "COMPUTE_CAP=%%a"
for /f "tokens=*" %%a in ('nvidia-smi --query-gpu^=memory.total --format^=csv^,noheader^,nounits 2^>nul') do set "VRAM_MB=%%a"

set "GPU_NAME=%GPU_NAME: =%"
if "%VRAM_MB%"=="" set VRAM_MB=0

set DEVICE=cuda:0
set DTYPE=float32
set FLASH_ATTN=no-flash-attn
set CUDA_VERSION=cu124
set GPU_SERIES=OTHER
set MODEL_SIZE=1.7B

if %VRAM_MB% LSS 8000 set MODEL_SIZE=0.6B

echo %GPU_NAME% | findstr /i "RTX 50" >nul
if !errorlevel! equ 0 (
    set DTYPE=bfloat16
    set FLASH_ATTN=flash-attn
    set GPU_SERIES=RTX50
    goto :DONE
)

echo %GPU_NAME% | findstr /i "RTX 40" >nul
if !errorlevel! equ 0 (
    set DTYPE=bfloat16
    set FLASH_ATTN=flash-attn
    set GPU_SERIES=RTX40
    goto :DONE
)

echo %GPU_NAME% | findstr /i "RTX 30" >nul
if !errorlevel! equ 0 (
    set DTYPE=bfloat16
    set FLASH_ATTN=flash-attn
    set GPU_SERIES=RTX30
    goto :DONE
)

echo %GPU_NAME% | findstr /i "RTX 20" >nul
if !errorlevel! equ 0 (
    set DTYPE=float16
    set GPU_SERIES=RTX20
    goto :DONE
)

echo %GPU_NAME% | findstr /i "GTX 16" >nul
if !errorlevel! equ 0 (
    set DTYPE=float16
    set GPU_SERIES=GTX16
    goto :DONE
)

echo %GPU_NAME% | findstr /i "GTX 10" >nul
if !errorlevel! equ 0 (
    set DTYPE=float16
    set GPU_SERIES=GTX10
    goto :DONE
)

echo %GPU_NAME% | findstr /i "GTX 9" >nul
if !errorlevel! equ 0 (
    set DTYPE=float32
    set CUDA_VERSION=cu118
    set GPU_SERIES=GTX9
    goto :DONE
)

echo %GPU_NAME% | findstr /i "GTX 7" >nul
if !errorlevel! equ 0 (
    set DEVICE=cpu
    set DTYPE=float32
    set CUDA_VERSION=cpu
    set GPU_SERIES=GTX7
    goto :DONE
)

if not "%COMPUTE_CAP%"=="" (
    set "CC_CLEAN=%COMPUTE_CAP:.=%"
    if "!CC_CLEAN:~0,1!" GEQ "8" (
        set DTYPE=bfloat16
        set FLASH_ATTN=flash-attn
        set GPU_SERIES=MODERN
    )
)

echo %GPU_NAME% | findstr /i "A100 H100 H200 B100 B200" >nul
if !errorlevel! equ 0 (
    set DTYPE=bfloat16
    set FLASH_ATTN=flash-attn
    set GPU_SERIES=HPC
)
echo %GPU_NAME% | findstr /i "V100" >nul
if !errorlevel! equ 0 (
    set DTYPE=float16
    set GPU_SERIES=VOLTA
)
echo %GPU_NAME% | findstr /i "Quadro RTX" >nul
if !errorlevel! equ 0 (
    set DTYPE=bfloat16
    set GPU_SERIES=QUADRO_RTX
)

:DONE
goto :OUTPUT

:NO_GPU
set GPU_SERIES=NONE
set DEVICE=cpu
set DTYPE=float32
set FLASH_ATTN=no-flash-attn
set CUDA_VERSION=cpu
set MODEL_SIZE=0.6B

:OUTPUT
endlocal & (
    set "GPU_NAME=%GPU_NAME%"
    set "GPU_SERIES=%GPU_SERIES%"
    set "VRAM_MB=%VRAM_MB%"
    set "DEVICE=%DEVICE%"
    set "DTYPE=%DTYPE%"
    set "FLASH_ATTN=%FLASH_ATTN%"
    set "CUDA_VERSION=%CUDA_VERSION%"
    set "MODEL_SIZE=%MODEL_SIZE%"
)
