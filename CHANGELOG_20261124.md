# ETA and waiting update — 24 November 2026

| File | Change and reason | Validation |
|---|---|---|
| sql/03_demand_analysis.sql | Scope numerator to same period as calendar denominator; preserve total-based Top 5 ranking; mark modified logic. | Actual SQL before/after outputs identical on current snapshot; 131 weekdays and 52 weekends. |
| sql/04_fulfillment_analysis.sql | Extend merged PR #3 with complete-stage waits, 61 ETA scopes, 21 minute bins, actor/open counts, exact distribution/behavior/legacy cutoff comparisons, full group-set evaluation and quality checks; retain legacy questions. | 20 batches executed successfully; 265 SQL checks passed including preserved legacy outputs. |
| sql/08_powerbi_preparation.sql | Add ordered minute bins, selected ETA sort key and existing peak-period definition; invalid ETA → Unknown. | Only v_pbi_trip deployed; original definition backed up; source tables untouched. |
| dashboard/measures.dax | Publish actual implemented measures, coherent populations, explicit blank guards, shared actor denominator and dynamic cutoff calculations. | See Power BI reconciliation evidence for actual execution status. |
| dashboard/eta_waiting_update_guide.md | Record implemented page, model populations and reproduction boundary. | Reviewed against SQL and PBIP source. |
| kpi_dictionary.md | Explain numerator, denominator, stage cohort, cutoff rules and formats. | Checked against actual SQL and model definitions. |
| data_dictionary.md | Document four new derived columns, two disconnected helper tables and unchanged grain/relationships. | PBIP/TMDL and SQL view definitions. |
| key_findings.md | Add actual wait/ETA results, cutoff decision, subgroup exceptions and sample limitations. | SQL outputs; no invented results. |
| README.md | Link new page, findings, evidence and change log. | Local link and artifact checks. |
| evidence/eta_waiting_20261124/* | Actual SQL result sets, calendar exposure, provenance, quality, subgroup and model reconciliation evidence. | Existing verified snapshot; CSV discrepancy explicitly retained. |
| dashboard/02_fulfillment.png, dashboard/05_eta_waiting_experience.png | Native report exports after model validation. | Capture evidence records actual final export status. |

PR #2 and #3 were already merged into main before this work. Original local folders had no Git checkout; no uncommitted user changes were overwritten. A separate checkout preserves repository history. The original PBIX and earlier PBIP are backed up under the local powerbi/backups/20261124_before_eta_waiting folder. Public source/evidence excludes raw data, credentials, PBIX and report caches.


## Completed model verification — 24 November 2026

Full SQL source refresh completed in Power BI Desktop. After reopening the saved PBIP, **20/20 tables are Ready**, with **80 measures** and the original **23 relationships**. **1,029 actual SQL/DAX comparisons passed**, covering overall, 42 zone/service/peak cells, minute buckets, 25 exact cutoff alternatives, calendar denominators and a combined date/service/zone context. Overall KPIs after the full refresh match the independently reconciled results. See [refresh evidence](evidence/eta_waiting_20261124/powerbi_refresh_validation.json) and [SQL/DAX reconciliation](evidence/eta_waiting_20261124/powerbi_reconciliation.json).

The local model uses calculated DAX helper columns and two calculated helper tables, preserving the FactTrips SQL projection. Source query grants are capped at 1% with MAXDOP 1 because SQL Express reported physical-memory pressure and RESOURCE_SEMAPHORE waits; query predicates and KPI semantics are unchanged. Native SELECT approvals were completed in Desktop. No server configuration, source rows, raw CSVs or credentials were changed.


## Saved deliverables

The native PBIX and PBIP are saved locally. The final PBIX was reopened: 20 Ready tables, 80 measures, 23 preserved relationships, 11 pages (six visible), and KPI values matching the SQL-reconciled model. Both updated screenshots were exported from the report and visually reviewed. Scrollable tables show a viewport; full cutoff and subgroup outputs remain in CSV evidence. [Native artifact verification](evidence/eta_waiting_20261124/pbix_reopen_validation.json).

The unchanged historical CSV discrepancy remains documented; this update used the previously verified database snapshot and did not reimport, regenerate or modify raw data. No required analysis/report step remains blocked.
