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
- [x] P3.3 Billing UI: Invoices index/show (compliant invoice w/ HPCSA+BHF, patient+scheme, codes,
  per-line VAT, sequential no., print/PDF, self-claim note), Estimates index. PracticeBillingProfile
  table+seed (HPCSA DP0118702, banking; BHF placeholder). WhatsApp-send button = disabled stub (not
  wired to live flow). Routes + nav added.
- [x] P3.4 Verified — /invoices, /estimates, /invoices/:id all HTTP 200; compliant invoice renders.

**PHASE 3 COMPLETE.**

### Phase 4 — Digital file & forms
- [x] P4.1 documents model + folders mirroring practice structure + PatientFile controller/page
- [x] P4.2 WhatsApp forms: form_templates (versioned) + form_submissions (tokenised link, e-sign capture, auto-file). Mobile form UI + WhatsApp delivery = integration (parked).
- [x] P4.3 notepad_pages model + file-to-patient-file. Drawing canvas UI later.
- [x] P4.4 Verified — PatientFile page HTTP 200 with folders, xray doc, signed consent form, notepad.

**PHASE 4 COMPLETE** (binary storage backend parked #18; FK-on-delete edge → audit #19).

### Phase 5 — Integrations
- [x] P5.1 imaging_studies + ImagingImportService (real SIDEXIS naming parsed, modality, conservative
  match→needs_match queue). 654 studies imported in dev. Imaging page. (Bridge agent + thumbnails = #18/#20)
- [x] P5.2 Recalls (model + due tracking + page). WhatsApp send = additive job (later).
- [x] P5.3 Reporting / KPIs page (production, collections, outstanding, by setting/status).
- [x] P5.4 Verified — /imaging, /recalls, /reporting HTTP 200.

**PHASE 5 COMPLETE.**

### Phase 6 — AI chair-side scribe (LAST)
- [x] P6.1 scribe_sessions bound to in-chair appointment (start_for); local-Whisper transcript field.
- [x] P6.2 ScribeDraftService (transcript→findings→proposed draft estimate; Claude backend + deterministic fallback).
- [x] P6.3 Review UI (ScribeSessions list + ScribeSessionShow with transcript/findings/draft estimate; never auto-bills).
- [x] P6.4 Verified — /scribe-sessions + show HTTP 200; transcript→4 findings→draft estimate.

**PHASE 6 COMPLETE.** (Wire real Anthropic + on-PC Whisper capture, and fix scribe code map → #21.)

**ALL PHASES 1-6 COMPLETE.** Next: Phase 7 — whole-system stress test, audit & remediation.

### Phase 7 — Whole-system stress test, audit & remediation (after Phases 1-6, per Paul 22 May)
- [x] P7.1 Audited whole system → docs/build/SYSTEM_AUDIT.md (security/POPIA, integrity, correctness, perf, additive-safety, gaps).
- [x] P7.2 Prioritised: 4 actionable fixes (high/med); rest are decisions for Paul.
- [x] P7.3 IMPLEMENTED + verified: (1) FK on_delete nullify — patient-delete safe (#19); (2) scribe
  surfaces needs_code instead of guessing a missing billable code (#21); (3) Imaging N+1 → includes(:patient);
  (4) Courses list N+1 → compute from loaded items. Pages still HTTP 200.
- [x] P7.4 Final summary + uncertainties presented to Paul.

**PHASE 7 COMPLETE — BUILD DONE. Loop ended (remaining items are Paul-decisions, not build steps).**

## Cross-cutting (every phase)
- [ ] Users/roles/permissions (reception vs dentist) + immutable AuditLog on every clinical/financial change
- [ ] Retention scheduling (clinical 6y / financial 5y); POPIA security

---

## Current status
**✅ BUILD COMPLETE — ALL PHASES 1-7 DONE. THE LOOP HAS ENDED. DO NO FURTHER BUILD WORK on a stale
wakeup** — if one fires, confirm completion and stop. Phase 7 audit + 4 fixes committed (04ed299);
report at docs/build/SYSTEM_AUDIT.md. The only remaining work needs Paul's input or live credentials/
hardware (NOT autonomous build steps): UNCERTAINTIES #3 (BHF no.), #13 (patient-identity import), #16
(name), #17 (VAT), #8/#20 (SIDEXIS bridge), plus deferred integrations (WhatsApp delivery, on-prem
Whisper, real Anthropic wiring, real patient import). Branch never deployed.

(historical) NEXT (P5.1):
SIDEXIS bridge — model `imaging_studies` (patient_id, modality: intraoral_2d/bitewing/panoramic/
cephalometric/cbct_3d, captured_at, sidexis_patient_ref, thumbnail/storage_key, status) + an
`ImagingImportService` that ingests from a watched export-folder manifest (CSV/JSON) and matches to
patients by id/phone, queuing unmatched for manual link (never fuzzy auto-attach). P5.2 recalls
(recall model, 6-month) + reminders (additive, outbound only — do NOT touch live WhatsApp incoming).
P5.3 reporting/KPIs page (production, collections, outstanding). P5.4 verify. Then Phase 6 (AI scribe),
then Phase 7 (audit + implement recommendations — Paul asked for this explicitly).
Guardrails: migration timestamps 20260523NNNNNN; irregular plurals need explicit column/class_name.

(historical) NEXT (P4.1): document/file model
+ patient file folders mirroring the practice structure (Consent Forms, Referral Letters, Befores &
Afters, Sidexis Scans, etc.) with uploads (Active Storage if available, else a documents table w/
metadata + storage path). P4.2 WhatsApp digital forms: form_templates (versioned) + form_submissions
(tokenised mobile link, e-signature capture) → lands in patient file. P4.3 digital notepad/annotation
→ PDF to file. P4.4 verify. Guardrails: migration timestamps 20260523NNNNNN; irregular plurals need
explicit column/class_name; do NOT touch the live WhatsApp incoming flow (forms send is additive/outbound only).

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
- **2026-05-22 ~19:34** — P3.3 + P3.4 DONE → PHASE 3 COMPLETE. PracticeBillingProfile (HPCSA DP0118702,
  banking, BHF placeholder) + Invoices index/show (compliant invoice: practice+practitioner numbers,
  patient+scheme, SADA codes+tooth+VAT per line, sequential no., print/PDF, self-claim note) + Estimates
  index. Routes + nav. WhatsApp-send = disabled stub. Demo seed extended (estimate+invoice+payment).
  Verified HTTP 200 + compliant header. Scorecard: Invoicing ✅, Self-claim statement ✅. Next: Phase 4.
- **2026-05-22 ~19:39** — PHASE 4 COMPLETE. documents (folders mirroring practice), form_templates +
  form_submissions (tokenised link, e-sign capture, auto-file to patient file), notepad_pages, +
  PatientFile page (folders/docs/forms/notes). Verified HTTP 200 (Sidexis Scans folder, OPG xray,
  signed consent form). Parked #18 (binary storage backend) + #19 (FK-on-delete → audit). Committed next.
  Next: Phase 5 (SIDEXIS + recalls + reporting). Also added Phase 7 (audit+remediate) per Paul.
- **2026-05-22 ~19:43** — PHASES 5 & 6 COMPLETE (built together per Paul). Phase 5: imaging_studies +
  ImagingImportService (real SIDEXIS naming parsed; 654 studies; conservative match→needs_match),
  Recalls, Reporting KPIs. Phase 6: scribe_sessions + ScribeDraftService (transcript→findings→draft
  estimate, Claude+fallback, never auto-bills) + review UI. Added missing Recall model (caused 2 transient
  500s, fixed). 9 new pages/controllers, routes, nav. Verified all HTTP 200. Parked #20 (imaging match/
  bridge) + #21 (scribe code map/Anthropic+Whisper wiring). Committed 7ade322. ALL PHASES 1-6 DONE.
  Next: Phase 7 audit + remediation.
