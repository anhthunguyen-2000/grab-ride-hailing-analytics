# KPI Dictionary

| KPI | Business definition | Formula | Numerator / input | Denominator / population | Data source | Important notes |
|---|---|---|---|---|---|---|
| Total Requests | Booking submissions, including retries | COUNTROWS(FactTrips) | All request rows | Not a ratio | trip_table → FactTrips | Request creation date; unresolved bookings remain included. |
| Active Customers | Customers who submitted at least one request | DISTINCTCOUNT(FactTrips[user_id]) | Distinct requesting users | Not a ratio | FactTrips | Not all registered users or customers with completed rides. |
| Completed Requests | Finished bookings | COUNT(status=4) | Status-4 requests | Not a ratio | FactTrips | Distinct from matched and picked-up requests. |
| Match Rate | Share ever accepted by a driver | matched / requests | accepted_at is not NULL | All requests | FactTrips | Use timestamp history, not current status 2. |
| Completion Rate | Share completed in the request cohort | completed / requests | status=4 | All requests | FactTrips | Includes open bookings in denominator. |
| Closed Completion Rate | Completion among resolved requests | completed / (completed+failed) | status=4 | status IN (4,5,6,7) | FactTrips | Excludes open 1/2/3; not interchangeable with request-based completion. |
| Failure Rate | Share ending in cancellation or expiry | failed / requests | status IN (5,6,7) | All requests | FactTrips | Not 1−completion when open requests exist. |
| Cancellation Rate | Share cancelled by either actor | cancelled / requests | status IN (5,6) | All requests | trip_table; DAX Cancelled Requests / Requests | SQL reports actor-specific rates too; cancellation share instead divides by all cancellations. |
| Post-match Cancellation Rate | Cancellation after acceptance | post-match cancellations / matched | status IN (5,6) AND accepted_at not NULL | Matched requests | FactTrips | Includes both customer and driver actors; a different denominator from cancellation rate. |
| Median Allocation Time | Median request-to-accept duration | MEDIANX(nonblank allocation_sec /60) | Observed allocation durations in minutes | Matched observations (sample) | v_trip_enriched → FactTrips | Continuous median, NULLs excluded. Not approach time. |
| P90 Total Waiting Time | 90th percentile from submission to pickup | PERCENTILEX.INC(nonblank total_wait_sec /60,0.9) | Observed pickup waits in minutes | Requests with observed pickup (sample) | FactTrips | Includes ongoing pickups; 102,936 full-period samples. Not completed-only; no average of subgroup P90s. |
| Online Hours | Total integrated online exposure | SUM(online_driver_minutes)/60 | Online driver-minutes | 60 minutes/hour | FactSupply | Additive exposure; not unique drivers. Do not multiply by requests. |
| Available Hours | Exposure free to accept an offer | SUM(available_driver_minutes)/60 | AVAILABLE driver-minutes | 60 minutes/hour | FactSupply | Last-known-zone approximation. |
| Occupied Utilization | Online time approaching, waiting or carrying | SUM(occupied_driver_minutes)/SUM(online_driver_minutes) | TO_PICKUP + WAITING_PICKUP + ON_TRIP minutes | Online minutes | FactSupply | OFFER_PENDING excluded from occupied; occupied is a subtotal, not a sixth stacked state. |
| On-trip Utilization | Passenger-carrying share of online time | SUM(on_trip_driver_minutes)/SUM(online_driver_minutes) | ON_TRIP minutes | Online minutes | FactSupply | Does not measure profit or driver earnings. |
| Offer Acceptance Rate | Acceptance of decided or timed-out offers | ACCEPTED/(ACCEPTED+REJECTED+TIMEOUT) | Accepted offers | Accepted, rejected and timed-out offers | FactOffers | WITHDRAWN/PENDING excluded. Offer-level, not request-level. |
| Trips per Online Hour | Driver productivity on activity dates | Driver Completed Trips / Driver Online Hours | Completions dated by finished_at | Online hours split by calendar date | v_driver_day → FactDriverDay | Aggregate both components before dividing; pickup-zone slicer does not filter citywide productivity. |
| Activation Rate (7D) | In-period signups requesting in first seven days | activated eligible signups / eligible signups | Eligible users with created_at >= registered_at and < registered_at+7d | In-period signups with registered_at+7d <= cutoff | user_table + trip_table; customer SQL | Pre-period signups excluded. Implemented in SQL, not a separate dashboard DAX measure. |
| Monthly Retention Rate | Active month-M requesters active in M+1 | retained_next_month_users / active_users | Distinct users requesting in M and M+1 | Distinct users requesting in M | customer SQL | Requires entire next month observed; September next-month rate is NULL. Not 30-day return. |
| Cohort Retention | Activity by age month of first-observed request cohort | active cohort users / original cohort size | Cohort users requesting at age month | Original cohort members | v_cohort_monthly → FactCohort | Not signup cohort or first-ever usage. Future cells absent/BLANK; DAX suppresses totals/subtotals. |
| Return Rate 30D | New-journey request within 30d after first observed index ends | returned eligible users / eligible users | Eligible users with different request_group_id, created_at > index_end_at and <= index_end_at+30d | One terminal index/user with complete 30d follow-up | v_retention30_user → FactRetention30 | Filter eligible_30d=1. Same-group retries excluded; SQL also reports inclusive return as sensitivity. |
| Pressure Proxy | Request load relative to available exposure | requests/(available_driver_minutes/60) | Requests at zone/service/time grain | Available driver-hours at same grain | v_zone_service_15min; driver SQL | Zero exposure gives NULL and a separate flag. A descriptive ratio, not a probability. |
| Long-wait Completion Share | Completions with observed pickup wait >12 minutes | long-wait completions / completed requests | status=4 AND total_wait_sec>720 | Completed requests with observed wait | business SQL; FactTrips | 22,124/102,931; differs from P90 population, which includes five ongoing pickups. |
| Average Requests per Day | Calendar-exposure-normalized demand | requests / observed calendar days | Requests in selected context | Calendar days in context, including zero-request days | DimDate + FactTrips; calendar SQL | Weekday/hour heatmap retains all 168 cells. Do not compare unequal pooled weekday/weekend exposures as intensity. |
| Avoided Failures Scenario | Arithmetic expected count under an assumed relative reduction | failed requests × selected reduction | Baseline failed requests × 0.05/0.10/0.15 | Not a ratio | Scenario selector + Failed Requests | Fractional expectations retained. No forecast, causal uplift, or automatic additional completion. |

## Similar measures that must remain separate

- **Match vs completion:** acceptance can precede cancellation; accepted timestamps remain populated after cancellation. Full period: 111,471 matched and 102,931 completed.
- **Request vs closed completion:** 102,931/125,923 vs 102,931/125,914. Nine requests are still open. Failure is not exactly one minus request completion.
- **Cancellation rate vs share:** cancellations/all requests measures operational incidence; actor/reason cancellations/all cancellations measures composition. Post-match cancellation uses matched requests.
- **Return vs monthly retention:** 30-day follow-up begins after the terminal index event; monthly retention compares calendar-month activity. Both differ from activation after signup.
- **Wait vs ETA:** total wait includes allocation, approach and pickup dwell. Quoted pickup ETA is recorded at acceptance; ETA accuracy compares it with actual approach duration, not total wait.
- **Occupied vs on-trip:** occupied includes approach and pickup waiting. Supply exposure uses integrated seconds rounded into minutes; tiny aggregate rounding residuals are disclosed.

## Implementation references

[Analytical SQL](sql/06_customer_analysis.sql), [business evidence SQL](sql/07_business_insights.sql), [Power BI views](sql/08_powerbi_preparation.sql), and [all implemented DAX](dashboard/measures.dax). Activation, monthly retention, and the combined cancellation rate are documented from SQL; no absent dashboard measure is claimed.
