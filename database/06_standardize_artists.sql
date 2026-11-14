
BEGIN;

-- =====================================================
-- GLOBAL MUSIC INTELLIGENCE
-- STEP 2: DATE CLEANING + ARTIST STANDARDIZATION
-- =====================================================

-- 1. INVALID RELEASE DATES
-- Preserve raw values in staging.
-- Set unreliable dates to NULL in the clean layer.

UPDATE clean.youtube_chart
SET
    quality_flags = array_append(
        COALESCE(quality_flags, ARRAY[]::TEXT[]),
        CASE
            WHEN release_date > chart_date
                THEN 'future_release_date'
            ELSE 'suspicious_historical_release_date'
        END
    ),
    release_date = NULL
WHERE release_date > chart_date
   OR release_date < DATE '1900-01-01';


UPDATE clean.spotify_chart
SET
    quality_flags = array_append(
        COALESCE(quality_flags, ARRAY[]::TEXT[]),
        CASE
            WHEN release_date > chart_date
                THEN 'future_release_date'
            ELSE 'suspicious_historical_release_date'
        END
    ),
    release_date = NULL
WHERE release_date > chart_date
   OR release_date < DATE '1900-01-01';


-- 2. PLATFORM TRACKS
-- Spotify track IDs and YouTube video IDs remain separate.

CREATE TABLE IF NOT EXISTS clean.platform_tracks (
    platform_name TEXT NOT NULL,
    platform_item_id TEXT NOT NULL,
    source_title TEXT,
    source_release_date DATE,
    PRIMARY KEY (platform_name, platform_item_id)
);


-- 3. STANDARDIZED ARTIST MASTER

CREATE TABLE IF NOT EXISTS clean.artists (
    artist_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    artist_name TEXT NOT NULL,
    normalized_name TEXT NOT NULL UNIQUE
);


-- 4. TRACK-TO-ARTIST RELATIONSHIP

CREATE TABLE IF NOT EXISTS clean.track_artists (
    platform_name TEXT NOT NULL,
    platform_item_id TEXT NOT NULL,
    artist_id BIGINT NOT NULL REFERENCES clean.artists(artist_id),
    artist_order INTEGER,

    PRIMARY KEY (
        platform_name,
        platform_item_id,
        artist_id
    ),

    FOREIGN KEY (platform_name, platform_item_id)
        REFERENCES clean.platform_tracks(
            platform_name,
            platform_item_id
        )
);


-- 5. LOAD SPOTIFY TRACKS

INSERT INTO clean.platform_tracks (
    platform_name,
    platform_item_id,
    source_title,
    source_release_date
)
SELECT
    'Spotify',
    track_id,
    MIN(title),
    MIN(release_date)
FROM clean.spotify_chart
WHERE track_id IS NOT NULL
GROUP BY track_id
ON CONFLICT (platform_name, platform_item_id)
DO NOTHING;


-- 6. LOAD YOUTUBE VIDEOS

INSERT INTO clean.platform_tracks (
    platform_name,
    platform_item_id,
    source_title,
    source_release_date
)
SELECT
    'YouTube',
    video_id,
    MIN(title),
    MIN(release_date)
FROM clean.youtube_chart
WHERE video_id IS NOT NULL
GROUP BY video_id
ON CONFLICT (platform_name, platform_item_id)
DO NOTHING;


-- 7. EXTRACT ARTIST NAMES FROM BOTH PLATFORMS

WITH source_artists AS (

    SELECT
        'Spotify' AS platform_name,
        track_id AS platform_item_id,
        artist_name,
        artist_order::INTEGER
    FROM clean.spotify_chart s
    CROSS JOIN LATERAL
        UNNEST(STRING_TO_ARRAY(s.artists, '|'))
        WITH ORDINALITY AS a(artist_name, artist_order)
    WHERE s.track_id IS NOT NULL
      AND s.artists IS NOT NULL

    UNION ALL

    SELECT
        'YouTube',
        video_id,
        artist_name,
        artist_order::INTEGER
    FROM clean.youtube_chart y
    CROSS JOIN LATERAL
        UNNEST(STRING_TO_ARRAY(y.artists, '|'))
        WITH ORDINALITY AS a(artist_name, artist_order)
    WHERE y.video_id IS NOT NULL
      AND y.artists IS NOT NULL
),

normalized AS (
    SELECT
        LOWER(
            REGEXP_REPLACE(
                BTRIM(artist_name),
                '\s+',
                ' ',
                'g'
            )
        ) AS normalized_name,

        MIN(BTRIM(artist_name)) AS artist_name

    FROM source_artists
    WHERE BTRIM(artist_name) <> ''
    GROUP BY 1
)

INSERT INTO clean.artists (
    artist_name,
    normalized_name
)
SELECT artist_name, normalized_name
FROM normalized
ON CONFLICT (normalized_name)
DO NOTHING;


-- 8. CONNECT ARTISTS TO PLATFORM TRACKS

WITH source_artists AS (

    SELECT
        'Spotify' AS platform_name,
        track_id AS platform_item_id,
        artist_name,
        artist_order::INTEGER
    FROM clean.spotify_chart s
    CROSS JOIN LATERAL
        UNNEST(STRING_TO_ARRAY(s.artists, '|'))
        WITH ORDINALITY AS a(artist_name, artist_order)
    WHERE s.track_id IS NOT NULL
      AND s.artists IS NOT NULL

    UNION ALL

    SELECT
        'YouTube',
        video_id,
        artist_name,
        artist_order::INTEGER
    FROM clean.youtube_chart y
    CROSS JOIN LATERAL
        UNNEST(STRING_TO_ARRAY(y.artists, '|'))
        WITH ORDINALITY AS a(artist_name, artist_order)
    WHERE y.video_id IS NOT NULL
      AND y.artists IS NOT NULL
),

normalized AS (
    SELECT
        platform_name,
        platform_item_id,

        LOWER(
            REGEXP_REPLACE(
                BTRIM(artist_name),
                '\s+',
                ' ',
                'g'
            )
        ) AS normalized_name,

        MIN(artist_order) AS artist_order

    FROM source_artists
    WHERE BTRIM(artist_name) <> ''
    GROUP BY 1, 2, 3
)

INSERT INTO clean.track_artists (
    platform_name,
    platform_item_id,
    artist_id,
    artist_order
)
SELECT
    n.platform_name,
    n.platform_item_id,
    a.artist_id,
    n.artist_order
FROM normalized n
JOIN clean.artists a
    ON a.normalized_name = n.normalized_name
ON CONFLICT (
    platform_name,
    platform_item_id,
    artist_id
)
DO NOTHING;


COMMIT;


-- =====================================================
-- OUTPUT: STANDARDIZATION SUMMARY
-- =====================================================

SELECT
    'Platform tracks' AS output,
    COUNT(*) AS total_records
FROM clean.platform_tracks

UNION ALL

SELECT
    'Unique artists',
    COUNT(*)
FROM clean.artists

UNION ALL

SELECT
    'Track-artist relationships',
    COUNT(*)
FROM clean.track_artists;




SELECT
    pt.platform_name,
    pt.source_title,
    a.artist_name,
    ta.artist_order
FROM clean.track_artists ta
JOIN clean.platform_tracks pt
    ON pt.platform_name = ta.platform_name
   AND pt.platform_item_id = ta.platform_item_id
JOIN clean.artists a
    ON a.artist_id = ta.artist_id
ORDER BY pt.platform_name, pt.source_title
LIMIT 30;
