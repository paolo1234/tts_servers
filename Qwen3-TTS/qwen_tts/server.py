# coding=utf-8
import argparse
import atexit
import io
import os
import subprocess
import sys
import tempfile
import traceback
from typing import Any, Dict, List, Optional

import numpy as np
import soundfile as sf
import torch
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response

from . import Qwen3TTSModel


def auto_detect_device(user_device: str, user_dtype: str, user_flash_attn: bool):
    if user_device.startswith("directml"):
        return user_device, user_dtype, user_flash_attn

    if user_device == "cpu" or not torch.cuda.is_available():
        return "cpu", "float32", False

    num_gpus = torch.cuda.device_count()
    gpu_name = torch.cuda.get_device_name(0)
    props = torch.cuda.get_device_properties(0)
    vram_gb = props.total_memory / 1024**3
    cc_major, cc_minor = props.major, props.minor

    if cc_major >= 8:
        best_dtype = "bfloat16"
        best_flash = True
    elif cc_major == 7:
        best_dtype = "float16"
        best_flash = False
    elif cc_major >= 6:
        best_dtype = "float16"
        best_flash = False
    else:
        best_dtype = "float32"
        best_flash = False

    if vram_gb < 6:
        best_dtype = "float32"
        best_flash = False

    if user_dtype == "float32" and best_dtype != "float32":
        pass
    elif user_dtype != best_dtype:
        pass

    flash_ok = best_flash and user_flash_attn
    if flash_ok:
        try:
            import importlib.metadata
            importlib.metadata.version("flash_attn")
        except Exception:
            flash_ok = False

    print(f"  GPU {num_gpus}x {gpu_name}  VRAM: {vram_gb:.1f}GB  CC: {cc_major}.{cc_minor}")
    print(f"  Device: cuda:0  Precisione: {best_dtype}  FlashAttn: {flash_ok}")

    return "cuda:0", best_dtype, flash_ok


def _load_model(checkpoint: str, device: str, dtype_val: str, flash_attn: bool):
    is_dml = device and device.startswith("directml")
    if is_dml:
        import torch_directml
        dml_device = torch_directml.device()
        device_cpu = True
    else:
        dml_device = None
        device_cpu = device == "cpu"

    if device_cpu:
        try:
            if not torch.cuda.is_available():
                torch.cuda.mem_get_info = lambda device=None: (0, 0)
        except Exception:
            pass

    attn_impl = None
    if flash_attn:
        try:
            import importlib.metadata
            importlib.metadata.version("flash_attn")
            attn_impl = "flash_attention_2"
        except Exception:
            pass

    tts = Qwen3TTSModel.from_pretrained(
        checkpoint,
        device_map=None if (device_cpu or is_dml) else device,
        dtype=dtype_val,
        attn_implementation=attn_impl,
    )

    if is_dml:
        tts.model = tts.model.to(dml_device)

    talker_config = getattr(getattr(tts.model, "talker", None), "config", None)
    spk_id = getattr(talker_config, "spk_id", None) if talker_config else None
    fine_tuned_speaker = None
    if spk_id and len(spk_id) > 0:
        fine_tuned_speaker = list(spk_id.keys())[0]
        tts.model.tts_model_type = "custom_voice"

    model_type = getattr(tts.model, "tts_model_type", None)
    model_size = getattr(tts.model, "tts_model_size", None)

    return tts, model_type, model_size, fine_tuned_speaker, is_dml


def create_app(models_config: Dict[str, str], device: str = "cuda:0", dtype: str = "bfloat16", flash_attn: bool = True) -> FastAPI:
    device, dtype, flash_attn = auto_detect_device(device, dtype, flash_attn)

    torch_dtype = {
        "bfloat16": torch.bfloat16,
        "bf16": torch.bfloat16,
        "float16": torch.float16,
        "fp16": torch.float16,
        "float32": torch.float32,
        "fp32": torch.float32,
    }.get(dtype, torch.bfloat16)

    loaded = {}
    errors = {}
    for name, ckpt in models_config.items():
        try:
            tts, mtype, msize, speaker, is_dml = _load_model(ckpt, device, torch_dtype, flash_attn)
            loaded[name] = dict(tts=tts, type=mtype, size=msize, speaker=speaker, is_dml=is_dml, path=ckpt)
        except Exception as e:
            errors[name] = str(e)

    if not loaded:
        raise RuntimeError(f"Nessun modello caricato. Errori: {errors}")

    app = FastAPI(title="Qwen3-TTS Multi-Model API", version="0.2.0")
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

    _temp_files = []

    @atexit.register
    def _cleanup():
        for f in _temp_files:
            try:
                os.unlink(f)
            except Exception:
                pass

    def _wav_response(wavs, sr):
        buf = io.BytesIO()
        sf.write(buf, wavs[0], sr, format="WAV")
        buf.seek(0)
        return Response(content=buf.read(), media_type="audio/wav")

    async def _read_audio(audio_file=None, audio_url=None, audio_base64=None):
        if audio_file and audio_file.filename:
            ext = os.path.splitext(audio_file.filename or "audio.wav")[1] or ".wav"
            tmp = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
            tmp.write(await audio_file.read())
            tmp.close()
            _temp_files.append(tmp.name)
            return tmp.name
        return audio_url or audio_base64

    def _get_model(model_name: Optional[str]) -> dict:
        if not model_name:
            name = next(iter(loaded))
            return loaded[name]
        if model_name not in loaded:
            raise HTTPException(400, f"Modello '{model_name}' non disponibile. Scegli tra: {list(loaded.keys())}")
        return loaded[model_name]

    @app.get("/health")
    async def health():
        info = {"status": "ok", "models": {}}
        for name, m in loaded.items():
            info["models"][name] = {"type": m["type"], "size": m["size"], "path": m["path"]}
        return info

    @app.get("/v1/models")
    async def get_models():
        info = {"models": {}}
        for name, m in loaded.items():
            entry = {"type": m["type"], "size": m["size"], "path": m["path"]}
            if m["speaker"]:
                entry["fine_tuned_speaker"] = m["speaker"]
            else:
                spk = m["tts"].get_supported_speakers()
                if spk:
                    entry["supported_speakers"] = spk
            langs = m["tts"].get_supported_languages()
            if langs:
                entry["supported_languages"] = langs
            info["models"][name] = entry
        return info

    @app.post("/v1/tts/custom-voice")
    async def custom_voice(text=Form(...), speaker=Form(None), model=Form(None), language="Auto", instruct=None,
                           max_new_tokens=None, temperature=None, top_k=None, top_p=None, repetition_penalty=None):
        m = _get_model(model)
        if m["type"] not in ("custom_voice",):
            raise HTTPException(400, f"Modello '{model or list(loaded.keys())[0]}' non supporta custom-voice")
        try:
            speaker_name = speaker or m["speaker"]
            if speaker_name is None:
                raise HTTPException(400, "speaker richiesto per questo modello")
            kwargs = {k: v for k, v in [("max_new_tokens", max_new_tokens), ("temperature", temperature),
                      ("top_k", top_k), ("top_p", top_p), ("repetition_penalty", repetition_penalty)] if v is not None}
            wavs, sr = m["tts"].generate_custom_voice(text=text, language=language, speaker=speaker_name,
                instruct=instruct or None, non_streaming_mode=True, **kwargs)
            if not m["is_dml"] and torch.cuda.is_available():
                torch.cuda.empty_cache()
            return _wav_response(wavs, sr)
        except Exception as e:
            traceback.print_exc()
            raise HTTPException(400, f"{type(e).__name__}: {e}")

    @app.post("/v1/tts/voice-design")
    async def voice_design(text=Form(...), instruct=Form(...), model=Form(None), language="Auto",
                           max_new_tokens=None, temperature=None, top_k=None, top_p=None, repetition_penalty=None):
        m = _get_model(model)
        if m["type"] != "voice_design":
            raise HTTPException(400, f"Modello '{model or list(loaded.keys())[0]}' non supporta voice-design")
        try:
            kwargs = {k: v for k, v in [("max_new_tokens", max_new_tokens), ("temperature", temperature),
                      ("top_k", top_k), ("top_p", top_p), ("repetition_penalty", repetition_penalty)] if v is not None}
            wavs, sr = m["tts"].generate_voice_design(text=text, language=language, instruct=instruct,
                non_streaming_mode=True, **kwargs)
            if not m["is_dml"] and torch.cuda.is_available():
                torch.cuda.empty_cache()
            return _wav_response(wavs, sr)
        except Exception as e:
            traceback.print_exc()
            raise HTTPException(400, f"{type(e).__name__}: {e}")

    @app.post("/v1/tts/voice-clone")
    async def voice_clone(text=Form(...), model=Form(None), language="Auto",
                          ref_audio=None, ref_audio_url=None, ref_audio_base64=None,
                          ref_text=None, x_vector_only_mode=False,
                          max_new_tokens=None, temperature=None, top_k=None, top_p=None, repetition_penalty=None):
        m = _get_model(model)
        if m["type"] != "base":
            raise HTTPException(400, f"Modello '{model or list(loaded.keys())[0]}' non supporta voice-clone (serve modello Base)")
        try:
            audio_input = await _read_audio(ref_audio, ref_audio_url, ref_audio_base64)
            if audio_input is None:
                raise HTTPException(400, "ref_audio, ref_audio_url, or ref_audio_base64 required")
            kwargs = {k: v for k, v in [("max_new_tokens", max_new_tokens), ("temperature", temperature),
                      ("top_k", top_k), ("top_p", top_p), ("repetition_penalty", repetition_penalty)] if v is not None}
            wavs, sr = m["tts"].generate_voice_clone(text=text, language=language, ref_audio=audio_input,
                ref_text=ref_text or None, x_vector_only_mode=x_vector_only_mode, non_streaming_mode=True, **kwargs)
            if not m["is_dml"] and torch.cuda.is_available():
                torch.cuda.empty_cache()
            return _wav_response(wavs, sr)
        except Exception as e:
            traceback.print_exc()
            raise HTTPException(400, f"{type(e).__name__}: {e}")

    return app

def get_lan_ip():
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def main():
    parser = argparse.ArgumentParser(prog="qwen-tts-server", description="Qwen3-TTS Multi-Model API")
    parser.add_argument("--models", required=True,
        help="Mappa nome=checkpoint separate da virgola. Es: cv=Qwen/...CustomVoice,vd=Qwen/...VoiceDesign,it=Aynursusuz/...")
    parser.add_argument("--device", default="cuda:0", help="Device (default: auto-detect)")
    parser.add_argument("--dtype", default="bfloat16", choices=["bfloat16", "bf16", "float16", "fp16", "float32", "fp32"])
    parser.add_argument("--flash-attn", default=True, action=argparse.BooleanOptionalAction)
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8000, help="Bind port (default: 8000)")
    args = parser.parse_args()

    print("=" * 45)
    print("  Qwen3-TTS Server")
    if torch.cuda.is_available():
        try:
            nvsmi = subprocess.run(["nvidia-smi", "--query-gpu=name,compute_cap,memory.total,driver_version",
                "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5)
            if nvsmi.returncode == 0:
                gpu_info = nvsmi.stdout.strip().split(",")
                name = gpu_info[0].strip() if len(gpu_info) > 0 else "?"
                vram = gpu_info[2].strip() if len(gpu_info) > 2 else "?"
                driver = gpu_info[3].strip() if len(gpu_info) > 3 else "?"
                print(f"  GPU: {name}  VRAM: {vram}MB  Driver: {driver}")
        except Exception:
            print(f"  GPU: {torch.cuda.get_device_name(0)}  VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f}GB")
    print(f"  PyTorch: {torch.__version__}")
    print("=" * 45)

    print("=" * 45)
    print("  Caricamento modelli in corso, attendere...")
    print("=" * 45)

    models = {}
    for pair in args.models.split(","):
        if "=" not in pair:
            raise ValueError(f"Formato errato: '{pair}'. Usa nome=checkpoint")
        name, ckpt = pair.split("=", 1)
        models[name.strip()] = ckpt.strip()

    app = create_app(models_config=models, device=args.device, dtype=args.dtype, flash_attn=args.flash_attn)

    lan_ip = get_lan_ip()
    print("=" * 45)
    print("  Qwen3-TTS Server PRONTO!")
    print(f"  Locale: http://127.0.0.1:{args.port}")
    print(f"  Rete:   http://{lan_ip}:{args.port}")
    print("=" * 45)
    
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
