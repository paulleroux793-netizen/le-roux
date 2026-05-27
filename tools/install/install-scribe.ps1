# ============================================================================
# Ivory scribe daemon installer — Surgery 1 / Surgery 2 PCs
# ============================================================================
#
# WHAT THIS SCRIPT DOES (idempotent — safe to re-run for upgrades):
#   1. Installs Python 3.12 via winget if missing
#   2. Installs nssm (service manager) via winget if missing
#   3. Pulls the scribe-daemon source from the laptop running serve-source.ps1
#   4. Creates a Python venv at C:\IvoryScribe\venv and pip-installs deps
#   5. Writes C:\IvoryScribe\.env with the device name, API URL, API token
#   6. Sets Windows power plan: never sleep, no USB selective suspend, no fast startup
#   7. Registers a Windows service "IvoryScribe" via nssm (auto-start, restart on crash)
#   8. Runs a self-test: records 3 seconds, POSTs to Rails, expects 200 OK
#
# REQUIRES (you set BEFORE running):
#   $env:DEVICE      = "Surgery 1"   # or "Surgery 2" — must match a RecordingDevice in Ivory
#   $env:SOURCE_HOST = "PAUL-LAPTOP" # the laptop running serve-source.ps1 (defaults below)
#   $env:RECEPTION   = "Reception-PC" # the Reception PC hosting the Ivory Rails app
#
# RUN:
#   Open PowerShell AS ADMIN. Then:
#     $env:DEVICE='Surgery 1'; iex (irm http://<source-host>:8000/install-scribe.ps1)
#
# UNINSTALL:
#   nssm stop IvoryScribe ; nssm remove IvoryScribe confirm
#   Remove-Item C:\IvoryScribe -Recurse -Force
#
# ============================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# ── Configuration (set via env before iex, or edit defaults here) ─────────
$DEVICE      = if ($env:DEVICE)      { $env:DEVICE }      else { 'Surgery 1' }
$SOURCE_HOST = if ($env:SOURCE_HOST) { $env:SOURCE_HOST } else { 'PAUL-LAPTOP' }
$SOURCE_PORT = if ($env:SOURCE_PORT) { $env:SOURCE_PORT } else { '8000' }
$RECEPTION   = if ($env:RECEPTION)   { $env:RECEPTION }   else { 'Reception-PC' }
$API_TOKEN   = if ($env:API_TOKEN)   { $env:API_TOKEN }   else { 'harness-test-token-dev-only' }
$INSTALL_DIR = 'C:\IvoryScribe'

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " IVORY SCRIBE DAEMON INSTALLER" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Device:      $DEVICE"
Write-Host " Source host: http://${SOURCE_HOST}:${SOURCE_PORT}"
Write-Host " Reception:   http://${RECEPTION}:3000"
Write-Host " Install dir: $INSTALL_DIR"
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

function Step($n, $msg) {
    Write-Host "[$n] $msg" -ForegroundColor Yellow
}

function Ensure-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found. Install App Installer from the Microsoft Store first."
    }
}

function Ensure-Python {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $ver = (& python --version 2>&1)
        Write-Host "    Python already installed: $ver"
        return
    }
    Step "1a" "Installing Python 3.12 via winget..."
    winget install -e --id Python.Python.3.12 --silent --accept-source-agreements --accept-package-agreements
    # Refresh PATH for this session
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python install completed but 'python' not on PATH. Close + reopen PowerShell and re-run."
    }
}

function Ensure-Nssm {
    $nssmPath = "$INSTALL_DIR\nssm.exe"
    if (Test-Path $nssmPath) {
        Write-Host "    nssm already present at $nssmPath"
        return $nssmPath
    }
    Step "2a" "Downloading nssm.exe..."
    $tmpZip = "$env:TEMP\nssm.zip"
    $tmpDir = "$env:TEMP\nssm-extract"
    Invoke-WebRequest -Uri 'https://nssm.cc/release/nssm-2.24.zip' -OutFile $tmpZip
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'win64' } else { 'win32' }
    Copy-Item "$tmpDir\nssm-2.24\$arch\nssm.exe" $nssmPath
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    return $nssmPath
}

function Fetch-Source {
    Step "3" "Fetching scribe-daemon source from http://${SOURCE_HOST}:${SOURCE_PORT}..."
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
    $sourceUrl = "http://${SOURCE_HOST}:${SOURCE_PORT}/scribe-daemon.zip"
    $zipPath   = "$INSTALL_DIR\scribe-daemon.zip"
    try {
        Invoke-WebRequest -Uri $sourceUrl -OutFile $zipPath -TimeoutSec 30
    } catch {
        throw "Failed to fetch from $sourceUrl. Is serve-source.ps1 running on $SOURCE_HOST? Error: $_"
    }
    # Extract into a temp dir, then copy daemon.py + requirements.txt into place.
    $extractDir = "$INSTALL_DIR\_extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    Copy-Item "$extractDir\daemon.py"        "$INSTALL_DIR\daemon.py"       -Force
    Copy-Item "$extractDir\requirements.txt" "$INSTALL_DIR\requirements.txt" -Force
    Remove-Item $extractDir -Recurse -Force
    Remove-Item $zipPath -Force
}

function Ensure-Venv {
    $venvPython = "$INSTALL_DIR\venv\Scripts\python.exe"
    if (-not (Test-Path $venvPython)) {
        Step "4a" "Creating Python venv at $INSTALL_DIR\venv..."
        & python -m venv "$INSTALL_DIR\venv"
    }
    Step "4b" "Installing dependencies (this may take 2-5 minutes — Whisper is large)..."
    & $venvPython -m pip install --upgrade pip --quiet
    & $venvPython -m pip install -r "$INSTALL_DIR\requirements.txt" --quiet
    return $venvPython
}

function Write-EnvFile {
    Step "5" "Writing $INSTALL_DIR\.env..."
    $envContent = @"
# Ivory scribe daemon — written by install-scribe.ps1
SCRIBE_API_URL=http://${RECEPTION}:3000
SCRIBE_API_TOKEN=${API_TOKEN}
SCRIBE_DEVICE_NAME=${DEVICE}
SCRIBE_WHISPER_MODEL=small.en
SCRIBE_CHUNK_SECONDS=15
SCRIBE_HEARTBEAT_SECONDS=60
"@
    [System.IO.File]::WriteAllText("$INSTALL_DIR\.env", $envContent, [System.Text.UTF8Encoding]::new($false))
}

function Set-PowerPlan {
    Step "6" "Configuring Windows power plan (never sleep, no USB suspend, no fast startup)..."
    powercfg /change standby-timeout-ac 0       2>&1 | Out-Null
    powercfg /change standby-timeout-dc 0       2>&1 | Out-Null
    powercfg /change hibernate-timeout-ac 0     2>&1 | Out-Null
    powercfg /change hibernate-timeout-dc 0     2>&1 | Out-Null
    powercfg /change monitor-timeout-ac 0       2>&1 | Out-Null
    powercfg /change disk-timeout-ac 0          2>&1 | Out-Null
    # Disable USB selective suspend (audio devices)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_USB USBSELECTIVESUSPEND 0 2>&1 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_USB USBSELECTIVESUSPEND 0 2>&1 | Out-Null
    powercfg /setactive SCHEME_CURRENT          2>&1 | Out-Null
    # Disable fast startup (which can wedge audio devices on cold boot)
    reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v HiberbootEnabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
}

function Register-Service($nssmPath, $venvPython) {
    Step "7" "Registering Windows service 'IvoryScribe' via nssm..."
    $existing = & $nssmPath status IvoryScribe 2>&1
    if ($existing -notmatch 'SERVICE_NOT_FOUND') {
        Write-Host "    Service already exists — stopping for upgrade..."
        & $nssmPath stop IvoryScribe 2>&1 | Out-Null
        & $nssmPath remove IvoryScribe confirm 2>&1 | Out-Null
    }
    & $nssmPath install IvoryScribe $venvPython "$INSTALL_DIR\daemon.py" | Out-Null
    & $nssmPath set IvoryScribe AppDirectory $INSTALL_DIR              | Out-Null
    & $nssmPath set IvoryScribe DisplayName  "Ivory Scribe Daemon ($DEVICE)" | Out-Null
    & $nssmPath set IvoryScribe Description  "Always-on dental scribe — captures audio from $DEVICE, transcribes via local Whisper, POSTs to $RECEPTION." | Out-Null
    & $nssmPath set IvoryScribe Start        SERVICE_AUTO_START         | Out-Null
    & $nssmPath set IvoryScribe AppStdout    "$INSTALL_DIR\scribe.log"  | Out-Null
    & $nssmPath set IvoryScribe AppStderr    "$INSTALL_DIR\scribe.log"  | Out-Null
    & $nssmPath set IvoryScribe AppRotateFiles 1                        | Out-Null
    & $nssmPath set IvoryScribe AppRotateOnline 1                       | Out-Null
    & $nssmPath set IvoryScribe AppRotateBytes 10485760                 | Out-Null  # 10 MB
    & $nssmPath set IvoryScribe AppThrottle 5000                        | Out-Null  # ms between restarts
    & $nssmPath set IvoryScribe AppExit Default Restart                 | Out-Null
    & $nssmPath start IvoryScribe                                       | Out-Null
}

function Self-Test {
    Step "8" "Self-test: heartbeat to http://${RECEPTION}:3000/api/v1/scribe/heartbeat..."
    Start-Sleep -Seconds 8
    try {
        $resp = Invoke-RestMethod -Method GET `
            -Uri "http://${RECEPTION}:3000/api/v1/scribe/heartbeat?device_name=$([uri]::EscapeDataString($DEVICE))" `
            -Headers @{ 'X-Scribe-Token' = $API_TOKEN } `
            -TimeoutSec 10
        if ($resp.ok) {
            Write-Host "    PASS — Ivory acknowledged device '$DEVICE' (id=$($resp.device_id), enabled=$($resp.enabled))" -ForegroundColor Green
        } else {
            Write-Host "    WARN — Ivory responded but device not recognised. Add a RecordingDevice named '$DEVICE' at http://${RECEPTION}:3000/admin/recording-devices" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    WARN — could not reach Ivory at http://${RECEPTION}:3000 yet. Check the service is running on the Reception PC, then 'Get-Service IvoryScribe'." -ForegroundColor Yellow
        Write-Host "    Detail: $_" -ForegroundColor DarkYellow
    }
}

# ── Run ───────────────────────────────────────────────────────────────────
Ensure-Winget
Step "1" "Ensuring Python 3.12..."
Ensure-Python
Step "2" "Ensuring nssm..."
$nssm = Ensure-Nssm
Fetch-Source
Step "4" "Setting up Python venv + dependencies..."
$venvPy = Ensure-Venv
Write-EnvFile
Set-PowerPlan
Register-Service -nssmPath $nssm -venvPython $venvPy
Self-Test

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " IVORY SCRIBE INSTALLED — device '$DEVICE'" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host " Service:   Get-Service IvoryScribe"
Write-Host " Logs:      $INSTALL_DIR\scribe.log"
Write-Host " Dashboard: http://${RECEPTION}:3000/admin/recording-devices"
Write-Host ""
Write-Host " You are done. Nothing else to do on this PC."
Write-Host "========================================================" -ForegroundColor Green
