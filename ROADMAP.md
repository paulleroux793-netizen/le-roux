# Dr Chalita le Roux AI Receptionist — Development Roadmap

## Current Status: 🚧 Dashboard Stabilization & UI Refresh Track Planned

**Completed**: Phases 1-9, 9.5, 13 (core system + channel integrations + confirmations + current dashboard foundation)
**Current Priority**: Phases 9.7-9.13 (audit, data integrity fixes, calendar polish, N+1 review, status removal, full blue theme rollout)
**Deferred Until After This Track**: Phase 10 (Import Historical Chats), Phase 11 (Data Capture & Analytics), Phase 12 (Billing), Phases 14-17 (Security, Training, Deployment, Enhancements)

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
- [ ] **Reminders tab** on Appointment detail page: show scheduled reminder status (24h sent ✓ / 1h sent ✓ / pending)
- [ ] Manual "Send Reminder Now" button: triggers `AppointmentReminder24hJob` or `AppointmentReminder1hJob` for a single appointment
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
- [ ] Create a conventional commit for the audit baseline before moving into bug-fix work

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

## Phase 9.13: Blue Brand Palette Rollout & Dashboard Theme Refresh

Apply the new palette consistently across the app using the provided screenshots as the design-language reference for a clean, modern, trustworthy clinic dashboard.

- [x] Replace the current warm brown/taupe brand tokens with the new source-of-truth palette
- [x] Define and apply the palette consistently:
  - Primary `#3164DE`
  - Secondary `#769BF5`
  - Accent light `#B1C5F6`
  - Background light `#D6E0F8`
  - White `#FFFFFF`
  - Dark text `#393C4D`
  - Muted text/borders `#8592AD`
  - Success `#19A14E`
  - Error/warning `#EF6161`
- [x] Restyle the sidebar, top navigation, cards, stats panels, forms, tables, modals, badges, and interactive controls to use the new palette consistently
- [x] Keep backgrounds light and airy, with white content surfaces and restrained use of saturated color
- [x] Use the primary blue for main CTAs, active navigation, highlights, and key interactive states
- [x] Use the softer blues for section backgrounds, subtle emphasis, selected states, and supportive accents
- [x] Keep headings and primary text high-contrast with `#393C4D`; use `#8592AD` for muted labels, borders, and helper copy
- [x] Restrict `#19A14E` and `#EF6161` to status communication only
- [x] Apply the new design direction to the calendar so it feels cohesive with the rest of the dashboard
- [x] Run a full consistency pass across the major pages and shared components
- [x] Create a conventional commit after the theme rollout is complete

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
