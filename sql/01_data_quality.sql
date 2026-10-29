-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Read-only checks. Requires the eleven imported source tables; no views required.
SET NOCOUNT ON;
-- Duplicate event IDs and composite supply keys: expect no rows.
SELECT trip_id, COUNT_BIG(*) AS duplicate_count
FROM dbo.trip_table GROUP BY trip_id HAVING COUNT_BIG(*)>1;
SELECT offer_id, COUNT_BIG(*) AS duplicate_count
FROM dbo.dispatch_offer_table GROUP BY offer_id HAVING COUNT_BIG(*)>1;
SELECT interval_start_at,zone_id,service_type,COUNT_BIG(*) AS duplicate_count
FROM dbo.supply_15min_table
GROUP BY interval_start_at,zone_id,service_type HAVING COUNT_BIG(*)>1;
GO
-- Missing fields and status/timestamp consistency: counts should be zero.
SELECT COUNT(*) AS requests,
 SUM(CASE WHEN user_id IS NULL OR created_at IS NULL OR service_type IS NULL THEN 1 ELSE 0 END) AS missing_required_fields,
 SUM(CASE WHEN status NOT IN (1,2,3,4,5,6,7) OR status IS NULL THEN 1 ELSE 0 END) AS invalid_status,
 SUM(CASE WHEN (status=4 AND finished_at IS NULL) OR (status<>4 AND finished_at IS NOT NULL) THEN 1 ELSE 0 END) AS finish_mismatch,
 SUM(CASE WHEN (status IN (5,6) AND cancelled_at IS NULL) OR (status NOT IN (5,6) AND cancelled_at IS NOT NULL) THEN 1 ELSE 0 END) AS cancel_mismatch,
 SUM(CASE WHEN (status=7 AND expired_at IS NULL) OR (status<>7 AND expired_at IS NOT NULL) THEN 1 ELSE 0 END) AS expiry_mismatch,
 SUM(CASE WHEN (driver_id IS NULL AND accepted_at IS NOT NULL) OR (driver_id IS NOT NULL AND accepted_at IS NULL) THEN 1 ELSE 0 END) AS driver_match_mismatch,
 SUM(CASE WHEN (status=5 AND ISNULL(cancelled_by,'')<>'CUSTOMER') OR (status=6 AND ISNULL(cancelled_by,'')<>'DRIVER') THEN 1 ELSE 0 END) AS actor_mismatch,
 SUM(CASE WHEN accepted_at<created_at OR arrived_at<accepted_at OR pickup_at<arrived_at
 OR finished_at<pickup_at OR cancelled_at<created_at OR expired_at<created_at
 OR (arrived_at IS NOT NULL AND accepted_at IS NULL) OR (pickup_at IS NOT NULL AND arrived_at IS NULL)
 THEN 1 ELSE 0 END) AS invalid_event_order
FROM dbo.trip_table;
GO
-- Referential integrity, excluding valid unmatched-driver NULL values.
SELECT 'request_user' AS check_name,COUNT(*) AS violations FROM dbo.trip_table t
WHERE NOT EXISTS (SELECT 1 FROM dbo.user_table u WHERE u.user_id=t.user_id)
UNION ALL SELECT 'request_driver',COUNT(*) FROM dbo.trip_table t
WHERE t.driver_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.driver_table d WHERE d.driver_id=t.driver_id)
UNION ALL SELECT 'pickup_zone',COUNT(*) FROM dbo.trip_table t
WHERE NOT EXISTS(SELECT 1 FROM dbo.zone_table z WHERE z.zone_id=t.pickup_zone_id)
UNION ALL SELECT 'dropoff_zone',COUNT(*) FROM dbo.trip_table t
WHERE NOT EXISTS(SELECT 1 FROM dbo.zone_table z WHERE z.zone_id=t.dropoff_zone_id)
UNION ALL SELECT 'request_weather',COUNT(*) FROM dbo.trip_table t
WHERE NOT EXISTS(SELECT 1 FROM dbo.weather_hourly_table w WHERE w.weather_id=t.weather_id)
UNION ALL SELECT 'offer_request',COUNT(*) FROM dbo.dispatch_offer_table o
WHERE NOT EXISTS(SELECT 1 FROM dbo.trip_table t WHERE t.trip_id=o.trip_id)
UNION ALL SELECT 'offer_session_driver',COUNT(*) FROM dbo.dispatch_offer_table o
WHERE NOT EXISTS(SELECT 1 FROM dbo.driver_session_table s WHERE s.session_id=o.session_id AND s.driver_id=o.driver_id)
UNION ALL SELECT 'request_before_registration',COUNT(*) FROM dbo.trip_table t JOIN dbo.user_table u ON t.user_id=u.user_id
WHERE t.created_at<u.registered_at;
GO
-- Aggregate offers before joining requests; preserve one row per request.
WITH offers AS (
 SELECT trip_id,SUM(CASE WHEN outcome='ACCEPTED' THEN 1 ELSE 0 END) AS accepted_offers,
 MAX(CASE WHEN outcome='ACCEPTED' THEN driver_id END) AS accepted_driver
 FROM dbo.dispatch_offer_table GROUP BY trip_id)
SELECT t.trip_id,o.accepted_offers FROM dbo.trip_table t LEFT JOIN offers o ON t.trip_id=o.trip_id
WHERE COALESCE(o.accepted_offers,0)>1
 OR (t.accepted_at IS NOT NULL AND (COALESCE(o.accepted_offers,0)<>1 OR t.driver_id<>o.accepted_driver))
 OR (t.accepted_at IS NULL AND COALESCE(o.accepted_offers,0)<>0);
GO
-- Compare each start with the latest previous end, including nested overlaps.
DECLARE @cutoff datetime2(0)='2026-10-01T00:00:00';
WITH bounds AS (
 SELECT trip_id,driver_id,accepted_at,
 COALESCE(finished_at,cancelled_at,expired_at,@cutoff) AS end_at
 FROM dbo.trip_table WHERE accepted_at IS NOT NULL),
ordered AS (
 SELECT *,MAX(end_at) OVER(PARTITION BY driver_id ORDER BY accepted_at,trip_id
 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS previous_end FROM bounds)
SELECT trip_id,driver_id,accepted_at,previous_end FROM ordered WHERE accepted_at<previous_end;
GO
-- Reconcile three independent exposure representations; rounding tolerance 0.1 minute.
SELECT SUM(online_driver_minutes) AS supply_online_minutes,
 (SELECT SUM(DATEDIFF_BIG(SECOND,online_at,observation_end_at))/60.0 FROM dbo.driver_session_table) AS session_online_minutes,
 (SELECT SUM(DATEDIFF_BIG(SECOND,started_at,ended_at))/60.0 FROM dbo.driver_state_interval_table) AS state_online_minutes,
 SUM(online_driver_minutes-available_driver_minutes-offer_pending_driver_minutes-occupied_driver_minutes) AS rounded_component_residual
FROM dbo.supply_15min_table;
-- Component residual is reported separately: summing rounded fields need not be exact.
GO
