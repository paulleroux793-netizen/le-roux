# Ivory — Disaster-Recovery Runbook

How to bring the AI receptionist back up if the rig fails or is stolen. Plain steps,
written so reception can follow them with one phone call to Paul.

**THE ONE RULE — never run two copies at once.** Cloudflare sends WhatsApp to whichever
machine is running the tunnel. If the rig AND a failover PC both run it, you get split-brain
(double bookings, two diverging databases). Failover = rig OFF (or already dead), failover ON.
When the rig is fixed, do the reverse cleanly.

---

## Where things live

| Thing | Location |
|---|---|
| Live system | The rig (`chalita-5090`, Ubuntu) at `100.73.38.21:3000` |
| Public WhatsApp address | `wa.chalitaleroux.co.za` (Cloudflare named tunnel `ivory-intake`) — never changes |
| Encrypted DB backups | Rig `/opt/ivory/backups/` **and** OneDrive `IvoryBackups/db/` (hourly) |
| Recovery bundle (the keys) | OneDrive `IvoryBackups/recovery/ivory-recovery-bundle.tar.gz.enc` |
| App code | OneDrive `…/le-roux-repo/` (syncs to Paul's PC + laptop) |
| **Bundle passphrase** | Paul's password manager (NOT on any machine, NOT in OneDrive) |
| **Recovery bundle decryption** | unlocks `.env.rig` (PHI keys), the DB-dump passphrase, the tunnel creds |

You need TWO secrets to recover, both kept off the machines: the **bundle passphrase**
(decrypts the recovery bundle) — everything else is inside that bundle.

---

## Scenario A — rig is down, hardware is fine (power, crash, reboot loop)

Fastest fix is usually to just restart the rig. If it won't come back:

1. **Fail over to the reception PC** (it has Docker + the OneDrive folder).
2. Open PowerShell in `…/le-roux-repo/ops/` and run:
   ```powershell
   .\ivory-failover.ps1
   ```
3. It will: pull the newest DB backup from OneDrive → ask for the **bundle passphrase** →
   decrypt the keys → restore the database into local Docker → start Ivory → start the
   tunnel so `wa.chalitaleroux.co.za` now points here.
4. Send a test WhatsApp to the practice number — confirm it replies and a booking lands.
5. **Tell Paul the rig is down and reception is now live.** Worst-case data loss = bookings
   since the last hourly backup (≤ 1 hour).

**When the rig is fixed:** stop Ivory + the tunnel on the reception PC FIRST
(`docker compose down`, stop cloudflared), restore the latest backup onto the rig, then
bring the rig back up. Never both at once.

---

## Scenario B — rig stolen / dead / building cleared out

Run from Paul's **laptop** (anywhere with internet):

1. Make sure OneDrive has synced (you need `IvoryBackups/db/` + `IvoryBackups/recovery/`).
2. In `…/le-roux-repo/ops/` run `.\ivory-failover.ps1` — same flow as Scenario A.
3. Because the **Cloudflare tunnel is a named tunnel**, starting it on the laptop with the
   recovered creds makes `wa.chalitaleroux.co.za` point at the laptop automatically —
   **no Twilio change needed.** WhatsApp keeps working on the same number.
4. Tell Paul. Order a new rig; when it arrives, restore onto it and cut back over.

If OneDrive itself is unreachable, the system can't be recovered from nothing — which is why
the bundle passphrase must be in your password manager and OneDrive version history is on.

---

## What makes this work (do NOT let these lapse)

- **Hourly off-box backups** — `rig_offsite_sync.sh`, pushed to OneDrive after each hourly dump.
- **Recovery bundle** — `rig_recovery_bundle.sh`, refreshed weekly; re-run it after any key/tunnel change.
- **Bundle passphrase in your password manager** — the single secret that must survive the theft.
- **Reception PC kept ready** — Docker Desktop installed, the OneDrive `le-roux-repo` folder synced.
- **A real drill** — once a quarter, actually run `ivory-failover.ps1` on the reception PC and
  send a test WhatsApp. A DR plan you've never run is a guess, not a plan.
