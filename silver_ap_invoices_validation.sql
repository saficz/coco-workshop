/*
 * Validation queries for SILVER_AP_INVOICES after adding Baan + Workday branches.
 * Run these after the DT refreshes to confirm correctness.
 */

-- 1. Row count by source — confirm Baan and Workday rows are flowing
SELECT SOURCE_SYSTEM, COUNT(*) AS row_count
FROM SILVER_AP_INVOICES
GROUP BY SOURCE_SYSTEM
ORDER BY SOURCE_SYSTEM;
-- Expected: BAAN and WORKDAY appear with row_count > 0


-- 2. No NULLs in required fields for new sources
SELECT
  SOURCE_SYSTEM,
  COUNT_IF(INVOICE_ID IS NULL)       AS null_invoice_id,
  COUNT_IF(INVOICE_NUMBER IS NULL)   AS null_invoice_number,
  COUNT_IF(VENDOR_ID IS NULL)        AS null_vendor_id,
  COUNT_IF(INVOICE_AMOUNT IS NULL)   AS null_amount,
  COUNT_IF(APPROVAL_STATUS IS NULL)  AS null_status,
  COUNT_IF(GL_ACCOUNT IS NULL)       AS null_gl,
  COUNT_IF(CREATED_AT IS NULL)       AS null_created
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY SOURCE_SYSTEM;
-- Expected: all zero


-- 3. Status normalization — only APPROVED, PENDING, UNKNOWN should appear
SELECT SOURCE_SYSTEM, APPROVAL_STATUS, COUNT(*) AS cnt
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY 1, 2
ORDER BY 1, 2;
-- Expected: no raw values like 'POSTED', 'Approved', 'In Review'


-- 4. Baan dedup — no duplicate INVOICE_NUMBERs within Baan
SELECT INVOICE_NUMBER, COUNT(*) AS dupes
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM = 'BAAN'
GROUP BY INVOICE_NUMBER
HAVING COUNT(*) > 1;
-- Expected: 0 rows


-- 5. UNKNOWN status alert — surface unmapped source values
SELECT SOURCE_SYSTEM, COUNT(*) AS unknown_count
FROM SILVER_AP_INVOICES
WHERE APPROVAL_STATUS = 'UNKNOWN'
GROUP BY SOURCE_SYSTEM;
-- Expected: 0 in steady state; >0 means new values appeared in source


-- 6. Currency codes are within expected set
SELECT SOURCE_SYSTEM, CURRENCY_CODE, COUNT(*) AS cnt
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY 1, 2
ORDER BY 1, 2;
-- Baan: EUR, GBP. Workday: USD, GBP, EUR.


-- 7. Composite key uniqueness (INVOICE_ID + SOURCE_SYSTEM)
SELECT INVOICE_ID, SOURCE_SYSTEM, COUNT(*) AS dupes
FROM SILVER_AP_INVOICES
GROUP BY 1, 2
HAVING COUNT(*) > 1;
-- Expected: 0 rows (Baan dedup should prevent this)


-- 8. Schema check — dropped columns must not exist
DESCRIBE DYNAMIC TABLE SILVER_AP_INVOICES;
-- Verify: no BAN_COMPANY, WD_TENANT_ID, SAP_COMPANY_CODE,
--         SAP_DOCUMENT_TYPE, ORACLE_ORG_ID, ORACLE_SOURCE columns


-- 9. Payment terms pass-through — values are raw source format
SELECT SOURCE_SYSTEM, PAYMENT_TERMS, COUNT(*) AS cnt
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY 1, 2
ORDER BY 1, 2;
-- Baan: N30, N60. Workday: Net 30, Net 60.
-- Confirms no premature normalization at Silver.
