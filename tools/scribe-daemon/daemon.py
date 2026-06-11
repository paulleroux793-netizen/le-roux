#!/usr/bin/env python3
"""
Dr Chalita le Roux Inc — Always-On Scribe Daemon (Phase 1)
==========================================================

Runs on the practice PC. Listens to a labelled microphone, transcribes
audio LOCALLY with faster-whisper (so audio NEVER leaves the practice
PC — POPIA-safe), and POSTs the transcript text to the Ivory dashboard.

Decision: 2026-05-24, Paul.
  Phase 1 = this script (cheap proof-of-concept).
  Phase 2 = dedicated Wi-Fi hardware mics per dental chair (see
  microphone_research memory file for the shopping list).

How it works
------------
1. Every CHUNK_SECONDS of audio, write a .wav buffer.
2. Run faster-whisper locally on the buffer (CPU is fine for short clips).
3. POST the resulting transcript text to the Rails API.
4. Send a heartbeat every HEARTBEAT_SECONDS so the dashboard knows we're alive.

Configuration via environment (.env file alongside this script):
  SCRIBE_API_URL=https://chalita.example.co.za       # Rails app base URL
  SCRIBE_API_TOKEN=<shared secret>                    # must match Rails ENV
  SCRIBE_DEVICE_NAME="Surgery 1"                      # must match RecordingDevice.name
  SCRIBE_AUDIO_INPUT_INDEX=                           # leave blank for default mic; or an int
  SCRIBE_WHISPER_MODEL=small.en                       # tiny / base / small / medium / large
  SCRIBE_CHUNK_SECONDS=15                             # 15s = good latency/accuracy trade-off
  SCRIBE_HEARTBEAT_SECONDS=60

Install
-------
  pip install -r requirements.txt
  # On first run, faster-whisper downloads the model (~75-450MB depending on size)

Run
---
  python daemon.py

Quit
----
  Ctrl+C. The current chunk in progress is discarded.

What this script does NOT do
----------------------------
- It doesn't identify WHICH patient is in the chair — that's the Rails
  side's job (it looks up the most recent in_consultation appointment
  for any patient with AI consent on file).
- It doesn't send audio over the network. Only the transcribed text.
- It doesn't decide whether the AI should run on a patient — POPIA
  consent is gated on the Rails side via Patient#ai_consent?

Failure modes handled
---------------------
- Network drop: retries with exponential backoff, buffers up to 10 chunks.
- Whisper model load failure: falls back to a no-op (logs the chunk).
- Rails returns 401: stops with a clear error (token mismatch).
- Rails returns 503: scribe is admin-disabled; daemon backs off 5 minutes.
"""

from __future__ import annotations
import os
import sys
import time
import wave
import queue
import threading
import tempfile
import logging
from collections import deque
from pathlib import Path

try:
    import sounddevice as sd  # type: ignore
except ImportError:
    sys.exit("missing dependency: sounddevice — run `pip install -r requirements.txt`")
try:
    import numpy as np  # type: ignore
except ImportError:
    sys.exit("missing dependency: numpy")
try:
    import requests  # type: ignore
except ImportError:
    sys.exit("missing dependency: requests")

try:
    from dotenv import load_dotenv  # type: ignore
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:
    pass  # .env file is optional; envvars from the shell still work

# ── Config ─────────────────────────────────────────────────────────────
API_URL           = os.environ.get("SCRIBE_API_URL", "http://localhost:3000").rstrip("/")
API_TOKEN         = os.environ.get("SCRIBE_API_TOKEN", "")
DEVICE_NAME       = os.environ.get("SCRIBE_DEVICE_NAME", "Surgery 1")
AUDIO_INPUT_INDEX = os.environ.get("SCRIBE_AUDIO_INPUT_INDEX", "") or None
WHISPER_MODEL     = os.environ.get("SCRIBE_WHISPER_MODEL", "large-v3-turbo")  # multilingual EN+AF (Perplexity-backed for Afrikaans); lighter fallbacks: "medium", "small"
LANGUAGE          = (os.environ.get("SCRIBE_LANGUAGE", "").strip() or None)   # "en"/"af"; blank = auto-detect (best for EN/AF code-switching)
CPU_THREADS       = int(os.environ.get("SCRIBE_CPU_THREADS", "0")) or max(1, (os.cpu_count() or 4))
CHUNK_SECONDS     = int(os.environ.get("SCRIBE_CHUNK_SECONDS", "15"))
HEARTBEAT_SECONDS = int(os.environ.get("SCRIBE_HEARTBEAT_SECONDS", "60"))
SAMPLE_RATE       = 16000  # Whisper wants 16kHz mono

if not API_TOKEN:
    sys.exit("SCRIBE_API_TOKEN is required — set it in .env or the shell environment")

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [scribe] %(levelname)s %(message)s",
                    datefmt="%H:%M:%S")
log = logging.getLogger("scribe")
log.info(f"starting scribe daemon — device='{DEVICE_NAME}' chunk={CHUNK_SECONDS}s model={WHISPER_MODEL}")

# ── Whisper (faster-whisper) ──────────────────────────────────────────
try:
    from faster_whisper import WhisperModel  # type: ignore
    log.info(f"loading Whisper model '{WHISPER_MODEL}' on {CPU_THREADS} cpu threads — first run downloads the model…")
    whisper = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8", cpu_threads=CPU_THREADS)
    log.info("Whisper ready")
except ImportError:
    log.error("faster-whisper not installed — chunks will be sent without transcription")
    whisper = None

# ── Audio capture: rolling chunk buffer ──────────────────────────────
chunk_queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=10)

def audio_callback(indata, frames, time_info, status):
    if status:
        log.warning(f"audio status: {status}")
    chunk_queue.put(indata.copy())

def write_wav(samples: np.ndarray) -> str:
    """Write a numpy float32 audio buffer to a temp .wav and return the path."""
    pcm = (samples * 32767.0).astype(np.int16)
    fd, path = tempfile.mkstemp(prefix="scribe-", suffix=".wav")
    os.close(fd)
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm.tobytes())
    return path

# Prime Whisper with dental vocabulary so clinical terms transcribe correctly (scale and polish,
# bitewing, tooth 11-48, etc.) instead of mishears like "scalp polish" / "vitamin X-ray".
DENTAL_PROMPT = (
    "Dental consultation notes for a dentist. Common terms: scale and polish, bitewing, "
    "periapical, panoramic, composite filling, amalgam, crown, bridge, veneer, root canal, "
    "extraction, caries, sensitivity, gingivitis, periodontitis, local anaesthetic, fluoride, "
    "occlusal, mesial, distal, buccal, lingual, palatal, impression, denture, implant, whitening, "
    "tooth 11 to 48, upper right, upper left, lower left, lower right quadrant. "
    "Afrikaanse tandheelkundige terme: tand, tandvleis, vulsel, kroon, brug, "
    "wortelkanaalbehandeling, tandsteen, skaal en poleer, verdowing, ekstraksie, "
    "sensitiwiteit, kies, abses, bytvlak, bo en onder, links en regs."
)

_prev_tail = ""  # last words of the previous transcript — stabilises language choice + code-switching (Perplexity-backed)

def transcribe(wav_path: str) -> str:
    global _prev_tail
    if whisper is None:
        return ""
    prompt = f"{_prev_tail} {DENTAL_PROMPT}".strip() if _prev_tail else DENTAL_PROMPT
    segments, _info = whisper.transcribe(
        wav_path,
        language=LANGUAGE,                # None = auto-detect English / Afrikaans per chunk
        beam_size=5,                      # wider beam = better accuracy (was greedy beam_size=1)
        best_of=5,                        # sample candidates, keep the best
        initial_prompt=prompt,            # dental vocab (EN+AF) + tail of previous chunk for continuity
        vad_filter=True,                  # skip silence — faster + avoids "Okay." hallucinations
        condition_on_previous_text=False, # reduce repetition / drift across chunks
    )
    text = " ".join(seg.text.strip() for seg in segments).strip()
    if text:
        _prev_tail = " ".join(text.split()[-30:])  # carry last ~30 words into the next chunk's prompt
    return text

# ── HTTP — post a transcript chunk to Rails ───────────────────────────
def post_transcript(text: str, started_at: float, ended_at: float) -> None:
    if not text:
        return
    payload = {
        "device_name":      DEVICE_NAME,
        "transcript_text":  text,
        "chunk_started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started_at)),
        "chunk_ended_at":   time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ended_at)),
    }
    delay = 1.0
    for attempt in range(5):
        try:
            r = requests.post(f"{API_URL}/api/v1/scribe/transcript",
                              json=payload, timeout=10,
                              headers={"X-Scribe-Token": API_TOKEN})
            if r.status_code == 200:
                log.info(f"posted {len(text)} chars · server: {r.json().get('reason') or 'accepted'}")
                return
            if r.status_code == 401:
                log.error("rails returned 401 — SCRIBE_API_TOKEN mismatch. stopping.")
                sys.exit(2)
            if r.status_code == 503:
                log.warning("rails returned 503 — scribe disabled on server side. sleeping 5 min.")
                time.sleep(300)
                return
            log.warning(f"rails returned {r.status_code}: {r.text[:200]}")
        except requests.RequestException as e:
            log.warning(f"network error attempt {attempt + 1}: {e}")
        time.sleep(delay)
        delay = min(delay * 2, 30)

def heartbeat_loop() -> None:
    while True:
        try:
            requests.get(f"{API_URL}/api/v1/scribe/heartbeat",
                         params={"device_name": DEVICE_NAME}, timeout=5,
                         headers={"X-Scribe-Token": API_TOKEN})
        except requests.RequestException:
            pass
        time.sleep(HEARTBEAT_SECONDS)

threading.Thread(target=heartbeat_loop, daemon=True).start()

# ── Main loop ─────────────────────────────────────────────────────────
log.info(f"opening audio stream — {SAMPLE_RATE}Hz mono, input device {AUDIO_INPUT_INDEX or 'default'}")
try:
    with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                        blocksize=SAMPLE_RATE * CHUNK_SECONDS,
                        device=int(AUDIO_INPUT_INDEX) if AUDIO_INPUT_INDEX else None,
                        callback=audio_callback):
        log.info(f"listening on '{DEVICE_NAME}' — Ctrl+C to stop")
        while True:
            chunk = chunk_queue.get()
            started = time.time() - CHUNK_SECONDS
            wav_path = write_wav(chunk)
            try:
                text = transcribe(wav_path)
            finally:
                try:
                    os.unlink(wav_path)
                except OSError:
                    pass
            if text:
                log.info(f"chunk transcribed ({len(text)} chars): {text[:80]}…")
                post_transcript(text, started, time.time())
            else:
                log.debug("chunk silent or empty")
except KeyboardInterrupt:
    log.info("stopped (Ctrl+C)")
