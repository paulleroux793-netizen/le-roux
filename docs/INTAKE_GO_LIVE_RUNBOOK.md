# Patient Intake — Go-Live Runbook (for the production RIG)

The WhatsApp patient-intake feature was **built and fully verified on the dev laptop**
(2026-06-04). This runbook is for the **always-on hardened rig** that will be the
internet-exposed production host. Work through it top to bottom; **do not skip the
verification gates** — this exposes patient PHI to the internet.

> **Security reality:** no internet-connected system is 100% unhackable. This runbook
> implements the defence-in-depth from the security research. The single biggest real
> risk is the **rig host itself** — confirm it is BitLocker/FDE-encrypted, patched,
> Defender-on, and NOT used for general browsing/email before exposing anything.

---

## What is already DONE (on the dev laptop — comes with the code)
- Intake feature: 3 forms, mobile wizard, tokenised WhatsApp link, branded PDF.
- `encrypts` on `Patient#id_number` (deterministic) + medical-history + form data.
- Completed pack is **emailed to info@drchalitaleroux.co.za** AND **saved to the
  "1. Patient Files" OneDrive folder** as `First Last YYYY-MM-DD.pdf`.
- App hardening: rack-attack on `/intake`, `block_public_host` (dashboard 404s on the
  public host), `production.rb` already has `force_ssl`/HSTS/generic-errors/info-log,
  PHI filtered from logs.
- DejaVu Sans vendored (`vendor/fonts/`) so no patient input can crash a PDF.

## What the RIG must do (this runbook)

### 1. Get the code
```bash
git fetch fork && git checkout feat/practice-management-system && git pull fork feat/practice-management-system
bundle install            # installs rack-attack 6.8 (now in Gemfile.lock)
```

### 2. Secrets / env (NEVER commit these; rig has its own C:\NightOwl-Secrets)
Generate the rig's OWN encryption keys (the rig has its own DB → its own keys):
```bash
bin/rails db:encryption:init   # paste the 3 values into the rig env:
#   AR_ENCRYPTION_PRIMARY_KEY / AR_ENCRYPTION_DETERMINISTIC_KEY / AR_ENCRYPTION_KEY_DERIVATION_SALT
```
Set the rest in the rig env (env_file / Railway / compose):
- `SECRET_KEY_BASE` (production) — `bin/rails secret`
- `BASE_URL=https://intake.chalitaleroux.co.za`
- `INTAKE_PUBLIC_HOST=intake.chalitaleroux.co.za`  ← makes the dashboard 404 on the public host
- `INTAKE_FILE_DIR=/patient_files`  ← bind-mount the rig's "1. Patient Files" OneDrive folder here (writable)
- `INTAKE_NOTIFY_EMAIL=info@drchalitaleroux.co.za`
- SMTP from the master vault: `SMTP_ADDRESS=<CHALITA_MAIL_SMTP_HOST>`, `SMTP_PORT`, `SMTP_USER_NAME=<CHALITA_MAIL_INFO_USER>`, `SMTP_PASSWORD=<CHALITA_MAIL_INFO_PASS>`, `MAILER_FROM_ADDRESS=reception@drchalitaleroux.co.za`
- Twilio from vault: `TWILIO_ACCOUNT_SID=<CHALITA_TWILIO_ACCOUNT_SID>`, `TWILIO_AUTH_TOKEN=<CHALITA_TWILIO_AUTH_TOKEN>`, `TWILIO_WHATSAPP_NUMBER=<CHALITA_TWILIO_WHATSAPP_FROM>`
- `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` (strong — gates the dashboard)
- `AR_ENCRYPTION_SUPPORT_UNENCRYPTED=true` (until the backfill runs; then set false)

### 3. Database (BACK UP FIRST)
```bash
pg_dump ... > backup-pre-intake.sql          # rig's own DB
bin/rails db:migrate                          # EncryptPhiColumns (id_number/medhist string→text, form data jsonb→text)
bin/rails runner db/seeds/intake_forms.rb     # seed the 3 templates
bin/rails phi:encrypt                         # re-encrypt existing PHI with the rig's keys
bin/rails phi:verify                          # MUST report 0 plaintext
```
Then set `AR_ENCRYPTION_SUPPORT_UNENCRYPTED=false` and restart.

### 4. Run in PRODUCTION mode (mandatory — dev mode leaks data on errors)
Build/run the production image (`./Dockerfile`, not Dockerfile.dev): `RAILS_ENV=production`,
assets precompiled, eager load. The dev stack stays for LAN reception; only the production
instance is tunnelled.

### 5. Cloudflare tunnel (zone chalitaleroux.co.za = 993f9693a429b3c2bd7b73186a13f92c)
```bash
cloudflared tunnel login                                  # Paul approves in browser
cloudflared tunnel create ivory-intake
cloudflared tunnel route dns ivory-intake intake.chalitaleroux.co.za
# config.yml ingress: intake.chalitaleroux.co.za -> http://localhost:<prod-port>; everything else -> 404
cloudflared tunnel run ivory-intake                       # install as a service so it's always-on
```

### 6. Cloudflare dashboard hardening (for intake.chalitaleroux.co.za)
- SSL/TLS: **Full (strict)**; **Always Use HTTPS**; **HSTS** on.
- **WAF**: managed OWASP ruleset on.
- **Rate limiting** rule on path `/intake*` (e.g. block > 40 req / 5 min per IP).
- **Firewall rule**: if `http.request.uri.path` does NOT start with `/intake` → **Block**.
- (Nice-to-have) **Turnstile** on the form if spam appears.

### 7. VERIFICATION GATES — do ALL before sending any patient a link
1. `https://intake.chalitaleroux.co.za/` and `/dashboard`, `/patients` → **404** (host-lock works).
2. A real tokenised `/intake/<token>` link → wizard loads, submits, completes.
3. Trigger an error on the public host → **generic page**, no stack trace / params.
4. Hammer `/intake` > limit → **429** (rate limiting works).
5. Completed submission → PDF appears in "1. Patient Files" named `First Last YYYY-MM-DD.pdf` AND email arrives at info@.
6. Raw DB check: `SELECT id_number FROM patients LIMIT 1` → ciphertext, not a number.
7. **Send the first real link to Paul's own WhatsApp** and complete it end-to-end before any patient.

### 8. Go live
Reception sends the link via the patient file ("Send intake" button) or it's wired into
the booking flow. Link preview card is already set (Open Graph + FB banner og-image).

---
*Generated from the dev build 2026-06-04. Mint a real link on the rig with:*
`"#{ENV['BASE_URL']}/intake/#{Patient.find(ID).signed_id(purpose: :intake, expires_in: 14.days)}"`
