
WITH chart_counts AS (

    SELECT
        'Spotify' AS platform,
        cc AS market,
        week_end AS chart_date,
        COUNT(*) AS total_rows,
        COUNT(DISTINCT
            CASE WHEN rank ~ '^[0-9]+$'
            THEN rank::INTEGER END
        ) AS unique_ranks,
        MIN(
            CASE WHEN rank ~ '^[0-9]+$'
            THEN rank::INTEGER END
        ) AS minimum_rank,
        MAX(
            CASE WHEN rank ~ '^[0-9]+$'
            THEN rank::INTEGER END
        ) AS maximum_rank,
        200 AS expected_rows
    FROM staging.spotify_chart_raw
    GROUP BY cc, week_end

    UNION ALL

    SELECT
        'YouTube',
        cc,
        week_end,
        COUNT(*),
        COUNT(DISTINCT
            CASE WHEN rank ~ '^[0-9]+$'
            THEN rank::INTEGER END
        ),
        MIN(
            CASE WHEN rank ~ '^[0-9]+$'
            THEN rank::INTEGER END
        ),
        MAX(
            CASE WHEN rank ~ '^[0-9]+$'
            THEN rank::INTEGER END
        ),
        100
    FROM staging.youtube_chart_raw
    GROUP BY cc, week_end
)

SELECT
    platform,
    COUNT(*) AS total_chart_instances,

    SUM(total_rows) AS total_records,

    COUNT(*) FILTER (
        WHERE total_rows <> expected_rows
    ) AS incomplete_or_oversized_charts,

    COUNT(*) FILTER (
        WHERE total_rows <> unique_ranks
    ) AS charts_with_duplicate_or_invalid_ranks,

    COUNT(*) FILTER (
        WHERE minimum_rank <> 1
           OR maximum_rank <> expected_rows
    ) AS charts_with_unexpected_rank_range

FROM chart_counts
GROUP BY platform
ORDER BY platform;





-- Spotify duplicate observations
SELECT
    cc AS market,
    week_end AS chart_date,
    track_id,
    COUNT(*) AS occurrences
FROM staging.spotify_chart_raw
GROUP BY cc, week_end, track_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;


-- YouTube duplicate observations
SELECT
    cc AS market,
    week_end AS chart_date,
    key AS video_id,
    COUNT(*) AS occurrences
FROM staging.youtube_chart_raw
GROUP BY cc, week_end, key
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;
