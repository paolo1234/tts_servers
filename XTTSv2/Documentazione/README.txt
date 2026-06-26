╔══════════════════════════════════════════╗
║        XTTSv2 TTS Server - Portable      ║
║         Installazione 1-Click            ║
╚══════════════════════════════════════════╝

COME USARE (su QUALSIASI PC Windows):
  1. Fai doppio click su "install_xtts_server.bat"
  2. L'installer scarica Python (se serve), crea venv,
     installa PyTorch, Coqui TTS, Flask (~10-30 min)
  3. Fai doppio click su "start_xtts.bat"
  4. Server pronto su http://localhost:8001

SE SERVE RIAVVIO:
  Dopo installazione Python, riavvia il PC se il .bat
  dice "Python non rilevato dopo installazione"

TEST RAPIDO:
  curl -X POST http://localhost:8001/api/tts ^
    -F "text=Ciao mondo!" ^
    -F "speaker_wav=isabella_ref.wav" ^
    -F "language=it" ^
    -o test.wav

LINGUE: it, en, de, fr, es
SPEAKER: isabella_ref.wav, giuseppe_ref.wav, diego_ref.wav, elsa_ref.wav

NOTA: Il modello XTTSv2 (~2GB) si scarica al primo avvio del server.
PC con GPU NVIDIA consigliata.
