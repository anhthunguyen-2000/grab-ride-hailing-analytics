-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
-- DRIVER SUPPLY & DISPATCH ANALYSIS
-- Count daily online, offered, and completed-trip drivers
WITH session_bounds AS (
    SELECT s.driver_id, s.service_type,
        CASE WHEN s.online_at < '20260401' THEN CAST('20260401' AS DATETIME2(0))
            ELSE s.online_at END AS segment_start,
        CASE WHEN e.observed_end > '20261001' THEN CAST('20261001' AS DATETIME2(0))
            ELSE e.observed_end END AS segment_end
    FROM dbo.driver_session_table s
    CROSS APPLY (VALUES (
        CASE WHEN s.offline_at IS NULL OR s.offline_at > s.observation_end_at
            THEN s.observation_end_at ELSE s.offline_at END
    )) e(observed_end)
    WHERE s.online_at < '20261001' AND e.observed_end > '20260401'
),
online_driver_day AS (
    SELECT DISTINCT d.[date] AS activity_date, s.driver_id
    FROM session_bounds s
    INNER JOIN dbo.date_table d
        ON CAST(d.[date] AS DATETIME2(0)) < s.segment_end
        AND DATEADD(DAY, 1, CAST(d.[date] AS DATETIME2(0))) > s.segment_start
    WHERE d.[date] >= '20260401' AND d.[date] < '20261001'
        AND s.segment_end > s.segment_start
),
offer_driver_day AS (
    SELECT DISTINCT CAST(sent_at AS DATE) AS activity_date, driver_id
    FROM dbo.dispatch_offer_table
    WHERE sent_at >= '20260401' AND sent_at < '20261001'
),
completed_driver_day AS (
    SELECT DISTINCT CAST(finished_at AS DATE) AS activity_date, driver_id
    FROM dbo.trip_table
    WHERE status = 4 AND finished_at >= '20260401' AND finished_at < '20261001'
)
SELECT d.[date] AS activity_date,
    COUNT(o.driver_id) AS online_drivers,
    COUNT(f.driver_id) AS drivers_receiving_offers,
    COUNT(c.driver_id) AS drivers_completing_trips
FROM dbo.date_table d
LEFT JOIN online_driver_day o ON d.[date] = o.activity_date
LEFT JOIN offer_driver_day f ON o.activity_date = f.activity_date AND o.driver_id = f.driver_id
LEFT JOIN completed_driver_day c ON o.activity_date = c.activity_date AND o.driver_id = c.driver_id
WHERE d.[date] >= '20260401' AND d.[date] < '20261001'
GROUP BY d.[date]
ORDER BY d.[date];
GO
-- Measure driver online hours and completed trips per hour
WITH session_bounds AS (
    SELECT s.driver_id, s.service_type,
        CASE WHEN s.online_at < '20260401' THEN CAST('20260401' AS DATETIME2(0))
            ELSE s.online_at END AS segment_start,
        CASE WHEN e.observed_end > '20261001' THEN CAST('20261001' AS DATETIME2(0))
            ELSE e.observed_end END AS segment_end
    FROM dbo.driver_session_table s
    CROSS APPLY (VALUES (
        CASE WHEN s.offline_at IS NULL OR s.offline_at > s.observation_end_at
            THEN s.observation_end_at ELSE s.offline_at END
    )) e(observed_end)
    WHERE s.online_at < '20261001' AND e.observed_end > '20260401'
),
online_time AS (
    SELECT driver_id, service_type,
        SUM(DATEDIFF_BIG(SECOND, segment_start, segment_end)) AS online_sec
    FROM session_bounds
    WHERE segment_end > segment_start
    GROUP BY driver_id, service_type
),
completed AS (
    SELECT driver_id, service_type, COUNT(*) AS completed_trips
    FROM dbo.trip_table
    WHERE status = 4 AND finished_at >= '20260401' AND finished_at < '20261001'
    GROUP BY driver_id, service_type
)
SELECT o.driver_id, o.service_type,
    ROUND(o.online_sec / 3600.0, 2) AS online_hours,
    COALESCE(c.completed_trips, 0) AS completed_trips,
    ROUND(COALESCE(c.completed_trips, 0) * 3600.0 / NULLIF(o.online_sec, 0), 2)
        AS trips_per_online_hour
FROM online_time o
LEFT JOIN completed c ON o.driver_id = c.driver_id AND o.service_type = c.service_type
LEFT JOIN dbo.driver_table d ON o.driver_id = d.driver_id
ORDER BY completed_trips DESC, o.driver_id, o.service_type;
GO
-- Minutes in each online activity state. Break down online time by driver activity status
WITH state_bounds AS (
    SELECT i.driver_id, i.service_type, i.state,
        CASE WHEN i.started_at < '20260401' THEN CAST('20260401' AS DATETIME2(0))
            ELSE i.started_at END AS segment_start,
        CASE WHEN i.ended_at > '20261001' THEN CAST('20261001' AS DATETIME2(0))
            ELSE i.ended_at END AS segment_end
    FROM dbo.driver_state_interval_table i
    WHERE i.started_at < '20261001' AND i.ended_at > '20260401'
),
driver_time AS (
    SELECT driver_id, service_type,
        SUM(DATEDIFF_BIG(SECOND, segment_start, segment_end)) AS online_sec,
        SUM(CASE WHEN state = 'AVAILABLE'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS available_sec,
        SUM(CASE WHEN state = 'OFFER_PENDING'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS offer_pending_sec,
        SUM(CASE WHEN state = 'TO_PICKUP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS to_pickup_sec,
        SUM(CASE WHEN state = 'WAITING_PICKUP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS waiting_pickup_sec,
        SUM(CASE WHEN state = 'ON_TRIP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS on_trip_sec
    FROM state_bounds
    WHERE segment_end > segment_start
    GROUP BY driver_id, service_type
)
SELECT driver_id, service_type,
    ROUND(online_sec / 60.0, 2) AS online_minutes,
    ROUND(available_sec / 60.0, 2) AS available_minutes,
    ROUND(offer_pending_sec / 60.0, 2) AS offer_pending_minutes,
    ROUND(to_pickup_sec / 60.0, 2) AS to_pickup_minutes,
    ROUND(waiting_pickup_sec / 60.0, 2) AS waiting_pickup_minutes,
    ROUND(on_trip_sec / 60.0, 2) AS on_trip_minutes
FROM driver_time
ORDER BY driver_id, service_type;
GO
-- Calculate occupied and on-trip utilization rates
WITH state_bounds AS (
    SELECT i.driver_id, i.service_type, i.state,
        CASE WHEN i.started_at < '20260401' THEN CAST('20260401' AS DATETIME2(0))
            ELSE i.started_at END AS segment_start,
        CASE WHEN i.ended_at > '20261001' THEN CAST('20261001' AS DATETIME2(0))
            ELSE i.ended_at END AS segment_end
    FROM dbo.driver_state_interval_table i
    WHERE i.started_at < '20261001' AND i.ended_at > '20260401'
),
driver_time AS (
    SELECT driver_id, service_type,
        SUM(DATEDIFF_BIG(SECOND, segment_start, segment_end)) AS online_sec,
        SUM(CASE WHEN state = 'AVAILABLE'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS available_sec,
        SUM(CASE WHEN state = 'OFFER_PENDING'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS offer_pending_sec,
        SUM(CASE WHEN state = 'TO_PICKUP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS to_pickup_sec,
        SUM(CASE WHEN state = 'WAITING_PICKUP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS waiting_pickup_sec,
        SUM(CASE WHEN state = 'ON_TRIP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS on_trip_sec
    FROM state_bounds
    WHERE segment_end > segment_start
    GROUP BY driver_id, service_type
)
SELECT driver_id, service_type,
    ROUND(online_sec / 60.0, 2) AS online_minutes,
    ROUND((to_pickup_sec + waiting_pickup_sec + on_trip_sec) / 60.0, 2) AS occupied_minutes,
    ROUND(on_trip_sec / 60.0, 2) AS on_trip_minutes,
    ROUND((to_pickup_sec + waiting_pickup_sec + on_trip_sec) * 100.0
        / NULLIF(online_sec, 0), 2) AS occupied_utilization_pct,
    ROUND(on_trip_sec * 100.0 / NULLIF(online_sec, 0), 2) AS on_trip_utilization_pct
FROM driver_time
ORDER BY driver_id, service_type;
GO
-- Analyze driver offer acceptance/rejection/timeout rates by driver and hour of day.
WITH offer_summary AS (
    SELECT driver_id, service_type, DATEPART(HOUR, sent_at) AS offer_hour,
        COUNT(*) AS total_offers,
        SUM(CASE WHEN outcome = 'ACCEPTED' THEN 1 ELSE 0 END) AS accepted_offers,
        SUM(CASE WHEN outcome = 'REJECTED' THEN 1 ELSE 0 END) AS rejected_offers,
        SUM(CASE WHEN outcome = 'TIMEOUT' THEN 1 ELSE 0 END) AS timeout_offers,
        SUM(CASE WHEN outcome = 'WITHDRAWN' THEN 1 ELSE 0 END) AS withdrawn_offers,
        SUM(CASE WHEN outcome = 'PENDING' THEN 1 ELSE 0 END) AS pending_offers
    FROM dbo.dispatch_offer_table
    WHERE sent_at >= '20260401' AND sent_at < '20261001'
    GROUP BY driver_id, service_type, DATEPART(HOUR, sent_at)
)
SELECT driver_id, service_type, offer_hour, total_offers,
    accepted_offers, rejected_offers, timeout_offers, withdrawn_offers, pending_offers,
    accepted_offers + rejected_offers + timeout_offers AS decision_offers,
    ROUND(accepted_offers * 100.0
        / NULLIF(accepted_offers + rejected_offers + timeout_offers, 0), 2) AS acceptance_rate_pct,
    ROUND(rejected_offers * 100.0
        / NULLIF(accepted_offers + rejected_offers + timeout_offers, 0), 2) AS rejection_rate_pct,
    ROUND(timeout_offers * 100.0
        / NULLIF(accepted_offers + rejected_offers + timeout_offers, 0), 2) AS timeout_rate_pct,
    CASE WHEN accepted_offers + rejected_offers + timeout_offers < 30 THEN 1 ELSE 0 END AS small_sample
FROM offer_summary
ORDER BY driver_id, service_type, offer_hour;
GO
-- Measure offer response times and timeout rates. P50/P90 response time and timeout rate.
WITH offer_time AS (
    SELECT service_type, DATEPART(HOUR, sent_at) AS offer_hour, outcome,
        CASE WHEN outcome IN ('ACCEPTED', 'REJECTED') AND response_at >= sent_at
            THEN DATEDIFF(SECOND, sent_at, response_at) * 1.0 END AS response_sec,
        CASE WHEN outcome = 'ACCEPTED' AND response_at >= sent_at
            THEN DATEDIFF(SECOND, sent_at, response_at) * 1.0 END AS accepted_response_sec,
        CASE WHEN outcome = 'REJECTED' AND response_at >= sent_at
            THEN DATEDIFF(SECOND, sent_at, response_at) * 1.0 END AS rejected_response_sec,
        CASE WHEN outcome = 'TIMEOUT' AND resolved_at >= sent_at
            THEN DATEDIFF(SECOND, sent_at, resolved_at) * 1.0 END AS timeout_duration_sec
    FROM dbo.dispatch_offer_table
    WHERE sent_at >= '20260401' AND sent_at < '20261001'
),
response_summary AS (
    SELECT service_type, offer_hour,
        COUNT(*) OVER (PARTITION BY service_type, offer_hour) AS total_offers,
        SUM(CASE WHEN outcome IN ('ACCEPTED', 'REJECTED', 'TIMEOUT') THEN 1 ELSE 0 END)
            OVER (PARTITION BY service_type, offer_hour) AS decision_offers,
        SUM(CASE WHEN outcome = 'TIMEOUT' THEN 1 ELSE 0 END)
            OVER (PARTITION BY service_type, offer_hour) AS timeout_offers,
        COUNT(response_sec) OVER (PARTITION BY service_type, offer_hour) AS response_sample_size,
        COUNT(accepted_response_sec) OVER (PARTITION BY service_type, offer_hour) AS accepted_sample_size,
        COUNT(rejected_response_sec) OVER (PARTITION BY service_type, offer_hour) AS rejected_sample_size,
        COUNT(timeout_duration_sec) OVER (PARTITION BY service_type, offer_hour) AS timeout_sample_size,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY response_sec)
            OVER (PARTITION BY service_type, offer_hour) AS response_p50_sec,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY response_sec)
            OVER (PARTITION BY service_type, offer_hour) AS response_p90_sec,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY accepted_response_sec)
            OVER (PARTITION BY service_type, offer_hour) AS accepted_p50_sec,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY accepted_response_sec)
            OVER (PARTITION BY service_type, offer_hour) AS accepted_p90_sec,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rejected_response_sec)
            OVER (PARTITION BY service_type, offer_hour) AS rejected_p50_sec,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY rejected_response_sec)
            OVER (PARTITION BY service_type, offer_hour) AS rejected_p90_sec,
        AVG(timeout_duration_sec) OVER (PARTITION BY service_type, offer_hour) AS avg_timeout_duration_sec
    FROM offer_time
)
SELECT DISTINCT service_type, offer_hour, total_offers, decision_offers, timeout_offers,
    ROUND(timeout_offers * 100.0 / NULLIF(decision_offers, 0), 2) AS timeout_rate_pct,
    response_sample_size, accepted_sample_size, rejected_sample_size, timeout_sample_size,
    ROUND(response_p50_sec, 2) AS response_p50_sec,
    ROUND(response_p90_sec, 2) AS response_p90_sec,
    ROUND(accepted_p50_sec, 2) AS accepted_p50_sec,
    ROUND(accepted_p90_sec, 2) AS accepted_p90_sec,
    ROUND(rejected_p50_sec, 2) AS rejected_p50_sec,
    ROUND(rejected_p90_sec, 2) AS rejected_p90_sec,
    ROUND(avg_timeout_duration_sec, 2) AS avg_timeout_duration_sec
FROM response_summary
ORDER BY service_type, offer_hour;
GO
-- Identify zones with high demand relative to available supply (Demand relative to available and online driver-hours)
WITH demand AS (
    SELECT pickup_zone_id AS zone_id, service_type, DATEPART(HOUR, created_at) AS activity_hour,
        COUNT(*) AS total_request,
        SUM(CASE WHEN accepted_at IS NOT NULL THEN 1 ELSE 0 END) AS matched_requests
    FROM dbo.trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
    GROUP BY pickup_zone_id, service_type, DATEPART(HOUR, created_at)
),
supply AS (
    SELECT zone_id, service_type, DATEPART(HOUR, interval_start_at) AS activity_hour,
        COUNT(*) AS observed_supply_intervals,
        SUM(available_driver_minutes) / 60.0 AS available_driver_hours,
        SUM(online_driver_minutes) / 60.0 AS online_driver_hours
    FROM dbo.supply_15min_table
    WHERE interval_start_at >= '20260401' AND interval_start_at < '20261001'
    GROUP BY zone_id, service_type, DATEPART(HOUR, interval_start_at)
),
exposure AS (
    SELECT COALESCE(d.zone_id, s.zone_id) AS zone_id,
        COALESCE(d.service_type, s.service_type) AS service_type,
        COALESCE(d.activity_hour, s.activity_hour) AS activity_hour,
        COALESCE(d.total_request, 0) AS total_request,
        COALESCE(d.matched_requests, 0) AS matched_requests,
        COALESCE(s.observed_supply_intervals, 0) AS observed_supply_intervals,
        s.available_driver_hours, s.online_driver_hours
    FROM demand d
    FULL OUTER JOIN supply s ON d.zone_id = s.zone_id
        AND d.service_type = s.service_type AND d.activity_hour = s.activity_hour
)
SELECT e.zone_id, z.zone_name, e.service_type, e.activity_hour,
    e.total_request, e.observed_supply_intervals,
    ROUND(e.available_driver_hours, 2) AS available_driver_hours,
    ROUND(e.online_driver_hours, 2) AS online_driver_hours,
    ROUND(e.total_request / NULLIF(e.available_driver_hours, 0), 2) AS requests_per_available_driver_hour,
    ROUND(e.total_request / NULLIF(e.online_driver_hours, 0), 2) AS requests_per_online_hour,
    CASE WHEN e.available_driver_hours = 0 THEN 1 ELSE 0 END AS zero_available_supply,
    CASE WHEN e.online_driver_hours = 0 THEN 1 ELSE 0 END AS zero_online_supply,
    CASE WHEN e.observed_supply_intervals = 0 THEN 1 ELSE 0 END AS missing_supply,
    CASE WHEN e.total_request < 30 THEN 1 ELSE 0 END AS small_sample
FROM exposure e
LEFT JOIN dbo.zone_table z ON e.zone_id = z.zone_id
ORDER BY missing_supply DESC, zero_available_supply DESC,
    requests_per_available_driver_hour DESC, e.total_request DESC,
    e.zone_id, e.service_type, e.activity_hour;
GO
-- Compare driver supply levels with trip match rates (Does lower supply exposure coincide with a lower match rate?)
WITH demand AS (
    SELECT pickup_zone_id AS zone_id, service_type, DATEPART(HOUR, created_at) AS activity_hour,
        COUNT(*) AS total_request,
        SUM(CASE WHEN accepted_at IS NOT NULL THEN 1 ELSE 0 END) AS matched_requests
    FROM dbo.trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
    GROUP BY pickup_zone_id, service_type, DATEPART(HOUR, created_at)
),
supply AS (
    SELECT zone_id, service_type, DATEPART(HOUR, interval_start_at) AS activity_hour,
        COUNT(*) AS observed_supply_intervals,
        SUM(available_driver_minutes) / 60.0 AS available_driver_hours,
        SUM(online_driver_minutes) / 60.0 AS online_driver_hours
    FROM dbo.supply_15min_table
    WHERE interval_start_at >= '20260401' AND interval_start_at < '20261001'
    GROUP BY zone_id, service_type, DATEPART(HOUR, interval_start_at)
),
exposure AS (
    SELECT COALESCE(d.zone_id, s.zone_id) AS zone_id,
        COALESCE(d.service_type, s.service_type) AS service_type,
        COALESCE(d.activity_hour, s.activity_hour) AS activity_hour,
        COALESCE(d.total_request, 0) AS total_request,
        COALESCE(d.matched_requests, 0) AS matched_requests,
        COALESCE(s.observed_supply_intervals, 0) AS observed_supply_intervals,
        s.available_driver_hours, s.online_driver_hours
    FROM demand d
    FULL OUTER JOIN supply s ON d.zone_id = s.zone_id
        AND d.service_type = s.service_type AND d.activity_hour = s.activity_hour
),
comparison AS (
    SELECT *,
        available_driver_hours / NULLIF(total_request, 0) AS available_hours_per_request,
        matched_requests * 100.0 / NULLIF(total_request, 0) AS match_rate_pct,
        SUM(available_driver_hours) OVER (PARTITION BY service_type, activity_hour)
            / NULLIF(SUM(total_request) OVER (PARTITION BY service_type, activity_hour), 0)
            AS service_hour_available_hours_per_request,
        SUM(matched_requests) OVER (PARTITION BY service_type, activity_hour) * 100.0
            / NULLIF(SUM(total_request) OVER (PARTITION BY service_type, activity_hour), 0)
            AS service_hour_match_rate_pct,
        SUM(total_request) OVER (PARTITION BY service_type, activity_hour) AS baseline_requests
    FROM exposure
    WHERE total_request > 0 AND observed_supply_intervals > 0
)
SELECT c.zone_id, z.zone_name, c.service_type, c.activity_hour,
    c.total_request, c.matched_requests, c.baseline_requests,
    ROUND(c.available_driver_hours, 2) AS available_driver_hours,
    ROUND(c.online_driver_hours, 2) AS online_driver_hours,
    ROUND(c.available_hours_per_request, 4) AS available_hours_per_request,
    ROUND(c.service_hour_available_hours_per_request, 4) AS service_hour_available_hours_per_request,
    ROUND(c.match_rate_pct, 2) AS match_rate_pct,
    ROUND(c.service_hour_match_rate_pct, 2) AS service_hour_match_rate_pct,
    ROUND(c.match_rate_pct - c.service_hour_match_rate_pct, 2) AS match_rate_gap_pp,
    CASE WHEN c.available_hours_per_request < c.service_hour_available_hours_per_request
        THEN 1 ELSE 0 END AS below_baseline_supply,
    CASE WHEN c.available_hours_per_request < c.service_hour_available_hours_per_request
        AND c.match_rate_pct < c.service_hour_match_rate_pct THEN 1 ELSE 0 END AS both_low,
    CASE WHEN c.total_request < 30 THEN 1 ELSE 0 END AS small_sample
FROM comparison c
LEFT JOIN dbo.zone_table z ON c.zone_id = z.zone_id
ORDER BY c.service_type, c.activity_hour, c.available_hours_per_request, c.zone_id;
GO
-- Compare driver productivity and online-time utilization. Is high completed volume associated with more hours or higher productivity?
WITH state_bounds AS (
    SELECT i.driver_id, i.service_type, i.state,
        CASE WHEN i.started_at < '20260401' THEN CAST('20260401' AS DATETIME2(0))
            ELSE i.started_at END AS segment_start,
        CASE WHEN i.ended_at > '20261001' THEN CAST('20261001' AS DATETIME2(0))
            ELSE i.ended_at END AS segment_end
    FROM dbo.driver_state_interval_table i
    WHERE i.started_at < '20261001' AND i.ended_at > '20260401'
),
driver_time AS (
    SELECT driver_id, service_type,
        SUM(DATEDIFF_BIG(SECOND, segment_start, segment_end)) AS online_sec,
        SUM(CASE WHEN state = 'AVAILABLE'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS available_sec,
        SUM(CASE WHEN state = 'OFFER_PENDING'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS offer_pending_sec,
        SUM(CASE WHEN state = 'TO_PICKUP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS to_pickup_sec,
        SUM(CASE WHEN state = 'WAITING_PICKUP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS waiting_pickup_sec,
        SUM(CASE WHEN state = 'ON_TRIP'
            THEN DATEDIFF_BIG(SECOND, segment_start, segment_end) ELSE 0 END) AS on_trip_sec
    FROM state_bounds
    WHERE segment_end > segment_start
    GROUP BY driver_id, service_type
),
completed AS (
    SELECT driver_id, service_type, COUNT(*) AS completed_trips
    FROM dbo.trip_table
    WHERE status = 4 AND finished_at >= '20260401' AND finished_at < '20261001'
    GROUP BY driver_id, service_type
),
productivity AS (
    SELECT t.*, COALESCE(c.completed_trips, 0) AS completed_trips,
        COALESCE(c.completed_trips, 0) * 3600.0 / NULLIF(t.online_sec, 0) AS trips_per_online_hour
    FROM driver_time t
    LEFT JOIN completed c ON t.driver_id = c.driver_id AND t.service_type = c.service_type
)
SELECT p.driver_id, p.service_type,
    ROUND(p.online_sec / 3600.0, 2) AS online_hours,
    p.completed_trips,
    ROUND(p.trips_per_online_hour, 2) AS trips_per_online_hour,
    ROUND((p.to_pickup_sec + p.waiting_pickup_sec + p.on_trip_sec) * 100.0
        / NULLIF(p.online_sec, 0), 2) AS occupied_utilization_pct,
    ROUND(p.on_trip_sec * 100.0 / NULLIF(p.online_sec, 0), 2) AS on_trip_utilization_pct,
    ROUND(SUM(p.completed_trips) OVER (PARTITION BY p.service_type) * 3600.0
        / NULLIF(SUM(p.online_sec) OVER (PARTITION BY p.service_type), 0), 2)
        AS service_trips_per_online_hour,
    ROUND(AVG(p.online_sec * 1.0) OVER (PARTITION BY p.service_type) / 3600.0, 2)
        AS service_avg_online_hours,
    DENSE_RANK() OVER (PARTITION BY p.service_type ORDER BY p.completed_trips DESC) AS completed_trips_rank,
    DENSE_RANK() OVER (PARTITION BY p.service_type ORDER BY p.online_sec DESC) AS online_hours_rank,
    DENSE_RANK() OVER (PARTITION BY p.service_type ORDER BY p.trips_per_online_hour DESC) AS trips_per_hour_rank
FROM productivity p
LEFT JOIN dbo.driver_table d ON p.driver_id = d.driver_id
ORDER BY p.service_type, completed_trips_rank, p.driver_id;
GO
