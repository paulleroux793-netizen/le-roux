/* Extracts the live Elixir diary (EXPRESSAPPOINTMENTS) to a pipe-delimited file
   for the read-only mirror into Ivory. Run via isql against a copy of MDLDATA.FDB:
     isql <copy.fdb> -user SYSDBA -password masterkey -i extract_elixir_diary.sql -o diary_raw.txt
   Columns: STARTDATE |@| FINISH |@| RESOURCEID |@| CAPTION |@| MESSAGE1
   RESOURCEID maps via DIARYRESOURCE.RESOURCECODE: 1=Chalita 2=Anneze 3=Eric 4=Theo 5=Eliska.
   SUBSTRING caps long free-text so a stray long note can't abort the dump. */
SET HEADING OFF;
SELECT
  CAST(e.STARTDATE AS VARCHAR(25)) || '|@|' ||
  COALESCE(CAST(e.FINISH AS VARCHAR(25)), '') || '|@|' ||
  COALESCE(CAST(e.RESOURCEID AS VARCHAR(5)), '') || '|@|' ||
  COALESCE(CAST(SUBSTRING(e.CAPTION FROM 1 FOR 150) AS VARCHAR(150)), '') || '|@|' ||
  COALESCE(CAST(SUBSTRING(e.MESSAGE1 FROM 1 FOR 200) AS VARCHAR(200)), '')
FROM EXPRESSAPPOINTMENTS e
WHERE e.STARTDATE >= '2026-06-01'
ORDER BY e.STARTDATE;
