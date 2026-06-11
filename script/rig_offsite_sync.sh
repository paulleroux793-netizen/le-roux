#!/usr/bin/env bash
# Off-box sync of the encrypted Ivory backups to OneDrive.
#
# THE theft-survival step. Without this the encrypted dumps live ONLY on the rig.
# Called at the end of rig_backup.sh; safe to run standalone. NO-OPS until the OneDrive
# remote is configured (post one-time OAuth).
#
# WHY NOT `rclone copy`: rclone's UPLOAD is broken on this OneDrive (a personal drive on a
# custom domain, info@drchalitaleroux.co.za) — it streams the bytes but the commit fails
# "unauthenticated", leaving 0-byte files. rclone's READ/LIST/DELETE + token refresh all work.
# So we use rclone ONLY for token management + listing, and upload via the Microsoft Graph
# simple-PUT endpoint (proven: HTTP 201, correct size; supports up to 250 MB, dumps are ~9 MB).
set -euo pipefail
DEST=/opt/ivory/backups
LOG=$DEST/offsite.log
RC=/usr/bin/rclone
REMOTE=${IVORY_RCLONE_REMOTE:-onedrive}
RDIR=${IVORY_RCLONE_PATH:-IvoryBackups}
KEEP_REMOTE_DAYS=${IVORY_RCLONE_KEEP_DAYS:-30}
CONF=/root/.config/rclone/rclone.conf
ts() { date -Is; }

if ! $RC listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
  echo "$(ts) offsite SKIPPED: rclone remote '${REMOTE}:' not configured yet — run the one-time OneDrive auth" | tee -a "$LOG"
  exit 0
fi

# Fresh access token (rclone refreshes it on any operation).
$RC about "${REMOTE}:" >/dev/null 2>&1 || true
ACCESS=$(grep -oP "\"access_token\":\"\K[^\"]+" "$CONF" | head -1)
[ -n "$ACCESS" ] || { echo "$(ts) offsite FAIL: no access token in $CONF" | tee -a "$LOG"; exit 1; }

graph_put() {  # $1 = local file, $2 = path under the drive root
  curl -s -m 300 -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer $ACCESS" -H "Content-Type: application/octet-stream" \
    --data-binary @"$1" "https://graph.microsoft.com/v1.0/me/drive/root:/$2:/content"
}

# Remote inventory (name->size) so we skip complete uploads and re-do any 0-byte/partial ones.
remote_list=$($RC lsl "${REMOTE}:${RDIR}/db" 2>/dev/null || true)
rsize() { echo "$remote_list" | awk -v n="$1" '$NF==n {print $1; exit}'; }

up=0; skip=0; fail=0
for f in "$DEST"/ivory-*.sql.gz.enc; do
  [ -e "$f" ] || continue
  nm=$(basename "$f"); lsz=$(stat -c%s "$f")
  if [ "$(rsize "$nm")" = "$lsz" ]; then skip=$((skip+1)); continue; fi
  code=$(graph_put "$f" "${RDIR}/db/$nm")
  if [ "$code" = "200" ] || [ "$code" = "201" ]; then up=$((up+1)); else fail=$((fail+1)); echo "$(ts) offsite: PUT $nm -> HTTP $code" >> "$LOG"; fi
done

# Off-box retention: prune cloud dumps older than KEEP_REMOTE_DAYS (rclone delete works fine).
$RC delete "${REMOTE}:${RDIR}/db" --include 'ivory-*.sql.gz.enc' --min-age "${KEEP_REMOTE_DAYS}d" 2>>"$LOG" || true

n=$($RC lsf "${REMOTE}:${RDIR}/db" --include 'ivory-*.sql.gz.enc' 2>/dev/null | wc -l)
echo "$(ts) offsite OK: uploaded=$up skipped=$skip failed=$fail; ${n} dumps off-box" | tee -a "$LOG"
[ "$fail" -eq 0 ]
