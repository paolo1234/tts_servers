# Qwen3-TTS API Reference

## Avvio Server

```bash
python -m qwen_tts.server \
  --models "cv=Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice,vd=Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign,it=Aynursusuz/Qwen-TTS-Best-Model" \
  --host 0.0.0.0 --port 8000 \
  --device cpu --dtype float32 --no-flash-attn
```

### Parametri CLI

| Parametro | Default | Descrizione |
|-----------|---------|-------------|
| `--models` | *(obbligatorio)* | Mappa `nome=checkpoint` separata da virgola. Es: `cv=Qwen/...CustomVoice,vd=Qwen/...VoiceDesign` |
| `--device` | `cuda:0` | Device: `cpu`, `cuda:0`, `directml:0` |
| `--dtype` | `bfloat16` | Precision: `bfloat16`, `float16`, `float32` |
| `--flash-attn` / `--no-flash-attn` | `True` | Abilita flash-attention se installata |
| `--host` | `0.0.0.0` | IP di bind |
| `--port` | `8000` | Porta |

---

## Endpoint

### `GET /health`

Stato del server e modelli caricati.

**Risposta:**
```json
{
  "status": "ok",
  "models": {
    "cv": { "type": "custom_voice", "size": "1b7", "path": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice" },
    "vd": { "type": "voice_design", "size": "1b7", "path": "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign" }
  }
}
```

---

### `GET /v1/models`

Lista dettagliata dei modelli caricati con capacità e speaker supportati.

**Risposta:**
```json
{
  "models": {
    "cv": {
      "type": "custom_voice",
      "size": "1b7",
      "path": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
      "supported_speakers": ["speaker1", "speaker2", ...],
      "supported_languages": ["auto", "en", "zh", "jp", "kr", "fr", "de", "it", "pt", "es", "ru", "ar", "th", "nl", "pl", "vi", "id", "tr"]
    },
    "vd": {
      "type": "voice_design",
      "size": "1b7",
      "path": "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
      "supported_languages": [...]
    },
    "it": {
      "type": "custom_voice",
      "size": "1b7",
      "path": "Aynursusuz/Qwen-TTS-Best-Model",
      "fine_tuned_speaker": "aldobaglio"
    }
  }
}
```

---

### `POST /v1/tts/custom-voice`

Genera voce con timbro predefinito (CustomVoice o Fine-Tune).

**Parametri (form-data):**

| Parametro | Tipo | Obbligatorio | Default | Descrizione |
|-----------|------|-------------|---------|-------------|
| `text` | string | **sì** | — | Testo da sintetizzare |
| `speaker` | string | no | (default del modello) | ID speaker. Per fine-tune italiani: `aldobaglio` |
| `model` | string | no | (primo modello caricato) | Nome modello (es: `cv`, `it`) |
| `language` | string | no | `Auto` | Lingua (auto-detect se `Auto`) |
| `instruct` | string | no | — | Istruzione stile voce. Es: "Parla come un narratore epico con tono profondo e solenne" |
| `max_new_tokens` | int | no | — | Max token generati |
| `temperature` | float | no | — | Creatività (0.1-1.0) |
| `top_k` | int | no | — | Top-K sampling |
| `top_p` | float | no | — | Top-P (nucleus) sampling |
| `repetition_penalty` | float | no | — | Penalità ripetizione |

**Risposta:** Audio WAV (Content-Type: `audio/wav`)

**Esempio:**
```bash
curl -X POST http://localhost:8000/v1/tts/custom-voice \
  -F "text=Ciao a tutti, benvenuti sul mio canale!" \
  -F "speaker=aldobaglio" \
  -F "instruct=Voce calda, accogliente, da creator di contenuti" \
  -F "language=Auto" \
  -o output.wav
```

---

### `POST /v1/tts/voice-design`

Genera voce da descrizione testuale (VoiceDesign). **Non serve speaker di riferimento.**

**Parametri (form-data):**

| Parametro | Tipo | Obbligatorio | Default | Descrizione |
|-----------|------|-------------|---------|-------------|
| `text` | string | **sì** | — | Testo da sintetizzare |
| `instruct` | string | **sì** | — | Descrizione della voce desiderata |
| `model` | string | no | (primo modello) | Nome modello (es: `vd`) |
| `language` | string | no | `Auto` | Lingua |
| `max_new_tokens` | int | no | — | Max token generati |
| `temperature` | float | no | — | Creatività |
| `top_k` | int | no | — | Top-K |
| `top_p` | float | no | — | Top-P |
| `repetition_penalty` | float | no | — | Penalità ripetizione |

**Risposta:** Audio WAV (Content-Type: `audio/wav`)

**Esempio:**
```bash
curl -X POST http://localhost:8000/v1/tts/voice-design \
  -F "text=Ciao a tutti ragazzi, oggi nuovo video emozionante!" \
  -F "instruct=Voce maschile giovane, entusiasta, stile YouTuber italiano, ritmo vivace, tono allegro" \
  -o output.wav
```

**Esempi di instruct:**
- `"Voce femminile morbida, calma, da audiolibro, italiana"`
- `"Voce robotica, metallica, stile HAL 9000"`
- `"Narratore epico, tono profondo e solenne, da trailer cinematografico"`
- `"Ragazza giovane, voce squillante, entusiasta, stile TikTok"`
- `"Uomo maturo, voce roca, da radiofonico, autorevole"`
- `"Voce sussurrata, intima, lenta"`
- `"Speaker commerciale, chiaro, scandito, professionale"`

---

### `POST /v1/tts/voice-clone`

Clona voce da audio di riferimento (solo modello Base).

**Parametri (form-data):**

| Parametro | Tipo | Obbligatorio | Default | Descrizione |
|-----------|------|-------------|---------|-------------|
| `text` | string | **sì** | — | Testo da sintetizzare |
| `model` | string | no | (primo modello) | Nome modello **Base** |
| `language` | string | no | `Auto` | Lingua |
| `ref_audio` | file | * | — | File audio di riferimento (WAV/MP3/OGG) |
| `ref_audio_url` | string | * | — | URL audio di riferimento |
| `ref_audio_base64` | string | * | — | Audio in base64 |
| `ref_text` | string | no | — | Trascrizione dell'audio di riferimento (migliora qualità) |
| `x_vector_only_mode` | bool | no | `false` | Se true, estrae solo x-vector e termina |
| `max_new_tokens` | int | no | — | Max token generati |
| `temperature` | float | no | — | Creatività |
| `top_k` | int | no | — | Top-K |
| `top_p` | float | no | — | Top-P |
| `repetition_penalty` | float | no | — | Penalità ripetizione |

\* Uno tra `ref_audio`, `ref_audio_url`, `ref_audio_base64` è obbligatorio.

**Risposta:** Audio WAV (Content-Type: `audio/wav`)

**Esempio:**
```bash
curl -X POST http://localhost:8000/v1/tts/voice-clone \
  -F "text=Questa è la mia voce clonata!" \
  -F "ref_audio=@campione.wav" \
  -o output.wav
```

---

## Modelli Disponibili

| Nome CLI | Checkpoint HF | Tipo | Descrizione |
|----------|--------------|------|-------------|
| `cv` | `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` | CustomVoice | Voce con speaker predefinito + instruct stile |
| `vd` | `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` | VoiceDesign | Genera voce da descrizione testuale |
| `it` | `Aynursusuz/Qwen-TTS-Best-Model` | CustomVoice (fine-tune) | Italiano naturale, 115K campioni |
| `base` | `Qwen/Qwen3-TTS-12Hz-1.7B-Base` | Base | Modello base per voice-clone |

---

## Selezione Modello via API

Aggiungi `model=NOME` come parametro form-data (o query param) per selezionare il modello:

```bash
# Usa modello CustomVoice
curl -X POST "http://localhost:8000/v1/tts/custom-voice?model=cv" ...

# Usa modello italiano fine-tune
curl -X POST "http://localhost:8000/v1/tts/custom-voice?model=it" ...

# Usa VoiceDesign
curl -X POST "http://localhost:8000/v1/tts/voice-design?model=vd" ...
```

Se non specificato, viene usato il primo modello caricato.

---

## Esempi Python

```python
import requests

API = "http://localhost:8000"

# Lista modelli
r = requests.get(f"{API}/v1/models")
print(r.json())

# CustomVoice con instruct
r = requests.post(f"{API}/v1/tts/custom-voice", data={
    "model": "cv",
    "text": "Ciao mondo!",
    "speaker": "default_speaker",
    "instruct": "Voce allegra e giovanile",
})
with open("output.wav", "wb") as f:
    f.write(r.content)

# VoiceDesign
r = requests.post(f"{API}/v1/tts/voice-design", data={
    "model": "vd",
    "text": "Oggi parliamo di intelligenza artificiale",
    "instruct": "Voce maschile, seria, da conferenza TED",
})
with open("output.wav", "wb") as f:
    f.write(r.content)

# Fine-tune italiano
r = requests.post(f"{API}/v1/tts/custom-voice", data={
    "model": "it",
    "text": "Ciao a tutti, benvenuti sul mio canale! Oggi vediamo insieme una ricetta fantastica.",
    "speaker": "aldobaglio",
    "instruct": "Voce calda, accogliente, stile creator italiano",
})
with open("italiano.wav", "wb") as f:
    f.write(r.content)
```

---

## Note

- **Latenza CPU**: 1.7B su CPU ~10-30 secondi per frase breve. Con GPU molto più veloce.
- **RAM**: Ogni modello 1.7B occupa ~7GB in float32, ~3.5GB in float16/bfloat16.
- **Lingue supportate**: Auto-detect supporta: en, zh, ja, ko, fr, de, it, pt, es, ru, ar, th, nl, pl, vi, id, tr.
- **VoiceClone**: Richiede modello Base (`Qwen/Qwen3-TTS-12Hz-1.7B-Base`), non ancora disponibile in questa istanza.
- **DirectML**: Su Intel Arc A580 il caricamento funziona ma alcune operazioni crashano. Preferire WSL2+IPEX.
