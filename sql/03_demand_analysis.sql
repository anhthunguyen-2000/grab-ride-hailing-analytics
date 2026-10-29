-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
-- Track daily and monthly trip requests and active customers.
SELECT 
    te.trip_date,
    COUNT(t.trip_id) AS total_request,
    COUNT(distinct([user_id])) AS unique_active_customers,
    SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END) AS total_completed_trips,
    COUNT(DISTINCT CASE WHEN t.status = 4 THEN t.[user_id] end) AS unique_customers_completed
FROM trip_table t 
INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
GROUP BY te.trip_date
ORDER BY te.trip_date;
GO
SELECT 
    te.trip_month,
    COUNT(t.trip_id) AS total_request,
    COUNT(distinct([user_id])) AS unique_active_customers,
    SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END) AS total_completed_trips,
    COUNT(DISTINCT CASE WHEN t.status = 4 THEN t.[user_id] end) AS unique_customers_completed
FROM trip_table t 
INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
GROUP BY te.trip_month
ORDER BY te.trip_month;
GO
-- Compare monthly demand and completion performance
WITH monthly_trip_comparison AS (
    SELECT 
        te.trip_month,
        COUNT(t.trip_id) AS total_request,
        LAG(COUNT(t.trip_id)) OVER (order by te.trip_month) AS total_request_previous_month,
        SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END) AS total_completed_trips,
        LAG(SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END)) OVER (
            ORDER BY te.trip_month
        ) AS total_completed_trips_previous_month
    FROM trip_table t 
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    GROUP BY te.trip_month
)
SELECT
    trip_month,
    total_request,
    total_request_previous_month,
    total_completed_trips,
    total_request - total_request_previous_month AS trip_difference,
    ROUND((total_request - total_request_previous_month) * 100.0 /
        NULLIF(total_request_previous_month,0)
        , 2) AS request_growth_MoM,
    ROUND((total_completed_trips - total_completed_trips_previous_month) * 100.0
        /NULLIF(total_completed_trips_previous_month,0)
        , 2) AS completion_growth_MoM,
    ROUND(total_completed_trips * 100.0 / total_request
        , 2) AS completion_rate
FROM monthly_trip_comparison;
GO
-- Identify peak booking hours on weekdays and weekends
WITH booking AS (
    SELECT 
        trip_hour,
        SUM(CASE WHEN is_weekend = 0 THEN 1 ELSE 0 END) AS weekdays_booking,
        SUM(CASE WHEN is_weekend = 1 THEN 1 ELSE 0 END) AS weekends_booking
    FROM v_trip_enriched
    GROUP BY trip_hour
),
ranked_booking AS (
    SELECT
        trip_hour,
        weekdays_booking,
        weekends_booking,
        ROW_NUMBER() OVER (ORDER BY weekdays_booking DESC, trip_hour) AS weekdays_rank,
        ROW_NUMBER() OVER (ORDER BY weekends_booking DESC, trip_hour) AS weekends_rank
    FROM booking
)
SELECT 
    'Weekdays' AS day_type,
    weekdays_rank AS booking_rank,
    trip_hour,
    weekdays_booking AS peak_booking
FROM ranked_booking
WHERE weekdays_rank <= 5 AND weekdays_booking > 0
UNION ALL
SELECT 
    'Weekends' AS day_type,
    weekends_rank AS booking_rank,
    trip_hour,
    weekends_booking AS peak_booking
FROM ranked_booking
WHERE weekends_rank <= 5 AND weekends_booking > 0
ORDER BY day_type, booking_rank;
GO
-- Compare booking demand and service preferences by zone.
SELECT 
    t.pickup_zone_id,
    COUNT(t.trip_id) AS total_request,
    COUNT(t.trip_id) * 100.0 / SUM(COUNT(t.trip_id)) OVER () AS zone_share,
    SUM(CASE WHEN t.service_type = 'BIKE' THEN 1 ELSE 0 END) AS total_bike,
    SUM(CASE WHEN t.service_type = 'CAR' THEN 1 ELSE 0 END) AS total_car,
    SUM(CASE WHEN t.service_type = 'BIKE' THEN 1 ELSE 0 END) * 100.0 
        / NULLIF(COUNT(t.trip_id),0) AS bike_rate,
    SUM(CASE WHEN t.service_type = 'CAR' THEN 1 ELSE 0 END) * 100.0 
        / NULLIF(COUNT(t.trip_id),0) AS car_rate
from trip_table t
LEFT JOIN zone_table z ON t.pickup_zone_id = z.zone_id
GROUP BY t.pickup_zone_id
ORDER BY t.pickup_zone_id
-- Identify the most popular pickup-to-dropoff zone pairs.
SELECT TOP (10)
    t.pickup_zone_id,
    pz.zone_name AS pickup_zone,
    t.dropoff_zone_id,
    dz.zone_name AS dropoff_zone,
    t.service_type,
    COUNT(t.trip_id) AS total_request,
    SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END) AS total_completed_trips,
    ROUND(SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END) * 100.0
        / COUNT(t.trip_id), 2) AS completion_rate
FROM trip_table t
INNER JOIN zone_table pz ON t.pickup_zone_id = pz.zone_id
INNER JOIN zone_table dz ON t.dropoff_zone_id = dz.zone_id
WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
GROUP BY t.pickup_zone_id, pz.zone_name, t.dropoff_zone_id, dz.zone_name, t.service_type
ORDER BY total_request DESC, t.pickup_zone_id, t.dropoff_zone_id, t.service_type;
GO
-- Analyze demand and completion performance by trip distance.
WITH distance_booking AS (
    SELECT
        CASE
            WHEN t.estimated_trip_distance_km < 2 THEN '<2 km'
            WHEN t.estimated_trip_distance_km < 5 THEN '2-<5 km'
            WHEN t.estimated_trip_distance_km < 10 THEN '5-<10 km'
            ELSE '>=10 km'
        END AS distance_group,
        t.status,
        te.total_wait_sec / 60.0 AS total_wait_min
    FROM trip_table t
    INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
),
distance_summary AS (
    SELECT
        distance_group,
        COUNT(*) OVER (PARTITION BY distance_group) AS total_request,
        SUM(CASE WHEN status = 4 THEN 1 ELSE 0 END)
            OVER (PARTITION BY distance_group) AS total_completed_trips,
        COUNT(total_wait_min) OVER (PARTITION BY distance_group) AS waiting_sample_size,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_wait_min)
            OVER (PARTITION BY distance_group) AS median_waiting_min,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY total_wait_min)
            OVER (PARTITION BY distance_group) AS p90_waiting_min
    FROM distance_booking
)
SELECT DISTINCT
    distance_group,
    total_request,
    total_completed_trips,
    ROUND(total_completed_trips * 100.0 / total_request, 2) AS completion_rate,
    waiting_sample_size,
    ROUND(median_waiting_min, 2) AS median_waiting_min,
    ROUND(p90_waiting_min, 2) AS p90_waiting_min,
    CASE distance_group
        WHEN '<2 km' THEN 1
        WHEN '2-<5 km' THEN 2
        WHEN '5-<10 km' THEN 3
        ELSE 4
    END AS distance_group_order
FROM distance_summary
ORDER BY distance_group_order;
GO
-- Compare hourly booking demand during rainy and dry weather.
WITH hourly_booking AS (
    SELECT
        t.weather_id,
        t.service_type,
        COUNT(t.trip_id) AS total_request
    FROM trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
    GROUP BY t.weather_id, t.service_type
)
SELECT
    w.zone_id AS pickup_zone_id,
    z.zone_name AS pickup_zone,
    DATEPART(HOUR, w.hour_start_at) AS trip_hour,
    s.service_type,
    w.is_raining,
    COUNT(*) AS observed_hours,
    SUM(COALESCE(b.total_request, 0)) AS total_request,
    ROUND(SUM(COALESCE(b.total_request, 0)) * 1.0 / COUNT(*), 2) AS requests_per_hour
FROM weather_hourly_table w
CROSS JOIN service_table s
INNER JOIN zone_table z ON w.zone_id = z.zone_id
LEFT JOIN hourly_booking b ON w.weather_id = b.weather_id
    AND s.service_type = b.service_type
WHERE w.hour_start_at >= '20260401' AND w.hour_start_at < '20261001'
GROUP BY w.zone_id, z.zone_name, DATEPART(HOUR, w.hour_start_at),
    s.service_type, w.is_raining
ORDER BY w.zone_id, trip_hour, s.service_type, w.is_raining;
GO
-- Analyze customer booking retries after failed requests.
SELECT
    te.trip_hour,
    COUNT(t.trip_id) AS total_request,
    SUM(CASE WHEN t.parent_trip_id IS NULL THEN 1 ELSE 0 END) AS original_requests,
    SUM(CASE WHEN t.parent_trip_id IS NOT NULL THEN 1 ELSE 0 END) AS retry_requests,
    ROUND(SUM(CASE WHEN t.parent_trip_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0
        / COUNT(t.trip_id), 2) AS retry_share
FROM trip_table t
INNER JOIN v_trip_enriched te ON t.trip_id = te.trip_id
WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
GROUP BY te.trip_hour
ORDER BY retry_requests DESC, te.trip_hour;
GO
