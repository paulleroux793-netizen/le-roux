# Dr Chalita le Roux AI Receptionist — Development Roadmap

## Current Status: 🚀 9 of 14 Phases Complete

**Completed**: Phases 1-5, 8-9 (Core WhatsApp integration + Dashboard)  
**In Progress**: Phase 6 (Voice), Phase 7 (Morning Confirmations)  
**Upcoming**: Phases 10-14 (Notifications, Security, Deployment)

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

## Phase 10: Notifications & Reminders (Using Templates from Phase 4.5)
- [ ] WhatsApp appointment confirmation after booking (using `appointment_confirmation` template)
- [ ] WhatsApp reminder 24 hours before appointment (using `appointment_reminder_24h` template)
- [ ] WhatsApp reminder 1 hour before appointment (using `appointment_reminder_1h` template)
- [ ] WhatsApp cancellation confirmation (using `cancellation_confirmation` template)
- [ ] WhatsApp reschedule confirmation (using `reschedule_confirmation` template)
- [ ] Create recurring Solid Queue jobs for reminders (24h + 1h daily jobs)
- [ ] Create method to send flagged patient alerts via WhatsApp (using `flagged_patient_alert` template)
- [ ] Cancellation/reschedule confirmation messages
- [ ] Reception alerts: new bookings, cancellations, flagged patients

## Phase 11: Security & Hardening
- [ ] Validate Twilio webhook signatures on all endpoints
- [ ] Rate limiting on webhook endpoints
- [ ] Input sanitization for all patient-provided data
- [ ] Secure credential storage (Rails credentials)
- [ ] POPIA compliance considerations (South African data protection)
- [ ] Audit logging for all appointment changes
- [ ] Health check endpoint monitoring

## Phase 12: Training Data & Continuous Improvement
- [ ] Build interface to upload and transcribe call recordings (Cube ACR)
- [ ] Import historical WhatsApp chat logs
- [ ] Store all conversations and transcripts for future training
- [ ] Tag conversations by outcome (booked, lost, rescheduled, etc.)
- [ ] Identify high-converting conversation patterns
- [ ] Feedback loop: refine AI prompts based on real conversation data

## Phase 13: Deployment & Production
- [ ] Configure Kamal deployment (`config/deploy.yml`)
- [ ] Set up production PostgreSQL database
- [ ] Configure production environment variables
- [ ] Set up SSL/TLS
- [ ] Configure Twilio webhook URLs for production domain
- [ ] Move from WhatsApp sandbox to WhatsApp Business API (production)
- [ ] Deploy and smoke test all channels
- [ ] Monitor logs, error tracking, and uptime

## Phase 14: Enhancements (Future)
- [ ] Multi-language support (English + Afrikaans)
- [ ] Website "Book Appointment" button → WhatsApp flow
- [ ] Google Business Profile booking integration
- [ ] Voice customization (different AI voices)
- [ ] Wait-list management for cancelled slots
- [ ] Integration with dental practice management software
- [ ] A/B testing for greeting scripts and objection handling
- [ ] Advanced analytics dashboard with charts and trends
