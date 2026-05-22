# Dr Chalita le Roux Inc — Digital Practice System: Full Proposal

> **The vision:** one digital system where a patient is booked, seen, charted, billed, and filed —
> with no paper, no double-entry, and an estimate in the patient's hand *before they leave the chair*.
> Built by copying what GoodX and Exact do well, removing what we don't need (medical-aid claims),
> and adding three things they don't have: WhatsApp-native forms, a fully digital patient file
> (replacing the 5 physical files), and an AI chair-side scribe that drafts estimates automatically.
>
> Compiled 2026-05-22. Research basis in [research/](research/). Grounded in real practice data:
> `Dental Macro's.xlsx`, `2025 until March 2026.xls` (a year of transactions), `Patient Demographics.XLS`
> (2,200 patients), and `PRACTICE_CONFIG_DRAFT.md`.

---

## 0. The single most important decision: we do NOT claim from medical aids

This shapes the whole system. Per `PRACTICE_CONFIG_DRAFT.md` §6:

> "We do not claim directly from medical aid. All patients pay at the practice, and we then provide a
> statement so you can claim back from your medical aid."

**Consequence:** we **delete the entire claims subsystem** that makes GoodX/Exact complex — no EDI
switch integration, no real-time medical-aid validation, no remittance reconciliation, no 4-R claim
loop. That removes the hardest, most fragile, most expensive part to build.

**But** — the invoice/statement we hand the patient must be a *perfect claimable document*, because
**the patient** submits it to their medical aid. If a field is wrong, *they* get rejected. So billing
gets simpler (no submission) but the **invoice itself must be more rigorous** (see §6 compliance).

---

## 1. The architecture spine (simplified for a non-claiming practice)

```
Patient ──┬─ pays via ──► Billing Account / Family   (who owes us money)
          └─ (optional) ─► Scheme Membership          (printed on statement so they can self-claim)
                                  │
                        Course of Treatment (COT)      ◄── the bridge: clinical ↔ money
                                  │   carries: setting (in-chair / hospital-theatre / sedation)
                        Treatment Items (tooth, surface, SADA code, planned → completed)
                                  │   tick "completed"
                        Invoice / Invoice Lines  (full patient-pay; VAT per line; SADA + ICD-10)
                                  │
                        Payment (card / cash / EFT)  ──►  Statement (claimable PDF) ──► WhatsApp
```

Compared to the earlier blueprint, **Claim / Remittance / Switch are gone.** The Scheme Membership is
kept only as *reference data printed on the statement* — never transmitted anywhere.

---

## 2. Grounding in your real data (this is "the way we do things")

From `2025 until March 2026.xls` (your GoodX export) the system already knows your real shape:

- **Account model:** `AccountHolder` + `Dependent` + `Account` no. (e.g. `M0174`), `MedicalFund` =
  "PRIVATE PATIENT" → confirms the cash model.
- **Per-line billing:** `AccessCode` (SADA tariff, e.g. 8107/8109/8110/8145), `Debits`, `Units`,
  `VAT`, `Teeth`, `DateOfService`, `Nett`.
- **Setting matters:** `LocationCode` / `ClinicName` ("Consulting rooms") — and your folders show a
  `12. Theatre`. So a Course of Treatment must carry a **setting**: *in-chair consultation*,
  *hospital chair*, *hospital/theatre*, or *sedation*. Pricing and notes differ per setting.

From `Dental Macro's.xlsx` — your **macros are exactly the bundle pattern** to copy. Example: macro
`BRIDGE 3` ("3 UNIT BRIDGE") expands to tariff lines **8447, 8145, 8443, 8398, 8109×4, 8110×2,
8107×4**. We **import this file directly** as `TreatmentMacro` records. One click charts a whole
bridge — exactly the GoodX time-saver, seeded from your own data on day one.

From `PRACTICE_CONFIG_DRAFT.md`: pricing (consult ~R850, check-up R1,900–2,600, cleaning R1,250–1,350,
aligners ~R5,000, whitening R7,800 / R2,000 deposit), Investec banking, HPCSA **DP 0118702**, scan
rules. The Service catalogue + fee schedule **seed from this file** — one source of truth.

---

## 3. The modules (what the complete system contains)

Ranked **must-have (M)** vs **later (L)** for a single private practice.

| # | Module | What it does | Priority |
|---|---|---|---|
| 1 | **Patients & Accounts** | Patient ↔ Family/Account ↔ (optional) scheme membership + dependants. Import 2,200 from `Patient Demographics.XLS`. | **M** |
| 2 | **Appointment diary** | The book we already have; add patient-in-chair status (arrived → in-chair → done). | **M** |
| 3 | **Service catalogue + Fee schedule** | SADA codes + your real codes; prices from PRACTICE_CONFIG. VAT status per code. | **M** |
| 4 | **Treatment macros** | Import `Dental Macro's.xlsx`; one-click bundle → many treatment items. | **M** |
| 5 | **Course of Treatment + tooth chart** | Odontogram; plan/chart per tooth; planned→completed. | **M** |
| 6 | **Estimates** | Patient quote with cost; **AI-drafted from chair-side scribe**; sent via WhatsApp. | **M** |
| 7 | **Invoicing & payments** | Compliant claimable invoice; card/cash/EFT; whitening R2,000 deposit. | **M** |
| 8 | **Statements & debtors** | Claimable statement PDF; age analysis; outstanding-balance follow-up via WhatsApp. | **M** |
| 9 | **Digital patient file** | Replaces the 5 physical files. Folders mirror yours (consent, referrals, before/after, scans). | **M** |
| 10 | **Digital forms over WhatsApp** | Send form link on WhatsApp → patient fills + signs on phone → lands in their file. | **M** |
| 11 | **Digital notepad / annotation** | Write/draw on forms digitally (stylus/touch) → saved as PDF to the file. No more photographing paper. | **M** |
| 12 | **SIDEXIS image link** | Pull X-rays/scans (2D, panoramic, CBCT 3D) under the right patient. | **M** |
| 13 | **AI chair-side scribe** | Whisper transcribes the consult locally → Claude extracts findings → drafts COT + estimate. | **M** (phased) |
| 14 | **Recalls & reminders** | 6-month check-up recall; appointment reminders via WhatsApp. | **L** |
| 15 | **Reporting / KPIs** | Production, collections, no-shows, outstanding, by setting/treatment. | **L** |
| 16 | **Clinical notes (SOAP)** | Structured visit notes (fed by the scribe). | **M** |
| 17 | **Users, roles & audit trail** | Reception vs dentist permissions; immutable change log (POPIA/HPCSA). | **M** |
| 18 | **Inventory / stock** | Dental materials + laser consumables; reorder. | **L** |
| 19 | **Accounting export** | Feed to the sibling "Transactions Check" / accounting. | **L** |
| 20 | **Backups + loadshedding resilience** | Offline-tolerant; automatic backups. | **M** |

**Commonly-overlooked items we are deliberately including** (research flagged these as what practices
forget): loadshedding/offline tolerance, granular reception-vs-dentist permissions, an immutable audit
trail, sequential tamper-evident invoice numbering, and per-line VAT zero-rating logic.

---

## 4. The three things that make this *better* than GoodX/Exact

### 4.1 WhatsApp-native digital forms (no paper intake)
Patient books → system sends a **form link over WhatsApp** (your existing Twilio line) → patient fills
medical history / consent **on their phone**, signs with finger → submitted form lands as a PDF in
**their patient file**, in the right folder, before they even arrive. Replaces printing + scanning.

### 4.2 Fully digital patient file + notepad (kill the 5 physical files)
Today: 5 physical files per patient, photographed at day-end and uploaded. Future: the file *is*
digital. A **notepad/annotation surface** lets Dr Chalita write or draw on forms and charts directly
(touch/stylus), saved straight to the file. Folder structure mirrors what you already use
(`Consent Forms`, `Referral Letters`, `Befores and Afters`, `Sidexis 4 Scans`, etc.).

### 4.3 AI chair-side scribe → auto-drafted estimates (the headline feature)
This is the one you most want, and you **already own the foundation** — `transcribe_calls.py` runs
Whisper locally, POPIA-safe, no audio leaving the PC. We point the same tech at the operatory:

1. Appointment marked **in-chair** → system knows *this patient is being charted now*.
2. A local mic + Whisper transcribes the consult on the practice PC (audio never leaves the building).
3. **Claude reads the transcript** + the live tooth chart → extracts "tooth 16 — deep caries, needs
   crown; tooth 36 — extraction" → maps to SADA codes/macros → **drafts a Course of Treatment +
   Estimate**.
4. Dr Chalita **reviews and adjusts** (doesn't build from scratch) → estimate handed to the patient
   **before they leave**, so they can ask their questions on the spot.

This turns "estimate after the fact" into "estimate in the chair" — the exact goal you described.

---

## 5. SIDEXIS (Dentsply Sirona) image integration — how it actually works

**The problem:** SIDEXIS 4 lives on a **Windows PC at the practice** (Microsoft SQL Server + a local
image file store; CBCT 3D, panoramic/OPG, 2D intraoral, cephalometric). Our system runs in the
**cloud** (Railway). They can't see each other directly.

**The bridge (recommended):** a small **local "bridge agent"** we install on the practice PC that:
- Talks to SIDEXIS via one of: **SLIDA** (Sidexis Link to Dental Applications — the official PMS
  bridge, lets you select a patient and pull images), the **VDDS-media** standard, or a **DICOM
  export folder** SIDEXIS writes to.
- **Matches by patient ID** (the critical, error-prone step — we align SIDEXIS patient IDs to our
  patient records, ideally seeded from the same `Patient Demographics.XLS`).
- Generates **web-friendly thumbnails/JPEGs** for 2D and panoramic (and a viewer link / exported
  stills for CBCT 3D volumes, which are too large to stream raw).
- **Uploads thumbnails + a reference** to the cloud app, so each patient's file shows their X-rays and
  scans under the right name and folder.

**Why a bridge, not direct cloud:** CBCT volumes are huge, SIDEXIS is on-prem and licensed, and patient
data must stay protected (POPIA). The bridge keeps originals on-site, ships only what's needed, and
survives the practice internet going down. *(Trade-offs and fallbacks are stress-tested in the audit.)*

---

## 6. Compliance built in (not bolted on)

Because the **patient** self-claims, the invoice must be flawless. Hard requirements baked into the data model:

- **16-element tax invoice** (VAT Act s20 / Tax Admin Act) + **sequential, gap-free, tamper-evident
  invoice numbering** (atomic sequence; voids keep their number).
- **Practice + practitioner identifiers** on every invoice: HPCSA **DP 0118702**, the **BHF practice
  number**, treating practitioner numbers — exact formatting (a transposed digit → patient's claim rejected).
- **Patient & main-member details** exactly as registered with the scheme (name char-for-char, membership no., ID).
- **SADA procedure codes + ICD-10 diagnosis codes + tooth numbers (FDI)** per line — the chart is the
  single source of truth that auto-fills tooth references.
- **VAT logic**: dental treatment for disease/injury is **zero-rated** (VAT Act s12(c)); purely
  **cosmetic** (e.g. whitening) is **standard-rated 15%**. VAT status derived from the diagnosis link
  per line — so whitening is taxed, a medically-necessary crown is not.
- **Retention**: clinical records **6 years** (HPCSA), financial records **5 years** (Tax Admin Act);
  automatic retention scheduling.
- **Immutable audit trail**: corrections are **new entries, never edits** (GoodX's "reverse, don't
  overwrite"). Every clinical/financial change logs who + when + why.
- **POPIA**: consent (already in the WhatsApp greeting), encryption at rest/in transit, role-based
  access (minimum-necessary), data-subject access/erasure handling.

---

## 7. How it's built (technical)

- **On top of what exists**: the current Rails + Inertia/React + Postgres dashboard on Railway. Each
  module = models + Inertia pages. WhatsApp via the existing Twilio line. Developed locally with
  `docker compose up`, shipped to Railway when proven.
- **Cloud (Railway)**: the web app, database, WhatsApp, forms, billing, patient file metadata.
- **On-prem bridge agent (practice PC)**: SIDEXIS images + the Whisper chair-side scribe (both keep
  raw data on-site for POPIA; only derived data/thumbnails/transcripts sync up).
- **Migration**: import `Patient Demographics.XLS` (2,200 patients), `Dental Macro's.xlsx`, and the
  service/fee data from PRACTICE_CONFIG and the transaction history.

---

## 8. Phased build plan

**Phase 1 — Foundation (accounts + catalogue).** Patients/Families/(scheme ref) + import 2,200
patients; Service catalogue + fee schedule + macros import. *Outcome: every patient and every code in
the system.*

**Phase 2 — Clinical core.** Course of Treatment + tooth chart + treatment items + clinical notes.
*Outcome: charting on screen.*

**Phase 3 — Money.** Estimates → compliant invoices → payments (incl. whitening deposit) → claimable
statements → WhatsApp delivery → debtors. *Outcome: full billing, paperless statements.*

**Phase 4 — Digital file & forms.** Patient file folders + WhatsApp digital forms + e-signature +
digital notepad. *Outcome: the 5 physical files retired.*

**Phase 5 — Integrations.** SIDEXIS bridge (images under each patient) + recalls/reminders + reporting.

**Phase 6 — The scribe.** Chair-side Whisper + Claude → auto-drafted estimates. *Built last because it
sits on top of the catalogue, macros, charting, and estimates from Phases 1–3.*

> Sequencing note: this all comes **after** the WhatsApp receptionist go-live settles (hard deadline
> today, 22 May, is the receptionist — not this). This is the long-term system.

---

## 9. What this changes for the practice

- Patients arrive with forms already done; leave with an estimate in hand.
- Dr Chalita charts by talking; the system drafts the plan and the bill.
- No physical files, no end-of-day photographing — the file is digital and complete.
- X-rays and scans sit under the right patient automatically.
- Every invoice a patient submits to their medical aid is correct the first time.
- One system, one source of truth, built and owned by the practice — not rented per-seat.

See the companion audit — [DIGITAL_PRACTICE_AUDIT.md](DIGITAL_PRACTICE_AUDIT.md) — for the stress test
of every risky assumption above and the creative solutions to make each one actually work.
