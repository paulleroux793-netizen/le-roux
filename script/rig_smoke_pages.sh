#!/usr/bin/env bash
# Page-level smoke test: hit every key dashboard route with auth and report the
# HTTP status + which Inertia component rendered. Run on the rig:
#   bash script/rig_smoke_pages.sh
set -uo pipefail
PW=$(grep ^DASHBOARD_PASSWORD .env.rig | cut -d= -f2)
BASE=http://localhost:3000
AUTH="-u reception:$PW"
PID=$(curl -s $AUTH "$BASE/patients" | grep -oE '/patients/[0-9]+' | head -1 | grep -oE '[0-9]+')
routes=(
  "/" "/dashboard" "/appointments" "/appointments/calendar" "/patients"
  "/patients/$PID" "/patients/$PID/file" "/conversations" "/reconciliation"
  "/imaging" "/procedure-codes" "/treatment-macros" "/accounts"
  "/courses-of-treatment" "/estimates" "/invoices" "/scribe-sessions"
  "/mail" "/recalls" "/reporting" "/analytics" "/reminders" "/audit-log"
  "/notifications" "/settings" "/search?q=a"
)
fail=0
printf "%-28s %-6s %s\n" "ROUTE" "HTTP" "INERTIA_COMPONENT"
for r in "${routes[@]}"; do
  body=$(curl -s $AUTH -w '\n%{http_code}' "$BASE$r")
  code=$(printf '%s' "$body" | tail -1)
  comp=$(printf '%s' "$body" | grep -oE '"component":"[^"]+"' | head -1 | sed 's/"component":"//;s/"//')
  [ -z "$comp" ] && comp=$(printf '%s' "$body" | grep -oE 'data-page="[^"]*component[^"]*' | head -1 | grep -oE '&quot;component&quot;:&quot;[^&]+' | sed 's/.*&quot;//')
  flag=""; if [ "$code" != "200" ]; then flag="  <-- FAIL"; fail=$((fail+1)); fi
  printf "%-28s %-6s %s%s\n" "$r" "$code" "${comp:-?}" "$flag"
done
echo; echo "PATIENT_ID_USED=$PID  FAILS=$fail"
