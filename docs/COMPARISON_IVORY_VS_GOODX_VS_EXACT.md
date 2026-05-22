# Ivory vs GoodX vs Exact — Feature Comparison

> **Ivory** is the working name for Dr Chalita le Roux Inc's own practice-management system
> (rename freely — see build UNCERTAINTIES #16). This is the review scorecard: how our purpose-built
> system compares to the two incumbents it's modelled on. Legend: ✅ full · 🟡 partial/planned ·
> ⬜ not built yet · ➖ deliberately out of scope · ⭐ where Ivory goes *beyond* both.
>
> Status as of the autonomous build (updated each phase). See BUILD_LOG.md for live progress.

## Why Ivory exists
GoodX = the SA revenue-cycle/billing leader. Exact = the clinical-charting/treatment-planning leader.
Ivory copies the best of both, **drops the medical-aid claims engine** (this practice doesn't claim —
patients self-claim), and **adds three things neither has**: WhatsApp-native digital forms, a fully
digital patient file replacing paper, and an AI chair-side scribe that drafts estimates live.

## Scorecard

| Capability | GoodX | Exact | **Ivory** | Notes |
|---|:--:|:--:|:--:|---|
| **Patient + family/account model** | ✅ | ✅ | ✅ | Billing account ↔ patients via join; account codes (M0001…). Phase 1 ✅ |
| **Medical-scheme + dependant data** | ✅ | ✅ | ✅ | Reference-only (we don't submit) — printed on self-claim statement. Phase 1 ✅ |
| **Procedure-code catalogue (SADA)** | ✅ | ✅ | ✅ | 172 codes, **priced from a real year of your charges**. Phase 1 ✅ |
| **Treatment macros / bundles** | ✅ | ✅ | ✅ | Your 20 GoodX macros imported (BRIDGE 3 → its lines). Phase 1 ✅ |
| **Fee schedules** | ✅ | ✅ | ✅ | PRIVATE 2026 list built from real fees. Phase 1 ✅ |
| **Tooth charting / odontogram** | ✅ | ✅ (best) | ✅ | FDI odontogram component + colour-coded conditions. Phase 2 ✅ |
| **Course-of-treatment planning** | ✅ | ✅ | ✅ | The clinical↔billing bridge; carries setting + auth. Phase 2 ✅ |
| **In-chair / hospital / sedation setting** | ✅ | 🟡 | ✅ | Matches your real billing (LocationCode/Theatre). Phase 2 ✅ |
| **Clinical SOAP notes (immutable)** | ✅ | ✅ | ✅ | Append-only; signed notes lock, corrections supersede (HPCSA). Phase 2 ✅ |
| **Estimates / quotations** | ✅ | ✅ | ⬜ | Phase 3 |
| **Invoicing** | ✅ | ✅ | ⬜ | Phase 3 — 16-element compliant invoice |
| **Medical-aid claim submission (EDI)** | ✅ | 🟡 | ➖ | **Deliberately omitted** — we don't claim. Big simplification. |
| **Self-claim statement (patient claims back)** | 🟡 | 🟡 | ⬜ | ⭐ First-class for us, not an afterthought. Phase 3 |
| **VAT logic (zero-rated vs cosmetic 15%)** | ✅ | 🟡 | 🟡 | Per-code VAT in catalogue; full logic Phase 3 |
| **Payments (card/cash/EFT + deposits)** | ✅ | ✅ | ⬜ | Phase 3 — incl. whitening R2,000 deposit |
| **Debtors / statements / age analysis** | ✅ | ✅ | ⬜ | Phase 3 |
| **Digital patient file (paperless)** | 🟡 | 🟡 | ⬜ | ⭐ Replaces the 5 physical files. Phase 4 |
| **WhatsApp digital forms + e-signature** | ⬜ | ⬜ | ⬜ | ⭐⭐ Neither incumbent does this. Phase 4 |
| **Digital notepad / annotate on forms** | ⬜ | 🟡 | ⬜ | ⭐ Phase 4 |
| **Imaging integration (X-ray/scan)** | ✅ | ✅ | ⬜ | SIDEXIS bridge. Phase 5 |
| **Recalls (6-month) + reminders** | ✅ | ✅ (best) | ⬜ | Phase 5 |
| **Reporting / KPIs** | ✅ | ✅ | ⬜ | Phase 5 |
| **AI chair-side scribe → draft estimate** | ⬜ | ⬜ | ⬜ | ⭐⭐⭐ The headline. Neither has it. Phase 6 |
| **WhatsApp booking AI receptionist** | ⬜ | ⬜ | ✅ | ⭐ Already live (the existing system this extends) |
| **Immutable audit trail** | ✅ | ✅ | ✅ | Reuses existing AuditLog + append-only clinical/financial records |
| **Multi-site / multi-tenant** | ✅ | ✅ | ➖ | Single practice — deliberately simpler & faster |
| **Per-seat licence cost** | 💰 | 💰 | ✅ free | ⭐ Owned, not rented |

## The headline differences (where Ivory wins)
1. **WhatsApp-native** — forms, estimates, statements, reminders over the line patients already use.
2. **AI chair-side scribe** — Dr Chalita charts by talking; the system drafts the plan + estimate to review.
3. **Truly paperless** — the digital file + notepad retire the 5 physical files per patient.
4. **Built for self-pay** — no claims engine to maintain; the statement the patient submits is first-class.
5. **Owned** — no monthly per-dentist fee; tuned exactly to this practice's real codes, macros, and fees.

## Where the incumbents still lead (honest)
- **Exact** has the most mature odontogram and recall engine — Ivory matches the model; UI polish is ongoing.
- **GoodX** has battle-tested medical-aid claiming — but that's exactly what we don't need.
- Both are proven at scale across thousands of practices; Ivory is new and purpose-built for one.

## How to review
Open `localhost:3000` (run `docker compose up` in `le-roux-repo`). The **Practice** group in the
sidebar shows what's built so far (Accounts, Procedure Codes, Treatment Macros). Tick down this
scorecard against GoodX/Exact as the remaining phases land.
