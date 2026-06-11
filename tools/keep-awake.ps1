# Keep this PC ALWAYS AWAKE — run once on any practice machine that must stay on and reachable
# (the SIDEXIS server, Surgery 1, Surgery 2, reception). It only changes power/sleep settings;
# it does NOT touch any files or data.
#
# Run it: right-click this file -> "Run with PowerShell"
#   (or:  powershell -ExecutionPolicy Bypass -File .\keep-awake.ps1 )

Write-Host "=== Keeping this PC always awake ===" -ForegroundColor Cyan
$name = $env:COMPUTERNAME
Write-Host "PC: $name"

# Never sleep, never hibernate, never spin the disk down (on AC and battery).
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
powercfg /change disk-timeout-ac 0
powercfg /change disk-timeout-dc 0

# Disable hibernate entirely (needs admin; ignored if not elevated).
try { powercfg /hibernate off 2>$null } catch {}

# If it's a laptop: do NOTHING when the lid closes (stay running).
try {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
} catch {}

Write-Host ""
Write-Host "Done. '$name' will no longer sleep or hibernate." -ForegroundColor Green
Write-Host "(The monitor may still switch off to save the screen - that does NOT sleep the PC.)" -ForegroundColor Gray
Write-Host ""
Read-Host "Press Enter to close"
