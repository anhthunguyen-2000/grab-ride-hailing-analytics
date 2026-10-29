# Limitations

This project uses synthetic ride-hailing data to demonstrate an end-to-end analytical workflow, from data validation and SQL analysis to KPI design and dashboard reporting. Its primary value lies in examining customer demand, booking behavior, and driver allocation within a defined simulation. The following considerations provide context for interpreting the results.

**Data design and operational assumptions**

Public references informed the operational concepts used to develop the dataset. All analytical records are simulated rather than sourced from confidential Grab systems, and the simulation parameters were not calibrated against verified operating benchmarks. The seven operating zones represent approximate analytical areas rather than official administrative boundaries or platform service territories.

Locations, distances, traffic, and weather are modeled to support scenario analysis. Distance estimates use Haversine distance with a detour factor, while driver location is represented by the last recorded zone. These approaches support aggregate comparisons but do not replicate road-level routing or continuous GPS tracking.

The simulation includes finite driver availability, sequential offers, cancellations, and retries. It simplifies other aspects of dispatch operations, including drivers working across multiple apps, demand that never becomes a booking request, and external events or policy changes.

**Interpretation of behavioral findings**

Demand patterns and selected customer behaviors are partly defined by the data-generation rules. Findings should therefore be interpreted as relationships within the simulated environment and as hypotheses for further investigation.

The 30-day return analysis describes observed differences between customer groups; it does not isolate the causal impact of waiting or cancellation. For example, customers whose requests expired showed a higher return rate than the short-wait group in the selected cohort. This highlights the importance of considering cohort composition and shared conditions when interpreting results. Proposed experiments outline potential next steps and have not yet been conducted.

**Observation period and metric coverage**

The six-month observation period supports comparisons across the available months, weekdays, and time slots. Annual seasonality and longer-term retention would require a longer dataset. For users registered before April, earlier activity is not fully observed, so their first recorded booking may not be their first-ever booking.

Return analysis uses bookings with a terminal status and complete follow-up periods. Incomplete observation windows are excluded, and cohort cells remain blank until sufficient follow-up is available. Waiting-time percentiles cover requests with an observed pickup and should be interpreted alongside cancellation and expiry metrics to assess the broader booking experience.

Metric definitions also reflect different units of analysis: requests, independent journeys, customers, and offers use different denominators. Driver exposure is measured in time, and occupied time includes travel to pickup and waiting at pickup. These measures describe operational activity; financial and safety assessments would require additional data on fares, earnings, costs, and safety outcomes.

**Reproducibility and source consistency**

The numerical findings presented in this package are supported by read-only SQL Server query evidence. Reproduction from the currently supplied CSV remains pending: the trip file differs from its historical checksum, has reduced timestamp precision, and currently produces two failed validator checks. Resolving these discrepancies is an outstanding step before the CSV can be treated as a verified reproduction source.

The repository documents the available methodology and analytical logic. Exact original Python/pandas versions, a complete AI prompt history, and identity-generation seeds are not fully included, so it is not a standalone release of the complete data generator.

**Application of results**

This project demonstrates analytical methods and develops operational hypotheses using a simulated ride-hailing process. Applying its findings to real Grab operations, industry comparisons, customer policies, or business forecasts would require validation with actual operational data and, where relevant, controlled experiments.
