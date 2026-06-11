/* Extracts billed line items (ACCOUNTITEMS Debits, last ~24 months) -> |@| file for
   parse_elixir_tariffs.py, which derives the current per-code fee. Run against a COPY of
   MDLDATA.FDB (Elixir CLOSED), charset NONE:
     isql <copy.fdb> -user SYSDBA -password masterkey -ch NONE -i extract_elixir_tariffs.sql -o tariffs_raw.txt
   Fields (exactly what parse_elixir_tariffs.py expects):
     code |@| narrative |@| amount |@| dos(DD-MON-YYYY) |@| vat_rate
   code = ACCOUNTITEMS.TARIFF, vat = VAT (the rate, e.g. 15). READ-ONLY on Elixir. */
SET HEADING OFF;
SELECT
  COALESCE(SUBSTRING(A.TARIFF FROM 1 FOR 12), '') || '|@|' ||
  COALESCE(SUBSTRING(A.NARRATIVE FROM 1 FOR 60), '') || '|@|' ||
  COALESCE(CAST(A.AMOUNT AS VARCHAR(14)), '0') || '|@|' ||
  COALESCE(CAST(A.DATEOFSERVICE AS VARCHAR(15)), '') || '|@|' ||
  COALESCE(CAST(A.VAT AS VARCHAR(6)), '0') || '|@|' ||
  COALESCE(CAST(A.QUANTITY AS VARCHAR(8)), '1')
FROM ACCOUNTITEMS A
WHERE A.ITEMTYPE = 'Debit'
  AND A.DATEOFSERVICE >= '2024-06-01'
  AND A.TARIFF IS NOT NULL
ORDER BY A.TARIFF, A.DATEOFSERVICE;
