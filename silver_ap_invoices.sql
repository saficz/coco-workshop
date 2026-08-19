/*
 * SILVER_AP_INVOICES Dynamic Table
 *
 * Consolidates AP invoice data from four source systems (SAP, Oracle, Baan, Workday)
 * into a unified Silver-layer schema. Each source is a UNION ALL branch with
 * source-specific transformations applied inline.
 *
 * Business rules applied:
 *   BR-001: Status normalization (source-specific values → APPROVED / PENDING)
 *   BR-003: Baan deduplication on INVOICE_NUMBER using latest CREATED_AT
 *   BR-007: SOURCE_SYSTEM literal per branch
 *   BR-008: System-specific columns dropped (not selected)
 *   BR-002/BR-006: Currency and GL codes passed through as-is (Gold concern)
 *
 * Open decisions encoded as pass-through (see assumptions at bottom):
 *   BR-005: Payment terms left raw — normalize at Gold
 *   Baan cost center format change — stored as-is
 */

CREATE OR REPLACE DYNAMIC TABLE SILVER_AP_INVOICES
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = TRANSFORM_WH
AS

-- ============================================================
-- SAP (existing source — real-time CDC)
-- ============================================================
SELECT
  SAP_INVOICE_ID          AS INVOICE_ID,
  SAP_INVOICE_NUMBER      AS INVOICE_NUMBER,
  SAP_VENDOR_ID           AS VENDOR_ID,
  SAP_VENDOR_NAME         AS VENDOR_NAME,
  SAP_INVOICE_DATE        AS INVOICE_DATE,
  SAP_DUE_DATE            AS DUE_DATE,
  SAP_AMOUNT              AS INVOICE_AMOUNT,
  SAP_CURRENCY            AS CURRENCY_CODE,
  SAP_PAYMENT_TERMS       AS PAYMENT_TERMS,
  SAP_PO_NUMBER           AS PO_NUMBER,
  SAP_LINE_DESC           AS LINE_DESCRIPTION,
  SAP_GL_ACCOUNT          AS GL_ACCOUNT,
  SAP_COST_CENTER         AS COST_CENTER,
  CASE
    WHEN SAP_STATUS = 'APPROVED' THEN 'APPROVED'
    WHEN SAP_STATUS = 'PENDING'  THEN 'PENDING'
    ELSE 'UNKNOWN'
  END                     AS APPROVAL_STATUS,
  SAP_CREATED_AT          AS CREATED_AT,
  'SAP'                   AS SOURCE_SYSTEM
FROM BRONZE_SAP_AP_INVOICES

UNION ALL

-- ============================================================
-- Oracle (existing source — hourly batch)
-- ============================================================
SELECT
  ORA_INVOICE_ID          AS INVOICE_ID,
  ORA_INVOICE_NUMBER      AS INVOICE_NUMBER,
  ORA_VENDOR_ID           AS VENDOR_ID,
  ORA_VENDOR_NAME         AS VENDOR_NAME,
  ORA_INVOICE_DATE        AS INVOICE_DATE,
  ORA_DUE_DATE            AS DUE_DATE,
  ORA_AMOUNT              AS INVOICE_AMOUNT,
  ORA_CURRENCY            AS CURRENCY_CODE,
  ORA_PAYMENT_TERMS       AS PAYMENT_TERMS,
  ORA_PO_NUMBER           AS PO_NUMBER,
  ORA_LINE_DESC           AS LINE_DESCRIPTION,
  ORA_GL_ACCOUNT          AS GL_ACCOUNT,
  ORA_COST_CENTER         AS COST_CENTER,
  CASE
    WHEN ORA_STATUS = 'VALIDATED' THEN 'APPROVED'
    WHEN ORA_STATUS = 'PENDING'   THEN 'PENDING'
    ELSE 'UNKNOWN'
  END                     AS APPROVAL_STATUS,
  ORA_CREATED_AT          AS CREATED_AT,
  'ORACLE'                AS SOURCE_SYSTEM
FROM BRONZE_ORACLE_AP_INVOICES

UNION ALL

-- ============================================================
-- Baan IV (NEW — nightly CSV batch ~02:00 UTC)
-- BR-003: Deduplicate on INVOICE_NUMBER using latest CREATED_AT
-- ============================================================
SELECT
  BAN_INVOICE_ID          AS INVOICE_ID,
  BAN_INVOICE_REF         AS INVOICE_NUMBER,
  BAN_VENDOR_CODE         AS VENDOR_ID,
  BAN_VENDOR_DESC         AS VENDOR_NAME,
  BAN_INV_DATE            AS INVOICE_DATE,
  BAN_PAY_DATE            AS DUE_DATE,
  BAN_AMOUNT              AS INVOICE_AMOUNT,
  BAN_CURR                AS CURRENCY_CODE,
  BAN_PAY_TERMS           AS PAYMENT_TERMS,
  BAN_PO_REF              AS PO_NUMBER,
  BAN_LINE_DESC           AS LINE_DESCRIPTION,
  BAN_GL_CODE             AS GL_ACCOUNT,
  BAN_COST_CTR            AS COST_CENTER,
  CASE
    WHEN BAN_STATUS = 'POSTED'   THEN 'APPROVED'
    WHEN BAN_STATUS = 'APPROVED' THEN 'APPROVED'
    WHEN BAN_STATUS = 'PENDING'  THEN 'PENDING'
    ELSE 'UNKNOWN'
  END                     AS APPROVAL_STATUS,
  BAN_CREATED             AS CREATED_AT,
  'BAAN'                  AS SOURCE_SYSTEM
FROM BRONZE_BAAN_AP_INVOICES
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY BAN_INVOICE_REF
  ORDER BY BAN_CREATED DESC
) = 1

UNION ALL

-- ============================================================
-- Workday (NEW — hourly via connector)
-- ============================================================
SELECT
  WD_INVOICE_ID           AS INVOICE_ID,
  WD_INVOICE_NUM          AS INVOICE_NUMBER,
  WD_SUPPLIER_ID          AS VENDOR_ID,
  WD_SUPPLIER_NAME        AS VENDOR_NAME,
  WD_INVOICE_DATE         AS INVOICE_DATE,
  WD_DUE_DATE             AS DUE_DATE,
  WD_AMOUNT               AS INVOICE_AMOUNT,
  WD_CURRENCY             AS CURRENCY_CODE,
  WD_PAY_TERMS            AS PAYMENT_TERMS,
  WD_PO_NUMBER            AS PO_NUMBER,
  WD_MEMO                 AS LINE_DESCRIPTION,
  WD_LEDGER_ACCOUNT       AS GL_ACCOUNT,
  WD_COST_CENTER          AS COST_CENTER,
  CASE
    WHEN WD_APPROVAL_STATUS = 'Approved'  THEN 'APPROVED'
    WHEN WD_APPROVAL_STATUS = 'In Review' THEN 'PENDING'
    ELSE 'UNKNOWN'
  END                     AS APPROVAL_STATUS,
  WD_CREATED_DATE         AS CREATED_AT,
  'WORKDAY'               AS SOURCE_SYSTEM
FROM BRONZE_WORKDAY_AP_INVOICES
;
