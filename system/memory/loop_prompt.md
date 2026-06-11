# AUTONOMOUS IVORY-READINESS LOOP — canonical task doc (Paul, 2026-06-09)

GOAL: get Ivory production-ready for the practice to use **tomorrow**. Work in cycles **≤2 min apart**, autonomously, until "system full" (below) or Paul says stop.

## Environment (rig: `ssh rig`)
- **LIVE**: `/opt/ivory/le-roux-repo`, `docker compose -f docker-compose.rig.yml`, web on **:3000**. Reception depends on it.
- **STAGING (offline)**: `/opt/ivory/staging`, `docker compose -p ivory-staging -f docker-compose.staging.yml`, web on **:3001**, its own DB. **ALL development + testing happens here.**

## HARD RULES (why: container recreates during the day dropped the live system)
1. **NEVER** edit `/opt/ivory/le-roux-repo` or recreate/restart the **live web container** inside a cycle. Build + test only on `/opt/ivory/staging` + :3001.
2. **Deploy to live only when**: validated on staging **AND** the test suite is green **AND** it is a **code** change → `rsync` just the changed file(s) staging→live (Rails dev hot-reloads; for `.jsx` run `docker compose -f docker-compose.rig.yml exec -T web bin/vite build` — this does NOT restart). **Never** apply compose/Docker/infra changes to live automatically — append them to `build-status.md` as `AFTER-HOURS DEPLOY NEEDED` for Paul.
3. **Read-only** on Elixir + the SIDEXIS PC. Money / PHI / access-control are hard gates, never traded.

## Priority tasks (pick the highest-value not-yet-done each cycle)
- **A. Staging ready**: `curl -s localhost:3001/up` returns 200. Seed its DB once from live: `docker compose -f docker-compose.rig.yml exec -T db pg_dump -U postgres -d dr_leroux_receptionist_development --clean --if-exists | docker compose -p ivory-staging -f docker-compose.staging.yml exec -T db psql -U postgres -d dr_leroux_receptionist_development`.
- **B. Fix the regression suite (on staging) → green**: 96 request specs fail with **401** (the harness doesn't sign in after the live login-wall — fix the request-spec auth/sign-in helper, or disable USER_AUTH cleanly in `RAILS_ENV=test`). 32 service specs are **stale vs the hybrid local-model fallback** (AiService now *falls back* instead of raising — update specs to the new behaviour). 7 job/mailer specs. Iterate `rspec` on staging until green/near-green; deploy the spec + code fixes to live (code-only, hot-reload).
- **C. Pull LATEST Elixir data into Ivory** (diary + accounts) for tomorrow: inspect `/opt/ivory/le-roux-repo/script/` for the Elixir import scripts + the **live Firebird** link (Firebird 2.5, SYSDBA/masterkey; the OneDrive `.FDB` is stale — use the LIVE link). Validate the import on **staging** first, then run it against **live** (data refresh, after-hours, read-only on Elixir). Verify the diary + accounts show the newest data. If the live Firebird isn't reachable, document exactly what's needed and flag for Paul.
- **D. Harden for tomorrow** (per self-improve-loop-pro): instrument → find top errors / SLO breaches → verify core workflows (WhatsApp booking, diary, billing, transaction report, imaging + DICOM viewer, scribe) → fix the highest-value gap. Regression-gate every change.

## Each cycle
1. **Dedup**: if the last `[LOOP-CYCLE …]` line in `build-status.md` is <90s old, a cycle is mid-flight — just ScheduleWakeup and exit.
2. Read `build-status.md` for state.
3. Do **ONE** focused improvement; validate on staging + run the relevant tests.
4. If validated + safe + after-hours → deploy **code-only** to live (hot-reload, no restart).
5. Append one line: `[LOOP-CYCLE <YYYY-MM-DD HH:MM>] <what was done> | <validation>` to `/opt/ivory/le-roux-repo/system/memory/build-status.md`.
6. **ScheduleWakeup(delaySeconds 100)** with the resume prompt.

## Stop condition ("system full")
Regression suite green **and** Elixir data current **and** all core flows verified. Then post a summary and drop to a long heartbeat (ScheduleWakeup 1800s).

If Paul messages: **answer first**, then resume.
