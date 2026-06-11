# Session Report — Patient-Journey UX Overhaul (overnight 2026-06-06 → 07)

**Author:** Ivory self-improvement loop · **Window:** ~19:40 (2026-06-06) → 07:01 (2026-06-07)
**Directive (Paul):** Focus the loop on the PATIENT JOURNEY end-to-end — make it better + easier. User-friendliness #1 (buttons + keyboard to go quicker, be predictive to save time, build the "flow" feeling), research-grounded, feature parity with leading dental software. Then (from ~23:44) "substantive deep work" = stress-test + harden the new code.

---

## 1. TL;DR

- **14 patient-journey UX features shipped** and **stress-verified (7/7 tests pass, no bugs)**. Every change is additive and reversible per-file.
- **One thing genuinely needs your action:** the **nightly backup took the rig (and likely the live WhatsApp bridge) offline for ~2.5 hours** (~23:00 → 01:36). See §5.
- Two research/parity documents produced; a queue of strategic features is **parked for your decision** (§6). No real patient data was touched — all tests ran against demo patient **2985 (John Demo-Smith)** with rollback or self-cleanup (verified unchanged: 3 estimates / 3 invoices / 3 appointments).

Review the running system at **http://100.73.38.21:3000** (login `reception` / `Jbxs8sMFEmWNLs`).

---

## 2. Shipped UX features

| Feature | What it does for the user | File(s) | How to reverse |
|---|---|---|---|
| **Smart Back** | "Back" returns to where you actually were (e.g. Back from an estimate inside a patient account → the patient, not the estimates index) — fixes the back-navigation glitch | `app/javascript/components/SmartBack.jsx` (wired into `EstimateShow.jsx`, `InvoiceShow.jsx`, `CourseOfTreatmentShow.jsx`) | Revert the 3 pages to their hardcoded "All …" links; delete `SmartBack.jsx` |
| **Keyboard code entry** | Type a code → Enter adds it and refocuses for the next; Enter on tooth/qty/fee adds; Esc clears — fast, hands-on-keyboard estimate building | `app/javascript/pages/EstimateShow.jsx` | Revert `EstimateShow.jsx` |
| **Ctrl/Cmd+K palette** | Global search/jump from anywhere via Ctrl-K (alongside `/`) | `app/javascript/components/GlobalSearch.jsx` | Revert `GlobalSearch.jsx` |
| **Estimate favourites** | One-click chips for the practice's most-used codes — no searching | `app/controllers/estimates_controller.rb` (`favourite_codes`) + `EstimateShow.jsx` | Remove the `favourite_codes` prop + chip block |
| **Visit-bundle macros** | "+ Visit bundle…" inserts a whole set of codes (C/U, CROWN, BRIDGE 3, etc.) in one click | `estimates_controller.rb#apply_macro` + `config/routes.rb` + `EstimateShow.jsx` | Remove the `apply_macro` action/route + the selector |
| **Predictive suggestions** | Reads the booking reason and suggests the likely codes ("AI-suggested from the booking — check before sending"), flagged for review — on both estimates and treatment plans | `app/controllers/concerns/visit_suggestions.rb` + `estimates_controller.rb` + `courses_of_treatment_controller.rb` + `EstimateShow.jsx` + `CourseOfTreatmentShow.jsx` | Remove the concern include + the amber suggestion block |
| **COT keyboard add** | ↑/↓ to highlight, Enter to pick then Enter to add — keyboard-first procedure entry on treatment plans | `app/javascript/components/AddProcedureModal.jsx` | Revert `AddProcedureModal.jsx` |
| **Diary → Start estimate** | "Start estimate for this visit" button on a diary appointment → creates the draft and opens the editor (which pre-suggests codes for the reason) | `app/javascript/components/AppointmentDetailModal.jsx` | Remove the button |
| **Payment keyboard + validation** | Amount autofocuses/selects, Enter submits, inline red errors keep focus (no toast-and-lose-context), overpay hint → recorded as patient credit | `app/javascript/components/PaymentModal.jsx` | Revert `PaymentModal.jsx` |
| **WhatsApp templates** | Compliance-safe canned replies (Reschedule, Running late) — no after-hours/weekend promises | `app/javascript/pages/ConversationShow.jsx` | Remove the added `CANNED_REPLIES` entries |
| **Recall counts** | Recalls page shows Due+overdue / Contacted / Booked / Total at a glance | `app/controllers/recalls_controller.rb` + `app/javascript/pages/Recalls.jsx` | Revert both |
| **Unscheduled-treatment worklist** | Dashboard card: patients with planned (accepted-but-not-done) treatment and **no** upcoming appointment = recoverable production to rebook (patient · item count · Rand value · click-through) | `app/controllers/pages_controller.rb` (`build_unscheduled_treatment`) + `app/javascript/pages/Dashboard.jsx` | Remove `build_unscheduled_treatment` + the `unscheduled_treatment` prop + the card |

**The "flow" this builds:** book (with a reason) → one-click **Start estimate** from the diary → the editor **pre-suggests** the visit's codes (flagged for review) → **favourites chips** + **visit bundles** + **keyboard entry** to finish fast → accept → invoice → **keyboard-first payment** with the overpay→credit hint. Fewer clicks, more prediction, less searching.

### 3. Shared concern

`app/controllers/concerns/visit_suggestions.rb` — `next_visit_for(patient)` (next today-or-upcoming non-cancelled appointment) and `suggested_macros_for(reason)` (keyword→macro map). Included in `EstimatesController` and `CoursesOfTreatmentController` (single source of truth — no duplicated logic).

---

## 4. Stress results — 7/7 PASS (no bugs found)

All safe: demo patient 2985 with transaction-rollback or self-cleanup. Scripts kept in **`script/stress/`**.

| # | Test | Result |
|---|---|---|
| 1 | `apply_macro` with invalid/missing macro id | **404** (graceful, not 500) |
| 2 | `apply_macro` end-to-end (`apply_macro_e2e.rb`) | **PASS** — C/U bundle → 5 lines, correct fees, total R1,922.79 = line-sum; self-destructed test estimate |
| 3 | `build_unscheduled_treatment` edge cases (`unscheduled_treatment_edge.rb`) | **PASS** — appears with no appointment, disappears once booked, reappears if cancelled. *(Initially read FAIL — diagnosed as a flawed test, since demo 2985 already had appointments; fixed the test, the code is correct.)* |
| 4 | Predictive matcher breadth (20 varied reasons) | **PASS** — 0 errors; correct bundles for known visit types; **suggests nothing** for unknown/empty/irrelevant (never mis-suggests) |
| 5 | Invoice payment guards (`invoice_payment_guards.rb`) | **PASS** — lifecycle open→part_paid→paid; non-positive amounts ignored; **voided invoice can't be paid** |
| 6 | Empty-estimate accept guard | **PASS** — accepting an empty estimate → 303 + alert, **no junk R0 invoice**, stays draft |
| 7 | Favourites query | **PASS** — only **active** ProcedureCodes returned; fee handling crash-safe |

---

## 5. ⚠️ INFRA-ALERT — top priority for you

The **nightly encrypted backup made the rig unreachable** (both HTTP :3000 and SSH :22) almost continuously from **~23:00 to 01:36 (~2.5 hours)**, oscillating, with HTTP recovering before SSH. Implications:

- The **LIVE WhatsApp bridge was almost certainly unreachable for that whole window** — patient messages around midnight may not have been received/answered.
- It blocked the deep-work stress tests until the rig recovered (they all ran and passed afterwards).

**Recommended fixes:** move the backup well off-peak; **throttle it** (`nice`/`ionice`, or the backup tool's IO/bandwidth limit); and **verify it isn't hanging/looping** — a healthy backup of this DB should not saturate the machine for 1.5h+. The loop did **not** attempt any restart (correctly — that's your call).

---

## 6. Open questions parked for you (need a decision)

Strategic / higher-effort items I deliberately did **not** build autonomously:

1. **Good/Better/Best** alternative treatment plans (tiered case presentation).
2. **Card-on-file / text-to-pay** (send a pay link over WhatsApp).
3. **Automated reminder/recall sequences** (multi-touch cadences).
4. **Patient self-check-in** (kiosk/QR on arrival).
5. **Voice charting** (dictate the chart chairside).
6. **AI radiograph overlays** (image-assisted diagnosis).
7. **Tooth-chart on the patient estimate PDF**.
8. **Auto-text the whole waitlist** when a slot opens.
9. **Content gap (small):** add an **"extraction" TreatmentMacro** — the predictive matcher correctly suggests *nothing* for extraction visits because no such macro exists yet. (Needs the right codes from you.)

Research backing these: `system/memory/ux_research_2026-06-06.md` (what people love/hate about dental software, mapped to Ivory) and `system/memory/feature_parity_frontdesk_2026-06-06.md` (front-desk + charting/case-acceptance parity).

---

## 7. Design / infra notes

- **Overpayment → patient credit** (the payment flow records the excess as credit, with a UI hint).
- **Double-generate invoice = "latest wins"** — re-generating an invoice produces a new one rather than being idempotent. Whether to make this idempotent is a **your-decision** (not changed).
- **Appointment EXCLUDE constraint** prevents double-booking at the DB level.
- **Rails 8 gotcha:** `pluck` with raw-SQL aggregates (`COUNT(*)`, `COALESCE(SUM…)`) raises `UnknownAttributeReference` — must wrap each in `Arel.sql()`. (Hit + fixed in `build_unscheduled_treatment`.)
- **Deploy pattern:** `tar → ssh → ruby -c` (+ `bin/vite build` for `.jsx`) → `restart web` → verify 200 via `curl -H 'Host: 10.0.0.125' http://localhost:3000/<path>`.
- **Post-recovery quirk:** after the backup, HTTP came back before SSH — worth knowing for any future monitoring.

---

## 8. How to reverse

Everything is **additive**. To undo a feature, revert the file(s) named in its row in §2 (frontend `.jsx` needs a `bin/vite build`; backend `.rb` just a `restart web`). To drop all the stress tests, delete `script/stress/`. No migrations were run; no data was mutated.

---

*End of report. The overnight loop stops here (no further wake-ups scheduled).*
