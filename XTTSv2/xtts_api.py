import os
import json
import subprocess
import sys
import uuid
import torch
# Fix per PyTorch 2.6+: TTS carica checkpoint con weights_only=True di default
_safe_load = torch.load
torch.load = lambda *a, **kw: _safe_load(*a, **kw, weights_only=False)
from TTS.api import TTS
from flask import Flask, request, send_file, jsonify, Response

app = Flask(__name__)


def _detect_gpu_info():
    if not torch.cuda.is_available():
        print("  [GPU] Nessuna GPU NVIDIA rilevata. Uso CPU.")
        print("  [GPU] Per usare GPU, installa PyTorch CUDA e driver NVIDIA aggiornati.")
        return "cpu"
    try:
        nvsmi = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,compute_cap,memory.total,driver_version",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if nvsmi.returncode == 0 and nvsmi.stdout.strip():
            parts = [p.strip() for p in nvsmi.stdout.strip().split(",")]
            name = parts[0] if len(parts) > 0 else "?"
            cc = parts[1] if len(parts) > 1 else "?"
            vram = parts[2] if len(parts) > 2 else "?"
            driver = parts[3] if len(parts) > 3 else "?"
            print(f"  [GPU] {name}  VRAM: {vram}MB  CC: {cc}  Driver: {driver}")
    except Exception:
        pass
    props = torch.cuda.get_device_properties(0)
    print(f"  [GPU] {torch.cuda.get_device_name(0)}  VRAM: {props.total_memory / 1024**3:.1f}GB")
    return "cuda"


device = _detect_gpu_info()
OUTPUT_DIR = os.path.join(os.getcwd(), "assets", "audios")
os.makedirs(OUTPUT_DIR, exist_ok=True)

DEFAULT_SPEAKER = "isabella_ref.wav"
xtts_model = None


def get_xtts():
    global xtts_model
    if xtts_model is None:
        print("")
        print("Caricamento modello XTTSv2 in corso...")
        print("(Primo avvio: ~2GB da scaricare da HuggingFace, potrebbe richiedere minuti)")
        print("")
        xtts_model = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
        print("Modello XTTSv2 caricato con successo!")
    return xtts_model


SPEAKER_INFO = {
    "isabella_ref.wav": "Isabella (donna)",
    "giuseppe_ref.wav": "Giuseppe (uomo)",
    "diego_ref.wav": "Diego (uomo)",
    "elsa_ref.wav": "Elsa (donna)",
}

# Mappa nomi brevi -> file .wav (compatibile con VibeCut)
SPEAKER_ALIAS = {}
for fname, label in SPEAKER_INFO.items():
    name = label.split("(")[0].strip().lower()
    SPEAKER_ALIAS[name] = fname
    # anche nome senza suffisso _ref.wav
    base = fname.replace("_ref.wav", "").lower()
    SPEAKER_ALIAS[base] = fname
    # anche tutta la label lowercase
    SPEAKER_ALIAS[label.lower()] = fname


@app.route("/", methods=["GET"])
def index():
    opts = "".join(
        f'<option value="{f}">{n}</option>'
        for f, n in SPEAKER_INFO.items()
    )
    return f"""<!DOCTYPE html>
<html><head><title>XTTS API</title><meta charset="utf-8"></head>
<body style="font-family:sans-serif;margin:40px">
<h2>XTTS Voice Cloning</h2>
<form method="POST" action="/api/tts" target="_blank">
<p><textarea name="text" rows="4" cols="50" placeholder="Testo...">Ciao mondo</textarea></p>
<p>
  <label>Voce: <select name="speaker_wav">{opts}</select></label>
  <label>Lingua:
    <select name="language">
      <option value="it">Italiano</option>
      <option value="en">English</option>
      <option value="de">Deutsch</option>
      <option value="fr">Francais</option>
      <option value="es">Espanol</option>
    </select>
  </label>
  <label>Speed: <input type="number" name="speed" value="1.0" step="0.05" min="0.5" max="2.0"></label>
</p>
<p><button type="submit">Genera e scarica</button></p>
</form>
<h3>Anteprima voci reference</h3>
<p>""" + " | ".join(
    f'<a href="/api/preview/{f}" target="_blank">{n}</a>'
    for f, n in SPEAKER_INFO.items()
) + """</p>
<p><a href="/health">Health</a> | <a href="/api/speakers">Speakers list</a></p>
</body></html>"""


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "device": device,
        "default_speaker": DEFAULT_SPEAKER,
        "xtts_loaded": xtts_model is not None
    })


@app.route("/api/speakers", methods=["GET"])
def list_speakers():
    return jsonify({
        "default": DEFAULT_SPEAKER,
        "available": list(SPEAKER_INFO.keys()),
        "names": SPEAKER_INFO,
    })


@app.route("/api/preview/<path:filename>", methods=["GET"])
def preview(filename):
    path = os.path.join(os.getcwd(), filename)
    if not os.path.exists(path):
        return jsonify({"error": "File not found"}), 404
    return send_file(path, mimetype="audio/wav")


@app.route("/api/tts", methods=["POST"])
def text_to_speech():
    raw = request.get_data(as_text=True)
    ct = request.content_type or ""

    if "json" in ct:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            return jsonify({"error": f"Invalid JSON: {e}"}), 400
    elif "multipart" in ct or "form" in ct:
        data = request.form
    else:
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            data = request.form

    text = data.get("text", "").strip()
    if not text:
        return jsonify({"error": "Missing 'text' field"}), 400

    speaker_wav = data.get("speaker_wav") or data.get("speaker", DEFAULT_SPEAKER)

    # 1. Verifica se è presente un file caricato multipart
    uploaded_file = request.files.get("speaker_file") or request.files.get("ref_audio")
    if uploaded_file and uploaded_file.filename:
        try:
            ext = os.path.splitext(uploaded_file.filename)[1] or ".wav"
            temp_dir = os.path.join(os.getcwd(), "temp_uploaded")
            os.makedirs(temp_dir, exist_ok=True)
            temp_path = os.path.join(temp_dir, f"{uuid.uuid4().hex}{ext}")
            uploaded_file.save(temp_path)
            speaker_wav = temp_path
            print(f"Usato file caricato via multipart per clone: {speaker_wav}")
        except Exception as e:
            print(f"Errore salvataggio file caricato: {e}")

    # 2. Verifica se speaker_wav è un URL HTTP/HTTPS
    elif isinstance(speaker_wav, str) and (speaker_wav.startswith("http://") or speaker_wav.startswith("https://")):
        try:
            import urllib.request
            ext = os.path.splitext(speaker_wav.split("?")[0])[1] or ".wav"
            temp_dir = os.path.join(os.getcwd(), "temp_uploaded")
            os.makedirs(temp_dir, exist_ok=True)
            temp_path = os.path.join(temp_dir, f"dl_{uuid.uuid4().hex}{ext}")
            print(f"Download voce di riferimento da URL: {speaker_wav} -> {temp_path}")
            urllib.request.urlretrieve(speaker_wav, temp_path)
            speaker_wav = temp_path
        except Exception as e:
            print(f"Errore download url {speaker_wav}: {e}")

    if not os.path.exists(speaker_wav):
        mapped = SPEAKER_ALIAS.get(speaker_wav.strip().lower())
        if mapped and os.path.exists(mapped):
            speaker_wav = mapped
    if not os.path.exists(speaker_wav):
        print(f"Speaker '{speaker_wav}' non trovato, uso default '{DEFAULT_SPEAKER}'")
        speaker_wav = DEFAULT_SPEAKER

    language = data.get("language", "it")
    speed = float(data.get("speed", 1.0))

    output_filename = f"{uuid.uuid4().hex}.wav"
    output_path = os.path.join(OUTPUT_DIR, output_filename)

    try:
        model = get_xtts()
        model.tts_to_file(
            text=text,
            speaker_wav=speaker_wav,
            language=language,
            file_path=output_path,
            speed=speed,
            split_sentences=True,
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    with open(output_path, "rb") as f:
        audio_data = f.read()

    return Response(
        audio_data,
        mimetype="audio/wav",
        headers={
            "Content-Disposition": f'attachment; filename="output.wav"',
            "Content-Length": str(len(audio_data)),
        },
    )


if __name__ == "__main__":
    import argparse
    import socket
    parser = argparse.ArgumentParser(description="XTTS API Server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8020)
    parser.add_argument("--preload", action="store_true", help="Precarica XTTS all'avvio")
    args = parser.parse_args()
    if args.preload:
        get_xtts()
    try:
        lan_ip = socket.gethostbyname(socket.gethostname())
    except Exception:
        lan_ip = "127.0.0.1"
    print("")
    print("=" * 45)
    print(f"  XTTSv2 Server PRONTO!")
    print(f"  Device: {device}")
    print(f"  Locale:    http://localhost:{args.port}")
    print(f"  LAN:       http://{lan_ip}:{args.port}")
    print(f"  Endpoint:  POST /api/tts")
    print("=" * 45)
    print("  Per VibeCut usa URL: http://{lan_ip}:{args.port}")
    print("")
    app.run(host=args.host, port=args.port, debug=False)
