# ============================================================================
# Ivory full-stack installer — Reception-PC
# ============================================================================
#
# Installs the complete Ivory practice-management system on Reception-PC:
#   * Docker Desktop (via winget) if missing
#   * Ivory source code pulled from the laptop running serve-source.ps1
#   * docker compose stack (Postgres + Rails + Vite) brought up as auto-start
#   * Scribe daemon for the Reception PC's own UB1 mic (POSTs to localhost:3000)
#   * Windows power plan locked: never sleep, no USB suspend, no fast startup
#   * Self-tests: Rails /up, scribe heartbeat, dashboard reachable
#
# REQUIRES (you set BEFORE running):
#   $env:SOURCE_HOST = "PAUL-LAPTOP"   # the laptop running serve-source.ps1
#   $env:API_TOKEN   = "..."            # shared scribe-API secret (default below)
#
# RUN:
#   Open PowerShell AS ADMIN. Then:
#     iex (irm http://<source-host>:8000/install-reception.ps1)
#
# After this completes:
#   Surgery 1 PC: run install-scribe.ps1 with $env:DEVICE='Surgery 1'
#   Surgery 2 PC: run install-scribe.ps1 with $env:DEVICE='Surgery 2'
#
# ============================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$SOURCE_HOST = if ($env:SOURCE_HOST) { $env:SOURCE_HOST } else { 'PAUL-LAPTOP' }
$SOURCE_PORT = if ($env:SOURCE_PORT) { $env:SOURCE_PORT } else { '8000' }
$API_TOKEN   = if ($env:API_TOKEN)   { $env:API_TOKEN }   else { 'harness-test-token-dev-only' }
$IVORY_DIR   = 'C:\Ivory'
$SCRIBE_DIR  = 'C:\IvoryScribe'

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " IVORY FULL-STACK INSTALLER — Reception-PC" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Ivory app dir:      $IVORY_DIR"
Write-Host " Scribe daemon dir:  $SCRIBE_DIR"
Write-Host " Source host:        http://${SOURCE_HOST}:${SOURCE_PORT}"
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

function Step($n, $msg) { Write-Host "[$n] $msg" -ForegroundColor Yellow }

function Ensure-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found. Install App Installer from the Microsoft Store first."
    }
}

function Ensure-Docker {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $dockerVersion = (& docker --version 2>&1)
        if ($dockerVersion -match 'Docker version') {
            Write-Host "    Docker already installed: $dockerVersion"
            return
        }
    }
    Step "1a" "Installing Docker Desktop via winget (takes 5-10 minutes)..."
    winget install -e --id Docker.DockerDesktop --silent --accept-source-agreements --accept-package-agreements
    Write-Host "    Docker installed. A REBOOT may be required for WSL2 backend." -ForegroundColor Yellow
    Write-Host "    Starting Docker Desktop now..."
    $dd = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dd) {
        Start-Process $dd
        # Wait up to 5 min for the engine to come up
        $deadline = (Get-Date).AddMinutes(5)
        while ((Get-Date) -lt $deadline) {
            try {
                & docker info 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    Docker engine ready."
                    return
                }
            } catch { }
            Start-Sleep -Seconds 5
        }
        throw "Docker Desktop did not become ready within 5 minutes. Reboot and re-run this script."
    } else {
        throw "Docker Desktop installed but not found at $dd. Reboot and re-run this script."
    }
}

function Fetch-Ivory-Source {
    Step "2" "Fetching Ivory source from http://${SOURCE_HOST}:${SOURCE_PORT}/ivory.zip..."
    New-Item -ItemType Directory -Force -Path $IVORY_DIR | Out-Null
    $zipPath = "$env:TEMP\ivory.zip"
    try {
        Invoke-WebRequest -Uri "http://${SOURCE_HOST}:${SOURCE_PORT}/ivory.zip" -OutFile $zipPath -TimeoutSec 60
    } catch {
        throw "Failed to fetch from http://${SOURCE_HOST}:${SOURCE_PORT}/ivory.zip. Is serve-source.ps1 running on $SOURCE_HOST? Error: $_"
    }
    $extractDir = "$env:TEMP\ivory-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    # The zip contains the repo root; copy contents into $IVORY_DIR
    $rootInZip = Get-ChildItem $extractDir | Where-Object PSIsContainer | Select-Object -First 1
    if (-not $rootInZip) { throw "ivory.zip layout unexpected — no root folder inside." }
    Copy-Item "$($rootInZip.FullName)\*" $IVORY_DIR -Recurse -Force
    Remove-Item $extractDir -Recurse -Force
    Remove-Item $zipPath -Force
}

function Write-Production-Env {
    Step "3" "Writing $IVORY_DIR\.env.production..."
    $secretKey = -join ((1..96) | ForEach-Object { [char](Get-Random -Min 33 -Max 126) })
    $envContent = @"
# Ivory production env — written by install-reception.ps1
RAILS_ENV=production
SCRIBE_API_TOKEN=${API_TOKEN}
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=$(-join ((1..16) | ForEach-Object { [char](Get-Random -Min 97 -Max 122) }))
SECRET_KEY_BASE=${secretKey}
# Leave ANTHROPIC_API_KEY blank to use deterministic stubs in dev/learning phase.
# Set it later when you want real LLM summaries.
ANTHROPIC_API_KEY=
"@
    [System.IO.File]::WriteAllText("$IVORY_DIR\.env.production", $envContent, [System.Text.UTF8Encoding]::new($false))
}

function Bring-Up-Ivory {
    Step "4" "Bringing up Ivory docker compose stack (Postgres + Rails + Vite)..."
    Push-Location $IVORY_DIR
    try {
        & docker compose --env-file .env.production up -d --build
        if ($LASTEXITCODE -ne 0) { throw "docker compose up failed (exit $LASTEXITCODE)." }
    } finally {
        Pop-Location
    }
    Step "4a" "Waiting for Rails /up to return 200..."
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri 'http://localhost:3000/up' -TimeoutSec 5 -UseBasicParsing
            if ($r.StatusCode -eq 200) { Write-Host "    Rails ready."; return }
        } catch { }
        Start-Sleep -Seconds 3
    }
    throw "Rails did not become ready within 3 minutes. Inspect: cd $IVORY_DIR; docker compose logs web"
}

function Run-Migrations-And-Seed {
    Step "5" "Running database migrations + seed (idempotent)..."
    Push-Location $IVORY_DIR
    try {
        & docker compose exec -T web bundle exec rails db:prepare
        & docker compose exec -T web bundle exec rails db:seed
        # Seed the three recording devices if not already present
        $devSeed = @'
%w[Surgery\ 1 Surgery\ 2 Reception].each do |name|
  RecordingDevice.find_or_create_by!(name: name) { |d| d.location = name.parameterize(separator: "_"); d.enabled = true }
end
puts "RecordingDevices: " + RecordingDevice.order(:name).pluck(:name).inspect
'@
        & docker compose exec -T web bundle exec rails runner "$devSeed"
    } finally {
        Pop-Location
    }
}

function Set-PowerPlan {
    Step "6" "Configuring Windows power plan (never sleep, no USB suspend, no fast startup)..."
    powercfg /change standby-timeout-ac 0       2>&1 | Out-Null
    powercfg /change standby-timeout-dc 0       2>&1 | Out-Null
    powercfg /change hibernate-timeout-ac 0     2>&1 | Out-Null
    powercfg /change hibernate-timeout-dc 0     2>&1 | Out-Null
    powercfg /change monitor-timeout-ac 0       2>&1 | Out-Null
    powercfg /change disk-timeout-ac 0          2>&1 | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_USB USBSELECTIVESUSPEND 0 2>&1 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_USB USBSELECTIVESUSPEND 0 2>&1 | Out-Null
    powercfg /setactive SCHEME_CURRENT          2>&1 | Out-Null
    reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v HiberbootEnabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
}

function Install-Scribe-On-Reception {
    Step "7" "Installing scribe daemon on Reception PC (POSTs to localhost)..."
    $env:DEVICE      = 'Reception'
    $env:SOURCE_HOST = $SOURCE_HOST
    $env:SOURCE_PORT = $SOURCE_PORT
    $env:RECEPTION   = 'localhost'   # scribe on same PC as the app
    $env:API_TOKEN   = $API_TOKEN
    iex (Invoke-RestMethod "http://${SOURCE_HOST}:${SOURCE_PORT}/install-scribe.ps1")
}

function Ensure-Docker-Autostart {
    Step "8" "Ensuring Docker Desktop auto-starts on Windows boot..."
    $startup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $dd      = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if ((Test-Path $dd) -and (Test-Path $startup)) {
        $wshell = New-Object -ComObject WScript.Shell
        $lnk = $wshell.CreateShortcut("$startup\Docker Desktop.lnk")
        $lnk.TargetPath = $dd
        $lnk.Save()
        Write-Host "    Startup shortcut created at $startup\Docker Desktop.lnk"
    } else {
        Write-Host "    SKIP — Docker Desktop or Startup folder not found." -ForegroundColor Yellow
    }
}

function Self-Test-Full {
    Step "9" "Full self-test..."
    try {
        $up = Invoke-WebRequest -Uri 'http://localhost:3000/up' -TimeoutSec 5 -UseBasicParsing
        if ($up.StatusCode -eq 200) { Write-Host "    [/up]               PASS" -ForegroundColor Green }
    } catch { Write-Host "    [/up]               FAIL: $_" -ForegroundColor Red }

    try {
        $hb = Invoke-RestMethod -Method GET `
            -Uri 'http://localhost:3000/api/v1/scribe/heartbeat?device_name=Reception' `
            -Headers @{ 'X-Scribe-Token' = $API_TOKEN } `
            -TimeoutSec 5
        if ($hb.ok) { Write-Host "    [scribe heartbeat]  PASS — device id=$($hb.device_id)" -ForegroundColor Green }
    } catch { Write-Host "    [scribe heartbeat]  FAIL: $_" -ForegroundColor Red }

    try {
        $dash = Invoke-WebRequest -Uri 'http://localhost:3000/' -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-Host "    [dashboard]         PASS — http://localhost:3000/" -ForegroundColor Green
    } catch { Write-Host "    [dashboard]         FAIL: $_" -ForegroundColor Red }
}

# ── Run ───────────────────────────────────────────────────────────────────
Ensure-Winget
Step "1" "Ensuring Docker Desktop..."
Ensure-Docker
Fetch-Ivory-Source
Write-Production-Env
Bring-Up-Ivory
Run-Migrations-And-Seed
Set-PowerPlan
Install-Scribe-On-Reception
Ensure-Docker-Autostart
Self-Test-Full

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " IVORY INSTALLED ON Reception-PC" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host " Dashboard:           http://Reception-PC:3000/  (or http://localhost:3000/)"
Write-Host " Recording devices:   http://Reception-PC:3000/admin/recording-devices"
Write-Host " Scribe logs:         $SCRIBE_DIR\scribe.log"
Write-Host " Stack control:       cd $IVORY_DIR; docker compose ps"
Write-Host ""
Write-Host " NEXT STEPS:" -ForegroundColor Yellow
Write-Host "   1. On Surgery 1 PC (admin PowerShell):"
Write-Host "        `$env:DEVICE='Surgery 1'; iex (irm http://${SOURCE_HOST}:${SOURCE_PORT}/install-scribe.ps1)"
Write-Host "   2. On Surgery 2 PC (admin PowerShell):"
Write-Host "        `$env:DEVICE='Surgery 2'; iex (irm http://${SOURCE_HOST}:${SOURCE_PORT}/install-scribe.ps1)"
Write-Host "========================================================" -ForegroundColor Green
