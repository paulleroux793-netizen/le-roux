# CLAUDE.md

## Project Overview
This is a Ruby-based production application.

Act like a careful senior Ruby engineer working in an existing production codebase.
Prioritize stability, small safe changes, and preserving existing behavior unless explicitly instructed otherwise.

---

## Execution Order (MANDATORY)

Before making any changes:

1. Read this `CLAUDE.md` file first (source of truth for behavior and safety).
2. Read `ROADMAP.md` (source of truth for phases, tasks, and progress tracking).
3. Read AI prompt files and datasets:
   - `config/ai/claude_master_prompt.md`
   - `config/ai/afrikaans_language_dataset.json`
4. Inspect the relevant parts of the codebase before making any changes.

Do not start coding before completing these steps.

---

## Core Engineering Rules

- Do not change code that is already working unless required.
- Do not refactor unrelated parts of the codebase.
- Do not rename files, classes, or variables unless necessary.
- Do not introduce breaking changes.
- Prefer the smallest safe diff that solves the problem.
- Preserve all existing business logic unless explicitly instructed otherwise.
- If something looks risky, stop and explain before proceeding.

---

## Working Style

- Think step by step.
- Read the codebase before making edits.
- Reuse existing patterns and architecture.
- Keep implementations simple and maintainable.
- Favor clarity over cleverness.
- Fix root causes, not symptoms.
- Integrate new features naturally into the existing system.

---

## Ruby Conventions

- Follow existing project style first.
- Prefer small methods and clear responsibilities.
- Use service objects/POROs where appropriate.
- Keep controllers, models, and services cleanly separated.
- Avoid unnecessary metaprogramming.
- Avoid adding dependencies unless absolutely necessary.

---

## Safety Rules

- Do not modify:
  - database schema
  - environment config
  - credentials
  - deployment config
  - CI/CD
  - secrets
  unless explicitly instructed.

- Do not:
  - delete code or tests
  - change APIs or response formats
  - introduce broad refactors

---

## AI Chatbot & Multilingual Rules

The system includes an AI receptionist with multilingual support.

### Language Behavior
- Detect the user's language from the **first message**.
- If English → respond in English.
- If Afrikaans → respond in Afrikaans.
- If mixed → use dominant language.
- If unclear → ask user preference.

- Maintain the same language unless user switches.

### Afrikaans Dataset Usage
- Use `afrikaans_language_dataset.json` as a **style reference only**.
- Use it for:
  - natural phrasing
  - tone
  - vocabulary

- Do NOT:
  - treat it as business logic
  - override clinic rules
  - blindly translate English

---

## Booking & Calendar Rules (CRITICAL)

- NEVER confirm or create a booking before checking availability.
- ALWAYS check calendar via existing services first.
- NEVER invent available slots.
- If unavailable → suggest alternatives.
- If calendar fails → explain limitation and fallback safely.

- Only the chatbot handles booking unless escalation is required.

---

## After-Hours Booking Behaviour (PERMANENT — DO NOT CHANGE)

Working hours: **Monday–Friday, 08:00–17:00**. Closed weekends.

When a patient messages **outside working hours**, the bot MUST:

1. Clearly state the practice is closed and what the working hours are.
2. Still take the full booking (name, contact, reason, preferred time).
3. Confirm the booking was noted and that the team will confirm it when the practice opens.
4. Provide Dr Chalita's emergency number (071 884 3204) for urgent cases.

The bot must NEVER refuse to take a booking after hours.
This is enforced via `PromptBuilder#after_hours_block` — do not remove or weaken this method.

---

## Admin WhatsApp Control (Paul Le Roux — +27714475022)

Paul can manage the chatbot's behaviour by sending WhatsApp messages to the sandbox number.

- Any instruction Paul sends is stored in `PracticeSettings#admin_instructions` and injected at the **top** of the AI system prompt with absolute priority.
- Greetings (hi, hello, hey, etc.) show the help menu instead of saving as instructions.
- Commands: `show` (view instructions), `clear` (remove all), `help` (show commands).
- Handled by `AdminWhatsappService` — Paul's messages bypass the patient AI flow entirely.
- `ADMIN_WHATSAPP_NUMBER` env var must be set in Railway to `+27714475022`.

---

## Dashboard Language Feature

- Support English + Afrikaans language selector.
- Persist user preference.
- Render UI based on selected language.
- Default = English unless specified otherwise.

---

## Roadmap Execution Rules

- `ROADMAP.md` is the **single source of truth** for work tracking.

### Rules:
- Do NOT create a new roadmap.
- Always extend the existing roadmap.
- Follow the existing formatting style.
- Add new work as:
  - phases
  - sub-phases
  - checklist items

### Workflow:
1. Read roadmap
2. Identify relevant phase
3. Add missing tasks if needed
4. Implement
5. Mark tasks complete
6. Update roadmap continuously

---

## Debugging Rules

When debugging:

1. Identify the failing flow
2. Read relevant files
3. Explain root cause
4. Propose smallest safe fix
5. Add/update tests if needed
6. Verify no regressions

---

## Testing & Verification

Before completing any task:

- Run tests: `bin/rails test`
- Run linting: `bin/rubocop -f simple`
- Run security scan: `bin/brakeman --no-pager`
- Verify:
  - new feature works
  - no regressions
- Clearly summarize:
  - what changed
  - what did NOT change

---

## CI/CD (GitHub Actions)

The CI runs three jobs on every push to `main`:

| Job | Command |
|-----|---------|
| `scan_ruby` | `bin/brakeman --no-pager` + `bin/bundler-audit --update` |
| `lint` | `bin/rubocop -f github` |
| `test` | `bin/rails db:test:prepare test` |

**All three must pass before deploying.**

Common failure causes:
- `actions/checkout@v6` — does not exist, use `@v4`
- Missing env vars in test job — `SECRET_KEY_BASE`, `DATABASE_URL`, `TWILIO_*`, `ANTHROPIC_API_KEY` must be set as dummy values in CI env
- RuboCop offenses — always run `bin/rubocop -f simple` locally before pushing
- Brakeman warnings — run `bin/brakeman --no-pager` before pushing

Railway auto-deploys on push to `main` — CI must be green first.

---

## Commands

Use existing project commands:

- bundle install
- bundle exec rspec
- bundle exec rubocop
- bin/rails test
- bin/rails server
- bin/dev

Ask before running destructive commands.

---

## Git & Commits

- Always use Conventional Commits:
  - `feat(scope): description`
  - `fix(scope): description`
  - `refactor(scope): description`
  - `docs(scope): description`

- Commit after EACH task
- Do not batch commits
- Run tests before committing
- Never force push without permission

---

## Session Management

- Suggest `/compact` when context becomes noisy
- Maintain continuity across sessions
- Continue exactly where left off when user says "continue"

---

## Definition of Done

A task is complete only when:

- The issue is fully addressed
- The solution is minimal and safe
- No existing behavior is broken
- Tests pass
- Roadmap is updated
- Final summary clearly explains:
  - what changed
  - what was intentionally untouched
