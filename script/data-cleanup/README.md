# Data-cleanup scripts — READ THIS FIRST (for Paul)

These scripts touch **real patient/financial data**. They are written by the
autonomous loop to be **PREPARED + DOCUMENTED, never auto-executed** (hard rule
from Paul, 2026-06-06). Each script defaults to a **DRY-RUN** that only prints
what it *would* change; applying requires an explicit env flag and is **your
decision to run**, after reviewing the dry-run output and taking a backup.

## Safe-handling protocol (every script here follows it)

1. **DRY-RUN by default** — `bin/rails runner script/data-cleanup/<name>.rb`
   prints a per-record preview (before → after) and a summary count. No writes.
2. **APPLY is env-gated** — only `APPLY=1 bin/rails runner ...` performs writes,
   wrapped in a single `ActiveRecord::Base.transaction` so a mid-run error rolls
   the whole thing back.
3. **Backup first** — take a fresh encrypted DB backup before any APPLY
   (the nightly backup exists, but take a point-in-time one too).
4. **Rollback note** — each script documents how to undo (usually: restore the
   backup, or the inverse update if it's reversible).
5. **Never run on a flapping link** — only when the rig is stable.

## The 5 data items Paul flagged (status)

| # | Item | What it is | Risk | Script status |
|---|------|-----------|------|---------------|
| 1 | **52 credits R87,638.76** | Credit balances that need attributing/clearing | HIGH (money) | needs Paul's rule (write-off? carry as credit? refund?) before a script can be written |
| 2 | **Per-line VAT backfill** | Invoice/estimate lines with vat_cents 0/null that should be 15% | MED | scriptable after read-only inspection of the rule + affected count |
| 3 | **~5 ambiguous +27 phones** | Phone numbers that don't normalise cleanly | LOW | scriptable — list them, propose normalised form, apply per-record |
| 4 | **Merge Morne Maartens dup + #2439 placeholder** | Two patient records for one person + a placeholder | MED (FK re-pointing) | scriptable after listing all FKs (appts/invoices/accounts/scheme) referencing each |
| 5 | **Zero-total estimate** | An estimate with R0 total | LOW | scriptable — identify it, void or delete with reason |

## Why none are auto-applied

- Items 1 & 4 need a **decision only Paul can make** (financial treatment;
  which record is canonical for the merge).
- Items 2, 3, 5 are mechanically safe but still touch real data, so they get a
  dry-run for Paul to eyeball before he runs the apply.

## Next steps (when the rig is stable)

The loop will add `<item>.rb` scripts here one at a time, each with its dry-run
verified (printing the real affected records read-only) so Paul can review the
exact impact before deciding to apply.
