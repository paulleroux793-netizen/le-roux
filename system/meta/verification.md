---
id: meta-verification
title: How to verify changes (so Ivory never ships broken)
status: active
last_reviewed: 2026-06-05
---

# Verification practice

Paul's standing instruction (2026-06-05): **stop needing nudges — verify properly, get it right.** This is the repeatable method. Research-backed (Perplexity benchmark of how disciplined teams gate changes).

## The core failure this prevents

A `curl` (or rig `curl`) returns **HTTP 200** while the **React SPA actually crashes in the browser** (e.g. a variable used before its declaration → "Cannot access 'X' before initialization" → the AppErrorBoundary shows "Something went wrong / 500"). The server rendered fine; the client died. **curl cannot see this.** This shipped the diary 500 twice. Only a real browser catches it.

## The verification ladder — run top-to-bottom, stop at the level the change touches

| Level | Tool | Catches |
|-------|------|---------|
| Syntax | `ruby -c` (Ruby) | parse errors before restart |
| Build | `bin/vite build` on the rig | broken imports, JSX errors |
| **Browser smoke** | **`node script/browser_smoke.mjs`** (Playwright, this PC) | **runtime JS crashes, React error boundary, console errors — the curl-200-but-crashed gap** |
| Data | `bin/rails runner` count/spot-check | the change actually wrote what it should |
| Visual | look at the screenshot Paul sends | layout/wording |

## CRITICAL: a frontend change is not "done" until ALL of this

The rig serves a **built Vite bundle**, not live source. Editing `.jsx` and `curl`-ing is meaningless. The full deploy:

1. Edit the `.jsx`/source.
2. `tar … | ssh rig "tar xzf -"` — land the source on the rig.
3. **`docker compose … exec web bin/vite build`** — recompile the bundle (else the browser still runs the OLD code).
4. **`docker compose … restart web`** — Puma reloads the asset manifest (after a rebuild the hashes change; without a restart you get 404s on assets).
5. **`node /c/Users/paul-/AppData/Local/Temp/ivory-verify/browser_smoke.mjs`** — browser-verify every touched page: `status=200, crashed=false, consoleErrors=0`.

Only after step 5 is green do you say "done". The harness lives at `le-roux-repo/script/browser_smoke.mjs` (hits the rig over Tailscale `100.73.38.21:3000` with basic auth). Set `PAGES=/foo,/bar` to target specific routes.

## Pre-claim checklist

- **Backend/DB/API only:** `ruby -c` → restart → `curl` status + a `rails runner` data assertion. No browser needed.
- **Frontend (any `.jsx`/`.css`/Vite):** the 5 steps above. NEVER skip the browser smoke.
- **Both:** do both.

## ESLint (next hardening step — would have caught the diary TDZ statically)

Add `@typescript-eslint/no-use-before-define`, `no-undef`, `react-hooks/rules-of-hooks` and run on every frontend change. (Tracked; not yet wired.)

## Production monitoring (separate from deploy-time)

`script/healthcheck.sh` runs **hourly via rig cron** — server-side checks (pages 200, DB, Solid Queue worker, disk, Cloudflare tunnel, 500-spike) → `/opt/ivory/health/{health.log,status.txt}`, alerts on FAIL. This catches *runtime* breakage; the browser smoke catches *deploy-time* breakage. Both are needed.
