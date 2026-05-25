# Always-On Scribe Daemon — Phase 1

Background listener for one labelled microphone in Dr Chalita le Roux's practice.
Streams short transcripts (NOT audio) to the Ivory dashboard so the dentist's
in-chair conversations get summarised + auto-drafted into estimates without
anyone clicking a "record" button.

**Phase 1 (this script):** runs on the practice PC, uses its mic. Cheap proof
of concept — Paul confirms 2026-05-24 to start here.
**Phase 2 (later):** wall- or ceiling-mounted Wi-Fi/PoE mics per dental chair.
See the [microphone_research_2026_05_24](../../../../memory/microphone_research_2026_05_24.md)
memory file for the shopping list.

## What it does

```
   ┌──────────────────────────┐         ┌──────────────────────────┐
   │  Mic on practice PC      │  audio  │  faster-whisper          │
   │  (built-in / USB / etc.) ├────────►│  LOCAL transcription     │
   └──────────────────────────┘         └────────────┬─────────────┘
                                                     │ text only
                                                     ▼
                                        ┌──────────────────────────┐
                                        │  POST /api/v1/scribe/    │
                                        │  transcript              │
                                        │  (Rails app)             │
                                        └──────────────────────────┘
```

Audio is transcribed **locally on the practice PC** — Whisper runs offline.
Only the **transcript text** is sent over the network. This is the POPIA-safe
posture: raw audio of patient consultations never leaves your premises.

## Quick start (Windows / WSL / macOS / Linux)

```bash
cd tools/scribe-daemon
python -m venv .venv && .venv/Scripts/activate   # on Mac/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env — set SCRIBE_API_TOKEN to the value from the Rails app's SCRIBE_API_TOKEN env var
python daemon.py
```

On first run, faster-whisper downloads the `small.en` model (~75 MB). Subsequent
runs are instant. You'll see lines like:

```
[scribe] INFO starting scribe daemon — device='Surgery 1' chunk=15s model=small.en
[scribe] INFO Whisper ready
[scribe] INFO listening on 'Surgery 1' — Ctrl+C to stop
[scribe] INFO chunk transcribed (84 chars): "I'll check tooth thirty-six — looks like a small distal caries…"
[scribe] INFO posted 84 chars · server: accepted
```

## Configuration

All via `.env` (gitignored — see `.env.example`).

| Variable | Default | Meaning |
|---|---|---|
| `SCRIBE_API_URL` | `http://localhost:3000` | Where the Rails app lives. For prod: your Railway URL. |
| `SCRIBE_API_TOKEN` | — | Shared secret. Must match the Rails env var of the same name. |
| `SCRIBE_DEVICE_NAME` | `Surgery 1` | Must match a `RecordingDevice.name` in the Rails app. |
| `SCRIBE_AUDIO_INPUT_INDEX` | (default mic) | Index of the audio device to listen on. List via `python -c "import sounddevice; print(sounddevice.query_devices())"`. |
| `SCRIBE_WHISPER_MODEL` | `small.en` | `tiny.en` faster but less accurate; `medium.en` slower but better. |
| `SCRIBE_CHUNK_SECONDS` | `15` | How often we batch + send. Lower = more responsive UI, higher = better accuracy. |
| `SCRIBE_HEARTBEAT_SECONDS` | `60` | Keepalive ping interval. |

## Run as a Windows service (Phase 1 production)

```powershell
# Install nssm (https://nssm.cc), then:
nssm install ChalitaScribe "C:\path\to\.venv\Scripts\python.exe" "C:\path\to\daemon.py"
nssm set ChalitaScribe AppDirectory "C:\path\to\tools\scribe-daemon"
nssm set ChalitaScribe Start SERVICE_AUTO_START
nssm start ChalitaScribe
```

## Run on each dental chair (Phase 2 with hardware mics)

Once we have the wall/ceiling-mounted Wi-Fi mics for each surgery (see the
hardware shopping list), the same script runs on each device, with
`SCRIBE_DEVICE_NAME` set to `Surgery 1` or `Surgery 2` respectively. The Rails
app routes each chunk to the right patient using the recording-device label.

## Failure modes

- **Network drop:** retries with exponential backoff. Up to ~30s between retries.
- **Whisper missing:** logs an error, runs without transcription (chunks
  recorded but not posted).
- **Token mismatch (401):** stops with a clear error so you notice immediately.
- **Server disabled (503):** scribe is off on the server side — daemon sleeps
  5 minutes then resumes.
- **No active appointment with AI consent:** server silently drops chunks. The
  log shows "no_active_appointment_with_consent" so you can confirm the
  daemon is working but legitimately has nothing to attach to.

## What this script does NOT do

- It does **not** identify which patient is in the chair. That's the Rails
  server's job: it looks for the most recent in_consultation appointment
  with a consented patient and attaches the transcript to that.
- It does **not** send audio over the network. Only the transcribed text.
- It does **not** override the patient's consent flag. If the patient hasn't
  signed the paper form, no summary will ever be written — the daemon can
  keep running, but its chunks get dropped server-side.
