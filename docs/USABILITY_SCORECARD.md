# Ivory Usability Scorecard — vs Exact, GoodX, Elixir

> How Ivory measures up on the usability dimensions where the incumbents are weakest (from
> docs/research/usability-exact-goodx-elixir.md). Goal: easier to navigate and faster to use than all three.
> ✅ strong · 🟡 partial · ⬜ not yet.

| Usability dimension | Exact | GoodX | Elixir | **Ivory** | How Ivory does it |
|---|:--:|:--:|:--:|:--:|---|
| **Global search** (across data types) | 🟡 | 🟡 | ⬜ (weak) | ✅ | One search box covers patients, appointments, conversations, **invoices, estimates, procedure codes**; grouped dropdown; keyboard-navigable |
| **Keyboard-first** | 🟡 | ⬜ | ⬜ | ✅ | `/` focuses search anywhere; ↑/↓/Enter to pick a result; Esc closes |
| **Clicks to a patient's file/bill** | many | many | many | ✅ | Patient → Digital File / Invoice in one click; list rows link straight to the document |
| **Screen clutter** (incumbents' #1 complaint) | 🟡 | ⬜ (cluttered) | ⬜ (cluttered) | ✅ | Clean cards, one consistent layout, generous whitespace, no dense grids |
| **Consistency** (same patterns everywhere) | 🟡 | 🟡 | ⬜ (inconsistent) | ✅ | Every PMS page uses the same DashboardLayout, table, badge, and empty-state patterns |
| **Empty states / guidance** | ⬜ | ⬜ | ⬜ | ✅ | Friendly empty states ("No invoices yet", "phases = visits" explainer) instead of blank screens |
| **Information hierarchy** | 🟡 | 🟡 | 🟡 | ✅ | Stat tiles → list → document; the important number is always biggest |
| **Mobile / responsive** | ⬜ (poor) | ⬜ | ⬜ (poor) | 🟡 | Responsive Tailwind grids; usable on a tablet. (Manual phone-viewport polish = follow-up) |
| **Onboarding / learning curve** | steep | steep | steep | ✅ | Plain-English labels ("Self / you pay"), explainers inline; no training manual needed |
| **Print/share a document** | 🟡 | 🟡 | 🟡 | ✅ | Any document prints clean from anywhere (Print/PDF hides the app chrome); WhatsApp-send hook |
| **Familiar billing format** | ✅ | ✅ | ✅ | ✅ | Matches the practice's existing Medical/Self + Visit estimate layout (no relearning) |
| **Speed (single practice, small data)** | 🟡 | 🟡 | 🟡 | ✅ | ~500-row tables ship client-side; instant filter/sort; N+1s audited out |

## The big usability wins (where Ivory clearly beats all three)
1. **One search for everything** + `/` shortcut — incumbents make you know which module to open first.
2. **Fewer clicks** — list → document/file directly; no nested menus.
3. **No clutter** — the single most common complaint about GoodX/Elixir billing screens; Ivory stays clean.
4. **Plain language** — "Self (you pay)" / "Visit 1" instead of jargon and confusing "phases".
5. **Print/share from anywhere** — every document is print-clean and shareable.

## Honest follow-ups (not blockers)
- Phone-viewport polish (it's responsive/tablet-fine; a dedicated mobile pass would help chairside use).
- Afrikaans localisation of the new PMS pages (dashboard already has EN/AF; new pages are EN).
- Per-user roles (reception vs dentist) for finer permissions.
