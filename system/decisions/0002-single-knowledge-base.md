---
id: adr-0002
title: Single in-repo knowledge base + daily memory consolidation
status: accepted
date: 2026-06-05
---

## Context
Rules/knowledge/config/memory were scattered (agent's `~/.claude` memory, project `00-memory/`, root `KNOWLEDGE_BASE.md`, app config) — risk of duplication and contradiction. Paul wants ONE place everything feeds from, built to good practice, plus an automated daily memory update. Research (Perplexity, 2026-06-05) recommended docs-as-code single source of truth + a daily extract/dedup/supersede pipeline.

## Decision
- **`le-roux-repo/system/` is the single source of truth** (Markdown + YAML, in Git, deployed on the rig). Both the app and all AI agents read from it. The DB is only a derived cache of `system/config/`.
- Layers: `rules/`, `reference/`, `config/`, `decisions/` (ADRs), `memory/` (curated, not raw logs), `meta/`.
- The agent's `~/.claude` memory becomes a **thin index** pointing here; `00-memory/` and `KNOWLEDGE_BASE.md` are consolidated in and deprecated.
- **A daily consolidation job runs on Paul's PC** (where the Claude Code transcripts live) — extracts durable knowledge via the Anthropic API, dedups/merges into `system/memory/`, supersedes (never silently overwrites) on contradiction, idempotent with catch-up. See `meta/daily-consolidation.md`.

## Consequences
- Every durable decision/change is written here in the same change as the code; ADRs capture the "why".
- One place to change a rule/config; the app + agents converge automatically.
