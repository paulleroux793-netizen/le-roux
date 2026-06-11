#!/usr/bin/env bash
# Hourly Ivory health check (runs on the rig via cron). Catches runtime /
# production breakages so Ivory never silently breaks: web down, any key page
# returning non-200/500, DB errors, a dead Solid Queue worker, full disk, the
# Cloudflare tunnel down, an unhealthy container, or a recent 500 spike.
# Writes a rolling log + a latest-status file, and alerts on FAIL.
# (Client-side React crashes are caught at DEPLOY time by the Playwright browser
#  smoke — see system/meta/verification.md — so this stays server-side.)
#
# Schedule (host crontab):  0 * * * * /opt/ivory/le-roux-repo/script/healthcheck.sh
set -uo pipefail
REPO=/opt/ivory/le-roux-repo
HDIR=/opt/ivory/health
LOG=$HDIR/health.log
STATUS=$HDIR/status.txt
mkdir -p "$HDIR"
DC="docker compose -f $REPO/docker-compose.rig.yml"
cd "$REPO" || exit 1
# Optional external dead-man's-switch: put HEALTH_HEARTBEAT_URL=<healthchecks.io ping URL>
# in /root/.ivory_health_env. On every healthy run we ping it; if the rig dies (power off,
# crash) the pings STOP and the external service alerts you — the one failure email can't catch.
[ -f /root/.ivory_health_env ] && . /root/.ivory_health_env || true
ts=$(date '+%Y-%m-%d %H:%M:%S')
fails=()

# 1. web /up
code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://localhost:3000/up 2>/dev/null || echo 000)
[ "$code" = 200 ] || fails+=("web /up=$code")

# 2. key pages render. 200 = served; 302 = redirect to /login when USER_AUTH_ENABLED is on
#    (still healthy — the app is up and auth is working). Only 000/500/4xx-other is a fault.
for p in /diary /patients /procedure-codes /dashboard; do
  c=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -H 'Host: 10.0.0.125' "http://localhost:3000$p" 2>/dev/null || echo 000)
  case "$c" in 200|302) ;; *) fails+=("page $p=$c") ;; esac
done

# 3. DB reachable
db=$($DC exec -T web bin/rails runner 'print Patient.count' 2>/dev/null | tr -dc '0-9')
[[ "$db" =~ ^[0-9]+$ ]] || fails+=("DB query failed")

# 4. Solid Queue has a live worker (heartbeat in last 5 min)
$DC exec -T web bin/rails runner 'exit(defined?(SolidQueue::Process) && SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).exists? ? 0 : 1)' 2>/dev/null \
  || fails+=("Solid Queue: no live worker")

# 5. disk under 90%
use=$(df --output=pcent /opt 2>/dev/null | tail -1 | tr -dc '0-9'); use=${use:-0}
[ "$use" -lt 90 ] || fails+=("disk ${use}%")

# 6. Cloudflare tunnel up
systemctl is-active --quiet cloudflared 2>/dev/null || fails+=("cloudflared tunnel down")

# 7. containers healthy
$DC ps --format '{{.Service}} {{.Status}}' 2>/dev/null | grep -qiE '^web .*Up' || fails+=("web container not Up")

# 8. recent 500 spike (last ~hour of web logs). grep -c exits 1 on zero matches, so
#    sanitize to a clean integer instead of `|| echo 0` (which double-counted -> "0\n0").
n500=$($DC logs --since 60m web 2>/dev/null | grep -c 'Completed 500' 2>/dev/null)
[[ "$n500" =~ ^[0-9]+$ ]] || n500=0
[ "$n500" -lt 20 ] || fails+=("$n500 x HTTP 500 in last hour")

# --- EMAIL alert via the practice SMTP (.env.rig). Debounced: only on STATE CHANGE
#     (ok->fail or fail->ok), never every cycle while down. Goes to ALERT_EMAIL_TO. ---
STATE=$HDIR/alert_state
send_alert() {  # $1 = ALERT|RECOVERED, $2 = body
  $DC exec -T -e ALERT_KIND="$1" -e ALERT_MSG="$2" web bin/rails runner '
    require "mail"
    m = Mail.new
    m.from = ENV["MAILER_FROM_ADDRESS"]
    m.to = (ENV["ALERT_EMAIL_TO"].to_s.empty? ? "paulleroux793@gmail.com" : ENV["ALERT_EMAIL_TO"])
    m.subject = "[Ivory uptime] " + ENV["ALERT_KIND"].to_s
    m.body = ENV["ALERT_MSG"].to_s
    m.delivery_method :smtp, address: ENV["SMTP_ADDRESS"], port: ENV["SMTP_PORT"].to_i, user_name: ENV["SMTP_USER_NAME"], password: ENV["SMTP_PASSWORD"], authentication: :plain, enable_starttls_auto: true, open_timeout: 15, read_timeout: 20
    m.deliver!
  ' >/dev/null 2>&1 || echo "$ts ALERT EMAIL FAILED" >> "$LOG"
}

prev=$(cat "$STATE" 2>/dev/null || echo ok)
if [ ${#fails[@]} -eq 0 ]; then
  line="$ts OK (db=$db, disk=${use}%, 500s/h=$n500)"
  echo "$line" >> "$LOG"; echo "$line" > "$STATUS"
  # dead-man's-switch ping (only on a healthy run; absence => external alert)
  [ -n "${HEALTH_HEARTBEAT_URL:-}" ] && curl -fsS -m 10 "$HEALTH_HEARTBEAT_URL" >/dev/null 2>&1 || true
  [ "$prev" = "fail" ] && send_alert "RECOVERED" "Ivory is back UP ($ts) — all health checks passing again."
  echo ok > "$STATE"
else
  line="$ts FAIL -> ${fails[*]}"
  echo "$line" >> "$LOG"; echo "$line" > "$STATUS"
  [ "$prev" != "fail" ] && send_alert "ALERT" "Ivory health ALERT ($ts): ${fails[*]}"
  echo fail > "$STATE"
fi

# keep the log from growing unbounded
tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
