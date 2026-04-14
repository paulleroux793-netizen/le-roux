# Dr Chalita le Roux AI Receptionist — Development Roadmap

## Current Status: 🚀 9 of 17 Phases Complete

**Completed**: Phases 1-5, 8-9 (Core WhatsApp integration + Dashboard)  
**Next Priority**: Phase 6 (Voice), Phase 7 (Morning Confirmations)  
**Recommended**: Phase 10 (Import Historical Chats) — *backfill data so the dashboard is useful from day one*  
**Then**: Phase 11 (Data Capture & Analytics) — *capture real data before building notifications*  
**Future**: Phase 12 (Billing), Phase 13 (Notifications), Phases 14-17 (Security, Training, Deployment, Enhancements)

## Phase 1: Project Setup & Infrastructure
- [x] Create Rails 8 API-only application
- [x] Configure PostgreSQL database (Supabase)
- [x] Set up Twilio account and WhatsApp sandbox
- [x] Add environment variables (.env)
- [x] Add all required gems to Gemfile
- [x] Create README.md and ROADMAP.md
- [x] Run `bundle install` and lock dependencies
- [x] Set up RSpec testing framework
- [x] Create `.env.example` template
- [x] Initial Git commit with conventional commits

## Phase 2: Database Models & Migrations
- [x] Create `Patient` model (first_name, last_name, phone, email, date_of_birth, notes)
- [x] Create `Appointment` model (patient_id, start_time, end_time, status enum, google_event_id, reason, notes)
- [x] Create `CallLog` model (twilio_call_sid, caller_number, intent, duration, status, transcript, ai_response)
- [x] Create `DoctorSchedule` model (day_of_week, start_time, end_time, break_start, break_end, active)
- [x] Add indexes and validations
- [x] Seed doctor schedule with working hours (Mon-Fri 8-5, Sat 8-12, Sun closed)
- [x] Run migrations and verify schema
- [x] Add `Conversation` model (channel, patient_id, status, messages as JSONB)
- [x] Add `CancellationReason` model (appointment_id, reason_category, details)
- [x] Add `ConfirmationLog` model (appointment_id, method, outcome, attempts, flagged)

## Phase 3: Google Calendar Integration ✅ COMPLETE
- [x] Create `GoogleCalendarService` in `app/services/`
- [x] Implement service account authentication using `googleauth`
- [x] Implement `available_slots(date)` — fetch free/busy, return open 30-min slots
- [x] Implement `book_appointment(patient, start_time, end_time, reason)`
- [x] Implement `find_appointment(patient_phone, date_range)`
- [x] Implement `reschedule_appointment(event_id, new_start, new_end)`
- [x] Implement `cancel_appointment(event_id)`
- [x] **Important**: Never expose full availability — match against patient's preferred time
- [x] Write tests with mocked Google API
- [x] Test with real Google Calendar in development

## Phase 4: AI Brain — Claude Integration ✅ COMPLETE
- [x] Create `AiService` in `app/services/`
- [x] Design system prompt with Dr le Roux receptionist persona
  - Warm, friendly, slightly energetic, reassuring
  - Education-based approach: educate → reassure → guide to booking
  - Consistent across WhatsApp and voice
- [x] Implement intent classification (book, reschedule, cancel, confirm, faq, objection, urgent)
- [x] Implement entity extraction (date, time, patient name, treatment type)
- [x] Implement conversation memory (multi-turn context per session)
- [x] Pricing rules: only quote consultation (R850) and cleaning (R1,300), everything else → "needs consultation"
- [x] FAQ knowledge base (office hours, location, services, directions, parking)
- [x] Objection handling (price concerns, dental fear, timing issues)
- [x] Write tests with mocked AI responses
- [x] **Fixed**: multi-turn conversation by passing history to intent classification

## Phase 4.5: WhatsApp Message Templates (Critical) ✅ COMPLETE
- [x] **Create templates in Twilio Console:**
  - `appointment_confirmation` — "Hi {{patient_name}}, your appointment with Dr Chalita le Roux is confirmed for {{date}} at {{time}}. Reply CONFIRM or RESCHEDULE."
  - `appointment_reminder_24h` — "Hi {{patient_name}}, reminder: you have an appointment tomorrow at {{time}} with Dr Chalita le Roux. Reply to reschedule."
  - `appointment_reminder_1h` — "Hi {{patient_name}}, reminder: your appointment with Dr Chalita le Roux is in 1 hour at {{time}}."
  - `cancellation_confirmation` — "Hi {{patient_name}}, your appointment on {{date}} has been cancelled. Reply to reschedule or call us."
  - `reschedule_confirmation` — "Hi {{patient_name}}, your appointment has been rescheduled to {{new_date}} at {{new_time}}. Reply CONFIRM or call us."
  - `flagged_patient_alert` — "New flagged patient: {{patient_name}} ({{phone}}) - {{reason}}. Follow-up needed."
- [x] Approve all templates with Twilio (they go through review)
- [x] Store template names + variables mapping in Rails constants/env
- [x] Create helper methods to inject variables into templates via `WhatsappTemplateService`
- [x] Test template delivery via Twilio API

### Template Testing Instructions

Use the Rails console (`bin/rails console`) to test each template. Ensure all `WHATSAPP_TPL_*` env vars are set first.

**`appointment_confirmation`**
```ruby
patient = Patient.new(first_name: "Sarah", phone: "+27821234567")
appointment = Appointment.new(start_time: Time.zone.parse("2026-04-20 09:00"))
WhatsappTemplateService.new.send_confirmation(patient, appointment)
```
Variables: `{{1}}` patient first name, `{{2}}` formatted date (e.g. `Monday, Apr 20`), `{{3}}` formatted time (e.g. `09:00 AM`)  
Expected message: *"Hi Sarah, your appointment with Dr Chalita le Roux is confirmed for Monday, Apr 20 at 09:00 AM. Reply CONFIRM or RESCHEDULE."*

---

**`appointment_reminder_24h`**
```ruby
patient = Patient.new(first_name: "Sarah", phone: "+27821234567")
appointment = Appointment.new(start_time: Time.zone.parse("2026-04-20 09:00"))
WhatsappTemplateService.new.send_reminder_24h(patient, appointment)
```
Variables: `{{1}}` patient first name, `{{2}}` formatted time (e.g. `09:00 AM`)  
Expected message: *"Hi Sarah, reminder: you have an appointment tomorrow at 09:00 AM with Dr Chalita le Roux. Reply to reschedule."*

---

**`appointment_reminder_1h`**
```ruby
patient = Patient.new(first_name: "Sarah", phone: "+27821234567")
appointment = Appointment.new(start_time: Time.zone.parse("2026-04-20 09:00"))
WhatsappTemplateService.new.send_reminder_1h(patient, appointment)
```
Variables: `{{1}}` patient first name, `{{2}}` formatted time (e.g. `09:00 AM`)  
Expected message: *"Hi Sarah, reminder: your appointment with Dr Chalita le Roux is in 1 hour at 09:00 AM."*

---

**`cancellation_confirmation`**
```ruby
patient = Patient.new(first_name: "Sarah", phone: "+27821234567")
appointment = Appointment.new(start_time: Time.zone.parse("2026-04-20 09:00"))
WhatsappTemplateService.new.send_cancellation(patient, appointment)
```
Variables: `{{1}}` patient first name, `{{2}}` formatted date (e.g. `Monday, Apr 20`)  
Expected message: *"Hi Sarah, your appointment on Monday, Apr 20 has been cancelled. Reply to reschedule or call us."*

---

**`reschedule_confirmation`**
```ruby
patient = Patient.new(first_name: "Sarah", phone: "+27821234567")
appointment = Appointment.new(start_time: Time.zone.parse("2026-04-22 14:00"))
WhatsappTemplateService.new.send_reschedule(patient, appointment)
```
Variables: `{{1}}` patient first name, `{{2}}` new formatted date (e.g. `Wednesday, Apr 22`), `{{3}}` new formatted time (e.g. `02:00 PM`)  
Expected message: *"Hi Sarah, your appointment has been rescheduled to Wednesday, Apr 22 at 02:00 PM. Reply CONFIRM or call us."*

---

**`flagged_patient_alert`** *(sends to reception, not patient)*
```ruby
patient = Patient.new(first_name: "Sarah", last_name: "Smith", phone: "+27821234567")
WhatsappTemplateService.new.send_flagged_alert(patient, "3rd cancellation this month")
```
Variables: `{{1}}` patient full name, `{{2}}` patient phone number, `{{3}}` reason string  
Expected message: *"New flagged patient: Sarah Smith (+27821234567) - 3rd cancellation this month. Follow-up needed."*  
Note: message is sent to `RECEPTION_WHATSAPP_NUMBER`, not the patient.

## Phase 5: WhatsApp Integration (Primary Channel) ✅ COMPLETE
- [x] Create `WhatsappController` with `incoming` webhook (POST /webhooks/whatsapp)
- [x] Configure Twilio WhatsApp webhook URL via ngrok
- [x] Implement message receiving and response loop
- [x] Implement `WhatsappService` — send text, buttons, and list messages
- [x] Wire up: incoming message → AI brain → calendar check → response
- [x] Booking flow: greet → understand intent → ask preferences → check availability → confirm → book
- [x] Reschedule flow: identify patient → find appointment → offer new times → update
- [x] Cancel flow: try to reschedule first → if declined, capture reason → cancel
- [x] FAQ flow: answer question → still guide toward booking
- [x] Send booking confirmation message with appointment details
- [x] Handle unknown/off-topic messages gracefully
- [x] Add Twilio request signature validation (skipped in dev/test)
- [x] Test end-to-end with Twilio WhatsApp sandbox
- [x] **Fixed**: multi-turn conversation loop by disabling fast-path patterns and increasing API timeout

## Phase 6: Voice Call Integration
- [ ] Create `VoiceController` with `incoming` action (POST /webhooks/voice)
- [ ] Configure routes for voice webhooks (`/webhooks/voice`, `/webhooks/voice/gather`, `/webhooks/voice/status`)
- [ ] Implement greeting TwiML with `<Gather>` for speech input
- [ ] Implement speech-to-text → AI brain → text-to-speech response loop
- [ ] Implement same booking/reschedule/cancel flows as WhatsApp
- [ ] After-hours handling: AI answers, guides to booking or takes message
- [ ] During-hours overflow: AI answers when reception is busy
- [ ] Transfer to human: detect urgency or patient request → `<Dial>` to reception
- [ ] Call logging (duration, transcript, outcome)
- [ ] Add Twilio request signature validation
- [ ] Test with real phone calls via ngrok

## Phase 7: Morning Confirmation System (Critical Feature)
- [ ] Create `ConfirmationService` for daily appointment confirmations
- [ ] Create Solid Queue recurring job: runs daily 08:00-09:00
- [ ] Pull all same-day appointments from database + Google Calendar
- [ ] AI calls each patient to confirm:
  - Confirmed → mark appointment as confirmed
  - Reschedule → AI asks for new time, checks calendar, updates booking
  - Cancel → try to reschedule first, capture reason if declined
  - No answer / voicemail / unclear → flag for manual follow-up
- [ ] Create `ConfirmationLog` to track each confirmation attempt and outcome
- [ ] WhatsApp fallback: if patient doesn't answer call, send WhatsApp confirmation request
- [ ] Generate flagged patient list and send to reception (WhatsApp group / email / dashboard)
- [ ] Test the full confirmation flow

## Phase 8: Dashboard — Inertia.js + React Setup ✅ COMPLETE
- [x] Install and configure `inertia_rails` gem
- [x] Install and configure Vite + React + TypeScript
- [x] Remove `api_only = true` from application.rb (needed for Inertia)
- [x] Add session/cookie middleware back for dashboard auth
- [x] Create base layout with Inertia root div
- [x] Set up Tailwind CSS for styling
- [x] Create authentication (simple login for reception team)
- [x] Create sidebar navigation layout with DashboardLayout component

## Phase 9: Dashboard — Pages & Features ✅ COMPLETE
- [x] **Dashboard home**: today's appointments, pending confirmations, flagged patients count, system status
- [x] **Appointments page**: list/filter appointments (by status, date, search), status badges, quick actions
- [x] **Appointments detail page**: cancellation reason and confirmation history
- [x] **Conversations page**: view WhatsApp + call transcripts per patient with message history
- [x] **Patients page**: patient list with search (by name/phone/email), search by appointment history
- [x] **Patient detail page**: appointment history and active conversations
- [x] **Cancellation analytics**: reasons breakdown by category (cost, fear, timing, transport, other)
- [x] **Booking stats**: booking rate by channel (WhatsApp vs Voice), conversion tracking
- [x] **Settings page**: office hours table, pricing reference, FAQ knowledge base

## Phase 10: Import Historical WhatsApp Chats

The dashboard should be useful from day one, not just for future conversations. This phase backfills the database with real historical data by importing exported WhatsApp chats through the dashboard.

- [ ] **Dashboard upload UI**: add an "Import Conversations" page to the dashboard (file upload input for `.txt` WhatsApp export files, one file per conversation)
- [ ] **Parser service** (`WhatsappImportService`): parse the standard WhatsApp export format
  - Extract sender, timestamp, and message body from each line
  - Identify patient phone number from the conversation file name or first message
  - Group messages into a single `Conversation` record with `channel: "whatsapp"` and `status: "closed"`
- [ ] **Patient matching**: match phone number to existing `Patient` record; create a stub patient if none exists (first_name from phone, flagged for manual review)
- [ ] **Appointment detection**: scan conversation text for booking keywords; link to existing `Appointment` records where a match is found by date/time mentioned
- [ ] **Duplicate prevention**: skip import if a `Conversation` with the same patient + date range already exists
- [ ] **Import summary**: return a result object showing: conversations imported, patients created, patients matched, lines skipped
- [ ] **Dashboard feedback**: display import summary after upload (e.g. "Imported 24 conversations, created 6 new patients, skipped 2 duplicates")
- [ ] **Bulk import**: support importing a `.zip` of multiple `.txt` files in one upload
- [ ] **Manual review queue**: conversations with unmatched patients surface in a "Needs Review" list on the Patients page
- [ ] Test the import flow with a real exported WhatsApp `.txt` file from the current sandbox or production number

## Phase 11: Data Capture & Real Analytics Dashboard
- [ ] **Enhance Conversation Model**: add `outcome` field (booked, lost, rescheduled, pending), `message_count`, `first_response_time`
- [ ] **Enhance Appointment Model**: add `attended` boolean (for no-shows), `time_to_cancel` (days between booking and cancellation)
- [ ] **Real Data Queries** (replace dashboard hardcoded stats):
  - Bookings today by channel (WhatsApp vs Voice count)
  - Conversion rate: (confirmed appointments this week / total conversations) × 100%
  - Average messages per booking
  - Cancellation breakdown by reason (cost, fear, timing, transport, other)
  - Cancellation rate by day of week
- [ ] **Channel Performance Analytics**:
  - WhatsApp: # conversations, # bookings, booking rate, avg messages per booking
  - Voice: # calls, # bookings, booking rate, avg call duration
  - Channel comparison: which converts better?
- [ ] **Patient Behavior Tracking**:
  - Repeat patients vs new patient ratio
  - Average appointments per patient
  - Flag patients with 3+ cancellations (high-churn list)
  - Time to first appointment (from first message to booking)
- [ ] **Revenue Analytics**:
  - Total revenue from confirmed appointments
  - Revenue impact of cancellations (lost revenue)
  - Treatment type breakdown (which procedures generate most revenue)
- [ ] **Real-Time Dashboard Updates**:
  - Replace placeholder stats with live SQL queries
  - Show trends: "Bookings up 20% vs last week"
  - Alert system: "High cancellation rate this week"
- [ ] **Export & Reporting**:
  - CSV export: all conversations + outcomes for AI training data
  - PDF weekly summary for reception
  - Monthly report: email to doctor with key KPIs
- [ ] **Testing**: seed conversation and appointment outcomes to verify analytics queries work

## Phase 12: Billing & Invoicing System
- [ ] Create `Invoice` model (appointment_id, patient_id, amount, due_date, invoice_number, status enum)
- [ ] Create `Payment` model (invoice_id, amount, payment_date, payment_method, transaction_id, status)
- [ ] Invoice PDF generation using `wicked_pdf` or `prawn` gem
- [ ] Integrate **PayFast** (or **Stripe**) webhook for payment confirmation
- [ ] Auto-send invoice via WhatsApp/email after appointment confirmation
- [ ] Payment webhook endpoint: receive payment confirmation → update invoice status to "paid"
- [ ] Send WhatsApp notification to patient: "Payment received! Thank you"
- [ ] Send WhatsApp notification to reception: "Payment received from [patient] for appointment [date]"
- [ ] Dashboard widget: revenue this month, pending payments, overdue, payment success rate
- [ ] Solid Queue job for payment reminders: 1 day before due, 7 days after overdue
- [ ] Payment receipt generation and delivery

## Phase 13: Notifications & Reminders (Using Templates from Phase 4.5)
- [ ] WhatsApp appointment confirmation after booking (using `appointment_confirmation` template)
- [ ] WhatsApp reminder 24 hours before appointment (using `appointment_reminder_24h` template)
- [ ] WhatsApp reminder 1 hour before appointment (using `appointment_reminder_1h` template)
- [ ] WhatsApp cancellation confirmation (using `cancellation_confirmation` template)
- [ ] WhatsApp reschedule confirmation (using `reschedule_confirmation` template)
- [ ] Create recurring Solid Queue jobs for reminders (24h + 1h daily jobs)
- [ ] Create method to send flagged patient alerts via WhatsApp (using `flagged_patient_alert` template)
- [ ] Cancellation/reschedule confirmation messages
- [ ] Reception alerts: new bookings, cancellations, flagged patients

## Phase 14: Security & Hardening
- [ ] Validate Twilio webhook signatures on all endpoints
- [ ] Rate limiting on webhook endpoints
- [ ] Input sanitization for all patient-provided data
- [ ] Secure credential storage (Rails credentials)
- [ ] POPIA compliance considerations (South African data protection)
- [ ] Audit logging for all appointment changes
- [ ] Health check endpoint monitoring

## Phase 15: Training Data & Continuous Improvement
- [ ] Build interface to upload and transcribe call recordings (Cube ACR)
- [ ] Import historical WhatsApp chat logs
- [ ] Store all conversations and transcripts for future training
- [ ] Tag conversations by outcome (booked, lost, rescheduled, etc.)
- [ ] Identify high-converting conversation patterns
- [ ] Feedback loop: refine AI prompts based on real conversation data

## Phase 16: Deployment & Production
- [ ] Configure Kamal deployment (`config/deploy.yml`)
- [ ] Set up production PostgreSQL database
- [ ] Configure production environment variables
- [ ] Set up SSL/TLS
- [ ] Configure Twilio webhook URLs for production domain
- [ ] Move from WhatsApp sandbox to WhatsApp Business API (production)
- [ ] Deploy and smoke test all channels
- [ ] Monitor logs, error tracking, and uptime

## Phase 17: Enhancements (Future)
- [ ] Multi-language support (English + Afrikaans)
- [ ] Website "Book Appointment" button → WhatsApp flow
- [ ] Google Business Profile booking integration
- [ ] Voice customization (different AI voices)
- [ ] Wait-list management for cancelled slots
- [ ] Integration with dental practice management software
- [ ] A/B testing for greeting scripts and objection handling
- [ ] Advanced analytics dashboard with charts and trends
