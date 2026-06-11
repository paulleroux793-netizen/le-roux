# Ivory — System Manual

Dr Chalita le Roux Inc · Practice Management System
How everything works — a guide for anyone learning Ivory.

## 1. What Ivory is

Ivory is the practice's own dental practice-management system. It runs the diary,
the patient records, the clinical treatment plans, the billing (estimates,
invoices, payments, statements), recalls and reminders, reporting, and the
WhatsApp AI receptionist — all in one place.

It is built to replace the day-to-day functions of the old Elixir system one piece
at a time, starting with the diary and WhatsApp booking. Elixir stays the live
source of historical data and is only ever read, never written. Ivory is the
working system the practice runs on going forward.

In one line: Ivory is where reception books patients, the dentist charts and bills
treatment, and the AI answers WhatsApp — backed by the practice's real patient and
billing data.

## 2. Getting in

Ivory runs on the practice rig (the RTX-5090 computer) inside Docker. You reach it
over the practice's private Tailscale network.

- Address: http://100.73.38.21:3000
- Login: username "reception", password (kept in the practice secrets file).

There is one shared reception login. Everything is logged in an audit trail, so
actions are traceable even with a shared login.

If a page does not load, it is almost always the network link (Tailscale) dropping,
not Ivory. Wait a moment and reload.

## 3. The big picture — how it is built

- The app is a single Rails 8 application with a React (Inertia) front end and a
  PostgreSQL database. It is one program; there is no separate "back office".
- It runs on the rig in two Docker containers: the web app and the database. A
  nightly encrypted backup runs automatically.
- The AI brain for WhatsApp uses Anthropic's Claude in the cloud. The rig's GPU is
  not used for the AI today.
- Patient health data is encrypted at rest in the database.

Where the data lives: Elixir (the old system) is the live read-only source of truth
for historical records. Ivory holds a fully editable working copy that the practice
operates on. When an Ivory function is proven better than Elixir's, that function is
"flipped" to Ivory. Ivory is never allowed to be worse than what Elixir already did.

## 4. The dashboard

The dashboard is the front page after login. It is the "what needs attention right
now" screen. It shows:

- Patient flow today — who is Waiting, In chair, or Ready for checkout.
- ASAP waitlist — patients who asked for an earlier slot, with one-tap "WhatsApp
  offer" and "Call" buttons so reception can fill a cancellation fast.
- Intake outstanding — patients whose digital intake form is not yet complete.
- No-shows to rebook — recent no-shows with click-to-call.
- Lab cases due back — crowns/bridges out at the lab, with overdue ones flagged, so
  reception books the fit appointment when they return.
- Reminders due and checkout banners.
- Stat cards (today's appointments, etc.) and a quick-start card.

## 5. The diary and booking

The diary is the Elixir-style two-column day view (one column per dentist). It is
the heart of reception's day.

- Each appointment shows the patient and is colour-coded by its lifecycle status
  (scheduled, arrived, in chair, completed, cancelled, no-show), not by treatment
  type.
- You can drag an appointment to reschedule it. The system blocks a move that would
  overlap another appointment for the same dentist.
- Type-ahead search finds a patient quickly when booking.
- "Find next available" uses the practice working hours (set per weekday in
  Settings, including breaks) to suggest the next open slots for a dentist and a
  given appointment length.
- Booking can send the patient a tokenised digital-intake link automatically.

Safety rules built in: you cannot double-book a dentist, and an appointment cannot
end before it starts.

## 6. Patients

The patients area is the searchable list of every patient and the full record for
each one.

- Search by name, account code, or phone.
- A patient's record holds their demographics, medical history (encrypted), contact
  details, billing account, scheme membership and dependant code, appointments,
  treatment plans, estimates, invoices, files, and WhatsApp conversation.
- From a patient you can book an appointment, edit details, start a treatment plan
  or estimate, send the intake link, print the intake pack, and (when a Google
  review link is configured) send a review request over WhatsApp.
- Deleting a patient who still has invoices is blocked by the database, so financial
  records are never orphaned.

Phone numbers are stored in +27 form. A handful of historical numbers are odd
(extra digits or genuine foreign numbers) and are listed in a cleanup report for
manual correction — Ivory never auto-"fixes" an ambiguous number because it could
write the wrong one.

## 7. Treatment plans (Courses of Treatment) and charting

A Course of Treatment (COT) is the clinical episode — the plan of what will be done
for a patient.

- Open or start a COT from the patient. Add procedures by clicking a tooth on the
  odontogram (tooth chart) or by adding whole-mouth procedures (exam, x-ray,
  cleaning) directly.
- One-click visit templates ("macros") add a standard set of planned items — for
  example a recall-plus-hygiene visit — so coding is consistent across patients.
- Each item can be marked planned, completed, failed, or voided. Marking items
  completed is what turns clinical work into billable work.
- Set the treating dentist on the COT; that carries through to the generated invoice
  and estimate (and the dentist's HPCSA number on the PDF).
- Lab items: flag a crown/bridge/denture "Send to lab" with a due-back date; it then
  appears on the dashboard "Lab cases due back" list, and you mark it "Returned" when
  it comes back.

From a COT you generate an Estimate (from planned + completed items) or an Invoice
(from completed items only). The system will not invoice a plan with nothing
completed.

## 8. Estimates

An estimate is a quote of planned treatment — not a final account.

- Start a blank estimate for a patient, or generate one from a treatment plan.
- Add and edit line items (codes, teeth, fees). Multi-visit estimates group lines by
  visit.
- The estimate PDF clearly states it is an estimate, valid for 14 days, and that
  actual fees may vary.
- Accepting an estimate converts it to an invoice. An empty estimate (no lines)
  cannot be converted.
- Estimates show expiry badges so reception can see which are stale.

## 9. Invoices, payments and receipts

The invoice is the final account for completed treatment.

- Generate an invoice from a treatment plan's completed items, or by accepting an
  estimate. Each invoice gets a sequential number.
- Record a payment (card, cash, or EFT) against an invoice. Part-payments are
  supported; the invoice status moves open → part-paid → paid automatically.
- A printable receipt is produced for each payment.
- The practice is patient-pay: it does not claim from medical aid on the patient's
  behalf. The invoice is given to the patient to submit to their scheme. The medical-
  aid dependant code prints on the invoice so the claim attributes correctly.
- Overdue invoices show an age badge. Reporting includes aged-debt buckets.

Built-in safeguards: you cannot pay a voided (cancelled) invoice; a finalised
invoice is voided rather than edited (a correction is a new invoice); and the bulk
fee-uplift tool is bounded so a typo cannot multiply or zero the whole fee schedule.

## 10. Statements

A statement is an account-level summary across a date range for a billing account
(which can cover a whole family).

- Open it from an account; choose a date range; it renders as a PDF in the Elixir
  layout (practice and account header, medical-fund reference, transactions grouped
  by family member, bank details, and an age analysis: current / 30 / 60 / 90 / 90+).

## 11. Recalls and reminders

- Recalls: the list of patients due to come back. Reception works the list — call,
  mark contacted, mark booked.
- Reminders: pre-appointment reminders. A reminder is sent over the patient's channel
  (WhatsApp); if a patient has no phone, the send fails gracefully rather than
  breaking.

## 12. Reporting and analytics

- Reporting: production by dentist, aged-debt buckets, no-show rate, and other
  operational figures.
- Analytics: practice trends. Both pages handle odd or missing date filters without
  error.

## 13. Settings

Settings is where the practice's own details and rules live. It has tabs/sections
for:

- Practice details (name, phone, email, address, emergency phone, Google Maps link,
  and the Google review link used for review requests).
- Billing details — the legal/financial details printed on every invoice, statement
  and claim: HPCSA number, BHF/practice number, VAT number, company registration,
  treating-practitioner HPCSA, and full banking. Editable by reception, no console
  needed.
- Pricing (headline prices used in messaging).
- Working hours — per weekday open/close times, breaks, and active days, used by the
  diary's "find next available".

## 14. The WhatsApp AI receptionist

Ivory answers the practice WhatsApp line with an AI receptionist (Claude). It:

- Handles booking, FAQs, emergency triage, payment quotes (e.g. whitening deposits),
  and public-holiday closure messaging.
- Lands real bookings straight into the Ivory diary.
- Passes every outgoing message through a compliance filter that rewrites or blocks
  anything not allowed: no after-hours/24-hour/weekend promises, no medical-aid
  direct-billing claims, no medication dosing, no absolute claims or superlatives.
  Pricing is allowed in the private 1:1 chat.
- Can be paused per conversation so a human takes over, and escalates urgent cases.
- The incoming webhook verifies Twilio's signature, so forged requests are rejected.

## 15. Digital intake

New patients can complete intake digitally before arriving.

- Reception sends a tokenised link over WhatsApp (or shares a generic link). The link
  carries no personal data in the URL and expires after 14 days; an expired or
  invalid link shows a clear "this link is no longer valid" message.
- The patient fills in details, medical history and consent. On submit, Ivory matches
  an existing record or creates a new one for reception to review.
- Reception prints the completed intake pack on arrival for signing.

## 16. Imaging and clinical scribe

- Imaging: X-ray studies link to the record (with a planned SIDEXIS link).
- Scribe: an always-on chair-side scribe daemon can send transcript chunks (token-
  protected) toward draft clinical notes/estimates. This is an evolving area.

## 17. Admin and operations

- The app runs in Docker on the rig. Restarting the web container reloads the app.
- Data is loaded from Elixir via import scripts; Ivory tests "as if live" before any
  function is flipped over.
- A nightly encrypted backup runs. Take an extra point-in-time backup before any bulk
  data change.
- Audit log: every significant action is recorded and exportable.

## 18. Data-cleanup scripts

Conservative, reviewed scripts for tidying historical data live in
script/data-cleanup/. Every one defaults to a DRY-RUN that only prints what it would
change; applying requires an explicit env flag and is the practice's decision to run,
after a backup. They are never run automatically. The README there explains the
protocol and the status of each item.

## 19. Where to start as a new user

1. Log in and look at the dashboard — it shows what needs attention.
2. Open the diary to see the day and learn booking and rescheduling.
3. Open a patient to see the full record.
4. Follow one patient end-to-end: book, chart a treatment plan, generate an estimate,
   convert to an invoice, take a payment, print the receipt, view the statement.
5. Skim Settings so you know where the practice's details, billing details, and hours
   are configured.

That single end-to-end walk-through teaches most of Ivory in fifteen minutes.
