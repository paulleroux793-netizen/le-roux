# Dr Chalita le Roux AI Receptionist — Development Roadmap

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
- [ ] Add `Conversation` model (channel, patient_id, status, messages as JSONB)
- [ ] Add `CancellationReason` model (appointment_id, reason_category, details)
- [ ] Add `ConfirmationLog` model (appointment_id, method, outcome, attempts, flagged)

## Phase 3: Google Calendar Integration
- [ ] Create `GoogleCalendarService` in `app/services/`
- [ ] Implement service account authentication using `googleauth`
- [ ] Implement `available_slots(date)` — fetch free/busy, return open 30-min slots
- [ ] Implement `book_appointment(patient, start_time, end_time, reason)`
- [ ] Implement `find_appointment(patient_phone, date_range)`
- [ ] Implement `reschedule_appointment(event_id, new_start, new_end)`
- [ ] Implement `cancel_appointment(event_id)`
- [ ] **Important**: Never expose full availability — match against patient's preferred time
- [ ] Write tests with VCR cassettes
- [ ] Test with real Google Calendar in development

## Phase 4: AI Brain — Claude Integration
- [ ] Create `AiService` in `app/services/`
- [ ] Design system prompt with Dr le Roux receptionist persona
  - Warm, friendly, slightly energetic, reassuring
  - Education-based approach: educate → reassure → guide to booking
  - Consistent across WhatsApp and voice
- [ ] Implement intent classification (book, reschedule, cancel, confirm, faq, objection, urgent)
- [ ] Implement entity extraction (date, time, patient name, treatment type)
- [ ] Implement conversation memory (multi-turn context per session)
- [ ] Pricing rules: only quote consultation (R850) and cleaning (R1,300), everything else → "needs consultation"
- [ ] FAQ knowledge base (office hours, location, services, directions, parking)
- [ ] Objection handling (price concerns, dental fear, timing issues)
- [ ] Write tests with mocked AI responses

## Phase 5: WhatsApp Integration (Primary Channel)
- [ ] Create `WhatsappController` with `incoming` webhook (POST /webhooks/whatsapp)
- [ ] Configure Twilio WhatsApp webhook URL
- [ ] Implement message receiving and response loop
- [ ] Implement `WhatsappService` — send text, buttons, and list messages
- [ ] Wire up: incoming message → AI brain → calendar check → response
- [ ] Booking flow: greet → understand intent → ask preferences → check availability → confirm → book
- [ ] Reschedule flow: identify patient → find appointment → offer new times → update
- [ ] Cancel flow: try to reschedule first → if declined, capture reason → cancel
- [ ] FAQ flow: answer question → still guide toward booking
- [ ] Send booking confirmation message with appointment details
- [ ] Handle unknown/off-topic messages gracefully
- [ ] Add Twilio request signature validation
- [ ] Test end-to-end with Twilio WhatsApp sandbox

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

## Phase 8: Dashboard — Inertia.js + React Setup
- [ ] Install and configure `inertia_rails` gem
- [ ] Install and configure Vite + React + TypeScript
- [ ] Remove `api_only = true` from application.rb (needed for Inertia)
- [ ] Add session/cookie middleware back for dashboard auth
- [ ] Create base layout with Inertia root div
- [ ] Set up Tailwind CSS for styling
- [ ] Create authentication (simple login for reception team)
- [ ] Create sidebar navigation layout

## Phase 9: Dashboard — Pages & Features
- [ ] **Dashboard home**: today's appointments, pending confirmations, flagged patients count
- [ ] **Appointments page**: list/filter appointments, status badges, quick actions
- [ ] **Conversations page**: view WhatsApp + call transcripts per patient
- [ ] **Flagged patients page**: list of patients needing manual follow-up with reasons
- [ ] **Patients page**: patient list, search by name/phone, appointment history
- [ ] **Cancellation analytics**: reasons breakdown (chart), trends over time
- [ ] **Conversion stats**: booking rate by channel, peak times, common objections
- [ ] **Settings page**: office hours, pricing config, AI prompt tuning

## Phase 10: Notifications & Reminders
- [ ] WhatsApp appointment confirmation after booking
- [ ] WhatsApp reminder 24 hours before appointment
- [ ] WhatsApp reminder 1 hour before appointment
- [ ] Create recurring Solid Queue jobs for reminders
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
