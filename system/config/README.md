---
id: ref-config
title: Operational config — what the app consumes
status: active
last_reviewed: 2026-06-05
---

# Operational config

The **canonical operational config** (pricing, hours, holidays, banking, emergency triage, greeting, POPIA notice — everything the AI says and the booking engine uses) is **`config/practice_config.yml`** in the app root, loaded by `PracticeConfig` and synced to `DoctorSchedule`. The human-readable twin is `PRACTICE_CONFIG_DRAFT.md` (project root).

> It stays at `config/practice_config.yml` (not moved here) so the Rails initializer keeps loading it unchanged. This file documents it AS the canonical config under `system/`. The DB (`DoctorSchedule`, caches) is a derived cache kept in sync on deploy (`practice:sync_schedules`).

## To change a rule the AI/booking uses
1. Edit `config/practice_config.yml` (and the human twin `PRACTICE_CONFIG_DRAFT.md` if it's patient-facing copy).
2. Redeploy → `practice:sync_schedules` re-syncs hours to the DB.
3. Never invent config keys not declared in `practice_config.yml`.

## What lives where
- Pricing, hours, holidays, banking, FAQ wording, greeting, triage → `config/practice_config.yml`.
- Providers (dentists), patients, appointments, estimates → the Postgres DB (see `reference/data-architecture.md`).
