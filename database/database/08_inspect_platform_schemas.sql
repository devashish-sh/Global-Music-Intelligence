
SELECT
    table_name,
    ordinal_position,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'clean'
  AND table_name IN ('spotify_chart', 'youtube_chart')
ORDER BY table_name, ordinal_position;
