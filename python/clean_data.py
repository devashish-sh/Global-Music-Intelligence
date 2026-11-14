
from pathlib import Path
import os

import psycopg
from dotenv import load_dotenv


# =====================================================
# GLOBAL MUSIC INTELLIGENCE
# DATA CLEANING PIPELINE
# =====================================================

ROOT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(ROOT_DIR / ".env")

DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
}


def execute(cursor, sql):
    cursor.execute(sql)


def create_clean_schema(cursor):

    execute(cursor, "CREATE SCHEMA IF NOT EXISTS clean;")

    # Add stable source identifiers for traceability.
    execute(cursor, """
        ALTER TABLE staging.spotify_chart_raw
        ADD COLUMN IF NOT EXISTS source_row_id
        BIGINT GENERATED ALWAYS AS IDENTITY;
    """)

    execute(cursor, """
        ALTER TABLE staging.youtube_chart_raw
        ADD COLUMN IF NOT EXISTS source_row_id
        BIGINT GENERATED ALWAYS AS IDENTITY;
    """)

    execute(cursor, """
        ALTER TABLE staging.youtube_metadata_raw
        ADD COLUMN IF NOT EXISTS source_row_id
        BIGINT GENERATED ALWAYS AS IDENTITY;
    """)


def create_clean_tables(cursor):

    execute(cursor, """
        CREATE TABLE IF NOT EXISTS clean.spotify_chart (
            source_row_id BIGINT PRIMARY KEY,
            market_code TEXT,
            chart_date DATE,
            chart_rank INTEGER,
            previous_rank INTEGER,
            peak_rank INTEGER,
            appearances INTEGER,
            streams BIGINT,
            entry_status TEXT,
            track_id TEXT,
            title TEXT,
            artists TEXT,
            artist_uris TEXT,
            release_date DATE,
            source_file TEXT,
            quality_flags TEXT[]
        );
    """)

    execute(cursor, """
        CREATE TABLE IF NOT EXISTS clean.youtube_chart (
            source_row_id BIGINT PRIMARY KEY,
            market_code TEXT,
            chart_date DATE,
            chart_rank INTEGER,
            previous_rank INTEGER,
            weeks_on_chart INTEGER,
            views BIGINT,
            video_id TEXT,
            title TEXT,
            artists TEXT,
            release_date DATE,
            source_file TEXT,
            duplicate_occurrences INTEGER,
            is_usable BOOLEAN,
            quality_flags TEXT[]
        );
    """)

    execute(cursor, """
        CREATE TABLE IF NOT EXISTS clean.youtube_metadata (
            source_row_id BIGINT PRIMARY KEY,
            video_id TEXT,
            title TEXT,
            artists TEXT,
            artist_ids TEXT,
            release_date DATE,
            songwriters TEXT,
            producers TEXT,
            source_file TEXT
        );
    """)


def clean_spotify(cursor):

    execute(cursor, "TRUNCATE clean.spotify_chart;")

    execute(cursor, """
        INSERT INTO clean.spotify_chart (
            source_row_id, market_code, chart_date, chart_rank,
            previous_rank, peak_rank, appearances, streams,
            entry_status, track_id, title, artists, artist_uris,
            release_date, source_file, quality_flags
        )
        SELECT
            source_row_id,
            NULLIF(BTRIM(cc), ''),
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(week_end), ''), 'date'
                )
                THEN NULLIF(BTRIM(week_end), '')::DATE
            END,
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(rank), ''), 'integer'
                )
                THEN NULLIF(BTRIM(rank), '')::INTEGER
            END,
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(prev_rank), ''), 'integer'
                )
                THEN NULLIF(BTRIM(prev_rank), '')::INTEGER
            END,
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(peak), ''), 'integer'
                )
                THEN NULLIF(BTRIM(peak), '')::INTEGER
            END,
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(appearances), ''), 'integer'
                )
                THEN NULLIF(BTRIM(appearances), '')::INTEGER
            END,
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(streams), ''), 'bigint'
                )
                THEN NULLIF(BTRIM(streams), '')::BIGINT
            END,
            NULLIF(BTRIM(entry_status), ''),
            NULLIF(BTRIM(track_id), ''),
            NULLIF(BTRIM(title), ''),
            NULLIF(BTRIM(artists), ''),
            NULLIF(BTRIM(artist_uris), ''),
            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(release_date), ''), 'date'
                )
                THEN NULLIF(BTRIM(release_date), '')::DATE
            END,
            source_file,
            ARRAY_REMOVE(ARRAY[
                CASE WHEN NULLIF(BTRIM(week_end), '') IS NULL
                    THEN 'missing_chart_date' END,
                CASE WHEN NULLIF(BTRIM(rank), '') IS NULL
                    THEN 'missing_rank' END,
                CASE WHEN NULLIF(BTRIM(track_id), '') IS NULL
                    THEN 'missing_track_id' END,
                CASE WHEN NULLIF(BTRIM(title), '') IS NULL
                    THEN 'missing_title' END,
                CASE WHEN NULLIF(BTRIM(artists), '') IS NULL
                    THEN 'missing_artists' END,
                CASE WHEN NULLIF(BTRIM(release_date), '') IS NOT NULL
                    AND NOT pg_input_is_valid(
                        NULLIF(BTRIM(release_date), ''), 'date'
                    )
                    THEN 'invalid_release_date' END
            ]::TEXT[], NULL)
        FROM staging.spotify_chart_raw;
    """)


def clean_youtube(cursor):

    execute(cursor, "TRUNCATE clean.youtube_chart;")

    execute(cursor, """
        INSERT INTO clean.youtube_chart (
            source_row_id, market_code, chart_date, chart_rank,
            previous_rank, weeks_on_chart, views, video_id,
            title, artists, release_date, source_file,
            duplicate_occurrences, is_usable, quality_flags
        )

        WITH ranked AS (
            SELECT
                y.*,

                CASE
                    WHEN BTRIM(y.key) = 'T:' THEN NULL
                    ELSE NULLIF(BTRIM(y.key), '')
                END AS cleaned_video_id,

                COUNT(*) OVER (
                    PARTITION BY
                        y.cc,
                        y.week_end,
                        CASE
                            WHEN BTRIM(y.key) = 'T:'
                                THEN 'missing:' || y.source_row_id::TEXT
                            ELSE NULLIF(BTRIM(y.key), '')
                        END
                ) AS duplicate_count,

                ROW_NUMBER() OVER (
                    PARTITION BY
                        y.cc,
                        y.week_end,
                        CASE
                            WHEN BTRIM(y.key) = 'T:'
                                THEN 'missing:' || y.source_row_id::TEXT
                            ELSE NULLIF(BTRIM(y.key), '')
                        END
                    ORDER BY
                        CASE
                            WHEN pg_input_is_valid(
                                NULLIF(BTRIM(y.rank), ''), 'integer'
                            )
                            THEN NULLIF(BTRIM(y.rank), '')::INTEGER
                        END ASC NULLS LAST,
                        y.source_row_id
                ) AS row_number

            FROM staging.youtube_chart_raw y
        )

        SELECT
            source_row_id,
            NULLIF(BTRIM(cc), ''),

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(week_end), ''), 'date'
                )
                THEN NULLIF(BTRIM(week_end), '')::DATE
            END,

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(rank), ''), 'integer'
                )
                THEN NULLIF(BTRIM(rank), '')::INTEGER
            END,

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(prev_rank), ''), 'integer'
                )
                THEN NULLIF(BTRIM(prev_rank), '')::INTEGER
            END,

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(weeks_on_chart), ''), 'integer'
                )
                THEN NULLIF(BTRIM(weeks_on_chart), '')::INTEGER
            END,

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(views), ''), 'bigint'
                )
                THEN NULLIF(BTRIM(views), '')::BIGINT
            END,

            cleaned_video_id,
            NULLIF(BTRIM(title), ''),
            NULLIF(BTRIM(artists), ''),

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(release_date), ''), 'date'
                )
                THEN NULLIF(BTRIM(release_date), '')::DATE
            END,

            source_file,
            duplicate_count,

            (
                cleaned_video_id IS NOT NULL
                AND NULLIF(BTRIM(title), '') IS NOT NULL
                AND pg_input_is_valid(
                    NULLIF(BTRIM(week_end), ''), 'date'
                )
                AND pg_input_is_valid(
                    NULLIF(BTRIM(rank), ''), 'integer'
                )
            ),

            ARRAY_REMOVE(ARRAY[
                CASE WHEN cleaned_video_id IS NULL
                    THEN 'missing_or_placeholder_video_id' END,
                CASE WHEN NULLIF(BTRIM(title), '') IS NULL
                    THEN 'missing_title' END,
                CASE WHEN NULLIF(BTRIM(artists), '') IS NULL
                    THEN 'missing_artists' END,
                CASE WHEN NULLIF(BTRIM(week_end), '') IS NULL
                    THEN 'missing_chart_date' END,
                CASE WHEN NULLIF(BTRIM(rank), '') IS NULL
                    THEN 'missing_rank' END,
                CASE WHEN duplicate_count > 1
                    THEN 'repeated_video_observation' END,
                CASE WHEN NULLIF(BTRIM(release_date), '') IS NOT NULL
                    AND NOT pg_input_is_valid(
                        NULLIF(BTRIM(release_date), ''), 'date'
                    )
                    THEN 'invalid_release_date' END
            ]::TEXT[], NULL)

        FROM ranked
        WHERE row_number = 1;
    """)


def clean_metadata(cursor):

    execute(cursor, "TRUNCATE clean.youtube_metadata;")

    execute(cursor, """
        INSERT INTO clean.youtube_metadata (
            source_row_id, video_id, title, artists,
            artist_ids, release_date, songwriters,
            producers, source_file
        )
        SELECT
            source_row_id,
            NULLIF(BTRIM(key), ''),
            NULLIF(BTRIM(title), ''),
            NULLIF(BTRIM(artists), ''),
            NULLIF(BTRIM(artist_ids), ''),

            CASE
                WHEN pg_input_is_valid(
                    NULLIF(BTRIM(release_date), ''), 'date'
                )
                THEN NULLIF(BTRIM(release_date), '')::DATE
            END,

            NULLIF(BTRIM(songwriters), ''),
            NULLIF(BTRIM(producers), ''),
            source_file

        FROM staging.youtube_metadata_raw;
    """)


def print_report(cursor):

    print("\n========== CLEANING REPORT ==========")

    for table in [
        "spotify_chart",
        "youtube_chart",
        "youtube_metadata"
    ]:
        cursor.execute(
            f"SELECT COUNT(*) FROM clean.{table};"
        )
        cleaned_count = cursor.fetchone()[0]

        print(f"{table}: {cleaned_count:,} records")

    cursor.execute("""
        SELECT
            COUNT(*) FILTER (WHERE is_usable = FALSE),
            COUNT(*) FILTER (WHERE duplicate_occurrences > 1),
            COUNT(*) FILTER (WHERE video_id IS NULL)
        FROM clean.youtube_chart;
    """)

    unusable, repeated, missing_ids = cursor.fetchone()

    print("\nYouTube quality summary:")
    print(f"Unusable records: {unusable:,}")
    print(f"Repeated observations flagged: {repeated:,}")
    print(f"Missing/placeholder video IDs: {missing_ids:,}")

    print("=====================================")


def main():

    print("Starting Global Music Intelligence cleaning...")

    with psycopg.connect(**DB_CONFIG) as connection:

        with connection.cursor() as cursor:

            create_clean_schema(cursor)
            create_clean_tables(cursor)

            print("Cleaning Spotify records...")
            clean_spotify(cursor)

            print("Cleaning YouTube records...")
            clean_youtube(cursor)

            print("Cleaning YouTube metadata...")
            clean_metadata(cursor)

            print_report(cursor)

    print("\nCleaning pipeline completed successfully.")


if __name__ == "__main__":
    main()



