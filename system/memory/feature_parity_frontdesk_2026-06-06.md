# Front-desk feature parity vs modern dental PMS (Perplexity, 2026-06-06)

Benchmarked Ivory against the 8 highest-impact front-desk/scheduling features in Curve,
Dentrix Ascend, Open Dental, tab32, Archy. Status: ✅ have · 🟡 partial · 🔴 gap.
Purpose: answer Paul's "make sure it has all the functions" — and flag what's worth building.

| # | Market feature | Ivory status | Notes |
|---|----------------|--------------|-------|
| 1 | Multi-touch automated reminders + status (confirmed/at-risk) | 🟡 partial | Ivory sends WhatsApp reminders; MISSING: timed multi-step sequences (7d/3d/1d) + an "unconfirmed / at-risk today" view on the schedule. |
| 2 | Online self-scheduling (live availability, rules) | ✅ have (different shape) | The WhatsApp AI receptionist books into the live diary with the practice hours/rules — arguably better for this practice than a web booker. |
| 3 | Automated waitlist auto-fill on cancellation | 🟡 partial | Dashboard ASAP waitlist + one-tap "WhatsApp offer" exists; MISSING: auto-text the whole matching waitlist when a slot opens (first-to-confirm). |
| 4 | Recall/reactivation campaigns w/ workflow + metrics | 🟡 partial | Recalls list exists (work-the-list); MISSING: automated reactivation sequences + pipeline metrics (sent/responded/booked). |
| 5 | 2-way texting tied to appointments + quick-reply templates | 🟡 partial | WhatsApp conversations + central handling exist; MISSING: canned quick-reply templates (confirm/reschedule/forms/payment-link) in the reply box. |
| 6 | Digital pre-registration + mobile self check-in | 🟡 partial | Pre-registration via tokenised intake link ✅; MISSING: patient day-of "I'm here" self check-in that flips arrival status. |
| 7 | Fast checkout: estimate + saved card / text-to-pay | 🟡 partial | Estimates + invoice + payment recording ✅; MISSING: card-on-file / text-to-pay (needs a payment-provider integration — strategic, not a quick build). |
| 8 | Front-desk analytics (no-show%, confirm%, utilisation) | 🟡 partial | Reporting has no-show rate + aged debt + production; MISSING: confirmation rate, filled-vs-unfilled cancellations, chair/operatory utilisation. |

## Verdict
Ivory is **not missing whole categories** — it has booking (via WhatsApp AI), reminders,
a waitlist, recalls, intake, estimates/invoices/payments, and reporting. The gaps are the
**"automated + measured" layer** on top: sequences, auto-fill, templates, self check-in,
and metrics. None are categories Ivory lacks entirely; they're depth upgrades.

## Candidate builds (for Paul's steer — some need a decision, not just code)
- 🟢 SMALL/safe (loop can build): quick-reply templates in the WhatsApp reply box (#5);
  a "confirmation status" chip + an "unconfirmed today" dashboard list (#1, needs a small
  status field); recall pipeline counts on the recalls page (#4).
- 🟡 MEDIUM: waitlist "offer to all matching" auto-text (#3); patient "I'm here" self
  check-in page (#6) — patient-facing, light.
- 🔴 STRATEGIC (Paul decision — cost/integration): card-on-file / text-to-pay (#7, payment
  provider); full automated reminder/recall sequences w/ analytics (#1/#4/#8).

These are noted as questions for Paul (kept aside per tonight's directive). The loop will
keep shipping the 🟢 small flow wins.

---

## Part 2 — Clinical charting + treatment-plan presentation / case acceptance (Perplexity, cycle 16)

Benchmarked vs Dentrix, Open Dental, Curve, Pearl, Overjet. Status: ✅ have · 🟡 partial · 🔴 gap.

| # | Market feature | Ivory status | Notes |
|---|----------------|--------------|-------|
| 1 | Templated/tooth-chart charting (shortcuts, surface picking) | ✅ have | Odontogram (tooth-first) + AddProcedureModal (whole-mouth, keyboard) + macros/visit-bundles + predictive suggestions. Strong. |
| 2 | Voice / hands-free charting | 🟡 partial | Token-protected chairside scribe daemon → draft notes exists; true live voice-charting is a gap (evolving). |
| 3 | Real-time insurance + out-of-pocket in the plan | 🟡 N/A by design | Practice is patient-pay (does not bill medical aid); estimate already shows medical/self split. Live eligibility is out of scope. |
| 4 | Patient-friendly visual plan (tooth chart + plain language), print/email | ✅ mostly | EstimateShow "Patient view" (plain language, no codes) + PDF download/print + WhatsApp send. Could add a tooth-chart picture to the patient PDF (minor). |
| 5 | Colour-coded image overlays for patient education | 🔴 gap (strategic) | AI radiology — out of tonight's scope; imaging links (SIDEXIS) planned. Paul decision. |
| 6 | "Good/better/best" alternative + phased plans | 🔴 gap | Ivory has single multi-visit estimates; no good/better/best alternatives model. Genuine product gap — medium build, Paul steer. |
| 7 | "Accepted-but-unscheduled treatment" follow-up worklist | 🔴 gap (HIGH VALUE) | No list of planned (not-yet-done) treatment for patients with NO future appointment = lost production. BUILDABLE: a dashboard/worklist querying TreatmentItem status=planned where the patient has no upcoming appointment. Strong revenue-recovery flow win. |

### Verdict (charting/case-acceptance)
Charting + patient-friendly presentation are largely **there**. The two real gaps worth Paul's
steer: **good/better/best alternative plans** (#6, medium) and an **unscheduled-treatment
worklist** (#7, HIGH VALUE + buildable — the single best revenue-flow addition found). Voice
charting (#2) and AI overlays (#5) are strategic/evolving. The loop may build a first version of
#7 (read-only worklist) if safe; #6 + #5 need Paul's decision.
