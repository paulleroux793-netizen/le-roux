# UX market research — dental/medical PMS (Perplexity, 2026-06-06)

Source: Perplexity sonar-pro (Dentrix, Open Dental, GoodX, ExACT, Curve). Drives the
patient-journey user-friendliness loop. Each finding mapped to Ivory + an action.

## What people HATE (avoid / fix)
1. **Too many clicks per task** — booking opens multiple windows + separate OK/Save dialogs. → Ivory: estimate editor is inline; keep reducing clicks.
2. **Modal popups block flow** — "Are you sure?" + separate popups for notes/recall/estimates. → Prefer inline / side-panel over modals.
3. **Poor keyboard support** — illogical tab order, mouse-only dropdowns/date pickers, inconsistent shortcuts. → ⭐ BUILD keyboard-first (Paul's ask).
4. **Brittle/slow search** — exact-spelling only, no "search anything" box, family switch hidden. → Ivory has patient type-ahead; add global omnibox.
5. **Clumsy procedure-code entry** — full code typing or dropdowns, no favorites/templates/recent. → ⭐⭐ THE item: autocomplete + favorites + macros.
6. **Dense, noisy layout** — tiny buttons, legacy icons, buried key actions. → Visual hierarchy; prominent primary actions.
7. **Inconsistent navigation between modules** — different save/close placement, users re-learn. → SmartBack (done) helps; standardise patterns.
8. **Harsh error handling** — cryptic errors, form resets losing context. → Inline validation, focus the bad field, never lose context.

## What makes it feel FAST / FLOW (build)
1. **Global search + quick patient switch** — omnibox: name/phone/DOB/chart → jump anywhere; quick family toggle.
2. **Deep keyboard-first** — logical tab order, Enter=confirm, Esc=close, letter shortcuts (A=appt, T=treatment plan, P=payment), type-ahead on every dropdown. ⭐ Paul's ask.
3. **Predictive defaults + sticky settings** — auto-fill provider/op/duration/recall/codes from appointment type + past behaviour; remember last-used per user. ⭐⭐ Paul's predictive-preload.
4. **Inline, non-modal editing + autosave** — edit in place (drawer/side panel/inline row), save as you go.
5. **Smart procedure entry** — favourites bar for common codes, code BUNDLES/templates ("New-patient exam + BWX + Prophy"), auto tooth/surface presets, suggested next procedures. ⭐⭐
6. **Responsive UI** — instant calendar nav (no spinner), snappy ledger, background sync.
7. **Context-aware actions** — from the schedule, one click → post charge / collect payment / print estimate / start note / send reminder; no module-hunting.
8. **Clear visual hierarchy** — primary action prominent; current patient/provider/date always visible; guide the eye to the next step.

## Modern patterns older software LACKS (differentiators)
1. **Unified timeline / patient "story"** — one chronological stream (appts, notes, images, messages, consents, estimates, payments) vs siloed tabs.
2. **Command palette (Ctrl+K)** — type "est"→Create estimate, "note"→New note, from anywhere. ⭐ high-flow, achievable.
3. **Inline validation + guided workflows** — real-time hints + step indicators vs cryptic post-submit errors.
4. **Role-based dashboards** — reception/assistant/hygienist/doctor each see a tailored home.
5. **Multi-pane layouts** — pin patient summary while editing schedule; real-time updates from other staff.

## Ivory verdict + SHARPENED build order (flow-first)
Ivory already does: inline estimate editor, patient type-ahead, status-colour diary, dashboard flow board, SmartBack (just added). GAPS that hurt "flow" most, in build order:
1. **Smart code entry** — Enter→new line + autocomplete (code OR description) + favourites/recent + macro/bundle picker. (Paul + research #5/#5.)
2. **Command palette (Ctrl+K)** — global quick-action launcher. (research differentiator #2.)
3. **Keyboard shortcuts** across the journey (Enter/Esc/letter keys, type-ahead). (research #2.)
4. **Predictive pre-load** of codes from the appointment visit-type, AI-suggested + "review" flagged. (Paul + research #3.)
5. **Global omnibox search** (name/phone/DOB) + quick patient switch. (research #1.)
6. **Statement/estimate layout** — visual hierarchy, prominent primary actions. (Paul + research #6/#8.)
7. **Context-aware diary actions** (one-click charge/payment/estimate/note). (research #7.)
8. **Inline validation** that focuses the bad field + never loses context. (research #8.)
