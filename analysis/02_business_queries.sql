-- =========================================================
-- GLOBAL MUSIC INTELLIGENCE
-- FINAL BUSINESS QUERY SET
-- =========================================================
-- Run after database/09_create_unified_dataset.sql.
--
-- Each query is tagged with "-- @query <key>". The dashboard
-- exporter (python/export_dashboard_data.py) parses those tags,
-- executes every query and writes dashboard/data/dashboard.json.
-- Keeping the SQL here means the SQL files stay the source of
-- truth for every number shown on the dashboard.
--
-- Rules carried over from the data preparation layer:
--   * Spotify streams and YouTube views are never added together.
--   * "Weeks on chart" always means COUNT(DISTINCT chart_date),
--     not raw rows, because every chart date appears once per
--     market (global + country charts).
--   * Chart rank is platform-specific and is never summed.
--   * Only is_usable observations are counted in business
--     analysis; the data-quality block reports the exclusions.
-- =========================================================


-- @query kpis
-- Q1. How large is the analysed chart footprint, by platform?
SELECT
    platform,
    COUNT(*)                          AS observations,
    COUNT(DISTINCT market_code)       AS markets,
    COUNT(DISTINCT chart_date)        AS chart_dates,
    COUNT(DISTINCT platform_item_id)  AS items,
    COUNT(DISTINCT platform_item_id)
        FILTER (WHERE chart_rank <= 10) AS items_with_top10,
    COUNT(*) FILTER (WHERE chart_rank <= 10) AS top10_observations,
    MIN(chart_date)                   AS first_date,
    MAX(chart_date)                   AS last_date
FROM analytics.v_unified_chart_observations
WHERE is_usable
GROUP BY platform
ORDER BY platform;


-- @query annual
-- Q2. How has chart activity moved year by year for each platform?
-- Note: average chart rank is intentionally not reported. Every chart
-- in the source is full (200 Spotify / 100 YouTube rows per market-week),
-- so the mean rank is a constant 100.5 / 50.5 and carries no information.
SELECT
    platform,
    EXTRACT(YEAR FROM chart_date)::INT AS chart_year,
    COUNT(*)                           AS observations,
    COUNT(DISTINCT platform_item_id)   AS items,
    COUNT(DISTINCT market_code)        AS markets,
    COUNT(*) FILTER (WHERE chart_rank <= 10) AS top10_observations
FROM analytics.v_unified_chart_observations
WHERE is_usable
GROUP BY platform, EXTRACT(YEAR FROM chart_date)
ORDER BY chart_year, platform;


-- @query new_items
-- Q3. How much genuinely new music reaches the charts each year?
-- A "new item" is charting for the first time in its platform's history.
WITH first_seen AS (
    SELECT
        platform,
        platform_item_id,
        MIN(chart_date) AS first_chart_date
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND platform_item_id IS NOT NULL
    GROUP BY platform, platform_item_id
)
SELECT
    platform,
    EXTRACT(YEAR FROM first_chart_date)::INT AS chart_year,
    COUNT(*)                                 AS new_items
FROM first_seen
GROUP BY platform, EXTRACT(YEAR FROM first_chart_date)
ORDER BY chart_year, platform;


-- @query weekly
-- Q4. How broad is the chart each week?
-- Counts distinct items, not rows: row counts are fixed by chart size
-- (200 Spotify / 100 YouTube per market), so only item breadth moves.
SELECT
    chart_date,
    COUNT(DISTINCT platform_item_id)
        FILTER (WHERE platform = 'Spotify') AS spotify_items,
    COUNT(DISTINCT platform_item_id)
        FILTER (WHERE platform = 'YouTube') AS youtube_items
FROM analytics.v_unified_chart_observations
WHERE is_usable
  AND platform_item_id IS NOT NULL
GROUP BY chart_date
ORDER BY chart_date;


-- @query seasonality
-- Q5. Is there a recurring seasonal pattern in chart breadth?
-- Averaged over chart dates first, so that unequal market coverage and
-- the number of observed weeks in a month cannot create a false trend.
WITH per_date AS (
    SELECT
        platform,
        chart_date,
        EXTRACT(YEAR FROM chart_date)::INT  AS chart_year,
        EXTRACT(MONTH FROM chart_date)::INT AS chart_month,
        COUNT(DISTINCT platform_item_id)    AS items
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND platform_item_id IS NOT NULL
    GROUP BY platform, chart_date
)
SELECT
    chart_year,
    chart_month,
    platform,
    ROUND(AVG(items), 1) AS avg_items,
    COUNT(*)             AS chart_dates
FROM per_date
GROUP BY chart_year, chart_month, platform
ORDER BY chart_year, chart_month, platform;


-- @query number_ones
-- Q6. Which songs own the top slot?
-- Counts market-weeks at rank 1 across every market and date.
WITH no1 AS (
    SELECT
        platform,
        platform_item_id,
        MAX(title)               AS title,
        MAX(artists)             AS artists,
        COUNT(*)                 AS no1_market_weeks,
        COUNT(DISTINCT market_code) AS markets,
        MIN(chart_date)          AS first_no1,
        MAX(chart_date)          AS last_no1
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND chart_rank = 1
      AND platform_item_id IS NOT NULL
    GROUP BY platform, platform_item_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY platform
               ORDER BY no1_market_weeks DESC
           ) AS rn
    FROM no1
)
SELECT platform, platform_item_id, title, artists, no1_market_weeks,
       markets, first_no1, last_no1
FROM ranked
WHERE rn <= 15
ORDER BY platform, rn;


-- @query number_ones_overview
-- Q6b. How often does the number-one position change hands?
WITH no1 AS (
    SELECT platform, platform_item_id, COUNT(*) AS weeks
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND chart_rank = 1
      AND platform_item_id IS NOT NULL
    GROUP BY platform, platform_item_id
)
SELECT
    platform,
    COUNT(*)          AS items,
    SUM(weeks)        AS no1_market_weeks,
    ROUND(AVG(weeks), 1) AS avg_weeks_per_item,
    MAX(weeks)        AS max_weeks
FROM no1
GROUP BY platform
ORDER BY platform;


-- @query longevity_items
-- Q7. Song-level longevity: how many chart weeks does an item get?
-- Grain: one row per platform item, feed for Q8/Q9 and the
-- Pareto concentration view.
CREATE OR REPLACE VIEW analytics.v_song_reach AS
SELECT
    u.platform,
    u.platform_item_id,
    MAX(u.title)                       AS title,
    MAX(u.artists)                     AS artists,
    COUNT(DISTINCT u.chart_date)       AS chart_weeks,
    COUNT(DISTINCT u.market_code)      AS markets,
    ROUND(AVG(u.chart_rank), 2)        AS avg_rank,
    MIN(u.chart_rank)                  AS best_rank,
    MIN(u.chart_date)                  AS first_chart_date,
    MAX(u.chart_date)                  AS last_chart_date
FROM analytics.v_unified_chart_observations u
WHERE u.is_usable
  AND u.platform_item_id IS NOT NULL
GROUP BY u.platform, u.platform_item_id;


-- @query longevity_buckets
-- Q8. How long do chart hits actually last?
SELECT
    platform,
    CASE
        WHEN chart_weeks = 1  THEN '1 week'
        WHEN chart_weeks <= 4  THEN '2-4'
        WHEN chart_weeks <= 12 THEN '5-12'
        WHEN chart_weeks <= 26 THEN '13-26'
        WHEN chart_weeks <= 52 THEN '27-52'
        ELSE '53+'
    END                     AS lifetime_band,
    COUNT(*)                AS items,
    SUM(chart_weeks)        AS total_weeks
FROM analytics.v_song_reach
GROUP BY
    platform,
    CASE
        WHEN chart_weeks = 1  THEN '1 week'
        WHEN chart_weeks <= 4  THEN '2-4'
        WHEN chart_weeks <= 12 THEN '5-12'
        WHEN chart_weeks <= 26 THEN '13-26'
        WHEN chart_weeks <= 52 THEN '27-52'
        ELSE '53+'
    END
ORDER BY platform, lifetime_band;


-- @query longevity_summary
-- Q9. What is the typical and extreme chart lifetime?
SELECT
    platform,
    COUNT(*)                AS items,
    ROUND(AVG(chart_weeks), 1) AS avg_weeks,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY chart_weeks)  AS median_weeks,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY chart_weeks)  AS p90_weeks,
    MAX(chart_weeks)        AS max_weeks,
    COUNT(*) FILTER (WHERE chart_weeks >= 26) AS items_26w,
    COUNT(*) FILTER (WHERE chart_weeks >= 52) AS items_52w
FROM analytics.v_song_reach
GROUP BY platform
ORDER BY platform;


-- @query top_songs
-- Q10. Which songs hold the longest chart presence?
WITH ranked AS (
    SELECT
        platform,
        platform_item_id,
        title,
        artists,
        chart_weeks,
        markets,
        avg_rank,
        best_rank,
        ROW_NUMBER() OVER (
            PARTITION BY platform
            ORDER BY chart_weeks DESC, best_rank ASC
        ) AS rn
    FROM analytics.v_song_reach
)
SELECT platform, platform_item_id, title, artists,
       chart_weeks, markets, avg_rank, best_rank
FROM ranked
WHERE rn <= 20
ORDER BY platform, rn;


-- @query top_global
-- Q11. Which songs lead the global chart specifically?
WITH global_items AS (
    SELECT
        platform,
        platform_item_id,
        MAX(title)                    AS title,
        MAX(artists)                  AS artists,
        COUNT(DISTINCT chart_date)    AS global_weeks,
        ROUND(AVG(chart_rank), 2)     AS avg_global_rank,
        MIN(chart_rank)               AS best_global_rank
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND market_code = 'global'
      AND platform_item_id IS NOT NULL
    GROUP BY platform, platform_item_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY platform
               ORDER BY global_weeks DESC, best_global_rank ASC
           ) AS rn
    FROM global_items
)
SELECT platform, title, artists, global_weeks,
       avg_global_rank, best_global_rank
FROM ranked
WHERE rn <= 10
ORDER BY platform, rn;


-- @query artists
-- Q12. Which artists reach the widest audience?
-- Candidate artists are pre-filtered on summed item weeks (cheap),
-- then exact distinct chart dates and markets are computed for them.
WITH item_agg AS (
    SELECT
        platform,
        platform_item_id,
        COUNT(DISTINCT chart_date) AS weeks,
        COUNT(DISTINCT market_code) AS markets,
        AVG(chart_rank) AS avg_rank,
        MIN(chart_rank) AS best_rank
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND platform_item_id IS NOT NULL
    GROUP BY platform, platform_item_id
),
artist_items AS (
    SELECT
        ta.platform_name AS platform,
        ta.artist_id,
        a.artist_name,
        i.platform_item_id,
        i.weeks
    FROM clean.track_artists ta
    JOIN clean.artists a
      ON a.artist_id = ta.artist_id
    JOIN item_agg i
      ON i.platform = ta.platform_name
     AND i.platform_item_id = ta.platform_item_id
),
candidates AS (
    SELECT platform, artist_id, artist_name, items, item_weeks
    FROM (
        SELECT
            platform,
            artist_id,
            artist_name,
            COUNT(*)   AS items,
            SUM(weeks) AS item_weeks,
            ROW_NUMBER() OVER (
                PARTITION BY platform
                ORDER BY SUM(weeks) DESC
            ) AS rn
        FROM artist_items
        GROUP BY platform, artist_id, artist_name
    ) ranked_artists
    WHERE rn <= 250
),
artist_stats AS (
    SELECT
        c.platform,
        c.artist_name,
        c.items,
        COUNT(DISTINCT u.chart_date)  AS chart_weeks,
        COUNT(DISTINCT u.market_code) AS markets,
        ROUND(AVG(u.chart_rank), 1)   AS avg_rank,
        MIN(u.chart_rank)             AS best_rank
    FROM candidates c
    JOIN clean.track_artists ta
      ON ta.artist_id = c.artist_id
     AND ta.platform_name = c.platform
    JOIN analytics.v_unified_chart_observations u
      ON u.platform = ta.platform_name
     AND u.platform_item_id = ta.platform_item_id
    WHERE u.is_usable
    GROUP BY c.platform, c.artist_name, c.items
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY platform
               ORDER BY chart_weeks DESC, markets DESC
           ) AS rn
    FROM artist_stats
)
SELECT platform, artist_name, items, chart_weeks, markets, avg_rank, best_rank
FROM ranked
WHERE rn <= 15
ORDER BY platform, rn;


-- @query markets
-- Q13. How deep is chart coverage in each market?
-- chart_dates is the honest denominator: Spotify country charts only
-- sample about 13 weeks per year, while global/TR and YouTube are weekly.
SELECT
    platform,
    market_code,
    COUNT(*)                          AS observations,
    COUNT(DISTINCT chart_date)        AS chart_dates,
    COUNT(DISTINCT platform_item_id)  AS items,
    COUNT(*) FILTER (WHERE chart_rank <= 10) AS top10_observations,
    MIN(chart_date)                   AS first_date,
    MAX(chart_date)                   AS last_date
FROM analytics.v_unified_chart_observations
WHERE is_usable
GROUP BY platform, market_code
ORDER BY platform, observations DESC;


-- @query market_leaders
-- Q14. Which song defines each market?
-- The leader is the item with the most chart weeks in that market,
-- tie-broken by its best rank there.
WITH market_items AS (
    SELECT
        platform,
        market_code,
        platform_item_id,
        MAX(title)                 AS title,
        MAX(artists)               AS artists,
        COUNT(DISTINCT chart_date) AS weeks,
        MIN(chart_rank)            AS best_rank
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND platform_item_id IS NOT NULL
    GROUP BY platform, market_code, platform_item_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY platform, market_code
               ORDER BY weeks DESC, best_rank ASC
           ) AS rn
    FROM market_items
)
SELECT platform, market_code, title, artists, weeks, best_rank
FROM ranked
WHERE rn = 1
ORDER BY platform, market_code;


-- @query cross_platform_summary
-- Q15. How much music appears on both platforms?
-- Matching is deliberately conservative: identical normalised title
-- plus identical normalised full artist credit string. This is a
-- lower bound; remixes, features and re-titles are not reconciled.
WITH sp AS (
    SELECT
        LOWER(REGEXP_REPLACE(BTRIM(title), '\s+', ' ', 'g'))   AS t,
        LOWER(REGEXP_REPLACE(BTRIM(artists), '\s+', ' ', 'g')) AS a
    FROM clean.spotify_chart
    WHERE title IS NOT NULL AND artists IS NOT NULL
    GROUP BY 1, 2
),
yt AS (
    SELECT
        LOWER(REGEXP_REPLACE(BTRIM(title), '\s+', ' ', 'g'))   AS t,
        LOWER(REGEXP_REPLACE(BTRIM(artists), '\s+', ' ', 'g')) AS a
    FROM clean.youtube_chart
    WHERE title IS NOT NULL AND artists IS NOT NULL AND is_usable
    GROUP BY 1, 2
)
SELECT
    (SELECT COUNT(*) FROM sp)  AS spotify_credits,
    (SELECT COUNT(*) FROM yt)  AS youtube_credits,
    COUNT(*)                   AS matched_credits
FROM sp
JOIN yt USING (t, a);


-- @query cross_platform_top
-- Q16. Which songs win on both platforms?
WITH sp AS (
    SELECT
        LOWER(REGEXP_REPLACE(BTRIM(title), '\s+', ' ', 'g'))   AS t,
        LOWER(REGEXP_REPLACE(BTRIM(artists), '\s+', ' ', 'g')) AS a,
        MAX(title)   AS title,
        MAX(artists) AS artists,
        COUNT(DISTINCT chart_date) AS weeks,
        MIN(chart_rank) AS best_rank
    FROM clean.spotify_chart
    WHERE title IS NOT NULL AND artists IS NOT NULL
    GROUP BY 1, 2
),
yt AS (
    SELECT
        LOWER(REGEXP_REPLACE(BTRIM(title), '\s+', ' ', 'g'))   AS t,
        LOWER(REGEXP_REPLACE(BTRIM(artists), '\s+', ' ', 'g')) AS a,
        COUNT(DISTINCT chart_date) AS weeks,
        MIN(chart_rank) AS best_rank
    FROM clean.youtube_chart
    WHERE title IS NOT NULL AND artists IS NOT NULL AND is_usable
    GROUP BY 1, 2
)
SELECT
    sp.title,
    sp.artists,
    sp.weeks  AS spotify_weeks,
    yt.weeks  AS youtube_weeks,
    sp.best_rank AS spotify_best,
    yt.best_rank AS youtube_best
FROM sp
JOIN yt USING (t, a)
ORDER BY sp.weeks + yt.weeks DESC
LIMIT 12;


-- @query entries
-- Q17. How much of Spotify chart traffic is new music?
SELECT
    EXTRACT(YEAR FROM chart_date)::INT AS chart_year,
    entry_status,
    COUNT(*) AS observations
FROM clean.spotify_chart
WHERE entry_status IS NOT NULL
GROUP BY EXTRACT(YEAR FROM chart_date), entry_status
ORDER BY chart_year, entry_status;


-- @query release_lag_buckets
-- Q18. How quickly does a release become a chart hit?
-- Measured once per item: days from release to the item's FIRST chart
-- appearance. Observation-level age would mix in catalogue longevity.
WITH first_entry AS (
    SELECT
        platform,
        platform_item_id,
        MIN(chart_date)   AS first_chart_date,
        MAX(release_date) AS release_date
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND release_date IS NOT NULL
    GROUP BY platform, platform_item_id
)
SELECT
    platform,
    CASE
        WHEN first_chart_date - release_date <= 30  THEN '0-30 days'
        WHEN first_chart_date - release_date <= 90  THEN '31-90'
        WHEN first_chart_date - release_date <= 180 THEN '91-180'
        WHEN first_chart_date - release_date <= 365 THEN '181-365'
        ELSE '1yr+'
    END     AS lag_band,
    COUNT(*) AS items
FROM first_entry
WHERE first_chart_date >= release_date
GROUP BY
    platform,
    CASE
        WHEN first_chart_date - release_date <= 30  THEN '0-30 days'
        WHEN first_chart_date - release_date <= 90  THEN '31-90'
        WHEN first_chart_date - release_date <= 180 THEN '91-180'
        WHEN first_chart_date - release_date <= 365 THEN '181-365'
        ELSE '1yr+'
    END
ORDER BY platform, lag_band;


-- @query release_lag_by_year
-- Q19. Is the gap between release and first chart appearance changing?
WITH first_entry AS (
    SELECT
        platform,
        platform_item_id,
        MIN(chart_date)   AS first_chart_date,
        MAX(release_date) AS release_date
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND release_date IS NOT NULL
    GROUP BY platform, platform_item_id
)
SELECT
    platform,
    EXTRACT(YEAR FROM first_chart_date)::INT AS chart_year,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY first_chart_date - release_date
        )
    )     AS median_days,
    COUNT(*) AS items
FROM first_entry
WHERE first_chart_date >= release_date
GROUP BY platform, EXTRACT(YEAR FROM first_chart_date)
ORDER BY platform, chart_year;


-- @query concentration
-- Q20. How concentrated is chart success?
-- Cumulative share of all chart weeks captured by the top N items.
WITH item_weeks AS (
    SELECT platform, chart_weeks AS w
    FROM analytics.v_song_reach
),
cumulative AS (
    SELECT
        platform,
        w,
        ROW_NUMBER() OVER (PARTITION BY platform ORDER BY w DESC) AS rn,
        SUM(w) OVER (
            PARTITION BY platform
            ORDER BY w DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_weeks,
        SUM(w) OVER (PARTITION BY platform) AS total_weeks,
        COUNT(*) OVER (PARTITION BY platform) AS total_items
    FROM item_weeks
)
SELECT
    platform,
    rn                        AS top_n,
    total_items,
    ROUND(100.0 * running_weeks / NULLIF(total_weeks, 0), 2)
                              AS cumulative_pct
FROM cumulative
WHERE rn IN (1, 10, 50, 100, 500, 1000, 5000, 10000)
ORDER BY platform, rn;


-- @query top_videos
-- Q21. Which YouTube videos accumulate the most views while charting?
SELECT
    platform_item_id                 AS video_id,
    MAX(title)                       AS title,
    MAX(artists)                     AS artists,
    SUM(views)                       AS total_views,
    MAX(views)                       AS peak_week_views,
    COUNT(DISTINCT chart_date)       AS chart_weeks,
    COUNT(DISTINCT market_code)      AS markets,
    MIN(chart_rank)                  AS best_rank
FROM analytics.v_unified_chart_observations
WHERE platform = 'YouTube'
  AND is_usable
  AND views IS NOT NULL
GROUP BY platform_item_id
ORDER BY total_views DESC
LIMIT 15;


-- @query views_by_rank_band
-- Q22. How steeply does viewing volume drop down the chart?
SELECT
    CASE
        WHEN chart_rank <= 10  THEN '1-10'
        WHEN chart_rank <= 25  THEN '11-25'
        WHEN chart_rank <= 50  THEN '26-50'
        ELSE '51-100'
    END     AS rank_band,
    COUNT(*) AS observations,
    ROUND(AVG(views))    AS avg_views,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY views)) AS median_views
FROM analytics.v_unified_chart_observations
WHERE platform = 'YouTube'
  AND is_usable
  AND views IS NOT NULL
GROUP BY
    CASE
        WHEN chart_rank <= 10  THEN '1-10'
        WHEN chart_rank <= 25  THEN '11-25'
        WHEN chart_rank <= 50  THEN '26-50'
        ELSE '51-100'
    END
ORDER BY rank_band;


-- @query writers
-- Q23. Who writes the charting songs?
-- Credits come from YouTube song metadata, split on the '|' delimiter.
WITH charting AS (
    SELECT DISTINCT video_id
    FROM clean.youtube_chart
    WHERE is_usable AND video_id IS NOT NULL
)
SELECT
    BTRIM(w)                       AS name,
    COUNT(DISTINCT m.video_id)     AS charting_songs
FROM clean.youtube_metadata m
JOIN charting c
  ON c.video_id = m.video_id
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(m.songwriters, '|')) AS w
WHERE m.songwriters IS NOT NULL
  AND BTRIM(w) <> ''
GROUP BY BTRIM(w)
ORDER BY charting_songs DESC
LIMIT 15;


-- @query producers
-- Q24. Who produces the charting songs?
WITH charting AS (
    SELECT DISTINCT video_id
    FROM clean.youtube_chart
    WHERE is_usable AND video_id IS NOT NULL
)
SELECT
    BTRIM(p)                       AS name,
    COUNT(DISTINCT m.video_id)     AS charting_songs
FROM clean.youtube_metadata m
JOIN charting c
  ON c.video_id = m.video_id
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(m.producers, '|')) AS p
WHERE m.producers IS NOT NULL
  AND BTRIM(p) <> ''
GROUP BY BTRIM(p)
ORDER BY charting_songs DESC
LIMIT 15;


-- @query data_quality
-- Q25. What is the quality state of the underlying data?
-- Uses the full unified view (no is_usable filter) on purpose.
SELECT
    platform,
    COUNT(*) AS observations,
    COUNT(*) FILTER (WHERE NOT is_usable) AS unusable,
    COUNT(*) FILTER (WHERE quality_flags LIKE '%future_release_date%')
        AS future_release_dates,
    COUNT(*) FILTER (WHERE quality_flags LIKE '%repeated_video_observation%')
        AS repeated_observations,
    COUNT(*) FILTER (WHERE platform_item_id IS NULL) AS missing_item_id,
    COUNT(*) FILTER (WHERE release_date IS NULL)     AS missing_release_date
FROM analytics.v_unified_chart_observations
GROUP BY platform
ORDER BY platform;
