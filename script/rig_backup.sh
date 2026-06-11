#!/usr/bin/env bash
# Nightly encrypted backup of the Ivory Postgres database.
#
# The DB lives in the Docker `pgdata` volume on the rig. This dumps it, gzips,
# and encrypts with AES-256 (passphrase in /root/.ivory_backup_pass, root-only)
# so the backup file is safe at rest (POPIA). Keeps the last 14 days.
#
# HARDENED 2026-06-07 after the backup saturated the rig for ~2.5h (web + the live
# WhatsApp bridge were unreachable). Root cause: an un-throttled `gzip -9` in the
# pipe at nice 0. Fixes here: (1) THROTTLE the host-side pipe with `ionice -c3`
# (idle IO) + `nice -n 19` (lowest CPU) so it can never starve the containers;
# (2) gzip -6 instead of -9 (far less CPU, marginally larger file); (3) a hard
# `timeout` on the dump so a stall can't hang the box forever; (4) an flock so a
# slow/hung run can't pile up on the next; (5) duration logging + a SLOW warning.
#
# Restore (gunzip reads any gzip level):
#   openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/.ivory_backup_pass \
#     -in ivory-YYYYMMDD-HHMM.sql.gz.enc | gunzip | \
#     docker compose -f docker-compose.rig.yml exec -T db psql -U postgres dr_leroux_receptionist_development
#
# Cron: runs nightly at 03:00 (deep off-peak, clear of the 00:00 dpkg timer).
# Run manually any time: bash /opt/ivory/le-roux-repo/script/rig_backup.sh
set -euo pipefail
REPO=/opt/ivory/le-roux-repo
DEST=/opt/ivory/backups
PASS=/root/.ivory_backup_pass
KEEP_DAYS=14
DUMP_TIMEOUT=1800        # 30-min hard cap on the dump — a stall fails loudly instead of hanging the rig
SLOW_WARN_SECS=900       # log a ⚠️ if a backup takes longer than 15 min
LOCK=/var/lock/ivory-backup.lock
DC="docker compose -f $REPO/docker-compose.rig.yml"
THROTTLE="ionice -c3 nice -n 19"   # idle IO class + lowest CPU priority

# Optional ops config (not in cron's minimal env). Put BACKUP_HEARTBEAT_URL=... here
# (e.g. a healthchecks.io ping URL) to get a dead-man's-switch alert if a backup ever
# stops running. No file / no var = no-op.
[ -f /root/.ivory_backup_env ] && . /root/.ivory_backup_env || true

# Single-run lock: if the previous backup is still going (or hung), SKIP this run
# rather than stack a second heavy job on top of it.
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "$(date -Is) backup SKIPPED: previous run still holding $LOCK" | tee -a "$DEST/backup.log"
  exit 0
fi

mkdir -p "$DEST"; chmod 700 "$DEST"
stamp=$(date +%Y%m%d-%H%M)
out="$DEST/ivory-${stamp}.sql.gz.enc"
start=$(date +%s)

# The CPU hogs (gzip, openssl) run on the HOST in this pipe, so the host-side
# throttle bites where it matters. timeout guards the dump itself.
$THROTTLE bash -c "
  set -o pipefail
  timeout $DUMP_TIMEOUT $DC exec -T db pg_dump -U postgres dr_leroux_receptionist_development \
    | gzip -6 \
    | openssl enc -aes-256-cbc -pbkdf2 -salt -pass 'file:$PASS' \
    > '$out'
"
chmod 600 "$out"

# Rotation: delete encrypted dumps older than KEEP_DAYS.
find "$DEST" -name 'ivory-*.sql.gz.enc' -mtime +"$KEEP_DAYS" -delete

bytes=$(stat -c%s "$out" 2>/dev/null || echo 0)
dur=$(( $(date +%s) - start ))
msg="$(date -Is) backup OK: $out (${bytes} bytes; ${dur}s); $(ls -1 "$DEST"/ivory-*.sql.gz.enc | wc -l) kept"
if [ "$dur" -gt "$SLOW_WARN_SECS" ]; then
  msg="$msg  ⚠️ SLOW(>$((SLOW_WARN_SECS/60))m) — investigate (backup should not saturate the rig)"
fi
echo "$msg" | tee -a "$DEST/backup.log"

# Freshness marker the app container CAN read. NB: tmp/ is a named volume inside the container
# (NOT the host repo tmp), so we use ops/ which IS part of the `.:/rails` bind mount. /health
# surfaces backup_age_hours from this so a stale/absent backup pages an external monitor.
MARKER="/opt/ivory/le-roux-repo/ops/last_backup.json"
mkdir -p "$(dirname "$MARKER")"
printf '{"at":"%s","bytes":%s,"file":"%s","duration_s":%s}\n' \
  "$(date -Is)" "$bytes" "$(basename "$out")" "$dur" > "$MARKER" 2>/dev/null || true

# Dead-man's-switch: ping the heartbeat only on a SUCCESSFUL run (set -e aborts before
# here on failure, so a missed ping = a failed/absent backup = an alert from the monitor).
if [ -n "${BACKUP_HEARTBEAT_URL:-}" ]; then
  curl -fsS -m 10 "$BACKUP_HEARTBEAT_URL" >/dev/null 2>&1 || true
fi
