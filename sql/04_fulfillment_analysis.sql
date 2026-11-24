-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
-- FULFILLMENT & CANCELLATION ANALYSIS
-- Track requests through the booking funnel
SELECT
    COUNT(t.trip_id) AS total_request,
    COUNT(t.accepted_at) AS accepted_requests,
    COUNT(t.pickup_at) AS picked_up_requests,
    COUNT(t.finished_at) AS completed_requests,
    ROUND(COUNT(t.accepted_at) * 100.0 / NULLIF(COUNT(t.trip_id), 0), 2) AS match_rate,
    ROUND(COUNT(t.finished_at) * 100.0 / NULLIF(COUNT(t.trip_id), 0), 2) AS completion_rate
FROM trip_table t
WHERE t.created_at >= '20260401' AND t.created_at < '20261001';
GO
-- Compare match and completion rates by zone, hour, and service.
SELECT
    t.pickup_zone_id,
    z.zone_name AS pickup_zone,
    te.trip_hour,
    t.service_type,
    COUNT(t.trip_id) AS total_request,
    COUNT(t.accepted_at) AS accepted_requests,
    COUNT(t.finished_at) AS completed_requests,
    SUM(CASE WHEN t.status IN (1, 2, 3) THEN 1 ELSE 0 END) AS open_requests,
    ROUND(COUNT(t.accepted_at) * 100.0 / COUNT(t.trip_id), 2) AS match_rate,
    ROUND(COUNT(t.finished_at) * 100.0 / COUNT(t.trip_id), 2) AS completion_rate,
    CASE WHEN COUNT(t.trip_id) < 30 THEN 1 ELSE 0 END AS small_sample
FROM trip_table t
INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
LEFT JOIN zone_table z ON t.pickup_zone_id = z.zone_id
WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
GROUP BY t.pickup_zone_id, z.zone_name, te.trip_hour, t.service_type
ORDER BY small_sample, completion_rate, match_rate, total_request DESC;
GO
-- Identify where and how booking requests fail
WITH request_outcome AS (
    SELECT
        CASE
            WHEN t.status = 4 THEN 'completed'
            WHEN t.status IN (5, 6) AND t.accepted_at IS NULL THEN 'cancel_before_match'
            WHEN t.status IN (5, 6) THEN 'cancel_after_match'
            WHEN t.status = 7 THEN 'expired_no_driver'
            WHEN t.status = 1 THEN 'open_searching'
            WHEN t.status = 2 THEN 'open_matched'
            WHEN t.status = 3 THEN 'open_on_trip'
            ELSE 'unknown_status'
        END AS outcome_group
    FROM trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
)
SELECT
    outcome_group,
    COUNT(*) AS total_request,
    SUM(COUNT(*)) OVER () AS all_requests,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS request_share
FROM request_outcome
GROUP BY outcome_group
ORDER BY total_request DESC;
GO
-- Analyze cancellation
---- Cancellation share?; cancellation rate?
WITH cancellation_by_actor AS (
    SELECT
        COALESCE(t.cancelled_by, 'unknown') AS cancelled_by,
        COUNT(*) AS cancelled_requests
    FROM trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
        AND t.status IN (5, 6)
    GROUP BY COALESCE(t.cancelled_by, 'unknown')
)
SELECT
    cancelled_by,
    cancelled_requests,
    SUM(cancelled_requests) OVER () AS all_cancellations,
    ROUND(cancelled_requests * 100.0 / SUM(cancelled_requests) OVER (), 2) AS cancellation_share,
    ROUND(cancelled_requests * 100.0 / NULLIF((
        SELECT COUNT(*)
        FROM trip_table
        WHERE created_at >= '20260401' AND created_at < '20261001'
    ), 0), 2) AS cancellation_rate
FROM cancellation_by_actor
ORDER BY cancelled_requests DESC;
GO
---- Cancellation reason (cancellation_stage)
SELECT
    COALESCE(t.cancelled_by, 'unknown') AS cancelled_by,
    COALESCE(t.cancel_reason, 'unknown') AS cancel_reason,
    te.cancellation_stage,
    COUNT(t.trip_id) AS cancelled_requests,
    ROUND(COUNT(t.trip_id) * 100.0 / SUM(COUNT(t.trip_id)) OVER (), 2) AS cancellation_share,
    ROUND(COUNT(t.trip_id) * 100.0 / NULLIF((
        SELECT COUNT(*)
        FROM trip_table
        WHERE created_at >= '20260401' AND created_at < '20261001'
    ), 0), 2) AS cancellation_rate
FROM trip_table t
INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
    AND t.status IN (5, 6)
GROUP BY COALESCE(t.cancelled_by, 'unknown'), COALESCE(t.cancel_reason, 'unknown'),
    te.cancellation_stage
ORDER BY cancelled_requests DESC;
GO
-- [MODIFIED] Compare allocation and waiting; exclude invalid durations without zero imputation.
WITH waiting_time AS (
    SELECT
        t.pickup_zone_id,
        z.zone_name AS pickup_zone,
        t.service_type,
        CASE
            WHEN te.trip_hour BETWEEN 7 AND 8 THEN 'morning_peak'
            WHEN te.trip_hour BETWEEN 16 AND 18 THEN 'evening_peak'
            ELSE 'off_peak'
        END AS peak_period,
        CASE WHEN te.allocation_sec >= 0 THEN te.allocation_sec / 60.0 END AS allocation_min,
        CASE WHEN t.pickup_at IS NOT NULL AND te.total_wait_sec >= 0 THEN te.total_wait_sec / 60.0 END AS total_wait_min
    FROM trip_table t
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    LEFT JOIN zone_table z ON t.pickup_zone_id = z.zone_id
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
),
waiting_summary AS (
    SELECT
        pickup_zone_id,
        pickup_zone,
        service_type,
        peak_period,
        COUNT(*) OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS total_request,
        COUNT(allocation_min) OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS allocation_sample_size,
        COUNT(total_wait_min) OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS waiting_sample_size,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY allocation_min)
            OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS median_allocation_min,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY allocation_min)
            OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS p90_allocation_min,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_wait_min)
            OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS median_total_wait_min,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY total_wait_min)
            OVER (PARTITION BY pickup_zone_id, service_type, peak_period) AS p90_total_wait_min
    FROM waiting_time
)
SELECT DISTINCT
    pickup_zone_id,
    pickup_zone,
    service_type,
    peak_period,
    total_request,
    allocation_sample_size,
    waiting_sample_size,
    ROUND(median_allocation_min, 2) AS median_allocation_min,
    ROUND(p90_allocation_min, 2) AS p90_allocation_min,
    ROUND(median_total_wait_min, 2) AS median_total_wait_min,
    ROUND(p90_total_wait_min, 2) AS p90_total_wait_min
FROM waiting_summary
ORDER BY pickup_zone_id, service_type, peak_period;
GO
-- Measure the accuracy of quoted pickup ETA
WITH eta_error AS (
    SELECT
        t.pickup_zone_id,
        z.zone_name AS pickup_zone,
        t.service_type,
        t.quoted_pickup_eta_min,
        te.approach_sec / 60.0 AS actual_approach_min,
        te.approach_sec / 60.0 - t.quoted_pickup_eta_min AS signed_error_min,
        ABS(te.approach_sec / 60.0 - t.quoted_pickup_eta_min) AS absolute_error_min
    FROM trip_table t
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    LEFT JOIN zone_table z ON t.pickup_zone_id = z.zone_id
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
        AND te.approach_sec >= 0
        AND t.quoted_pickup_eta_min >= 0
),
eta_summary AS (
    SELECT
        pickup_zone_id,
        pickup_zone,
        service_type,
        COUNT(*) OVER (PARTITION BY pickup_zone_id, service_type) AS eta_sample_size,
        AVG(quoted_pickup_eta_min) OVER (PARTITION BY pickup_zone_id, service_type) AS average_quoted_eta_min,
        AVG(actual_approach_min) OVER (PARTITION BY pickup_zone_id, service_type) AS average_actual_approach_min,
        AVG(signed_error_min) OVER (PARTITION BY pickup_zone_id, service_type) AS average_signed_error_min,
        AVG(absolute_error_min) OVER (PARTITION BY pickup_zone_id, service_type) AS average_absolute_error_min,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY signed_error_min)
            OVER (PARTITION BY pickup_zone_id, service_type) AS median_signed_error_min,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY absolute_error_min)
            OVER (PARTITION BY pickup_zone_id, service_type) AS p90_absolute_error_min
    FROM eta_error
)
SELECT DISTINCT
    pickup_zone_id,
    pickup_zone,
    service_type,
    eta_sample_size,
    ROUND(average_quoted_eta_min, 2) AS average_quoted_eta_min,
    ROUND(average_actual_approach_min, 2) AS average_actual_approach_min,
    ROUND(average_signed_error_min, 2) AS average_signed_error_min,
    ROUND(average_absolute_error_min, 2) AS average_absolute_error_min,
    ROUND(median_signed_error_min, 2) AS median_signed_error_min,
    ROUND(p90_absolute_error_min, 2) AS p90_absolute_error_min
FROM eta_summary
ORDER BY pickup_zone_id, service_type;
GO
-- [MODIFIED] PR #3 exploratory batches are expanded below to report sample sizes,
-- service/zone/period stability, exact cutoffs, and a common valid-stage cohort.
-- [MODIFIED] Selected ETA groups: retain dashboard 3/6/12 until evidence warrants a change.
WITH eta_booking AS (
    SELECT
        CASE
            WHEN t.quoted_pickup_eta_min IS NULL OR t.quoted_pickup_eta_min < 0 THEN 'Unknown'
            WHEN t.quoted_pickup_eta_min < 3 THEN '01 | <3 min'
            WHEN t.quoted_pickup_eta_min < 6 THEN '02 | 3-<6 min'
            WHEN t.quoted_pickup_eta_min < 12 THEN '03 | 6-<12 min'
            ELSE '04 | 12+ min'
        END AS eta_group,
        t.status
    FROM trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
        AND t.accepted_at IS NOT NULL
)
SELECT
    eta_group,
    COUNT(*) AS accepted_requests,
    SUM(CASE WHEN status IN (5, 6) THEN 1 ELSE 0 END) AS post_match_cancellations,
    SUM(CASE WHEN status = 5 THEN 1 ELSE 0 END) AS customer_cancellations,
    SUM(CASE WHEN status = 6 THEN 1 ELSE 0 END) AS driver_cancellations,
    SUM(CASE WHEN status IN (1, 2, 3) THEN 1 ELSE 0 END) AS open_requests,
    ROUND(SUM(CASE WHEN status IN (5, 6) THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2) AS post_match_cancellation_rate,
    CASE WHEN COUNT(*) < 30 THEN 1 ELSE 0 END AS small_sample,
    CASE eta_group
        WHEN '01 | <3 min' THEN 1
        WHEN '02 | 3-<6 min' THEN 2
        WHEN '03 | 6-<12 min' THEN 3
        WHEN '04 | 12+ min' THEN 4
        ELSE 99
    END AS eta_group_order
FROM eta_booking
GROUP BY eta_group
ORDER BY eta_group_order;
GO
-- Identify zones and hours with the most failed requests
SELECT
    t.pickup_zone_id,
    z.zone_name AS pickup_zone,
    t.service_type,
    te.trip_hour,
    COUNT(t.trip_id) AS total_request,
    SUM(CASE WHEN t.status IN (5, 6, 7) THEN 1 ELSE 0 END) AS failed_requests,
    SUM(CASE WHEN t.status IN (1, 2, 3) THEN 1 ELSE 0 END) AS open_requests,
    ROUND(SUM(CASE WHEN t.status IN (5, 6, 7) THEN 1 ELSE 0 END) * 100.0
        / COUNT(t.trip_id), 2) AS failure_rate,
    CASE WHEN COUNT(t.trip_id) < 30 THEN 1 ELSE 0 END AS small_sample
FROM trip_table t
INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
LEFT JOIN zone_table z ON t.pickup_zone_id = z.zone_id
WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
GROUP BY t.pickup_zone_id, z.zone_name, t.service_type, te.trip_hour
ORDER BY small_sample, failed_requests DESC, failure_rate DESC;
GO
-- Prioritize areas with the greatest fulfillment problems
WITH area_summary AS (
    SELECT
        t.pickup_zone_id,
        z.zone_name AS pickup_zone,
        t.service_type,
        te.trip_hour,
        COUNT(*) OVER (PARTITION BY t.pickup_zone_id, t.service_type, te.trip_hour) AS total_request,
        SUM(CASE WHEN t.status IN (5, 6, 7) THEN 1 ELSE 0 END)
            OVER (PARTITION BY t.pickup_zone_id, t.service_type, te.trip_hour) AS failed_requests,
        COUNT(te.total_wait_sec) OVER (PARTITION BY t.pickup_zone_id, t.service_type, te.trip_hour)
            AS waiting_sample_size,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY te.total_wait_sec / 60.0)
            OVER (PARTITION BY t.pickup_zone_id, t.service_type, te.trip_hour) AS p90_total_wait_min
    FROM trip_table t
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    LEFT JOIN zone_table z ON t.pickup_zone_id = z.zone_id
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
),
area_performance AS (
    SELECT DISTINCT
        pickup_zone_id,
        pickup_zone,
        service_type,
        trip_hour,
        total_request,
        failed_requests,
        failed_requests * 100.0 / total_request AS failure_rate,
        waiting_sample_size,
        p90_total_wait_min
    FROM area_summary
),
overall_performance AS (
    SELECT
        SUM(CASE WHEN status IN (5, 6, 7) THEN 1 ELSE 0 END) AS all_failed_requests,
        SUM(CASE WHEN status IN (5, 6, 7) THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0) AS overall_failure_rate
    FROM trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.failed_requests DESC, a.failure_rate DESC,
        a.p90_total_wait_min DESC, a.total_request DESC,
        a.pickup_zone_id, a.service_type, a.trip_hour) AS priority_rank,
    a.pickup_zone_id,
    a.pickup_zone,
    a.service_type,
    a.trip_hour,
    a.total_request,
    a.failed_requests,
    ROUND(a.failure_rate, 2) AS failure_rate,
    ROUND(o.overall_failure_rate, 2) AS overall_failure_rate,
    ROUND(a.failed_requests * 100.0 / NULLIF(o.all_failed_requests, 0), 2) AS share_of_all_failures,
    a.waiting_sample_size,
    ROUND(a.p90_total_wait_min, 2) AS p90_total_wait_min,
    CASE WHEN a.waiting_sample_size < 30 THEN 1 ELSE 0 END AS waiting_small_sample
FROM area_performance a
CROSS JOIN overall_performance o
WHERE a.total_request >= 30
    AND a.failed_requests > 0
    AND a.failure_rate >= o.overall_failure_rate
ORDER BY priority_rank;
GO
-- [MODIFIED] End-of-period sensitivity; keep open requests and valid wait populations explicit.
WITH period_booking AS (
    SELECT
        'full_period' AS analysis_period,
        1 AS period_order,
        t.trip_id,
        t.status,
        t.accepted_at,
        t.pickup_at,
        t.finished_at,
        CASE WHEN te.allocation_sec >= 0 THEN te.allocation_sec / 60.0 END AS allocation_min,
        CASE WHEN t.pickup_at IS NOT NULL AND te.total_wait_sec >= 0 THEN te.total_wait_sec / 60.0 END AS total_wait_min
    FROM trip_table t
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'

    UNION ALL

    SELECT
        'exclude_last_24h' AS analysis_period,
        2 AS period_order,
        t.trip_id,
        t.status,
        t.accepted_at,
        t.pickup_at,
        t.finished_at,
        CASE WHEN te.allocation_sec >= 0 THEN te.allocation_sec / 60.0 END AS allocation_min,
        CASE WHEN t.pickup_at IS NOT NULL AND te.total_wait_sec >= 0 THEN te.total_wait_sec / 60.0 END AS total_wait_min
    FROM trip_table t
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    WHERE t.created_at >= '20260401' AND t.created_at < '20260930'
),
period_summary AS (
    SELECT
        analysis_period,
        period_order,
        COUNT(*) OVER (PARTITION BY analysis_period) AS total_request,
        COUNT(accepted_at) OVER (PARTITION BY analysis_period) AS accepted_requests,
        COUNT(pickup_at) OVER (PARTITION BY analysis_period) AS picked_up_requests,
        COUNT(finished_at) OVER (PARTITION BY analysis_period) AS completed_requests,
        SUM(CASE WHEN status IN (5, 6, 7) THEN 1 ELSE 0 END)
            OVER (PARTITION BY analysis_period) AS failed_requests,
        SUM(CASE WHEN status IN (1, 2, 3) THEN 1 ELSE 0 END)
            OVER (PARTITION BY analysis_period) AS open_requests,
        SUM(CASE WHEN status IN (5, 6) AND accepted_at IS NOT NULL THEN 1 ELSE 0 END)
            OVER (PARTITION BY analysis_period) AS post_match_cancellations,
        COUNT(allocation_min) OVER (PARTITION BY analysis_period) AS allocation_sample_size,
        COUNT(total_wait_min) OVER (PARTITION BY analysis_period) AS waiting_sample_size,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY allocation_min)
            OVER (PARTITION BY analysis_period) AS median_allocation_min,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY allocation_min)
            OVER (PARTITION BY analysis_period) AS p90_allocation_min,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_wait_min)
            OVER (PARTITION BY analysis_period) AS median_total_wait_min,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY total_wait_min)
            OVER (PARTITION BY analysis_period) AS p90_total_wait_min
    FROM period_booking
),
period_kpi AS (
    SELECT DISTINCT
        analysis_period,
        period_order,
        total_request,
        accepted_requests,
        picked_up_requests,
        completed_requests,
        failed_requests,
        open_requests,
        accepted_requests * 100.0 / total_request AS match_rate,
        completed_requests * 100.0 / total_request AS completion_rate,
        failed_requests * 100.0 / total_request AS failure_rate,
        open_requests * 100.0 / total_request AS open_rate,
        completed_requests * 100.0 / NULLIF(completed_requests + failed_requests, 0) AS closed_completion_rate,
        post_match_cancellations,
        post_match_cancellations * 100.0 / NULLIF(accepted_requests, 0) AS post_match_cancellation_rate,
        allocation_sample_size,
        waiting_sample_size,
        median_allocation_min,
        p90_allocation_min,
        median_total_wait_min,
        p90_total_wait_min
    FROM period_summary
)
SELECT
    analysis_period,
    total_request,
    accepted_requests,
    picked_up_requests,
    completed_requests,
    failed_requests,
    open_requests,
    ROUND(match_rate, 2) AS match_rate,
    ROUND(completion_rate, 2) AS completion_rate,
    ROUND(failure_rate, 2) AS failure_rate,
    ROUND(open_rate, 2) AS open_rate,
    ROUND(closed_completion_rate, 2) AS closed_completion_rate,
    post_match_cancellations,
    ROUND(post_match_cancellation_rate, 2) AS post_match_cancellation_rate,
    allocation_sample_size,
    waiting_sample_size,
    ROUND(median_allocation_min, 2) AS median_allocation_min,
    ROUND(p90_allocation_min, 2) AS p90_allocation_min,
    ROUND(median_total_wait_min, 2) AS median_total_wait_min,
    ROUND(p90_total_wait_min, 2) AS p90_total_wait_min,
    ROUND(match_rate - LAG(match_rate) OVER (ORDER BY period_order), 2) AS match_rate_change_pp,
    ROUND(completion_rate - LAG(completion_rate) OVER (ORDER BY period_order), 2) AS completion_rate_change_pp,
    ROUND(failure_rate - LAG(failure_rate) OVER (ORDER BY period_order), 2) AS failure_rate_change_pp,
    ROUND(p90_total_wait_min - LAG(p90_total_wait_min) OVER (ORDER BY period_order), 2) AS p90_wait_change_min
FROM period_kpi
ORDER BY period_order;
GO


-- [NEW] Reusable session-local request population. No source data is changed.
-- Overall total wait only needs observed pickup + nonnegative total duration.
-- Breakdown needs all stages, chronological timestamps, and exact additive identity.
DROP TABLE IF EXISTS #eta_request;
SELECT t.trip_id,t.status,t.service_type,t.pickup_zone_id,z.zone_name AS pickup_zone,
       CONVERT(char(7),t.created_at,126) AS request_month,
       CASE WHEN e.trip_hour BETWEEN 7 AND 8 THEN 'morning_peak'
            WHEN e.trip_hour BETWEEN 16 AND 18 THEN 'evening_peak' ELSE 'off_peak' END AS peak_period,
       t.accepted_at,t.pickup_at,t.quoted_pickup_eta_min AS eta_min,
       CASE WHEN t.pickup_at IS NOT NULL AND e.total_wait_sec >= 0
            THEN e.total_wait_sec/60.0 END AS total_wait_min,
       CASE WHEN t.pickup_at IS NOT NULL AND e.allocation_sec >= 0 AND e.approach_sec >= 0
                  AND e.pickup_dwell_sec >= 0 AND e.total_wait_sec >= 0
                  AND t.created_at<=t.accepted_at AND t.accepted_at<=t.arrived_at
                  AND t.arrived_at<=t.pickup_at
                  AND e.total_wait_sec=e.allocation_sec+e.approach_sec+e.pickup_dwell_sec
            THEN 1 ELSE 0 END AS complete_stage_flag,
       e.allocation_sec/60.0 AS allocation_min,e.approach_sec/60.0 AS approach_min,
       e.pickup_dwell_sec/60.0 AS pickup_dwell_min
INTO #eta_request
FROM dbo.trip_table t JOIN dbo.v_trip_enriched e ON t.trip_id=e.trip_id
LEFT JOIN dbo.zone_table z ON t.pickup_zone_id=z.zone_id
WHERE t.created_at>='20260401' AND t.created_at<'20261001';
CREATE UNIQUE CLUSTERED INDEX ix_eta_request ON #eta_request(trip_id);
GO
-- [NEW] Wait scopes include marginal groups and the full zone/service/peak cells.
-- result: waiting_summary
WITH scoped AS (
 SELECT s.scope_type,s.scope_name,r.*
 FROM #eta_request r CROSS APPLY (VALUES
 ('Overall','All'),('Service',r.service_type),('Pickup Zone',r.pickup_zone),
 ('Peak Period',r.peak_period),
 ('Zone Service Peak',CONCAT(r.pickup_zone,' | ',r.service_type,' | ',r.peak_period))) s(scope_type,scope_name)
), stats AS (
 SELECT scope_type,scope_name,
 COUNT(*) OVER(PARTITION BY scope_type,scope_name) AS requests,
 COUNT(total_wait_min) OVER(PARTITION BY scope_type,scope_name) AS waiting_sample_size,
 SUM(complete_stage_flag) OVER(PARTITION BY scope_type,scope_name) AS breakdown_sample_size,
 AVG(total_wait_min) OVER(PARTITION BY scope_type,scope_name) AS average_total_wait_min,
 PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY total_wait_min) OVER(PARTITION BY scope_type,scope_name) AS median_total_wait_min,
 PERCENTILE_CONT(0.9) WITHIN GROUP(ORDER BY total_wait_min) OVER(PARTITION BY scope_type,scope_name) AS p90_total_wait_min,
 AVG(CASE WHEN complete_stage_flag=1 THEN total_wait_min END) OVER(PARTITION BY scope_type,scope_name) AS breakdown_total_wait_min,
 AVG(CASE WHEN complete_stage_flag=1 THEN allocation_min END) OVER(PARTITION BY scope_type,scope_name) AS average_allocation_min,
 AVG(CASE WHEN complete_stage_flag=1 THEN approach_min END) OVER(PARTITION BY scope_type,scope_name) AS average_approach_min,
 AVG(CASE WHEN complete_stage_flag=1 THEN pickup_dwell_min END) OVER(PARTITION BY scope_type,scope_name) AS average_pickup_dwell_min
 FROM scoped
)
SELECT DISTINCT *,average_allocation_min+average_approach_min+average_pickup_dwell_min-breakdown_total_wait_min AS stage_identity_residual_min
FROM stats ORDER BY scope_type,scope_name;
GO
-- [NEW] Matched valid ETA population; each request appears once in each scope type.
DROP TABLE IF EXISTS #eta_scoped;
SELECT s.scope_type,s.scope_name,r.eta_min,r.status,
 CASE WHEN r.eta_min>=20 THEN 20 ELSE CAST(FLOOR(r.eta_min) AS int) END AS eta_bucket_order
INTO #eta_scoped
FROM #eta_request r CROSS APPLY (VALUES
 ('Overall','All'),('Service',r.service_type),('Pickup Zone',r.pickup_zone),
 ('Peak Period',r.peak_period),('Month',r.request_month),
 ('Zone Service Peak',CONCAT(r.pickup_zone,' | ',r.service_type,' | ',r.peak_period))) s(scope_type,scope_name)
WHERE r.accepted_at IS NOT NULL AND r.eta_min>=0;
CREATE CLUSTERED INDEX ix_eta_scope ON #eta_scoped(scope_type,scope_name,eta_min);
GO
-- [NEW] Continuous percentiles remain unrounded, including when used as cutoffs.
-- result: eta_distribution
SELECT DISTINCT scope_type,scope_name,
 COUNT(*) OVER(PARTITION BY scope_type,scope_name) AS eta_sample_size,
 MIN(eta_min) OVER(PARTITION BY scope_type,scope_name) AS minimum_eta_min,
 AVG(eta_min) OVER(PARTITION BY scope_type,scope_name) AS average_eta_min,
 PERCENTILE_CONT(0.25) WITHIN GROUP(ORDER BY eta_min) OVER(PARTITION BY scope_type,scope_name) AS p25_eta_min,
 PERCENTILE_CONT(0.50) WITHIN GROUP(ORDER BY eta_min) OVER(PARTITION BY scope_type,scope_name) AS p50_eta_min,
 PERCENTILE_CONT(0.75) WITHIN GROUP(ORDER BY eta_min) OVER(PARTITION BY scope_type,scope_name) AS p75_eta_min,
 PERCENTILE_CONT(0.90) WITHIN GROUP(ORDER BY eta_min) OVER(PARTITION BY scope_type,scope_name) AS p90_eta_min,
 MAX(eta_min) OVER(PARTITION BY scope_type,scope_name) AS maximum_eta_min
INTO #eta_distribution
FROM #eta_scoped;
SELECT * FROM #eta_distribution ORDER BY scope_type,scope_name;
GO
-- [NEW] All 21 minute buckets are retained, including empty buckets.
-- Adjacency requires the immediately preceding minute, never skipping empty buckets.
-- result: eta_cancellation_by_minute
WITH buckets AS (SELECT b.n AS eta_bucket_order FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20)) b(n)),
scopes AS (SELECT DISTINCT scope_type,scope_name FROM #eta_scoped),
counts AS (
 SELECT scope_type,scope_name,eta_bucket_order,COUNT(*) AS matched_requests,
 SUM(CASE WHEN status IN(5,6) THEN 1 ELSE 0 END) AS post_match_cancellations,
 SUM(CASE WHEN status=5 THEN 1 ELSE 0 END) AS customer_cancellations,
 SUM(CASE WHEN status=6 THEN 1 ELSE 0 END) AS driver_cancellations,
 SUM(CASE WHEN status IN(1,2,3) THEN 1 ELSE 0 END) AS open_requests
 FROM #eta_scoped GROUP BY scope_type,scope_name,eta_bucket_order
), rates AS (
 SELECT s.scope_type,s.scope_name,b.eta_bucket_order,
 CASE WHEN b.eta_bucket_order=20 THEN '20+ min' ELSE CONCAT(b.eta_bucket_order,'-<',b.eta_bucket_order+1,' min') END AS eta_bucket,
 COALESCE(c.matched_requests,0) AS matched_requests,COALESCE(c.post_match_cancellations,0) AS post_match_cancellations,
 COALESCE(c.customer_cancellations,0) AS customer_cancellations,COALESCE(c.driver_cancellations,0) AS driver_cancellations,
 COALESCE(c.open_requests,0) AS open_requests,
 c.post_match_cancellations*100.0/NULLIF(c.matched_requests,0) AS post_match_cancellation_rate_pct,
 c.customer_cancellations*100.0/NULLIF(c.matched_requests,0) AS customer_cancellation_rate_pct,
 c.driver_cancellations*100.0/NULLIF(c.matched_requests,0) AS driver_cancellation_rate_pct,
 CASE WHEN COALESCE(c.matched_requests,0)<30 THEN 1 ELSE 0 END AS small_sample_flag
 FROM scopes s CROSS JOIN buckets b LEFT JOIN counts c ON c.scope_type=s.scope_type AND c.scope_name=s.scope_name AND c.eta_bucket_order=b.eta_bucket_order
), adjacent AS (
 SELECT *,LAG(matched_requests) OVER(PARTITION BY scope_type,scope_name ORDER BY eta_bucket_order) AS previous_minute_requests,
 post_match_cancellation_rate_pct-LAG(post_match_cancellation_rate_pct) OVER(PARTITION BY scope_type,scope_name ORDER BY eta_bucket_order) AS adjacent_rate_change_pp
 FROM rates
)
SELECT *,CASE WHEN matched_requests>=30 AND previous_minute_requests>=30 AND adjacent_rate_change_pp>=1.0 THEN 1 ELSE 0 END AS exploratory_rise_flag
INTO #eta_behavior FROM adjacent;
SELECT * FROM #eta_behavior ORDER BY scope_type,scope_name,eta_bucket_order;
GO
-- [NEW] Compare exact distribution cutoffs, current SQL/dashboard cutoffs, and
-- exploratory rises >=1 percentage point between adjacent well-populated minutes.
-- This screening rule does not test statistical significance or prove causation.
-- Overall/service rise boundaries are evaluated in ALL scopes for stability.
-- result: proposed_eta_cutoff_comparison
WITH proposed AS (
 SELECT v.cutoff_name,'Distribution' AS cutoff_source,CAST(v.eta_cutoff_min AS float) AS eta_cutoff_min
 FROM #eta_distribution d CROSS APPLY(VALUES('P25',d.p25_eta_min),('P50',d.p50_eta_min),('P75',d.p75_eta_min),('P90',d.p90_eta_min)) v(cutoff_name,eta_cutoff_min)
 WHERE d.scope_type='Overall'
 UNION ALL SELECT v.cutoff_name,'Existing Power BI',CAST(v.eta_cutoff_min AS float) FROM (VALUES('3 min',3),('6 min',6),('12 min',12)) v(cutoff_name,eta_cutoff_min)
 UNION ALL SELECT v.cutoff_name,'Existing SQL',CAST(v.eta_cutoff_min AS float) FROM (VALUES('3 min',3),('5 min',5),('8 min',8),('12 min',12)) v(cutoff_name,eta_cutoff_min)
 UNION ALL SELECT DISTINCT CONCAT(eta_bucket_order,' min'),'Behavior: adjacent rise',CAST(eta_bucket_order AS float)
 FROM #eta_behavior WHERE exploratory_rise_flag=1 AND scope_type IN('Overall','Service')
), counts AS (
 SELECT b.scope_type,b.scope_name,c.cutoff_name,c.cutoff_source,c.eta_cutoff_min,
 SUM(CASE WHEN b.eta_min<c.eta_cutoff_min THEN 1 ELSE 0 END) AS requests_below,
 SUM(CASE WHEN b.eta_min>=c.eta_cutoff_min THEN 1 ELSE 0 END) AS requests_above,
 SUM(CASE WHEN b.eta_min<c.eta_cutoff_min AND b.status IN(5,6) THEN 1 ELSE 0 END) AS cancellations_below,
 SUM(CASE WHEN b.eta_min>=c.eta_cutoff_min AND b.status IN(5,6) THEN 1 ELSE 0 END) AS cancellations_above
 FROM #eta_scoped b CROSS JOIN proposed c GROUP BY b.scope_type,b.scope_name,c.cutoff_name,c.cutoff_source,c.eta_cutoff_min
), rates AS (
 SELECT *,cancellations_below*100.0/NULLIF(requests_below,0) AS cancellation_rate_below_pct,
 cancellations_above*100.0/NULLIF(requests_above,0) AS cancellation_rate_above_pct FROM counts
)
SELECT *,cancellation_rate_above_pct-cancellation_rate_below_pct AS cancellation_rate_difference_pp,
 CASE WHEN requests_below>=30 AND requests_above>=30 THEN 1 ELSE 0 END AS sufficient_sample_flag
FROM rates ORDER BY scope_type,scope_name,eta_cutoff_min,cutoff_source;
GO
-- [NEW] Compare entire sets rather than choosing the largest single rate gap.
-- Selected set provisionally retains existing dashboard 3/6/12; see verified findings.
-- Unknown is retained for matched requests with missing/negative ETA.
-- result: eta_group_set_evaluation
WITH grouped AS (
 SELECT s.scope_type,s.scope_name,v.group_set,v.eta_band_order,v.eta_band,r.status
 FROM #eta_request r CROSS APPLY(VALUES('Overall','All'),('Service',r.service_type),('Pickup Zone',r.pickup_zone),('Peak Period',r.peak_period),('Month',r.request_month),('Zone Service Peak',CONCAT(r.pickup_zone,' | ',r.service_type,' | ',r.peak_period))) s(scope_type,scope_name)
 CROSS APPLY(VALUES
 ('Selected Power BI 3/6/12',CASE WHEN r.eta_min IS NULL OR r.eta_min<0 THEN 99 WHEN r.eta_min<3 THEN 1 WHEN r.eta_min<6 THEN 2 WHEN r.eta_min<12 THEN 3 ELSE 4 END,
 CASE WHEN r.eta_min IS NULL OR r.eta_min<0 THEN 'Unknown' WHEN r.eta_min<3 THEN '01 | <3 min' WHEN r.eta_min<6 THEN '02 | 3-<6 min' WHEN r.eta_min<12 THEN '03 | 6-<12 min' ELSE '04 | 12+ min' END),
 ('Previous SQL 3/5/8/12',CASE WHEN r.eta_min IS NULL OR r.eta_min<0 THEN 99 WHEN r.eta_min<3 THEN 1 WHEN r.eta_min<5 THEN 2 WHEN r.eta_min<8 THEN 3 WHEN r.eta_min<12 THEN 4 ELSE 5 END,
 CASE WHEN r.eta_min IS NULL OR r.eta_min<0 THEN 'Unknown' WHEN r.eta_min<3 THEN '01 | <3 min' WHEN r.eta_min<5 THEN '02 | 3-<5 min' WHEN r.eta_min<8 THEN '03 | 5-<8 min' WHEN r.eta_min<12 THEN '04 | 8-<12 min' ELSE '05 | 12+ min' END)) v(group_set,eta_band_order,eta_band)
 WHERE r.accepted_at IS NOT NULL
)
SELECT scope_type,scope_name,group_set,eta_band_order,eta_band,COUNT(*) AS matched_requests,
 SUM(CASE WHEN status IN(5,6) THEN 1 ELSE 0 END) AS post_match_cancellations,
 SUM(CASE WHEN status=5 THEN 1 ELSE 0 END) AS customer_cancellations,
 SUM(CASE WHEN status=6 THEN 1 ELSE 0 END) AS driver_cancellations,
 SUM(CASE WHEN status IN(1,2,3) THEN 1 ELSE 0 END) AS open_requests,
 SUM(CASE WHEN status IN(5,6) THEN 1 ELSE 0 END)*100.0/COUNT(*) AS post_match_cancellation_rate_pct,
 SUM(CASE WHEN status=5 THEN 1 ELSE 0 END)*100.0/COUNT(*) AS customer_cancellation_rate_pct,
 SUM(CASE WHEN status=6 THEN 1 ELSE 0 END)*100.0/COUNT(*) AS driver_cancellation_rate_pct,
 CASE WHEN COUNT(*)<30 THEN 1 ELSE 0 END AS small_sample_flag
FROM grouped GROUP BY scope_type,scope_name,group_set,eta_band_order,eta_band
ORDER BY scope_type,scope_name,group_set,eta_band_order;
GO
-- [NEW] Quality checks distinguish missing stages from overall valid pickups.
-- result: eta_waiting_quality
SELECT COUNT(*) AS requests,COUNT(DISTINCT r.trip_id) AS distinct_requests,
 SUM(CASE WHEN r.accepted_at IS NOT NULL THEN 1 ELSE 0 END) AS matched_requests,
 SUM(CASE WHEN r.pickup_at IS NOT NULL THEN 1 ELSE 0 END) AS pickup_requests,
 COUNT(r.total_wait_min) AS waiting_sample_size,SUM(r.complete_stage_flag) AS breakdown_sample_size,
 SUM(CASE WHEN r.status IN(1,2,3) THEN 1 ELSE 0 END) AS open_requests,
 SUM(CASE WHEN r.accepted_at IS NOT NULL AND r.eta_min IS NULL THEN 1 ELSE 0 END) AS matched_missing_eta,
 SUM(CASE WHEN r.eta_min<0 THEN 1 ELSE 0 END) AS negative_eta,
 SUM(CASE WHEN e.allocation_sec<0 OR e.approach_sec<0 OR e.pickup_dwell_sec<0 OR e.total_wait_sec<0 THEN 1 ELSE 0 END) AS negative_duration_requests,
 SUM(CASE WHEN r.total_wait_min IS NOT NULL AND r.complete_stage_flag=0 THEN 1 ELSE 0 END) AS valid_wait_missing_or_invalid_stages,
 SUM(CASE WHEN e.total_wait_sec<>e.allocation_sec+e.approach_sec+e.pickup_dwell_sec THEN 1 ELSE 0 END) AS stage_identity_violations,
 SUM(CASE WHEN t.accepted_at>='20261001' OR t.arrived_at>='20261001' OR t.pickup_at>='20261001' OR t.finished_at>='20261001' THEN 1 ELSE 0 END) AS events_at_or_after_cutoff
FROM #eta_request r JOIN dbo.v_trip_enriched e ON e.trip_id=r.trip_id JOIN dbo.trip_table t ON t.trip_id=r.trip_id;
GO
