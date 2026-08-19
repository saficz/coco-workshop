/*===========================================================================
  SILVER_AP_INVOICES — PRD Update (Baan + Workday onboarding)
  
  PRD Sources:
    - sample_business_requirements_source_onboarding.csv
    - sample_business_requirements_column_mapping.csv
    - sample_business_requirements_business_rules.csv

  Changes from baseline:
    1. TARGET_LAG changed from '1 hour' to DOWNSTREAM (BR-009)
    2. Added Baan IV branch with dedup (BR-003) and status mapping (BR-001)
    3. Added Workday FM branch with status mapping (BR-001)
    4. Applied status normalization to ALL branches including Oracle VALIDATED→APPROVED
    5. SOURCE_IDENTIFIER populated from BAN_COMPANY / WD_TENANT_ID for traceability
===========================================================================*/

CREATE OR REPLACE DYNAMIC TABLE COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
  TARGET_LAG = DOWNSTREAM
  REFRESH_MODE = AUTO
  INITIALIZE = ON_CREATE
  WAREHOUSE = COMPUTE_WH
AS

-- SAP: Status already matches Silver standard (BR-001)
SELECT
    INVOICE_ID,
    INVOICE_NUMBER,
    VENDOR_ID,
    VENDOR_NAME,
    INVOICE_DATE,
    DUE_DATE,
    INVOICE_AMOUNT,
    CURRENCY_CODE,
    PAYMENT_TERMS,
    PO_NUMBER,
    LINE_DESCRIPTION,
    GL_ACCOUNT,
    COST_CENTER,
    CASE
        WHEN APPROVAL_STATUS = 'APPROVED' THEN 'APPROVED'
        WHEN APPROVAL_STATUS = 'PENDING' THEN 'PENDING'
        ELSE APPROVAL_STATUS
    END AS APPROVAL_STATUS,
    CREATED_AT,
    'SAP' AS SOURCE_SYSTEM,
    SAP_COMPANY_CODE AS SOURCE_IDENTIFIER
FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_SAP_AP_INVOICES

UNION ALL

-- Oracle: VALIDATED → APPROVED (BR-001)
SELECT
    INV_ID AS INVOICE_ID,
    INV_NUM AS INVOICE_NUMBER,
    SUPPLIER_ID AS VENDOR_ID,
    SUPPLIER_NAME AS VENDOR_NAME,
    INV_DATE AS INVOICE_DATE,
    PAYMENT_DUE_DATE AS DUE_DATE,
    TOTAL_AMOUNT AS INVOICE_AMOUNT,
    CURRENCY AS CURRENCY_CODE,
    TERMS_CODE AS PAYMENT_TERMS,
    PURCHASE_ORDER AS PO_NUMBER,
    DESCRIPTION AS LINE_DESCRIPTION,
    ACCOUNT_CODE AS GL_ACCOUNT,
    DEPT_CODE AS COST_CENTER,
    CASE
        WHEN STATUS = 'VALIDATED' THEN 'APPROVED'
        WHEN STATUS = 'APPROVED' THEN 'APPROVED'
        WHEN STATUS = 'PENDING' THEN 'PENDING'
        ELSE STATUS
    END AS APPROVAL_STATUS,
    CREATION_DATE AS CREATED_AT,
    'ORACLE' AS SOURCE_SYSTEM,
    ORACLE_ORG_ID AS SOURCE_IDENTIFIER
FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_ORACLE_AP_INVOICES

UNION ALL

-- Baan: POSTED → APPROVED, deduplicated on INVOICE_NUMBER (BR-001, BR-003)
SELECT
    BAN_INVOICE_ID AS INVOICE_ID,
    BAN_INVOICE_REF AS INVOICE_NUMBER,
    BAN_VENDOR_CODE AS VENDOR_ID,
    BAN_VENDOR_DESC AS VENDOR_NAME,
    BAN_INV_DATE AS INVOICE_DATE,
    BAN_PAY_DATE AS DUE_DATE,
    BAN_AMOUNT AS INVOICE_AMOUNT,
    BAN_CURR AS CURRENCY_CODE,
    BAN_PAY_TERMS AS PAYMENT_TERMS,
    BAN_PO_REF AS PO_NUMBER,
    BAN_LINE_DESC AS LINE_DESCRIPTION,
    BAN_GL_CODE AS GL_ACCOUNT,
    BAN_COST_CTR AS COST_CENTER,
    CASE
        WHEN BAN_STATUS = 'POSTED' THEN 'APPROVED'
        WHEN BAN_STATUS = 'APPROVED' THEN 'APPROVED'
        WHEN BAN_STATUS = 'PENDING' THEN 'PENDING'
        ELSE BAN_STATUS
    END AS APPROVAL_STATUS,
    BAN_CREATED AS CREATED_AT,
    'BAAN' AS SOURCE_SYSTEM,
    BAN_COMPANY AS SOURCE_IDENTIFIER
FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_BAAN_AP_INVOICES
QUALIFY ROW_NUMBER() OVER (PARTITION BY BAN_INVOICE_REF ORDER BY BAN_CREATED DESC) = 1

UNION ALL

-- Workday: "Approved" → APPROVED, "In Review" → PENDING (BR-001)
SELECT
    WD_INVOICE_ID AS INVOICE_ID,
    WD_INVOICE_NUM AS INVOICE_NUMBER,
    WD_SUPPLIER_ID AS VENDOR_ID,
    WD_SUPPLIER_NAME AS VENDOR_NAME,
    WD_INVOICE_DATE AS INVOICE_DATE,
    WD_DUE_DATE AS DUE_DATE,
    WD_AMOUNT AS INVOICE_AMOUNT,
    WD_CURRENCY AS CURRENCY_CODE,
    WD_PAY_TERMS AS PAYMENT_TERMS,
    WD_PO_NUMBER AS PO_NUMBER,
    WD_MEMO AS LINE_DESCRIPTION,
    WD_LEDGER_ACCOUNT AS GL_ACCOUNT,
    WD_COST_CENTER AS COST_CENTER,
    CASE
        WHEN WD_APPROVAL_STATUS = 'Approved' THEN 'APPROVED'
        WHEN WD_APPROVAL_STATUS = 'In Review' THEN 'PENDING'
        ELSE UPPER(WD_APPROVAL_STATUS)
    END AS APPROVAL_STATUS,
    WD_CREATED_DATE AS CREATED_AT,
    'WORKDAY' AS SOURCE_SYSTEM,
    WD_TENANT_ID AS SOURCE_IDENTIFIER
FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_WORKDAY_AP_INVOICES
;


/*===========================================================================
  SOURCE MAPPING EXPLANATION
  
  Each source maps to the same 17-column common schema via UNION ALL:

  Silver Column      | SAP              | Oracle            | Baan             | Workday
  -------------------|------------------|-------------------|------------------|------------------
  INVOICE_ID         | INVOICE_ID       | INV_ID            | BAN_INVOICE_ID   | WD_INVOICE_ID
  INVOICE_NUMBER     | INVOICE_NUMBER   | INV_NUM           | BAN_INVOICE_REF  | WD_INVOICE_NUM
  VENDOR_ID          | VENDOR_ID        | SUPPLIER_ID       | BAN_VENDOR_CODE  | WD_SUPPLIER_ID
  VENDOR_NAME        | VENDOR_NAME      | SUPPLIER_NAME     | BAN_VENDOR_DESC  | WD_SUPPLIER_NAME
  INVOICE_DATE       | INVOICE_DATE     | INV_DATE          | BAN_INV_DATE     | WD_INVOICE_DATE
  DUE_DATE           | DUE_DATE         | PAYMENT_DUE_DATE  | BAN_PAY_DATE     | WD_DUE_DATE
  INVOICE_AMOUNT     | INVOICE_AMOUNT   | TOTAL_AMOUNT      | BAN_AMOUNT       | WD_AMOUNT
  CURRENCY_CODE      | CURRENCY_CODE    | CURRENCY          | BAN_CURR         | WD_CURRENCY
  PAYMENT_TERMS      | PAYMENT_TERMS    | TERMS_CODE        | BAN_PAY_TERMS    | WD_PAY_TERMS
  PO_NUMBER          | PO_NUMBER        | PURCHASE_ORDER    | BAN_PO_REF       | WD_PO_NUMBER
  LINE_DESCRIPTION   | LINE_DESCRIPTION | DESCRIPTION       | BAN_LINE_DESC    | WD_MEMO
  GL_ACCOUNT         | GL_ACCOUNT       | ACCOUNT_CODE      | BAN_GL_CODE      | WD_LEDGER_ACCOUNT
  COST_CENTER        | COST_CENTER      | DEPT_CODE         | BAN_COST_CTR     | WD_COST_CENTER
  APPROVAL_STATUS    | Direct pass      | VALIDATED→APPROVED| POSTED→APPROVED  | Approved→APPROVED
                     |                  |                   |                  | In Review→PENDING
  SOURCE_SYSTEM      | 'SAP'            | 'ORACLE'          | 'BAAN'           | 'WORKDAY'
  SOURCE_IDENTIFIER  | SAP_COMPANY_CODE | ORACLE_ORG_ID     | BAN_COMPANY      | WD_TENANT_ID
===========================================================================*/


/*===========================================================================
  ASSUMPTIONS REQUIRING ENGINEERING REVIEW

  #1  PAYMENT_TERMS passed through raw (BR-005)
      Baan sends "N30"/"N60", Workday sends "Net 30"/"Net 60".
      Normalization deferred to Gold layer per recommendation.
      RISK: Gold must implement; downstream reports will be inconsistent until then.
      DECISION OWNER: Sarah Chen / David Kim (due 2025-06-20)

  #2  BAN_COMPANY / WD_TENANT_ID used as SOURCE_IDENTIFIER (BR-008 vs existing pattern)
      BR-008 says "drop" these columns, but the existing DT uses system-specific
      identifiers (SAP_COMPANY_CODE, ORACLE_ORG_ID) as SOURCE_IDENTIFIER.
      We follow the existing pattern for traceability.
      RISK: Downstream consumers expecting NULL for new sources.

  #3  Baan dedup partitions on BAN_INVOICE_REF (BR-003)
      Assumes same INVOICE_NUMBER across different vendors is not legitimate.
      Karen confirmed the issue is same-vendor duplicates from nightly extract.
      RISK: Low — but add monitoring if Baan volume grows.

  #4  Workday legal signoff (DPA-2025-0041) not yet complete (SRC-2025-004)
      DT is deployed and will process Workday data immediately.
      RISK: Compliance exposure if data flows before DPA completion.
      RECOMMENDATION: Gate Workday bronze ingestion on legal signoff.

  #5  Baan cost center format change BC-XX → BC-XXX (SRC-2025-003)
      Both formats pass through as-is. No normalization at Silver.
      RISK: GROUP BY on COST_CENTER treats old/new as separate entities.
      Consider a mapping table or REGEXP normalization at Gold.
===========================================================================*/


/*===========================================================================
  VALIDATION QUERIES
===========================================================================*/

-- V1: No Baan duplicates survived dedup logic (BR-003)
SELECT INVOICE_NUMBER, COUNT(*) AS DUPES
FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM = 'BAAN'
GROUP BY INVOICE_NUMBER
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- V2: All four sources present with data
SELECT SOURCE_SYSTEM, COUNT(*) AS ROW_COUNT
FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
GROUP BY SOURCE_SYSTEM
ORDER BY SOURCE_SYSTEM;
-- Expected: BAAN, ORACLE, SAP, WORKDAY all with ROW_COUNT > 0

-- V3: Only APPROVED and PENDING in approval status (BR-001 normalization)
SELECT DISTINCT APPROVAL_STATUS
FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
WHERE APPROVAL_STATUS NOT IN ('APPROVED', 'PENDING');
-- Expected: 0 rows

-- V4: Status distribution by source — verify no raw values leaked through
SELECT SOURCE_SYSTEM, APPROVAL_STATUS, COUNT(*) AS CNT
FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
GROUP BY SOURCE_SYSTEM, APPROVAL_STATUS
ORDER BY SOURCE_SYSTEM, APPROVAL_STATUS;
-- Expected: No VALIDATED, POSTED, "In Review", or "Approved" values

-- V5: Currency codes are valid ISO 4217 (sanity check)
SELECT DISTINCT CURRENCY_CODE
FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
ORDER BY CURRENCY_CODE;
-- Expected: EUR, GBP, USD (no NULLs or invalid codes)

-- V6: No NULL INVOICE_ID or SOURCE_SYSTEM (required fields)
SELECT SOURCE_SYSTEM, COUNT(*) AS NULL_INVOICE_IDS
FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
WHERE INVOICE_ID IS NULL OR SOURCE_SYSTEM IS NULL
GROUP BY SOURCE_SYSTEM;
-- Expected: 0 rows
