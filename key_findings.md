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
