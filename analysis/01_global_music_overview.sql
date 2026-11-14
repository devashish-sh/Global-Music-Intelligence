-- GLOBAL MUSIC INTELLIGENCE
-- Initial business analysis queries
-- Run after database/09_create_unified_dataset.sql.
-- Spotify streams and YouTube views are deliberately kept separate.

-- 1. Executive KPI by platform
SELECT
    platform,
    COUNT(*) AS chart_observations,
    COUNT(DISTINCT market_code) AS markets,
    COUNT(DISTINCT chart_date) AS chart_dates,
    COUNT(DISTINCT platform_item_id) AS distinct_platform_items,
    ROUND(AVG(chart_rank), 2) AS average_chart_rank
FROM analytics.v_unified_chart_observations
WHERE is_usable
GROUP BY platform
ORDER BY platform;

-- 2. Annual chart activity by platform
SELECT
    platform,
    EXTRACT(YEAR FROM chart_date)::INT AS chart_year,
    COUNT(*) AS chart_observations,
    COUNT(DISTINCT platform_item_id) AS distinct_items,
    ROUND(AVG(chart_rank), 2) AS average_chart_rank
FROM analytics.v_unified_chart_observations
WHERE is_usable
GROUP BY platform, EXTRACT(YEAR FROM chart_date)
ORDER BY chart_year, platform;

-- 3. Top markets by chart coverage (not a popularity ranking)
SELECT
    platform,
    market_code,
    COUNT(*) AS chart_observations,
    COUNT(DISTINCT chart_date) AS observed_chart_dates,
    COUNT(DISTINCT platform_item_id) AS distinct_items
FROM analytics.v_unified_chart_observations
WHERE is_usable
GROUP BY platform, market_code
ORDER BY platform, chart_observations DESC;

-- 4. Most persistent songs/videos within each platform.
-- Count distinct chart dates rather than raw rows across markets.
SELECT
    platform,
    platform_item_id,
    MAX(title) AS title,
    MAX(artists) AS artists,
    COUNT(DISTINCT chart_date) AS chart_weeks_observed,
    COUNT(DISTINCT market_code) AS markets_present,
    ROUND(AVG(chart_rank), 2) AS average_rank,
    MIN(chart_rank) AS best_rank
FROM analytics.v_unified_chart_observations
WHERE is_usable
  AND platform_item_id IS NOT NULL
GROUP BY platform, platform_item_id
ORDER BY platform, chart_weeks_observed DESC, best_rank ASC;

-- 5. Artist reach using normalized track-artist relationships.
-- Results are platform-specific; this counts distinct chart dates
-- and markets for each artist's platform items.
SELECT
    ta.platform_name AS platform,
    a.artist_name,
    COUNT(DISTINCT u.chart_date) AS chart_weeks_observed,
    COUNT(DISTINCT u.market_code) AS markets_reached,
    COUNT(DISTINCT u.platform_item_id) AS distinct_items,
    ROUND(AVG(u.chart_rank), 2) AS average_rank
FROM clean.track_artists ta
JOIN clean.artists a
  ON a.artist_id = ta.artist_id
JOIN analytics.v_unified_chart_observations u
  ON u.platform = ta.platform_name
 AND u.platform_item_id = ta.platform_item_id
WHERE u.is_usable
GROUP BY ta.platform_name, a.artist_id, a.artist_name
ORDER BY platform, chart_weeks_observed DESC, markets_reached DESC;

-- 6. Top songs by chart presence in the global chart only.
-- Avoids mixing global and country observations.
SELECT
    platform,
    platform_item_id,
    MAX(title) AS title,
    MAX(artists) AS artists,
    COUNT(DISTINCT chart_date) AS global_chart_weeks,
    ROUND(AVG(chart_rank), 2) AS average_global_rank,
    MIN(chart_rank) AS best_global_rank
FROM analytics.v_unified_chart_observations
WHERE is_usable
  AND market_code = 'global'
  AND platform_item_id IS NOT NULL
GROUP BY platform, platform_item_id
ORDER BY platform, global_chart_weeks DESC, best_global_rank
LIMIT 100;
