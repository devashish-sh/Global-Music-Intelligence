
-- =========================================================
-- GLOBAL MUSIC INTELLIGENCE
-- STEP 4: UNIFIED ANALYTICAL DATASET
-- =========================================================

-- Create a dedicated schema for analytical objects.
CREATE SCHEMA IF NOT EXISTS analytics;


-- Combine Spotify and YouTube observations.
-- UNION ALL preserves every source observation.
-- Platform-specific metrics remain separate.

CREATE OR REPLACE VIEW analytics.v_unified_chart_observations AS

-- SPOTIFY
SELECT
    source_row_id,
    'Spotify'::TEXT AS platform,
    market_code,
    chart_date,
    chart_rank,
    previous_rank,

    appearances,
    NULL::INTEGER AS weeks_on_chart,

    streams,
    NULL::BIGINT AS views,

    'streams'::TEXT AS metric_type,
    track_id AS platform_item_id,

    title,
    artists,
    release_date,
    source_file,

    TRUE AS is_usable,
    quality_flags::TEXT AS quality_flags

FROM clean.spotify_chart

UNION ALL

-- YOUTUBE
SELECT
    source_row_id,
    'YouTube'::TEXT AS platform,
    market_code,
    chart_date,
    chart_rank,
    previous_rank,

    NULL::INTEGER AS appearances,
    weeks_on_chart,

    NULL::BIGINT AS streams,
    views,

    'views'::TEXT AS metric_type,
    video_id AS platform_item_id,

    title,
    artists,
    release_date,
    source_file,

    is_usable,
    quality_flags::TEXT AS quality_flags

FROM clean.youtube_chart;


-- =========================================================
-- VALIDATION 1: TOTAL RECORDS BY PLATFORM
-- =========================================================

SELECT
    platform,
    COUNT(*) AS total_observations,
    COUNT(*) FILTER (
        WHERE is_usable
    ) AS usable_observations,
    COUNT(*) FILTER (
        WHERE NOT is_usable
    ) AS unusable_observations
FROM analytics.v_unified_chart_observations
GROUP BY platform
ORDER BY platform;


-- =========================================================
-- VALIDATION 2: TOTAL RECORDS
-- =========================================================

SELECT
    (SELECT COUNT(*) FROM clean.spotify_chart)
    +
    (SELECT COUNT(*) FROM clean.youtube_chart)
        AS expected_records,

    (SELECT COUNT(*)
     FROM analytics.v_unified_chart_observations)
        AS unified_records;


-- =========================================================
-- VALIDATION 3: METRIC SEPARATION
-- =========================================================

SELECT
    platform,
    metric_type,
    COUNT(*) AS observations,
    COUNT(streams) AS records_with_streams,
    COUNT(views) AS records_with_views
FROM analytics.v_unified_chart_observations
GROUP BY platform, metric_type
ORDER BY platform;


-- =========================================================
-- VALIDATION 4: MARKET COVERAGE
-- =========================================================

SELECT
    platform,
    COUNT(DISTINCT market_code) AS markets,
    MIN(chart_date) AS first_chart_date,
    MAX(chart_date) AS last_chart_date,
    COUNT(DISTINCT chart_date) AS chart_dates
FROM analytics.v_unified_chart_observations
GROUP BY platform
ORDER BY platform;
