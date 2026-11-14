# Global Music Intelligence

A music-market analytics portfolio project exploring weekly Spotify and YouTube chart performance across global and country markets from 2018–2025.

## Project objective

Turn multi-year music chart data into decision-ready insights about song longevity, artist reach, market differences and platform-specific performance. The intended audience includes music marketers, advertisers and analysts evaluating audience reach and music trends.

**Important:** this project measures chart presence and platform-reported performance. Popularity does not establish advertising suitability, licensing availability or permission to use music.

## Current scope

- Platforms: Spotify and YouTube
- Period: 2018–2025
- Geography: global chart plus available country charts
- Database: PostgreSQL
- Data preparation: Python, Pandas and SQL
- Visualization: Tableau
- Optional validation: Google Sheets

Apple Music and other streaming services are not included in the current source dataset.

## Data source

National Music Charts dataset by Güncel Gürsel Artıktay, Zenodo record [23645386](https://zenodo.org/records/23645386), DOI [10.5281/zenodo.23645386](https://doi.org/10.5281/zenodo.23645386).

The downloaded source files cover Spotify Top 200 and YouTube Top 100 chart positions for 2018–2025, plus YouTube song metadata. Review the dataset's CC BY 4.0 attribution requirements and the applicable platform terms before redistribution. Raw source files are intentionally not committed to this repository.

## Current data preparation results

| Dataset | Records |
|---|---:|
| Spotify cleaned chart observations | 857,000 |
| YouTube cleaned chart observations | 1,757,972 |
| YouTube metadata records | 121,256 |
| Unified Spotify + YouTube observations | 2,614,972 |

The YouTube cleaning step reduced 2,159 repeated video observations by retaining the best-ranked observation within a market and chart date. The 99 placeholder/missing video IDs remain flagged as unusable. The unified view preserves platform-specific metrics: Spotify streams and YouTube views are never added together.

YouTube metadata enrichment matched 1,757,873 chart observations; 99 observations had no usable video ID. The enriched view preserved the original chart observation count.

These are preparation-stage counts, not final analytical findings. Results should be regenerated from the scripts and local database.

## Repository structure

```
.
├── analysis/             # Business analysis SQL
├── database/             # PostgreSQL schema, audit and transformation SQL
├── python/               # Data loading, audit and cleaning scripts
├── documentation/        # Methodology and data-quality documentation
├── data/                 # Local data folders (raw files excluded from Git)
├── tableau/              # Tableau workbook exports and dashboard assets
├── .env.example          # Local database configuration template
└── .gitignore
```

## Reproducing the project

1. Install PostgreSQL and Python.
2. Create a PostgreSQL database and local role.
3. Clone this repository.
4. Create and activate a virtual environment.
5. Install dependencies used by the scripts: `pandas`, `psycopg[binary]`, and `python-dotenv`.
6. Copy `.env.example` to `.env` and set local database credentials. Never commit `.env`.
7. Download the Zenodo source files and place them under `data/raw/zenodo_music_charts/`.
8. Run the staging table SQL, then `python python/load_staging.py`.
9. Run the cleaning script: `python python/clean_data.py`.
10. Execute the database SQL scripts in sequence, then run the analysis queries.

Use the SQL files and script comments as the source of truth for the current implementation. The local raw data and database are not included in this repository.

## Methodological notes and limitations

- Spotify streams and YouTube views are different measures and must be analyzed separately.
- Chart coverage is not uniform across all markets and weeks. Compare like-for-like periods or normalize by available chart observations.
- A chart rank is platform-specific; ranks should not be treated as a universal cross-platform popularity score without a clearly documented model.
- YouTube duplicate-rank conditions in the source are not equivalent to duplicate video observations. The cleaning process targets repeated video IDs within a market and chart date.
- Artist name normalization currently handles whitespace and case, not aliases, transliterations or identity resolution.
- Cross-platform song matching requires additional evidence and confidence scoring; Spotify track IDs and YouTube video IDs are not interchangeable.
- Missing metadata is retained as missing rather than fabricated.
- Metadata release dates that occur after chart dates or before 1900 are treated as unreliable and nulled in the clean layer; original source values remain in staging.
- Genre, audio features, brand suitability and licensing status are not established by the current source data.

## Planned deliverables

- Reproducible PostgreSQL cleaning and analysis workflow
- Data-quality and methodology documentation
- Tableau dashboards for executive overview, song/artist intelligence, market trends and platform comparison
- Portfolio summary with evidence-based findings

## Author

**Devashish Anand**  
GitHub: [@devashish-sh](https://github.com/devashish-sh)
