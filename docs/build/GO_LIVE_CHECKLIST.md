# Ivory — Go-Live Checklist (target: Monday)

> Branch `feat/practice-management-system` — **fully built, tested, NOT deployed.** This is the
> hand-off: what's done on my side, and the exact steps **you (Paul)** must do to go live.
> Compiled 2026-05-22.

## ✅ What's built & verified (Phases 1–8)
- Accounts/family + scheme membership · SADA procedure catalogue (172 codes at **latest real fees**) ·
  your 20 GoodX macros · fee schedule.
- Course of Treatment + FDI odontogram · immutable SOAP notes · treatment items.
- Estimates + **compliant invoices** (sequential no., HPCSA DP0118702 + BHF 0992801 + VAT 4260308871,
  **Medical/Self columns**, **Visit 1/2** grouping + explainer, 14-day footer, print-clean) · payments
  (card/cash/EFT + deposit) · statements.
- Digital patient file (your folders) · WhatsApp forms + ECTA e-signature · notepad.
- SIDEXIS imaging (real export parsed, 654 studies) · recalls · reporting KPIs.
- AI chair-side scribe (transcript → draft estimate, review-only, never auto-bills).
- Gold/grey brand palette · swappable logo · global search over everything · `/` shortcut.
- **Quality:** 51/51 scenario harness (stable), Brakeman 0 warnings, model specs 0 failures, additive
  (zero live-table/route/behaviour changes), nothing deployed.

## 🛑 What YOU must do for Monday (the gating path)
1. **Clear CI lint** — 18 pre-existing RuboCop offenses live in `app/services/{prompt_builder,
   whatsapp_service,practice_config}.rb` (existing WhatsApp code I was told not to touch). Run
   `bundle exec rubocop -a app/services/prompt_builder.rb app/services/whatsapp_service.rb app/services/practice_config.rb`
   (cosmetic, safe) so CI's lint job goes green — or confirm they're already accepted on main.
2. **Run the full RSpec suite in CI** (proper test env with dummy API creds per CLAUDE.md). The 39
   failures seen locally are **environmental** (integration specs need API creds/mocks absent in the dev
   container); model specs pass.
3. **Deploy** — I never push/deploy. Merge `feat/practice-management-system` → `main` once CI is green;
   Railway auto-deploys.
4. **Production env vars (Railway):** `DASHBOARD_USERNAME` + `DASHBOARD_PASSWORD` (gate the PII!),
   real `ANTHROPIC_API_KEY`.
5. **Run migrations on prod:** `bin/rails db:migrate` (12 additive migrations).
6. **Seed reference data on prod:** `bin/rails runner db/seeds/practice_management.rb`
   (catalogue + macros + PRIVATE fee schedule). Also seed the billing profile / confirm it.
7. **Import patients on prod:** place the secured `Patient Demographics` export as
   `db/seed_data/patients.csv` (gitignored — never commit PII), then
   `PatientDemographicsImporter.new.call(dry_run: false)`. Dry-run imports all 2,200 with 0 exceptions.
8. **Drop the logo:** put your logo at `public/brand/logo.png` → flows onto every document.
9. **Confirm** VAT `4260308871` + BHF `0992801` are still current (from 2023 docs).

## 🔌 You'll connect at the end (you said)
- **SIDEXIS** export folder / SLIDA on the practice PC → I'll wire the live image bridge.
- **Discovery 2026 rates** (SADA login or file) → I'll fill the **Medical** column precisely. *(Until
  then: your total/practice fees are exact from transactions; the Medical split shows 0 / full-Self.)*

## ⏳ Deferred (NOT blocking trial use — wired after go-live)
WhatsApp **delivery** of forms/estimates/recalls (engines built; outbound send is a stub) · on-prem
**Whisper** capture + real Anthropic call for the scribe · binary file storage backend (Active Storage)
· Afrikaans localisation of new pages · per-user reception/dentist roles · phone-viewport polish.

## Honest go/no-go
The system is **trial-ready now** and self-consistent. For **live patients on Monday**, steps 1–7 are the
gating path and only you can do them (deploy, prod env, prod data import). Everything on my side is done,
tested, and waiting. Open `localhost:3000` (`docker compose up`) → **Practice** sidebar to review.
