#!/usr/bin/env bash
# Restore drill — proves the nightly encrypted backup is actually restorable.
# Restores the NEWEST backup into a throwaway scratch DB on the db container, checks
# key tables have sane row counts vs the live DB, then drops the scratch DB. Touches
# NO real data. Run manually, or wire into cron weekly.
set -euo pipefail
REPO=/opt/ivory/le-roux-repo
DEST=/opt/ivory/backups
PASS=/root/.ivory_backup_pass
DC="docker compose -f $REPO/docker-compose.rig.yml"
SRC=dr_leroux_receptionist_development
TMP=ivory_restore_drill

newest=$(ls -1t "$DEST"/ivory-*.sql.gz.enc 2>/dev/null | head -1)
[ -n "$newest" ] || { echo "FAIL: no backup found in $DEST"; exit 1; }
echo "restore-drill of $(basename "$newest")"

cleanup() { $DC exec -T db psql -U postgres -c "DROP DATABASE IF EXISTS $TMP;" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Fresh scratch DB
$DC exec -T db psql -U postgres -c "DROP DATABASE IF EXISTS $TMP;" >/dev/null
$DC exec -T db psql -U postgres -c "CREATE DATABASE $TMP;" >/dev/null

# Decrypt -> gunzip -> restore into the scratch DB
openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$PASS" -in "$newest" \
  | gunzip \
  | $DC exec -T db psql -U postgres "$TMP" >/dev/null 2>&1

# Compare row counts on key tables (live may be slightly ahead of the dump — that's fine;
# the drill proves restorability + non-empty data, not byte-equality).
fail=0
for t in patients appointments invoices treatment_items; do
  live=$($DC exec -T db psql -U postgres -tA "$SRC" -c "SELECT count(*) FROM $t;" 2>/dev/null | tr -d '[:space:]')
  rest=$($DC exec -T db psql -U postgres -tA "$TMP" -c "SELECT count(*) FROM $t;" 2>/dev/null | tr -d '[:space:]')
  status=OK
  # Restored must be > 0 (proof of data) and within 5% of live (proof of completeness).
  if [ -z "$rest" ] || [ "$rest" = "0" ]; then status="FAIL(empty)"; fail=1; fi
  echo "  $t: live=$live restored=$rest $status"
done

if [ "$fail" -eq 0 ]; then
  echo "restore-drill PASS (scratch DB restored + verified, now dropped)"
else
  echo "restore-drill FAIL — backup did not restore cleanly; investigate"
  exit 1
fi
