╔═══════════════════════════════════════╗
║   QWEN3-TTS SERVER - GUIDA RAPIDA    ║
╚═══════════════════════════════════════╝

COME USARE (solo 2 passaggi):

  [1] Fai doppio click su:  1 - INSTALL.bat
      (Installa Python, venv, dipendenze... aspetta)

  [2] Fai doppio click su:  2 - START GPU.bat  (se hai GPU)
                         o  2 - START CPU.bat   (se non hai GPU)

  🎯 Server pronto su http://localhost:8000

TEST VELOCE (apri CMD dopo aver avviato il server):
  curl -X POST http://localhost:8000/v1/tts/custom-voice ^
    -F "text=Ciao mondo!" -F "model=cv" -F "speaker=Vivian" -o test.wav

CARTELLA "Altri script\":
  Server con modelli alternativi:
  - Avvia - CustomVoice 1.7B (GPU).bat     → 9 voci predefinite
  - Avvia - VoiceDesign 1.7B.bat           → Voce generata da descrizione
    Esempio: "Voce calda, femminile, italiana, professionale"
  - Avvia - VoiceClone Base 1.7B.bat       → Clona voce da file audio
    (serve audio di riferimento .wav)
  - Avvia - Italiano Fine-Tune.bat         → Modello italiano specializzato
  - Avvia - CPU Veloce 0.6B.bat            → Modello leggero per CPU
  - Avvia - Menu Multi-Modello.bat         → Menu interattivo per scegliere
  - genera_voce_riferimento.py             → Utility per creare reference audio
  - install_and_run (originale).bat        → Installer originale
  - install_qwen_server (senza Python).bat → Installer senza download Python

CARTELLA "Documentazione\":
  - API_REFERENCE.md    = Specifiche tecniche API
  - README (ufficiale)  = Documentazione originale
  - PROVIDER_CONFIG.txt = Guida integrazione in altre app

SERVER:
  http://localhost:8000
  POST /v1/tts/custom-voice   → Sintesi vocale
  POST /v1/tts/voice-design   → Voce da descrizione
  POST /v1/tts/voice-clone    → Clonazione voce
  GET  /health                 → Stato server
  GET  /v1/models              → Modelli caricati

NOTA: I modelli si scaricano da HuggingFace al primo avvio.
      GPU NVIDIA raccomandata (8GB+ VRAM).
      Su CPU usa "2 - START CPU.bat" (modello 0.6B).
