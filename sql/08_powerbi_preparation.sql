-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
-- Grab portfolio preparation only. Existing analytical views and raw tables remain unchanged.
-- Execute in Ride_Hailing, in file order. Period is local UTC+7, [2026-04-01,2026-10-01).
-- Trip grain: one request. Reuse existing enrichment; restore raw attributes by unique trip_id.
CREATE OR ALTER VIEW dbo.v_pbi_trip AS
SELECT t.trip_id,t.user_id,t.driver_id,t.created_at,t.accepted_at,t.arrived_at,t.pickup_at,
 t.finished_at,t.cancelled_at,t.expired_at,t.status,t.cancelled_by,t.cancel_reason,
 t.service_type,t.pickup_zone_id,t.dropoff_zone_id,t.quoted_pickup_eta_min,
 t.request_group_id,t.parent_trip_id,
 e.trip_date AS RequestDate,e.trip_hour AS RequestHour,e.bucket_15min_start AS Request15Min,
 e.allocation_sec,e.approach_sec,e.pickup_dwell_sec,e.total_wait_sec,e.ride_sec,e.end_to_end_sec,
 CASE WHEN t.status=7 THEN 'Expired / no driver' ELSE e.cancellation_stage END AS cancellation_stage,
 CASE WHEN t.quoted_pickup_eta_min IS NULL THEN 'Unknown'
 WHEN t.quoted_pickup_eta_min<3 THEN '01 | <3 min'
 WHEN t.quoted_pickup_eta_min<6 THEN '02 | 3-<6 min'
 WHEN t.quoted_pickup_eta_min<12 THEN '03 | 6-<12 min' ELSE '04 | 12+ min' END AS eta_band
FROM dbo.trip_table t JOIN dbo.v_trip_enriched e ON t.trip_id=e.trip_id
WHERE t.created_at>='20260401' AND t.created_at<'20261001';
GO
-- Offer grain: one dispatch attempt, never joined into FactTrips.
CREATE OR ALTER VIEW dbo.v_offer_enriched AS
SELECT o.*,CAST(sent_at AS date) AS SentDate,DATEPART(hour,sent_at) AS SentHour,
 DATEDIFF(second,sent_at,response_at) AS response_sec,
 DATEDIFF(second,sent_at,resolved_at) AS resolution_sec
FROM dbo.dispatch_offer_table o WHERE sent_at>='20260401' AND sent_at<'20261001';
GO
-- Supply grain: one interval x zone x service. Existing supply-led view preserves zeros.
CREATE OR ALTER VIEW dbo.v_pbi_supply AS
SELECT v.interval_start_at,v.zone_id,v.service_type,CAST(v.interval_start_at AS date) AS RequestDate,
 DATEPART(hour,v.interval_start_at) AS RequestHour,v.total_request AS requests,
 COALESCE(d.matched,0) AS matched,COALESCE(d.completed,0) AS completed,COALESCE(d.failed,0) AS failed,
 v.online_driver_minutes,v.available_driver_minutes,v.occupied_driver_minutes,
 s.offer_pending_driver_minutes,s.to_pickup_driver_minutes,s.waiting_pickup_driver_minutes,s.on_trip_driver_minutes
FROM dbo.v_zone_service_15min v
JOIN dbo.supply_15min_table s ON s.interval_start_at=v.interval_start_at AND s.zone_id=v.zone_id AND s.service_type=v.service_type
LEFT JOIN (SELECT Request15Min,pickup_zone_id,service_type,
 SUM(CASE WHEN accepted_at IS NOT NULL THEN 1 ELSE 0 END) AS matched,
 SUM(CASE WHEN status=4 THEN 1 ELSE 0 END) AS completed,
 SUM(CASE WHEN status IN (5,6,7) THEN 1 ELSE 0 END) AS failed
 FROM dbo.v_pbi_trip GROUP BY Request15Min,pickup_zone_id,service_type) d
 ON v.interval_start_at=d.Request15Min AND v.zone_id=d.pickup_zone_id AND v.service_type=d.service_type
WHERE v.interval_start_at>='20260401' AND v.interval_start_at<'20261001';
GO
-- State intervals are split at each calendar midnight with half-open boundaries.
CREATE OR ALTER VIEW dbo.v_driver_time_day AS
WITH segments AS (
 SELECT i.driver_id,i.service_type,d.[date] AS activity_date,i.state,
 DATEDIFF_BIG(second,
 CASE WHEN i.started_at>CAST(d.[date] AS datetime2) THEN i.started_at ELSE CAST(d.[date] AS datetime2) END,
 CASE WHEN i.ended_at<DATEADD(day,1,CAST(d.[date] AS datetime2)) THEN i.ended_at ELSE DATEADD(day,1,CAST(d.[date] AS datetime2)) END) AS seconds
 FROM dbo.driver_state_interval_table i JOIN dbo.date_table d
 ON CAST(d.[date] AS datetime2)<i.ended_at AND DATEADD(day,1,CAST(d.[date] AS datetime2))>i.started_at
 WHERE d.[date]>='20260401' AND d.[date]<'20261001')
SELECT driver_id,service_type,activity_date,SUM(seconds)/60.0 AS online_minutes,
 SUM(CASE WHEN state='AVAILABLE' THEN seconds ELSE 0 END)/60.0 AS available_minutes,
 SUM(CASE WHEN state='OFFER_PENDING' THEN seconds ELSE 0 END)/60.0 AS offer_pending_minutes,
 SUM(CASE WHEN state='TO_PICKUP' THEN seconds ELSE 0 END)/60.0 AS to_pickup_minutes,
 SUM(CASE WHEN state='WAITING_PICKUP' THEN seconds ELSE 0 END)/60.0 AS waiting_pickup_minutes,
 SUM(CASE WHEN state='ON_TRIP' THEN seconds ELSE 0 END)/60.0 AS on_trip_minutes,
 SUM(CASE WHEN state IN ('TO_PICKUP','WAITING_PICKUP','ON_TRIP') THEN seconds ELSE 0 END)/60.0 AS occupied_minutes
FROM segments GROUP BY driver_id,service_type,activity_date;
GO
-- Productivity: one driver x activity date x service, completed trips dated by finished_at.
CREATE OR ALTER VIEW dbo.v_driver_day AS
WITH completed AS (SELECT driver_id,service_type,CAST(finished_at AS date) AS activity_date,COUNT(*) AS completed_trips
 FROM dbo.trip_table WHERE status=4 AND finished_at>='20260401' AND finished_at<'20261001'
 GROUP BY driver_id,service_type,CAST(finished_at AS date))
SELECT d.*,COALESCE(c.completed_trips,0) AS completed_trips
FROM dbo.v_driver_time_day d LEFT JOIN completed c ON d.driver_id=c.driver_id AND d.service_type=c.service_type AND d.activity_date=c.activity_date;
GO
-- One first-observed index per requesting customer. Preserve ineligible customers with flag=0.
-- corrected pattern: correlated predicate belongs in WHERE, avoiding SQL error 8124.
CREATE OR ALTER VIEW dbo.v_retention30_user AS
WITH ranked AS (SELECT *,ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY created_at,trip_id) AS rn FROM dbo.v_pbi_trip),
idx AS (SELECT user_id,trip_id AS index_trip_id,request_group_id,created_at AS index_created_at,
 CAST(created_at AS date) AS index_date,service_type AS index_service_type,pickup_zone_id AS index_pickup_zone_id,
 CASE WHEN status=4 THEN finished_at WHEN status IN (5,6) THEN cancelled_at WHEN status=7 THEN expired_at END AS index_end_at,
 CASE WHEN status IN (5,6) THEN 'cancelled' WHEN status=7 THEN 'expired_no_driver'
 WHEN status=4 AND total_wait_sec>720 THEN 'completed_long_wait'
 WHEN status=4 AND total_wait_sec>=0 THEN 'completed_good'
 WHEN status=4 THEN 'completed_unknown_wait' ELSE 'open_or_unknown' END AS outcome_group
 FROM ranked WHERE rn=1)
SELECT i.user_id,i.index_trip_id,i.index_created_at,i.index_date,i.index_service_type,i.index_pickup_zone_id,i.index_end_at,i.outcome_group,
 CASE WHEN i.index_end_at>=i.index_created_at AND i.index_end_at<'20261001' AND DATEADD(day,30,i.index_end_at)<='20261001' THEN 1 ELSE 0 END AS eligible_30d,
 CASE WHEN EXISTS (SELECT 1 FROM dbo.trip_table t WHERE t.user_id=i.user_id AND t.created_at>i.index_end_at
 AND t.created_at<=DATEADD(day,30,i.index_end_at) AND t.created_at<'20261001' AND t.request_group_id<>i.request_group_id) THEN 1 ELSE 0 END AS returned_30d_new_journey
FROM idx i;
GO
-- First-observed cohort x age month. Omit unobserved future cells rather than render false zeros.
CREATE OR ALTER VIEW dbo.v_cohort_monthly AS
WITH monthly AS (SELECT DISTINCT user_id,DATEFROMPARTS(YEAR(created_at),MONTH(created_at),1) AS activity_month FROM dbo.v_pbi_trip),
cohorts AS (SELECT user_id,MIN(activity_month) AS cohort_month FROM monthly GROUP BY user_id),
sizes AS (SELECT cohort_month,COUNT(*) AS cohort_size FROM cohorts GROUP BY cohort_month),
active AS (SELECT c.cohort_month,m.activity_month,COUNT(*) AS active_users FROM cohorts c JOIN monthly m ON c.user_id=m.user_id GROUP BY c.cohort_month,m.activity_month)
SELECT s.cohort_month,a.age_month,s.cohort_size,COALESCE(x.active_users,0) AS active_users
FROM sizes s CROSS JOIN (VALUES(0),(1),(2),(3),(4),(5)) a(age_month)
LEFT JOIN active x ON x.cohort_month=s.cohort_month AND x.activity_month=DATEADD(month,a.age_month,s.cohort_month)
WHERE DATEADD(month,a.age_month+1,s.cohort_month)<='20261001';
GO
-- Fixed full-period customer profile; avoids defective original customer-summary view.
CREATE OR ALTER VIEW dbo.v_pbi_customer_profile AS
WITH profile AS (SELECT u.user_id,COUNT(t.trip_id) AS requests,
 SUM(CASE WHEN t.status=4 THEN 1 ELSE 0 END) AS completed,
 MAX(CASE WHEN t.status=4 THEN t.finished_at END) AS last_completed_at
 FROM dbo.user_table u LEFT JOIN dbo.v_pbi_trip t ON t.user_id=u.user_id
 WHERE u.registered_at<'20261001' GROUP BY u.user_id)
SELECT *,CASE WHEN requests=0 THEN '00 | No requests' WHEN requests=1 THEN '01 | One request'
 WHEN requests<5 THEN '02 | 2-4' WHEN requests<10 THEN '03 | 5-9' WHEN requests<20 THEN '04 | 10-19' ELSE '05 | 20+' END AS frequency_band,
 CASE WHEN completed=0 THEN 'Never completed' WHEN last_completed_at>='20260901' THEN 'Recent: 0-30d'
 WHEN last_completed_at>='20260802' THEN 'Warm: 30-60d' ELSE 'Lapsed: >60d' END AS recency_group,
 CASE WHEN completed=0 THEN 'No completions' WHEN completed=1 THEN 'One completion' WHEN completed<5 THEN '2-4 completions' ELSE '5+ completions' END AS completion_frequency
FROM profile;
GO
