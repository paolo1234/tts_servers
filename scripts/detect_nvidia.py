import subprocess
import json
import sys
import re

def get_gpu_info():
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,compute_cap,memory.total,driver_version",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        lines = result.stdout.strip().split('\n')
        gpus = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            parts = [p.strip() for p in line.split(',')]
            name = parts[0]
            cc = parts[1] if len(parts) > 1 else ""
            memory = parts[2] if len(parts) > 2 else "0"
            driver = parts[3] if len(parts) > 3 else "unknown"
            try:
                memory_mb = int(memory)
            except ValueError:
                memory_mb = 0
            gpus.append({
                "name": name,
                "compute_cap": cc,
                "memory_mb": memory_mb,
                "driver_version": driver
            })
        return gpus
    except Exception:
        return None


def get_recommendations(gpu_info):
    if gpu_info is None:
        return {
            "device": "cpu", "cuda_version": "cpu", "dtype": "float32",
            "flash_attn": False, "series": "NONE", "vram_mb": 0,
            "gpu_name": "", "model_size": "0.6B", "cc": ""
        }

    gpu = gpu_info[0]
    name = gpu["name"]
    cc = gpu["compute_cap"]
    vram = gpu["memory_mb"]

    try:
        cc_major = int(cc.split('.')[0])
    except (ValueError, IndexError):
        cc_major = 0

    device = "cuda:0"
    dtype = "float32"
    flash_attn = False
    cuda_version = "cu124"
    series = "OTHER"
    model_size = "1.7B" if vram >= 8000 else "0.6B"

    if cc_major >= 8:
        dtype = "bfloat16"
        flash_attn = True
        series = "RTX30PLUS"
    elif cc_major == 7:
        dtype = "float16"
        flash_attn = False
        series = "TURING" if cc.startswith("7.5") else "VOLTA"
    elif cc_major == 6:
        dtype = "float16"
        flash_attn = False
        series = "PASCAL"
    elif cc_major == 5:
        dtype = "float32"
        flash_attn = False
        cuda_version = "cu118"
        series = "MAXWELL"
    else:
        device = "cpu"
        dtype = "float32"
        flash_attn = False
        cuda_version = "cpu"
        series = "OLD"

    return {
        "device": device,
        "cuda_version": cuda_version,
        "dtype": dtype,
        "flash_attn": flash_attn,
        "series": series,
        "vram_mb": vram,
        "gpu_name": name,
        "model_size": model_size,
        "cc": cc,
        "n_gpus": len(gpu_info)
    }


if __name__ == "__main__":
    gpus = get_gpu_info()
    recs = get_recommendations(gpus)
    if "--json" in sys.argv:
        print(json.dumps(recs))
    else:
        for k, v in recs.items():
            print(f"{k.upper()}={v}")
