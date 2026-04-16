# Dr Chalita le Roux AI Receptionist

A production-grade AI receptionist system for **Dr Chalita le Roux Inc** (dental practice in Pretoria, South Africa). Handles WhatsApp conversations, inbound/outbound voice calls, appointment booking, morning confirmations, cancellation recovery, and a full reception dashboard — all focused on maximising patient bookings and reducing no-shows.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Running the App](#running-the-app)
- [WhatsApp Commands (Patient Guide)](#whatsapp-commands-patient-guide)
- [Dashboard Pages](#dashboard-pages)
- [Appointment Lifecycle](#appointment-lifecycle)
- [Reminder System](#reminder-system)
- [Background Jobs](#background-jobs)
- [API Endpoints & Webhooks](#api-endpoints--webhooks)
- [Environment Variables](#environment-variables)
- [Testing](#testing)
- [Key Business Rules](#key-business-rules)
- [Project Status](#project-status)
- [Deployment](#deployment)
- [License](#license)

---

## Features

### For Patients (via WhatsApp / Voice)

| Action | What to say | What happens |
|---|---|---|
| **Book an appointment** | "I want to book an appointment" or "Book me for Friday at 11am" | AI asks for preferred day/time, checks availability against doctor schedule, creates the appointment, sends confirmation |
| **Reschedule** | "I want to reschedule" or "Can I move my appointment to Monday?" | AI finds the existing appointment, asks for new time, updates both local DB and Google Calendar |
| **Cancel** | "I want to cancel" or "Cancel my appointment" | AI tries to reschedule first; if patient insists, captures the cancellation reason (cost/fear/timing/transport) and cancels |
| **Confirm** | "Confirm" or "Yes I'll be there" | Marks the appointment as confirmed, logs it in the confirmation history |
| **Ask a question** | "What are your hours?" / "How much is a consultation?" / "Where are you located?" | AI answers from the FAQ knowledge base and gently guides toward booking |
| **Emergency** | "I'm in pain" / "Emergency" / "My tooth is bleeding" | Immediate flag to reception with urgent follow-up |

### For the Practice (Reception Dashboard)

- **Live appointment calendar** — FullCalendar week/day/month views with drag-to-reschedule
- **Pre-appointment reminders** — Table of all upcoming appointments with status tracking (Pending → Sent → Confirmed → Cancelled)
- **Patient management** — Patient list with search, creation, medical history
- **Conversation history** — View all WhatsApp and voice conversations per patient
- **Notifications** — Real-time bell with unread count for new bookings, cancellations, flagged patients
- **Analytics** — Booking stats, cancellation breakdown, channel performance
- **Global search** — Find patients, appointments, and conversations from the navbar
- **Morning confirmations** — Automated batch calls + WhatsApp fallback for same-day appointments

---

## Architecture

```
                    ┌──────────────────────────────────┐
                    │      Reception Dashboard         │
                    │   (Inertia.js + React + Vite)    │
                    │                                  │
                    │  Calendar · Reminders · Patients │
                    │  Conversations · Analytics       │
                    └──────────┬───────────────────────┘
                               │
┌──────────┐    ┌──────────────┴──────────────┐    ┌──────────────────┐
│  Twilio   │───▶│        Rails 8 API          │───▶│  Google Calendar  │
│ WhatsApp  │◀──│                              │◀──│  (best-effort     │
│  Voice    │    │  ┌────────────────────────┐  │    │   sync)           │
└──────────┘    │  │   Claude AI (Brain)     │  │    └──────────────────┘
                │  │   - Intent classifier   │  │
                │  │   - Entity extraction   │  │    ┌──────────────────┐
                │  │   - Response generator  │  │    │    PostgreSQL     │
                │  │   - Multi-turn memory   │  │───▶│   (Supabase)     │
                │  └────────────────────────┘  │    │   Source of truth │
                │                              │    └──────────────────┘
                │  ┌────────────────────────┐  │
                │  │   Solid Queue (Jobs)    │  │
                │  │   - Morning confirms    │  │
                │  │   - 24h/1h reminders    │  │
                │  │   - WhatsApp fallbacks  │  │
                │  └────────────────────────┘  │
                └──────────────────────────────┘
```

### Data Flow: WhatsApp Booking

```
Patient sends "Book me Friday 11am"
  → Twilio webhook POST /webhooks/whatsapp
  → WhatsappController#incoming
  → WhatsappService#handle_incoming
    → AiService#classify_intent (→ intent: "book", entities: {date: "2026-04-17", time: "11:00"})
    → AiService#generate_response (→ conversational reply)
    → handle_booking
      → attempt_booking
        → Check: slot is in the future ✓
        → Check: DoctorSchedule working hours ✓
        → Check: no conflict in Appointment table ✓
        → Appointment.create! (local DB — source of truth)
        → ConfirmationLog.create! (tracks on reminders page)
        → sync_to_google_calendar (best-effort, swallows errors)
        → send_confirmation_template (WhatsApp template via Twilio)
  → TwiML response back to patient
```

---

## Tech Stack

| Component | Technology |
|---|---|
| Framework | Rails 8.1.3 (Ruby 3.3.2) |
| Database | PostgreSQL (Supabase with PgBouncer) |
| Frontend | Inertia.js + React 18 + Vite |
| Styling | Tailwind CSS (brand token system) |
| Calendar | FullCalendar (week/day/month + drag-drop) |
| WhatsApp | Twilio WhatsApp Business API |
| Voice | Twilio Programmable Voice (TTS/STT) |
| AI Brain | Claude API (Anthropic) — claude-sonnet-4-20250514 |
| Calendar Sync | Google Calendar API (service account) |
| Background Jobs | Solid Queue (recurring + one-off) |
| Notifications | Sonner (toast) + in-app bell dropdown |
| Deployment | Kamal (Docker) |

---

## Prerequisites

- **Ruby** 3.3.2
- **Node.js** 20+ and npm
- **PostgreSQL** (or Supabase URL)
- **Twilio account** — phone number + WhatsApp Business sandbox or production number
- **Google Cloud project** — Calendar API enabled + service account JSON key
- **Anthropic API key** — for Claude AI
- **ngrok** — for local Twilio webhook development

---

## Setup

```bash
# 1. Clone the repository
git clone https://github.com/your-username/dr-leroux-receptionist.git
cd dr-leroux-receptionist

# 2. Install Ruby dependencies
bundle install

# 3. Install JavaScript dependencies
npm install

# 4. Set up environment variables
cp .env.example .env
# Edit .env with your credentials (see Environment Variables section)

# 5. Create database, run migrations, seed doctor schedule
bin/rails db:create db:migrate db:seed

# 6. Verify seeds
bin/rails runner "puts DoctorSchedule.active.count"
# Should output: 6 (Mon-Sat schedules)

# 7. Run tests
bundle exec rspec
```

### Seeding

The seed file creates the doctor's working hours:
- **Monday–Friday**: 08:00–17:00, lunch break 12:00–13:00
- **Saturday & Sunday**: Closed

These schedules are required for WhatsApp booking to work — `attempt_booking` checks `DoctorSchedule` before creating an appointment.

---

## Running the App

```bash
# Start Rails + Vite dev servers (uses Procfile.dev)
bin/dev

# In a separate terminal, start ngrok for Twilio webhooks:
ngrok http 3000

# Configure Twilio webhooks to your ngrok URL:
#   WhatsApp: POST https://your-ngrok-url.ngrok.io/webhooks/whatsapp
#   Voice:    POST https://your-ngrok-url.ngrok.io/webhooks/voice
```

### Accessing the Dashboard

Open `http://localhost:3000` in your browser. The dashboard home page shows today's appointments, pending confirmations, and key stats.

**Navigation:**
- `/` or `/dashboard` — Dashboard home
- `/appointments` — Appointment calendar + list
- `/reminders` — Pre-appointment reminders with status tracking
- `/patients` — Patient list and management
- `/conversations` — WhatsApp + voice conversation history
- `/analytics` — Booking stats and cancellation breakdown
- `/settings` — Office hours, pricing reference, FAQ

---

## WhatsApp Commands (Patient Guide)

These are natural-language messages patients can send via WhatsApp. The AI understands variations — these are examples, not rigid commands.

### Booking an Appointment

```
Patient: "I'd like to book an appointment"
Bot:     "I'd love to help! What day and time work best for you?"

Patient: "Friday at 11am"
Bot:     "Perfect! I have you booked for Friday, Apr 17 at 11:00 AM.
          You'll receive a confirmation shortly."
```

The bot checks:
1. Is the slot in the future?
2. Is the practice open? (Mon-Fri 8-5, closed Sat & Sun, lunch 12-1)
3. Is the slot available? (no overlapping appointments)

If any check fails, the bot says: *"Sorry — I couldn't lock that slot in. Could you try a different time, or call the practice directly?"*

### Rescheduling

```
Patient: "I need to reschedule my appointment"
Bot:     "Of course! When would you prefer instead?"

Patient: "How about Wednesday at 2pm?"
Bot:     "Done! Your appointment has been moved to Wednesday, Apr 22 at 2:00 PM."
```

### Cancelling

```
Patient: "I want to cancel my appointment"
Bot:     "I understand. Before we cancel, would you like to reschedule
          to a different time instead?"

Patient: "No, just cancel please"
Bot:     "Your appointment has been cancelled. Could I ask what prompted
          the change? This helps us improve."

Patient: "It's too expensive"
Bot:     "I understand. Our consultation is R850 and includes x-rays —
          it's a thorough assessment. We also accept medical aid.
          Would you like to reconsider?"
```

The bot captures the cancellation reason (cost, fear, timing, transport, other) for analytics.

### Confirming

```
Patient: "Confirm"
Bot:     "Great, your appointment is confirmed! See you then."
```

This updates the appointment status to `confirmed` and logs it in the confirmation history.

### Asking Questions (FAQ)

```
Patient: "What are your hours?"
Bot:     "We're open Monday to Friday 8am–5pm, and Saturdays 8am–12pm.
          We're closed on Sundays."

Patient: "How much is a consultation?"
Bot:     "A consultation is R850 and includes x-rays. Would you like
          to book one?"

Patient: "Where are you located?"
Bot:     "Dr Chalita le Roux Inc is located in Pretoria. Please call
          or WhatsApp us for exact directions."
```

### Emergencies

```
Patient: "I'm in severe pain"
Bot:     "I'm sorry you're dealing with that. If this is urgent, please
          call the practice directly now so we can assist you as quickly
          as possible."
```

Emergencies are flagged immediately to reception via WhatsApp alert.

---

## Dashboard Pages

### Appointment Calendar (`/appointments`)

- **Week/Day/Month** views via FullCalendar
- **Drag-and-drop** to reschedule (PATCHes the server)
- **Click** any event to view details
- **Create** appointments via the "New Appointment" modal
- **Search** by patient name, phone, reason, or status
- **Status chips**: Scheduled (blue), Confirmed (green), Completed (dark), Cancelled (red), No Show (grey), Rescheduled (amber)
- **Real-time cache**: appointments created via WhatsApp appear after a page reload

### Pre-Appointment Reminders (`/reminders`)

- **Table view** of all upcoming appointments in the next 7 days
- **Status chips**: Pending, Sent, Confirmed, Cancelled, No Answer
- **Sort** by patient name, appointment time, reason, or status
- **Search** by patient, phone, or status
- **Window tabs**: Today / Tomorrow / This Week
- **Actions per row**: Send WhatsApp, Call, Confirm, Cancel
- **Stat cards**: Total upcoming, Pending, Confirmed, Today
- **Pagination**: 10 per page

### Patients (`/patients`)

- Searchable patient list with name, phone, last appointment
- Create new patients with the registration form
- View patient detail: appointment history, conversations, medical info

### Conversations (`/conversations`)

- View all WhatsApp and voice transcripts
- Reply to WhatsApp conversations from the dashboard
- Import historical WhatsApp chat exports

### Analytics (`/analytics`)

- Booking rate by channel (WhatsApp vs Voice)
- Cancellation breakdown by reason
- Appointment volume trends

---

## Appointment Lifecycle

```
┌──────────┐    ┌───────────┐    ┌───────────┐    ┌───────────┐
│ Scheduled │───▶│ Confirmed │───▶│ Completed │    │ No Show   │
└──────────┘    └───────────┘    └───────────┘    └───────────┘
     │               │                                  ▲
     │               │                                  │
     ▼               ▼                                  │
┌──────────┐    ┌─────────────┐                        │
│ Cancelled│    │ Rescheduled │────────────────────────┘
└──────────┘    └─────────────┘
```

| Status | Meaning |
|---|---|
| `scheduled` | Appointment created, awaiting confirmation |
| `confirmed` | Patient confirmed (via WhatsApp, voice, or dashboard) |
| `completed` | Appointment took place |
| `cancelled` | Patient or practice cancelled (reason captured) |
| `no_show` | Patient didn't show up |
| `rescheduled` | Moved to a new time |

---

## Reminder System

### Automatic Reminders

| Trigger | What happens |
|---|---|
| **Appointment created** | ConfirmationLog created (status: Pending on reminders page) |
| **Morning batch (08:00)** | `MorningConfirmationJob` calls each same-day patient; WhatsApp fallback if no answer |
| **24 hours before** | `AppointmentReminder24hJob` sends WhatsApp reminder template |
| **1 hour before** | `AppointmentReminder1hJob` sends WhatsApp reminder template |

### Manual Reminders (Dashboard)

From the Reminders page (`/reminders`), the receptionist can:
- **Send WhatsApp** — dispatches a reminder template immediately
- **Call** — triggers an outbound voice confirmation
- **Confirm** — marks the appointment as confirmed (one-click)
- **Cancel** — opens the cancellation modal with reason capture

### Status Flow on Reminders Page

```
Pending → Sent → Confirmed
                → No Answer (flagged for follow-up)
                → Cancelled
```

---

## Background Jobs

All jobs run via **Solid Queue** (Rails 8 built-in).

| Job | Schedule | What it does |
|---|---|---|
| `MorningConfirmationJob` | Daily 08:00 | Calls each same-day patient to confirm; falls back to WhatsApp |
| `AppointmentReminder24hJob` | Daily | Sends WhatsApp reminder for tomorrow's appointments |
| `AppointmentReminder1hJob` | Hourly | Sends WhatsApp reminder for appointments in 45-75 min window |

---

## API Endpoints & Webhooks

### Webhooks (Twilio → Rails)

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/webhooks/whatsapp` | Incoming WhatsApp messages |
| `POST` | `/webhooks/voice` | Incoming voice calls |
| `POST` | `/webhooks/voice/gather` | Voice speech input |
| `POST` | `/webhooks/voice/status` | Call status updates |
| `POST` | `/webhooks/voice/confirmation` | Outbound confirmation call |
| `POST` | `/webhooks/voice/confirmation_gather` | Confirmation call speech input |

### Dashboard Routes (Inertia)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Dashboard home |
| `GET` | `/appointments` | Calendar + list |
| `POST` | `/appointments` | Create appointment |
| `PATCH` | `/appointments/:id` | Update / reschedule |
| `PATCH` | `/appointments/:id/cancel` | Cancel with reason |
| `PATCH` | `/appointments/:id/confirm` | One-click confirm |
| `GET` | `/reminders` | Reminders table |
| `POST` | `/reminders/:id/send` | Dispatch manual reminder |
| `GET` | `/patients` | Patient list |
| `POST` | `/patients` | Create patient |
| `GET` | `/conversations` | Conversation list |
| `GET` | `/search?q=` | Global search |
| `GET` | `/analytics` | Analytics dashboard |

---

## Environment Variables

```env
# === Twilio ===
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_WHATSAPP_NUMBER=whatsapp:+14155238886
TWILIO_PHONE_NUMBER=+1XXXXXXXXXX

# === Google Calendar ===
GOOGLE_CALENDAR_ID=your_calendar_id
GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}

# === Anthropic (Claude AI) ===
ANTHROPIC_API_KEY=sk-ant-xxxxxxxx

# === Database ===
DATABASE_URL=postgresql://localhost/dr_leroux_receptionist_development

# === WhatsApp Template SIDs (from Twilio Console) ===
WHATSAPP_TPL_CONFIRMATION=HXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
WHATSAPP_TPL_REMINDER_24H=HXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
WHATSAPP_TPL_REMINDER_1H=HXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
WHATSAPP_TPL_CANCELLATION=HXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
WHATSAPP_TPL_RESCHEDULE=HXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
WHATSAPP_TPL_FLAGGED_ALERT=HXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# === Reception ===
RECEPTION_WHATSAPP_NUMBER=+27XXXXXXXXXX

# === App ===
BASE_URL=https://your-ngrok-url.ngrok.io
```

### Notes on Environment Variables

- **Google Calendar is optional** — if `GOOGLE_CALENDAR_ID` is not set, appointments are created locally only (they still show on the in-app calendar). Google sync is best-effort.
- **WhatsApp templates** require Twilio approval. Without them, the bot still works for conversation but won't send proactive template messages (confirmations, reminders).
- **ngrok** is only needed for local development with Twilio webhooks.

---

## Testing

```bash
# Run the full test suite
bundle exec rspec

# Run a specific spec file
bundle exec rspec spec/services/whatsapp_service_spec.rb

# Run with verbose output
bundle exec rspec --format documentation

# Build frontend (verify no JS errors)
npx vite build
```

### Test Coverage

| Area | Specs |
|---|---|
| WhatsApp booking flow | 12 examples (new patient, reuse, booking, conflicts, outside hours, fallbacks) |
| Appointment CRUD | 13 examples (create, update, cancel, confirm, calendar data) |
| Reminders | 8 examples (index, scoping, send dispatch, error handling) |
| AI service | Unit tests with mocked Claude responses |
| Models | Validations, scopes, callbacks |

---

## Key Business Rules

| Rule | Detail |
|---|---|
| **Pricing** | Only quote consultation (R850 incl. x-rays) and cleaning (R1,300). Everything else: "needs a consultation first." |
| **Availability** | Never expose full calendar. Ask patient preference first, then match against schedule. |
| **Tone** | Warm, friendly, slightly energetic, reassuring. Education-based approach: educate → reassure → book. |
| **Cancellations** | Always try to reschedule first. If declined, capture the reason (cost/fear/timing/transport/other). |
| **Working hours** | Mon–Fri 08:00–17:00. Closed on weekends (Sat & Sun). Lunch break 12:00–13:00 (Mon–Fri). |
| **Slot duration** | 30 minutes per appointment. |
| **Conversion focus** | Every interaction should naturally guide toward booking a consultation. |

---

## Project Status

### Completed

| Phase | Description |
|---|---|
| 1 | Project setup & infrastructure (Rails 8, PostgreSQL, Twilio, RSpec) |
| 2 | Database models & migrations (Patient, Appointment, DoctorSchedule, Conversation, etc.) |
| 3 | Google Calendar integration (available slots, booking, reschedule, cancel) |
| 4 | Claude AI brain (intent classification, entity extraction, multi-turn memory) |
| 4.5 | WhatsApp message templates (6 pre-approved Twilio templates) |
| 5 | WhatsApp integration (webhook, booking/reschedule/cancel flows) |
| 6 | Voice call integration (inbound/outbound, after-hours, overflow) |
| 7 | Morning confirmation system (daily batch calls + WhatsApp fallback) |
| 8 | Inertia.js + React + Vite + Tailwind setup |
| 9 | Dashboard pages (calendar, patients, conversations, analytics, settings) |
| 9.5 | Premium brand redesign |
| 9.7–9.12 | Audits & hardening (N+1, cache, data integrity) |
| 9.14 | Design consolidation + local-first booking + reminders redesign |
| 13 | Notifications & automated reminders (24h/1h WhatsApp jobs) |

### In Progress

- **Phase 9.14**: Component library, inline-style purge, per-page token audit
- **Phase 9.6**: React Hook Form validation, TanStack table, patient medical history

### Planned

- **Phase 10**: Import historical WhatsApp chats
- **Phase 11**: Real analytics with live SQL queries
- **Phase 12**: Billing & invoicing (PayFast/Stripe)
- **Phase 14–17**: Security hardening, deployment, enhancements

See [ROADMAP.md](ROADMAP.md) for the full development plan.

---

## Deployment

```bash
# Production deployment via Kamal (Docker)
kamal setup    # First-time server setup
kamal deploy   # Deploy latest code

# Environment variables are set via Kamal secrets or .env on the server
```

Production uses:
- **Solid Cache** for page caching (replaces dev MemoryStore)
- **Solid Queue** for background jobs
- **PostgreSQL** on Supabase

---

## License

Private — All rights reserved. Dr Chalita le Roux Inc.
