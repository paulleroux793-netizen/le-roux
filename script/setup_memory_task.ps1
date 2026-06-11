# Registers the daily memory-consolidation scheduled task on this PC (where the
# Claude Code transcripts live). Runs once a day; catches up if the PC was off.
# Run once in PowerShell:  powershell -ExecutionPolicy Bypass -File le-roux-repo\script\setup_memory_task.ps1

$ErrorActionPreference = "Stop"
$TaskName = "IvoryMemoryConsolidation"
$Script   = Join-Path $PSScriptRoot "consolidate_memory.py"
$Python   = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $Python) { $Python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $Python) { throw "Python not found on PATH." }

$Action  = New-ScheduledTaskAction -Execute $Python -Argument "`"$Script`""
# Daily at 23:10 local; StartWhenAvailable runs it ASAP if the PC was off at 23:10.
$Trigger = New-ScheduledTaskTrigger -Daily -At 11:10PM
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
    -Settings $Settings -Description "Daily: extract durable knowledge from Claude Code transcripts into le-roux-repo/system/memory/" -Force | Out-Null

Write-Output "Registered scheduled task '$TaskName' (daily 23:10, catch-up enabled)."
Write-Output "Run now to test:  Start-ScheduledTask -TaskName $TaskName"
