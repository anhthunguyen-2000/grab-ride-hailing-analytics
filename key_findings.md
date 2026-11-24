# Executive Findings

**Synthetic ride-hailing case study | 1 April–30 September 2026 | UTC+7**

The objective is to identify operational friction and propose measurable tests. The analysis covers 125,923 requests, 121,297 independent journeys, and 4,977 requesting customers. Counts and the main KPI values below were verified through read-only SQL Server. They describe a simulation, not Grab operations.

| Finding | Supporting KPI | Interpretation and next step |
|---|---|---|
| Fulfillment failures are concentrated enough to prioritize locally | 22,983 / 125,923 requests failed: **18.25%**. Another 102,931 completed and nine remained open. | Use failure count, rate, and sample size together. Northeast BIKE at 07:00 has 638 failures / 1,022 requests; 484 are expiries. Test targeted morning availability rather than assume uniform citywide shortage. |
| Successful matching can still produce long pickup waits | 22,124 / 102,931 completions waited >12 minutes: **21.49%**. P90 wait across all 102,936 observed pickups is **20.45 minutes**. | Central BIKE at 17:00 contributes 1,271 long-wait completions from 2,938 requests. Test pickup-time-aware assignment. Measure timely completions per all assigned requests to prevent apparent improvement from excluding difficult bookings. |
| Some matched requests are cancelled before pickup | 8,532 / 111,471 accepted requests cancel: **7.65%**. Central BIKE at 17:00 contributes 457. | Test clearer pickup confirmation and communication. The simulated reason labels support questions to investigate; they do not independently establish causes. |
| Driver time has distinct operational uses | **183,703.13 online hours**, **31.36% occupied utilization**, **24.15% on-trip utilization**. Offers accepted: 111,471 / 169,639 decision-or-timeout offers: **65.71%**. | Separate approach/waiting from passenger-carrying time and investigate local exposure. Neither a citywide utilization average nor acceptance alone proves the cause of an unserved request. |
| Return patterns do not support a universal failure penalty | 4,381 / 4,877 eligible customers start a new journey within 30 days: **89.83%**. | Short-wait completion: 90.40%; long-wait completion: 88.14%; cancellation: 87.21%; expiry: 91.18%. Expiry return is higher than short-wait completion, so avoid a blanket claim that failure lowers return. These are associations with embedded simulation rules. |

## Operational priorities and proposed tests

The existing business-priority analysis ranks three mutually exclusive observed problems by affected request volume: long-wait completions (22,124), no-driver expiries (11,359), and post-match cancellations (8,532). Their affected-user populations overlap. This ranking does not quantify financial loss or severity.

For Central BIKE at 17:00, evaluate pickup-time-aware assignment in randomized zone/time switchback blocks. Predeclare completion, expiry, allocation delay, driver approach exposure, and adjacent-zone effects as guardrails. Test pickup confirmation separately or use a planned factorial design so overlapping interventions remain interpretable.

For Northeast BIKE mornings, test voluntary positioning guidance and capped availability support in comparable randomized operating blocks. Measure actual incremental available driver-minutes and neighboring-zone displacement. Real earnings, incentive costs, and safety data are required before launch. Power and pilot duration should come from a real baseline and cluster-aware design, not synthetic counts alone.

For customer experience, treat 30-day return as a secondary, fully observed outcome. Use one first-observed terminal index per user and exclude retries from the same journey. Cancellation indices include both cancellation stages; they are not identical to the post-match-only operational population.

## Scenario, not a forecast

A fixed baseline of 22,983 failures gives 1,149.15 / 2,298.30 / 3,447.45 assumed avoided failures under 5% / 10% / 15% **relative** reductions. These are arithmetic expectations, not measured uplift or guaranteed extra completions. No revenue or ROI estimate is supported.

## Evidence and interpretation limits

[Verified metrics](evidence/verified_metrics.json) support population, waits, supply, acceptance and return values. [Business priorities](evidence/business_priorities.csv) support the ranked counts and target cells; [scenario evidence](evidence/failure_scenarios.csv) supports the arithmetic. Reproduce with [business-insights SQL](sql/07_business_insights.sql), [fulfillment SQL](sql/04_fulfillment_analysis.sql), and [customer SQL](sql/06_customer_analysis.sql). [SQL execution checks](evidence/sql_execution_checks.json) record executed batches; view bodies were tested as SELECTs, not deployed.

The generator imposes demand, ETA, acceptance, weather and experience mechanisms. Findings demonstrate an analytical workflow, not real-world causal effects. The current trip CSV fails two supplied validation checks after timestamp precision loss; the database evidence remains the basis for reported findings. See [validation](validation.md) before attempting reproduction or publication.



## ETA and waiting experience — verified SQL update, 24 November 2026

Actual execution on the reviewed database, requests created in **[1 April, 1 October 2026)**, local UTC+7. [Validation evidence](evidence/eta_waiting_20261124/sql_validation.json) reconciles request counts and accepted-offer timestamps with the previously verified database. The changed minute-precision trip CSV remains unsuitable for replacing that database; no CSV was reimported.

Among **102,936 pickups**, average actual total wait is **7.41 min**, median **3.55 min**, P90 **20.45 min**. All 102,936 also have complete valid stages: allocation **0.32**, approach **6.08**, pickup dwell **1.00 min**. Approach accounts for **82.2%** of the average. Stage components use the same cohort. The unrounded SQL averages sum within 0.00001 min because SQL decimal AVG retains six fractional digits.

Quoted ETA is a different measure: **111,471 matched requests**, mean **6.70**, P25 **1.64**, P50 **2.29**, P75 **10.66**, P90 **20.37**, range **1.00–36.16 min**. BIKE P75 is **9.1825 min**, CAR P75 **14.12 min**; a common percentile boundary has different operational meaning across services. Exact values are retained in [distribution output](evidence/eta_waiting_20261124/eta_distribution.csv).

| Selected ETA group | Matched n | Customer cancellations | Driver cancellations | Post-match cancellation rate |
|---|---:|---:|---:|---:|
| 01 | <3 min | 70,974 | 1,358 | 1,100 | 3.46% |
| 02 | 3-<6 min | 6,650 | 180 | 118 | 4.48% |
| 03 | 6-<12 min | 7,788 | 461 | 228 | 8.85% |
| 04 | 12+ min | 26,059 | 3,605 | 1,482 | 19.52% |


**Selected ETA groups: retain 3/6/12 minutes**, with lower-inclusive, upper-exclusive bins and a separate Unknown category. SQL now agrees with the existing dashboard. The four groups have adequate overall and service samples; rates increase across the groups for both BIKE and CAR and separately in each of six months and three peak periods. This supports retaining an understandable reporting scheme, not claiming a universal operational or causal threshold.

The minute analysis uses an explicitly exploratory screen: an increase of at least **1 percentage point** from the immediately preceding minute, with at least **30 matched requests in each**. Rises occur at several different minutes and differ by service. The 5–<6 minute bucket has only **99** observations overall (55 BIKE, 44 CAR), making a split around five minutes fragile after further slicing. Empty minute buckets remain in the output; the 20+ bucket is open-ended, so its comparison to 19–<20 is not an equal-width minute comparison.

The complete group-set evaluation covers service, zone, peak period, month, and all 42 zone/service/peak cells. Some cells have no observations in a particular ETA group, and **four populated cells have n<30** (minimum n=7). Northeast's marginal <3 and 3–<6 rates are not monotone; several fine-grained cells also reverse the overall pattern. Do not apply these cutoffs as universal service guarantees or use small cells to drive operational changes. [Group-set results](evidence/eta_waiting_20261124/eta_group_set_evaluation.csv) and [cutoff comparison](evidence/eta_waiting_20261124/proposed_eta_cutoff_comparison.csv) retain those limitations.

All cutoff comparisons retain exact continuous-percentile values and report both cancellation counts, both denominators, rates and percentage-point differences. Choosing the largest gap alone would favor extreme cutoffs without establishing a useful intervention. n≥30 is only a screening condition, not evidence of statistical significance. The data are synthetic, and observed association does not establish causation.

The snapshot has **nine open requests**, including **eight matched** requests; they remain in matched denominators and are reported separately. No recorded event occurs at or after the exclusive observation cutoff. The existing full-period versus excluding-last-24-hours sensitivity analysis is preserved.
