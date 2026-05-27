# ============================================================================
# serve-source.ps1 — runs on Paul's laptop ONLY, during install
# ============================================================================
#
# Exposes the Ivory repo + scribe-daemon source over HTTP on the practice LAN
# so the Reception PC and Surgery PCs can fetch them via install-*.ps1.
#
# WHAT IT DOES:
#   1. Builds two zips in $env:TEMP:
#        ivory.zip          — the full repo (for install-reception.ps1)
#        scribe-daemon.zip  — just tools/scribe-daemon/* (for install-scribe.ps1)
#   2. Copies the install scripts into the same temp folder
#   3. Starts a Python HTTP server on port 8000 serving that folder
#
# RUN:
#   .\serve-source.ps1
#
# Then on each practice PC:
#   Reception:  iex (irm http://<your-laptop-hostname-or-ip>:8000/install-reception.ps1)
#   Surgery 1:  $env:DEVICE='Surgery 1'; iex (irm http://<your-laptop-hostname-or-ip>:8000/install-scribe.ps1)
#   Surgery 2:  $env:DEVICE='Surgery 2'; iex (irm http://<your-laptop-hostname-or-ip>:8000/install-scribe.ps1)
#
# Press Ctrl+C in this window when all PCs are done.
# ============================================================================

$ErrorActionPreference = 'Stop'

# Detect repo root (script is in <repo>/tools/install/)
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$repoRoot = $repoRoot.Path
$serveDir = Join-Path $env:TEMP 'ivory-install-serve'
if (Test-Path $serveDir) { Remove-Item $serveDir -Recurse -Force }
New-Item -ItemType Directory -Path $serveDir | Out-Null

Write-Host "Repo root:  $repoRoot"
Write-Host "Serve dir:  $serveDir"
Write-Host ""

# ── Build ivory.zip ───────────────────────────────────────────────────────
Write-Host "[1/4] Building ivory.zip..."
$ivoryZip = Join-Path $serveDir 'ivory.zip'
# Exclude .git, node_modules, tmp, log to keep it small
$tempStaging = Join-Path $env:TEMP 'ivory-staging'
if (Test-Path $tempStaging) { Remove-Item $tempStaging -Recurse -Force }
New-Item -ItemType Directory -Path $tempStaging | Out-Null
$repoName = Split-Path $repoRoot -Leaf
$dest = Join-Path $tempStaging $repoName
robocopy $repoRoot $dest /MIR /XD .git node_modules tmp log .vite-cache /XF *.log /NFL /NDL /NJH /NJS /NP /NC /NS | Out-Null
Compress-Archive -Path "$tempStaging\*" -DestinationPath $ivoryZip -Force
Remove-Item $tempStaging -Recurse -Force
$sz = (Get-Item $ivoryZip).Length / 1MB
Write-Host ("       Done ({0:N1} MB)" -f $sz)

# ── Build scribe-daemon.zip ───────────────────────────────────────────────
Write-Host "[2/4] Building scribe-daemon.zip..."
$scribeZip = Join-Path $serveDir 'scribe-daemon.zip'
Compress-Archive -Path "$repoRoot\tools\scribe-daemon\*" -DestinationPath $scribeZip -Force
$sz = (Get-Item $scribeZip).Length / 1KB
Write-Host ("       Done ({0:N0} KB)" -f $sz)

# ── Copy install scripts ──────────────────────────────────────────────────
Write-Host "[3/4] Copying install-*.ps1 to serve dir..."
Copy-Item "$PSScriptRoot\install-reception.ps1" $serveDir
Copy-Item "$PSScriptRoot\install-scribe.ps1"    $serveDir

# ── Print LAN URL ─────────────────────────────────────────────────────────
$hostname = (hostname)
$ipAddrs = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp,Manual -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^127\.|^169\.' } |
            Select-Object -ExpandProperty IPAddress)

Write-Host ""
Write-Host "[4/4] Starting HTTP server on port 8000..."
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " INSTALL SCRIPTS READY ON YOUR LAN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Hostname: $hostname"
foreach ($ip in $ipAddrs) {
    Write-Host " URL:      http://$($ip):8000/"
}
Write-Host ""
Write-Host " ON RECEPTION PC (admin PowerShell):" -ForegroundColor Yellow
foreach ($ip in $ipAddrs) {
    Write-Host "   `$env:SOURCE_HOST='$ip'; iex (irm http://$($ip):8000/install-reception.ps1)"
    break
}
Write-Host ""
Write-Host " ON SURGERY 1 PC (admin PowerShell, AFTER reception is up):" -ForegroundColor Yellow
foreach ($ip in $ipAddrs) {
    Write-Host "   `$env:SOURCE_HOST='$ip'; `$env:DEVICE='Surgery 1'; iex (irm http://$($ip):8000/install-scribe.ps1)"
    break
}
Write-Host ""
Write-Host " ON SURGERY 2 PC: same as Surgery 1 but `$env:DEVICE='Surgery 2'"
Write-Host ""
Write-Host " Press Ctrl+C in this window when all three PCs are done."
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Use Python's built-in HTTP server (every Windows install of Python has this)
Push-Location $serveDir
try {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        & python -m http.server 8000
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        & py -m http.server 8000
    } else {
        throw "Python not found. Install Python 3.x first: winget install Python.Python.3.12"
    }
} finally {
    Pop-Location
}
