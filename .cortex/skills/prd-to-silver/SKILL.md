---
name: prd-to-silver
description: "Analyze PRD-style requirement files and produce a structured implementation plan for a target Dynamic Table. Use when: user has a PRD, business requirements doc, or source onboarding sheet and wants to plan changes to a Silver/Gold Dynamic Table. Triggers: PRD, business requirements, source onboarding, plan DT changes, dynamic table plan, implementation plan from requirements, new source system plan."
---

# PRD to Dynamic Table Plan

Turn product requirement documents (source onboarding sheets, business rules, mapping specs) into a concrete, auditable implementation plan for a Snowflake Dynamic Table.

## Inputs

The user MUST provide:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `prd_path` | Path to the PRD file (XLSX, CSV, or PDF) | `./requirements/source_onboarding.xlsx` |
| `target_dynamic_table` | Fully-qualified or short name of the DT to modify | `SILVER_AP_INVOICES` |

Optional:
| Parameter | Description | Default |
|-----------|-------------|---------|
| `sheet_names` | For XLSX: which sheets to read | All sheets |
| `existing_dt_ddl` | Path or SQL of the current DT definition | Discover via `SHOW DYNAMIC TABLES` |

If either required input is missing, ask the user before proceeding.

## Workflow

### Step 1: Ingest and Parse the PRD

1. Read the file at `prd_path` using the Read tool.
   - **XLSX**: Read all sheets (or those specified in `sheet_names`). Treat each sheet as a separate requirements domain.
   - **CSV**: Read the file. Infer domain from column headers.
   - **PDF**: Read and extract tabular content.
2. Identify the document type(s) present:
   - Source Onboarding (new systems, connectors, landing zones)
   - Business Rules (transformations, normalization, dedup, flags)
   - Field Mappings (source column → target column)
   - Data Quality Rules (thresholds, DMFs, alerts)
3. Present a brief inventory of what was found to the user.

**STOP**: Confirm the parsed inventory is complete before analysis.

### Step 2: Discover the Current Target DT

1. If `existing_dt_ddl` was not provided, run:
   ```sql
   SELECT GET_DDL('DYNAMIC TABLE', '<target_dynamic_table>');
   ```
   If the DT does not exist yet, note this as a net-new creation and skip to Step 3.
2. Extract the current column list, source tables (FROM/JOIN), and any UNION ALL branches.
3. Identify the current `TARGET_LAG` and refresh mode.

### Step 3: Analyze Impact

For each requirement row in the PRD, classify it into exactly one category:

| Category | Meaning |
|----------|---------|
| **NEW_SOURCE** | A new source system must be added as a UNION ALL branch |
| **NEW_FIELD** | A new column must appear in the target DT |
| **TRANSFORM_RULE** | A transformation (CASE, dedup, cast, rename) applies to an existing or new field |
| **DQ_RULE** | A data quality rule (DMF, alert, threshold) — lives outside the DT SQL |
| **CONFIG_CHANGE** | Change to TARGET_LAG, warehouse, or scheduling |
| **OUT_OF_SCOPE** | Explicitly deferred, Phase 2, or belongs to Gold/downstream |
| **AMBIGUOUS** | Cannot be classified without a human decision |

### Step 4: Surface Assumptions and Open Questions

**This is the most important step.** Do NOT guess or silently assume.

For every item classified as AMBIGUOUS, and for any item where:
- The PRD says "TBD", "to be confirmed", "open question", or "needs decision"
- Two rules contradict each other
- A mapping is incomplete (source column named but no target column specified)
- A normalization rule lacks exhaustive value mappings
- A rule's layer placement (Silver vs. Gold) is unclear

...produce an entry in the **Open Questions** section with:
1. The rule/row ID from the PRD
2. What is ambiguous
3. Who owns the decision (if stated in the PRD)
4. A recommended default (clearly labeled as YOUR assumption, not a fact)

### Step 5: Produce the Plan

Output a structured plan with these exact sections:

---

## Output Format

```
## PRD Analysis: <target_dynamic_table>

### 1. New Source Systems
| Source | Platform | Region | Landing Pattern | Refresh Cadence | Status |
|--------|----------|--------|-----------------|-----------------|--------|
(one row per new source)

### 2. Silver Layer Changes

#### 2a. New Columns
| Column Name | Data Type | Source(s) | Derivation Logic |
|-------------|-----------|-----------|------------------|

#### 2b. Transformation Rules
| Rule ID | Affected Column | Logic (SQL sketch) | Notes |
|---------|-----------------|---------------------|-------|

#### 2c. Deduplication / Filtering
| Rule ID | Scope | Partition Key | Order Key | Notes |
|---------|-------|---------------|-----------|-------|

### 3. Data Quality Rules (outside DT)
| Rule ID | Type | Condition | Action | Owner |
|---------|------|-----------|--------|-------|

### 4. Out of Scope / Deferred
| Rule ID | Reason | Phase/Owner |
|---------|--------|-------------|

### 5. Open Questions (MUST RESOLVE BEFORE IMPLEMENTATION)
| # | Rule ID | Question | Decision Owner | Recommended Default |
|---|---------|----------|----------------|---------------------|

### 6. Suggested Implementation Order
(numbered list of steps, dependencies noted)
```

---

**STOP**: Present the full plan to the user. Do NOT proceed to write SQL or modify any objects until the user explicitly approves the plan and confirms all Open Questions are resolved.

## Principles

1. **Never guess.** If a requirement is ambiguous, surface it. Implementation that encodes a wrong assumption is worse than no implementation.
2. **Cite rule IDs.** Every item in the plan must trace back to a specific row/rule in the PRD.
3. **Separate concerns.** Silver DT logic vs. DMFs vs. Gold layer vs. downstream — keep them in their own sections.
4. **Preserve optionality.** When recommending a default for an open question, present it as "Recommended default" not as a decision. The human decides.
5. **Idempotent output.** Running this skill twice on the same PRD should produce the same plan.

## Example Usage

**User prompt:**
```
/prd-to-silver

prd_path: ./sample_business_requirements_source_onboarding.xlsx
target_dynamic_table: SILVER_AP_INVOICES
```

**Expected output** (abbreviated):

```
## PRD Analysis: SILVER_AP_INVOICES

### 1. New Source Systems
| Source | Platform | Region | Landing Pattern | Refresh Cadence | Status |
|--------|----------|--------|-----------------|-----------------|--------|
| Baan IV | Infor Baan | EMEA (NL + UK) | CSV → S3 nightly | ~02:00 UTC batch | Approved |
| Workday FM | Workday | Americas (US + CA) | Workday connector (hourly) | Hourly | Pending legal review |

### 2. Silver Layer Changes

#### 2b. Transformation Rules
| Rule ID | Affected Column | Logic | Notes |
|---------|-----------------|-------|-------|
| BR-001 | STATUS | CASE WHEN SOURCE_SYSTEM='BAAN' AND status='POSTED' THEN 'APPROVED' ... END | Adds Baan + Workday branches |
| BR-003 | (dedup) | QUALIFY ROW_NUMBER() OVER (PARTITION BY INVOICE_NUMBER ORDER BY CREATED_AT DESC)=1 | Baan-only; applied before UNION |
| BR-007 | SOURCE_SYSTEM | Hard-coded 'BAAN' / 'WORKDAY' literals | New UNION ALL branches |

### 5. Open Questions
| # | Rule ID | Question | Owner | Recommended Default |
|---|---------|----------|-------|---------------------|
| 1 | BR-005 | Normalize payment terms at Silver or Gold? | Sarah Chen / David Kim | Leave raw at Silver, normalize at Gold |
| 2 | SRC-2025-003 | Baan cost center format changed (BC-XX → BC-XXX). Normalize or pass through? | Karen van der Berg | Pass through as-is at Silver |
| 3 | SRC-2025-004 | Legal signoff (DPA-2025-0041) not yet complete. Proceed with implementation or wait? | Jennifer Okafor / Legal | Build and test; gate deployment on signoff |
```
