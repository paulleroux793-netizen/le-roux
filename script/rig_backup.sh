#!/usr/bin/env bash
# Nightly encrypted backup of the Ivory Postgres database.
#
# The DB lives in the Docker `pgdata` volume on the rig. This dumps it, gzips,
# and encrypts with AES-256 (passphrase in /root/.ivory_backup_pass, root-only)
# so the backup file is safe at rest (POPIA). Keeps the last 14 days.
#
# Restore:
#   openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/.ivory_backup_pass \
#     -in ivory-YYYYMMDD-HHMM.sql.gz.enc | gunzip | \
#     docker compose -f docker-compose.rig.yml exec -T db psql -U postgres dr_leroux_receptionist_development
#
# Installed in cron (see crontab) to run nightly. Run manually any time:
#   bash /opt/ivory/le-roux-repo/script/rig_backup.sh
set -euo pipefail
REPO=/opt/ivory/le-roux-repo
DEST=/opt/ivory/backups
PASS=/root/.ivory_backup_pass
KEEP_DAYS=14
DC="docker compose -f $REPO/docker-compose.rig.yml"

mkdir -p "$DEST"; chmod 700 "$DEST"
stamp=$(date +%Y%m%d-%H%M)
out="$DEST/ivory-${stamp}.sql.gz.enc"

$DC exec -T db pg_dump -U postgres dr_leroux_receptionist_development \
  | gzip -9 \
  | openssl enc -aes-256-cbc -pbkdf2 -salt -pass "file:$PASS" \
  > "$out"
chmod 600 "$out"

# Rotation: delete encrypted dumps older than KEEP_DAYS.
find "$DEST" -name 'ivory-*.sql.gz.enc' -mtime +"$KEEP_DAYS" -delete

bytes=$(stat -c%s "$out" 2>/dev/null || echo 0)
echo "$(date -Is) backup OK: $out (${bytes} bytes); $(ls -1 "$DEST"/ivory-*.sql.gz.enc | wc -l) kept" \
  | tee -a "$DEST/backup.log"
