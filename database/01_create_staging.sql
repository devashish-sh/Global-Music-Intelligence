
CREATE SCHEMA IF NOT EXISTS staging;

-- Spotify weekly chart source
CREATE TABLE IF NOT EXISTS staging.spotify_chart_raw (
    cc TEXT,
    week_end TEXT,
    rank TEXT,
    prev_rank TEXT,
    peak TEXT,
    appearances TEXT,
    streams TEXT,
    entry_status TEXT,
    track_id TEXT,
    title TEXT,
    artists TEXT,
    artist_uris TEXT,
    release_date TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- YouTube weekly chart source
CREATE TABLE IF NOT EXISTS staging.youtube_chart_raw (
    cc TEXT,
    week_end TEXT,
    rank TEXT,
    prev_rank TEXT,
    weeks_on_chart TEXT,
    views TEXT,
    key TEXT,
    title TEXT,
    artists TEXT,
    release_date TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- YouTube additional metadata
CREATE TABLE IF NOT EXISTS staging.youtube_metadata_raw (
    key TEXT,
    title TEXT,
    artists TEXT,
    artist_ids TEXT,
    release_date TEXT,
    songwriters TEXT,
    producers TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
