SELECT CASE
           WHEN key IS NULL THEN 'Missing'
           WHEN TRIM(key) = '' THEN 'Blank'
           WHEN key = 'T:' THEN 'T: placeholder'
           ELSE 'Other'
       END AS identifier_type,
       COUNT(*) AS total_records
FROM staging.youtube_chart_raw
GROUP BY 1
ORDER BY total_records DESC;


SELECT cc AS market,
       week_end AS chart_date,
       rank,
       key,
       title,
       artists,
       views,
       source_file
FROM staging.youtube_chart_raw
WHERE key = 'T:'
ORDER BY cc,
         week_end
LIMIT 30;


SELECT cc AS market,
       week_end AS chart_date,
       key,
       COUNT(*) AS occurrences,
       COUNT(DISTINCT title) AS distinct_titles,
       STRING_AGG(DISTINCT title, ' | ') AS titles
FROM staging.youtube_chart_raw
WHERE key IS NOT NULL
GROUP BY cc,
         week_end,
         key
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 30;


SELECT cc AS market,
       week_end AS chart_date,
       rank,
       COUNT(*) AS records_at_rank,
       STRING_AGG(title, ' | ') AS titles
FROM staging.youtube_chart_raw
GROUP BY cc,
         week_end,
         rank
HAVING COUNT(*) > 1
ORDER BY records_at_rank DESC
LIMIT 30;


SELECT cc AS market,
       week_end AS chart_date,
       key AS video_id,
              COUNT(*) AS occurrences,
              COUNT(DISTINCT rank) AS different_ranks,
              COUNT(DISTINCT title) AS different_titles,
              STRING_AGG(DISTINCT rank, ', ') AS ranks,
              STRING_AGG(DISTINCT title, ' | ') AS titles
FROM staging.youtube_chart_raw
WHERE key IS NOT NULL
  AND key <> 'T:'
GROUP BY cc,
         week_end,
         key
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 30;


SELECT cc AS market,
       week_end AS chart_date,
       rank,
       COUNT(*) AS records_at_rank,
       COUNT(DISTINCT key) AS distinct_video_ids,
       STRING_AGG(DISTINCT title, ' | ') AS titles
FROM staging.youtube_chart_raw
GROUP BY cc,
         week_end,
         rank
HAVING COUNT(*) > 1
ORDER BY records_at_rank DESC
LIMIT 30;


SELECT COUNT(*) AS total_records,
       COUNT(*) FILTER (
                        WHERE key = 'T:') AS placeholder_ids,
       COUNT(*) FILTER (
                        WHERE key IS NULL
                          OR TRIM(key) = '') AS missing_ids,
       COUNT(*) FILTER (
                        WHERE title IS NULL) AS missing_titles,
       COUNT(*) FILTER (
                        WHERE artists IS NULL) AS missing_artists,
       COUNT(*) FILTER (
                        WHERE views IS NULL) AS missing_views
FROM staging.youtube_chart_raw;
