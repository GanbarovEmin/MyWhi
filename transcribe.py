#!/usr/bin/env python3
"""
Hermes Dictate — local Faster-Whisper transcription.

Usage:
    transcribe.py <audio_path> [--model MODEL] [--language LANG]
                 [--compute-type TYPE] [--beam-size N] [--no-vad-filter]
                 [--output text|json]

Writes plain text to stdout (or JSON: {"text": "..."}).
Exits with non-zero status on error; error message goes to stderr.

Model selection is intentionally a CLI flag so the Swift app can
change it without re-importing the model.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import traceback
from pathlib import Path

# Defaults — match the spec.
DEFAULT_MODEL = "medium"
DEFAULT_LANGUAGE = "ru"
DEFAULT_COMPUTE_TYPE = "int8"
DEFAULT_BEAM_SIZE = 5


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="transcribe.py",
        description="Local Faster-Whisper transcription for Hermes Dictate.",
    )
    p.add_argument("audio_path", help="Path to audio file (WAV 16kHz mono preferred)")
    p.add_argument("--model", default=DEFAULT_MODEL,
                   help=f"Model size (default: {DEFAULT_MODEL})")
    p.add_argument("--language", default=DEFAULT_LANGUAGE,
                   help="Language: ru, en, or auto (default: ru)")
    p.add_argument("--compute-type", default=DEFAULT_COMPUTE_TYPE,
                   help="Compute type: int8, int8_float16, float16, float32 (default: int8)")
    p.add_argument("--beam-size", type=int, default=DEFAULT_BEAM_SIZE,
                   help=f"Beam size (default: {DEFAULT_BEAM_SIZE})")
    p.add_argument("--no-vad-filter", dest="vad_filter",
                   action="store_false", default=True,
                   help="Disable VAD filter")
    p.add_argument("--output", choices=["text", "json"], default="text",
                   help="Output format (default: text)")
    return p.parse_args(argv)


def transcribe(
    audio_path: str,
    model_size: str,
    language: str,
    compute_type: str,
    vad_filter: bool,
    beam_size: int,
) -> str:
    """Run WhisperModel.transcribe and return concatenated text."""
    # Import inside the function so import errors don't crash the whole CLI
    # when --help is invoked without faster-whisper installed.
    from faster_whisper import WhisperModel

    if not os.path.isfile(audio_path):
        raise FileNotFoundError(f"Audio file not found: {audio_path}")

    # Lazy model load. The model is downloaded to
    # ~/.cache/huggingface/hub/ on first use; subsequent calls reuse it.
    # device="auto" lets ctranslate2 pick CPU/GPU; on Apple Silicon
    # CPU with int8 is the safe, fast default.
    model = WhisperModel(
        model_size,
        device="auto",
        compute_type=compute_type,
    )

    # Language: "auto" -> let the model detect; otherwise pass through.
    lang_arg = None if language == "auto" else language

    segments, info = model.transcribe(
        audio_path,
        language=lang_arg,
        beam_size=beam_size,
        vad_filter=vad_filter,
    )

    # segments is a generator; we must iterate to actually run inference.
    parts: list[str] = []
    for segment in segments:
        parts.append(segment.text)

    text = "".join(parts).strip()

    # Diagnostic info on stderr (does not pollute stdout JSON/text).
    print(
        f"[transcribe.py] model={model_size} lang={info.language} "
        f"prob={info.language_probability:.2f} duration={info.duration:.1f}s "
        f"-> {len(text)} chars",
        file=sys.stderr,
        flush=True,
    )
    return text


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        text = transcribe(
            audio_path=args.audio_path,
            model_size=args.model,
            language=args.language,
            compute_type=args.compute_type,
            vad_filter=args.vad_filter,
            beam_size=args.beam_size,
        )
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr, flush=True)
        return 2
    except KeyboardInterrupt:
        print("ERROR: interrupted", file=sys.stderr, flush=True)
        return 130
    except Exception as e:  # noqa: BLE001
        print(f"ERROR: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        traceback.print_exc(file=sys.stderr)
        return 1

    if args.output == "json":
        # Strict JSON to stdout so Swift can parse reliably.
        sys.stdout.write(json.dumps({"text": text}, ensure_ascii=False))
        sys.stdout.write("\n")
    else:
        # Plain text to stdout. Add a trailing newline for friendliness.
        sys.stdout.write(text)
        if text and not text.endswith("\n"):
            sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
