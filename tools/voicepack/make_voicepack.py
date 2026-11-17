#!/usr/bin/env python3
"""Raid.Earth: crea un voicepack de copiloto para BeamNG (mismo formato que los del juego) en otro idioma.

Lee las frases de un archivo como es.json (una por cada nota del juego: "four_right": "cuatro derecha"), las convierte
en voz con un motor TTS y escribe un mod listo para copiar a mods/:

  <salida>/lua/ge/extensions/gameplay/rally/compositors/voicepacks/<id>/
      voicepack.json   (nombre, idioma, estilo)
      metadata.json    (duración de cada audio)
      audio/pacenote_<nota>.ogg

Raid.Earth (y el rally del juego) listan cualquier voicepack de esa carpeta: el copiloto se elige en Ajustes.

Motores:
  --engine piper    voz neuronal, la mejor. Necesita `pip install piper-tts` y un modelo .onnx (con su .onnx.json),
                    p. ej. es_ES-davefx-medium de https://huggingface.co/rhasspy/piper-voices (mira su licencia).
  --engine sapi     voces de Windows (Configuración → Hora e idioma → Voz: instala "Español (España)"). pip install pyttsx3
  --engine espeak   espeak-ng (suena robótico; para probar).
Hace falta ffmpeg para pasar a .ogg.

Ejemplo:
  python make_voicepack.py --phrases es.json --engine piper --model es_ES-davefx-medium.onnx \
      --id raidearth_es_davefx --persona "Copiloto (español)" --dialect es-ES --out build/voice_es
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

VP_DIR = "lua/ge/extensions/gameplay/rally/compositors/voicepacks"


def tts_piper(text, wav, args):
    from piper import PiperVoice  # piper-tts
    import wave
    voice = tts_piper.voice = getattr(tts_piper, "voice", None) or PiperVoice.load(args.model)
    with wave.open(wav, "wb") as w:
        if hasattr(voice, "synthesize_wav"):
            voice.synthesize_wav(text, w)
        else:
            voice.synthesize(text, w, length_scale=args.speed)


def tts_espeak(text, wav, args):
    subprocess.run(["espeak-ng", "-v", args.voice or "es", "-s", str(int(175 / args.speed)), "-w", wav, text], check=True)


def tts_sapi(text, wav, args):
    import pyttsx3
    eng = tts_sapi.eng = getattr(tts_sapi, "eng", None) or pyttsx3.init()
    if args.voice:
        for v in eng.getProperty("voices"):
            if args.voice.lower() in (v.name or "").lower() or args.voice.lower() in (v.id or "").lower():
                eng.setProperty("voice", v.id)
                break
    eng.setProperty("rate", int(190 / args.speed))
    eng.save_to_file(text, wav)
    eng.runAndWait()


ENGINES = {"piper": tts_piper, "espeak": tts_espeak, "sapi": tts_sapi}


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout.strip()
    return float(out or 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--phrases", required=True)
    ap.add_argument("--engine", choices=ENGINES, default="piper")
    ap.add_argument("--model", help="modelo .onnx de Piper")
    ap.add_argument("--voice", help="voz (espeak: es, es-419...; sapi: parte del nombre, p. ej. Helena)")
    ap.add_argument("--speed", type=float, default=0.9, help="<1 más rápido (los copilotos leen deprisa)")
    ap.add_argument("--id", required=True, help="carpeta del voicepack (sin espacios)")
    ap.add_argument("--persona", default="Copiloto")
    ap.add_argument("--language", default="ui.options.rally.languages.spanish.name")
    ap.add_argument("--dialect", default="es-ES")
    ap.add_argument("--out", required=True)
    ap.add_argument("--zip", help="además, un .zip del mod listo para mods/")
    args = ap.parse_args()

    phrases = {k: v for k, v in json.load(open(args.phrases, encoding="utf-8")).items() if not k.startswith("_")}
    dest = os.path.join(args.out, VP_DIR, args.id)
    os.makedirs(os.path.join(dest, "audio"), exist_ok=True)
    meta = {}
    tts = ENGINES[args.engine]
    with tempfile.TemporaryDirectory() as tmp:
        for i, (note, text) in enumerate(sorted(phrases.items()), 1):
            wav = os.path.join(tmp, note + ".wav")
            name = "pacenote_" + note + ".ogg"
            ogg = os.path.join(dest, "audio", name)
            tts(text, wav, args)
            # recorta silencios y normaliza: las notas se encadenan una tras otra
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-af",
                            "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
                            "silenceremove=start_periods=1:start_threshold=-45dB,areverse,loudnorm=I=-16:TP=-1.5",
                            "-ar", "44100", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
            meta[name] = {"audioLen": round(duration(ogg), 6)}
            print(f"[{i}/{len(phrases)}] {note}: {text}")
    json.dump(meta, open(os.path.join(dest, "metadata.json"), "w"), indent=2)
    json.dump({
        "persona": args.persona, "language": args.language, "dialect": args.dialect,
        "compositorStyle": "english/enthusiast", "notebooks": ["enthusiast", "structured"],
        "styleLabel": "ui.options.rally.styles.enthusiast.name", "styleDetailLevel": 50, "enableSpeedScaling": True,
        "codriverTimingOffsetSeconds": 0.0, "linkWordGapMs": 0, "cornerGapMs": -30, "phraseGapMs": 0, "pacenoteGapMs": 200,
    }, open(os.path.join(dest, "voicepack.json"), "w"), indent=2)
    if args.zip:
        with zipfile.ZipFile(args.zip, "w", zipfile.ZIP_DEFLATED) as z:
            for root, _, files in os.walk(args.out):
                for f in files:
                    p = os.path.join(root, f)
                    z.write(p, os.path.relpath(p, args.out))
        print("zip:", args.zip)
    print("voicepack:", dest)


if __name__ == "__main__":
    if not shutil.which("ffmpeg"):
        sys.exit("Falta ffmpeg")
    main()
