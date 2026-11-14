
-- =====================================================
-- GLOBAL MUSIC INTELLIGENCE
-- STEP 3: YOUTUBE METADATA ENRICHMENT
-- =====================================================

-- 1. Create an enriched view.
-- LEFT JOIN preserves chart records even when metadata
-- is unavailable for a particular video.

CREATE OR REPLACE VIEW clean.v_youtube_enriched AS
SELECT
    y.source_row_id,
    y.market_code,
    y.chart_date,
    y.chart_rank,
    y.previous_rank,
    y.weeks_on_chart,
    y.views,
    y.video_id,

    y.title AS chart_title,
    y.artists AS chart_artists,
    y.release_date AS chart_release_date,

    m.title AS metadata_title,
    m.artists AS metadata_artists,
    m.artist_ids,
    m.release_date AS metadata_release_date,
    m.songwriters,
    m.producers,

    y.source_file AS chart_source_file,
    m.source_file AS metadata_source_file,

    y.is_usable,
    y.quality_flags,

    CASE
        WHEN m.video_id IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS metadata_matched

FROM clean.youtube_chart y

LEFT JOIN clean.youtube_metadata m
    ON y.video_id = m.video_id;


-- 2. Metadata matching summary

SELECT
    COUNT(*) AS total_chart_observations,

    COUNT(*) FILTER (
        WHERE metadata_matched
    ) AS matched_observations,

    COUNT(*) FILTER (
        WHERE NOT metadata_matched
    ) AS unmatched_observations,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE metadata_matched
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS match_percentage

FROM clean.v_youtube_enriched;


-- 3. Metadata coverage

SELECT
    COUNT(DISTINCT video_id) AS unique_chart_videos,

    COUNT(DISTINCT video_id) FILTER (
        WHERE metadata_matched
    ) AS videos_with_metadata,

    COUNT(DISTINCT video_id) FILTER (
        WHERE NOT metadata_matched
    ) AS videos_without_metadata

FROM clean.v_youtube_enriched;


-- 4. Check whether the view duplicated observations

SELECT
    (SELECT COUNT(*)
     FROM clean.youtube_chart) AS original_chart_records,

    (SELECT COUNT(*)
     FROM clean.v_youtube_enriched) AS enriched_chart_records;
