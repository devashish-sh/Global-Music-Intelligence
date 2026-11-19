"""
GLOBAL MUSIC INTELLIGENCE
TABLEAU DATA EXPORT

Builds the CSV files consumed by the Tableau workbook described in
documentation/tableau_build_guide.md.

Tableau Public cannot reach the local PostgreSQL instance, so the
analysis layer is materialised into purpose-built, dashboard-sized
CSVs (one file per analysis grain). Nothing here invents numbers:
every file is a direct projection of staging/clean/analytics.

Usage:
    python python/export_tableau_data.py

Output: tableau/data/*.csv (UTF-8, ISO dates, comma separated)
"""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT_DIR / "tableau" / "data"

# Tableau geocodes country names, not ISO-2 codes reliably, and it does
# not know "Türkiye". Map each marketing code to a Tableau-friendly name.
COUNTRY_MAP = """
    ('ar','Argentina'), ('at','Austria'), ('au','Australia'), ('be','Belgium'),
    ('br','Brazil'), ('ca','Canada'), ('ch','Switzerland'), ('cl','Chile'),
    ('co','Colombia'), ('cz','Czechia'), ('de','Germany'), ('dk','Denmark'),
    ('ee','Estonia'), ('es','Spain'), ('fi','Finland'), ('fr','France'),
    ('gb','United Kingdom'), ('global','Global'), ('ie','Ireland'),
    ('is','Iceland'), ('it','Italy'), ('jp','Japan'), ('ke','Kenya'),
    ('kr','South Korea'), ('lu','Luxembourg'), ('mx','Mexico'), ('ng','Nigeria'),
    ('nl','Netherlands'), ('no','Norway'), ('nz','New Zealand'), ('pe','Peru'),
    ('pl','Poland'), ('pt','Portugal'), ('ro','Romania'), ('rs','Serbia'),
    ('ru','Russia'), ('se','Sweden'), ('tr','Turkey'), ('tz','Tanzania'),
    ('ua','Ukraine'), ('ug','Uganda'), ('us','United States'),
    ('za','South Africa'), ('zw','Zimbabwe')
"""

JOIN_MAP = """
    SELECT * FROM (VALUES
        ('ar','Argentina'), ('at','Austria'), ('au','Australia'), ('be','Belgium'),
        ('br','Brazil'), ('ca','Canada'), ('ch','Switzerland'), ('cl','Chile'),
        ('co','Colombia'), ('cz','Czechia'), ('de','Germany'), ('dk','Denmark'),
        ('ee','Estonia'), ('es','Spain'), ('fi','Finland'), ('fr','France'),
        ('gb','United Kingdom'), ('global','Global'), ('ie','Ireland'),
        ('is','Iceland'), ('it','Italy'), ('jp','Japan'), ('ke','Kenya'),
        ('kr','South Korea'), ('lu','Luxembourg'), ('mx','Mexico'), ('ng','Nigeria'),
        ('nl','Netherlands'), ('no','Norway'), ('nz','New Zealand'), ('pe','Peru'),
        ('pl','Poland'), ('pt','Portugal'), ('ro','Romania'), ('rs','Serbia'),
        ('ru','Russia'), ('se','Sweden'), ('tr','Turkey'), ('tz','Tanzania'),
        ('ua','Ukraine'), ('ug','Uganda'), ('us','United States'),
        ('za','South Africa'), ('zw','Zimbabwe')
    ) AS m(market_code, country)
"""

# ---------------------------------------------------------------------------
# 1. song_reach — one row per charting song/video (the core fact table)
# ---------------------------------------------------------------------------
SONG_REACH = f"""
SELECT
    i.platform,
    i.platform_item_id,
    i.title,
    i.artists,
    BTRIM(SPLIT_PART(i.artists, '|', 1))   AS primary_artist,
    i.chart_weeks,
    i.markets,
    i.avg_rank,
    i.best_rank,
    i.first_chart_date,
    i.last_chart_date,
    i.release_date,
    CASE
        WHEN i.release_date IS NOT NULL
         AND i.first_chart_date >= i.release_date
        THEN i.first_chart_date - i.release_date
    END                                    AS days_to_first_chart,
    EXTRACT(YEAR FROM i.first_chart_date)::INT AS first_chart_year,
    i.total_streams,
    i.total_views,
    i.peak_week_views,
    i.no1_market_weeks,
    ROUND(i.chart_weeks::NUMERIC / NULLIF(i.markets, 0), 2) AS weeks_per_market,
    CASE
        WHEN i.chart_weeks = 1 THEN '1 week'
        WHEN i.chart_weeks <= 4 THEN '2-4 weeks'
        WHEN i.chart_weeks <= 12 THEN '5-12 weeks'
        WHEN i.chart_weeks <= 26 THEN '13-26 weeks'
        WHEN i.chart_weeks <= 52 THEN '27-52 weeks'
        ELSE '53+ weeks'
    END                                    AS lifetime_band
FROM (
    SELECT
        u.platform,
        u.platform_item_id,
        MAX(u.title)                    AS title,
        COALESCE(MAX(u.artists), 'Unknown artist') AS artists,
        COUNT(DISTINCT u.chart_date)    AS chart_weeks,
        COUNT(DISTINCT u.market_code)   AS markets,
        ROUND(AVG(u.chart_rank), 2)     AS avg_rank,
        MIN(u.chart_rank)               AS best_rank,
        MIN(u.chart_date)               AS first_chart_date,
        MAX(u.chart_date)               AS last_chart_date,
        MAX(u.release_date)             AS release_date,
        SUM(u.streams)                  AS total_streams,
        SUM(u.views)                    AS total_views,
        MAX(u.views)                    AS peak_week_views,
        COUNT(*) FILTER (WHERE u.chart_rank = 1) AS no1_market_weeks
    FROM analytics.v_unified_chart_observations u
    WHERE u.is_usable
      AND u.platform_item_id IS NOT NULL
    GROUP BY u.platform, u.platform_item_id
) i
ORDER BY i.platform, i.chart_weeks DESC
"""

# ---------------------------------------------------------------------------
# 2. market_week — one row per market per chart date (trend + seasonality)
# ---------------------------------------------------------------------------
MARKET_WEEK = f"""
SELECT
    o.platform,
    o.market_code,
    m.country,
    o.chart_date,
    EXTRACT(YEAR FROM o.chart_date)::INT  AS chart_year,
    EXTRACT(MONTH FROM o.chart_date)::INT AS chart_month,
    TO_CHAR(o.chart_date, 'YYYY-MM')      AS chart_month_label,
    COUNT(*)                              AS observations,
    COUNT(DISTINCT o.platform_item_id)    AS items,
    COUNT(*) FILTER (WHERE o.chart_rank <= 10) AS top10_observations
FROM analytics.v_unified_chart_observations o
JOIN ({JOIN_MAP}) m ON m.market_code = o.market_code
WHERE o.is_usable
GROUP BY o.platform, o.market_code, m.country, o.chart_date
ORDER BY o.platform, o.market_code, o.chart_date
"""

# ---------------------------------------------------------------------------
# 3. market_summary — one row per market (coverage panel + map)
# ---------------------------------------------------------------------------
MARKET_SUMMARY = f"""
SELECT
    o.platform,
    o.market_code,
    m.country,
    COUNT(*)                              AS observations,
    COUNT(DISTINCT o.chart_date)          AS chart_dates,
    COUNT(DISTINCT o.platform_item_id)    AS items,
    COUNT(*) FILTER (WHERE o.chart_rank <= 10) AS top10_observations,
    ROUND(100.0 * COUNT(*) FILTER (WHERE o.chart_rank <= 10) / COUNT(*), 2)
                                          AS top10_share_pct,
    MIN(o.chart_date)                     AS first_date,
    MAX(o.chart_date)                     AS last_date,
    CASE
        WHEN COUNT(DISTINCT o.chart_date) >= 400 THEN 'Weekly'
        ELSE 'Sampled'
    END                                   AS coverage_type,
    (m.country <> 'Global')               AS is_country
FROM analytics.v_unified_chart_observations o
JOIN ({JOIN_MAP}) m ON m.market_code = o.market_code
WHERE o.is_usable
GROUP BY o.platform, o.market_code, m.country
ORDER BY o.platform, observations DESC
"""

# ---------------------------------------------------------------------------
# 4. market_leader — the defining song of each market
# ---------------------------------------------------------------------------
MARKET_LEADER = f"""
WITH market_items AS (
    SELECT
        o.platform,
        o.market_code,
        o.platform_item_id,
        MAX(o.title)                 AS title,
        COALESCE(MAX(o.artists), 'Unknown artist') AS artists,
        COUNT(DISTINCT o.chart_date) AS weeks,
        MIN(o.chart_rank)            AS best_rank
    FROM analytics.v_unified_chart_observations o
    WHERE o.is_usable
      AND o.platform_item_id IS NOT NULL
    GROUP BY o.platform, o.market_code, o.platform_item_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY platform, market_code
               ORDER BY weeks DESC, best_rank ASC
           ) AS rn
    FROM market_items
)
SELECT r.platform, r.market_code, m.country, r.title, r.artists,
       r.weeks, r.best_rank
FROM ranked r
JOIN ({JOIN_MAP}) m ON m.market_code = r.market_code
WHERE r.rn = 1
ORDER BY r.platform, r.market_code
"""

# ---------------------------------------------------------------------------
# 5. artists — one row per artist per platform
# ---------------------------------------------------------------------------
ARTISTS = """
SELECT
    ta.platform_name                        AS platform,
    a.artist_name,
    COUNT(DISTINCT ta.platform_item_id)     AS items,
    COUNT(DISTINCT u.chart_date)            AS chart_weeks,
    COUNT(DISTINCT u.market_code)           AS markets,
    ROUND(AVG(u.chart_rank), 1)             AS avg_rank,
    MIN(u.chart_rank)                       AS best_rank,
    ROUND(
        1.0 * COUNT(DISTINCT u.chart_date)
        / NULLIF(COUNT(DISTINCT u.market_code), 0), 2
    )                                       AS weeks_per_market
FROM clean.track_artists ta
JOIN clean.artists a
  ON a.artist_id = ta.artist_id
JOIN analytics.v_unified_chart_observations u
  ON u.platform = ta.platform_name
 AND u.platform_item_id = ta.platform_item_id
WHERE u.is_usable
GROUP BY ta.platform_name, a.artist_name
ORDER BY chart_weeks DESC, markets DESC
"""

# ---------------------------------------------------------------------------
# 6. cross_platform — conservative exact title+artist matches
# ---------------------------------------------------------------------------
CROSS_PLATFORM = """
WITH sp AS (
    SELECT
        LOWER(REGEXP_REPLACE(BTRIM(title), '\\s+', ' ', 'g'))   AS t,
        LOWER(REGEXP_REPLACE(BTRIM(artists), '\\s+', ' ', 'g')) AS a,
        MAX(title)   AS title,
        MAX(artists) AS artists,
        COUNT(DISTINCT chart_date) AS weeks,
        MIN(chart_rank) AS best_rank,
        COUNT(DISTINCT market_code) AS markets
    FROM clean.spotify_chart
    WHERE title IS NOT NULL AND artists IS NOT NULL
    GROUP BY 1, 2
),
yt AS (
    SELECT
        LOWER(REGEXP_REPLACE(BTRIM(title), '\\s+', ' ', 'g'))   AS t,
        LOWER(REGEXP_REPLACE(BTRIM(artists), '\\s+', ' ', 'g')) AS a,
        COUNT(DISTINCT chart_date) AS weeks,
        MIN(chart_rank) AS best_rank,
        COUNT(DISTINCT market_code) AS markets
    FROM clean.youtube_chart
    WHERE title IS NOT NULL AND artists IS NOT NULL AND is_usable
    GROUP BY 1, 2
)
SELECT
    sp.title,
    sp.artists,
    sp.weeks        AS spotify_weeks,
    yt.weeks        AS youtube_weeks,
    sp.best_rank    AS spotify_best,
    yt.best_rank    AS youtube_best,
    sp.markets      AS spotify_markets,
    yt.markets      AS youtube_markets,
    sp.weeks + yt.weeks AS combined_weeks,
    CASE
        WHEN sp.weeks >= yt.weeks THEN 'Spotify-led'
        ELSE 'YouTube-led'
    END             AS lead_platform
FROM sp
JOIN yt USING (t, a)
ORDER BY combined_weeks DESC
"""

# ---------------------------------------------------------------------------
# 7. creators — songwriters and producers in long format
# ---------------------------------------------------------------------------
CREATORS = """
WITH charting AS (
    SELECT DISTINCT video_id
    FROM clean.youtube_chart
    WHERE is_usable AND video_id IS NOT NULL
),
credits AS (
    SELECT 'Songwriter' AS role,
           BTRIM(w)     AS name,
           m.video_id,
           ROW_NUMBER() OVER (PARTITION BY m.video_id ORDER BY m.video_id) AS ord
    FROM clean.youtube_metadata m
    JOIN charting c ON c.video_id = m.video_id
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(m.songwriters, '|')) AS w
    WHERE m.songwriters IS NOT NULL AND BTRIM(w) <> ''

    UNION ALL

    SELECT 'Producer',
           BTRIM(p),
           m.video_id,
           ROW_NUMBER() OVER (PARTITION BY m.video_id ORDER BY m.video_id)
    FROM clean.youtube_metadata m
    JOIN charting c ON c.video_id = m.video_id
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(m.producers, '|')) AS p
    WHERE m.producers IS NOT NULL AND BTRIM(p) <> ''
)
SELECT role, name, COUNT(DISTINCT video_id) AS charting_songs
FROM credits
GROUP BY role, name
HAVING COUNT(DISTINCT video_id) >= 5
ORDER BY charting_songs DESC
"""

# ---------------------------------------------------------------------------
# 8. entry_status — Spotify chart freshness by year
# ---------------------------------------------------------------------------
ENTRY_STATUS = """
SELECT
    EXTRACT(YEAR FROM chart_date)::INT AS chart_year,
    entry_status,
    COUNT(*)                           AS observations
FROM clean.spotify_chart
WHERE entry_status IS NOT NULL
GROUP BY EXTRACT(YEAR FROM chart_date), entry_status
ORDER BY chart_year, entry_status
"""

# ---------------------------------------------------------------------------
# 9. seasonality — breadth per chart date, by month
# ---------------------------------------------------------------------------
SEASONALITY = """
WITH per_date AS (
    SELECT
        platform,
        chart_date,
        EXTRACT(YEAR FROM chart_date)::INT  AS chart_year,
        EXTRACT(MONTH FROM chart_date)::INT AS chart_month,
        COUNT(DISTINCT platform_item_id)    AS items
    FROM analytics.v_unified_chart_observations
    WHERE is_usable
      AND platform_item_id IS NOT NULL
    GROUP BY platform, chart_date
)
SELECT
    chart_year,
    chart_month,
    platform,
    ROUND(AVG(items), 1) AS avg_items,
    COUNT(*)             AS chart_dates
FROM per_date
GROUP BY chart_year, chart_month, platform
ORDER BY chart_year, chart_month, platform
"""

# ---------------------------------------------------------------------------
# 10. concentration_curve — cumulative share of chart weeks by item rank
# ---------------------------------------------------------------------------
CONCENTRATION = """
WITH item_weeks AS (
    SELECT platform, platform_item_id, COUNT(DISTINCT chart_date) AS w
    FROM analytics.v_unified_chart_observations
    WHERE is_usable AND platform_item_id IS NOT NULL
    GROUP BY platform, platform_item_id
),
cumulative AS (
    SELECT
        platform,
        w,
        ROW_NUMBER() OVER (PARTITION BY platform ORDER BY w DESC) AS rn,
        SUM(w) OVER (
            PARTITION BY platform
            ORDER BY w DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_weeks,
        SUM(w) OVER (PARTITION BY platform) AS total_weeks,
        COUNT(*) OVER (PARTITION BY platform) AS total_items
    FROM item_weeks
)
SELECT
    platform,
    rn                                              AS top_n,
    total_items,
    total_weeks,
    ROUND(100.0 * rn / total_items, 4)               AS pct_of_items,
    ROUND(100.0 * running_weeks / NULLIF(total_weeks, 0), 2) AS cumulative_pct
FROM cumulative
WHERE rn IN (1, 2, 5, 10, 25, 50, 100, 250, 500, 1000,
             2500, 5000, 10000, 25000, 50000, 75000, 100000)
ORDER BY platform, rn
"""

FILES = [
    ("01_song_reach.csv", SONG_REACH),
    ("02_market_week.csv", MARKET_WEEK),
    ("03_market_summary.csv", MARKET_SUMMARY),
    ("04_market_leader.csv", MARKET_LEADER),
    ("05_artists.csv", ARTISTS),
    ("06_cross_platform.csv", CROSS_PLATFORM),
    ("07_creators.csv", CREATORS),
    ("08_entry_status.csv", ENTRY_STATUS),
    ("09_seasonality.csv", SEASONALITY),
    ("10_concentration.csv", CONCENTRATION),
]


def db_config() -> dict:
    load_dotenv(ROOT_DIR / ".env")
    return {
        "host": os.getenv("DB_HOST"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME"),
        "user": os.getenv("DB_USER"),
        "password": os.getenv("DB_PASSWORD"),
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total_bytes = 0

    print("Exporting Tableau sources...\n")

    with psycopg.connect(**db_config()) as connection:
        with connection.cursor() as cursor:
            for filename, sql in FILES:
                path = OUT_DIR / filename
                with open(path, "wb") as handle:
                    with cursor.copy(f"COPY ({sql}) TO STDOUT WITH CSV HEADER") as copy:
                        for block in copy:
                            handle.write(block)

                size_mb = path.stat().st_size / (1024 * 1024)
                total_bytes += path.stat().st_size

                cursor.execute(f"SELECT COUNT(*) FROM ({sql}) q")
                rows = cursor.fetchone()[0]
                print(f"  {filename:<26} {rows:>8,} rows   {size_mb:>6.2f} MB")

    print(f"\nTotal: {total_bytes / (1024 * 1024):.1f} MB in {len(FILES)} files")
    print(f"Location: {OUT_DIR.relative_to(ROOT_DIR)}")


if __name__ == "__main__":
    main()
