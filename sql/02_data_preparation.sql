-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
-- Reusable views, in dependency order; execute only in a review database.
CREATE OR ALTER VIEW v_trip_enriched AS
SELECT 
    trip_id,
    created_at,
    CAST(created_at as date) AS trip_date,
    DATEFROMPARTS(YEAR(created_at), MONTH(created_at), 1) AS start_month,
    DATEPART(DAY,created_at) AS trip_day,
    DATEPART(MONTH,created_at) AS trip_month,
    DATEPART(HOUR, created_at) AS trip_hour,
    DATEDIFF(DAY,'19000101', CAST(created_at as date)) % 7 + 1 AS week_day, -- Mon=1..Sun=7
    case when DATEDIFF(DAY,'19000101', CAST(created_at as date)) % 7 + 1 in (6,7)
        then 1 else 0 end AS is_weekend,
    DATEADD(MINUTE,
        DATEDIFF(MINUTE, CAST('19000101' AS DATETIME2(0)), created_at) / 15 * 15,
        CAST('19000101' AS DATETIME2(0))) AS bucket_15min_start,
    DATEDIFF(SECOND, created_at, accepted_at) AS allocation_sec,
    DATEDIFF(SECOND, accepted_at, arrived_at) AS approach_sec,
    DATEDIFF(SECOND, arrived_at, pickup_at) AS pickup_dwell_sec,
    DATEDIFF(SECOND, created_at, pickup_at) AS total_wait_sec,
    DATEDIFF(SECOND, pickup_at, finished_at) AS ride_sec,
    DATEDIFF(SECOND, created_at, finished_at) AS end_to_end_sec,
    CASE 
        WHEN cancelled_at IS NULL THEN NULL
        WHEN accepted_at IS NULL THEN 'cancel_before_match'
        WHEN arrived_at IS NULL OR cancelled_at < arrived_at THEN 'cancel_after_match_before_arrival'
        WHEN arrived_at IS NOT NULL AND cancelled_at >= arrived_at THEN 'cancel_at_pickup'
    END AS 'cancellation_stage'
FROM trip_table;
GO

CREATE OR ALTER VIEW v_offer_per_trip AS
SELECT 
    t.trip_id,
    COUNT(do.offer_id) AS offers,
    SUM(CASE WHEN do.outcome = 'ACCEPTED' THEN 1 ELSE 0 END) AS 'accepted',
    SUM(CASE WHEN do.outcome = 'REJECTED' THEN 1 ELSE 0 END) AS 'rejected',
    SUM(CASE WHEN do.outcome = 'TIMEOUT' THEN 1 ELSE 0 END) AS 'timeout',
    SUM(CASE WHEN do.outcome = 'WITHDRAWN' THEN 1 ELSE 0 END) AS 'withdrawn',
    SUM(CASE WHEN do.outcome = 'PENDING' THEN 1 ELSE 0 END) AS 'pending'
from trip_table t
LEFT JOIN dispatch_offer_table do ON do.trip_id = t.trip_id
GROUP BY t.trip_id
GO
-- One registered customer; include zero-request customers.
CREATE OR ALTER VIEW dbo.v_customer_summary AS

SELECT 
    u.user_id,
    COUNT(t.trip_id) AS total_request,
    SUM(CASE WHEN t.status = 4 THEN 1 ELSE 0 END) AS total_completed
from user_table u
LEFT JOIN trip_table t ON u.[user_id] = t.[user_id] 
    AND t.created_at >= datefromparts(2026,04,01)
    AND t.created_at < datefromparts(2026,10,01)
group by u.user_id
GO
CREATE OR ALTER VIEW dbo.v_zone_service_15min AS
SELECT
    s.interval_start_at,
    s.zone_id,
    s.service_type,
    COALESCE(d.total_request, 0) AS total_request,
    s.online_driver_minutes,
    s.available_driver_minutes,
    s.occupied_driver_minutes
FROM supply_15min_table AS s
LEFT JOIN (
    SELECT
        te.bucket_15min_start,
        t.pickup_zone_id,
        t.service_type,
        COUNT(te.trip_id) AS total_request
    FROM v_trip_enriched AS te
    INNER JOIN trip_table AS t ON te.trip_id = t.trip_id
    GROUP BY te.bucket_15min_start, t.pickup_zone_id, t.service_type
) AS d
       ON d.bucket_15min_start = s.interval_start_at
      AND d.pickup_zone_id = s.zone_id
      AND d.service_type = s.service_type;
GO

