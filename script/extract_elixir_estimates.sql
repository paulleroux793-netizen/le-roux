/* Extracts Elixir estimates (header-only) -> |@| file for parse_elixir_estimates.py.
   Run against a COPY of MDLDATA.FDB (Elixir CLOSED), charset NONE:
     isql <copy.fdb> -user SYSDBA -password masterkey -ch NONE -i extract_elixir_estimates.sql -o estimates_raw.txt
   Fields (exactly what parse_elixir_estimates.py expects):
     dateof(DD-MON-YYYY) |@| account_cl |@| patient_name |@| valueof |@| details |@| status
   account_cl = ESTIMATES.ACCOUNT (CL-code, mapped to A-code via patients.json).
   patient_name via DEPENDANTLINK -> DEPENDANTS. CAST(DATE AS VARCHAR) => DD-MON-YYYY in FB 2.5.
   Estimates are header-only (line items are NOT estimate-scoped — verified). READ-ONLY on Elixir. */
SET HEADING OFF;
SELECT
  COALESCE(CAST(E.DATEOF AS VARCHAR(15)), '') || '|@|' ||
  COALESCE(SUBSTRING(E.ACCOUNT FROM 1 FOR 12), '') || '|@|' ||
  COALESCE(SUBSTRING(TRIM(D.FIRSTNAME) || ' ' || TRIM(D.SURNAME) FROM 1 FOR 50), '') || '|@|' ||
  COALESCE(CAST(E.VALUEOF AS VARCHAR(14)), '') || '|@|' ||
  COALESCE(SUBSTRING(E.TREATMENT FROM 1 FOR 180), '') || '|@|' ||
  COALESCE(SUBSTRING(E.STATUS FROM 1 FOR 20), '')
FROM ESTIMATES E
LEFT JOIN DEPENDANTS D ON E.DEPENDANTLINK = D.IDENTIFIER
WHERE E.VALUEOF > 0
ORDER BY E.DATEOF;
