<#
  ivory-failover.ps1 — bring Ivory up on the reception PC or laptop when the rig is down.

  Pulls the newest encrypted DB backup + the recovery bundle from OneDrive, decrypts them
  (you supply the bundle passphrase from your password manager), restores the database into
  local Docker, starts Ivory, and optionally starts the Cloudflare tunnel so the public
  WhatsApp address (wa.chalitaleroux.co.za) points at THIS machine.

  THE ONE RULE: never run this while the rig is also live. Rig OFF, failover ON.

  PREREQUISITES on this PC (do these BEFORE you ever need it — see DR-RUNBOOK.md):
    - Docker Desktop installed and running
    - The OneDrive folder `…/le-roux-repo/` synced (this script lives in its ops/ folder)
    - OneDrive `IvoryBackups/db/` and `IvoryBackups/recovery/` synced locally
    - Git for Windows installed (provides openssl + gzip)  — or Docker is used as a fallback

  ⚠️ NOT YET CERTIFIED — run this once as a SUPERVISED DRILL on the reception PC and fix any
     path/tool gaps before relying on it in a real outage.

  Usage:   .\ivory-failover.ps1            # full failover
           .\ivory-failover.ps1 -NoTunnel  # restore + run locally, do NOT take over the public URL (safe drill)
#>
[CmdletBinding()]
param(
  [string]$BackupsRoot = (Join-Path $env:OneDrive 'IvoryBackups'),
  [switch]$NoTunnel
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent          # …/le-roux-repo
$compose = Join-Path $repo 'docker-compose.rig.yml'
$work = Join-Path $env:TEMP 'ivory-failover'
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Die($m)  { Write-Host "FAIL: $m" -ForegroundColor Red; exit 1 }

# --- locate openssl + gzip (Git for Windows ships both) ---
$openssl = (Get-Command openssl -ErrorAction SilentlyContinue)?.Source `
  ?? @("$env:ProgramFiles\Git\usr\bin\openssl.exe","$env:ProgramFiles\Git\mingw64\bin\openssl.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$gzip = (Get-Command gzip -ErrorAction SilentlyContinue)?.Source `
  ?? @("$env:ProgramFiles\Git\usr\bin\gzip.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $openssl) { Die "openssl not found — install Git for Windows (provides openssl + gzip)." }
if (-not $gzip)    { Die "gzip not found — install Git for Windows." }

Step "Preflight"
try { docker info *> $null } catch { Die "Docker Desktop is not running — start it and retry." }
if (-not (Test-Path $compose)) { Die "compose file not found at $compose (is the le-roux-repo OneDrive folder synced?)" }
$dbDir  = Join-Path $BackupsRoot 'db'
$recDir = Join-Path $BackupsRoot 'recovery'
if (-not (Test-Path $dbDir))  { Die "no $dbDir — has OneDrive synced the backups?" }
$dump   = Get-ChildItem $dbDir  -Filter 'ivory-*.sql.gz.enc' | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$bundle = Get-ChildItem $recDir -Filter 'ivory-recovery-bundle.tar.gz.enc' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dump)   { Die "no DB backups found in $dbDir" }
if (-not $bundle) { Die "no recovery bundle in $recDir — run rig_recovery_bundle.sh on the rig first" }
Write-Host ("Newest DB backup : {0} ({1:yyyy-MM-dd HH:mm})" -f $dump.Name,  $dump.LastWriteTime)
Write-Host ("Recovery bundle  : {0} ({1:yyyy-MM-dd HH:mm})" -f $bundle.Name, $bundle.LastWriteTime)

Step "Decrypt the recovery bundle (keys)"
$bundlePass = Read-Host "Enter the RECOVERY BUNDLE passphrase (from your password manager)" -AsSecureString
$bp = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($bundlePass))
$passFile = Join-Path $work 'bundle.pass'; Set-Content -NoNewline -Path $passFile -Value $bp -Encoding ascii
$tarPath = Join-Path $work 'bundle.tar.gz'
& $openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$passFile" -in $bundle.FullName -out $tarPath
if ($LASTEXITCODE -ne 0) { Remove-Item $passFile -Force; Die "bundle decryption failed — wrong passphrase?" }
$keyDir = Join-Path $work 'keys'; New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
& tar -xzf $tarPath -C $keyDir
Copy-Item (Join-Path $keyDir '.env.rig') (Join-Path $repo '.env.rig') -Force
$dumpPass = Join-Path $keyDir 'ivory_backup_pass'      # decrypts the DB dump
Write-Host "Keys recovered (.env.rig, dump passphrase, cloudflared creds)." -ForegroundColor Green

Step "Start the database container"
Push-Location $repo
docker compose -f $compose up -d db
Start-Sleep -Seconds 8
$createdb = 'CREATE DATABASE dr_leroux_receptionist_development;'
docker compose -f $compose exec -T db psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='dr_leroux_receptionist_development'" `
  | Select-String -Quiet '1' | ForEach-Object { if (-not $_) { docker compose -f $compose exec -T db psql -U postgres -c $createdb } }

Step "Restore the newest backup into the database"
# decrypt -> gunzip -> psql, all streamed (no plaintext PHI hits disk)
$decPass = Join-Path $work 'dump.pass'; Copy-Item $dumpPass $decPass -Force
& $openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$decPass" -in $dump.FullName `
  | & $gzip -d `
  | docker compose -f $compose exec -T db psql -U postgres dr_leroux_receptionist_development
Write-Host "Database restored from $($dump.Name)." -ForegroundColor Green

Step "Start Ivory (web)"
docker compose -f $compose up -d web
Start-Sleep -Seconds 10
try { $code = (Invoke-WebRequest http://localhost:3000/up -UseBasicParsing -TimeoutSec 30).StatusCode } catch { $code = 0 }
Write-Host "Local Ivory /up = $code  (expect 200)"

if (-not $NoTunnel) {
  Step "Take over the public WhatsApp address (Cloudflare tunnel)"
  Write-Host "⚠️  Confirm the RIG IS OFF before doing this (no split-brain)." -ForegroundColor Yellow
  $go = Read-Host "Type YES to start the tunnel on this machine"
  if ($go -eq 'YES') {
    $cf = Join-Path $keyDir 'cloudflared'
    docker run -d --name ivory-tunnel --restart unless-stopped --network host `
      -v "${cf}:/etc/cloudflared:ro" cloudflare/cloudflared:latest `
      --no-autoupdate --config /etc/cloudflared/config.yml tunnel run
    Write-Host "Tunnel started — wa.chalitaleroux.co.za now points here. Send a test WhatsApp to confirm." -ForegroundColor Green
  } else { Write-Host "Skipped tunnel. Ivory is running locally only (http://localhost:3000)." }
}

# cleanup transient secrets
Remove-Item $passFile,$decPass -Force -ErrorAction SilentlyContinue
Pop-Location
Step "Done"
Write-Host "Ivory is up on this machine. See DR-RUNBOOK.md for cutting BACK to the rig (rig ON, this OFF)." -ForegroundColor Green
