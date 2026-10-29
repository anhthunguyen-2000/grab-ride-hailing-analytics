# Synthetic Data Assumptions

This portfolio models a **synthetic** single-platform ride-hailing market in Ho Chi Minh City. All numerical parameters below are simulation assumptions, **not actual Grab statistics, service policies, or industry benchmarks**. Public articles supplied business concepts, not transaction records. See [data generation](data_generation.md), [limitations](limitations.md), and [validation](validation.md).

## Scope and time

- Observation period: **1 April–30 September 2026**, ending at **1 October 2026 00:00** (exclusive), local UTC+7.
- Seven approximate operating zones, not official administrative boundaries. Pickup/dropoff points sampled around zone centers (±0.003°).
- Two generic services: BIKE and CAR. The simulated driver pool is 700 BIKE and 300 CAR drivers within a 1,000-driver fleet.
- 5,000 synthetic user identities. User activity is heterogeneous; 65% registered before the observation period.
- Hourly demand weights reflect constructed weekday peaks and weekend patterns. Month-level demand includes a modeled increase of up to 12%, not measured company growth.

## Booking and dispatch mechanics

- Trip status: 1 CREATED; 2 ACCEPTED; 3 ONGOING; 4 FINISHED; 5 CUSTOMER_CANCELLED; 6 DRIVER_CANCELLED; 7 EXPIRED_NO_DRIVER.
- Offer outcomes: ACCEPTED, REJECTED, TIMEOUT, WITHDRAWN, PENDING. A withdrawn or pending offer is not treated as a driver rejection.
- Driver state categories: AVAILABLE, OFFER_PENDING, TO_PICKUP, WAITING_PICKUP, ON_TRIP, plus an OFFLINE snapshot.
- The event simulator sends sequential offers to available same-service drivers within an approximate 8-km road-distance radius; no concurrent offers are sent to one driver.
- Simulated request search timeout: **300 seconds**. This is not a Grab policy.
- Baseline per-driver offer acceptance likelihood: approximately 0.69–0.95, adjusted for modeled conditions such as ETA, rain and trip distance.
- A driver cancellation after acceptance closes that request. A further attempt becomes a **new request**, rather than automatic reassignment within the same `trip_id`.
- `parent_trip_id` points to an earlier failed request; `request_group_id` groups retries for the same intended journey. The generator allows limited retries, with at most one retry for some failures.

## Travel, weather and driver supply

- Estimated distance comes from Haversine distance × synthetic detour factor (1.15–1.50), with a 0.6-km floor; no road-network routing or GPS trajectories were observed.
- Base speeds were set to 24 km/h for BIKE and 26 km/h for CAR, with modeled peak, rain, nighttime and driver adjustments.
- Hourly rainfall is synthetic; it is not historical weather data.
- Driver online sessions last approximately 4–7 hours and may cross midnight.
- Driver-zone location is based on last-known operating events rather than continuous GPS coverage.
- Fifteen-minute supply cells integrate per-state driver-minutes across time intervals; driver-minutes are **not** the number of distinct drivers.

## Customer return and observation

- The generator includes a built-in behavior rule: after failed or long-wait requests (over 12 minutes), next-day request propensity is reduced for 14 days using a factor of 0.58. Any resulting relationship between poor experience and return is **simulator-driven**, not a real-world causal finding.
- Open requests at the observation cutoff stay open; they are not automatically classified as completed or failed.
- Seven-, fourteen- and thirty-day return metrics require full follow-up windows. Unobserved future cohort cells remain blank.
- Analyst thresholds (such as 10/12-minute waiting cutoffs or n ≥ 30 for stable segments) are analytical conventions, not official service levels.

## Reproducibility and current caveat

The generator records fixed seed `20261015`, but reproducing identical files also requires the same code, identity seed inputs and compatible runtimes. Current distributed source CSVs are **not fully reconciled**: the available validator reported **94 PASS / 2 FAIL**, with `trip_table.csv` differing from the recorded manifest. Therefore the portfolio does not claim fully reproducible current source CSVs. See [validation](validation.md) for the specific blockers.

## Interpretation boundaries

Do not apply simulated failure rates, waiting times, acceptance rates, utilization or retention as real Grab benchmarks. Demand–supply relationships are observational within the simulation, and scenario arithmetic is **not** an empirically estimated uplift. Pricing, incentives, cross-platform supply, GPS trajectories and external events are absent. This dataset is intended for SQL, KPI design and BI practice only.
