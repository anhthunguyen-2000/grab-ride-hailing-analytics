# ETA & Waiting Experience — implemented report update

The update extends the existing Desktop-exported PBIP. The source PBIX and earlier PBIP were backed up before editing; the latest PBIX was saved through Desktop as PBIP to retain later report changes. PBIX binary structure was not edited.

## Report behavior

- Booking Fulfillment keeps its five KPI cards and adds Average Total Wait (min) immediately before P90, using six equal-width cards without overlap.
- ETA groups use 3/6/12 minutes, with explicit sort order and Unknown for invalid ETA. The existing ETA cancellation visual uses valid matched ETA requests.
- ETA & Waiting Experience contains four waiting/quoted-ETA cards, a stage breakdown by service, one-minute ETA histogram, four percentile cards, cancellation rate lines by actor, a selected-group stacked actor chart, a dynamic cutoff comparison table and a conditionally formatted zone/service matrix.
- Date, Service and Pickup Zone slicers are copied from the existing report. All analytical values are model measures; no KPI is hardcoded.
- Cutoff percentiles recalculate in context; behavior boundaries were screened on full-period data and remain fixed alternatives. The table's counts and rates always recalculate in context. Its annotation explains the difference.
- Waiting and breakdown sample sizes are in tooltips; the histogram and cancellation chart show ETA sample size and n<30 flags in tooltips. The 20+ bucket is open-ended.

## Population rules

Overall actual wait requires recorded pickup plus valid total duration. The three stage means additionally require all durations, chronological events and additive identity on one common cohort. Missing or negative durations are excluded, never zero-filled. Quoted ETA uses matched requests with valid ETA. Actor rates share the same valid matched ETA denominator. Open matched requests remain included and are counted separately.

## Reproduce and validate

Use the reviewed database snapshot; the current minute-precision trip CSV does not reconcile to the original manifest. Run sql/03_demand_analysis.sql and sql/04_fulfillment_analysis.sql; deploy only the v_pbi_trip batch from sql/08_powerbi_preparation.sql for this update. Other views and all source tables are preserved. Refresh the local PBIP, then compare unfiltered and Date/Service/Zone-filtered DAX with SQL before saving/exporting through Desktop.

See [verified findings](../key_findings.md), [SQL evidence](../evidence/eta_waiting_20261124/sql_validation.json), and [change log](../CHANGELOG_20261124.md). PBIX, imported report caches, raw data and credentials remain local.

Full refresh and reopen validation passed: 20 Ready tables, 80 measures, 23 original relationships; 1,029 actual SQL/DAX comparisons. [Refresh evidence](../evidence/eta_waiting_20261124/powerbi_refresh_validation.json). The local model implements the four ETA/peak helper columns and both helper tables as native DAX calculations; SQL exposes equivalent derived columns.

[Portable helper DAX](eta_helpers.dax) records the actual calculated columns and disconnected tables. Sort eta_band by eta_band_order, eta_minute_bucket by eta_minute_order, and WaitStage[Stage] by WaitStage[Order].
