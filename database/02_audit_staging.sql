SELECT 'Spotify Charts' AS source,
       COUNT(*) AS total_records
FROM staging.spotify_chart_raw
UNION ALL
SELECT 'YouTube Charts',
       COUNT(*)
FROM staging.youtube_chart_raw
UNION ALL
SELECT 'YouTube Metadata',
       COUNT(*)
FROM staging.youtube_metadata_raw;


SELECT source_file,
       COUNT(*) AS total_records
FROM staging.spotify_chart_raw
GROUP BY source_file
UNION ALL
SELECT source_file,
       COUNT(*)
FROM staging.youtube_chart_raw
GROUP BY source_file
UNION ALL
SELECT source_file,
       COUNT(*)
FROM staging.youtube_metadata_raw
GROUP BY source_file
ORDER BY source_file;


SELECT 'Spotify' AS platform,
       cc AS market,
       week_end AS chart_date,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT rank) AS unique_ranks,
       MIN(rank::INTEGER) AS minimum_rank,
       MAX(rank::INTEGER) AS maximum_rank
FROM staging.spotify_chart_raw
GROUP BY cc,
         week_end
UNION ALL
SELECT 'YouTube',
       cc,
       week_end,
       COUNT(*),
       COUNT(DISTINCT rank),
       MIN(rank::INTEGER),
       MAX(rank::INTEGER)
FROM staging.youtube_chart_raw
GROUP BY cc,
         week_end;


SELECT COUNT(*) AS total_records,
       COUNT(DISTINCT key) AS unique_video_ids,
       COUNT(*) - COUNT(DISTINCT key) AS duplicate_video_ids,
       COUNT(*) FILTER (
                        WHERE title IS NULL) AS missing_titles,
       COUNT(*) FILTER (
                        WHERE artists IS NULL) AS missing_artists,
       COUNT(*) FILTER (
                        WHERE artist_ids IS NULL) AS missing_artist_ids,
       COUNT(*) FILTER (
                        WHERE songwriters IS NULL) AS missing_songwriters,
       COUNT(*) FILTER (
                        WHERE producers IS NULL) AS missing_producers
FROM staging.youtube_metadata_raw;
