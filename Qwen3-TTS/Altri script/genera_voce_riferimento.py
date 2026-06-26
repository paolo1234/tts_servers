"""
Genera una voce di riferimento perfetta usando VoiceDesign,
da usare poi con il voice clone.
"""
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

device = "cpu"
dtype = torch.float32

print("Caricamento modello VoiceDesign (prima volta richiede download)...")
tts = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
    device_map=device,
    dtype=dtype,
)

text = "Ciao, sono una voce naturale e professionale. Posso leggere qualsiasi testo per te con un tono caldo e piacevole."
instruct = "Voce femminile italiana calda, naturale, morbida, con tono professionale ma amichevole. Dizione chiara e rilassata."

print("Generazione voce di riferimento...")
wavs, sr = tts.generate_voice_design(
    text=text,
    language="Italian",
    instruct=instruct,
    non_streaming_mode=True,
)

sf.write("voce_riferimento.wav", wavs[0], sr)
print(f"OK - salvato voce_riferimento.wav ({sr}Hz)")
