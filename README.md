# Dr Chalita le Roux AI Receptionist

A premium AI receptionist system for **Dr Chalita le Roux Inc** (dental practice). Handles WhatsApp conversations, inbound/outbound voice calls, appointment booking, morning confirmations, and cancellation recovery — all focused on maximizing patient bookings.

## What It Does

### For Patients
- **WhatsApp chat** — instant, natural conversation to book, reschedule, or ask questions
- **Phone calls** — AI answers after hours and during overflow, guides toward booking
- **Appointment confirmations** — morning calls to confirm same-day appointments
- **Reminders** — automated WhatsApp reminders before appointments

### For the Practice
- **Reception dashboard** — view conversations, flagged patients, appointment stats
- **Cancellation tracking** — captures reasons (price, fear, timing, etc.) for analysis
- **Manual follow-up lists** — flagged patients sent to reception when AI can't reach them
- **Conversion analytics** — track booking rates, common objections, channel performance

## Architecture

```
                    ┌─────────────────────────────┐
                    │     Reception Dashboard      │
                    │    (Inertia.js + React)       │
                    └──────────┬──────────────────┘
                               │
┌──────────┐    ┌──────────────┴──────────────┐    ┌────────────────┐
│  Twilio   │───▶│        Rails 8 API          │───▶│ Google Calendar│
│ WhatsApp  │◀──│                              │◀──│    (Booking)   │
│  Voice    │    │  ┌────────────────────────┐  │    └────────────────┘
└──────────┘    │  │   Claude AI (Brain)     │  │
                │  │   - Intent recognition  │  │
                │  │   - Conversation mgmt   │  │
                │  │   - Tone & personality  │  │
                │  └────────────────────────┘  │
                │                              │
                │  ┌────────────────────────┐  │
                │  │   Solid Queue (Jobs)    │  │
                │  │   - Morning confirms    │  │
                │  │   - Reminders           │  │
                │  │   - WhatsApp fallbacks  │  │
                │  └────────────────────────┘  │
                └──────────────────────────────┘
```

## Tech Stack

| Component | Technology |
|---|---|
| Framework | Rails 8.1.3 |
| Ruby | 3.3.2 |
| Database | PostgreSQL (Supabase) |
| Frontend | Inertia.js + React + Vite |
| WhatsApp | Twilio WhatsApp Business API |
| Voice | Twilio Programmable Voice |
| AI Brain | Claude API (Anthropic) |
| Calendar | Google Calendar API |
| Background Jobs | Solid Queue |
| Deployment | Kamal (Docker) |

## Prerequisites

- Ruby 3.3.2
- Node.js 20+ and npm
- PostgreSQL
- Twilio account (phone number + WhatsApp Business)
- Google Cloud project with Calendar API enabled
- Google service account JSON key
- Anthropic API key (Claude)
- ngrok (for local Twilio webhook development)

## Setup

```bash
# Clone the repo
git clone https://github.com/your-username/dr-leroux-receptionist.git
cd dr-leroux-receptionist

# Install Ruby dependencies
bundle install

# Install JavaScript dependencies
npm install

# Setup database
bin/rails db:create db:migrate db:seed

# Copy environment variables
cp .env.example .env
# Edit .env with your credentials
```

## Environment Variables

```env
# Twilio
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_WHATSAPP_NUMBER=whatsapp:+14155238886

# Google Calendar
GOOGLE_CALENDAR_ID=your_calendar_id
GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}

# Anthropic (Claude AI)
ANTHROPIC_API_KEY=your_api_key

# Database
DATABASE_URL=postgresql://localhost/dr_leroux_receptionist_development

# App
BASE_URL=https://your-ngrok-url.ngrok.io
```

## Running the App

```bash
# Start Rails + Vite dev servers
bin/dev

# For Twilio webhooks in development:
ngrok http 3000
# Configure Twilio webhook URLs to your ngrok URL
```

## Testing

```bash
bundle exec rspec
```

## Key Business Rules

- **Pricing**: Only quote consultation (~R850 incl x-rays) and cleaning (~R1,300). All other treatments require a consultation.
- **Availability**: Never expose full calendar or number of open slots. Ask patient preference first, then match.
- **Tone**: Human, warm, friendly, slightly energetic. Education-based approach: educate, reassure, book.
- **Cancellations**: Always try to reschedule first. If declined, capture the reason.
- **Conversion focus**: Every interaction should guide toward booking a consultation.

## Project Status

### ✅ Completed Phases
- **Phase 1**: Project setup & infrastructure (Rails 8, PostgreSQL/Supabase, Twilio, environment variables, gems, RSpec)
- **Phase 2**: Database models & migrations
  - Patient model with phone validation
  - Appointment model with status enum and Google Calendar integration
  - CallLog model for tracking Twilio interactions
  - DoctorSchedule model with working hours (Mon-Fri 8-5, Sat 8-12, Sun closed)
  - All models have indexes, validations, and factory fixtures
  - Database uses Supabase with PgBouncer (prepared_statements: false)

### 🔄 In Progress
- **Phase 8**: Inertia.js + React + Vite + Tailwind CSS setup (frontend infrastructure)

### 📋 Pending
- **Phase 3**: Google Calendar Integration (available_slots, book_appointment, reschedule, cancel)
- **Phase 4**: AI Brain — Claude Integration (intent classification, entity extraction, conversation memory)
- **Phase 4.5**: WhatsApp Message Templates (6 pre-approved templates for compliance)
- **Phase 5**: WhatsApp Integration (webhook, booking flow, conversation management)
- **Phase 6**: Voice Call Integration (inbound/outbound, after-hours, overflow)
- **Phase 7**: Morning Confirmation System (daily 8-9am confirmation calls)
- **Phase 9**: Dashboard Pages & Features (appointments, conversations, flagged patients, analytics)
- **Phase 10**: Notifications & Reminders (templated WhatsApp messages)
- **Phase 11**: Security & Hardening (POPIA compliance, audit logging)
- **Phase 12**: Training Data & Continuous Improvement
- **Phase 13**: Deployment & Production (Kamal, production database, SSL)
- **Phase 14**: Enhancements (multi-language, website integration, wait-list management)

## Project Roadmap

See [ROADMAP.md](ROADMAP.md) for the full development plan with phases and detailed checklist.

## License

Private — All rights reserved. Dr Chalita le Roux Inc.
