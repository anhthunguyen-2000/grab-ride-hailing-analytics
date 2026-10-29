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
-- Compare driver allocation and customer waiting times
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
        te.allocation_sec / 60.0 AS allocation_min,
        te.total_wait_sec / 60.0 AS total_wait_min
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
-- Analyze cancellation rates by quoted pickup ETA
WITH eta_booking AS (
    SELECT
        CASE
            WHEN t.quoted_pickup_eta_min IS NULL OR t.quoted_pickup_eta_min < 0 THEN 'unknown'
            WHEN t.quoted_pickup_eta_min < 3 THEN '0-<3 min'
            WHEN t.quoted_pickup_eta_min < 5 THEN '3-<5 min'
            WHEN t.quoted_pickup_eta_min < 8 THEN '5-<8 min'
            WHEN t.quoted_pickup_eta_min < 12 THEN '8-<12 min'
            ELSE '>=12 min'
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
        WHEN '0-<3 min' THEN 1
        WHEN '3-<5 min' THEN 2
        WHEN '5-<8 min' THEN 3
        WHEN '8-<12 min' THEN 4
        WHEN '>=12 min' THEN 5
        ELSE 6
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
-- Test whether end-of-period requests affect KPI results
WITH period_booking AS (
    SELECT
        'full_period' AS analysis_period,
        1 AS period_order,
        t.trip_id,
        t.status,
        t.accepted_at,
        t.pickup_at,
        t.finished_at,
        te.allocation_sec / 60.0 AS allocation_min,
        te.total_wait_sec / 60.0 AS total_wait_min
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
        te.allocation_sec / 60.0 AS allocation_min,
        te.total_wait_sec / 60.0 AS total_wait_min
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
