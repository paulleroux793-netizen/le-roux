# Ivory — Session Report (autonomous improvement run)

**For:** Paul le Roux **Generated:** 2026-06-06 (run spanned ~12:25–19:25)
**Scope:** What the autonomous loop built, fixed, hardened, and prepared. Everything
is **reversible via git** unless noted. Nothing was applied to real patient/financial
data — all data-cleanup work is read-only or dry-run, awaiting your decisions.

---

## 1. How to access Ivory (to review)

- **URL (Tailscale):** http://100.73.38.21:3000  — you must be on the practice Tailscale network.
- **Login:** username `reception`, password `Jbxs8sMFEmWNLs`
- The app runs on the practice rig (RTX-5090 box) in Docker. The WhatsApp number
  +27 83 710 9131 is wired live into the Ivory diary.

> ⚠️ **Infra note:** the rig's Tailscale link flapped badly from ~14:18 on 2026-06-06
> (dropping every couple of minutes). The **app itself is healthy** — it answers when
> the link is up — but the network link needs a look.

---

## 2. Features shipped (all reversible via git)

| # | Feature | Where | What it does |
|---|---------|-------|--------------|
| 1 | **Lab-case tracking** | migration `20260606123801`, `treatment_items_controller`, `pages_controller` (dashboard `lab_cases_due`), `Dashboard.jsx`, `CourseOfTreatmentShow.jsx` (LabControl) | Flag a crown/bridge/denture item "out at the lab" with a due-back date; dashboard "Lab cases due back" list (overdue highlighted); "Send to lab" / "Returned" on the treatment plan. |
| 2 | **Billing-settings edit form** | `settings_controller#update_billing`, route `settings/billing`, `Settings.jsx` (Billing Card) | Reception can edit HPCSA, BHF/practice no, VAT, company reg, practitioner HPCSA, and banking — the details printed on every invoice/statement/claim — without the rails console. |
| 3 | **Medical-aid dependant code on PDFs** | `document_pdf.rb`, `statement_pdf.rb` | Invoices + statements now print "Member X · Dependant YY" (read from the per-patient scheme join) so a self-submitted claim attributes to the right beneficiary. |
| 4 | **Practice-hours wired into booking** | `next_available_slot_finder.rb` | The next-available-slot finder now reads the existing `DoctorSchedule` (per-weekday active/open/close/break) instead of hardcoded Mon-Fri 8-5. Edit the schedule in Settings → it flows into booking. |
| 5 | **Review-request nudge** | migration `20260606131501` (`google_review_url` on PracticeSettings), `settings_controller`, `Settings.jsx`, `patients_controller`, `PatientShow.jsx` | When a Google-review URL is set, the patient page shows a "Request review" button that opens WhatsApp pre-filled with a review link (reception sends). Coordinates with the SEO project that owns GBP. |
| 6 | **ASAP one-tap-offer** | `Dashboard.jsx` (ASAP list) | The "Wants an earlier slot" list now has a "WhatsApp offer" button (wa.me pre-filled "a slot just opened — want it?") alongside Call. |
| 7 | **Compliance-scrubber gap fixes** | `compliance_filter.rb` | Closed two gaps so the AI never sends banned phrasings: weekend-booking promises and superlative-dentist claims ("Best dentist") are rewritten; verified zero false positives on legitimate text. |

Plus a **latent bug fix**: `treatment_items_controller` referenced an undefined
`course_of_treatment_path` helper (would 500 on the no-referer fallback) — replaced
with URL strings, same fix as an earlier controller.

---

## 3. Stress-testing: 3 real bugs FIXED, 2 hardenings

**Bugs found + fixed (all would have hit real users):**

1. **Unicode/emoji name crashed all PDF generation.** A patient whose name (or an
   estimate line) contained a character outside Windows-1252 — emoji, macron (ā),
   Greek, Cyrillic — crashed invoice/estimate/statement/receipt PDFs with a 500.
   Common SA accents (é, ë, ô) were fine. **Fix:** a `winansi()` sanitiser added to
   `document_pdf.rb`, `statement_pdf.rb`, `receipt_pdf.rb` (keeps Latin-1,
   transliterates the rest to ASCII, drops the unmappable). IntakePdf was already safe.

2. **Paying a VOIDED invoice silently un-voided it.** A payment on a cancelled
   invoice flipped its status from `void` back to `part_paid`. **Fix:** guards in
   `payments_controller#create` (rejects if `invoice.void?`) and `Invoice#register_payment!`.

3. **Accepting a ZERO-LINE estimate made an empty R0 invoice** (burning a sequence
   number). **Fix:** `estimates#accept_and_invoice` now rejects an empty estimate.

**Hardenings (defense-in-depth):**

- `Invoice#register_payment!` ignores non-positive amounts (so a stray/negative call
  can't drive a balance negative).
- `procedure_codes#bulk_update` (the bulk fee-uplift) is now bounded to **-90%…100%** —
  it writes every fee immediately with no preview, so a fat-finger like "600" would
  have ×7'd the whole live fee schedule, and a value below -100% would have made fees
  negative. Verified out-of-range is rejected with the fee total unchanged.

**Verified solid (no change needed):** double-booking blocked even under a 2-thread
concurrency test, end<start blocked, public-host → 401 (no PHI exposure), sparse +
120-line PDFs, malformed controller params (no 500s), audit-log doesn't write false
success rows, search with special characters, payments summing, blank-phone & past
reminders graceful, intake empty-submit → 422 (no junk), WhatsApp + voice webhooks
reject unsigned/forged requests (403, signature validation).

---

## 4. Three decisions waiting on you (design-notes, not bugs)

1. **Overpayment → credit.** Paying more than an invoice's total leaves a negative
   balance, which is correctly a patient *credit*. Decide: surface it clearly as
   "credit" in the UI?
2. **Double-click "Generate invoice" → 2 invoices** ("latest wins", by design for
   re-invoicing). Decide: make it idempotent (redirect if the COT already has a
   non-void invoice)?
3. **Appointment overlap guard is app-level.** It held under a concurrency test, but
   for true-concurrency safety a Postgres `EXCLUDE` constraint (needs `btree_gist`)
   would guarantee it. Low risk on the current single-worker setup.

---

## 5. Data-cleanup — all 5 items addressed (read-only / dry-run, NOTHING applied)

Scripts + reports live in **`script/data-cleanup/`** (see README there for the safe
protocol: dry-run default, `APPLY=1` env-gated, backup-first, rollback note,
never auto-run).

- **#2 VAT backfill → documented-moot.** Line `vat_cents` is 0 on ~20,729 of 20,753
  historical (imported) invoice lines, but the practice prices VAT-*inclusive* so
  per-line VAT is derivable (`line_total × 15 ÷ 115`) and the invoice-level total is
  what shows on documents. A 20k-line backfill would be a large, risky mutation of a
  probably-unused field — **don't backfill** unless an accountant says per-line VAT is
  required on historical invoices.
- **#3 Ambiguous phones → report (`ambiguous_phones.rb`, read-only).** Of 1,868
  patients with a phone, 10 don't match +27XXXXXXXXX: **3 are legit foreign** (Arnold
  +64 NZ, Lochner +31 NL, Taylor +64 NZ — leave alone) and **7 SA numbers have an
  extra digit** (Hlatshwayo, Jonker, Maritz, Peyper, Steyn, Mphepo, Gouws) → reception
  fixes each by hand against the real number (auto-fixing could write a *wrong* number).
- **#5 Zero-total estimate → dry-run script (`zero_total_estimate.rb`).** One real
  candidate: estimate #31 (Lance Van Vuuuren, empty 2022 draft). `APPLY=1` would delete
  only old/empty/draft/non-demo estimates.
- **#4 Morne Maartens merge → inspected (read-only).** #1191 is canonical (account
  M0186, phone, 3 invoices + 1 estimate); **#1 is an empty duplicate** (no activity) →
  unlink + delete after **you confirm the correct SA ID** (the two records differ in
  the last 3 digits: ...085 vs ...008). #1193 Ilze-Mari is a different person. Surprise:
  **#2439 is not a Maartens record** — it's "LEON CLARK - KONTAK HOM VIR NUWE AFSPRAAK",
  an Elixir import where the *name field holds an instruction* (2 appointments) — a
  separate fix.
- **#1 The R87,638 in credits → needs YOUR decision** (write-off? carry as credit?
  refund?) before any script can be written.

---

## 6. Bottom line

Seven features shipped, three real bugs fixed, two financial-safety hardenings, and a
complete data-cleanup toolkit — all reversible, all documented. Two data decisions
(the credits, the Morne canonical ID) and three design questions are waiting on you.
The only operational concern is the **rig's Tailscale link flapping**.
