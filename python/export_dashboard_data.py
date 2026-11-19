"""
GLOBAL MUSIC INTELLIGENCE
DASHBOARD DATA EXPORT

Executes the tagged business queries in analysis/02_business_queries.sql
and writes a single JSON payload consumed by dashboard/index.html.

Usage:
    python python/export_dashboard_data.py

The SQL file stays the source of truth: this script only runs it,
serialises the result sets and records the metadata shown in the
dashboard footer (period, row counts, generation timestamp).
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from decimal import Decimal
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent.parent
QUERY_FILE = ROOT_DIR / "analysis" / "02_business_queries.sql"
OUTPUT_FILE = ROOT_DIR / "dashboard" / "data" / "dashboard.json"

QUERY_MARKER = re.compile(r"^--\s*@query\s+([a-z_]+)\s*$", re.MULTILINE)


def db_config() -> dict:
    load_dotenv(ROOT_DIR / ".env")
    return {
        "host": os.getenv("DB_HOST"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME"),
        "user": os.getenv("DB_USER"),
        "password": os.getenv("DB_PASSWORD"),
    }


def parse_queries(path: Path) -> list[tuple[str, str]]:
    """Split the SQL file into (key, statement) pairs on -- @query markers."""
    text = path.read_text()
    markers = list(QUERY_MARKER.finditer(text))

    if not markers:
        raise SystemExit(f"No -- @query markers found in {path}")

    queries: list[tuple[str, str]] = []

    for index, marker in enumerate(markers):
        start = marker.end()
        end = markers[index + 1].start() if index + 1 < len(markers) else len(text)
        block = text[start:end]

        # Drop trailing comment-only lines so the statement ends cleanly.
        lines = [line for line in block.splitlines()]
        while lines and (not lines[-1].strip() or lines[-1].lstrip().startswith("--")):
            lines.pop()

        statement = "\n".join(lines).strip().rstrip(";")
        queries.append((marker.group(1), statement))

    return queries


def serialise(value):
    """Make PostgreSQL values JSON-safe."""
    if value is None:
        return None
    if isinstance(value, Decimal):
        as_float = float(value)
        return int(as_float) if as_float.is_integer() else round(as_float, 4)
    if isinstance(value, (dt.date, dt.datetime)):
        return value.isoformat()
    return value


def main() -> None:
    queries = parse_queries(QUERY_FILE)
    payload: dict[str, object] = {}
    row_counts: dict[str, int] = {}

    print(f"Running {len(queries)} business queries...\n")

    with psycopg.connect(**db_config()) as connection:
        with connection.cursor() as cursor:
            for key, statement in queries:
                cursor.execute(statement)

                if cursor.description is None:
                    row_counts[key] = 0
                    payload[key] = []
                    continue

                columns = [column.name for column in cursor.description]
                rows = [
                    {column: serialise(value) for column, value in zip(columns, row)}
                    for row in cursor.fetchall()
                ]

                payload[key] = rows
                row_counts[key] = len(rows)
                print(f"  {key:<26} {len(rows):>5} rows")

            cursor.execute("""
                SELECT
                    (SELECT COUNT(*) FROM clean.spotify_chart),
                    (SELECT COUNT(*) FROM clean.youtube_chart),
                    (SELECT COUNT(*) FROM clean.youtube_metadata),
                    (SELECT COUNT(*) FROM clean.artists),
                    (SELECT COUNT(*) FROM analytics.v_unified_chart_observations),
                    (SELECT COUNT(*) FROM analytics.v_unified_chart_observations
                      WHERE is_usable)
            """)
            (spotify_rows, youtube_rows, metadata_rows,
             artist_rows, unified_rows, usable_rows) = cursor.fetchone()

    payload["meta"] = {
        "generated_at": dt.datetime.now().replace(microsecond=0).isoformat(),
        "source_rows": {
            "spotify_chart": spotify_rows,
            "youtube_chart": youtube_rows,
            "youtube_metadata": metadata_rows,
            "artists": int(artist_rows),
            "unified_observations": unified_rows,
            "usable_observations": usable_rows,
        },
        "query_row_counts": row_counts,
        "query_file": str(QUERY_FILE.relative_to(ROOT_DIR)),
    }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(payload, separators=(",", ":")))

    size_kb = OUTPUT_FILE.stat().st_size / 1024
    print(f"\nWrote {OUTPUT_FILE.relative_to(ROOT_DIR)} ({size_kb:,.1f} KB)")
    print(f"Usable observations: {usable_rows:,} of {unified_rows:,}")


if __name__ == "__main__":
    sys.exit(main())
