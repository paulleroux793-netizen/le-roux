# Dr Chalita le Roux AI Receptionist — Development Roadmap

## Current Status: 🚧 Phase 9.15 In Progress — 9.15.5–9.15.9 Complete

**Completed**: Phases 1-9, 9.5, 9.7-9.12, 13, partial 9.14, 9.15.1–9.15.9, 18, 20
**Current Priority**: Phase 9.15.10 (E2E verification), then Phase 10
**Deferred**: Phase 11 (Analytics), Phase 12 (Billing), Phases 14-17 (Security, Training, Deployment, remaining future enhancements)

## Mandatory Project Execution Rules
- Read `CLAUDE.md` first before making any implementation changes on this track
- Treat this `ROADMAP.md` as the single source of truth for phases, checklists, and progress tracking
- Do not create a separate roadmap if one already exists — merge new work into this file using the same phase/checklist structure
- Add new work as phases, sub-phases, or checklist items that match the existing roadmap style
- Update this roadmap continuously as work is completed
- Mark checklist items complete as soon as implementation, verification, and required tests are done
- Keep prompt files, language datasets, and AI configuration organized and maintainable — do not scatter them across the codebase
- Use the Afrikaans dataset as style guidance for natural Afrikaans phrasing only; clinic policy, safety, booking logic, pricing, and business rules remain the source of truth
- Never confirm or create a booking without checking calendar availability first

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
- [x] Seed doctor schedule with working hours (Mon-Fri 8-5, weekends closed)
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

## Phase 6: Voice Call Integration ✅ COMPLETE
- [x] Create `VoiceController` with `incoming` action (POST /webhooks/voice)
- [x] Configure routes for voice webhooks (`/webhooks/voice`, `/webhooks/voice/gather`, `/webhooks/voice/status`)
- [x] Implement greeting TwiML with `<Gather>` for speech input
- [x] Implement speech-to-text → AI brain → text-to-speech response loop
- [x] Implement same booking/reschedule/cancel flows as WhatsApp
- [x] After-hours handling: AI answers, guides to booking or takes message
- [x] During-hours overflow: AI answers when reception is busy
- [x] Transfer to human: detect urgency or patient request → `<Dial>` to reception
- [x] Call logging (duration, transcript, outcome)
- [x] Add Twilio request signature validation
- [x] Test with real phone calls via ngrok

## Phase 7: Morning Confirmation System (Critical Feature) ✅ COMPLETE
- [x] Create `ConfirmationService` for daily appointment confirmations
- [x] Create Solid Queue recurring job: runs daily 08:00-09:00
- [x] Pull all same-day appointments from database + Google Calendar
- [x] AI calls each patient to confirm:
  - Confirmed → mark appointment as confirmed
  - Reschedule → AI asks for new time, checks calendar, updates booking
  - Cancel → try to reschedule first, capture reason if declined
  - No answer / voicemail / unclear → flag for manual follow-up
- [x] Create `ConfirmationLog` to track each confirmation attempt and outcome
- [x] WhatsApp fallback: if patient doesn't answer call, send WhatsApp confirmation request
- [x] Generate flagged patient list and send to reception (WhatsApp group / email / dashboard)
- [x] Test the full confirmation flow

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

## Phase 9.5: Dashboard UI Redesign — Premium Brand System ✅ COMPLETE

Redesign the full dashboard layout to reflect a luxury medical/dental brand aesthetic. Replace the earlier light purple direction with a warm, premium color system. No inline styling — all styles must be handled through Tailwind classes or CSS modules.

- [x] **Review `STACK.md` and install all listed packages**: follow the installation order defined in the file. Make use of all these libraries when redesigning the app to create a more modern, polished UI
- [x] **Brand color system**: define and apply the core palette across all components
  - Primary brown `rgb(60, 53, 50)` — high-priority elements (Patient Form button, footer backgrounds)
  - Secondary taupe `rgb(120, 95, 81)` — secondary actions (Book an Appointment, smaller accents)
  - Muted antique gold — luxury accent for logo highlights, important text accents, premium UI details
  - White — dominant background color, large clean heading areas
  - Soft grays — borders, dividers, subtle backgrounds
- [x] **Remove all inline styles**: audit every component and move styles to Tailwind classes or CSS modules
- [x] **Top navbar redesign** (fixed): search bar, dentist/doctor name dropdown with selectable options, notification bell — clean, minimal, and easy to use
- [x] **Left sidebar redesign**: main navigation items plus settings, support, and logout — simple, elegant, consistent with premium look
- [x] **Main dashboard content layout**: structured, spacious sections for calendar, patient list, appointments, and admin/practice modules with generous spacing
- [x] **Component consistency pass**: ensure all buttons, cards, badges, tables, and form elements follow the new brand palette
- [x] **Overall aesthetic**: clean whites, soft grays, warm browns, taupe, and gold accents — no bright or overly colorful UI

## Phase 9.6: Dashboard Full Feature Build

Build out the full interactive dashboard functionality on top of the Phase 9.5 brand foundation. This phase adds real interactivity — calendar drag-and-drop, modals, filterable tables, functional search, a notification system, and patient forms. Install all remaining packages from `STACK.md` before starting.

> **Note:** Status badges and the notification bell icon (visual only) were completed in Phase 9.5 and are excluded here.

### Package Installs (from `STACK.md` — install before implementing)
- [ ] `react-hook-form zod @hookform/resolvers` — form validation
- [ ] `@tanstack/react-query axios` — server state + data fetching
- [ ] `@fullcalendar/react @fullcalendar/daygrid @fullcalendar/timegrid @fullcalendar/interaction date-fns react-datepicker` — interactive calendar
- [ ] `@tanstack/react-table @tremor/react recharts` — sortable tables + charts
- [ ] `@chatscope/chat-ui-kit-react react-dropzone` — chat UI + file upload
- [ ] `framer-motion @formkit/auto-animate` — animations
- [ ] `@dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities` — drag-and-drop
- [ ] `zustand` (optional) — client state management

### Interactive Calendar (FullCalendar)
- [ ] Replace static appointments table on Dashboard with a `FullCalendar` week/day view
- [ ] Drag-and-drop to reschedule appointments (`@fullcalendar/interaction` + `@dnd-kit`)
- [ ] Dentist/chair availability view: colour-coded lanes per dentist or treatment room
- [ ] Emergency/priority slot indicator (visual flag on calendar blocks)
- [ ] Waitlist management: if a slot is cancelled, surface the next waitlist patient automatically
- [ ] Click a calendar block to open the appointment detail modal

### Appointment Flows (Modal-Driven)
- [ ] **Create Appointment modal**: date picker, time slot selector (from Google Calendar availability), patient search, reason field — submits to `AppointmentsController#create`
- [ ] **Edit/Reschedule modal**: pre-filled with current appointment, updates via `AppointmentsController#update`
- [ ] **Cancel flow modal**: confirm cancel, capture reason (dropdown + notes), submits cancellation reason — no separate page needed
- [ ] Confirm appointment directly from the Appointments list (one-click status change)

### Sortable & Filterable Tables (`@tanstack/react-table`)
- [ ] Replace the Appointments list table with a `@tanstack/react-table` instance
  - Sortable columns: date, patient name, status, reason
  - Column filters: status dropdown, date range picker, channel badge
- [ ] Replace the Patients list table with the same approach
  - Sortable: name, last appointment, total appointments
  - Searchable: name, phone, email (functional — not just visual)
- [ ] Pagination component shared across both tables

### Patient Forms & Records
- [ ] **Patient Registration form** (`react-hook-form` + `zod`): first name, last name, phone, email, date of birth, notes — submits to `PatientsController#create`
- [ ] **Medical / dental history section** on Patient detail page: allergies, current medications, previous procedures, last X-ray date — requires new `PatientMedicalHistory` model and migration
- [ ] **Consent form**: digital consent checkbox with timestamp — stored on patient record
- [ ] **Edit Patient modal**: update patient details inline without leaving the page

### Functional Global Navbar Search
- [ ] Wire up the search input in the top navbar (currently renders but does nothing)
- [ ] On keystroke (debounced), query `/search?q=` endpoint in `SearchController`
- [ ] Create `SearchController#index`: search `Patient` (name/phone/email) + `Appointment` (reason/date) + `Conversation` (patient name)
- [ ] Render results in a dropdown below the search bar, grouped by type (Patients / Appointments / Conversations)
- [ ] Clicking a result navigates to the relevant detail page via Inertia `router.visit`

### Notification System
- [ ] Create `Notification` model: `recipient_type`, `recipient_id`, `action`, `notifiable_type`, `notifiable_id`, `read_at`, `message`
- [ ] Migration: add `notifications` table
- [ ] `NotificationsController`: `index` (list), `update` (mark read), `destroy` (dismiss)
- [ ] Bell dropdown in navbar: show unread notifications with count badge (replace visual-only bell)
- [ ] Notification types to create automatically:
  - New booking via WhatsApp/Voice → "New appointment booked: [patient] on [date]"
  - Appointment cancelled → "Cancellation: [patient] cancelled [date] appointment"
  - Flagged patient → "Flagged: [patient] needs manual follow-up"
  - Confirmation failed → "No response from [patient] for [date] appointment"
- [ ] Mark all as read button; individual dismiss
- [ ] Unread count shown on bell icon badge (real-time via polling or Turbo Streams)

### Pre-Appointment Reminders UI
- [x] **Reminders page** (`/reminders`): table of all upcoming appointments with status chips (Pending/Sent/Confirmed/Cancelled), sort, search, pagination
- [x] **Auto-tracking**: ConfirmationLog created when appointment is booked (via WhatsApp or UI) so it appears immediately on reminders page
- [x] **Manual actions**: Send WhatsApp, Call, Confirm, Cancel buttons per row
- [x] **Status flow**: Pending → Sent (reminder dispatched) → Confirmed (patient confirmed) / No Answer / Cancelled
- [x] **Window tabs**: Today / Tomorrow / This Week filter
- [x] **Stat cards**: Total, Pending, Confirmed, Today
- [ ] **Reminders tab** on Appointment detail page: show scheduled reminder status (24h sent ✓ / 1h sent ✓ / pending)
- [ ] Reminder log: timestamp of each reminder sent, delivery status (sent/failed)

## Phase 9.7: Full Application Audit & Implementation Baseline

Do a full audit before changing behavior. This phase exists to make the remaining work deliberate, minimal, and production-safe.

- [x] Read `CLAUDE.md` carefully and align the work with its safety rules, debugging rules, and commit requirements
- [x] Review the current `ROADMAP.md` structure and use the same phase/checklist format for all new work
- [x] Audit the current application surface area: routes, controllers, models, services, Inertia pages, shared layouts, key dashboard components, and existing specs
- [x] Review the provided dashboard/calendar screenshots and record them as the visual reference for this track
- [x] Capture baseline reproduction steps for the broken patient creation flow
- [x] Capture baseline reproduction steps for the appointment/calendar visibility issue
- [x] Record current N+1 hotspots, slow pages, and any known performance constraints before changing query behavior
- [x] Summarize the smallest safe implementation plan for the next phases before touching production-facing flows
- [x] Create a conventional commit for the audit baseline before moving into bug-fix work

## Phase 9.8: Patient Creation & Database Persistence Hardening

Fix the patient creation flow at the root-cause level so new patient data is reliably persisted and validation failures are handled cleanly.

- [x] Trace the full create-patient flow end to end: `PatientFormModal` → Inertia payload → `PatientsController#create` → `patient_params` → model validations → nested `medical_history` persistence → database write
- [x] Reproduce the current failure with logs and confirm exactly which fields are being lost or rejected
- [x] Verify that all patient fields are submitted correctly from the frontend and shaped correctly in the request payload
- [x] Verify that strong parameters and nested attribute handling accept all intended fields
- [x] Fix the root cause without changing unrelated patient behavior
- [x] Ensure validation failures and server errors are surfaced cleanly in the UI
- [x] Add or update tests for successful creation, validation failure handling, and nested medical history persistence
- [x] Re-test patient create and patient edit flows to confirm existing working behavior is preserved
- [x] Create a conventional commit before moving to the appointment flow

## Phase 9.9: Appointment Creation, Persistence & Calendar Rendering Integrity

Fix appointment creation so newly created records always appear in the calendar and the appointment lifecycle is consistent from form submission to visual rendering.

- [x] Trace the full appointment flow end to end: `AppointmentFormModal` → request payload → `AppointmentsController#create` → database/Google booking logic → Inertia props → `AppointmentCalendar`
- [x] Reproduce the current issue and confirm whether the failure is caused by persistence, page reload state, query scope, event mapping, or timezone handling
- [x] Verify that appointments are stored with the correct timestamps and timezone assumptions
- [x] Verify that the calendar queries the correct records and that newly created appointments are included in the returned dataset
- [x] Verify that event mapping in `AppointmentCalendar` matches the data shape returned by Rails
- [x] Fix the root cause so new appointments always appear in both the list view and the calendar view
- [x] Add or update tests for appointment creation, calendar payload integrity, and timezone-safe rendering assumptions
- [x] Re-test create, edit/reschedule, and cancel flows to confirm the calendar stays accurate
- [x] Create a conventional commit before moving to calendar polish

## Phase 9.10: Calendar UI Restyle & Booking Presentation

Refine the calendar so it matches the clean, premium booking/dashboard feel from the provided screenshot without copying it literally.

- [x] Audit the current calendar toolbar, spacing, surfaces, event cards, and empty states against the screenshot benchmark
- [x] Restyle the calendar shell so it feels like part of a polished clinic dashboard rather than a plain technical widget
- [x] Improve appointment card/event presentation for scanability: name, time, treatment/reason, spacing, and status hierarchy
- [x] Improve the calendar toolbar, controls, and surrounding card layout to match the screenshot’s clean SaaS composition
- [x] Keep the calendar visually aligned with the rest of the dashboard theme and card system
- [x] Verify the calendar remains readable and functional on desktop and smaller screen widths
- [x] Create a conventional commit before moving to performance work

## Phase 9.11: N+1 Query Audit & Performance Hardening

Review the application for avoidable query explosions and fix them without introducing over-fetching or behavior regressions.

- [x] Audit major pages for N+1 queries: dashboard, appointments, appointment detail, patients, patient detail, conversations, reminders, analytics, settings, and any calendar-related data loads
- [x] Check create/update flows that render associated records immediately after writes
- [x] Fix each confirmed N+1 with the appropriate eager loading or query restructuring strategy
- [x] Avoid loading unnecessary associations or broad datasets while fixing query counts
- [x] Add or update tests where practical to lock in the optimized query behavior
- [x] Re-run representative page requests and verify improved query counts and response times
- [x] Create a conventional commit before moving to UI cleanup

## Phase 9.12: Remove “System Status” From the UI

Remove the System Status feature completely from the dashboard and side navigation so it no longer appears anywhere in the interface.

- [x] Remove the “System Status” panel from the dashboard
- [x] Remove any “System Status”, “System Online”, or related status indicator from the sidebar/navigation
- [x] Remove any now-unused props, controller data, or helper code that only existed to support the removed UI
- [x] Verify the layout still feels balanced after the removal
- [x] Create a conventional commit before moving to the global theme update

## Phase 9.14: Design System Consolidation & Production Hardening

Establish a single source of truth for styling, consolidate reusable components, remove all inline styles, and bring every page and interactive flow up to production quality. Reference screenshots: clean teal/white/grey dental-clinic dashboards (DentaClinic / Dentlo / Zendenta style) — restrained palette, white surfaces, soft grey borders, a single accent colour used sparingly for CTAs and active states.

## Phase 9.15: Multilingual AI Receptionist + Afrikaans Dataset Integration

Add production-safe multilingual support to the AI receptionist so the bot can detect English or Afrikaans from the user’s first message, respond in the same language, use the Afrikaans dataset as style guidance, enforce calendar validation before booking/rescheduling, and support a dashboard language selector with persisted preference.

### 9.15.1: Discovery, File Placement & Existing Flow Audit ✅
- [x] Read `CLAUDE.md` first and confirm all work follows its safety, testing, and commit rules
- [x] Read `ROADMAP.md` and keep this phase in the existing checklist structure
- [x] Inspect the current AI/chatbot flow end to end
- [x] Identify files responsible for system prompt, booking, language detection, calendar
- [x] `config/ai/claude_master_prompt.md` — exists (developer tool, not used by bot at runtime)
- [x] `config/ai/afrikaans_language_dataset.json` — exists (2000 records, not loaded at runtime previously)
- [x] `Conversation#language` — already in schema; `WhatsappService#detect_language` already implemented
- [x] `Patient#preferred_language` — did not exist; added in 9.15.3
- [x] `AiService#build_system_prompt` — large inline heredoc; extracted to `PromptBuilder` in 9.15.4

### 9.15.2: Afrikaans Dataset Integration (Backend Reference Source) ✅
- [x] `config/ai/afrikaans_language_dataset.json` already in place
- [x] Created `app/services/afrikaans_dataset_service.rb` — class-level memoized loader
  - Reads and parses JSON once per process; filters on `gpt_evaluation_of_afrikaans == "Yes"`
  - `examples_for_intent(intent, limit: 6)` — topic-weighted selection per booking intent
  - `random_examples(limit: 8)` — general random sample
  - Graceful fallback (3 hardcoded health examples) if file missing or malformed
  - `reload!` method for test isolation
- [x] Dataset usage is read-only and style-focused only — no business logic

### 9.15.3: Conversation Language Detection & Session Persistence ✅
- [x] Language detection already existed (`detect_language`, `detect_and_persist_language`, `AFRIKAANS_MARKERS`)
- [x] Expanded `AFRIKAANS_MARKERS` with ~40 additional uniquely-Afrikaans words (removed ambiguous English words like "is", "was", "week", "help")
- [x] Added `patients.preferred_language` column (string, limit 5) via migration `20260418200000`
- [x] `Patient` model: `SUPPORTED_LANGUAGES` constant + `validates :preferred_language, inclusion: ...`
- [x] `detect_and_persist_language` now also syncs `patient.preferred_language`
- [x] `find_or_create_conversation` seeds `language:` from `patient.preferred_language` for cross-conversation memory
- [x] Tests added: `detect_language` (7 cases) + `detect_and_persist_language` (5 cases)
- [x] All 24 WhatsApp service specs pass

### 9.15.4: Prompt Builder Refactor — Multilingual + Dataset-Aware Prompt Assembly ✅
- [x] Created `app/services/prompt_builder.rb` — extracted full system prompt assembly from `AiService`
  - Constructor: `PromptBuilder.new(patient:, context:, afrikaans_examples:)`
  - `build` method: assembles the full system prompt with all existing clinic rules
  - `resolved_examples` — uses injected examples if provided, otherwise calls `AfrikaansDatasetService.examples_for_intent`
  - Dynamic Afrikaans examples injected only when `language == "af"`
  - English requests receive no Afrikaans examples (clean separation)
- [x] `AiService#build_system_prompt` now delegates to `PromptBuilder.new(...).build` (1 line)
- [x] Removed `working_hours_block`, `afrikaans_style_guide` from `AiService` (now in `PromptBuilder`)
- [x] Hardcoded `AFRIKAANS_STYLE_EXAMPLES` constant removed from `AiService`
- [x] All 37 affected specs pass (whatsapp_service + ai_service)

### 9.15.5: Booking & Rescheduling Guardrail Enforcement ✅
- [x] `attempt_booking` already validates: slot in future, within working hours, no local conflict ✅
- [x] `handle_reschedule` — added 3 guardrails before any DB write:
  - new slot must be in the future
  - new slot must be within working hours (`slot_within_working_hours?`)
  - new slot must not conflict with any other appointment (`slot_conflicts_locally?` with `exclude_appointment_id`)
- [x] `slot_conflicts_locally?` extended with `exclude_appointment_id:` keyword (avoids self-conflict when rescheduling)
- [x] `RESCHEDULE_REJECTED` bilingual constant — EN + AF rejection message
- [x] All guardrail rejections rewrite `result[:response]` so the controller TwiML reply matches reality
- [x] 228 specs pass, 0 failures

### 9.15.6: WhatsApp Message Flow Localization ✅
- [x] `send_booking_confirmation_message` — full bilingual rewrite (EN + AF body, after-hours notice, new patient addon)
- [x] Language threaded from `handle_booking` → `attempt_booking(language:)` → `send_confirmation_template(language:)` → `send_booking_confirmation_message(language:)`
- [x] `FALLBACK_BUSY` constant — bilingual AI-unavailable fallback (EN + AF)
- [x] `URGENT_FAST_PATH` constant — bilingual urgent/emergency fast-path response (EN + AF)
- [x] `build_fallback_result` and `build_local_result` use `conversation.language` for response selection
- [x] Afrikaans FAQ keyword patterns added to `build_fallback_result` (ure, oopmaak, tyd, prys, koste, hoeveel)
- [x] Twilio template flows (`send_reschedule_template`, `send_cancellation_template`) unchanged — pre-approved templates not localized
- [x] 228 specs pass, 0 failures

### 9.15.7: Dashboard Language Selector — Backend Preference Handling ✅
- [x] Decided: session-backed (no user model in app; single-admin dashboard)
- [x] `POST /settings/language` route added to `config/routes.rb`
- [x] `SettingsController#update_language` — validates lang ∈ `%w[en af]`, saves to `session[:ui_language]`, falls back to “en” on invalid
- [x] `ApplicationController#inertia_share` now exposes `ui_language: session[:ui_language].presence || “en”` to every page

### 9.15.8: Dashboard Language Selector — Frontend UI + Translation Wiring ✅
- [x] `LanguageContext.jsx` — refactored to seed initial state from `page.props.ui_language` (server) then localStorage then “en”
- [x] `setLanguage` now posts `POST /settings/language` via Inertia `router.post` on every change (session sync)
- [x] Full EN + AF `translations.js` already covered all pages (nav, dashboard, appointments, reminders, patients, conversations, analytics, settings, modals)
- [x] `DashboardLayout.jsx` topbar — compact EN/AF toggle chip added (Globe icon + EN/AF pill buttons)
- [x] Settings → Appearance tab already has the full EN/AF card toggle ✅
- [x] `t()` fallback: `translations.en[key] || key` — unknown keys return the key itself, never crashes

### 9.15.9: Patient/Conversation Language Visibility ✅
- [x] `conversation_props` (list view) — added `language:` field
- [x] `detailed_conversation_props` (detail view) — added `language:` field
- [x] `patient_detail_props` — added `preferred_language:` field
- [x] `ConversationShow.jsx` — language chip in header (`Afrikaans` green / `English` gray)
- [x] `Conversations.jsx` list — small `AF`/`EN` badge in the message-count column
- [x] `PatientShow.jsx` — “Preferred Language” field in patient info grid (colored badge)

### 9.15.10: End-to-End Verification & Regression Safety
- [ ] Run `bundle exec rspec`
- [ ] Run frontend build/verification (`npx vite build` or the project’s existing frontend verification command)
- [ ] Re-test the key flows manually end to end:
  - English booking via WhatsApp
  - Afrikaans booking via WhatsApp
  - English reschedule
  - Afrikaans reschedule
  - dashboard language switch to Afrikaans
  - dashboard language switch back to English
  - calendar unavailable fallback
  - urgent escalation behavior in both languages
- [ ] Verify existing English behavior is preserved where no multilingual changes were intended
- [ ] Verify approved Twilio template flows were not unintentionally broken
- [ ] Verify roadmap items are marked complete only where truly implemented
- [ ] Add a final conventional commit for end-to-end multilingual support verification

### 9.15.11: Documentation & Roadmap Maintenance
- [ ] Update `ROADMAP.md` continuously as each sub-task is completed
- [ ] Update setup/documentation notes if new AI config paths are introduced:
  - `config/ai/claude_master_prompt.md`
  - `config/ai/afrikaans_language_dataset.json`
- [ ] Add a short note in developer docs/README describing:
  - how language detection works
  - how the Afrikaans dataset is used
  - where dashboard translations live
  - the rule that calendar checks are mandatory before booking confirmation
- [ ] Summarize what changed and what was intentionally left untouched
- [ ] Create a final docs/conventional commit if documentation changes are separate

### Design tokens — single source of truth
- [x] Replace `theme.extend.colors.brand` in `tailwind.config.js` with a clean teal/white/grey palette
- [x] Expose the same tokens as CSS variables in `app/javascript/styles/application.css`
- [x] Remove old Phase 9.13 blue token block and backwards-compat aliases
- [x] Document the palette in a short comment block at the top of `tailwind.config.js`

### Zero inline styles audit
- [ ] Grep the codebase for `style={{` and `style="` — eliminate every occurrence
- [ ] Known offenders to fix:
  - `app/javascript/components/DataTable.jsx` — header width inline style
  - `app/javascript/pages/ConversationShow.jsx` — chat card `calc(100vh - 260px)` height
- [ ] Replace dynamic sizing with Tailwind utilities or named CSS classes in `application.css`
- [ ] Add a CI-friendly grep check (or a RuboCop-style reminder in CLAUDE.md) documenting the no-inline-styles rule

### Reusable component library
- [ ] `Button` — variants: primary, secondary, ghost, danger; sizes: sm, md, lg; icon slot; loading state
- [ ] `Card` — standard white surface with consistent padding, border, shadow
- [ ] `Badge` / `Chip` — status variants mapped to the token palette (success/warning/danger/info/neutral)
- [ ] `Input`, `Textarea`, `Select`, `DatePicker` wrappers — consistent label/help/error layout, shared focus ring
- [ ] `PageHeader` — title + subtitle + right actions, used on every page
- [ ] `EmptyState` — icon + title + subtitle + optional action
- [ ] `SectionTitle` — small uppercase label used above tables/cards
- [ ] Refactor existing ad-hoc chips/buttons/cards on each page to use these shared components
- [ ] Confirm `DataTable.jsx` is the single table implementation used by every list (Appointments, Patients, Conversations, Reminders, Analytics recent events)

### Page-by-page refactor to the new tokens + components
- [ ] `Dashboard.jsx`
- [ ] `Appointments.jsx` + `AppointmentShow.jsx`
- [ ] `Patients.jsx` + `PatientShow.jsx`
- [ ] `Conversations.jsx` + `ConversationShow.jsx`
- [ ] `Reminders.jsx`
- [ ] `Analytics.jsx`
- [ ] `Settings.jsx`
- [ ] `Login.jsx`
- [ ] Shared: `DashboardLayout`, `Sidebar`, `Topbar`, `NotificationBell`, `GlobalSearch`, `Modal`, all form modals (`PatientFormModal`, `AppointmentFormModal`, `CancelAppointmentModal`, `AppointmentDetailModal`)

### Calendar UI polish (reference: user-provided booking calendar screenshot)
- [ ] Restyle `AppointmentCalendar.jsx` + `appointment-calendar.css` to the new tokens
- [ ] Clean week/day/month toolbar matching the reference (rounded pill buttons, muted borders, generous spacing)
- [ ] Event cards show patient name, time, and reason with clear hierarchy
- [ ] Colour-coded event status (confirmed / pending / cancelled) using the token palette only
- [ ] Current-time indicator and today-column highlight use the primary accent
- [ ] Verify drag-and-drop reschedule still works and writes through to the backend

### Production-readiness verification (end-to-end flows)
- [x] **Appointment create** → saves → appears on calendar and list; syncs to Google Calendar when configured
- [x] **WhatsApp booking** → local-first persistence (source of truth is DB, Google is best-effort)
- [x] **WhatsApp honesty guard** → bot cannot claim a booking that didn't persist (response rewritten to fallback)
- [x] **AI date normalization** → classifier prompt gets `today` so "Friday at 11am" resolves to ISO date
- [x] **Calendar stability** → no more refresh loop (stable string key + skip-first-mount guard)
- [x] **Cache invalidation** → `after_commit` on Appointment model busts all dashboard caches
- [x] **Reminders page** → shows all upcoming appointments with status chips (Pending/Sent/Confirmed/Cancelled)
- [x] **Auto-tracking** → ConfirmationLog created automatically when appointment is booked (WhatsApp or UI)
- [x] **WhatsApp booking confirmation** → branded message with day, date, time, arrival instruction (15 min early), and practice directions from Hendrik Potgieter Rd and CR Swart Rd
- [x] **Practice location** → corrected from Pretoria to Doreen Rd, Roodepoort (directions from Hendrik Potgieter Rd and CR Swart Rd)
- [x] **Dashboard redesign** → stat cards (Total Patients, Today's Appointments, New Patients, Total Appointments), weekly appointment chart (recharts BarChart), upcoming appointments sidebar, today's schedule, reminders panel, recent patients table
- [ ] **Appointment edit/reschedule** → updates in list + calendar + Google
- [ ] **Appointment cancel** → captures reason, updates status, removes from active calendar view, fires notification
- [ ] **Patient create / edit** → validation errors surface inline; nested medical history persists
- [ ] **Notifications** fire automatically on: new booking, cancellation, flagged patient, incoming WhatsApp message, confirmation failure — visible in the bell dropdown with unread count
- [ ] **Global search** returns patients, appointments, and conversations
- [ ] Verify every page handles empty states, loading states, and server errors cleanly

### Patient model — optional extra fields
- [ ] Migration: add optional columns to `patients` — `address`, `city`, `postal_code`, `id_number`, `gender`, `occupation`, `preferred_language`, `referral_source`, `marketing_consent`
- [ ] Update `patient_params` strong parameters
- [ ] Add the fields to `PatientFormModal` (Edit) as an "Additional details" collapsible section
- [ ] Display populated fields on `PatientShow.jsx`
- [ ] Spec: create/update with the new fields persists and renders

### Commit cadence
- [ ] Commit the roadmap update first (`docs(roadmap): add Phase 9.14 design consolidation, drop Phase 9.13 blue rollout`)
- [ ] Commit after each sub-area (tokens, inline-style purge, component library, per-page refactor batches, calendar, production verification, patient fields)
- [ ] Run `bundle exec rspec` and `npx vite build` before each commit

## Phase 9.15: Multilingual AI Receptionist + Afrikaans Dataset Integration

Add production-ready English/Afrikaans support to the AI receptionist, wire in the Afrikaans dataset as style guidance, enforce first-message language detection, and add a dashboard language selector while preserving strict booking validation.

### Project instructions + file organization
- [ ] Read `CLAUDE.md` first before implementing this phase and follow it as the primary instruction file
- [ ] Keep this `ROADMAP.md` as the source of truth and update it as each multilingual task is completed
- [ ] Decide and document the final file locations for AI assets (recommended structure: `docs/`, `config/ai/` or `prompts/`, `data/language/`)
- [ ] Place the Afrikaans dataset JSON in a maintainable location (for example `config/ai/afrikaans_language_dataset.json` or `data/language/afrikaans_language_dataset.json`)
- [ ] Place the master Claude prompt in a maintainable location (for example `config/ai/claude_master_prompt.md` or `prompts/chatbot/claude_master_prompt.md`)
- [ ] Ensure prompt loading is handled by application code (`AiService`, `PromptBuilder`, or equivalent) rather than hardcoded inline strings

### Afrikaans dataset ingestion + normalization
- [ ] Convert the provided Afrikaans Excel dataset into structured JSON/JSONL suitable for runtime use
- [ ] Normalize records into a consistent schema (language, intent, user example, assistant example, optional tags/notes)
- [ ] Remove duplicates, blank rows, malformed examples, and obviously unusable records
- [ ] Store the cleaned dataset in version-controlled project files if size permits; otherwise document the loading approach clearly
- [ ] Add a lightweight loader/service to retrieve relevant Afrikaans examples by intent or semantic match
- [ ] Ensure the dataset is used as style guidance only and cannot override clinic policy or safety rules

### Language detection + conversation behavior
- [ ] Detect the user's language from the very first message of the conversation
- [ ] If the first message is English, respond in English and continue in English unless the user switches
- [ ] If the first message is Afrikaans, respond in Afrikaans and continue in Afrikaans unless the user switches
- [ ] If the message is mixed-language, choose the dominant language
- [ ] If language confidence is low, ask whether the user prefers English or Afrikaans
- [ ] Persist the active chat language in conversation state/session memory so follow-up turns remain consistent
- [ ] Add support for storing preferred language on the patient record when available or confirmed
- [ ] Use the Afrikaans dataset to improve Afrikaans tone, sentence structure, and phrasing; avoid awkward direct translations from English
- [ ] Do not mix English and Afrikaans in the same response unless the user does so first

### Claude prompt / AI service upgrade
- [ ] Update the master Claude system prompt to include language rules, booking rules, escalation rules, and dashboard language requirements
- [ ] Explicitly instruct the AI to use the Afrikaans dataset as a reference source for natural Afrikaans wording
- [ ] Keep safety boundaries in the prompt: no diagnosis, no medication advice, no invented pricing, no invented availability
- [ ] Add retrieval/context assembly so relevant Afrikaans examples can be injected into the Claude request when Afrikaans is detected
- [ ] Ensure business rules (pricing, office hours, services, booking logic, location) still come from the approved clinic knowledge base
- [ ] Add tests around prompt assembly to verify the correct language guidance is injected

### Booking and rescheduling validation hardening
- [ ] Enforce a mandatory calendar check before every booking confirmation
- [ ] Enforce a mandatory calendar check before every reschedule confirmation
- [ ] If a requested slot is unavailable, do not book it — offer alternative available slots instead
- [ ] Ensure the bot never claims a booking was made unless both persistence and availability checks succeeded
- [ ] If the calendar service is unavailable, explain that availability cannot be confirmed right now and provide the next best step
- [ ] Re-test WhatsApp and voice booking flows to verify the language rules do not bypass booking validation

### Dashboard language selector (English / Afrikaans)
- [ ] Add a dashboard language selector with exactly two options: English and Afrikaans
- [ ] Persist the selected dashboard language as a user preference or session preference
- [ ] Render dashboard labels, menus, buttons, helper text, and user-facing copy in the selected language
- [ ] Default the dashboard to English when no preference exists
- [ ] Optionally suggest the known chat language as the initial dashboard preference, while still allowing manual override
- [ ] Add translation keys/resources for dashboard UI strings and keep them centralized
- [ ] Ensure switching dashboard language does not affect booking data, statuses, timestamps, or business logic

### Tests, QA, and commit cadence
- [ ] Add/update specs for first-message language detection
- [ ] Add/update specs for Afrikaans-response behavior when Afrikaans input is used
- [ ] Add/update specs for fallback behavior when language is unclear
- [ ] Add/update specs for mandatory calendar validation before booking/rescheduling
- [ ] Add/update frontend tests or QA steps for dashboard language switching
- [ ] Run `bundle exec rspec` and `npx vite build` before each multilingual-related commit
- [ ] Commit the roadmap merge first, then commit dataset ingestion, prompt integration, language detection, calendar enforcement, and dashboard language selector as separate conventional commits

## Phase 10: Import Historical WhatsApp Chats

The dashboard should be useful from day one, not just for future conversations. This phase backfills the database with real historical data by importing exported WhatsApp chats through the dashboard.

### 10.1: Core Import Infrastructure ✅ COMPLETE
- [x] **Dashboard upload UI**: ImportModal in Conversations page with file upload for `.txt` and `.json` files
- [x] **Parser service** (`WhatsappImportService`): parse WhatsApp export format (iOS + Android line formats)
  - Extract sender, timestamp, and message body from each line
  - Identify patient phone number from caller-supplied param or JSON phone field
  - Group messages into a single `Conversation` record with `channel: "whatsapp"` and `status: "closed"`
- [x] **Patient matching**: match phone number to existing `Patient` record; create a stub patient if none exists (first_name from display name, last_name "(imported)")
- [x] **Topic classification**: `WhatsappTopicClassifier` assigns topic via keyword rules (booking, cancellation, emergency, etc.)
- [x] **Language capture**: `language` field on Conversation model stores detected language
- [x] **Duplicate prevention**: deterministic `external_id` (SHA1 of source + phone) — re-importing same file updates existing record
- [x] **Import summary**: Result struct with created/updated/skipped/errors counts
- [x] **Dashboard feedback**: flash notice shows import results after upload
- [x] **Import/live filter**: source filter pills on Conversations page ("Imported" / "Live" badges)

### 10.2: Zip Import & Review Queue ✅ COMPLETE
- [x] **Bulk zip import**: support `.zip` uploads containing multiple `.txt`/`.json` files — extract and process each (rubyzip gem)
- [x] **Review queue**: "Needs Review" stat card + filter on Patients page surfaces auto-created/imported placeholder patients
- [x] **Patient detection**: `needs_review?` method on Patient model flags placeholders (WhatsApp Patient, Phone Caller, Unknown, (imported))
- [ ] **Patient merge**: ability to link an auto-created patient to an existing patient record

### 10.3: AI Improvement Workflow ✅ COMPLETE
- [x] **Conversation tagging**: `tags` JSONB array column on conversations with migration
- [x] **Tag management UI**: tag editor on ConversationShow page with suggested tags, autocomplete, add/remove
- [x] **Curated examples filter**: tag filter pill on Conversations index page, `tagged` scope on Conversation model
- [x] **Export tagged conversations**: `GET /conversations/export_tagged?tag=...` endpoint exports JSON for prompt engineering
- [x] **Tag display**: conversation list rows show up to 2 tag chips with overflow count

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

## Phase 13: Notifications & Reminders (Using Templates from Phase 4.5) ✅ COMPLETE
- [x] WhatsApp appointment confirmation after booking (using `appointment_confirmation` template)
- [x] WhatsApp reminder 24 hours before appointment (using `appointment_reminder_24h` template)
- [x] WhatsApp reminder 1 hour before appointment (using `appointment_reminder_1h` template)
- [x] WhatsApp cancellation confirmation (using `cancellation_confirmation` template)
- [x] WhatsApp reschedule confirmation (using `reschedule_confirmation` template)
- [x] Create recurring Solid Queue jobs for reminders (24h + 1h daily jobs)
- [x] Create method to send flagged patient alerts via WhatsApp (using `flagged_patient_alert` template)
- [x] Cancellation/reschedule confirmation messages
- [x] Reception alerts: new bookings, cancellations, flagged patients

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
- [ ] Tag/store conversation language (English/Afrikaans) for multilingual analysis and prompt improvement
- [ ] Identify high-converting conversation patterns
- [ ] Build a multilingual feedback loop: refine English and Afrikaans prompts/examples based on real conversation quality
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

## Phase 15: Multi-Channel Notifications & Settings Redesign ✅ COMPLETE

### 15.1: Booking Confirmation with Location
- [x] Update WhatsApp booking confirmation to include full practice address
- [x] Include Google Maps link in confirmation message
- [x] Address: Unit 2, Amorosa Office Park, Corner of Doreen Road, Lawrence Rd, Amorosa, Johannesburg, 2040
- [x] Map: https://www.google.com/maps/place/Dr+Chalita+Johnson+le+Roux/
- [x] Include driving directions from Hendrik Potgieter Rd and CR Swart Rd

### 15.2: Insurance/Medical Aid Policy Update
- [x] Practice is a CASH practice — does not claim from medical aids directly
- [x] After payment, a statement is issued for the patient to claim back
- [x] Update AI system prompt with correct payment policy
- [x] Update FAQ payment entry
- [x] Remove "medical aid acceptance" from objection handling
- [x] Update patient form labels (Insurance → Medical Aid for claim-back)
- [x] No phone/WhatsApp quotes — consultation needed for tailored costs
- [x] Appointments only — no walk-ins

### 15.3: Email Confirmations & Reminders
- [x] Create AppointmentMailer with confirmation, reminder, and cancellation emails
- [x] Branded HTML email templates with practice details and map link
- [x] Email sent on booking (WhatsApp + dashboard), cancellation, and 24h reminder
- [x] Graceful fallback — email failures don't block primary flow

### 15.4: SMS Confirmations & Reminders
- [x] Create SmsService using Twilio SMS API
- [x] SMS confirmation on booking with practice address and map link
- [x] SMS reminder 24h before appointment asking patient to confirm
- [x] SMS cancellation notification
- [x] Graceful fallback — SMS failures don't block primary flow

### 15.5: WhatsApp 24h Reminder with Confirmation Request
- [x] Updated 24h reminder to send free-form message asking patient to confirm
- [x] Message includes: appointment details, YES/NO reply options, reschedule option
- [x] Creates confirmation log entry for tracking

### 15.6: Availability Enforcement
- [x] Added model-level validation for slot conflicts (no_overlapping_appointments)
- [x] Added model-level validation for working hours (within_working_hours)
- [x] Both validations on :create scope — applies to dashboard and WhatsApp booking
- [x] Cancelled appointments immediately free up slots for rebooking (excluded from conflict check)

### 15.7: Notification Ping Sound
- [x] Web Audio API ping sound plays when new notifications arrive
- [x] 30-second polling for notification count changes
- [x] Two-tone ascending ping (A5 → D6) with fade

### 15.8: Sidebar/Navbar Alignment Fix
- [x] Fixed navbar to span full width with inset-x-0 and pl-64
- [x] Border-bottom now runs seamlessly from edge to edge
- [x] Sidebar at z-30 overlays correctly

### 15.9: Settings Page Redesign
- [x] Tabbed interface: Practice Info, Office Hours, Notifications, Appearance
- [x] Practice tab: name, address, phone, email, map link, pricing with cash practice note
- [x] Hours tab: schedule table with status badges
- [x] Notifications tab: channel status (WhatsApp, Email, SMS) with confirmation/reminder indicators
- [x] Appearance tab: language toggle (EN/AF)
- [x] Full EN/AF translation support
- [x] Production-ready card-based design

## Phase 17: Enhancements (Future)
- [ ] Website "Book Appointment" button → WhatsApp flow
- [ ] Google Business Profile booking integration
- [ ] Voice customization (different AI voices)
- [ ] Wait-list management for cancelled slots
- [ ] Integration with dental practice management software
- [ ] A/B testing for greeting scripts and objection handling
- [ ] Advanced analytics dashboard with charts and trends

## Phase 18: Proactive Bot Messaging — No-Response Follow-Up ✅ COMPLETE

### 18.1: No-Response Follow-Up ✅
- [x] Migration: add `follow_up_count` (integer, default 0) and `follow_up_sent_at` (datetime) to conversations; index on follow_up_sent_at
- [x] Create `NoResponseFollowUpJob` — Solid Queue recurring job, every 5 minutes
  - Queries active WhatsApp conversations where last message is from the bot, not the patient
  - First follow-up after 10 min idle: warm check-in message in patient's language
  - Second follow-up after 90 min idle: closing message + marks conversation `stale`
  - Guard: follow_up_count < 2; uses with_lock to prevent double-sends
  - Bilingual (English/Afrikaans based on conversation.language)
- [x] Index on `conversations.follow_up_sent_at` for efficient job queries

### 18.2: Day-Before Appointment Reminder at 07:30 ✅
- [x] config/queue.yml recurring_tasks: `appointment_reminder_24h` cron `30 5 * * 1-5` (07:30 SAST, Mon–Fri)
- [x] 1h reminder: cron `0 6-15 * * 1-5` (hourly during clinic hours)
- [x] Morning confirmation: cron `0 6 * * 1-5` (08:00 SAST)
- [x] Existing reminder message includes YES/NO reply + reschedule offer; each reminder logged in ConfirmationLog

## Phase 19: Local vs Production Environment Parity

Currently the local development database and production (Supabase) are completely separate. This phase documents and optionally implements a bridge so the team can test with real production data safely.

### 19.1: Documentation
- [ ] Add `docs/ENVIRONMENTS.md` explaining: local dev DB vs production Supabase DB, why data doesn't sync, how to book through the production WhatsApp bot to see data on the production dashboard
- [ ] Add a note to `.env.example` explaining `DATABASE_URL` and the risk of pointing dev at production

### 19.2: Staging / Preview Environment (Optional)
- [ ] Create a separate Supabase project for staging (not the production DB)
- [ ] Add `STAGING_DATABASE_URL` to Railway — staging deploys use this DB, production keeps its own
- [ ] Seed staging DB with realistic but anonymised patient and appointment data via `db/seeds/staging.rb`
- [ ] Document the promotion path: staging → production release

### 19.3: One-Click Production Data Snapshot for Local Dev (Optional)
- [ ] Create a `bin/pull_prod_snapshot` script that dumps anonymised production rows (patients + appointments, PII redacted) into local DB
- [ ] Run with: `bin/pull_prod_snapshot` — replaces local dev data with a recent anonymised snapshot
- [ ] Guard: require explicit `CONFIRM=yes` env var to avoid accidental overwrites

## Phase 20: Enhanced Bulk WhatsApp Importer ✅ COMPLETE

Production-ready upgrade to the historical WhatsApp chat importer based on the developer specification, adding encoding safety, background processing, per-message deduplication, and identity mapping.

### 20.1: Encoding Safety ✅
- [x] `WhatsappImportService.sanitize_encoding` — normalises raw bytes to valid UTF-8 at every read boundary (import_file, import_upload, import_zip). Strips UTF-8 BOM, falls back to binary transcoding with `invalid: :replace` when bytes are not valid UTF-8
- [x] Fixes `Encoding::CompatibilityError` crash at `parse_txt_messages` line 207 (UTF-8 regex vs ASCII-8BIT string)
- [x] 50 MB upload size guard before reading file content (prevents OOM on huge uploads)

### 20.2: Format Support ✅
- [x] Android pattern: `dd/mm/yyyy, HH:mm - Sender: body`
- [x] iOS pattern: `[dd/mm/yyyy, HH:mm:ss] Sender: body`
- [x] Multi-line message continuation (lines without timestamp prefix are appended to previous message)
- [x] System message filtering (`<Media omitted>`, encryption notice)
- [x] Sender identity mapping: phone number pattern → stored as phone; display name → linked to Patient via `find_or_create_patient`

### 20.3: Background Processing for Large Files ✅
- [x] Files < 1 MB: processed inline, redirect with result summary (existing fast path)
- [x] Files ≥ 1 MB: saved to `tmp/imports/` and queued as `BulkWhatsappImportJob`
  - Job reads from temp file, runs full import, then deletes temp file in `ensure` block
  - On completion: creates a `Notification` (system category) with import summary visible in dashboard bell
  - On failure: creates a danger-level notification with the error message
  - Re-raises unexpected errors after notification so Solid Queue marks the job as failed for retry

### 20.4: Deduplication ✅
- [x] Conversation-level: deterministic `external_id` (SHA1 of source + phone) — re-importing same file updates existing Conversation row instead of creating a duplicate
- [ ] Per-message deduplication: add `message_fingerprints` JSONB column on conversations to track SHA1 of (timestamp + sender + body); skip messages already seen on re-import (Phase 20.4 extension)

### 20.5: Race Condition Fix ✅
- [x] `find_or_create_patient`: rescue `RecordNotUnique` / `RecordInvalid` and re-fetch — safe for concurrent imports of files with overlapping patients
