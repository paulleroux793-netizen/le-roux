---
id: ref-data-architecture
title: Data architecture — where everything lives
status: active
last_reviewed: 2026-06-05
---

# Data architecture — where everything lives

## The build model (read first)
- **Elixir = the LIVE system and READ-ONLY source.** Never written to. Reception keeps doing real work in Elixir.
- **Ivory = a FULLY EDITABLE working copy**, populated by importing Elixir data, so we build + test the whole system "as if we're using Ivory now" without touching Elixir.
- **Flip the switch** (reception moves to Ivory) only when Paul says so. Until then both run; Ivory is a sandbox refreshed from Elixir. See `decisions/0001-build-model.md`.

## SOURCE — Elixir (Firebird 2.5)
- Host: **RECEPTION-PC** (practice LAN `10.0.0.126`, Tailscale `100.117.109.22`). DB file `C:\Elixir\SQL\MDLDATA.FDB`. Server is Firebird 2.5.
- **Read path (read-only):** Paul copies `MDLDATA.FDB` (Elixir CLOSED → file unlocked) → OneDrive `…\1. Dr Chalita le Roux\Elixir\MDLDATA.FDB` → read on local Firebird (`C:\Program Files (x86)\Firebird\Firebird_2_5\bin\isql.exe`) with `SYSDBA/masterkey` (works on a copy; the live remote login is a custom unknown pw — irrelevant while the copy works).
- Key tables: `EXPRESSAPPOINTMENTS` (diary; STARTDATE/FINISH/RESOURCEID/CAPTION/MESSAGE1), `DIARYRESOURCE` (RESOURCECODE 1=Chalita 5=Eliska; 2/3/4 inactive), `ACCOUNTS` (1566 patients/accounts; SURNAME/FIRSTNAME/EMAIL/MEDICALFUNDID/NIDN/phones), `MEDICAL` (3614 medical aid), `ESTIMATES` (3935)+`ESTIMATEITEMS` (41788; TARIFFLINK/NARRATIVE/AMOUNT/PATIENTDUE/CREDITMEDICAL/TEETH), `TARIFF` (1345).

## TARGET — Ivory (Rails 8 + Inertia/React + Postgres, on the rig)
- Reach: rig Tailscale `100.73.38.21`, practice LAN `http://10.0.0.125:3000` (LAN = no password; remote = password `reception` / see secrets).
- Models: `Patient` (requires phone OR id_number; id_number encrypted) · `BillingAccount` (account_code) ↔ `AccountPatient` (relationship) · `Appointment` (belongs_to patient; provider optional; status enum scheduled/confirmed/arrived/in_consultation/completed/pending_confirmation/cancelled, colour follows status; per-provider no-overlap GiST; status change = `PATCH /appointments/:id/set_status`) · `Provider` · `Estimate`+`EstimateLine` · `ProcedureCode` (172 SADA/tariff codes) · `MedicalScheme` (178) · `CalendarNote` (block-outs/"Closed") · `ElixirDiarySnapshot`/`ElixirEstimateSnapshot` (read-only mirrors).

## IMPORT SCRIPTS (`le-roux-repo/script/`)
- `refresh_elixir_mirror.sh` — ONE COMMAND: freshest OneDrive MDLDATA.FDB → extract → parse → ship to rig → import.
- `extract_elixir_diary.sql` + `parse_elixir_diary.py` — Firebird → `diary_live.json`. (CAUTION: `isql -o` APPENDS — rm first.)
- `import_elixir_live.rb` — → `ElixirDiarySnapshot` (read-only mirror).
- `import_elixir_appointments.rb` — → **EDITABLE Ivory Appointments** tagged `[elixir-test]` (Closed→CalendarNote; patient matched by name else created with synthetic id `ELX-IMPORT-n`; overlaps skipped; idempotent). **The current editable test diary.**
- Container note: rig repo mounts at `/rails`; `tmp/` is a separate volume → use `docker compose cp` to land files inside the container.

## Infra
- Rig: 2 Docker containers (`web`, `db`), Solid Queue in Puma, Cloudflare named tunnel (`wa.`/`intake.chalitaleroux.co.za`), ufw (3000 open to LAN `10.0.0.0/24` + Tailscale).
- Tailscale tailnet `paulleroux793@`: laptop / rig (`chalita-5090`) / `reception-pc`. Key expiry disabled, SSH check→accept (no re-logins).
- Secrets: `../_shared/.env`. Anthropic = cloud API (the RTX-5090 GPU is idle).
