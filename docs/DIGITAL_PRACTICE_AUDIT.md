# Digital Practice System — Stress Test & Audit

> Companion to [DIGITAL_PRACTICE_PROPOSAL.md](DIGITAL_PRACTICE_PROPOSAL.md). This document does the
> opposite job of the proposal: it tries to **break** every risky assumption, rates the risk, and
> proposes a concrete, creative way to make it actually work. Compiled 2026-05-22.

## How to read this

Each item: **the claim → how it could fail → severity → the solution that makes it real.**
Severity: 🔴 high (could sink a subsystem) · 🟡 medium · 🟢 low.

---

## A. The AI chair-side scribe (the headline feature, and the riskiest)

**Claim:** Whisper transcribes the consult; Claude drafts a Course of Treatment + estimate; Dr Chalita reviews.

| Failure mode | Sev | Solution |
|---|---|---|
| **Crosstalk / two voices / drill noise** muddies the transcript | 🔴 | Whisper handles SA-English/Afrikaans well (your call pipeline proves it). Use a directional/lapel mic near the dentist, not a room mic. Accept that the transcript is a *draft aid*, never the record. |
| **Hallucinated or wrong findings → wrong estimate** | 🔴 | The scribe **never auto-charts or auto-bills**. It produces a **proposed** COT that Dr Chalita explicitly accepts line-by-line. The clinical record is what *she confirms*, not what the AI heard. |
| **POPIA: recording a patient** | 🔴 | Audio processed **locally** (no cloud), **deleted after** the transcript is drafted, and only with **consent** (add a one-line consent to intake forms). Store the *structured findings*, not the raw audio. |
| **"Is the patient in the chair?" sync is wrong** | 🟡 | Drive it off the appointment state machine: `arrived → in_chair → completed`. The scribe only listens while status = `in_chair` for that specific appointment, so the transcript binds to the right patient. Manual start/stop button as backstop. |
| **Latency — estimate not ready before they leave** | 🟡 | Stream the transcript during the visit; draft the COT incrementally so it's ready at chair-side, not minutes later. Worst case, reception finalises within a few minutes while the patient settles up. |

**Verdict:** feasible *as an assistant*, dangerous *as an authority*. Build it as "draft → human
confirms." This is also why it's **Phase 6** — it needs the catalogue, macros, charting and estimates underneath it.

---

## B. SIDEXIS image integration (the hardest integration)

**Claim:** a local bridge agent pulls X-rays/scans into the cloud app under the right patient.

| Failure mode | Sev | Solution |
|---|---|---|
| **Patient-ID mismatch** (SIDEXIS ID ≠ our ID) → images under wrong/no patient | 🔴 | Seed both sides from the same `Patient Demographics.XLS`; match on ID number + DOB + name; **queue unmatched images for manual linking** rather than guessing. Never auto-attach on a fuzzy match. |
| **CBCT 3D volumes are huge** (hundreds of MB) — can't stream to a web app | 🟡 | Don't. Keep the volume on-prem; sync a **thumbnail + key stills + a "open in SIDEXIS" link**. Full 3D viewing stays in SIDEXIS where the dentist already works. |
| **SLIDA/VDDS licensing or version limits** | 🟡 | Three fallback routes ranked: (1) SLIDA live bridge; (2) VDDS-media; (3) **watch a DICOM/JPEG export folder** SIDEXIS writes to — the simplest and most robust, needs no SDK. Start with (3), upgrade later. |
| **Practice internet down** → no sync | 🟢 | Bridge queues locally and uploads when back online. Images aren't time-critical. |
| **Sirona changes/locks the format** | 🟢 | DICOM is a standard; the export-folder route is vendor-stable. |

**Verdict:** achievable, but **start with the dumb-but-reliable export-folder watcher**, not the fancy
live SDK. Patient-ID matching is the real work, not the file transfer.

---

## C. Digital forms over WhatsApp + e-signature

**Claim:** patient fills + signs forms on their phone from a WhatsApp link; it lands in their file.

| Failure mode | Sev | Solution |
|---|---|---|
| **Is a finger-drawn signature legally valid?** | 🟡 | Yes under SA **ECTA** for ordinary consent (an "electronic signature" suffices; only a narrow class of documents needs an "advanced" signature — dental consent isn't one). Capture signature image + timestamp + IP + the exact form version signed = strong evidence. |
| **Patient doesn't complete the form** | 🟢 | Reminder nudge over WhatsApp; reception can still capture on a practice tablet on arrival; paper remains an emergency fallback during transition. |
| **Wrong form version stored** | 🟡 | Version every form template; store *which version* was signed (compliance + disputes). |
| **WhatsApp link security** (anyone with link sees the form) | 🟡 | Per-patient signed, expiring tokenised links; no patient data prefilled until they verify DOB. |

**Verdict:** solid. ECTA makes it legal; versioning + token links make it safe.

---

## D. Digital patient file replacing the 5 physical files

**Claim:** the file becomes fully digital; the notepad replaces writing on paper.

| Failure mode | Sev | Solution |
|---|---|---|
| **Migration of existing paper/photos** | 🟡 | Don't big-bang. New patients go digital immediately; existing files digitised opportunistically (next visit) — the current "photograph + upload" stays as the bridge until each file is converted. |
| **Notepad needs stylus/touch hardware** | 🟢 | Works on any tablet/touchscreen; degrade gracefully to typed notes + uploaded annotated PDFs where no stylus. |
| **HPCSA record integrity** (no silent edits) | 🔴 | Append-only clinical records with full version history; edits create a new version, original preserved (same audit principle as billing). |
| **6-year retention + safe destruction** | 🟡 | Automated retention schedule; nothing hard-deleted before its term; secure deletion after. |

**Verdict:** the retention + immutability rules are non-negotiable and must be in the data model from
day one — retrofitting an audit trail later is painful.

---

## E. Billing & compliance (because the patient self-claims)

| Failure mode | Sev | Solution |
|---|---|---|
| **Invoice missing a field → patient's claim rejected** | 🔴 | Hard validation: an invoice can't be finalised unless all 16 elements + HPCSA/BHF + SADA + ICD-10 + tooth + date + VAT status are present. Block, don't warn. |
| **VAT applied wrong** (zero-rate vs 15%) | 🔴 | VAT status derived from the diagnosis link per line, not chosen freely. Whitening/cosmetic → 15%; disease/injury treatment → zero-rated. Flag borderline cases (e.g. veneers) for explicit decision. |
| **Invoice numbering gaps** (tax offence) | 🟡 | Atomic central sequence; voids retain their number marked invalid; next invoice continues. |
| **BHF practice number** — do we have it? | 🟡 | **Open item for Paul** (HPCSA DP 0118702 is confirmed; BHF practice number must be captured before go-live). |

**Verdict:** simpler than a claiming practice (no submission) but the document rigor is *higher*. Validation-at-source is the whole game.

---

## F. Platform & operational resilience

| Failure mode | Sev | Solution |
|---|---|---|
| **Loadshedding / practice power down** | 🟡 | Cloud app (Railway) stays up regardless; staff can work from a phone/4G. The on-prem bridge (SIDEXIS/scribe) queues and resumes. UPS on the SIDEXIS PC recommended. |
| **Practice internet down** | 🟡 | Read-critical paths (today's diary, patient file) cached; writes queue. Full offline-first is a large effort — phase it; start with graceful degradation. |
| **OneDrive bind-mount dev slowness** | 🟢 | Already solved for dev (fast tmp volumes). Production is on Railway, unaffected. |
| **Data migration errors from 2,200 rows** | 🟡 | Dry-run import into the local Docker stack first; reconcile counts; never import straight to production. |
| **Single-developer bus factor** | 🟡 | Everything in git, documented, on Railway — not locked in a vendor or one person's head. |

---

## G. Scope & sequencing risks

- **Biggest risk is not technical — it's scope.** This is ~6 modules + 2 hard integrations. Trying to
  build it all at once fails. The **phased plan (Proposal §8) is the mitigation**: each phase is
  independently useful and shippable.
- **Don't let this distract from the 22 May WhatsApp deadline.** This system is the *next* chapter.
- **The scribe is the temptation to build first** (it's exciting) but it's correctly **last** — it
  depends on everything else.

---

## H. Decisions needed from Paul (so the overnight build isn't blocked)

These are genuine forks where your answer changes what gets built. Answer at your leisure:

1. **BHF practice number** — what is it? (HPCSA DP 0118702 already confirmed.)
2. **Tooth notation** — FDI two-digit (SA standard) assumed. Confirm.
3. **Who can do what** — reception vs Dr Chalita permissions: any procedures only the dentist may bill/sign?
4. **Scribe consent wording** — OK to add a recording-consent line to intake forms?
5. **Whitening VAT** — confirm whitening is treated as standard-rated (cosmetic) 15%.
6. **Migration cutover** — happy with "new patients digital now, old files digitised on next visit"?
7. **SIDEXIS access** — can we get the practice PC's SIDEXIS export folder / SLIDA enabled for the bridge?

---

## Overall verdict

**The system is buildable, and the no-claims model makes it materially simpler than GoodX/Exact.** The
two genuinely hard parts — the SIDEXIS bridge and the AI scribe — both have a "dumb but reliable"
starting version (export-folder watcher; draft-then-confirm scribe) that de-risks them. The compliance
rigor and immutable audit trail must be in the foundation from day one. Build it in phases, foundation
first, scribe last. Nothing here is a blocker — only the 7 decisions above need your input, and none of
them stop Phase 1 (patients + catalogue) from starting tonight.
