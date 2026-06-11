#!/usr/bin/env bash
# Self-healing public ingress for Ivory on the rig.
#
# Runs a Cloudflare quick-tunnel to localhost:3000. If cloudflared dies (the
# failure that caused Twilio HTTP 530 on 2026-06-04), the loop restarts it.
# Quick-tunnel subdomains rotate on restart, so on EVERY (re)start we push the
# new URL to the Twilio WhatsApp sender's webhook automatically — the line
# self-heals without a human. Paired with URL-independent signature validation
# in Webhooks::WhatsappController, a rotated URL never breaks inbound delivery.
#
# Secrets (TWILIO_SID/TWILIO_TOKEN/SENDER_SID) live in /opt/ivory/tunnel.env (root 600).
set -u

ENV_FILE=/opt/ivory/tunnel.env
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
LOG=/var/log/ivory-tunnel.log
RUNLOG=/run/ivory-cf.log
URLFILE=/opt/ivory/current_tunnel_url

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "$LOG"; }

update_twilio() {
  local url="$1"
  if [ -z "${TWILIO_SID:-}" ] || [ -z "${SENDER_SID:-}" ]; then
    log "WARN no Twilio creds in $ENV_FILE — skipping webhook update"
    return
  fi
  curl -s -X POST -u "$TWILIO_SID:$TWILIO_TOKEN" \
    "https://messaging.twilio.com/v2/Channels/Senders/$SENDER_SID" \
    -H "Content-Type: application/json" \
    -d "{\"webhook\":{\"callback_url\":\"$url/webhooks/whatsapp\",\"callback_method\":\"POST\"}}" \
    -o /dev/null -w "twilio_update http=%{http_code}" >> "$LOG" 2>&1
  echo "" >> "$LOG"
}

while true; do
  : > "$RUNLOG"
  /usr/local/bin/cloudflared tunnel --url http://localhost:3000 --no-autoupdate >> "$RUNLOG" 2>&1 &
  CF=$!

  url=""
  for _ in $(seq 1 40); do
    url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$RUNLOG" | head -1)
    [ -n "$url" ] && break
    kill -0 "$CF" 2>/dev/null || break
    sleep 2
  done

  if [ -n "$url" ]; then
    log "UP $url"
    echo "$url" > "$URLFILE"
    update_twilio "$url"
  else
    log "FAILED to obtain tunnel URL — restarting cloudflared"
    kill "$CF" 2>/dev/null
  fi

  wait "$CF" 2>/dev/null
  rc=$?
  log "cloudflared exited (rc=$rc) — restarting in 5s"
  sleep 5
done
