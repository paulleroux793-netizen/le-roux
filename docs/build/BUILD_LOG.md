# Practice-Management System — Autonomous Build Log

> Append-only progress log for the overnight autonomous build. Each work session reads the
> **Current status** block, does the next chunk, ticks the checklist, and appends a session entry.
> Branch: `feat/practice-management-system` (based on `feat/calendar-redesign-status-journey`).
> **NEVER deployed by the build. Additive only — do not modify existing live tables/models/routes
> in breaking ways. Park anything uncertain in UNCERTAINTIES.md and keep going.**

## Guardrails (read every session)
- Additive only. New tables/models/controllers/pages. Do not alter `patients`, `appointments`,
  `conversations`, `call_logs`, `doctor_schedules`, `practice_settings` in breaking ways.
- **System name: "Ivory"** (working codename — UNCERTAINTIES #16).
- **Migration timestamps**: Rails 8.1 rejects timestamps >~1 day in the future. System clock is
  2026-05-22; use `20260523NNNNNN`-dated migrations (NOT the 24th+). Keep them after the last applied.
- **Irregular plurals**: `courses_of_treatment` — set `self.table_name` on the model, pass `column:`
  to `add_foreign_key`, and `class_name:` on `has_many :courses_of_treatment`. (Learned in P2.1.)
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
- [x] P1.5 Importer (dry-run): PatientDemographicsImporter — extracts to db/seed_data/patients.csv
  (gitignored PII), matches existing patients by phone, never clobbers. Dry-run plan: 1572 accounts,
  1690 patients, 168 schemes, 510 exceptions (families sharing/lacking a phone). **Real write GATED on
  UNCERTAINTIES #13 (patient identity).** Logic proven; no live data touched.
- [x] P1.6 Controllers + Inertia pages: ProcedureCatalogue, TreatmentMacros, BillingAccounts(+show).
  Additive routes (/procedure-codes, /treatment-macros, /accounts). New "Practice" nav group.
- [x] P1.7 Verified on localhost:3000 — all three pages HTTP 200 with real seeded data (8101, BRIDGE 3).

**PHASE 1 COMPLETE.**

### Phase 2 — Clinical core: Course of Treatment + tooth chart
- [x] P2.1 Migrations: courses_of_treatment, treatment_items, clinical_notes, tooth_chart_entries
- [x] P2.2 Models + state machine (planned→completed), immutable signed notes — verified in Docker
- [x] P2.3 Odontogram component (FDI, colour-coded) + CoursesOfTreatment index/show pages + routes + nav
- [x] P2.4 Verified — pages HTTP 200 with demo COT (odontogram, items, signed note). Demo seed added.

**PHASE 2 COMPLETE.**

### Phase 3 — Money: estimates → invoices → payments → statements
- [x] P3.1 Migrations: estimates+lines, invoices (sequential no.)+lines, payments, statements, document_sequences
- [x] P3.2 Models + logic: atomic gap-free numbering, per-line VAT (inclusive), estimate→invoice convert,
  invoice-from-completed-items, payment→status, statements, void-not-edit immutability. Verified in Docker.
- [ ] P3.3 UI (Invoices/Estimates pages) + 16-element compliant invoice presentation (HPCSA DP0118702 +
  BHF placeholder on practice settings) + claimable statement PDF + WhatsApp-send hook (additive)
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
**Phase 3 data layer + logic done (P3.1, P3.2). Next: P3.3 — billing UI + compliant invoice
presentation + statement PDF + WhatsApp hook, then P3.4 verify. Then Phase 4 (digital file & forms).**
NEXT (P3.3): Invoices index/show + Estimates index pages; add HPCSA (DP0118702) + BHF (placeholder)
fields to practice settings for the invoice header; render a compliant invoice (practice+practitioner
numbers, patient details, SADA+tooth+date+VAT per line, sequential number); claimable statement view;
an additive "send via WhatsApp" stub (do NOT touch the live WhatsApp incoming flow). Guardrails:
migration timestamps 20260523NNNNNN; irregular plurals need explicit column/class_name.

(historical) NEXT (P2.1):
migrations for courses_of_treatment (patient_id, optional scheme_membership_id, setting enum:
in_chair/hospital_chair/hospital_theatre/sedation, status, authorisation_number),
treatment_items (cot_id, procedure_code_id, provider, tooth_number FDI, surface, planned/completed
dates, status, fee), clinical_notes (cot_id/patient_id, SOAP fields, signed_by/at — append-only),
tooth_chart_entries (patient_id, tooth_number, condition, surface, noted_at). Then P2.2 models +
status state machine (planned→completed moves item toward invoicing), P2.3 odontogram component +
COT page, P2.4 verify. Keep additive; no live tables touched.

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
- **2026-05-22 ~18:10** — P1.5 DONE (dry-run). Extracted 2,200-row demographics → gitignored
  db/seed_data/patients.csv (PII never committed). Built PatientDemographicsImporter (matches existing
  by phone, never clobbers; creates accounts/schemes; creates new patients only with unique phone).
  Dry-run: 1572 accounts / 1690 patients / 168 schemes / 510 exceptions. Real write GATED on
  UNCERTAINTIES #13 (patient identity for families sharing a phone). Committed importer code only.
  Next: P1.6 controllers + Inertia pages on the seeded catalogue.
- **2026-05-22 ~18:30** — P1.6 + P1.7 DONE → PHASE 1 COMPLETE. Built ProcedureCodes/TreatmentMacros/
  BillingAccounts controllers + 4 Inertia pages + additive routes + a "Practice" sidebar group.
  Verified all 3 pages HTTP 200 with real seeded data (8101, BRIDGE 3). Parked #15 (nav labels not yet
  localised to AF). Next: Phase 2 clinical core.
- **2026-05-22 ~18:55** — Phase 2 data layer DONE (P2.1, P2.2). 4 clinical tables + models;
  planned→completed state machine, fee/VAT snapshot, immutable signed SOAP notes w/ amendment chain,
  FDI tooth chart. Hit + fixed two Rails gotchas (future migration timestamp; irregular-plural
  FK/association) — now in Guardrails. Named the system **Ivory** (UNCERTAINTIES #16) and wrote
  docs/COMPARISON_IVORY_VS_GOODX_VS_EXACT.md (the review scorecard). Committed a52684c. Next: P2.3 odontogram UI.
- **2026-05-22 ~19:15** — P2.3 + P2.4 DONE → PHASE 2 COMPLETE. Odontogram component (FDI, colour-coded
  conditions), CoursesOfTreatment index + show pages, routes, nav entry. Demo seed
  (db/seeds/practice_management_demo.rb, fake patient) so clinical screens are reviewable. Verified
  HTTP 200 with chart + items + signed note. Scorecard updated (odontogram ✅). Next: Phase 3 (money).
- **2026-05-22 ~19:16** — Phase 3 data layer DONE (P3.1, P3.2). 7 billing tables; DocumentSequence
  (atomic gap-free numbering), BillableLine concern (VAT-inclusive per-line), Estimate/Invoice/Payment/
  Statement models with estimate→invoice conversion, invoice-from-completed-items, payment→status,
  void-not-edit immutability. Verified full flow in Docker (EST/INV sequential, VAT, statement balance).
  Parked #17 (VAT-inclusive + VAT-registered?). Committed 10d3a9e. Scorecard updated. Next: P3.3 billing UI + compliant invoice.
