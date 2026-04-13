# Dr Le Roux AI Receptionist — Development Roadmap

## Phase 1: Project Setup & Infrastructure
- [x] Create Rails 8 API-only application
- [x] Configure PostgreSQL database
- [x] Set up Twilio account and phone number
- [x] Add environment variables (.env)
- [x] Add all required gems to Gemfile
- [x] Create README.md and ROADMAP.md
- [x] Run `bundle install` and lock dependencies
- [x] Set up RSpec testing framework (`rails generate rspec:install`)
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

## Phase 3: Google Calendar Integration
- [ ] Create `GoogleCalendarService` (lib/services or app/services)
- [ ] Implement service account authentication using `googleauth`
- [ ] Implement `list_available_slots(date)` — fetch free/busy info
- [ ] Implement `create_event(patient, start_time, end_time)` — book appointment
- [ ] Implement `find_event(patient_phone, date_range)` — look up existing appointments
- [ ] Implement `update_event(event_id, new_start, new_end)` — reschedule
- [ ] Implement `delete_event(event_id)` — cancel appointment
- [ ] Write tests with VCR cassettes for Google API calls
- [ ] Test with real Google Calendar in development

## Phase 4: Twilio Voice Webhook & Call Flow
- [ ] Create `TwilioController` with `voice` action (POST /twilio/voice)
- [ ] Configure routes for Twilio webhooks (`/twilio/voice`, `/twilio/status`, `/twilio/gather`)
- [ ] Implement initial greeting TwiML response with `<Gather>` for speech input
- [ ] Implement `gather` callback to receive speech transcription
- [ ] Implement `status` callback for call logging
- [ ] Add Twilio request signature validation (security)
- [ ] Set up ngrok for local development testing
- [ ] Test end-to-end call flow with Twilio

## Phase 5: AI/NLU Intent Recognition (Claude)
- [ ] Create `AiService` / `IntentRecognitionService`
- [ ] Design system prompt for medical receptionist persona
- [ ] Implement intent classification (book, reschedule, cancel, faq, transfer, unknown)
- [ ] Implement entity extraction (date, time, patient name, reason)
- [ ] Implement conversation context management (multi-turn)
- [ ] Handle ambiguous inputs — ask clarifying questions
- [ ] Create FAQ knowledge base (office hours, location, services, insurance)
- [ ] Write tests with mocked AI responses

## Phase 6: Call Flow Orchestration
- [ ] Create `CallFlowService` — ties Twilio + AI + Calendar together
- [ ] Implement booking flow: greet → gather intent → extract details → check availability → confirm → book
- [ ] Implement reschedule flow: identify patient → find appointment → offer new slots → confirm → update
- [ ] Implement cancel flow: identify patient → find appointment → confirm → cancel
- [ ] Implement FAQ flow: detect question → respond with answer
- [ ] Implement transfer flow: detect urgency → transfer to doctor's direct line
- [ ] Handle edge cases (no availability, patient not found, invalid date)
- [ ] Add retry logic for failed API calls
- [ ] Write integration tests for each flow

## Phase 7: SMS Notifications
- [ ] Create `SmsService` using Twilio
- [ ] Send appointment confirmation SMS after booking
- [ ] Send reminder SMS 24 hours before appointment (background job)
- [ ] Send cancellation confirmation SMS
- [ ] Send reschedule confirmation SMS with new time
- [ ] Create recurring Solid Queue job for reminders

## Phase 8: Call Logging & Analytics
- [ ] Log all calls to `CallLog` model
- [ ] Store transcripts and AI intent classifications
- [ ] Create API endpoints for call history (`GET /api/calls`)
- [ ] Create API endpoints for appointment stats (`GET /api/stats`)
- [ ] Add basic dashboard data (calls per day, booking rate, common intents)

## Phase 9: Security & Hardening
- [ ] Validate Twilio webhook signatures on all endpoints
- [ ] Rate limiting on API endpoints
- [ ] Input sanitization for all user-provided data
- [ ] Secure storage for credentials (Rails credentials or environment variables)
- [ ] HIPAA considerations — audit logging, data encryption at rest
- [ ] Add health check endpoint monitoring

## Phase 10: Deployment & Production
- [ ] Configure Kamal deployment (`config/deploy.yml`)
- [ ] Set up production PostgreSQL database
- [ ] Configure production environment variables
- [ ] Set up SSL/TLS
- [ ] Configure Twilio webhook URLs for production
- [ ] Deploy to production server
- [ ] Smoke test with real phone calls
- [ ] Monitor logs and error tracking

## Phase 11: Enhancements (Future)
- [ ] Multi-language support (English + Afrikaans)
- [ ] Voice selection and customization
- [ ] Patient portal / web interface
- [ ] Automated appointment reminders (email + SMS)
- [ ] Wait-list management
- [ ] Integration with medical practice management software
- [ ] Analytics dashboard with charts
- [ ] A/B testing different greeting scripts
