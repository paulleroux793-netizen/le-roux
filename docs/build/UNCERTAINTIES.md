# Build Uncertainties — Parking Lot for Paul

> Anything I'm unsure about during the autonomous build goes here. For each, I record my **best-guess
> decision** (so the build keeps moving) and the **question** for you to confirm/correct at the end.
> Nothing here blocks the build — these are review items.

Format: **[status] Topic** — *Decision I made* → **Question for Paul.**

---

### Architecture / git
1. **[decided] Build branch base.** I based `feat/practice-management-system` on your local
   `feat/calendar-redesign-status-journey` (schema 2026_05_22, the most complete current schema) rather
   than `fork/main` (which showed an older schema, 2026_04_23). → **Is the calendar branch the right
   base, or is something else actually in production right now?**

2. **[decided] Patients table left untouched.** To honour "don't touch my current setup," I linked
   accounts/schemes to patients via **join tables** (`account_patients`, `scheme_membership_patients`)
   instead of adding columns to the `patients` table. → **OK, or would you prefer simple
   `billing_account_id` columns on patients (simpler but modifies the existing table)?**

---

### Decisions already raised in the audit (Proposal/Audit §H) — still open
3. **[blocked-needs-you] BHF practice number** — required on every compliant invoice. HPCSA
   `DP 0118702` is confirmed; I'll leave a placeholder field. → **What is the practice's BHF number?**
4. **[decided] Tooth notation = FDI two-digit** (SA standard). → **Confirm FDI.**
5. **[decided] Whitening VAT = standard-rated 15%** (cosmetic); medically-necessary treatment
   zero-rated. → **Confirm whitening is taxed at 15%.**
6. **[decided] Roles** — two roles to start: `reception` and `dentist`. Dentist-only: signing clinical
   notes, finalising clinical records. Reception can do billing/accounts. → **Right split?**
7. **[decided] Migration cutover** — new patients fully digital now; existing paper files digitised
   opportunistically on next visit (current photograph-and-upload stays as bridge). → **Agree?**
8. **[needs-you] SIDEXIS access** — I'll build the bridge against a watched export folder + DICOM.
   → **Can you enable a SIDEXIS export folder / SLIDA on the practice PC, and share a sample export
   so I can test patient-ID matching?**
9. **[decided] Scribe recording consent** — I'll add a recording-consent line to the digital intake
   form; audio processed locally and deleted after transcript. → **OK to record consults for the scribe?**

---

### Added during the build
10. **[decided] Procedure-code descriptions are partly placeholders.** Your GoodX transaction export
    didn't carry procedure descriptions, so ~150 of 172 codes show "Tariff NNNN" (the 20-odd codes used
    in your macros have real descriptions from the macro file). Fees are REAL (median of a year's
    actual charges). → **I'll enrich descriptions from the SADA tariff book later — can you share a SADA
    code list, or confirm it's fine to pull standard SADA descriptions?**
11. **[decided] VAT per code guessed by keyword.** Codes whose description mentions
    whiten/bleach/cosmetic/veneer → standard-rated 15%; everything else → zero-rated (medical). Most
    codes lack descriptions so defaulted to zero-rated. → **Needs a proper pass once descriptions are in.**
12. **[decided] A few non-clinical codes** (e.g. `0000`) came through from the transaction export. Left
    in the catalogue as `category: other` for now. → **Confirm these can be hidden/removed.**

13. **[BLOCKED-needs-you] Patient identity / family members sharing a phone.** The live `patients`
    table requires a **unique, non-blank phone**. In your 2,200-row export, **386 rows are family
    members sharing one cell number** and **124 have no phone** — 510 patients that can't each get a
    unique-phone Patient row. My dry-run importer creates the 1,690 patients that DO have a unique
    phone, plus all 1,572 accounts + 168 schemes, and parks the other 510 as exceptions. → **To import
    the whole family, I recommend adding a nullable `id_number` to patients as the real identity key
    (SA ID is unique per person) and allowing a blank phone for non-contactable dependants. That's a
    small additive change to the patients table — may I make it? Or do you prefer family members live
    only as account links until they first message us?** *(Real import is gated on this answer; dry-run
    proves the logic.)*
14. **[decided] Patient PII is NOT committed to git.** `db/seed_data/patients.csv` is gitignored (real
    names/IDs/phones). The importer reads it locally only. → **For the production import, point the
    importer at a secured local path; don't put the export in the repo.** (Macro/procedure-code CSVs
    are non-PII and are tracked.)

15. **[decided] New nav labels are English-only.** The existing dashboard has an EN/AF toggle via a
    translations file; my new "Practice" nav items (Accounts / Procedure Codes / Treatment Macros) use
    literal English labels to avoid touching the shared i18n system. → **Want these (and the new pages)
    localised to Afrikaans too? I'll add the keys if so.**

16. **[decided] System name = "Ivory" (working codename).** Paul said he'll give it a cool name; I'm
    using **Ivory** so the build + comparison doc have something to refer to (clean, dental, brandable —
    reads well as "Exact · GoodX · Ivory"). → **Keep "Ivory" or rename?** One place to change it.

17. **[decided] VAT is treated as INCLUSIVE in the fee.** Your catalogue fees (the real medians) are
    taken as VAT-inclusive; for cosmetic/standard-rated lines the 15% is extracted from the price
    (not added on top). Most dental treatment is zero-rated anyway. → **Confirm fees are VAT-inclusive
    (vs. adding 15% on top of cosmetic line prices).** Also: **are you VAT-registered?** If not, no VAT
    line is needed at all and whitening etc. are simply not taxed.

### Will be added as the build progresses
*(new uncertainties appended here by later build sessions)*
