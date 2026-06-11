# `system/` — the single source of truth

Everything that defines **how Ivory works and how we build it** lives here, in one place, in Git. **Both the running app *and* every AI agent read from this directory.** Nothing authoritative lives anywhere else — no scattered memory folders, no contradictory copies. The Postgres database is only a fast-lookup *cache* derived from `config/`.

> Decided 2026-06-05 (Paul). Research-backed (docs-as-code single source of truth). Replaces the old scattered stores: the project `00-memory/`, root `KNOWLEDGE_BASE.md`, and the agent's separate `~/.claude` memory (now a thin index pointing here).

## Layout

| Dir | What | Changes |
|---|---|---|
| `rules/` | **Non-negotiable laws** — PHI, "never write to Elixir", banned phrases, compliance. Prescriptive, rarely change. | Rare, reviewed |
| `reference/` | **How/why knowledge** — data architecture, where data lives, dental/billing workflows, module overviews. Descriptive. | As the system grows |
| `config/` | **What the APP consumes at runtime** — the canonical operational config (pricing, hours, holidays…). The app reads this; the DB caches it. | When practice values change |
| `decisions/` | **ADRs** — the decision log: what we chose and *why*, numbered, append-only. | One per durable decision |
| `memory/` | **Curated durable facts** the agents must remember across sessions (build status, gotchas). NOT raw chat logs. | Daily consolidation + as we work |
| `meta/` | Process docs — how to update this directory, the daily-consolidation pipeline. | Rare |

## Rules for using it
1. **This directory is canonical.** If a fact matters beyond one conversation, it belongs here — not in a chat, not in a separate memory store.
2. **Durable change → write it here** (the right layer) in the same change as the code. Decisions get an ADR in `decisions/`.
3. **The app reads `config/`** (via an initializer); the DB is a derived cache, kept in sync by a rake task + tests. Never invent config keys not declared here.
4. **Daily consolidation** (`meta/daily-consolidation.md`) reviews each day's conversations and updates `memory/` — extracting only durable knowledge, never raw logs, superseding (not silently overwriting) on contradiction.

## Where to look first
- New here / resuming work → `reference/data-architecture.md` (where everything lives) + `memory/build-status.md` (current state).
- "Can I do X?" → `rules/`.
- "Why is it this way?" → `decisions/`.
