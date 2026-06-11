---
id: adr-0001
title: Build Ivory as an editable working copy of read-only Elixir
status: accepted
date: 2026-06-05
---

## Context
Elixir (Firebird) is the practice's live system; reception uses it daily. We're building Ivory to eventually replace it. We need to build + test Ivory's full workflow (diary edits, status, estimates, accounts) without any risk to the live practice.

## Decision
- **Elixir stays the live system and a READ-ONLY source.** Ivory NEVER writes to Elixir.
- **Ivory is a fully EDITABLE working copy**, populated by importing all Elixir data, so we can use/test it "as if we're live."
- **We flip the switch** (reception moves to Ivory) only when Paul decides. Until then both run in parallel; Ivory is a sandbox refreshed from Elixir snapshots. Divergence is acceptable (it's a test copy).
- Therefore the Ivory diary is **editable real `Appointment` records**, not the read-only `ElixirDiarySnapshot` mirror (the mirror was the first pass; superseded for the test phase, code retained).

## Consequences
- Import scripts create editable Ivory data tagged `[elixir-test]`, idempotently refreshable from a fresh Elixir copy.
- Patient/account/estimate data is imported so Ivory is a complete working replica.
- No medical-aid divergence risk to the practice because Elixir is untouched.
