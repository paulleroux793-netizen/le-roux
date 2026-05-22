# Practice-Management System — Autonomous Build Log

> Append-only progress log for the overnight autonomous build. Each work session reads the
> **Current status** block, does the next chunk, ticks the checklist, and appends a session entry.
> Branch: `feat/practice-management-system` (based on `feat/calendar-redesign-status-journey`).
> **NEVER deployed by the build. Additive only — do not modify existing live tables/models/routes
> in breaking ways. Park anything uncertain in UNCERTAINTIES.md and keep going.**

## Guardrails (read every session)
- Additive only. New tables/models/controllers/pages. Do not alter `patients`, `appointments`,
  `conversations`, `call_logs`, `doctor_schedules`, `practice_settings` in breaking ways.
- New routes namespaced where possible; never touch `webhooks/*` or existing booking/calendar routes.
- Migrate + verify in the local Docker stack (`docker compose up`); never touch production/Railway.
- Commit after each working chunk with a clear message. Don't push unless asked.
- Uncertain? Pick the sensible default, build it, log it in UNCERTAINTIES.md, move on.

## The plan (phases from DIGITAL_PRACTICE_PROPOSAL.md §8)

### Phase 1 — Foundation: accounts + catalogue + macros
- [x] P1.0 Branch + build infra (BUILD_LOG, UNCERTAINTIES)
- [x] P1.1 Migrations: billing_accounts, account_patients, medical_schemes, scheme_memberships, scheme_membership_patients
- [x] P1.2 Migrations: procedure_codes, treatment_macros, treatment_macro_items, fee_schedules, fee_schedule_items
- [x] P1.3 Models + associations (additive on Patient via PracticeManagementPatient concern; Patient logic untouched) — migrated + sanity-verified in Docker
- [x] P1.4 Seeds: 172 procedure_codes (real median fees from transactions) + 20 macros (170 lines, all linked) + PRIVATE 2026 fee schedule. CSVs in db/seed_data/, seed at db/seeds/practice_management.rb (idempotent)
- [ ] P1.5 Importer: Patient Demographics.XLS → patients + billing_accounts (dry-run first)
- [ ] P1.6 Controllers + Inertia pages: Accounts list/show, Procedure catalogue, Macros
- [ ] P1.7 Verify on localhost:3000

### Phase 2 — Clinical core: Course of Treatment + tooth chart
- [ ] P2.1 Migrations: courses_of_treatment, treatment_items, clinical_notes, tooth_chart_entries
- [ ] P2.2 Models + state machine (planned→completed)
- [ ] P2.3 Tooth chart (odontogram) component + COT page
- [ ] P2.4 Verify

### Phase 3 — Money: estimates → invoices → payments → statements
- [ ] P3.1 Migrations: estimates, estimate_lines, invoices (sequential no.), invoice_lines, payments, statements
- [ ] P3.2 Compliance: 16-element invoice, VAT logic (zero/15%), HPCSA+BHF, sequential numbering, immutable (reverse-not-edit)
- [ ] P3.3 PDF generation (claimable statement) + WhatsApp send hook (additive, not touching live flow)
- [ ] P3.4 Verify

### Phase 4 — Digital file & forms
- [ ] P4.1 Patient file folders (mirror practice structure) + document model + uploads
- [ ] P4.2 WhatsApp digital forms: form templates (versioned), tokenised mobile links, e-signature (ECTA), submission → file
- [ ] P4.3 Digital notepad / annotation surface → PDF to file
- [ ] P4.4 Verify

### Phase 5 — Integrations
- [ ] P5.1 SIDEXIS bridge agent (export-folder watcher first) + patient-ID matching + thumbnails
- [ ] P5.2 Recalls (6-month) + reminders (additive)
- [ ] P5.3 Reporting / KPIs
- [ ] P5.4 Verify

### Phase 6 — AI chair-side scribe (LAST)
- [ ] P6.1 In-chair appointment state → local Whisper capture (reuse transcribe_calls.py)
- [ ] P6.2 Claude extracts findings → drafts Course of Treatment + Estimate
- [ ] P6.3 Review-and-confirm UI (never auto-bill)
- [ ] P6.4 Verify

## Cross-cutting (every phase)
- [ ] Users/roles/permissions (reception vs dentist) + immutable AuditLog on every clinical/financial change
- [ ] Retention scheduling (clinical 6y / financial 5y); POPIA security

---

## Current status
**Phase 1, next step P1.5 — patient import (dry-run first).** Data layer + seeds done. NEXT:
extract `Patient Demographics.XLS` (2,200 rows) → a repo CSV (db/seed_data/patients.csv), write an
idempotent importer that (a) matches existing patients by normalised phone (NEVER duplicates/clobbers
live patients), (b) creates billing_accounts + account_patients, (c) captures scheme membership where
present. Run a DRY-RUN that reports create/match/skip counts before any write. Then P1.6
controllers/pages (Accounts list/show, Procedure catalogue, Macros), P1.7 verify on localhost:3000.

How to resume: read this file, do the next unchecked `[ ]` step, stay additive, verify in Docker
(`docker compose exec -T web bundle exec rails ...`), commit, append a session entry, keep going.
Park anything uncertain in UNCERTAINTIES.md.

## Session entries
- **2026-05-22 ~17:10** — Branch set up (based on calendar branch — UNCERTAINTIES #1), wrote
  BUILD_LOG + UNCERTAINTIES, studied schema/controllers/Inertia conventions.
- **2026-05-22 ~17:35** — P1.1–P1.3 DONE. 10 new tables + 11 models, Patient extended via concern.
  Migrated cleanly in Docker; sanity test passed (account codes, associations, macro resolution, VAT).
  Committed `e93367b`. Next: P1.4 seeds + macro import.
- **2026-05-22 ~17:55** — P1.4 DONE. Extracted real GoodX data to repo CSVs (db/seed_data/): 172
  procedure codes with real median fees from a year of transactions, 20 macros (170 lines). Fixed a
  column bug (tariff code lives in `TariffLink`, not `TariffCode`). Idempotent seed at
  db/seeds/practice_management.rb; PRIVATE 2026 fee schedule built. Verified BRIDGE 3 expands to 16
  linked lines. Parked UNCERTAINTIES #10–12 (placeholder descriptions, VAT-by-keyword, junk codes).
  Next: P1.5 patient import (dry-run).
