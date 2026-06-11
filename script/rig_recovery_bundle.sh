#!/usr/bin/env bash
# Recovery bundle — the SECRETS needed to rebuild Ivory from scratch on another
# machine (reception PC / laptop) after the rig is lost or stolen. Without these,
# the off-box DB dumps are useless (can't decrypt the dump, can't read the encrypted
# PHI, can't take over the public hostname):
#   - .env.rig             AR_ENCRYPTION_* (PHI-at-rest keys), SECRET_KEY, Twilio, Anthropic
#   - ivory_backup_pass    the AES passphrase that decrypts every ivory-*.sql.gz.enc dump
#   - cloudflared/         the named-tunnel creds (take over wa/intake.chalitaleroux.co.za)
#
# The bundle is itself AES-256 encrypted with a SEPARATE passphrase in
# /root/.ivory_recovery_pass. That passphrase is the ONE secret that must live OFF all
# three machines — store it in your password manager (Bitdefender/1Password). OneDrive
# holding the bundle is then safe: an attacker needs the bundle passphrase too.
#
# Re-run whenever a key or the tunnel cred changes (rare). Wired weekly in cron.
set -euo pipefail
REPO=/opt/ivory/le-roux-repo
OUT=/opt/ivory/backups
PASS=/root/.ivory_recovery_pass
REMOTE=${IVORY_RCLONE_REMOTE:-onedrive}
RPATH=${IVORY_RCLONE_PATH:-IvoryBackups}
LOG=$OUT/offsite.log
ts() { date -Is; }

[ -f "$PASS" ] || { echo "$(ts) recovery-bundle ABORT: $PASS missing — create it (a strong passphrase) and store the SAME passphrase in your password manager" | tee -a "$LOG"; exit 1; }

stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
install -m600 "$REPO/.env.rig"          "$stage/.env.rig"
install -m600 /root/.ivory_backup_pass  "$stage/ivory_backup_pass"
mkdir -p "$stage/cloudflared"
cp /etc/cloudflared/config.yml          "$stage/cloudflared/"
cp /root/.cloudflared/*.json            "$stage/cloudflared/"
cp /root/.cloudflared/cert.pem          "$stage/cloudflared/" 2>/dev/null || true
# Bundle the failover runbook + script too, so the machine that has the bundle has everything.
cp "$REPO/ops/DR-RUNBOOK.md"            "$stage/" 2>/dev/null || true
cp "$REPO/ops/ivory-failover.ps1"      "$stage/" 2>/dev/null || true

out="$OUT/ivory-recovery-bundle.tar.gz.enc"
tar -C "$stage" -czf - . | openssl enc -aes-256-cbc -pbkdf2 -salt -pass "file:$PASS" > "$out"
chmod 600 "$out"

# Push via Microsoft Graph simple-PUT (rclone's upload is broken on this drive — see rig_offsite_sync.sh).
RC=/usr/bin/rclone
CONF=/root/.config/rclone/rclone.conf
if $RC listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
  $RC about "${REMOTE}:" >/dev/null 2>&1 || true
  ACCESS=$(grep -oP "\"access_token\":\"\K[^\"]+" "$CONF" | head -1)
  code=$(curl -s -m 120 -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer $ACCESS" -H "Content-Type: application/octet-stream" \
    --data-binary @"$out" "https://graph.microsoft.com/v1.0/me/drive/root:/${RPATH}/recovery/$(basename "$out"):/content")
  if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    echo "$(ts) recovery-bundle OK: encrypted + pushed (Graph PUT $code) to ${REMOTE}:${RPATH}/recovery" | tee -a "$LOG"
  else
    echo "$(ts) recovery-bundle: built locally but cloud push failed (HTTP $code)" | tee -a "$LOG"
  fi
else
  echo "$(ts) recovery-bundle built locally ($out); cloud push pending the one-time OneDrive auth" | tee -a "$LOG"
fi
