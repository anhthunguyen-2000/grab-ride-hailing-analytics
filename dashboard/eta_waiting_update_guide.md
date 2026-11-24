# ETA & Waiting Experience — Power BI implementation

## Required KPI card
Add the measure `Average Total Wait Min` from `measures.dax` to Grab Measures in Power BI Desktop. On Grab | Booking Fulfillment, duplicate the existing P90 Total Wait card, replace its field with Average Total Wait Min, remove the P90-specific report-page tooltip, and label it Average Total Wait (min). Use two decimals. Keep the other five cards. On the uploaded 1280 × 720 report, use six cards at x=24, 231, 438, 645, 852, 1059, y=203, height=82, width=197. The metric averages observed nonnegative pickup waits; cancelled and expired requests without pickup are excluded.

## ETA detail
- Histogram: matched requests by one-minute quoted pickup ETA bucket; 20+ is open-ended.
- Line chart: post-match cancellation rate by one-minute ETA bucket; show matched requests and customer/driver cancellation rates in tooltip.
- Compare proposed ETA time cutoffs: P25/P50/P75/P90 versus 3/6/12 minutes, showing rate gap in percentage points and both sample sizes.
- Waiting time breakdown: allocation, approach and pickup dwell averages calculated on the same valid pickup-stage sample.
- Validate separately by service and pickup zone before adopting cutoffs; do not treat full-period aggregates as dynamically slicable.
- Current SQL and Power BI ETA groups remain unchanged until exploratory results support a common set of cutoffs.

## Validation
Run the added batches in 04_fulfillment_analysis.sql on the reviewed database, compare the average against DAX on the same population, refresh the report and verify slicers. No new average or percentile result has been verified yet. The PBIX model and report visuals have not been edited in this environment; screenshots remain the original exports.
