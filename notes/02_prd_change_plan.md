# PRD Analysis: SILVER_AP_INVOICES

**PRD file:** `sample_business_requirements_column_mapping.csv`
**Target DT:** `SILVER_AP_INVOICES`
**Existing DDL:** `silver_ap_invoices.sql`

---

## 1. Summary of Requested Changes

The PRD is a column mapping spec for the Baan IV and Workday source integrations. Comparing it against the existing DT:

| Area | PRD Asks | Current DT State | Delta |
|------|----------|------------------|-------|
| Baan branch | 17 fields mapped, 1 dropped, dedup on `BAN_INVOICE_REF` | Implemented | **No change needed** |
| Workday branch | 17 fields mapped, 1 dropped | Implemented | **No change needed** |
| Payment terms normalization | Flagged "Open — needs decision" | Passed through raw | **No change needed** (matches recommended default) |
| Status mapping (Baan) | POSTED→APPROVED, APPROVED→APPROVED, PENDING→PENDING | Implemented exactly | **No change needed** |
| Status mapping (Workday) | Approved→APPROVED, In Review→PENDING | Implemented exactly | **No change needed** |
| Dropped columns | BAN_COMPANY, WD_TENANT_ID | Not selected (correctly dropped) | **No change needed** |

**Conclusion: The existing DT fully implements this PRD. No DDL changes are required.**

---

## 2. Source-to-Silver Mapping Summary

### Baan IV → SILVER_AP_INVOICES

| Source Column | Silver Column | Transform | PRD Status |
|---|---|---|---|
| BAN_INVOICE_ID | INVOICE_ID | Direct | Confirmed |
| BAN_INVOICE_REF | INVOICE_NUMBER | Direct + dedup key | Confirmed |
| BAN_VENDOR_CODE | VENDOR_ID | Direct | Confirmed |
| BAN_VENDOR_DESC | VENDOR_NAME | Direct | Confirmed |
| BAN_INV_DATE | INVOICE_DATE | Direct | Confirmed |
| BAN_PAY_DATE | DUE_DATE | Direct | Confirmed |
| BAN_AMOUNT | INVOICE_AMOUNT | Direct | Confirmed |
| BAN_CURR | CURRENCY_CODE | Direct | Confirmed |
| BAN_PAY_TERMS | PAYMENT_TERMS | Pass-through (normalize at Gold) | Open |
| BAN_PO_REF | PO_NUMBER | Direct | Confirmed |
| BAN_LINE_DESC | LINE_DESCRIPTION | Direct | Confirmed |
| BAN_GL_CODE | GL_ACCOUNT | Direct | Confirmed |
| BAN_COST_CTR | COST_CENTER | Direct (old+new formats coexist) | Confirmed |
| BAN_STATUS | APPROVAL_STATUS | CASE map | Confirmed |
| BAN_CREATED | CREATED_AT | Direct (already UTC) | Confirmed |
| BAN_COMPANY | — | DROP | Confirmed |

### Workday → SILVER_AP_INVOICES

| Source Column | Silver Column | Transform | PRD Status |
|---|---|---|---|
| WD_INVOICE_ID | INVOICE_ID | Direct | Confirmed |
| WD_INVOICE_NUM | INVOICE_NUMBER | Direct | Confirmed |
| WD_SUPPLIER_ID | VENDOR_ID | Direct | Confirmed |
| WD_SUPPLIER_NAME | VENDOR_NAME | Direct | Confirmed |
| WD_INVOICE_DATE | INVOICE_DATE | Direct | Confirmed |
| WD_DUE_DATE | DUE_DATE | Direct | Confirmed |
| WD_AMOUNT | INVOICE_AMOUNT | Direct | Confirmed |
| WD_CURRENCY | CURRENCY_CODE | Direct | Confirmed |
| WD_PAY_TERMS | PAYMENT_TERMS | Pass-through (normalize at Gold) | Open |
| WD_PO_NUMBER | PO_NUMBER | Direct | Confirmed |
| WD_MEMO | LINE_DESCRIPTION | Direct (rename) | Confirmed |
| WD_LEDGER_ACCOUNT | GL_ACCOUNT | Direct | Confirmed |
| WD_COST_CENTER | COST_CENTER | Direct | Confirmed |
| WD_APPROVAL_STATUS | APPROVAL_STATUS | CASE map | Confirmed |
| WD_CREATED_DATE | CREATED_AT | Direct (already UTC) | Confirmed |
| WD_TENANT_ID | — | DROP | Confirmed |

---

## 3. Open Questions and Assumptions

| # | Rule ID | Question | Decision Owner | Recommended Default | Current DT Behavior |
|---|---------|----------|----------------|---------------------|---------------------|
| 1 | BAN_PAY_TERMS (row 10) | Baan uses "N30"/"N60" — standardize to SAP format "NET30"/"NET60" at Silver? | Not stated in PRD | Leave raw at Silver, normalize in Gold | **Already pass-through (matches default)** |
| 2 | WD_PAY_TERMS (row 26) | Workday uses "Net 30"/"Net 60" (with space) — same normalization question | Not stated in PRD | Leave raw at Silver, normalize in Gold | **Already pass-through (matches default)** |

**Assumptions already encoded in the DT (confirmed by PRD):**

- Baan cost center format change (BC-XX → BC-XXX) is stored as-is — no Silver-layer normalization
- GL codes are never cross-mapped at Silver
- BAN_COMPANY and WD_TENANT_ID are intentionally excluded
- Baan dedup uses `ROW_NUMBER() OVER (PARTITION BY BAN_INVOICE_REF ORDER BY BAN_CREATED DESC) = 1`

---

## 4. DDL Delta Plan

**No DDL changes required.** The existing `silver_ap_invoices.sql` already fully implements the PRD specification:

- All confirmed column mappings match 1:1
- Status normalization CASE expressions match the PRD's value mappings
- Baan dedup logic is in place
- Dropped columns are correctly excluded
- Open items (payment terms) follow the recommended default (pass-through)

If the open questions are resolved **against** the current default (i.e., decision is made to normalize at Silver), the delta would be:

```sql
-- HYPOTHETICAL ONLY — if payment terms normalization moves to Silver:
-- Replace direct map of BAN_PAY_TERMS with:
CASE
  WHEN BAN_PAY_TERMS = 'N30' THEN 'NET30'
  WHEN BAN_PAY_TERMS = 'N60' THEN 'NET60'
  ELSE BAN_PAY_TERMS
END AS PAYMENT_TERMS,

-- Replace direct map of WD_PAY_TERMS with:
CASE
  WHEN WD_PAY_TERMS = 'Net 30' THEN 'NET30'
  WHEN WD_PAY_TERMS = 'Net 60' THEN 'NET60'
  ELSE WD_PAY_TERMS
END AS PAYMENT_TERMS,
```

---

## 5. Validation Queries

The existing `silver_ap_invoices_validation.sql` covers these checks. For a reviewer confirming this PRD is satisfied:

```sql
-- V1: All four sources present with rows
SELECT SOURCE_SYSTEM, COUNT(*) AS row_count
FROM SILVER_AP_INVOICES
GROUP BY SOURCE_SYSTEM
ORDER BY SOURCE_SYSTEM;
-- Expected: BAAN > 0, ORACLE > 0, SAP > 0, WORKDAY > 0

-- V2: No NULLs in required fields (per PRD Required?=Yes)
SELECT
  SOURCE_SYSTEM,
  COUNT_IF(INVOICE_ID IS NULL)       AS null_invoice_id,
  COUNT_IF(INVOICE_NUMBER IS NULL)   AS null_invoice_number,
  COUNT_IF(VENDOR_ID IS NULL)        AS null_vendor_id,
  COUNT_IF(INVOICE_AMOUNT IS NULL)   AS null_amount,
  COUNT_IF(CURRENCY_CODE IS NULL)    AS null_currency,
  COUNT_IF(GL_ACCOUNT IS NULL)       AS null_gl,
  COUNT_IF(COST_CENTER IS NULL)      AS null_cost_center,
  COUNT_IF(APPROVAL_STATUS IS NULL)  AS null_status,
  COUNT_IF(CREATED_AT IS NULL)       AS null_created
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY SOURCE_SYSTEM;
-- Expected: all zeros

-- V3: Status values are only APPROVED/PENDING/UNKNOWN (no raw source values)
SELECT SOURCE_SYSTEM, APPROVAL_STATUS, COUNT(*) AS cnt
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY 1, 2
ORDER BY 1, 2;
-- Must NOT contain: POSTED, Approved, In Review

-- V4: Baan dedup — no duplicate INVOICE_NUMBERs
SELECT INVOICE_NUMBER, COUNT(*) AS dupes
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM = 'BAAN'
GROUP BY INVOICE_NUMBER
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- V5: Dropped columns do not exist
DESCRIBE DYNAMIC TABLE SILVER_AP_INVOICES;
-- Verify absence of: BAN_COMPANY, WD_TENANT_ID

-- V6: Payment terms are raw (confirms pass-through)
SELECT SOURCE_SYSTEM, PAYMENT_TERMS, COUNT(*) AS cnt
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IN ('BAAN', 'WORKDAY')
GROUP BY 1, 2
ORDER BY 1, 2;
-- Baan: N30, N60 (not NET30/NET60)
-- Workday: Net 30, Net 60 (with space, not NET30/NET60)

-- V7: Composite key uniqueness
SELECT INVOICE_ID, SOURCE_SYSTEM, COUNT(*) AS dupes
FROM SILVER_AP_INVOICES
GROUP BY 1, 2
HAVING COUNT(*) > 1;
-- Expected: 0 rows
```
