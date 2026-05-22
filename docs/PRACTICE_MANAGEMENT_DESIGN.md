# Practice Management System — Design Blueprint

> Custom invoicing / billing / estimates / treatment-tracking for Dr Chalita le Roux Inc,
> modelled on **GoodX** (SA revenue-cycle leader) and **ExACT / EXACT** (clinical charting +
> course-of-treatment planning), then simplified and improved for a single practice.
>
> Source research: [research/goodx-architecture.md](research/goodx-architecture.md),
> [research/exact-architecture.md](research/exact-architecture.md),
> [research/SA-dental-billing-ecosystem.md](research/SA-dental-billing-ecosystem.md). Compiled 2026-05-22.

## 1. The one big idea (the "spine")

Both GoodX and Exact succeed because **everything links to one chain** — no data entered twice:

```
Patient ──┐
          ├─ belongs to ─ Family / Billing Account ── (who pays)
          └─ covered by ─ Scheme Membership ───────── (main member + dependant code)
                                   │
                          Course of Treatment (COT)   ◄── THE BRIDGE: clinical ↔ money
                                   │   (carries payor + authorisation)
                          Treatment Items  (tooth, surface, procedure code, planned→completed)
                                   │   when ticked "completed"
                          Invoice Lines  (billed / patient portion / scheme portion)
                                   │
                          Claim ─► Switch ─► Remittance ─► Statement
```

**The Course of Treatment is the single most important entity.** It is the hinge that connects
"what the dentist did" (charting) to "what gets billed" (invoice). Copy this; it's why their
systems feel seamless instead of like two disconnected apps.

## 2. Core data model (entities & how they connect)

Adapted from Exact's reference schema ([research/exact-architecture.md](research/exact-architecture.md) §5.2),
expressed for our Rails/Postgres stack. We already have `patients`, `appointments`, `conversations` —
this extends them.

| Entity | Purpose | Key links |
|---|---|---|
| **Patient** | the clinical person | → Family, → Scheme Memberships |
| **Family / BillingAccount** | the unit that *pays* | has a head/guarantor patient |
| **Scheme** | a medical aid (Discovery, Bonitas…) | — |
| **SchemeMembership** | the contract: main member + plan/option + member no. | → Scheme, → main-member Patient |
| **MembershipDependant** | links a patient to a membership w/ dependant code | → Membership, → Patient |
| **Service** | a billable procedure (catalogue) | SADA code, ICD hints, tooth-specific flag |
| **FeeSchedule / FeeScheduleItem** | price of each Service per scheme/plan/year | AllowedAmount, PracticeFee |
| **CourseOfTreatment** | episode of care; carries payor + auth no. | → Patient, → SchemeMembership |
| **TreatmentItem** | one planned/done procedure | tooth, surface, planned→completed, → Service |
| **Estimate** | patient-facing quote / scheme pre-auth request | → COT, → TreatmentItems |
| **Invoice / InvoiceLine** | the bill; line traces back to a TreatmentItem | PatientPortion, PayorPortion |
| **Claim / ClaimLine** | EDI submission to a scheme | → InvoiceLines |
| **Remittance / RemittanceLine** | scheme's response (paid/short/denied) | → ClaimLines |
| **Payment / Adjustment** | money in / corrections (never overwrite history) | → Invoice, → Account |

**Golden rule from GoodX:** corrections are *new ledger entries*, never edits-in-place. To fix a
claim you **Reverse → Redo → Resubmit → Resolve** ("the 4 R's"). This preserves an audit trail —
essential for medical-aid disputes and POPIA.

## 3. The dual-liability split (the SA-specific heart of billing)

Every invoice line splits into **PayorPortion** (medical aid) + **PatientPortion** (co-pay / shortfall).
This is the thing generic foreign systems get wrong and GoodX gets right. Drivers:

- **Balance billing**: practice fee may exceed scheme tariff → patient owes the difference (OOP).
- **Private flag**: tick "private" → whole line/invoice is patient-liable, never sent to scheme.
- **PMB flag**: scheme *must* cover in full (e.g. acute abscess emergency).
- **Cosmetic exclusion**: whitening / cosmetic veneers → always 100% patient (ties to our existing
  whitening-quote flow in `PRACTICE_CONFIG_DRAFT.md` §5).

## 4. SA coding layer (what the Service catalogue must hold)

- **SADA procedure codes** — 4-digit, hierarchical: `81xx` exams/diagnostics (8101 oral exam,
  8104 limited exam, 8112 bitewing), `82xx` extractions (8201), `83xx` restorative (8341 amalgam 1-surface).
- **Modifiers**: `8025` handling fee (direct materials), `PLUS M` materials, `PLUS L` lab / `8099`
  lab fee, `9099` unlisted procedure.
- **Frequency & age limits** per code per benefit year (e.g. 8201 max 4 extractions/yr; fluoride
  8161 ages 3–11, 8162 ages 12–16) → the catalogue must store these so we can warn before claiming.
- **ICD-10 diagnosis** (mandatory on claims): K-codes dominate (K02 caries, K04 pulp/periapical,
  K05 gingivitis/periodontitis); `Z01.2` = dental exam with no diagnosis. **No fixed procedure→diagnosis
  mapping** — suggest, don't force. Mismatch = the #1 rejection cause, so add a soft validation flag.

## 5. End-to-end flow (the picture)

1. **Arrive / book** — appointment already exists (we have this). Validate scheme membership is active.
2. **Examine & plan** — dentist charts findings on a tooth chart; adds TreatmentItems to a Course of
   Treatment, each with a Service code, tooth, surface. System prices each via the right FeeSchedule.
3. **Estimate** — generate a patient quote (cost split shown) and/or a scheme pre-authorisation request.
   Patient accepts → estimate is locked.
4. **Treat** — dentist ticks items **Completed**. *That tick* moves them onto an Invoice (charting→billing).
5. **Invoice** — lines split into patient vs scheme portions. Patient co-pay can be collected at checkout.
6. **Claim** — scheme portion submitted electronically via a switch; response tracked.
7. **Remittance & statement** — scheme pays/short-pays/denies; payment matched to the line; residual
   becomes patient balance; statement runs per Family account. Rejections handled via the 4 R's.

## 6. What to copy vs. where to improve

**Copy (don't reinvent):**
- Course-of-Treatment-centric model (Exact). The clinical↔billing bridge.
- Dual-liability invoice lines + the 4 R's audit discipline (GoodX).
- Fee-schedule-per-scheme/year with importable tariffs (ExACT SA).
- Tooth-chart / odontogram as the planning surface (EXACT SOE).

**Improve / simplify for one practice:**
- **WhatsApp-native**: estimates, deposit requests, statements and reminders go out over our existing
  Twilio WhatsApp line — GoodX/Exact bolt SMS/email on; for us it's the primary channel.
- **AI-assisted coding**: suggest ICD-10 from the clinical note (Claude) instead of manual lookup.
- **No multi-site / multi-tenant complexity** — single practice = a far simpler, faster system.
- **One source of operational truth** already exists in `PRACTICE_CONFIG_DRAFT.md` (pricing, whitening,
  banking) — fee schedules seed from there.

## 7. Build sequencing (fits the existing patient-records plan)

Aligns with the already-approved patient-records plan (accounts-first, after WhatsApp go-live settles):

1. **Accounts & people**: Patient ↔ Family ↔ SchemeMembership/Dependant (import from
   `Patient Demographics.XLS`, 2200 rows).
2. **Service catalogue + Fee schedules** (SADA codes, private fees from PRACTICE_CONFIG).
3. **Course of Treatment + Treatment Items + tooth chart** (planning & charting).
4. **Estimates** (patient quote + WhatsApp send).
5. **Invoicing** (dual-liability lines, payments).
6. **Claims / remittances / statements** (last — needs a switch integration).

> Built on the Rails dashboard that already exists; each module is a set of models + Inertia pages,
> developed locally via `docker compose up` and shipped to Railway when proven.
