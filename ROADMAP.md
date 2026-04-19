# Roadmap — Dr Chalita le Roux AI Receptionist

---

## Completed Phases

### Phase 1 — Project Setup & Infrastructure
- [x] Rails 8, PostgreSQL (Supabase), RSpec, Tailwind, Vite

### Phase 2 — Database Models & Migrations
- [x] Patient, Appointment, DoctorSchedule, Conversation, ConfirmationLog, CancellationReason, Notification

### Phase 3 — Google Calendar Integration
- [x] Available slots, booking, reschedule, cancel via GoogleCalendarService

### Phase 4 — Claude AI Brain
- [x] Intent classification, entity extraction, multi-turn conversation memory
- [x] FAQ knowledge base (hours, location, pricing, services, payment, emergency)

### Phase 4.5 — WhatsApp Message Templates
- [x] 6 pre-approved Twilio templates (confirmation, reminder 24h, reminder 1h, cancellation, reschedule, flagged alert)

### Phase 5 — WhatsApp Integration
- [x] Webhook, booking/reschedule/cancel flows, patient auto-registration
- [x] Local-first booking (DB is source of truth, Google Calendar is best-effort sync)
- [x] Booking confirmation message with practice directions

### Phase 6 — Voice Call Integration
- [x] Inbound/outbound, after-hours, overflow, TTS/STT

### Phase 7 — Morning Confirmation System
- [x] MorningConfirmationJob: daily batch calls + WhatsApp fallback

### Phase 8 — Frontend Setup
- [x] Inertia.js + React 18 + Vite + Tailwind brand token system

### Phase 9 — Dashboard Pages
- [x] Appointment calendar (FullCalendar week/day/month, drag-to-reschedule)
- [x] Reminders table (status tracking, manual send, window tabs)
- [x] Patients (list, search, create, detail view)
- [x] Conversations (WhatsApp + voice transcripts, reply, import)
- [x] Analytics page
- [x] Settings (office hours, pricing)
- [x] Global search (navbar, debounced, keyboard nav)
- [x] Notification bell (real-time, unread count)

### Phase 9.5 — Premium Brand Redesign
- [x] Teal brand palette, Inter font, card-based layout

### Phase 9.7–9.12 — Audits & Hardening
- [x] N+1 queries, caching strategy, data integrity

### Phase 9.14 — Design Consolidation
- [x] Local-first booking, reminders redesign, FullCalendar theming

### Phase 13 — Notifications & Automated Reminders
- [x] 24h/1h WhatsApp reminder jobs, in-app notification system

---

## Phase 14 — Multilingual Support (English + Afrikaans)

### 14.1 — Discovery & Audit
- [x] Read and follow `claude_master_prompt.md` as primary AI behavior spec
- [x] Audit current booking flow for calendar validation gaps
- [x] Audit current chatbot prompt for language support
- [x] Audit dashboard UI for i18n readiness
- [x] Identify Afrikaans dataset structure (`config/ai/afrikaans_language_dataset.json`)

### 14.2 — Afrikaans Dataset Integration
- [x] Load Afrikaans dataset samples into AI system prompt as language style reference — *Implemented: 8 curated health/work/family examples in `AFRIKAANS_STYLE_EXAMPLES` constant*
- [x] Add Afrikaans greeting/response examples to system prompt for tone guidance — *Implemented: `afrikaans_style_guide` method generates style block when language=af*
- [x] Document dataset usage rules (style reference only, not business logic source) — *Implemented: comment in constant + prompt text*

### 14.3 — Language Detection & Conversation Persistence
- [x] Detect language (EN/AF) from the first WhatsApp message — *Implemented: word-marker heuristic with 40+ Afrikaans markers*
- [x] Persist detected language on the Conversation record — *Implemented: `language` column (migration 20260416140000), `update_column` on first message*
- [x] Pass detected language to AI system prompt so responses match — *Implemented: `context[:language]` flows through to `build_system_prompt`*
- [x] Support language switching mid-conversation — *Implemented: `strong_language_signal?` prevents flip-flopping on borrowed words*
- [x] Generate Afrikaans responses when Afrikaans is detected — *Implemented: system prompt instructs "You MUST respond in Afrikaans" when language=af*
- [x] Generate English responses when English is detected — *Implemented: default language=en*

### 14.4 — Booking & Rescheduling Calendar Validation Hardening
- [x] Ensure AI response never claims a booking before `attempt_booking` succeeds — *Already implemented: `BOOKING_CLAIM_PHRASES` + rewrite logic*
- [x] When AI claims a booking but `attempt_booking` fails, rewrite response — *Enhanced: now language-aware with EN/AF fallback messages*
- [x] Add weekend rejection message in detected language — *Implemented: system prompt includes weekend rejection in both EN and AF*
- [ ] Return alternative available slots when requested slot is unavailable

### 14.5 — Dashboard Language Selector
- [x] Create translation system (`app/javascript/lib/translations.js`) — *Implemented: ~400 keys in EN + AF*
- [x] Create LanguageContext (`app/javascript/lib/LanguageContext.jsx`) — *Implemented: React context + localStorage*
- [x] Wrap app in LanguageProvider (`entrypoints/inertia.jsx`)
- [x] Dashboard page uses `t()` for all user-facing strings
- [x] DashboardLayout sidebar/nav uses `t()` for all labels
- [x] AppointmentFormModal uses `t()` for labels, validation, toasts
- [x] CancelAppointmentModal uses `t()` for labels, reasons, toasts
- [x] Settings page has language toggle (English / Afrikaans pill buttons)
- [x] Language persists in localStorage across page reloads
- [x] Extend translations to Reminders page — *Implemented: all strings, status chips, date formatting locale-aware*
- [x] Extend translations to Patients page — *Implemented: all strings, status badges, column headers*
- [x] Extend translations to Appointments page — *Implemented: all strings, status badges, date/time locale-aware*
- [x] Extend translations to Conversations page — *Implemented: all strings, import modal, relative time formatting*
- [x] Extend translations to Analytics page — *Implemented: all strings, stat labels, section titles*

### 14.6 — AI Prompt Multilingual Hardening
- [x] Update system prompt with language detection rules from master prompt — *Implemented: Language Rules section with CRITICAL marker*
- [x] Add Afrikaans response examples to system prompt — *Implemented: style guide block with dataset examples*
- [x] Add "do not mix languages" rule — *Implemented: "Do NOT mix English and Afrikaans in the same response"*
- [x] Reinforce calendar-first booking validation in prompt — *Already in place via booking rules section*
- [x] Reinforce "no weekends" rule in system prompt — *Implemented: 3 reinforcement points*
- [x] Remove Saturday hours from README (conflicted with actual behavior)
- [x] Add Afrikaans booking claim phrases to `BOOKING_CLAIM_PHRASES` — *8 Afrikaans phrases added*

### 14.7 — Search Bar & UI Polish
- [x] Fix search bar visibility (border/background contrast) — *Implemented: `brand-border` + `brand-surface/60`*
- [x] Remove FAQ section from Settings page (not user-facing config)
- [x] Add cancel/reschedule/create appointment actions to Dashboard

### 14.8 — QA & Regression Testing
- [x] Run full RSpec suite — verify 0 failures — *226 examples, 0 failures*
- [x] Run Vite build — verify 0 errors — *Built in 5.72s, 0 errors*
- [ ] Manual test: WhatsApp English booking flow
- [ ] Manual test: WhatsApp Afrikaans booking flow
- [ ] Manual test: Dashboard language toggle EN → AF → EN
- [ ] Manual test: Cancel appointment from dashboard
- [ ] Manual test: Create appointment from dashboard

---

## Planned Phases

### Phase 10 — Historical WhatsApp Import
- [ ] Bulk import of historical WhatsApp chat exports

### Phase 11 — Real Analytics
- [ ] Live SQL queries for booking stats, cancellation breakdown, channel performance

### Phase 12 — Billing & Invoicing
- [ ] PayFast/Stripe integration

### Phase 14–17 — Security Hardening & Deployment
- [ ] Auth, CSRF, rate limiting, Kamal production deploy
