SELECT event_name, event_date, user_pseudo_id
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20201201`
LIMIT 10;

-- Q1 - Where do users drop off in the conversion funnel?
-- Goal: Map the funnel: session_start -> view_item -> add_to_cart -> begin_checkout -> purchase. Compute unique-user and unique-session counts at each stage. Find the key drop-off stage

WITH funnel_events AS (
  SELECT
    event_name,
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN (
      'session_start',
      'view_item',
      'add_to_cart',
      'begin_checkout',
      'purchase'
    )
),
funnel_counts AS (
  SELECT
    CASE event_name
      WHEN 'session_start'   THEN 1
      WHEN 'view_item'       THEN 2
      WHEN 'add_to_cart'     THEN 3
      WHEN 'begin_checkout'  THEN 4
      WHEN 'purchase'        THEN 5
    END AS funnel_step,
    event_name,
    COUNT(DISTINCT user_pseudo_id) AS unique_users,
    COUNT(DISTINCT ga_session_id)  AS unique_sessions
  FROM funnel_events
  GROUP BY event_name    
)
SELECT
  funnel_step,
  event_name,
  unique_users,
  -- Step-by-step: this row's users / previous row's users
  ROUND(unique_users * 100.0 / LAG(unique_users) OVER (ORDER BY funnel_step), 2)
    AS step_conversion_pct,
  -- Cumulative: this row's users / first row's users
  ROUND(unique_users * 100.0 / FIRST_VALUE(unique_users) OVER (ORDER BY funnel_step), 2)
    AS cumulative_conversion_pct
FROM funnel_counts
ORDER BY funnel_step;
-- SUMMARY: Of 267,116 users who started a session, only 22.9% viewed a product and 1.65% completed a purchase
-- The biggest leak is the session_start -> view_item transition (top-of-funnel engagement)
-- Once users add an item to cart, the rest of the funnel is comparatively healthy (77% to begin checkout, 45% to purchase)


-- Q2 - Which acquisition channel converts best?
-- Goal: Group sessions by GA4 default channel grouping (Direct, Organic Search, etc.).
-- Compute sessions, users, purchasers, and conversion rate per channel.
-- Test whether the top two channels' conversion rates are statistically different.

WITH sessions_with_channel AS (
  SELECT
    -- Map GA4 medium/source pairs to standard channel groupings
    CASE
      WHEN traffic_source.medium = '(none)' AND traffic_source.source = '(direct)' THEN 'Direct'
      WHEN traffic_source.medium = 'organic'                                       THEN 'Organic Search'
      WHEN traffic_source.medium = 'cpc'                                           THEN 'Paid Search'
      WHEN traffic_source.medium = 'referral'                                      THEN 'Referral'
      WHEN traffic_source.medium = '<Other>'                                       THEN 'Unassigned'
      ELSE 'Other'
    END AS channel_group,
    event_name,
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND traffic_source.medium != '(data deleted)'    -- GA4 placeholder for redacted user data
    AND traffic_source.source != '(data deleted)'
),
channel_metrics AS (
  SELECT
    channel_group,
    COUNT(DISTINCT user_pseudo_id) AS unique_users,
    COUNT(DISTINCT ga_session_id)  AS total_sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN ga_session_id END)
      AS purchasing_sessions
  FROM sessions_with_channel
  GROUP BY channel_group
)
SELECT
  channel_group,
  unique_users,
  total_sessions,
  purchasing_sessions,
  ROUND(purchasing_sessions * 100.0 / total_sessions, 2) AS conversion_rate_pct
FROM channel_metrics
WHERE total_sessions >= 100   -- exclude tiny channels where the rate is unstable
ORDER BY total_sessions DESC;

-- SUMMARY: Direct traffic converts slightly better than Organic Search (1.30% vs 1.12%).
-- That's a 0.18pp difference, or about 16% higher.
-- The difference is small but statistically reliable (z = -3.64, p < 0.001) because the
-- sample size is large (~194K sessions).


-- Q3 - Cohort retention: do users come back?
-- Goal: Define each user's cohort as the week of their first session. For each later week, calculate what share of the cohort's users came back. 
-- The output is a retention table showing how many users from each cohort were still active in week 1, week 2, week 3, and so on.

WITH users_first_event_date AS (
  SELECT
    user_pseudo_id,
    --Finding first event date per user, and converting event date into cohort week
    DATE_TRUNC(PARSE_DATE('%Y%m%d', MIN(event_date)), WEEK) AS cohort_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY user_pseudo_id
),
event_week_metrics AS (
  SELECT
    wm.user_pseudo_id,
    fd.cohort_week,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', wm.event_date), WEEK) AS event_week,  -- temp for sanity check
    DATE_DIFF(DATE_TRUNC(PARSE_DATE('%Y%m%d', wm.event_date), WEEK), fd.cohort_week, WEEK
    ) AS week_offset
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` wm
  JOIN users_first_event_date fd ON wm.user_pseudo_id = fd.user_pseudo_id
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
active_users_per_cohort_offset AS (
  SELECT
    cohort_week,
    week_offset,
    COUNT(DISTINCT user_pseudo_id) AS active_users
  FROM event_week_metrics
  GROUP BY cohort_week, week_offset
),
cohort_size_per_cohort AS (
  SELECT 
    cohort_week,
    active_users AS cohort_size
  FROM active_users_per_cohort_offset
  WHERE week_offset = 0
)

SELECT 
  au.cohort_week,
  au.week_offset,
  au.active_users,
  cs.cohort_size,
  ROUND(au.active_users * 100.0 / cs.cohort_size, 2) AS retention_pct
FROM cohort_size_per_cohort cs
JOIN active_users_per_cohort_offset au ON cs.cohort_week = au.cohort_week
ORDER BY au.cohort_week, au.week_offset;
-- SUMMARY: Average Week 1 retention is ~4% across all cohorts, but the
-- pattern isn't uniform — November cohorts retain at ~6%, then retention
-- nearly halves to ~3% from December onward. Most users never return after
-- their first visit; from Week 4 onward, retention settles at well under 1%.
-- The November-to-December drop is consistent across multiple weekly cohorts
-- and worth flagging for further investigation (holiday-shopping effect?
-- marketing-driven traffic with lower intent?)


-- Q4 - Mobile vs desktop conversion difference
-- Goal: Group sessions by device.category. Compute sessions, users, purchasers, conversion rate, and average revenue per purchase per device type. Test whether device type is independent of conversion

WITH sessions_with_device AS (
  SELECT
    device.category AS device_type,
    event_name,
    user_pseudo_id,
      (SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS purchase_revenue
    FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
device_category_metrics AS (
  SELECT
    device_type,
    COUNT(DISTINCT user_pseudo_id) AS unique_users,
    COUNT(DISTINCT ga_session_id)  AS total_sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN ga_session_id END)
      AS purchasing_sessions,
    ROUND(SUM(purchase_revenue), 2) AS total_purchase_revenue
  FROM sessions_with_device
  GROUP BY device_type
)
SELECT
  device_type,
  unique_users,
  total_sessions,
  purchasing_sessions,
  ROUND(purchasing_sessions * 100.0 / total_sessions, 2) AS conversion_rate_pct,
  total_purchase_revenue,
  ROUND(total_purchase_revenue / NULLIF(purchasing_sessions, 0), 2) AS avg_revenue_per_purchase
FROM device_category_metrics
ORDER BY total_sessions DESC;
-- SUMMARY: Mobile leads conversion at 1.41% vs desktop 1.34% and tablet 1.30%, but the differences are not statistically significant (chi-square p = 0.18).
-- Desktop drives the highest average purchase value ($75.96), while mobile drives more frequent but smaller purchases ($73.57), 
-- the classic mobile vs desktop pattern of higher frequency at lower per-transaction value.



-- KPI metrics

-- Total sessions, total unique users, purchasing sessions and avg revenue per purchase
WITH event_data AS (
  SELECT
    event_name,
    user_pseudo_id,
      (SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS purchase_revenue
    FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
aggregates AS (
  SELECT
    COUNT(DISTINCT user_pseudo_id) AS unique_users,
    COUNT(DISTINCT ga_session_id)  AS total_sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN ga_session_id END)
      AS purchasing_sessions,
    ROUND(SUM(purchase_revenue), 2) AS total_purchase_revenue
  FROM event_data
)
SELECT
  unique_users,
  total_sessions,
  purchasing_sessions,
  total_purchase_revenue,
  ROUND(total_purchase_revenue / NULLIF(purchasing_sessions, 0), 2) AS avg_revenue_per_purchase
FROM aggregates;
-- SUMMARY: ~355K sessions from ~268K unique users over the 3-month window
-- produced ~4.8K purchases at an average of ~$74 per purchase, for total
-- wholesale revenue of ~$362K