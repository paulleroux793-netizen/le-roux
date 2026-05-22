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
- [ ] P1.1 Migrations: billing_accounts, account_patients, medical_schemes, scheme_memberships, scheme_membership_patients
- [ ] P1.2 Migrations: procedure_codes, treatment_macros, treatment_macro_items, fee_schedules, fee_schedule_items
- [ ] P1.3 Models + associations (additive on Patient via link tables; Patient itself untouched)
- [ ] P1.4 Seeds: procedure codes from PRACTICE_CONFIG + transaction history; import Dental Macro's.xlsx
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
**Phase 1, step P1.1 — writing the accounts + schemes migrations.** Next: P1.2 catalogue + macros migrations, then P1.3 models, then migrate in Docker.

## Session entries
- **2026-05-22 ~17:10** — Set up branch `feat/practice-management-system` (based on calendar branch — see UNCERTAINTIES #1), wrote BUILD_LOG + UNCERTAINTIES, studied existing schema/controllers/Inertia conventions. Beginning Phase 1 migrations.
