param(
    [switch]$Json
)

$DEFAULT = @{
    device = "cpu"
    dtype = "float32"
    flash_attn = $false
    cuda_version = "cpu"
    series = "NONE"
    gpu_name = ""
    vram_mb = 0
    model_size = "0.6B"
    cc = ""
}

try {
    $nvidia = Get-Command "nvidia-smi" -ErrorAction Stop
    $output = & nvidia-smi --query-gpu=name,compute_cap,memory.total,driver_version --format=csv,noheader,nounits 2>$null
    if (-not $output) { throw "no output" }
    $parts = $output[0] -split ',' | ForEach-Object { $_.Trim() }
    $gpuName = $parts[0]
    $cc = $parts[1]
    $vram = [int]($parts[2])
    $driver = $parts[3]

    $ccMajor = [int]($cc -split '\.')[0]

    $device = "cuda:0"
    $dtype = "float32"
    $flashAttn = $false
    $cudaVer = "cu124"
    $series = "OTHER"
    $modelSize = "1.7B"

    if ($ccMajor -ge 8) {
        $dtype = "bfloat16"
        $flashAttn = $true
        $cudaVer = "cu124"
        $series = "RTX30PLUS"
    } elseif ($ccMajor -eq 7) {
        $dtype = "float16"
        $flashAttn = $false
        $cudaVer = "cu124"
        $series = "RTX20"
        if ($cc -like "7.5*") { $series = "TURING" }
        elseif ($cc -like "7.0*") { $series = "VOLTA" }
    } elseif ($ccMajor -eq 6) {
        $dtype = "float16"
        $flashAttn = $false
        $cudaVer = "cu124"
        $series = "PASCAL"
    } elseif ($ccMajor -eq 5) {
        $dtype = "float32"
        $flashAttn = $false
        $cudaVer = "cu118"
        $series = "MAXWELL"
    } else {
        $device = "cpu"
        $dtype = "float32"
        $flashAttn = $false
        $cudaVer = "cpu"
        $series = "OLD"
    }

    if ($vram -lt 8000) { $modelSize = "0.6B" }

    $result = @{
        device = $device
        dtype = $dtype
        flash_attn = $flashAttn
        cuda_version = $cudaVer
        series = $series
        gpu_name = $gpuName
        vram_mb = $vram
        model_size = $modelSize
        cc = $cc
        driver = $driver
    }

    if ($Json) {
        Write-Output ($result | ConvertTo-Json -Compress)
    } else {
        Write-Output "GPU_NAME=$($result.gpu_name)"
        Write-Output "GPU_SERIES=$($result.series)"
        Write-Output "COMPUTE_CAP=$($result.cc)"
        Write-Output "VRAM_MB=$($result.vram_mb)"
        Write-Output "DEVICE=$($result.device)"
        Write-Output "DTYPE=$($result.dtype)"
        Write-Output "FLASH_ATTN=$($result.flash_attn)"
        Write-Output "CUDA_VERSION=$($result.cuda_version)"
        Write-Output "MODEL_SIZE=$($result.model_size)"
    }
} catch {
    if ($Json) {
        Write-Output ($DEFAULT | ConvertTo-Json -Compress)
    } else {
        Write-Output "GPU_NAME="
        Write-Output "GPU_SERIES=NONE"
        Write-Output "COMPUTE_CAP="
        Write-Output "VRAM_MB=0"
        Write-Output "DEVICE=cpu"
        Write-Output "DTYPE=float32"
        Write-Output "FLASH_ATTN=False"
        Write-Output "CUDA_VERSION=cpu"
        Write-Output "MODEL_SIZE=0.6B"
    }
}
