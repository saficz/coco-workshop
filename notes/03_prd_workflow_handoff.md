# PRD Workflow Handoff

Artifacts produced by the PRD-driven update to `SILVER_AP_INVOICES`.

## Artifact Inventory

| # | File | Purpose |
|---|------|---------|
| 1 | `.cortex/skills/prd-to-silver/SKILL.md` | The PRD Evaluator skill definition. Another engineer loads this via `/prd-to-silver` to re-run the analysis workflow on a new or updated PRD. |
| 2 | `.cortex/plans/plan_2026-08-19_1605.md` | The approved implementation plan — column mapping, source tables, verification criteria. Serves as the "design decision record" for review. |
| 3 | `silver_ap_invoices.sql` | The final Dynamic Table DDL (4 UNION ALL branches: SAP, Oracle, Baan, Workday) with inline business-rule comments (BR-001 through BR-008). |
| 4 | `silver_ap_invoices_validation.sql` | 9 post-refresh validation queries (row counts, NULL checks, dedup, status normalization, schema shape). Run these to re-verify correctness. |

## Not in the repo (but relevant)

- The original PRD/XLSX input file was consumed interactively but not committed — consider adding it if it's not sensitive.
- The Snowflake objects themselves (`COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES` and the four Bronze source tables) live in the account, not in version control.

## Reusing the PRD Evaluator Skill

Another engineer runs `/prd-to-silver` in Cortex Code and provides:

- `prd_path` — path to their requirements file
- `target_dynamic_table` — the DT to plan changes for

The skill walks them through parsing, impact classification, open-question surfacing, and plan generation before any SQL is written.

## Re-running Validation

After the Dynamic Table refreshes, execute `silver_ap_invoices_validation.sql` in order. Each query includes an inline "Expected" comment describing the passing condition.
