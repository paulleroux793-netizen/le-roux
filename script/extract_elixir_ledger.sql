/* Extracts RECENT Elixir account ledger (ACCOUNTITEMS) -> |@| file for parse_elixir_ledger.py.
   Run against a COPY of MDLDATA.FDB (Elixir CLOSED), charset NONE:
     isql <copy.fdb> -user SYSDBA -password masterkey -ch NONE -i extract_elixir_ledger.sql -o ledger_raw.txt
   Fields (exactly what parse_elixir_ledger.py expects):
     acct_cl |@| dos(DD-MON-YYYY) |@| itype(Debit/Credit) |@| amt |@| vat_value |@| narrative |@| tariff_code |@| provider
   acct_cl = ACCOUNTITEMS.ACCOUNT (CL-code -> A-code via internal.json). vat = VATVALUE (rand, not the rate).
   WINDOW: last ~12 months so current account balances reconstruct (payments allocated oldest-first
   in the importer). READ-ONLY on Elixir. */
SET HEADING OFF;
SELECT
  COALESCE(SUBSTRING(A.ACCOUNT FROM 1 FOR 12), '') || '|@|' ||
  COALESCE(CAST(A.DATEOFSERVICE AS VARCHAR(15)), '') || '|@|' ||
  COALESCE(SUBSTRING(A.ITEMTYPE FROM 1 FOR 8), '') || '|@|' ||
  COALESCE(CAST(A.AMOUNT AS VARCHAR(14)), '0') || '|@|' ||
  COALESCE(CAST(A.VATVALUE AS VARCHAR(14)), '0') || '|@|' ||
  COALESCE(SUBSTRING(A.NARRATIVE FROM 1 FOR 80), '') || '|@|' ||
  COALESCE(SUBSTRING(A.TARIFF FROM 1 FOR 12), '') || '|@|' ||
  COALESCE(SUBSTRING(A.PROVIDER FROM 1 FOR 40), '')
FROM ACCOUNTITEMS A
WHERE A.DATEOFSERVICE >= '2025-06-01'
  AND A.ACCOUNT STARTING WITH 'CL'
ORDER BY A.ACCOUNT, A.DATEOFSERVICE;
