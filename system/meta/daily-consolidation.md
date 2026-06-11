---
id: meta-daily-consolidation
title: Daily memory consolidation pipeline
status: active
last_reviewed: 2026-06-05
---

# Daily memory consolidation

Automated end-of-day job that turns each day's Claude Code conversations into durable knowledge in `system/memory/`, without bloat or raw logs.

## Where it runs
On **Paul's PC** (where the Claude Code transcripts live: `~/.claude/projects/<project>/*.jsonl`). Windows Task Scheduler task **`IvoryMemoryConsolidation`**, daily 23:10, `StartWhenAvailable` (catches up if the PC was off). Script: `le-roux-repo/script/consolidate_memory.py`. Register/re-register with `script/setup_memory_task.ps1`.

## What it does
1. Finds transcripts changed since last processed (tracked in `system/memory/.consolidation_state.json`; **resumable** — state persists per transcript).
2. Extracts user+assistant text, sends to the Anthropic API (`claude-sonnet-4-6`) with a strict schema → only durable items (decision / rule / fact / definition / convention / config / preference / todo). Discards chatter, debugging, rejected options, and **never outputs PHI**.
3. Dedups against `system/memory/extracted-knowledge.md` (normalised statement match), appends new items, writes a dated digest in `system/memory/digests/`.
4. Idempotent: re-running re-processes only changed transcripts.

## Promotion to canonical
`extracted-knowledge.md` is the auto-captured raw feed. Curate the important items up into the right layer — a `decisions/` ADR, a `rules/` entry, or `reference/` — during normal work. The daily digest is the review surface.

## Roadmap (v2)
- Contradiction handling: mark superseded notes (`status: superseded`, `superseded_by`) instead of letting stale facts linger (e.g. old "Railway deployment" now wrong — it's the rig).
- Sync `system/` to the rig + a digest to WhatsApp/dashboard.
