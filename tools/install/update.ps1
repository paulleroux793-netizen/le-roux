# ============================================================================
# update.ps1 — pull latest Ivory source from Paul's laptop and restart
# ============================================================================
#
# Runs on Reception-PC. Re-fetches the Ivory source from the laptop running
# serve-source.ps1, copies it into $IVORY_DIR, and restarts the Rails stack.
#
# RUN (on Reception-PC, admin PowerShell):
#   $env:SOURCE_HOST='<your-laptop-ip-or-hostname>'; iex (irm http://<host>:8000/update.ps1)
#
# OR locally if this script is already on the PC:
#   .\update.ps1
#
# ============================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$SOURCE_HOST = if ($env:SOURCE_HOST) { $env:SOURCE_HOST } else { 'PAUL-LAPTOP' }
$SOURCE_PORT = if ($env:SOURCE_PORT) { $env:SOURCE_PORT } else { '8000' }
$IVORY_DIR   = 'C:\Ivory'

Write-Host "Updating Ivory from http://${SOURCE_HOST}:${SOURCE_PORT}..." -ForegroundColor Cyan

if (-not (Test-Path $IVORY_DIR)) {
    throw "$IVORY_DIR not found. Run install-reception.ps1 first."
}

# Preserve .env.production + stack data — never overwrite those
$envProdPath  = Join-Path $IVORY_DIR '.env.production'
$preserveDir  = Join-Path $env:TEMP "ivory-preserve-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $preserveDir | Out-Null
if (Test-Path $envProdPath) { Copy-Item $envProdPath "$preserveDir\.env.production" -Force }

# Download fresh zip
$zip = Join-Path $env:TEMP 'ivory-update.zip'
Invoke-WebRequest -Uri "http://${SOURCE_HOST}:${SOURCE_PORT}/ivory.zip" -OutFile $zip -TimeoutSec 60

# Extract to a staging folder, then sync into IVORY_DIR (preserving Docker volumes)
$extractDir = Join-Path $env:TEMP 'ivory-update-extract'
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $extractDir -Force
$rootInZip = Get-ChildItem $extractDir | Where-Object PSIsContainer | Select-Object -First 1
if (-not $rootInZip) { throw "ivory.zip layout unexpected" }

# Use robocopy: mirror source files, but EXCLUDE the .env.production + tmp/postgres-data
robocopy $rootInZip.FullName $IVORY_DIR /E /XF .env.production /XD tmp postgres-data /NFL /NDL /NJH /NJS | Out-Null

# Restore preserved files
if (Test-Path "$preserveDir\.env.production") {
    Copy-Item "$preserveDir\.env.production" $envProdPath -Force
}
Remove-Item $preserveDir -Recurse -Force
Remove-Item $extractDir  -Recurse -Force
Remove-Item $zip -Force

# Rebuild + restart
Write-Host "Rebuilding Rails image..." -ForegroundColor Yellow
Push-Location $IVORY_DIR
try {
    & docker compose --env-file .env.production build web
    if ($LASTEXITCODE -ne 0) { throw "docker compose build failed" }

    Write-Host "Restarting stack..." -ForegroundColor Yellow
    & docker compose --env-file .env.production up -d

    Write-Host "Running migrations..." -ForegroundColor Yellow
    & docker compose exec -T web bundle exec rails db:migrate

    Write-Host "Waiting for Rails /up..." -ForegroundColor Yellow
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri 'http://localhost:3000/up' -TimeoutSec 5 -UseBasicParsing
            if ($r.StatusCode -eq 200) {
                Write-Host "UPDATE COMPLETE — Rails ready at http://localhost:3000/" -ForegroundColor Green
                exit 0
            }
        } catch { }
        Start-Sleep -Seconds 3
    }
    throw "Rails did not return /up=200 within 2 minutes. Inspect: docker compose logs web"
} finally {
    Pop-Location
}
