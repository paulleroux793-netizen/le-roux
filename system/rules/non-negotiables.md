---
id: rules-non-negotiables
title: Non-negotiable rules
status: active
last_reviewed: 2026-06-05
---

# Non-negotiable rules

These are hard laws. Do not break them without an explicit decision recorded in `decisions/`.

## Elixir (the live legacy system)
1. **NEVER write to, modify, or reset anything in Elixir** — the database, its files, its Firebird logins, or the `…/Elixir/` folder. Ivory only ever READS Elixir (via a file copy). Elixir is the practice's live system; reception still uses it.
2. Read access is **read-only by copy**: a fresh `MDLDATA.FDB` (Elixir CLOSED) copied to OneDrive, opened on a local Firebird with `SYSDBA/masterkey`. See `reference/data-architecture.md`.

## PHI / POPIA (patient data)
3. Patient-identifiable data (names, ID numbers, medical history, contact, mail bodies) is **special personal information** — encrypted at rest in Postgres (Active Record Encryption). Never put PHI in logs, Markdown, or anything in `system/` (only schema/architecture, never patient rows).
4. SA ID number is encrypted (deterministic). Dr Chalita le Roux is the Information Officer.

## What the AI says to patients (WhatsApp / mail)
5. The 11 brand rules apply to every patient-facing message. Specifically banned: after-hours/24-hour/weekend availability claims, "we'll see you today", medical-aid direct-billing claims, medication dosing, absolute claims/superlatives.
6. **No direct medical-aid billing** — patients pay and self-claim with a statement.
7. Pricing IS allowed in WhatsApp (private 1:1) per the brand file; quote per `config/` with the scan-cost warning.
8. Canonical spellings/positioning: **Amorosa** (not Amarosa), Roodepoort positioning, canonical phone numbers + Maps URL.

## Email
9. For ALL mail use ONLY **drchalitaleroux.co.za** (info@drchalitaleroux.co.za on mail.drchalitaleroux.co.za). NEVER chalitaleroux.co.za.

## Engineering
10. **ONE booking engine** (`attempt_booking`) that all channels call; no channel writes the diary directly.
11. Config that affects runtime behaviour is declared in `config/` — never invent config keys elsewhere.
12. Before restarting the rig web container after a Ruby change, `ruby -c` it in a one-off container first.

## Research & verification (Paul, 2026-06-05)
13. **Research is ONLY via Perplexity** (the Perplexity API / `mcp__perplexity__*`). NEVER use WebSearch or rely on unaided model knowledge for research — and only TRUST research that came from Perplexity. (Perplexity API key is in `~/.claude/settings.json` → `mcpServers.perplexity.env.PERPLEXITY_API_KEY`; Windows: write responses with `encoding="utf-8"`, they contain `→`/`‑`.)
14. **VERIFY before claiming done — at the right level.** Backend/API/DB changes: curl + a `rails runner` data check. **FRONTEND changes MUST be browser-tested** (Playwright headless) — a `curl` returns HTTP 200 while the React page actually crashes client-side (this shipped the diary 500). Never say "done"/"works" on a frontend change without a passing browser smoke test. See `meta/verification.md`.
