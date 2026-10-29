-- Synthetic ride-hailing portfolio | UTC+7 | [2026-04-01,2026-10-01).
-- Run in your selected project database. See README for prerequisites.
SET NOCOUNT ON;
GO
-- Review correction: isolate correlated new-journey MIN to avoid SQL Server error 8124.
-- CUSTOMER BEHAVIOR & RETENTION ANALYSIS
-- Measure customer activation within 7 days of registration.
WITH signup_activation AS (
    SELECT u.user_id,
        DATEFROMPARTS(YEAR(u.registered_at), MONTH(u.registered_at), 1) AS signup_month,
        CASE WHEN DATEADD(DAY, 7, u.registered_at) <= '20261001' THEN 1 ELSE 0 END AS eligible,
        CASE WHEN EXISTS (
            SELECT 1 FROM dbo.trip_table t
            WHERE t.user_id = u.user_id AND t.created_at >= u.registered_at
                AND t.created_at < DATEADD(DAY, 7, u.registered_at)
                AND t.created_at >= '20260401' AND t.created_at < '20261001'
        ) THEN 1 ELSE 0 END AS activated
    FROM dbo.user_table u
    WHERE u.registered_at >= '20260401' AND u.registered_at < '20261001'
)
SELECT signup_month, COUNT(*) AS total_signups,
    SUM(eligible) AS eligible_signups,
    SUM(1 - eligible) AS excluded_incomplete_followup,
    SUM(CASE WHEN eligible = 1 THEN activated ELSE 0 END) AS activated_7d,
    ROUND(SUM(CASE WHEN eligible = 1 THEN activated ELSE 0 END) * 100.0
        / NULLIF(SUM(eligible), 0), 2) AS activation_7d_pct
FROM signup_activation
GROUP BY signup_month
ORDER BY signup_month;
GO
-- Analyze time from registration to first booking request
WITH first_request AS (
    SELECT user_id, MIN(created_at) AS first_request_at
    FROM dbo.trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
    GROUP BY user_id
),
user_delay AS (
    SELECT u.user_id,
        CASE WHEN u.registered_at < '20260401' THEN 'pre_period_signup_left_censored'
            ELSE 'in_period_signup' END AS signup_history_group,
        f.first_request_at,
        CASE WHEN f.first_request_at >= u.registered_at
            THEN DATEDIFF_BIG(SECOND, u.registered_at, f.first_request_at) / 86400.0
        END AS days_to_first_observed_request
    FROM dbo.user_table u
    LEFT JOIN first_request f ON u.user_id = f.user_id
    WHERE u.registered_at < '20261001'
),
delay_summary AS (
    SELECT signup_history_group,
        COUNT(*) OVER (PARTITION BY signup_history_group) AS registered_users,
        COUNT(first_request_at) OVER (PARTITION BY signup_history_group) AS observed_requesters,
        COUNT(days_to_first_observed_request) OVER (PARTITION BY signup_history_group) AS valid_delay_sample_size,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_first_observed_request)
            OVER (PARTITION BY signup_history_group) AS median_days,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY days_to_first_observed_request)
            OVER (PARTITION BY signup_history_group) AS p90_days
    FROM user_delay
)
SELECT DISTINCT signup_history_group, registered_users, observed_requesters,
    registered_users - observed_requesters AS never_requested_observed_users,
    valid_delay_sample_size,
    ROUND(median_days, 2) AS median_days_to_first_observed_request,
    ROUND(p90_days, 2) AS p90_days_to_first_observed_request
FROM delay_summary
ORDER BY signup_history_group;
GO
-- Measure booking contribution from the top 10% of customers
WITH customer_volume AS (
    SELECT user_id, COUNT(*) AS total_request,
        SUM(CASE WHEN status = 4 THEN 1 ELSE 0 END) AS completed_trips
    FROM dbo.trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
    GROUP BY user_id
),
ranked_customers AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY total_request DESC, user_id) AS customer_rank,
        COUNT(*) OVER () AS active_customers
    FROM customer_volume
)
SELECT COUNT(*) AS active_customers,
    SUM(CASE WHEN customer_rank <= CEILING(active_customers * 0.10) THEN 1 ELSE 0 END) AS top_10pct_customers,
    SUM(total_request) AS all_requests, SUM(completed_trips) AS all_completed_trips,
    SUM(CASE WHEN customer_rank <= CEILING(active_customers * 0.10) THEN total_request ELSE 0 END) AS top_requests,
    SUM(CASE WHEN customer_rank <= CEILING(active_customers * 0.10) THEN completed_trips ELSE 0 END) AS top_completed_trips,
    ROUND(SUM(CASE WHEN customer_rank <= CEILING(active_customers * 0.10) THEN total_request ELSE 0 END)
        * 100.0 / NULLIF(SUM(total_request), 0), 2) AS top_request_contribution_pct,
    ROUND(SUM(CASE WHEN customer_rank <= CEILING(active_customers * 0.10) THEN completed_trips ELSE 0 END)
        * 100.0 / NULLIF(SUM(completed_trips), 0), 2) AS top_completed_contribution_pct
FROM ranked_customers;
GO
-- Segment customers by recency and frequency
WITH customer_rf AS (
    SELECT u.user_id, COUNT(t.trip_id) AS total_request,
        SUM(CASE WHEN t.status = 4 AND t.finished_at < '20261001' THEN 1 ELSE 0 END) AS completed_trips,
        MAX(CASE WHEN t.status = 4 AND t.finished_at < '20261001' THEN t.finished_at END) AS last_completed_at
    FROM dbo.user_table u
    LEFT JOIN dbo.trip_table t ON u.user_id = t.user_id
        AND t.created_at >= '20260401' AND t.created_at < '20261001'
    WHERE u.registered_at < '20261001'
    GROUP BY u.user_id
),
rf_bands AS (
    SELECT *, DATEDIFF_BIG(SECOND, last_completed_at, CAST('20261001' AS DATETIME2(0))) / 86400.0 AS recency_days,
        CASE WHEN last_completed_at IS NULL THEN 'never_completed'
            WHEN last_completed_at >= '20260901' THEN 'recent_0_30d'
            WHEN last_completed_at >= '20260802' THEN 'warm_30_60d'
            ELSE 'lapsed_over_60d' END AS recency_group,
        CASE WHEN completed_trips = 0 THEN 'no_completions'
            WHEN completed_trips = 1 THEN 'one_time'
            WHEN completed_trips < 5 THEN 'repeat_2_4'
            ELSE 'frequent_5_plus' END AS frequency_group
    FROM customer_rf
)
SELECT user_id, total_request, completed_trips, last_completed_at,
    ROUND(recency_days, 2) AS recency_days, recency_group, frequency_group,
    CASE WHEN completed_trips = 0 AND total_request = 0 THEN 'no_observed_requests'
        WHEN completed_trips = 0 THEN 'requested_never_completed'
        ELSE CONCAT(recency_group, '_', frequency_group) END AS rf_segment
FROM rf_bands
ORDER BY user_id;
GO
-- Calculate customer retention from one month to the next
WITH months AS (
    SELECT DISTINCT month_start FROM dbo.date_table
    WHERE [date] >= '20260401' AND [date] < '20261001'
),
monthly_users AS (
    SELECT DISTINCT user_id, DATEFROMPARTS(YEAR(created_at), MONTH(created_at), 1) AS activity_month
    FROM dbo.trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
)
SELECT m.month_start AS activity_month, COUNT(a.user_id) AS active_users,
    CASE WHEN DATEADD(MONTH, 2, m.month_start) <= '20261001' THEN COUNT(b.user_id) END AS retained_next_month_users,
    CASE WHEN DATEADD(MONTH, 2, m.month_start) <= '20261001'
        THEN ROUND(COUNT(b.user_id) * 100.0 / NULLIF(COUNT(a.user_id), 0), 2) END AS monthly_retention_pct
FROM months m
LEFT JOIN monthly_users a ON m.month_start = a.activity_month
LEFT JOIN monthly_users b ON a.user_id = b.user_id
    AND b.activity_month = DATEADD(MONTH, 1, m.month_start)
GROUP BY m.month_start
ORDER BY m.month_start;
GO
-- Analyze monthly retention by first observed booking cohort, M0-M5
WITH monthly_users AS (
    SELECT DISTINCT user_id, DATEFROMPARTS(YEAR(created_at), MONTH(created_at), 1) AS activity_month
    FROM dbo.trip_table
    WHERE created_at >= '20260401' AND created_at < '20261001'
),
user_cohort AS (
    SELECT user_id, MIN(activity_month) AS cohort_month FROM monthly_users GROUP BY user_id
),
cohort_grid AS (
    SELECT c.cohort_month, a.age_month, COUNT(*) AS cohort_size,
        DATEADD(MONTH, a.age_month, c.cohort_month) AS activity_month
    FROM user_cohort c
    CROSS JOIN (VALUES (0), (1), (2), (3), (4), (5)) a(age_month)
    GROUP BY c.cohort_month, a.age_month
),
cohort_activity AS (
    SELECT c.cohort_month, m.activity_month, COUNT(*) AS active_users
    FROM user_cohort c
    INNER JOIN monthly_users m ON c.user_id = m.user_id
    GROUP BY c.cohort_month, m.activity_month
)
SELECT g.cohort_month AS first_observed_cohort_month, g.age_month, g.activity_month, g.cohort_size,
    CASE WHEN DATEADD(MONTH, 1, g.activity_month) <= '20261001'
        THEN COALESCE(a.active_users, 0) END AS active_users,
    CASE WHEN DATEADD(MONTH, 1, g.activity_month) <= '20261001'
        THEN ROUND(COALESCE(a.active_users, 0) * 100.0 / g.cohort_size, 2) END AS cohort_retention_pct
FROM cohort_grid g
LEFT JOIN cohort_activity a ON g.cohort_month = a.cohort_month AND g.activity_month = a.activity_month
ORDER BY g.cohort_month, g.age_month;
GO
-- Measure customer return within 30 days after an index request
WITH ranked_requests AS (
    SELECT t.*, ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.created_at, t.trip_id) AS request_order
    FROM dbo.trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
),
index_request AS (
    SELECT t.user_id, t.trip_id AS index_trip_id, t.request_group_id AS index_request_group_id,
        t.created_at AS index_created_at, t.service_type,
        CASE WHEN t.status = 4 THEN t.finished_at
            WHEN t.status IN (5, 6) THEN t.cancelled_at
            WHEN t.status = 7 THEN t.expired_at END AS index_end_at,
        CASE WHEN t.status IN (5, 6) THEN 'cancelled'
            WHEN t.status = 7 THEN 'expired_no_driver'
            WHEN t.status = 4 AND DATEDIFF_BIG(SECOND, t.created_at, t.pickup_at) > 720 THEN 'completed_long_wait'
            WHEN t.status = 4 AND t.pickup_at >= t.created_at THEN 'completed_good'
            WHEN t.status = 4 THEN 'completed_unknown_wait'
            ELSE 'open_or_unknown' END AS experience_group,
        CASE WHEN u.registered_at < '20260401' THEN 'pre_period_signup'
            WHEN t.created_at < DATEADD(DAY, 30, u.registered_at) THEN 'in_period_tenure_under_30d'
            ELSE 'in_period_tenure_30d_plus' END AS tenure_group,
        (SELECT COUNT(*) FROM dbo.trip_table p
            WHERE p.user_id = t.user_id AND p.created_at >= '20260401'
                AND p.created_at >= DATEADD(DAY, -30, t.created_at)
                AND p.created_at < t.created_at) AS pre_index_requests_30d
    FROM ranked_requests t
    INNER JOIN dbo.user_table u ON t.user_id = u.user_id
    WHERE t.request_order = 1
),
index_followup AS (
    SELECT i.*, r.next_request_inclusive_at, r.next_new_journey_at
    FROM index_request i
    OUTER APPLY (
        SELECT MIN(t.created_at) AS next_request_inclusive_at,
            (SELECT MIN(n.created_at) FROM dbo.trip_table n
                WHERE n.user_id = i.user_id
                    AND n.request_group_id <> i.index_request_group_id
                    AND n.created_at > i.index_end_at AND n.created_at < '20261001'
                    AND n.created_at <= DATEADD(DAY, 30, i.index_end_at)) AS next_new_journey_at
        FROM dbo.trip_table t
        WHERE t.user_id = i.user_id AND t.created_at > i.index_end_at
            AND t.created_at < '20261001'
            AND t.created_at <= DATEADD(DAY, 30, i.index_end_at)
    ) r
)
,
eligibility AS (
    SELECT *, CASE WHEN index_end_at >= index_created_at AND index_end_at < '20261001'
        AND DATEADD(DAY, 30, index_end_at) <= '20261001' THEN 1 ELSE 0 END AS eligible_30d
    FROM index_followup
)
SELECT experience_group, COUNT(*) AS indexed_users,
    SUM(CASE WHEN index_end_at IS NULL OR index_end_at < index_created_at THEN 1 ELSE 0 END) AS excluded_open_or_invalid_end,
    SUM(CASE WHEN index_end_at >= index_created_at AND eligible_30d = 0 THEN 1 ELSE 0 END) AS excluded_incomplete_followup,
    SUM(eligible_30d) AS eligible_users,
    SUM(CASE WHEN eligible_30d = 1 AND next_new_journey_at IS NOT NULL THEN 1 ELSE 0 END) AS returned_new_journey_users,
    SUM(CASE WHEN eligible_30d = 1 AND next_request_inclusive_at IS NOT NULL THEN 1 ELSE 0 END) AS returned_inclusive_users,
    ROUND(SUM(CASE WHEN eligible_30d = 1 AND next_new_journey_at IS NOT NULL THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(SUM(eligible_30d), 0), 2) AS return_30d_pct,
    ROUND(SUM(CASE WHEN eligible_30d = 1 AND next_request_inclusive_at IS NOT NULL THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(SUM(eligible_30d), 0), 2) AS return_30d_inclusive_pct
FROM eligibility
GROUP BY experience_group
ORDER BY experience_group;
GO
-- Compare 30-day return rates by index booking experience
WITH ranked_requests AS (
    SELECT t.*, ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.created_at, t.trip_id) AS request_order
    FROM dbo.trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
),
index_request AS (
    SELECT t.user_id, t.trip_id AS index_trip_id, t.request_group_id AS index_request_group_id,
        t.created_at AS index_created_at, t.service_type,
        CASE WHEN t.status = 4 THEN t.finished_at
            WHEN t.status IN (5, 6) THEN t.cancelled_at
            WHEN t.status = 7 THEN t.expired_at END AS index_end_at,
        CASE WHEN t.status IN (5, 6) THEN 'cancelled'
            WHEN t.status = 7 THEN 'expired_no_driver'
            WHEN t.status = 4 AND DATEDIFF_BIG(SECOND, t.created_at, t.pickup_at) > 720 THEN 'completed_long_wait'
            WHEN t.status = 4 AND t.pickup_at >= t.created_at THEN 'completed_good'
            WHEN t.status = 4 THEN 'completed_unknown_wait'
            ELSE 'open_or_unknown' END AS experience_group,
        CASE WHEN u.registered_at < '20260401' THEN 'pre_period_signup'
            WHEN t.created_at < DATEADD(DAY, 30, u.registered_at) THEN 'in_period_tenure_under_30d'
            ELSE 'in_period_tenure_30d_plus' END AS tenure_group,
        (SELECT COUNT(*) FROM dbo.trip_table p
            WHERE p.user_id = t.user_id AND p.created_at >= '20260401'
                AND p.created_at >= DATEADD(DAY, -30, t.created_at)
                AND p.created_at < t.created_at) AS pre_index_requests_30d
    FROM ranked_requests t
    INNER JOIN dbo.user_table u ON t.user_id = u.user_id
    WHERE t.request_order = 1
),
index_followup AS (
    SELECT i.*, r.next_request_inclusive_at, r.next_new_journey_at
    FROM index_request i
    OUTER APPLY (
        SELECT MIN(t.created_at) AS next_request_inclusive_at,
            (SELECT MIN(n.created_at) FROM dbo.trip_table n
                WHERE n.user_id = i.user_id
                    AND n.request_group_id <> i.index_request_group_id
                    AND n.created_at > i.index_end_at AND n.created_at < '20261001'
                    AND n.created_at <= DATEADD(DAY, 30, i.index_end_at)) AS next_new_journey_at
        FROM dbo.trip_table t
        WHERE t.user_id = i.user_id AND t.created_at > i.index_end_at
            AND t.created_at < '20261001'
            AND t.created_at <= DATEADD(DAY, 30, i.index_end_at)
    ) r
)
,
comparison_population AS (
    SELECT *, CASE WHEN pre_index_requests_30d = 0 THEN '0_observed'
        WHEN pre_index_requests_30d < 5 THEN '1_4' ELSE '5_plus' END AS pre_index_frequency_group
    FROM index_followup
    WHERE index_end_at >= index_created_at AND index_end_at < '20261001'
        AND DATEADD(DAY, 30, index_end_at) <= '20261001'
),
group_rates AS (
    SELECT CASE WHEN GROUPING(service_type) = 1 THEN 'overall' ELSE 'stratified' END AS comparison_level,
        service_type, tenure_group, pre_index_frequency_group, experience_group,
        COUNT(*) AS eligible_users,
        SUM(CASE WHEN next_new_journey_at IS NOT NULL THEN 1 ELSE 0 END) AS returned_users,
        SUM(CASE WHEN next_new_journey_at IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS return_rate_pct
    FROM comparison_population
    GROUP BY GROUPING SETS ((experience_group),
        (service_type, tenure_group, pre_index_frequency_group, experience_group))
),
comparison AS (
    SELECT *, MAX(CASE WHEN experience_group = 'completed_good' THEN return_rate_pct END)
            OVER (PARTITION BY comparison_level, service_type, tenure_group, pre_index_frequency_group) AS good_return_rate_pct,
        MAX(CASE WHEN experience_group = 'completed_good' THEN eligible_users END)
            OVER (PARTITION BY comparison_level, service_type, tenure_group, pre_index_frequency_group) AS good_sample_size
    FROM group_rates
)
SELECT comparison_level, service_type, tenure_group, pre_index_frequency_group,
    experience_group, eligible_users, returned_users, good_sample_size,
    ROUND(return_rate_pct, 2) AS return_30d_pct,
    ROUND(good_return_rate_pct, 2) AS good_return_30d_pct,
    ROUND(return_rate_pct - good_return_rate_pct, 2) AS return_rate_gap_pp,
    CASE WHEN eligible_users < 30 THEN 1 ELSE 0 END AS small_sample,
    CASE WHEN good_sample_size IS NULL THEN NULL WHEN good_sample_size < 30 THEN 1 ELSE 0 END AS small_baseline_sample
FROM comparison
ORDER BY comparison_level, service_type, tenure_group, pre_index_frequency_group, experience_group;
GO
-- Test customer return rates across 7, 14, and 30 days
WITH ranked_requests AS (
    SELECT t.*, ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.created_at, t.trip_id) AS request_order
    FROM dbo.trip_table t
    WHERE t.created_at >= '20260401' AND t.created_at < '20261001'
),
index_request AS (
    SELECT t.user_id, t.trip_id AS index_trip_id, t.request_group_id AS index_request_group_id,
        t.created_at AS index_created_at, t.service_type,
        CASE WHEN t.status = 4 THEN t.finished_at
            WHEN t.status IN (5, 6) THEN t.cancelled_at
            WHEN t.status = 7 THEN t.expired_at END AS index_end_at,
        CASE WHEN t.status IN (5, 6) THEN 'cancelled'
            WHEN t.status = 7 THEN 'expired_no_driver'
            WHEN t.status = 4 AND DATEDIFF_BIG(SECOND, t.created_at, t.pickup_at) > 720 THEN 'completed_long_wait'
            WHEN t.status = 4 AND t.pickup_at >= t.created_at THEN 'completed_good'
            WHEN t.status = 4 THEN 'completed_unknown_wait'
            ELSE 'open_or_unknown' END AS experience_group,
        CASE WHEN u.registered_at < '20260401' THEN 'pre_period_signup'
            WHEN t.created_at < DATEADD(DAY, 30, u.registered_at) THEN 'in_period_tenure_under_30d'
            ELSE 'in_period_tenure_30d_plus' END AS tenure_group,
        (SELECT COUNT(*) FROM dbo.trip_table p
            WHERE p.user_id = t.user_id AND p.created_at >= '20260401'
                AND p.created_at >= DATEADD(DAY, -30, t.created_at)
                AND p.created_at < t.created_at) AS pre_index_requests_30d
    FROM ranked_requests t
    INNER JOIN dbo.user_table u ON t.user_id = u.user_id
    WHERE t.request_order = 1
),
index_followup AS (
    SELECT i.*, r.next_request_inclusive_at, r.next_new_journey_at
    FROM index_request i
    OUTER APPLY (
        SELECT MIN(t.created_at) AS next_request_inclusive_at,
            (SELECT MIN(n.created_at) FROM dbo.trip_table n
                WHERE n.user_id = i.user_id
                    AND n.request_group_id <> i.index_request_group_id
                    AND n.created_at > i.index_end_at AND n.created_at < '20261001'
                    AND n.created_at <= DATEADD(DAY, 30, i.index_end_at)) AS next_new_journey_at
        FROM dbo.trip_table t
        WHERE t.user_id = i.user_id AND t.created_at > i.index_end_at
            AND t.created_at < '20261001'
            AND t.created_at <= DATEADD(DAY, 30, i.index_end_at)
    ) r
)
,
window_population AS (
    SELECT i.*, w.window_days, p.followup_population,
        CASE WHEN i.index_end_at >= i.index_created_at AND i.index_end_at < '20261001'
            AND DATEADD(DAY, CASE WHEN p.followup_population = 'common_30d' THEN 30 ELSE w.window_days END,
                i.index_end_at) <= '20261001' THEN 1 ELSE 0 END AS eligible
    FROM index_followup i
    CROSS JOIN (VALUES (7), (14), (30)) w(window_days)
    CROSS JOIN (VALUES ('window_specific'), ('common_30d')) p(followup_population)
),
window_rates AS (
    SELECT followup_population, window_days,
        CASE WHEN GROUPING(experience_group) = 1 THEN 'all_experiences' ELSE experience_group END AS experience_group,
        COUNT(*) AS indexed_users, SUM(eligible) AS eligible_users,
        SUM(CASE WHEN eligible = 1 AND next_new_journey_at <= DATEADD(DAY, window_days, index_end_at)
            THEN 1 ELSE 0 END) AS returned_users,
        SUM(CASE WHEN eligible = 1 AND next_request_inclusive_at <= DATEADD(DAY, window_days, index_end_at)
            THEN 1 ELSE 0 END) AS returned_inclusive_users
    FROM window_population
    GROUP BY GROUPING SETS ((followup_population, window_days, experience_group),
        (followup_population, window_days))
),
window_kpi AS (
    SELECT *, returned_users * 100.0 / NULLIF(eligible_users, 0) AS return_rate_pct
    FROM window_rates
),
sensitivity AS (
    SELECT *, MAX(CASE WHEN experience_group = 'completed_good' THEN return_rate_pct END)
        OVER (PARTITION BY followup_population, window_days) AS good_return_rate_pct
    FROM window_kpi
)
SELECT followup_population, window_days, experience_group, indexed_users,
    indexed_users - eligible_users AS excluded_users, eligible_users, returned_users, returned_inclusive_users,
    ROUND(return_rate_pct, 2) AS return_rate_pct,
    ROUND(returned_inclusive_users * 100.0 / NULLIF(eligible_users, 0), 2) AS return_inclusive_pct,
    ROUND(good_return_rate_pct, 2) AS good_return_rate_pct,
    CASE WHEN experience_group <> 'all_experiences'
        THEN ROUND(return_rate_pct - good_return_rate_pct, 2) END AS return_rate_gap_pp,
    CASE WHEN eligible_users < 30 THEN 1 ELSE 0 END AS small_sample
FROM sensitivity
ORDER BY followup_population, window_days, experience_group;
GO
