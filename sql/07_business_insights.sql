-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
SET NOCOUNT ON;
-- Validation: grain, status reconciliation, timestamps and NULL observations.
SELECT COUNT_BIG(*) AS requests, COUNT(DISTINCT trip_id) AS distinct_requests,
    COUNT(DISTINCT request_group_id) AS independent_journeys,
    COUNT(DISTINCT user_id) AS active_users, MIN(created_at) AS first_request_at,
    MAX(created_at) AS last_request_at,
    SUM(CASE WHEN status=4 THEN 1 ELSE 0 END) AS completed_requests,
    SUM(CASE WHEN status IN (5,6,7) THEN 1 ELSE 0 END) AS failed_requests,
    SUM(CASE WHEN status IN (1,2,3) THEN 1 ELSE 0 END) AS open_requests,
    COUNT(accepted_at) AS matched_requests, COUNT(pickup_at) AS picked_up_requests,
    SUM(CASE WHEN (status=4 AND finished_at IS NULL) OR (status<>4 AND finished_at IS NOT NULL)
        THEN 1 ELSE 0 END) AS completion_status_timestamp_mismatches,
    SUM(CASE WHEN accepted_at<created_at OR arrived_at<accepted_at OR pickup_at<arrived_at
        OR finished_at<pickup_at OR cancelled_at<created_at OR expired_at<created_at
        THEN 1 ELSE 0 END) AS invalid_timestamp_orders,
    SUM(CASE WHEN status IN (5,6) AND cancelled_at IS NULL OR status=7 AND expired_at IS NULL
        THEN 1 ELSE 0 END) AS missing_failure_end_at,
    SUM(CASE WHEN status NOT IN (1,2,3,4,5,6,7) THEN 1 ELSE 0 END) AS unknown_statuses,
    SUM(CASE WHEN pickup_at IS NULL THEN 1 ELSE 0 END) AS unknown_total_wait_requests
FROM dbo.trip_table WHERE created_at>='20260401' AND created_at<'20261001';
SELECT COUNT_BIG(*) AS offers, COUNT(DISTINCT offer_id) AS distinct_offers,
    SUM(CASE WHEN outcome='ACCEPTED' THEN 1 ELSE 0 END) AS accepted_offers,
    SUM(CASE WHEN outcome IN ('ACCEPTED','REJECTED','TIMEOUT') THEN 1 ELSE 0 END) AS decision_offers,
    SUM(CASE WHEN outcome='WITHDRAWN' THEN 1 ELSE 0 END) AS withdrawn_offers,
    SUM(CASE WHEN outcome='PENDING' THEN 1 ELSE 0 END) AS pending_offers
FROM dbo.dispatch_offer_table;
SELECT (SELECT COUNT_BIG(*) FROM dbo.v_trip_enriched) AS enriched_rows,
    (SELECT COUNT_BIG(*) FROM dbo.trip_table) AS raw_requests,
    (SELECT COUNT_BIG(*) FROM dbo.v_offer_per_trip) AS offer_summary_rows,
    (SELECT SUM(offers) FROM dbo.v_offer_per_trip) AS summarized_offers,
    (SELECT COUNT(*) FROM dbo.v_offer_per_trip WHERE accepted>1) AS multiple_accepted_offers,
    (SELECT COUNT(*) FROM dbo.trip_table t INNER JOIN dbo.v_offer_per_trip o ON t.trip_id=o.trip_id
        WHERE (t.accepted_at IS NOT NULL AND o.accepted<>1) OR (t.accepted_at IS NULL AND o.accepted<>0)) AS match_offer_mismatches,
    (SELECT COUNT_BIG(*) FROM dbo.v_zone_service_15min) AS supply_view_rows,
    (SELECT SUM(total_request) FROM dbo.v_zone_service_15min) AS supply_view_requests,
    (SELECT SUM(total_request) FROM dbo.v_customer_summary) AS customer_view_requests,
    (SELECT SUM(total_completed) FROM dbo.v_customer_summary) AS customer_view_completed,
    (SELECT COUNT(*) FROM dbo.trip_table WHERE created_at<'20260401' OR created_at>='20261001') AS outside_cohort_requests;
SELECT SUM(online_driver_minutes) AS online_minutes,
    SUM(occupied_driver_minutes) AS occupied_minutes, SUM(on_trip_driver_minutes) AS on_trip_minutes,
    SUM(occupied_driver_minutes)*100.0/NULLIF(SUM(online_driver_minutes),0) AS occupied_utilization_pct,
    SUM(on_trip_driver_minutes)*100.0/NULLIF(SUM(online_driver_minutes),0) AS on_trip_utilization_pct,
    SUM(online_driver_minutes-available_driver_minutes-offer_pending_driver_minutes-occupied_driver_minutes) AS state_balance_minutes,
    (SELECT SUM(DATEDIFF_BIG(SECOND,started_at,ended_at))/60.0 FROM dbo.driver_state_interval_table) AS interval_online_minutes,
    (SELECT SUM(DATEDIFF_BIG(SECOND,online_at,observation_end_at))/60.0 FROM dbo.driver_session_table) AS session_online_minutes
FROM dbo.supply_15min_table WHERE interval_start_at>='20260401' AND interval_start_at<'20261001';
GO
-- Rank distinct observed outcomes by affected request volume
WITH classified AS (
    SELECT t.trip_id,t.user_id,t.pickup_zone_id,t.service_type,te.trip_hour,t.status,t.accepted_at,
        CASE WHEN t.status=4 AND te.total_wait_sec>720 THEN 'completed_long_wait'
            WHEN t.status=7 THEN 'expired_no_driver'
            WHEN t.status IN (5,6) AND t.accepted_at IS NOT NULL THEN 'post_match_cancellation'
            WHEN t.status IN (5,6) THEN 'pre_match_cancellation' END AS problem
    FROM dbo.trip_table t INNER JOIN dbo.v_trip_enriched te ON t.trip_id=te.trip_id
    WHERE t.created_at>='20260401' AND t.created_at<'20261001'
), totals AS (
    SELECT COUNT(*) AS requests, SUM(CASE WHEN status=4 THEN 1 ELSE 0 END) AS completed_requests,
        COUNT(accepted_at) AS matched_requests FROM classified
), problems AS (
    SELECT problem,COUNT(*) AS affected_requests,COUNT(DISTINCT user_id) AS affected_users
    FROM classified WHERE problem IS NOT NULL GROUP BY problem
), cells AS (
    SELECT problem,pickup_zone_id,service_type,trip_hour,COUNT(*) AS affected_requests,
        ROW_NUMBER() OVER (PARTITION BY problem ORDER BY COUNT(*) DESC,pickup_zone_id,service_type,trip_hour) AS cell_rank
    FROM classified WHERE problem IS NOT NULL
    GROUP BY problem,pickup_zone_id,service_type,trip_hour
)
SELECT TOP (3) ROW_NUMBER() OVER (ORDER BY p.affected_requests DESC,p.problem) AS priority_rank,
    p.problem,p.affected_requests,p.affected_users,p.affected_requests AS kpi_numerator,
    CASE WHEN p.problem='completed_long_wait' THEN t.completed_requests
        WHEN p.problem='post_match_cancellation' THEN t.matched_requests ELSE t.requests END AS kpi_denominator,
    CASE WHEN p.problem='completed_long_wait' THEN 'completed requests with observed wait'
        WHEN p.problem='post_match_cancellation' THEN 'matched requests' ELSE 'all requests' END AS denominator_population,
    CAST(p.affected_requests*100.0/NULLIF(CASE WHEN p.problem='completed_long_wait' THEN t.completed_requests
        WHEN p.problem='post_match_cancellation' THEN t.matched_requests ELSE t.requests END,0) AS DECIMAL(12,4)) AS kpi_rate_pct,
    t.requests AS all_requests,CAST(p.affected_requests*100.0/NULLIF(t.requests,0) AS DECIMAL(12,4)) AS share_of_all_requests_pct,
    c.pickup_zone_id AS target_zone_id,z.zone_name AS target_zone,c.service_type AS target_service,
    c.trip_hour AS target_hour,c.affected_requests AS target_affected_requests,
    (SELECT COUNT(*) FROM classified d WHERE d.pickup_zone_id=c.pickup_zone_id AND d.service_type=c.service_type
        AND d.trip_hour=c.trip_hour) AS target_all_requests,
    '2026-04-01 00:00:00' AS period_start,'2026-10-01 00:00:00' AS period_end_exclusive,
    'created_at; local UTC+7; synthetic' AS cohort_basis
FROM problems p CROSS JOIN totals t INNER JOIN cells c ON p.problem=c.problem AND c.cell_rank=1
LEFT JOIN dbo.zone_table z ON c.pickup_zone_id=z.zone_id
ORDER BY p.affected_requests DESC,p.problem;
GO
-- Relative reduction of failures (5/6/7); decimal expectations, not forecasts or completions.
SELECT b.baseline_failed_requests,s.reduction_rate AS assumed_reduction_rate,
    CAST(b.baseline_failed_requests*s.reduction_rate AS DECIMAL(18,2)) AS estimated_avoided_failed_requests,
    CAST(b.baseline_failed_requests*(1-s.reduction_rate) AS DECIMAL(18,2)) AS remaining_failed_requests,
    '2026-04-01' AS period_start,'2026-10-01' AS period_end_exclusive,
    'Relative failure reduction; fixed request cohort; fractional scenario expectation; avoided failures are not additional completions' AS assumptions
FROM (SELECT COUNT(*) AS baseline_failed_requests FROM dbo.trip_table
    WHERE created_at>='20260401' AND created_at<'20261001' AND status IN (5,6,7)) b
CROSS JOIN (VALUES (CAST(0.05 AS DECIMAL(5,2))),(CAST(0.10 AS DECIMAL(5,2))),(CAST(0.15 AS DECIMAL(5,2)))) s(reduction_rate)
ORDER BY s.reduction_rate;
GO
-- Calendar exposure and sensitivity: calendar-day normalization; all weekday/hour cells.
SELECT d.month_start,COUNT(DISTINCT d.[date]) AS observed_days,COUNT(t.trip_id) AS requests,
    COUNT(t.trip_id)*1.0/NULLIF(COUNT(DISTINCT d.[date]),0) AS requests_per_day
FROM dbo.date_table d LEFT JOIN dbo.trip_table t ON CAST(t.created_at AS DATE)=d.[date]
WHERE d.[date]>='20260401' AND d.[date]<'20261001' GROUP BY d.month_start ORDER BY d.month_start;
SELECT d.day_of_week_no,h.trip_hour,COUNT(DISTINCT d.[date]) AS observed_days,COUNT(t.trip_id) AS requests,
    COUNT(t.trip_id)*1.0/NULLIF(COUNT(DISTINCT d.[date]),0) AS requests_per_calendar_day
FROM dbo.date_table d CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),
    (12),(13),(14),(15),(16),(17),(18),(19),(20),(21),(22),(23)) h(trip_hour)
LEFT JOIN dbo.trip_table t ON CAST(t.created_at AS DATE)=d.[date] AND DATEPART(HOUR,t.created_at)=h.trip_hour
WHERE d.[date]>='20260401' AND d.[date]<'20261001'
GROUP BY d.day_of_week_no,h.trip_hour ORDER BY d.day_of_week_no,h.trip_hour;
-- Compare cell priorities at n>=20/30/50 and after grouping adjacent hours.
WITH cells AS (
    SELECT g.hours_per_bucket,t.pickup_zone_id,t.service_type,
        DATEPART(HOUR,t.created_at)/g.hours_per_bucket*g.hours_per_bucket AS hour_bucket,
        COUNT(*) AS requests,SUM(CASE WHEN t.status IN (5,6,7) THEN 1 ELSE 0 END) AS failures
    FROM dbo.trip_table t CROSS JOIN (VALUES (1),(2)) g(hours_per_bucket)
    WHERE t.created_at>='20260401' AND t.created_at<'20261001'
    GROUP BY g.hours_per_bucket,t.pickup_zone_id,t.service_type,DATEPART(HOUR,t.created_at)/g.hours_per_bucket*g.hours_per_bucket
), ranked AS (
    SELECT n.minimum_requests,c.*,ROW_NUMBER() OVER (PARTITION BY n.minimum_requests,c.hours_per_bucket
        ORDER BY c.failures DESC,c.failures*1.0/NULLIF(c.requests,0) DESC,c.pickup_zone_id,c.service_type,c.hour_bucket) AS priority_rank
    FROM cells c CROSS JOIN (VALUES (20),(30),(50)) n(minimum_requests) WHERE c.requests>=n.minimum_requests
)
SELECT * FROM ranked WHERE priority_rank<=3 ORDER BY hours_per_bucket,minimum_requests,priority_rank;
-- Sensitivity: long-wait convention, not an external service-level benchmark.
SELECT v.wait_minutes,COUNT(*) AS completed_requests,
    SUM(CASE WHEN te.total_wait_sec>v.wait_minutes*60 THEN 1 ELSE 0 END) AS long_wait_completed_requests
FROM dbo.trip_table t INNER JOIN dbo.v_trip_enriched te ON t.trip_id=te.trip_id
CROSS JOIN (VALUES (8),(12),(15)) v(wait_minutes)
WHERE t.status=4 AND t.created_at>='20260401' AND t.created_at<'20261001'
GROUP BY v.wait_minutes ORDER BY v.wait_minutes;
GO
-- Independent raw-table cross-checks
SELECT SUM(CASE WHEN status=4 AND DATEDIFF_BIG(SECOND,created_at,pickup_at)>720 THEN 1 ELSE 0 END) AS raw_long_wait_completed,
    SUM(CASE WHEN status=4 AND (pickup_at IS NULL OR pickup_at<created_at) THEN 1 ELSE 0 END) AS invalid_completed_wait,
    SUM(CASE WHEN status=7 THEN 1 ELSE 0 END) AS raw_expired,
    SUM(CASE WHEN status IN (5,6) AND accepted_at IS NOT NULL THEN 1 ELSE 0 END) AS raw_post_match_cancellations,
    SUM(CASE WHEN status IN (5,6) AND accepted_at IS NULL THEN 1 ELSE 0 END) AS raw_pre_match_cancellations
FROM dbo.trip_table WHERE created_at>='20260401' AND created_at<'20261001';
SELECT COUNT(DISTINCT u.user_id) AS registered_users,COUNT(t.trip_id) AS corrected_customer_requests,
    SUM(CASE WHEN t.status=4 THEN 1 ELSE 0 END) AS corrected_customer_completed,
    (SELECT COUNT(*) FROM dbo.trip_table t WHERE NOT EXISTS (SELECT 1 FROM dbo.user_table u WHERE u.user_id=t.user_id)) AS orphan_request_users,
    (SELECT COUNT(*) FROM dbo.dispatch_offer_table o WHERE NOT EXISTS (SELECT 1 FROM dbo.trip_table t WHERE t.trip_id=o.trip_id)) AS orphan_offer_requests
FROM dbo.user_table u LEFT JOIN dbo.trip_table t ON u.user_id=t.user_id AND t.created_at>='20260401' AND t.created_at<'20261001';
SELECT COUNT(*) AS duplicate_supply_keys FROM (
    SELECT interval_start_at,zone_id,service_type FROM dbo.supply_15min_table
    GROUP BY interval_start_at,zone_id,service_type HAVING COUNT(*)>1
) d;
