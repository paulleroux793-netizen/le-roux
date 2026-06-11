# Ivory Chair-side Scribe — LAPTOP TEST.
# Run it, wait for "listening", talk for ~20-30 seconds, watch it transcribe. Uses YOUR laptop's
# default mic + the secure tunnel URL (works on any network). Installs NO auto-start task and
# posts to a throwaway "Laptop Test" device + test patient — nothing production is touched.
# Ctrl+C to stop.  Run:  powershell -ExecutionPolicy Bypass -File .\test-scribe-laptop.ps1
$ErrorActionPreference = "Stop"
$dir = $PSScriptRoot
if (-not $dir) { $dir = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location $dir
Write-Host "=== Ivory Scribe - LAPTOP TEST ===" -ForegroundColor Cyan

# 1) Python
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $py) { Write-Host "Python not found. Install Python 3.12 from python.org (tick 'Add python.exe to PATH'), then re-run." -ForegroundColor Red; exit 1 }
Write-Host "Python: $py" -ForegroundColor Green

# 2) venv + dependencies
$venvDir = Join-Path $dir ".venv"
if (-not (Test-Path $venvDir)) { & $py -m venv $venvDir }
$venvPy = Join-Path $venvDir "Scripts\python.exe"
Write-Host "Installing dependencies (first run downloads the ~75 MB Whisper model)..." -ForegroundColor Cyan
& $venvPy -m pip install -q --upgrade pip
& $venvPy -m pip install -q -r (Join-Path $dir "requirements.txt")

# 3) test config
# Scribe API token — from the SCRIBE_API_TOKEN env var, else prompt (not hardcoded, safe in git).
$ScribeToken = $env:SCRIBE_API_TOKEN
if (-not $ScribeToken) { $ScribeToken = Read-Host "Paste the Scribe API token (from Paul)" }
$envText = "SCRIBE_API_URL=https://ivory.chalitaleroux.co.za`r`n" +
           "SCRIBE_API_TOKEN=$ScribeToken`r`n" +
           "SCRIBE_DEVICE_NAME=Laptop Test`r`n" +
           "SCRIBE_WHISPER_MODEL=large-v3-turbo`r`n" +
           "SCRIBE_LANGUAGE=`r`n" +
           "SCRIBE_CHUNK_SECONDS=15`r`n" +
           "SCRIBE_HEARTBEAT_SECONDS=60`r`n" +
           "SCRIBE_AUDIO_INPUT_INDEX=`r`n"
[System.IO.File]::WriteAllText((Join-Path $dir ".env"), $envText)
Write-Host "Test config written (device 'Laptop Test', your default mic, secure URL)." -ForegroundColor Green

Write-Host ""
Write-Host "Starting the scribe. When you see 'listening on Laptop Test', TALK clearly for ~20-30 seconds" -ForegroundColor Yellow
Write-Host "(a few full dental sentences), then leave it running and tell Paul's assistant." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop when done." -ForegroundColor Yellow
Write-Host ""
& $venvPy (Join-Path $dir "daemon.py")
