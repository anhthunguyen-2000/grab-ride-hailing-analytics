# Portfolio Validation and Review Items

Prepared **29 October 2026**. **Status: Published portfolio; source CSV provenance requires reconciliation before full reproduction.** This document was originally prepared during local packaging and is retained as an evidence record. The repository was subsequently published.

## Checks performed

| Check | Result and scope |
|---|---|
| Source review | Reviewed the SQL analyses and views, corrected working copies, schema/import scripts, dictionaries, workbook and Power BI guide, assumptions, generator/validator, generation records, business reports/outputs, PBIX metadata, PBIP/TMDL, theme, DAX and existing captures. Earlier start-guide statements about a missing dashboard were superseded by the completed artifacts. |
| SQL execution | All **67 nonempty batches** across eight portfolio scripts passed read-only execution checks after correcting a packaging extraction issue. The 12 reusable view definitions were exercised as their SELECT bodies; no CREATE/ALTER was deployed. Result row counts are recorded in [SQL checks](evidence/sql_execution_checks.json). |
| Full SQL syntax | All eight files were also parsed by SQL Server with PARSEONLY. This checks the full CREATE VIEW syntax without deploying it. The setup/import script is reviewed separately; it was not used to import or create tables. |
| Findings | Main values were independently queried from SQL Server. Evidence includes populations, wait percentiles, exposure, offer decisions, return groups, and current column schema in [verified_metrics.json](evidence/verified_metrics.json). |
| Data dictionary | All 102 source-column type families and NULL rules were compared against current SQL Server metadata. Length/precision declarations were taken from the delivered schema and dictionary. Derived report fields were compared with the saved model and view definitions. |
| KPI dictionary | Compared the delivered KPI CSV, analysis SQL, Power BI views and implemented DAX. SQL-only activation/monthly retention are explicitly separated from dashboard measures. |
| Model | Native `relationships.tmdl` endpoints match all 23 exported relationships. All are active, single direction, dimension 1 → fact *. The diagram contains all five connected facts and all six disconnected analytical/helper tables. FactCohort is the sixth fact. Shared dimensions repeat visually for readability. |
| Dashboard images | Updated on 29 October 2026 from the revised PBIX via native Power BI Desktop PDF export. The first four visible pages were rendered at **2,880 × 1,620** after excluding external PDF margins. All four were visually inspected. Latest labels, layout and original scrollable visual viewports are preserved; no editing interface or generated dashboard content is included. See [capture evidence](evidence/dashboard_capture.json). |
| CSV validation | Supplied validator rerun against the current original CSVs, redirecting only its output into this package: **94 PASS / 2 FAIL**. The failed checks are retained in [validation_checks.csv](evidence/validation_checks.csv). |
| Historical generation records | Seed 20261015, row counts and observation period agree with generator/summary. The historical record reports byte-identical regeneration and 96 passed checks; this task did not regenerate data and does not claim today's bundle meets that historical result. |
| References | Four conceptual sources were readable. Grab Help Centre returned a JavaScript/error screen; its policy contents remain unverified. Links and attribution are in [methodology](data_generation.md). |

## 1. Resolve trip-CSV provenance before reproduction

The current `data/trip_table.csv` in the original project differs from the SHA-256 in the recorded generation manifest. The other ten files match. Its event timestamps use minute-precision strings, while dispatch-offer response timestamps retain seconds. The cause/history of this file change cannot be established from the available evidence.

The two currently failed checks are `accepted_offer_reconciles_timestamp` and `no_overlap_driver_id`. Do not state that all 96 checks currently pass. Read-only SQL Server evidence verifies analytical counts and event-based KPIs independently, but does not certify the changed CSV. Original files were left intact.

Recommended owner action: locate an unmodified generated trip CSV or restore a reviewed source bundle in a **separate copy**. Compare all eleven hashes; rerun the supplied validator; reconcile event times and primary KPIs against the database. If regenerating, retain exact generator code and identity inputs and record runtime/library versions. Do not replace the database from the changed CSV until reconciliation succeeds.

## 2. Dashboard recapture completed

The earlier 1,016 × 572 captures have been replaced with **2,880 × 1,620 PNGs**, all 16:9, exported from the owner's revised PBIX saved on 29 October 2026 at 11:18 local UTC+7. A separate copy was opened in Power BI Desktop; the original PBIX was not saved, refreshed, or changed. Its SHA-256 was checked before and after export.

Power BI's native Export to PDF produced five visible analytical pages. The first four match Demand Overview, Booking Fulfillment, Driver Operations and Customer Retention. The exact report canvas was rendered from the PDF, excluding only its external margins. The prior small screenshots were not enlarged or reused.

All four pages were visually inspected. Headline values remain consistent with the saved analytical evidence: 125,923 requests, 22,983 failures, 183,703.1 online hours, and 89.8% 30-day return at display precision. The latest PBIX changes labels, navigation and annotations. The source PBIX retains its synthetic-data footer on Retention and omits it on the other three pages. After export, the owner requested removal of the two Retention footer lines from the PNG only; this edit leaves the dashboard visuals and source PBIX unchanged. The README labels every preview as synthetic.

The original scrollable tables, shortened labels and slicer rendering are retained. A single exported page shows the visual viewport, not every row in a scrolling visual. No source visual was resized or redesigned during capture.

For future updates: open a separate report copy, export to PDF locally, identify the first four visible pages, and render the full canvas at a consistent 16:9 size. Verify filters, values, labels and source-file hash before replacing the four PNGs.

## 3. Optional report distribution

The original PBIX is **31,484,994 bytes (about 30.0 MiB)**. It was intentionally excluded. It contains imported analytical data and machine-specific SQL source configuration. Although the source model excludes customer/driver names, phones and precise trip coordinates, a PBIX still needs a separate data-distribution and portability review. Refresh requires access to an equivalent SQL Server database and reviewed view definitions; cached data can be viewed without refreshing. This task does not approve or publish the PBIX.

The package instead includes four PNGs, the report theme, DAX, model relationships, dictionary and reconstruction instructions. These assets are not a runnable dashboard.

## Corrections preserved in copied SQL

- Customer summary: filter the request cohort by `created_at >= start AND created_at < cutoff`, not by nullable `finished_at`. The corrected SELECT returns 5,000 users and 125,923 requests. The original database view still has the old logic; it was not changed.
- Customer return: use a separate WHERE-filtered correlated minimum for the next different request group to avoid SQL Server error 8124. Keep the user and time-window restrictions.
- Data-quality overlap check: compare event starts with prior terminal ends/cutoff; the original draft incorrectly referenced start times as ends. A running maximum of previous ends also detects nested overlaps.
- Strip assignment identifiers and personal-name output columns from portfolio SQL. Preserve request/offer/exposure grain and the implemented analytical denominators.

The setup script and CREATE OR ALTER scripts are for an intentionally selected review database. Analytical SELECT checks were run against the existing source database without deploying them. Original source files and database objects remain unchanged.

## Reproduction boundary

No raw datasets, personal-looking seed identities, full generator, PBIX or PBIP are distributed. The package is reviewable analytical code and evidence, not a standalone public data release. Full execution requires a reconciled V2 source bundle or owner-provided database/report. A fresh import, full dashboard rebuild and interactive refresh on another machine were not performed.

## Final package checks

The initial local package check found Markdown links intact; the first GitHub upload placed documentation at repository root instead of `docs/`. A subsequent link-repair PR addresses that mismatch. code fences are balanced. A browser/GitHub-rendered visual preview of the README was not performed because no browser-control runtime or Markdown renderer was available. All four original dashboard captures and the generated model PNG were visually inspected. The README structure and tables were reviewed as Markdown.

All eight SQL scripts and the setup/import scaffold passed SQL Server syntax parsing. Source files were hashed before and after preparation: **340 files unchanged**. A credential-pattern/local-path scan found no matches in public text assets. This is a targeted hygiene check, not a universal secret-detection guarantee. No raw identities, report caches or database files are included. [Package checks](evidence/package_checks.json) and [provenance checks](evidence/provenance_check.json) record the results. See the [complete file inventory](file_inventory.md).

### Current capture-task link check

The four README image links resolve and the PNGs open successfully. During the wider link check, `docs/assumptions.md` was listed as a zero-byte entry and could not be read by the filesystem. This unrelated document was not modified as part of recapture; a complete current Markdown-link validation could not be confirmed. The earlier package-wide link result above records the initial packaging check.
