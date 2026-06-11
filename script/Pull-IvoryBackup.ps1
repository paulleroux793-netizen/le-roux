# Pull-IvoryBackup.ps1  (canonical copy runs from C:\Users\paul-\IvoryOps\ on Paul's PC,
# invoked by the Windows Scheduled Task "IvoryOneDriveBackup" — daily 04:15 + catch-up)
#
# Offsite replication of the Ivory database backup: copy the newest AES-256-encrypted
# nightly dump from the rig into a OneDrive folder, which OneDrive then syncs offsite.
# POPIA-safe: the dumps are already encrypted and the decryption passphrase stays on
# the rig (/root/.ivory_backup_pass) — it is NEVER copied to OneDrive, so the blobs in
# the cloud are useless without it. Idempotent + self-pruning.
$ErrorActionPreference = 'Stop'

$OneDrive = if ($env:OneDrive) { $env:OneDrive } else { 'D:\Paul le Roux\OneDrive' }
$Dest     = Join-Path $OneDrive 'Ivory-Backups'
$KeepDays = 30
$LogFile  = Join-Path $Dest 'pull.log'

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
function Log($m) { "$([DateTime]::Now.ToString('s'))  $m" | Tee-Object -FilePath $LogFile -Append }

try {
  $newest = ssh -o BatchMode=yes -o ConnectTimeout=20 rig "ls -1t /opt/ivory/backups/ivory-*.sql.gz.enc 2>/dev/null | head -1" |
            Select-Object -First 1
  $newest = "$newest".Trim()
  if (-not $newest) { Log 'ERROR: no backup found on rig'; exit 1 }

  $name  = Split-Path $newest -Leaf
  $local = Join-Path $Dest $name

  if (Test-Path $local) {
    Log "SKIP: $name already replicated"
  } else {
    scp -o BatchMode=yes "rig:$newest" "$local"
    if (-not (Test-Path $local)) { Log "ERROR: scp failed for $name"; exit 1 }
    $size = (Get-Item $local).Length
    if ($size -lt 1024) { Log "ERROR: $name looks truncated ($size bytes)"; Remove-Item $local -Force; exit 1 }
    Log "OK: pulled $name ($size bytes)"
  }

  Get-ChildItem $Dest -Filter 'ivory-*.sql.gz.enc' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
    ForEach-Object { Remove-Item $_.FullName -Force; Log "pruned $($_.Name)" }

  $kept = (Get-ChildItem $Dest -Filter 'ivory-*.sql.gz.enc' | Measure-Object).Count
  Log "done; $kept backup(s) kept offsite in OneDrive"
} catch {
  Log "ERROR: $($_.Exception.Message)"
  exit 1
}
