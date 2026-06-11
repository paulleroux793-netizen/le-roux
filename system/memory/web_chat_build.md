# WEB CHAT WIDGET — BUILD + SELF-IMPROVE-PRO LOOP (canonical task)
Paul, started 2026-06-09 ~21:30 SAST. DEADLINE: ready to demo 06:00 SAST 2026-06-10.

## GOAL
A custom embeddable web chat widget for the practice website that books appointments using the **SAME AI booking brain + SAME diary** as the WhatsApp bot, behind a **FLIP-SWITCH** (OFF by default; Paul flips it ON when happy → it appears on the website, automated, linked to the diary, same purpose as WhatsApp bookings). Then run self-improve-pro cycles (≤2 min apart) to build + harden + audit + stress-test until 06:00.

## THE FLOW (Paul, crystallised)
Visitor on the website → widget PROACTIVELY engages (sales + educational, grab attention early, don't just wait for a WhatsApp tap) → gathers info (reason for visit, new/existing, name, WhatsApp number, consent) → proposes REAL available slots from the live diary → books into the diary → **AFTER the visitor agrees in the widget, send via WhatsApp**: directions + practice address + Google Maps link + **intake form link** + **appointment details**. WhatsApp is the delivery channel for the confirmation pack.

## HARD GUARDS — identical to WhatsApp, regression-gated every cycle
- NO double-booking (same per-provider exclusion constraint as WhatsApp).
- NO weekends (Mon–Fri only, via DoctorSchedule / AvailabilityService).
- NO after-hours (within DoctorSchedule hours, ~8am–5pm).
- Same compliance filter (banned phrases, no after-hours/24-7/weekend promises, Roodepoort positioning, canonical numbers/address).
- POPIA: minimal data; consent BEFORE collecting phone; no medical detail in chat; encrypt phone at rest; privacy notice in widget.
- TESTING: NEVER send a real WhatsApp/SMS (stub it). NEVER change the live WhatsApp path's behaviour. NEVER recreate the live web container. Build + test on STAGING (:3001); deploy code-only to live behind the OFF flag.

## ARCHITECTURE
- Backend: `WebChatService` reuses `AiService` (channel: :web) for conversation/intent/entities/availability injection, and the SAME availability + appointment-creation guards as WhatsApp (extract a shared booking core if needed — regression-gate the whatsapp specs). `WebChatSession` model = anonymous session memory (jsonb messages, like Conversation). Endpoint `POST /api/v1/web_chat` (+ `/confirm`), CORS for the website origin, Rack::Attack rate-limit, signed embed token, channel:"web". On booking-agreement → reuse a WhatsApp sender to deliver the pack (directions/address/maps/intake-form/details).
- Frontend: embeddable widget = a single `<script>` snippet mounting a **Shadow-DOM** web component (CSS-isolated) served from Ivory; iframe fallback. A PREVIEW page on Ivory (`/web_chat_preview`, behind login) so Paul can TEST it tomorrow. Proactive triggers (8–12s / 40–60% scroll / exit-intent desktop; 10–15s / sticky bar mobile), human-avatar teaser, quick-reply chips, sales + educational copy, mobile-first.
- FLIP SWITCH: `WEB_CHAT_ENABLED` (env/Setting, default OFF). Provide the embed snippet for the SEO project's website when Paul says go.

## SALES + EDUCATIONAL (Perplexity-backed — full research in web_chat_research.md)
Opening hook: "Book your visit in under 60 sec — real-time availability, 24/7. I'll send everything to your WhatsApp." Branches: Book / Ask a question / Costs & medical aid / Nervous about the dentist. Use: social proof, real-time availability ("2 slots left this week"), friction reduction ("just 3 details"), anxiety reduction, educational micro-flows (whitening, pricing ranges, anxiety-friendly consult), inline confirmation, progress hints, "skip to booking" CTA, WhatsApp delivery. Metrics: open-rate, engagement-rate, booking-intent-rate, completed-booking-rate, drop-off step, channel preference, after-hours share.

## LOOP CYCLE (self-improve-pro) — each iteration
1. Read this doc + the last `[WEBCHAT-CYCLE …]` lines in build-status.md (dedup if <90s old).
2. Pick the single highest-value item: a BUILD gap (backend → model → endpoint → widget → preview → flag → WhatsApp pack) until MVP, then AUDIT/STRESS-TEST scenarios + polish.
3. Benchmark vs best-in-class (Perplexity) when adding a behaviour.
4. Implement ONE focused change on STAGING.
5. Verify for real + REGRESSION GATE: whatsapp_service_spec stays green, new web_chat specs pass, and the 3 guards hold (weekend/after-hours/double-book). Vite build must SUCCEED before any restart.
6. Log `[WEBCHAT-CYCLE <YYYY-MM-DD HH:MM>] <what> | <verify>` to build-status.md. ScheduleWakeup(100s).

## STRESS SCENARIOS (rotate; each must pass)
weekend request rejected + offers Mon–Fri · after-hours request rejected + offers in-hours · double-book race (two confirm same slot → one fails gracefully) · no availability → suggests next day · mid-booking abandonment → resumes · hostile/spam/off-topic input → safe canned reply, no booking · 20-turn memory retention · mobile layout · consent gate before phone · WhatsApp pack actually assembled (directions/address/maps/intake/details) · compliance filter on every outbound line · identical entities vs the WhatsApp brain for the same input.

## DONE = MVP built + flip-switch + preview page + all guards green + stress scenarios pass + WhatsApp pack wired. Then keep polishing sales/education until 06:00.
