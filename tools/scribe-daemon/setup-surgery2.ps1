# Ivory Chair-side Scribe — ONE-CLICK setup for Surgery 2 (Dr Eliska).
#
# Run it ON the Surgery 2 PC: right-click this file -> "Run with PowerShell"
#   (or in PowerShell:  powershell -ExecutionPolicy Bypass -File .\setup-surgery2.ps1 )
#
# It installs Python (if needed), the daemon's dependencies, auto-detects the Lark M2 mic,
# writes the config, sets the scribe to auto-start on login, and starts it now.
# Idempotent — safe to run again.

$ErrorActionPreference = "Stop"
$dir = $PSScriptRoot
if (-not $dir) { $dir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $dir) { $dir = (Get-Location).Path }
Set-Location $dir
Write-Host "=== Ivory Scribe setup - Surgery 2 (Dr Eliska) ===" -ForegroundColor Cyan

# 0) Keep this PC ALWAYS AWAKE (a sleeping PC stops transcribing + drops off Tailscale) -------
Write-Host "Setting this PC to never sleep/hibernate..." -ForegroundColor Cyan
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
powercfg /change disk-timeout-ac 0
try { powercfg /hibernate off 2>$null } catch {}
Write-Host "This PC will now stay awake (screen may still turn off - that's fine)." -ForegroundColor Green

# 1) Ensure a REAL Python (the Microsoft Store "python.exe" stub in WindowsApps does NOT count) -
function Find-Python {
  foreach ($c in (Get-Command python.exe -All -ErrorAction SilentlyContinue)) {
    if ($c.Source -notmatch 'WindowsApps') {
      try { if ((& $c.Source --version 2>&1) -match 'Python 3') { return $c.Source } } catch {}
    }
  }
  foreach ($p in @(
      "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
      "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
      "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
      "$env:ProgramFiles\Python313\python.exe",
      "$env:ProgramFiles\Python312\python.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}
$python = Find-Python
if (-not $python) {
  Write-Host "Installing real Python (a few minutes)..." -ForegroundColor Yellow
  winget install -e --id Python.Python.3.12 --scope user --accept-package-agreements --accept-source-agreements
  Start-Sleep -Seconds 3
  $python = Find-Python
}
if (-not $python) {
  Write-Host "Could not auto-install Python. Install Python 3.12 from https://www.python.org/downloads/" -ForegroundColor Red
  Write-Host "(tick 'Add python.exe to PATH' during install), then re-run this script." -ForegroundColor Red
  Read-Host "Press Enter to close"; exit 1
}
Write-Host "Python: $python" -ForegroundColor Green

# 2) Virtual env + dependencies ---------------------------------------------
# A .venv copied from another PC (e.g. via OneDrive) won't run here — validate it and rebuild if broken.
$venvPy = Join-Path $dir ".venv\Scripts\python.exe"
$venvOk = Test-Path $venvPy
if ($venvOk) { try { & $venvPy --version *> $null; if ($LASTEXITCODE -ne 0) { $venvOk = $false } } catch { $venvOk = $false } }
if (-not $venvOk) {
  if (Test-Path "$dir\.venv") { Write-Host "Rebuilding the Python environment for THIS PC..." -ForegroundColor Yellow; Remove-Item "$dir\.venv" -Recurse -Force }
  & $python -m venv .venv
}
& $venvPy -m pip install --upgrade pip --quiet
Write-Host "Installing dependencies (faster-whisper, sounddevice, ...)..."
& $venvPy -m pip install -r requirements.txt
Write-Host "Dependencies installed." -ForegroundColor Green

# 3) Auto-detect the Lark M2 microphone -------------------------------------
$idx = & $venvPy -c "import sounddevice as sd; ds=sd.query_devices(); h=[str(i) for i,d in enumerate(ds) if d['max_input_channels']>0 and ('lark' in d['name'].lower() or 'hollyland' in d['name'].lower())]; print(h[0] if h else '')"
$idx = ($idx | Out-String).Trim()
if ($idx) {
  Write-Host "Found the Lark M2 microphone at input index $idx" -ForegroundColor Green
} else {
  Write-Host "Lark M2 not auto-detected - using the Windows DEFAULT input. Set the Lark M2 as the" -ForegroundColor Yellow
  Write-Host "default microphone in Sound settings, then re-run this script." -ForegroundColor Yellow
}

# 4) Write the config (.env) -------------------------------------------------
# Scribe API token — read from the SCRIBE_API_TOKEN env var, else prompt. NOT hardcoded,
# so this script is safe to keep in git. Ask Paul / see _shared/.env for the value.
$ScribeToken = $env:SCRIBE_API_TOKEN
if (-not $ScribeToken) { $ScribeToken = Read-Host "Paste the Scribe API token (from Paul)" }
$envText = "SCRIBE_API_URL=http://10.0.0.125:3000`r`n" +
           "SCRIBE_API_TOKEN=$ScribeToken`r`n" +
           "SCRIBE_DEVICE_NAME=Surgery 2`r`n" +
           "SCRIBE_WHISPER_MODEL=large-v3-turbo`r`n" +
           "SCRIBE_LANGUAGE=`r`n" +
           "SCRIBE_CHUNK_SECONDS=15`r`n" +
           "SCRIBE_AUDIO_INPUT_INDEX=$idx`r`n"
[System.IO.File]::WriteAllText((Join-Path $dir ".env"), $envText)
Write-Host "Config written (device 'Surgery 2', model large-v3-turbo - English + Afrikaans auto-detect)." -ForegroundColor Green

# 5) Auto-start on every login (pythonw = no console window) ------------------
$pyw    = Join-Path $dir ".venv\Scripts\pythonw.exe"
$daemon = Join-Path $dir "daemon.py"
schtasks /Create /TN "IvoryScribeSurgery2" /TR "`"$pyw`" `"$daemon`"" /SC ONLOGON /RL HIGHEST /F | Out-Null
Write-Host "Auto-start registered - the scribe will launch by itself on every login." -ForegroundColor Green

# 5b) Connectivity check — confirm we can reach Ivory before starting ---------
Write-Host "Checking connection to Ivory..." -ForegroundColor Cyan
try {
  $resp = Invoke-RestMethod -Uri "http://10.0.0.125:3000/api/v1/scribe/heartbeat?device_name=Surgery%202" `
            -Headers @{ "X-Scribe-Token" = $ScribeToken } -TimeoutSec 8
  if ($resp.ok) { Write-Host "Connected to Ivory - device 'Surgery 2' is registered and enabled." -ForegroundColor Green }
  else { Write-Host "Reached Ivory but the device is not enabled - tell Paul." -ForegroundColor Yellow }
} catch {
  Write-Host "Could NOT reach Ivory at 10.0.0.125:3000 - check this PC is on the practice network." -ForegroundColor Red
  Write-Host "(The scribe will keep retrying automatically once started.)" -ForegroundColor Yellow
}

# 6) Start it now (downloads the model on first run, then starts listening) ----
Write-Host ""
Write-Host "Starting the scribe now. FIRST RUN downloads the English+Afrikaans model" -ForegroundColor Cyan
Write-Host "(~1.5 GB, a few minutes - ONCE only; instant every time after)." -ForegroundColor Cyan
Write-Host "When you see   listening on 'Surgery 2'   it is WORKING. You can close this window then -" -ForegroundColor Cyan
Write-Host "it auto-starts on every login from now on." -ForegroundColor Cyan
Write-Host ""
& $venvPy daemon.py
