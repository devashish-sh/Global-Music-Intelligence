from pathlib import Path
import pandas as pd

RAW_DIR = Path("data/raw/zenodo_music_charts")
REPORT_DIR = Path("documentation/data_audit")

REPORT_DIR.mkdir(parents=True, exist_ok=True)

file_reports = []
column_reports = []
chart_reports = []

files = sorted(RAW_DIR.glob("*_positions_*.csv.gz"))

for file in files:
    print(f"Auditing: {file.name}")

    df = pd.read_csv(file)

    platform = "spotify" if file.name.startswith("spotify") else "youtube"

    charts = (
        df.groupby(["cc", "week_end"])
        .agg(
            rows=("rank", "size"),
            unique_ranks=("rank", "nunique"),
            min_rank=("rank", "min"),
            max_rank=("rank", "max"),
        )
        .reset_index()
    )

    charts["duplicate_rank_count"] = (
        charts["rows"] - charts["unique_ranks"]
    )

    file_reports.append({
        "file": file.name,
        "platform": platform,
        "rows": len(df),
        "markets": df["cc"].nunique(),
        "chart_dates": df["week_end"].nunique(),
        "first_date": df["week_end"].min(),
        "last_date": df["week_end"].max(),
        "chart_instances": len(charts),
        "incomplete_charts": (
            charts["rows"] != (200 if platform == "spotify" else 100)
        ).sum(),
        "charts_with_duplicate_ranks": (
            charts["duplicate_rank_count"] > 0
        ).sum(),
    })

    for column in df.columns:
        column_reports.append({
            "file": file.name,
            "platform": platform,
            "column": column,
            "missing_values": int(df[column].isna().sum()),
            "missing_percentage": round(
                df[column].isna().mean() * 100, 3
            ),
            "data_type": str(df[column].dtype),
        })

    charts["file"] = file.name
    charts["platform"] = platform

    chart_reports.append(charts)

pd.DataFrame(file_reports).to_csv(
    REPORT_DIR / "file_summary.csv", index=False
)

pd.DataFrame(column_reports).to_csv(
    REPORT_DIR / "column_quality.csv", index=False
)

pd.concat(chart_reports, ignore_index=True).to_csv(
    REPORT_DIR / "chart_quality.csv", index=False
)

print("\nAUDIT COMPLETE")
print(f"Files processed: {len(files)}")
print(f"Reports saved in: {REPORT_DIR}")
print("\nFILE SUMMARY:")
print(pd.DataFrame(file_reports).to_string(index=False))
