
from pathlib import Path
import os

import pandas as pd
import psycopg
from dotenv import load_dotenv


# --------------------------------------------------
# 1. PROJECT CONFIGURATION
# --------------------------------------------------

ROOT_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT_DIR / "data" / "raw" / "zenodo_music_charts"

load_dotenv(ROOT_DIR / ".env")

DB_CONFIG = {
    "host": os.getenv("DB_HOST"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
}

CHUNK_SIZE = 50000


# --------------------------------------------------
# 2. SOURCE CONFIGURATION
# --------------------------------------------------

SOURCES = [
    {
        "pattern": "spotify_top200_positions_*.csv.gz",
        "table": "staging.spotify_chart_raw",
        "columns": [
            "cc", "week_end", "rank", "prev_rank", "peak",
            "appearances", "streams", "entry_status",
            "track_id", "title", "artists", "artist_uris",
            "release_date"
        ],
    },
    {
        "pattern": "youtube_top100_positions_*.csv.gz",
        "table": "staging.youtube_chart_raw",
        "columns": [
            "cc", "week_end", "rank", "prev_rank",
            "weeks_on_chart", "views", "key", "title",
            "artists", "release_date"
        ],
    },
    {
        "pattern": "youtube_songs_metadata.csv.gz",
        "table": "staging.youtube_metadata_raw",
        "columns": [
            "key", "title", "artists", "artist_ids",
            "release_date", "songwriters", "producers"
        ],
    },
]


# --------------------------------------------------
# 3. LOAD A SINGLE FILE IN BATCHES
# --------------------------------------------------

def load_file(cursor, file_path, table, columns):

    column_list = ", ".join(columns + ["source_file"])

    copy_query = (
        f"COPY {table} ({column_list}) FROM STDIN"
    )

    total_rows = 0

    for chunk in pd.read_csv(
        file_path,
        dtype=str,
        keep_default_na=False,
        chunksize=CHUNK_SIZE
    ):

        with cursor.copy(copy_query) as copy:

            for row in chunk[columns].itertuples(
                index=False,
                name=None
            ):

                clean_row = tuple(
                    None if value == "" else value
                    for value in row
                )

                copy.write_row(
                    clean_row + (file_path.name,)
                )

        total_rows += len(chunk)

    return total_rows


# --------------------------------------------------
# 4. MAIN DATABASE LOADING PROCESS
# --------------------------------------------------

def main():

    print("GLOBAL MUSIC INTELLIGENCE")
    print("Starting staging data import...\n")

    with psycopg.connect(**DB_CONFIG) as connection:

        with connection.cursor() as cursor:

            # Replace previous staging contents on each full run.
            cursor.execute("""
                TRUNCATE TABLE
                    staging.spotify_chart_raw,
                    staging.youtube_chart_raw,
                    staging.youtube_metadata_raw;
            """)

            grand_total = 0

            for source in SOURCES:

                files = sorted(
                    RAW_DIR.glob(source["pattern"])
                )

                if not files:
                    raise FileNotFoundError(
                        f"No files found: {source['pattern']}"
                    )

                for file_path in files:

                    print(f"Loading: {file_path.name}")

                    rows = load_file(
                        cursor,
                        file_path,
                        source["table"],
                        source["columns"]
                    )

                    grand_total += rows

                    print(f"Loaded rows: {rows:,}\n")

    print("--------------------------------")
    print("DATA IMPORT COMPLETED")
    print(f"Total imported rows: {grand_total:,}")
    print("--------------------------------")


if __name__ == "__main__":
    main()
