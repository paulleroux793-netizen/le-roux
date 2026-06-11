/* Extracts the live Elixir patients (DEPENDANTS joined to ACCOUNTS) to a |@|-delimited file
   for the Ivory patient import. Run via isql against a COPY of MDLDATA.FDB (Elixir CLOSED):
     isql <copy.fdb> -user SYSDBA -password masterkey -i extract_elixir_patients.sql -o patients_raw.txt
   Join: DEPENDANTS.ACCOUNT = ACCOUNTS.IDENTIFIER (the CL3000000x family code) — VERIFIED 2026-06-08
   (2513 of 2514 dependants join; the 1 non-joining row is the placeholder ACCOUNT='1').
   Output fields (exactly what parse_elixir_patients.py expects):
     firstname |@| surname |@| nidn |@| cellular |@| birthdate(DD/MM/YYYY) |@| relation |@|
     account_cl |@| email |@| telephonehome |@| account_surname
   SUBSTRING caps long free-text so a stray long value can't abort the dump. READ-ONLY on Elixir. */
SET HEADING OFF;
SELECT
  COALESCE(SUBSTRING(D.FIRSTNAME     FROM 1 FOR 30), '') || '|@|' ||
  COALESCE(SUBSTRING(D.SURNAME       FROM 1 FOR 25), '') || '|@|' ||
  COALESCE(SUBSTRING(D.NIDN          FROM 1 FOR 13), '') || '|@|' ||
  COALESCE(SUBSTRING(D.CELLULAR      FROM 1 FOR 12), '') || '|@|' ||
  COALESCE(SUBSTRING(D.BIRTHDATE     FROM 1 FOR 10), '') || '|@|' ||
  COALESCE(SUBSTRING(D.RELATION      FROM 1 FOR 18), '') || '|@|' ||
  COALESCE(SUBSTRING(D.ACCOUNT       FROM 1 FOR 10), '') || '|@|' ||
  COALESCE(SUBSTRING(A.EMAIL         FROM 1 FOR 50), '') || '|@|' ||
  COALESCE(SUBSTRING(D.TELEPHONEHOME FROM 1 FOR 16), '') || '|@|' ||
  COALESCE(SUBSTRING(A.SURNAME       FROM 1 FOR 25), '')
FROM DEPENDANTS D
JOIN ACCOUNTS A ON D.ACCOUNT = A.IDENTIFIER
WHERE CHAR_LENGTH(TRIM(D.FIRSTNAME)) > 0
  AND CHAR_LENGTH(TRIM(D.SURNAME)) > 0
ORDER BY A.SURNAME, D.SURNAME, D.FIRSTNAME;
