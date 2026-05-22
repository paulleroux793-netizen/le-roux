# Ivory — Whole-System Stress Test & Audit (Phase 7)

> Audit of the complete Ivory practice-management build (Phases 1-6) on branch
> `feat/practice-management-system`. Severity: 🔴 high · 🟡 medium · 🟢 low/info.
> **Fixed** items were implemented + re-verified this phase; **Deferred** need Paul or a larger task.
> Compiled 2026-05-22.

## Summary
The build is sound, fully additive, and not deployed. No live behaviour (patients, appointments,
conversations, bookings, calendar, WhatsApp) was modified. Auth, PII handling, money correctness, and
clinical immutability are in good shape. This phase fixed 4 concrete issues and catalogued the rest as
decisions for Paul.

## A. Security & POPIA
- 🟢 **Auth** — all new PMS controllers inherit `ApplicationController`'s HTTP-basic gate, so the new
  routes are protected exactly like the rest of the dashboard. No public PII exposure. ✅ (no change needed)
- 🟢 **PII not committed** — `patients.csv` and `sidexis_manifest.csv` (real names/IDs) are gitignored;
  only non-PII CSVs (macros, procedure codes) are tracked. gitleaks pre-commit hook passes on every commit. ✅
- 🟡 **No per-user roles yet** — single shared dashboard password (matches existing app). Per-user
  reception/dentist roles + audit attribution on mutating PMS actions → **Deferred** (UNCERTAINTIES #6).
- 🟢 **Imaging originals stay on-prem** by design (POPIA); only metadata + match status in the app. ✅

## B. Data integrity
- 🟡→✅ **FK on-delete ordering (#19)** — destroying a patient cascades to documents/estimates/COTs while
  form_submissions/notepad_pages/scribe_sessions reference them; default RESTRICT FKs could crash.
  **FIXED**: migration `…000009` sets those cross-child FKs to `on_delete: :nullify`. Verified
  `patient.destroy!` now succeeds.
- 🟢 **Immutability** — signed clinical notes lock (corrections supersede); invoices are void-not-edit;
  fees/VAT are snapshotted at charting/invoicing so later price changes never rewrite history. ✅
- 🟢 **Sequential invoice numbering** — atomic row-locked `DocumentSequence`, gap-free. ✅

## C. Correctness
- 🟡→✅ **Scribe proposed non-existent codes (#21)** — fallback mapped "filling"→8341, absent from the
  172-code catalogue. **FIXED**: the extractor now only attaches a code that exists; otherwise the
  finding is surfaced with `needs_code: true` for the dentist to select (never guesses a billable code).
  Verified. *(Remaining: wire the real Anthropic call + on-PC Whisper — Deferred #21.)*
- 🟡 **Imaging patient-matching (#20)** — conservative exact-name/account-code match; everything else
  queued `needs_match`. Correct + safe; needs a one-click manual-link UI + the on-prem bridge install. **Deferred.**
- 🟡 **VAT treatment (#17)** — implemented VAT-inclusive; whether the practice is VAT-registered at all
  is unconfirmed. **Deferred** (decision).

## D. Performance
- 🟡→✅ **N+1 on Imaging index** (patient per row, up to 400) — **FIXED** with `includes(:patient)`.
- 🟡→✅ **N+1 on Courses list** (`estimated_total` ran a SUM per row) — **FIXED**: computed from the
  already-loaded items in Ruby.
- 🟢 Other index pages already eager-load or use aggregates. The 654-row imaging list is capped/paged
  (200 shown). ✅

## E. Additive-safety (the headline guarantee)
- 🟢 Zero live tables altered; the live `patients` table is untouched (associations added via the
  `PracticeManagementPatient` concern). New routes are namespaced/standalone; existing routes, the
  existing `PatientShow`, and all webhook/booking/calendar flows are unchanged. Nothing deployed. ✅

## F. Gaps vs the proposal (intentionally deferred — need Paul or a larger task)
- Binary file storage backend (uploads/scan images/signed-PDF bytes) — #18.
- WhatsApp **delivery** of forms/estimates/statements/recalls (outbound jobs) + the patient-facing
  mobile form UI + the notepad drawing canvas. Engines exist; delivery/UX is integration work.
- Real patient import (1,690 patients) — gated on the identity decision (#13).
- SIDEXIS on-prem bridge agent (manifest + thumbnails + keep CBCT local) — #8/#20.
- Localising new nav/pages to Afrikaans — #15.

## Fixes implemented this phase
1. FK `on_delete: :nullify` migration (#19) — patient-delete safe.
2. Scribe: surface `needs_code` instead of proposing a missing billable code (#21).
3. Imaging index N+1 → `includes(:patient)`.
4. Courses list N+1 → compute total from loaded items.

## Verdict
Ivory is a coherent, additive, reviewable system at parity-or-ahead of GoodX/Exact for this practice
(see the comparison scorecard). The remaining items are deliberate decisions for Paul (billing
registration details, VAT status, patient-identity import strategy, storage backend, and the on-prem
SIDEXIS + Whisper installs) — none are blockers to reviewing the system, and none touch production.
