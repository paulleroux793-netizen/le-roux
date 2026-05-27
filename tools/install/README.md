# Ivory install runbook

One PowerShell command per PC. After it finishes, the system runs forever — never touched again.

## Pre-flight (do once)

1. **Plug a Samson UB1 USB boundary mic** into each PC's USB port:
   - Surgery 1 PC
   - Surgery 2 PC
   - Reception-PC

2. **Confirm all three PCs are on the same LAN** (Wi-Fi or Ethernet — doesn't matter; same router).

3. **Confirm Reception-PC's Windows computer name is `Reception-PC`** (`hostname` in PowerShell should print exactly that). If different, edit the `$RECEPTION` default in `install-scribe.ps1` line 36 before running.

## Step 0 — on the dev laptop (one-time per install session)

```powershell
cd "D:\Paul le Roux\OneDrive\Documents\Claude\Projects\DR CHALITA AI RECEPTIONIST\le-roux-repo\tools\install"
.\serve-source.ps1
```

The script:
- Bundles the repo into `ivory.zip` and the scribe daemon into `scribe-daemon.zip`
- Starts a Python HTTP server on port 8000 serving the install scripts + zips
- Prints the **exact three commands to paste** on each PC (with the laptop's LAN IP filled in)

Leave the window open. Press **Ctrl+C** when all three PCs are installed.

## Step 1 — on Reception-PC (admin PowerShell)

Paste the command serve-source.ps1 printed for Reception. Looks like:

```powershell
$env:SOURCE_HOST='<laptop-ip>'; iex (irm http://<laptop-ip>:8000/install-reception.ps1)
```

What this does (in order, ~10-15 minutes):
- Installs Docker Desktop via winget (if missing) — may require a reboot
- Pulls the Ivory source
- Builds the Docker image
- Brings up Postgres + Rails + Vite as a docker compose stack with auto-start
- Runs migrations + seeds
- Creates RecordingDevices named `Surgery 1`, `Surgery 2`, `Reception`
- Locks Windows power plan (never sleep, no USB suspend, no fast startup)
- Installs the scribe daemon for Reception's own mic (POSTs to localhost)
- Adds Docker Desktop to Startup so it auto-launches on boot
- Self-tests: `/up`, scribe heartbeat, dashboard

When it prints `IVORY INSTALLED ON Reception-PC`, the dashboard is live at:
- **http://Reception-PC:3000/** (from any PC on the LAN)
- or **http://localhost:3000/** (from Reception-PC itself)

## Step 2 — on Surgery 1 PC (admin PowerShell)

```powershell
$env:SOURCE_HOST='<laptop-ip>'; $env:DEVICE='Surgery 1'; iex (irm http://<laptop-ip>:8000/install-scribe.ps1)
```

Takes ~5 minutes. Installs Python 3.12, nssm, the scribe daemon, registers the Windows service.

## Step 3 — on Surgery 2 PC (admin PowerShell)

```powershell
$env:SOURCE_HOST='<laptop-ip>'; $env:DEVICE='Surgery 2'; iex (irm http://<laptop-ip>:8000/install-scribe.ps1)
```

## Done

Open the dashboard from your laptop (or any PC on the LAN):
**http://Reception-PC:3000/**

Visit `/admin/recording-devices` to confirm all three devices have a recent `last_seen_at`.

## When Claude makes code changes — updating Reception-PC

On the dev laptop, run `serve-source.ps1` again (to rebuild the zip). Then on Reception-PC:

```powershell
$env:SOURCE_HOST='<laptop-ip>'; iex (irm http://<laptop-ip>:8000/update.ps1)
```

This pulls the latest source, rebuilds the image, restarts the stack, and runs new migrations. Surgery PCs don't need updating — the daemon code rarely changes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `winget not found` | Install App Installer from the Microsoft Store first |
| `Docker not ready` after install | Reboot the PC and re-run `install-reception.ps1` (idempotent) |
| Scribe service starts but no transcripts arriving | Check `C:\IvoryScribe\scribe.log`. Verify mic is plugged in and selected as the default Windows input |
| `401 Unauthorized` from Ivory | `SCRIBE_API_TOKEN` mismatch. The default token is `harness-test-token-dev-only`. For production set `$env:API_TOKEN` to a strong value BEFORE running both install scripts |
| Dashboard shows no recent activity | Check `RecordingDevice.last_seen_at`. If stale, the surgery PC isn't reaching Reception-PC over the LAN. Test: `Test-NetConnection Reception-PC -Port 3000` from the surgery PC |

## Uninstall

```powershell
# On surgery / reception PCs
nssm stop IvoryScribe
nssm remove IvoryScribe confirm
Remove-Item C:\IvoryScribe -Recurse -Force

# On Reception-PC additionally
cd C:\Ivory
docker compose down -v   # WARNING — destroys the database
Remove-Item C:\Ivory -Recurse -Force
```
