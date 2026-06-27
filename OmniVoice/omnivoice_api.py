# coding=utf-8
"""
OmniVoice TTS API Server
========================
API compatibile con VibeCut (endpoint /api/tts) e con le convenzioni
Qwen3-TTS (endpoint /v1/tts/voice-clone, /v1/tts/voice-design, /v1/models).

Modello: https://github.com/k2-fsa/OmniVoice
"""
import argparse
import atexit
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import traceback
import uuid
from typing import Optional

import numpy as np
import soundfile as sf
import torch
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, HTMLResponse

# ── Fix per Windows: stdout/stderr UTF-8 ──────────────────────────────
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# ── Modello globale lazy ──────────────────────────────────────────────
_model = None
_device = "cpu"
_dtype = torch.float16

OUTPUT_DIR = os.path.join(os.getcwd(), "assets", "audios")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Speaker reference predefiniti (metti i tuoi .wav nella cartella del server)
SPEAKER_DIR = os.path.join(os.getcwd(), "speakers")
os.makedirs(SPEAKER_DIR, exist_ok=True)

SPEAKER_INFO = {}  # nome_file -> descrizione
SPEAKER_ALIAS = {}  # alias -> nome_file


def scan_speakers():
    """Scansiona la cartella speakers/ per file .wav."""
    global SPEAKER_INFO, SPEAKER_ALIAS
    SPEAKER_INFO = {}
    SPEAKER_ALIAS = {}
    if not os.path.isdir(SPEAKER_DIR):
        return
    for fname in os.listdir(SPEAKER_DIR):
        if fname.lower().endswith(".wav"):
            label = os.path.splitext(fname)[0].replace("_", " ").title()
            SPEAKER_INFO[fname] = label
            SPEAKER_ALIAS[label.lower()] = fname
            SPEAKER_ALIAS[fname.lower()] = fname
            base = os.path.splitext(fname)[0].lower()
            SPEAKER_ALIAS[base] = fname


scan_speakers()


def auto_detect_device(user_device: str, user_dtype: str):
    """Rileva GPU e sceglie dtype ottimale."""
    global _device, _dtype
    dtype_map = {
        "bfloat16": torch.bfloat16,
        "bf16": torch.bfloat16,
        "float16": torch.float16,
        "fp16": torch.float16,
        "float32": torch.float32,
        "fp32": torch.float32,
    }

    if user_device == "cpu":
        _device = "cpu"
        _dtype = torch.float32
        return _device, _dtype

    if user_device.startswith("cuda"):
        if not torch.cuda.is_available():
            print("  [GPU] CUDA non disponibile, uso CPU.")
            _device = "cpu"
            _dtype = torch.float32
            return _device, _dtype
        _device = user_device
    elif user_device == "mps":
        if not torch.backends.mps.is_available():
            print("  [MPS] Non disponibile, uso CPU.")
            _device = "cpu"
            _dtype = torch.float32
            return _device, _dtype
        _device = "mps"
    elif user_device == "xpu":
        if not hasattr(torch, "xpu") or not torch.xpu.is_available():
            print("  [XPU] Non disponibile, uso CPU.")
            _device = "cpu"
            _dtype = torch.float32
            return _device, _dtype
        _device = "xpu"
    else:
        # Auto-detect: prefer CUDA
        if torch.cuda.is_available():
            _device = "cuda:0"
        elif torch.backends.mps.is_available():
            _device = "mps"
        else:
            _device = "cpu"
            _dtype = torch.float32
            return _device, _dtype

    # Sceglie dtype ottimale per GPU
    if _device.startswith("cuda"):
        props = torch.cuda.get_device_properties(0)
        vram_gb = props.total_memory / 1024**3
        cc = props.major + props.minor / 10
        _device_name = torch.cuda.get_device_name(0)
        print(f"  [GPU] {_device_name}  VRAM: {vram_gb:.1f}GB  CC: {props.major}.{props.minor}")
        if cc >= 8.0 and vram_gb >= 6:
            _dtype = dtype_map.get(user_dtype, torch.bfloat16)
        elif cc >= 7.0:
            _dtype = torch.float16
        else:
            _dtype = torch.float32
    elif _device == "mps":
        _dtype = torch.float32
    elif _device == "xpu":
        _dtype = torch.float16

    return _device, _dtype


def load_model(model_name: str = "k2-fsa/OmniVoice", device: str = "auto",
               dtype: str = "bfloat16"):
    """Carica il modello OmniVoice (lazy)."""
    global _model, _device, _dtype

    if _model is not None:
        return _model

    if device == "auto":
        device = None  # auto_detect_device deciderà
    _device, _dtype = auto_detect_device(device or "auto", dtype)

    print(f"\n{'='*45}")
    print(f"  Caricamento OmniVoice in corso...")
    print(f"  Modello: {model_name}")
    print(f"  Device:  {_device}")
    print(f"  Dtype:   {_dtype}")
    print(f"{'='*45}\n")

    from omnivoice import OmniVoice

    _model = OmniVoice.from_pretrained(
        model_name,
        device_map=_device if _device != "cpu" else None,
        dtype=_dtype,
    )

    print(f"\n{'='*45}")
    print(f"  OmniVoice caricato con successo!")
    print(f"{'='*45}\n")
    return _model


def get_model():
    if _model is None:
        raise HTTPException(503, "Modello non ancora caricato. Usa /health per verificare.")
    return _model


# ── App FastAPI ───────────────────────────────────────────────────────

app = FastAPI(title="OmniVoice TTS API", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

_temp_files = []


@atexit.register
def _cleanup():
    for f in _temp_files:
        try:
            os.unlink(f)
        except Exception:
            pass


def _wav_response(audio_list, sr=24000):
    """Converte una lista di numpy array in risposta WAV."""
    combined = audio_list[0] if len(audio_list) == 1 else \
        np.concatenate(audio_list)
    buf = io.BytesIO()
    sf.write(buf, combined, sr, format="WAV", subtype="PCM_16")
    buf.seek(0)
    return Response(content=buf.read(), media_type="audio/wav")


async def _save_upload(audio_file: UploadFile = None) -> Optional[str]:
    """Salva un file caricato su disco, restituisce il path."""
    if audio_file and audio_file.filename:
        ext = os.path.splitext(audio_file.filename or "audio.wav")[1] or ".wav"
        tmp = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
        tmp.write(await audio_file.read())
        tmp.close()
        _temp_files.append(tmp.name)
        return tmp.name
    return None


def _resolve_speaker(speaker_wav: str) -> Optional[str]:
    """Risolve speaker_wav: path file, alias, URL → path locale."""
    if not speaker_wav:
        return None

    # URL remoto → download
    if speaker_wav.startswith(("http://", "https://")):
        try:
            import urllib.request
            ext = os.path.splitext(speaker_wav.split("?")[0])[1] or ".wav"
            tmp = tempfile.NamedTemporaryFile(suffix=ext, delete=False)
            tmp.close()
            print(f"  Download ref_audio da URL: {speaker_wav}")
            urllib.request.urlretrieve(speaker_wav, tmp.name)
            _temp_files.append(tmp.name)
            return tmp.name
        except Exception as e:
            print(f"  Errore download URL {speaker_wav}: {e}")
            return None

    # Alias speaker
    mapped = SPEAKER_ALIAS.get(speaker_wav.strip().lower())
    if mapped:
        path = os.path.join(SPEAKER_DIR, mapped)
        if os.path.exists(path):
            return path

    # Path diretto
    if os.path.exists(speaker_wav):
        return speaker_wav

    # Path dentro speakers/
    path = os.path.join(SPEAKER_DIR, speaker_wav)
    if os.path.exists(path):
        return path

    return None


# ── Web UI ────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
async def index():
    speaker_opts = "".join(
        f'<option value="{f}">{n}</option>'
        for f, n in SPEAKER_INFO.items()
    )
    return f"""<!DOCTYPE html>
<html><head><title>OmniVoice TTS API</title><meta charset="utf-8"></head>
<body style="font-family:sans-serif;margin:40px">
<h2>OmniVoice TTS</h2>
<p>Modello: <b>k2-fsa/OmniVoice</b> — Oltre 600 lingue · Voice Cloning · Voice Design</p>
<hr>
<h3>Voice Cloning</h3>
<form method="POST" action="/api/tts" target="_blank" enctype="multipart/form-data">
<p><textarea name="text" rows="3" cols="60" placeholder="Testo da sintetizzare...">Ciao mondo, questo è un test di voice cloning.</textarea></p>
<p>
  <label>Voce reference:
    <select name="speaker_wav">{speaker_opts}</select>
  </label>
  <label>Oppure carica audio: <input type="file" name="ref_audio" accept="audio/*"></label>
</p>
<p><label>Testo reference (opzionale, per clone più preciso):
  <input type="text" name="ref_text" size="50" placeholder="Trascrizione dell'audio reference...">
</label></p>
<p><label>Lingua: <input type="text" name="language" value="it" size="5"></label>
<label>Speed: <input type="number" name="speed" value="1.0" step="0.05" min="0.5" max="2.0"></label></p>
<p><button type="submit">Genera e scarica</button></p>
</form>
<hr>
<h3>Voice Design</h3>
<form method="POST" action="/v1/tts/voice-design" target="_blank" enctype="multipart/form-data">
<p><textarea name="text" rows="3" cols="60" placeholder="Testo da sintetizzare...">Ciao mondo, questo è un test di voice design.</textarea></p>
<p><label>Istruzioni voce: <input type="text" name="instruct" size="60" value="female, italian accent" placeholder="es. female, british accent, low pitch"></label></p>
<p><label>Lingua: <input type="text" name="language" value="it" size="5"></label></p>
<p><button type="submit">Genera e scarica</button></p>
</form>
<hr>
<h3>Auto Voice</h3>
<form method="POST" action="/v1/tts/generate" target="_blank">
<p><textarea name="text" rows="3" cols="60" placeholder="Testo da sintetizzare...">Questo testo verrà letto con una voce automatica.</textarea></p>
<p><button type="submit">Genera e scarica</button></p>
</form>
<hr>
<p><a href="/health">Health</a> | <a href="/v1/models">Models</a> | <a href="/api/speakers">Speakers</a></p>
</body></html>"""


# ── Health ────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": "k2-fsa/OmniVoice",
        "device": _device,
        "dtype": str(_dtype),
        "model_loaded": _model is not None,
        "speakers_available": list(SPEAKER_INFO.keys()),
    }


# ── Models ────────────────────────────────────────────────────────────

@app.get("/v1/models")
async def list_models():
    return {
        "models": {
            "omnivoice": {
                "type": "base",
                "source": "k2-fsa/OmniVoice",
                "device": _device,
                "dtype": str(_dtype),
                "loaded": _model is not None,
                "languages": "600+",
                "modes": ["voice-clone", "voice-design", "auto-voice"],
            }
        }
    }


# ── Speakers (compatibile XTTSv2 / VibeCut) ──────────────────────────

@app.get("/api/speakers")
async def list_speakers():
    return {
        "default": list(SPEAKER_INFO.keys())[0] if SPEAKER_INFO else None,
        "available": list(SPEAKER_INFO.keys()),
        "names": SPEAKER_INFO,
    }


# ── API compatibile XTTSv2 / VibeCut ─────────────────────────────────

@app.post("/api/tts")
async def api_tts(request: Request):
    """
    Endpoint compatibile con XTTSv2 / VibeCut.
    Accetta sia JSON che form-data/multipart.

    Parametri:
    - text (obbligatorio): testo da sintetizzare
    - speaker_wav / speaker: file audio reference (nome, path o URL)
    - ref_audio: file audio caricato (multipart)
    - ref_text: trascrizione dell'audio reference
    - language: lingua del testo
    - speed: velocità (1.0 = normale)
    - instruct: istruzioni voce (per voice design)
    """
    ct = request.headers.get("content-type", "")
    data = {}
    files_data = {}

    if "multipart" in ct:
        form = await request.form()
        data = {k: v for k, v in form.items() if not hasattr(v, "read")}
        files_data = {k: v for k, v in form.items() if hasattr(v, "read")}
    elif "json" in ct:
        data = await request.json()
    else:
        try:
            data = await request.json()
        except Exception:
            form = await request.form()
            data = {k: v for k, v in form.items()}

    text = (data.get("text") or "").strip()
    if not text:
        raise HTTPException(400, "Campo 'text' obbligatorio")

    speaker_wav = data.get("speaker_wav") or data.get("speaker") or ""
    ref_text = data.get("ref_text") or data.get("ref_text") or None
    instruct = data.get("instruct") or None
    language = data.get("language", "it")
    speed = float(data.get("speed", 1.0))

    model = get_model()

    # ── Prepara ref_audio ──
    ref_audio_path = None

    # 1. File caricato via multipart
    uploaded = files_data.get("ref_audio") or files_data.get("speaker_file")
    if uploaded and hasattr(uploaded, "read"):
        ref_audio_path = await _save_upload(uploaded)
        print(f"  Usato file caricato: {uploaded.filename}")

    # 2. Speaker predefinito / alias
    if not ref_audio_path and speaker_wav:
        ref_audio_path = _resolve_speaker(speaker_wav)
        if ref_audio_path:
            print(f"  Usato speaker: {speaker_wav} → {ref_audio_path}")

    print(f"\n[OmniVoice] /api/tts")
    print(f"  Testo: {text[:60]!r}...")
    print(f"  Ref audio: {ref_audio_path or 'N/A'}")
    print(f"  Ref text: {ref_text or 'N/A'}")
    print(f"  Instruct: {instruct or 'N/A'}")
    print(f"  Language: {language}")
    print(f"  Speed: {speed}")

    try:
        kwargs = dict(text=text)

        if ref_audio_path and os.path.exists(ref_audio_path):
            kwargs["ref_audio"] = ref_audio_path
        if ref_text:
            kwargs["ref_text"] = ref_text
        if instruct:
            kwargs["instruct"] = instruct
        if speed != 1.0:
            kwargs["speed"] = speed

        audio_list = model.generate(**kwargs)

        if _device.startswith("cuda") and torch.cuda.is_available():
            torch.cuda.empty_cache()

        return _wav_response(audio_list)

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"{type(e).__name__}: {e}")


# ── Voice Clone ───────────────────────────────────────────────────────

@app.post("/v1/tts/voice-clone")
async def voice_clone(
    text: str = Form(...),
    ref_audio: UploadFile = File(None),
    ref_audio_url: str = Form(None),
    ref_text: str = Form(None),
    model_name: str = Form(None),
    language: str = Form("Auto"),
    speed: float = Form(1.0),
    num_step: int = Form(None),
    duration: float = Form(None),
):
    """Clona una voce da un audio reference."""
    model = get_model()

    # Risolvi ref_audio
    ref_audio_path = None
    if ref_audio and ref_audio.filename:
        ref_audio_path = await _save_upload(ref_audio)
    elif ref_audio_url:
        ref_audio_path = _resolve_speaker(ref_audio_url)
    else:
        raise HTTPException(400, "ref_audio o ref_audio_url obbligatorio per voice-clone")

    print(f"\n[OmniVoice] /v1/tts/voice-clone")
    print(f"  Testo: {text[:60]!r}...")
    print(f"  Ref audio: {ref_audio_path}")
    print(f"  Ref text: {ref_text or 'N/A'}")

    try:
        kwargs = dict(text=text, ref_audio=ref_audio_path)
        if ref_text:
            kwargs["ref_text"] = ref_text
        if speed != 1.0:
            kwargs["speed"] = speed
        if num_step is not None:
            kwargs["num_step"] = num_step
        if duration is not None:
            kwargs["duration"] = duration

        audio_list = model.generate(**kwargs)

        if _device.startswith("cuda") and torch.cuda.is_available():
            torch.cuda.empty_cache()

        return _wav_response(audio_list)

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"{type(e).__name__}: {e}")


# ── Voice Design ─────────────────────────────────────────────────────

@app.post("/v1/tts/voice-design")
async def voice_design(
    text: str = Form(...),
    instruct: str = Form(...),
    model_name: str = Form(None),
    language: str = Form("Auto"),
    speed: float = Form(1.0),
    num_step: int = Form(None),
    duration: float = Form(None),
):
    """Genera voce con attributi specificati (senza audio reference)."""
    model = get_model()

    print(f"\n[OmniVoice] /v1/tts/voice-design")
    print(f"  Testo: {text[:60]!r}...")
    print(f"  Instruct: {instruct}")

    try:
        kwargs = dict(text=text, instruct=instruct)
        if speed != 1.0:
            kwargs["speed"] = speed
        if num_step is not None:
            kwargs["num_step"] = num_step
        if duration is not None:
            kwargs["duration"] = duration

        audio_list = model.generate(**kwargs)

        if _device.startswith("cuda") and torch.cuda.is_available():
            torch.cuda.empty_cache()

        return _wav_response(audio_list)

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"{type(e).__name__}: {e}")


# ── Auto Voice / Generate ────────────────────────────────────────────

@app.post("/v1/tts/generate")
async def generate(
    text: str = Form(...),
    model_name: str = Form(None),
    language: str = Form("Auto"),
    speed: float = Form(1.0),
    num_step: int = Form(None),
    duration: float = Form(None),
):
    """Generazione automatica (senza reference né istruzioni)."""
    model = get_model()

    print(f"\n[OmniVoice] /v1/tts/generate")
    print(f"  Testo: {text[:60]!r}...")

    try:
        kwargs = dict(text=text)
        if speed != 1.0:
            kwargs["speed"] = speed
        if num_step is not None:
            kwargs["num_step"] = num_step
        if duration is not None:
            kwargs["duration"] = duration

        audio_list = model.generate(**kwargs)

        if _device.startswith("cuda") and torch.cuda.is_available():
            torch.cuda.empty_cache()

        return _wav_response(audio_list)

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"{type(e).__name__}: {e}")


# ── Preview speaker ──────────────────────────────────────────────────

@app.get("/api/preview/{filename:path}")
async def preview_speaker(filename: str):
    """Riproduce un file audio reference."""
    path = os.path.join(SPEAKER_DIR, filename)
    if not os.path.exists(path):
        # Cerca anche nella root
        path = os.path.join(os.getcwd(), filename)
    if not os.path.exists(path):
        raise HTTPException(404, "File non trovato")
    return Response(content=open(path, "rb").read(), media_type="audio/wav")


# ── Main ──────────────────────────────────────────────────────────────

def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def main():
    parser = argparse.ArgumentParser(prog="omnivoice-api", description="OmniVoice TTS API Server")
    parser.add_argument("--model", default="k2-fsa/OmniVoice",
                        help="Modello HuggingFace (default: k2-fsa/OmniVoice)")
    parser.add_argument("--device", default="auto",
                        help="Device: auto, cpu, cuda:0, mps, xpu (default: auto)")
    parser.add_argument("--dtype", default="bfloat16",
                        choices=["bfloat16", "bf16", "float16", "fp16", "float32", "fp32"],
                        help="Precisione (default: bfloat16, auto-ridotto se VRAM < 6GB)")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8010, help="Bind port (default: 8010)")
    parser.add_argument("--preload", action="store_true", help="Precarica il modello all'avvio")
    args = parser.parse_args()

    print("=" * 45)
    print("  OmniVoice TTS Server")
    print("=" * 45)
    print(f"  Modello: {args.model}")
    print(f"  Host:    {args.host}")
    print(f"  Porta:   {args.port}")
    print(f"  Device:  {args.device}")
    print(f"  Dtype:   {args.dtype}")
    print("=" * 45)

    if args.preload:
        load_model(args.model, args.device, args.dtype)

    lan_ip = get_lan_ip()
    print("\n" + "=" * 45)
    print("  OmniVoice Server PRONTO!")
    print(f"  Locale:    http://127.0.0.1:{args.port}")
    print(f"  Rete:      http://{lan_ip}:{args.port}")
    print(f"  Web UI:    http://{lan_ip}:{args.port}/")
    print(f"  Endpoint VibeCut: POST http://{lan_ip}:{args.port}/api/tts")
    print(f"  Endpoint Clone:   POST http://{lan_ip}:{args.port}/v1/tts/voice-clone")
    print(f"  Endpoint Design:  POST http://{lan_ip}:{args.port}/v1/tts/voice-design")
    print("=" * 45)
    print(f"  Metti i file .wav reference nella cartella 'speakers/'")
    print("=" * 45 + "\n")

    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
