# Tableau Build Guide — Global Music Intelligence

A complete, step-by-step build for a portfolio-grade Tableau workbook: three dashboards,
one method sheet, published to Tableau Public, with the copy and launch plan to make it
work for you on LinkedIn.

**Read this first:** every number quoted in this guide is a real output of this repository.
The validation table in Step 8 lets you prove your workbook matches the database — that is
what separates a portfolio project from a screenshot of charts.

---

## Contents

| Step | What you do | Time |
|---|---|---|
| 0 | Decide what you are building | 5 min |
| 1 | Install the correct Tableau edition | 15 min |
| 2 | Generate the Tableau data (`export_tableau_data.py`) | 5 min |
| 3 | Connect, type and model the data | 20 min |
| 4 | Create the calculated fields and parameter | 25 min |
| 5 | Build the worksheets (25 of them, in order) | 4–6 hrs |
| 6 | Assemble the three dashboards | 2 hrs |
| 7 | Apply the formatting system | 45 min |
| 8 | Validate every number against the reference table | 20 min |
| 9 | Publish to Tableau Public | 20 min |
| 10 | Portfolio, LinkedIn and interview playbook | ongoing |

Total hands-on build: **one solid weekend**. Do it in the order written; each dashboard
works on its own if you run out of time.

---

## Step 0 — What you are building

One workbook, **three dashboards plus a method sheet**. Each dashboard answers a different
job, and each one is individually screenshot-worthy.

### Dashboard 1 — "Executive Overview"

Audience: a music marketer or label strategist who has 30 seconds.

* What is the scale of the chart universe? (2.61M observations, 400 weeks, 82 market rows)
* Is chart space growing, and how much new music enters each year?
* How long does a hit actually last?
* Answer: *"Charts are not a launch pad, they are a holding pattern — and most entries
  are one-week events."*

### Dashboard 2 — "Song & Artist Intelligence"

Audience: an A&R, playlist editor or artist manager.

* Which songs and artists have genuine staying power versus a viral spike?
* How concentrated is chart success? (top 1,000 songs = 19.5% of all chart weeks on Spotify)
* Which artists reach many markets rather than many weeks in one?
* Answer: *"Reach and longevity are different assets, and the dashboard scores both."*

### Dashboard 3 — "Market & Platform"

Audience: a media planner allocating spend across countries and platforms.

* Which markets are deepest? Where is local repertoire winning?
* Which songs own the #1 slot?
* How steeply does attention fall down the chart? (5.5× views gap, top 10 vs 51–100)
* What appears on both platforms? (24,438 songs = 38.3% of Spotify credits)
* Answer: *"YouTube attention decays smoothly; Spotify's chart is the more concentrated
  one; most songs do not cross over."*

### Sheet 4 — "Method & Data Quality"

Audience: the interviewer who asks "how do you know this is right?"

Shows row counts, exclusions, the Spotify sampling caveat and the cross-platform matching
rule. This sheet is why a hiring manager trusts the rest.

### Non-negotiables

1. **Never add Spotify streams to YouTube views.** They are different measures. Every
   panel is labelled by platform.
2. **Never imply advertising suitability, licensing or genre.** The source has none of it.
3. **Attribution:** the source is CC BY 4.0 — put *"Data: National Music Charts
   (Güncel Gürsel Artıktay), Zenodo 23645386, CC BY 4.0"* in the footer of every dashboard.

---

## Step 1 — Install the correct Tableau edition

This is the step where most people lose a week, so read it carefully.

Tableau ships **two free desktop apps with almost the same name**:

| | Tableau Desktop **Public Edition** | Tableau Desktop **Free Edition** |
|---|---|---|
| Free | Yes | Yes |
| **Publish to Tableau Public** | **Yes** | **No** |
| Connect to PostgreSQL / live databases | No — files only | Yes |
| Row limit per workbook | **15 million** | none |
| Cost of publishing | Free | n/a |

You need **Tableau Desktop Public Edition** from
<https://www.tableau.com/en-us/products/public/download>.

Verify it is the right build: the menu bar must show **Server → Tableau Public**.

### Tableau Public's hard limits (as of 2026)

* **15 million rows per workbook.** You are at 184,616 rows in the largest source — no risk.
* **1 GB maximum per uploaded file.** Your largest CSV is 27 MB.
* **10 GB total storage per account.** Each published workbook counts once.
* **Extracts only, no live connections.** This is why Step 2 exports CSVs: Tableau Public
  cannot connect to your local PostgreSQL, so the analysis layer must be materialised.
* **Everything you publish is public.** Only publish this dataset (it is already public).

Create your Tableau Public account **before** you build (step 1 of the app's welcome
screen), and use your real name — the profile URL becomes part of your portfolio.

---

## Step 2 — Generate the Tableau data

```bash
cd Global-Music-Intelligence
.venv/bin/python python/export_tableau_data.py
```

This writes ten CSVs to `tableau/data/`. They are a projection of the same PostgreSQL
analysis layer the HTML dashboard uses, so the numbers are identical by construction.

| File | Rows | Size | Grain | Used for |
|---|---:|---:|---|---|
| `01_song_reach.csv` | 184,616 | 27 MB | one song/video per platform | longevity, concentration, top songs, #1s, views, release lag |
| `02_market_week.csv` | 21,885 | 1.2 MB | market × chart date | trend lines, seasonality, market coverage over time |
| `03_market_summary.csv` | 82 | 6 KB | market per platform | map, coverage table, sampled-vs-weekly flag |
| `04_market_leader.csv` | 82 | 5 KB | market per platform | "the song that defines this market" |
| `05_artists.csv` | 53,063 | 2.0 MB | artist per platform | artist reach, artist tables |
| `06_cross_platform.csv` | 24,438 | 1.3 MB | matched song | overlap scatter, dual-platform table |
| `07_creators.csv` | 12,825 | 339 KB | creator per role | songwriters and producers |
| `08_entry_status.csv` | 40 | 1 KB | year × entry status | new-music intake |
| `09_seasonality.csv` | 184 | 4 KB | year × month × platform | seasonality heatmap |
| `10_concentration.csv` | 32 | 1 KB | platform × rank band | concentration curve |

### Rules for using these files

* **Never join two files together.** Each is a different grain. Joining `01_song_reach`
  (song-level) to `02_market_week` (market-week-level) multiplies measures and every total
  becomes wrong. Use **separate data sources**, and use a parameter (Step 4) to filter all
  of them at once.
* `01_song_reach.csv` is the workhorse — build Dashboards 1 and 2 mostly from it.
* Re-run the export whenever you change the database. The workbook keeps its own extract,
  so re-publishing is a two-click operation.

---

## Step 3 — Connect, type and model the data

Repeat for each file you need. Start with the big one.

1. **Connect** → *Text file* → `tableau/data/01_song_reach.csv`.
2. On the Data Source page, check the field types Tableau guessed:
   * `first_chart_date`, `last_chart_date`, `release_date` → **Date**
   * `chart_weeks`, `markets`, `best_rank`, `no1_market_weeks`, `first_chart_year` → **Number (whole)**
   * `avg_rank`, `weeks_per_market`, `total_streams`, `total_views`, `peak_week_views` → **Number (whole)** for views/streams, **decimal** for the two averages
   * `platform_item_id` → **String** (it must never be treated as a measure)
3. Rename fields to readable labels (right-click → *Rename*):
   `platform_item_id` → `Item ID`, `chart_weeks` → `Chart Weeks`,
   `markets` → `Markets`, `no1_market_weeks` → `#1 Market-Weeks`.
4. Set the geographic role on `03_market_summary.csv`: right-click `country` →
   *Geographic Role* → **Country/Region**. Tableau will draw a world map.
   `Global` is not a country — it is filtered out on the map sheet, not in the data.
5. **Create the extract**: *Data* → *Extract* → *Create Extract*. Choose *All rows*.
   Do this for every source; Tableau Public needs extracts anyway and dashboards get
   noticeably faster.
6. Hide fields you do not use (right-click → *Hide*) so the Data pane stays clean in
   screenshots. Hide: `platform_item_id` is fine to keep, but hide internal helpers.

### Data source list you should end up with

```
DS_Songs      → 01_song_reach.csv
DS_MarketWeek → 02_market_week.csv
DS_Markets    → 03_market_summary.csv
DS_Leaders    → 04_market_leader.csv
DS_Artists    → 05_artists.csv
DS_Cross      → 06_cross_platform.csv
DS_Creators   → 07_creators.csv
DS_Entries    → 08_entry_status.csv
DS_Season     → 09_seasonality.csv
DS_Concen     → 10_concentration.csv
```

Rename each source in the Data pane so your workbook is readable to anyone opening it.

---

## Step 4 — Calculated fields and the platform parameter

### 4.1 The parameter (this is what makes a multi-source dashboard work)

A normal quick filter only filters the sheet's own data source. With ten sources you need
one control that drives all of them.

1. Data pane → **Create Parameter**:
   * Name: `Platform Selection`
   * Data type: **String**
   * Allowable values: **List** → `All platforms`, `Spotify`, `YouTube`
   * Current value: `All platforms`
2. In **every** data source, create:

```
[Platform Filter]

[Parameters].[Platform Selection] = "All platforms"
OR [Platform] = [Parameters].[Platform Selection]
```

3. On every worksheet: drag `Platform Filter` to **Filters** and select **True**.
   (Right-click the field in Filters → *Apply to Worksheets* → *All Using This Data Source*.)

Now show the parameter control on each dashboard: right-click the parameter in the Data
pane → *Show Parameter*.

### 4.2 The calculated fields

Create these in the source noted. Copy the formulas exactly.

| Field | Data source | Formula | Used by |
|---|---|---|---|
| `Platform Filter` | all | see 4.1 | every sheet |
| `Platform Colour` | DS_Songs, DS_Artists | `IF [Platform] = "Spotify" THEN "#1DB954" ELSE "#E22134" END` | marks colour |
| `Song Label` | DS_Songs | `[Title] + "  ·  " + [Artists]` | tooltips, tables |
| `Is Evergreen` | DS_Songs | `[Chart Weeks] >= 52` | longevity callout |
| `Lag Band` | DS_Songs | see below | release velocity |
| `Avg Weekly Views` | DS_Songs | `[Total Views] / [Chart Weeks]` | views vs rank |
| `Markets per Week` | DS_Songs | `[Markets] / [Chart Weeks]` | scatter |
| `Top 10 Share` | DS_Markets | `[Top10 Observations] / [Observations]` | coverage table |
| `Observation Share` | DS_Entries | `SUM([Observations]) / TOTAL(SUM([Observations]))` | stacked bar labels |
| `Breadth per Market` | DS_MarketWeek | `AVG([Items])` | weekly breadth line |
| `Item Percentile` | DS_Concen | `[Pct Of Items]` | concentration x-axis |
| `KPI Observations` | DS_MarketWeek | `SUM([Observations])` | KPI sheet |
| `KPI Median Lifetime` | DS_Songs | `MEDIAN([Chart Weeks])` | KPI sheet |
| `KPI Items` | DS_Songs | `COUNTD([Platform Item ID])` | KPI sheet |
| `KPI Markets` | DS_Markets | `COUNTD([Market Code])` | KPI sheet |

`Lag Band`:

```
IF ISNULL([Days To First Chart]) THEN "Unknown"
ELSEIF [Days To First Chart] <= 30 THEN "0-30 days"
ELSEIF [Days To First Chart] <= 90 THEN "31-90 days"
ELSEIF [Days To First Chart] <= 180 THEN "91-180 days"
ELSEIF [Days To First Chart] <= 365 THEN "181-365 days"
ELSE "1yr+"
END
```

Number formatting for KPI fields: right-click → *Default Properties* → *Number Format* →
*Custom* → `#,##0` (use `#,##0.0` for medians, `#,##0.0,,"M"` is not needed — keep raw
thousands so the numbers are checkable).

---

## Step 5 — Build the worksheets

Build in this order. Each block is a dashboard; you can publish after block 1 and keep going.
Use **Show Me** only as a starting point — finish every sheet by hand for control.

### 5.1 Block A — six KPI "BAN" sheets (Dashboard 1)

A BAN (big number) is one worksheet per number: no rows, no columns, **Text** mark.

**A1 · Chart Observations**
* Source `DS_MarketWeek`, drag `Platform Filter` to Filters (True).
* Drag `Observations` to **Text**, aggregation `SUM`.
* Format: `#,##0`, font size 30, colour `#111318`.
* Rename sheet `KPI - Observations`.

**A2 · Markets Covered** — `DS_Markets`, **Text** = `COUNTD([Market Code])`, label `markets`.
**A3 · Items Tracked** — `DS_Songs`, **Text** = `COUNTD([Platform Item ID])`, label `songs & videos`.
**A4 · Chart Weeks** — `DS_MarketWeek`, **Text** = `COUNTD([Chart Date])`, label `weekly charts`.
**A5 · Median Chart Lifetime** — `DS_Songs`, **Text** = `MEDIAN([Chart Weeks])`, label `weeks of chart life`.
**A6 · Items Reaching the Top 10** — `DS_Songs`, Filter `[Best Rank] <= 10`, **Text** = `COUNTD([Platform Item ID])`.

For the small caption under each number, add a **second** text field: drag a
calculated literal onto Text, e.g. `"markets"`. Simpler and more consistent: put the caption
in the dashboard as a separate Text object under the tile. Do that — it gives you exact
control over typography.

### 5.2 Block B — Dashboard 1 charts

**B1 · Items by Year** (bar)
* `DS_Songs`; Columns `First Chart Year` (dimension, continuous→discrete), Rows
  `COUNTD([Platform Item ID])`; colour `Platform` with the palette from Step 7.
* Label: mark labels on, `#,##0`.
* Note 2018 is a partial year (starts 3 May) — put that in the subtitle, not the axis.

**B2 · New Items per Year** (line, two series)
* `DS_Songs`; Columns `First Chart Year`, Rows `COUNTD([Platform Item ID])`, colour `Platform`.
* This duplicates B1's information; use it only if you want the trend emphasised.
  If you keep both, make B2 a line and B1 a bar — never two identical charts.

**B3 · Chart Breadth per Market, per Week** (line)
* `DS_MarketWeek`; Columns `Chart Date` (continuous, exact date), Rows `AVG([Items])`,
  colour `Platform`.
* Title: *"How many songs a single market chart carries each week"*. This is the honest
  version of "chart activity over time" — row counts are fixed by chart size.

**B4 · Lifetime Distribution** (100% stacked bar or grouped bar)
* `DS_Songs`; Columns `Lifetime Band`, Rows `COUNTD([Platform Item ID])`,
  colour `Platform`, sort the band field manually:
  `1 week, 2-4 weeks, 5-12 weeks, 13-26 weeks, 27-52 weeks, 53+ weeks`.
* Add label `Percentage of Total` (right-click measure → *Quick Table Calculation* →
  *Percent of Total*, Compute Using `Platform`) if you stack.

**B5 · Entry Status by Year** (stacked bar)
* `DS_Entries`; Columns `Chart Year`, Rows `SUM([Observations])`, colour `Entry Status`
  (5 values). Sort the legend: New entry, Re-entry, Moved up, Moved down, No change.

**B6 · Insight text** — a Text object, not a sheet. See the copy in Step 6.

### 5.3 Block C — Dashboard 2 worksheets

**C1 · Top 20 Songs by Chart Weeks** (bar + table hybrid)
* `DS_Songs`; Rows `Title` (sorted desc by weeks), Columns `[Chart Weeks]`, mark **Bar**.
* Colour by `Platform`. Label: `[Chart Weeks]` + `" wks"`.
* Add `Markets` and `Best Rank` to **Tooltip**.
* Filter: `[Chart Weeks] >= 200` to keep the axis meaningful, or use a Top 20 filter
  (right-click Title → *Filter* → *Top* → by field `Chart Weeks`, Top 20).
* Title: *"Songs that never leave"* — the top song (`lovely`, Billie Eilish & Khalid)
  charted 372 of 400 possible weeks across 36 markets.

**C2 · Reach vs Longevity** (scatter — the most shareable chart in the workbook)
* `DS_Songs`; Columns `[Markets]` (average), Rows `[Chart Weeks]` (average),
  Detail `Item ID`, colour `Platform`, size `SUM([No1 Market-Weeks])`? No — keep size
  constant for honesty; put `#1 Market-Weeks` in the tooltip.
* Tooltip: `Song Label`, `Chart Weeks`, `Markets`, `Best Rank`.
* Add a reference line at `Markets = 20` (Analytics pane → Reference Line) and label the
  quadrants in your subtitle: *"wide reach / long life"*, *"regional evergreen"*.
* Insight to state in the caption: *Karol G and Diamond Platnumz both reach 400 chart
  weeks, but 42 markets vs 14 — same longevity, very different footprint.*

**C3 · Concentration Curve** (line)
* `DS_Concen`; Columns `Top N` (dimension, **log-ish**: because the ranks jump 1→2→5→10…,
  use `Top N` as a discrete dimension and Tableau spaces them evenly, which reads well),
  Rows `AVG([Cumulative Pct])`, colour `Platform`.
* Add a reference line at `Top N = 1000` or annotate the point.
* Caption: *"The top 1,000 Spotify items are 1.4% of all songs and 19.5% of all chart weeks."*

**C4 · Top Artists** (horizontal bar)
* `DS_Artists`; Rows `Artist Name`, Columns `[Chart Weeks]`, colour `Platform`,
  filter Top 10 by `Chart Weeks`.
* This dataset rewards interpretation: Tanzanian and Latin artists dominate YouTube
  weeks, US/UK pop dominates Spotify weeks.

**C5 · Artist Detail Table**
* `DS_Artists`; Rows `Artist Name`, Text: `Items`, `Chart Weeks`, `Markets`, `Best Rank`.
* Sort by `Chart Weeks`. Filter Top 20. Platform filter applies.

**C6 · Evergreen Callout** (KPI, optional)
* `DS_Songs`, filter `[Is Evergreen]`, **Text** = `COUNTD([Platform Item ID])`,
  caption: *"songs that stayed 52+ weeks"* → 1,024 Spotify / 2,341 YouTube.

### 5.4 Block D — Dashboard 3 worksheets

**D1 · Market Map** (filled map)
* `DS_Markets`; *Double-click* `Country`, drag `Country` to **Detail**,
  `SUM([Items])` to **Colour**, `Platform` to Filters/Detail.
* Set Geographic Role to Country/Region (Step 3). Exclude `Global`: filter
  `[Is Country] = True`.
* Colour palette: single-hue green ramp (Spotify) or two maps side by side (one per
  platform) — two small maps is clearer than one confusing blend and looks better in a
  screenshot. Use two sheets: `D1a Spotify map`, `D1b YouTube map`.
* Add `Chart Dates` to the tooltip — a country with few chart weeks will look "smaller"
  than reality. That single tooltip field is what makes the map honest.

**D2 · Market Coverage** (horizontal bar)
* `DS_Markets`; Rows `Country` sorted by `Chart Dates` desc, Columns `[Chart Dates]`,
  colour `Coverage Type` (`Weekly` / `Sampled`).
* Caption: *"36 of 38 Spotify markets are sampled — roughly monthly — not weekly.
  YouTube is weekly in all 44."*

**D3 · Market Leaders** (text table with market filter)
* `DS_Leaders`; Rows `Country`, Text: `Title`, `Artists`, `Weeks`, `Best Rank`.
* Add `Country` as a quick filter (single value list) → it becomes an interactive
  "pick a market" control.
* Great stories to surface: Argentina's leader charted 100 weeks and is local-language
  (`Nunca quise` — Intoxicados); Austria's is German-language. Local repertoire wins
  markets that global charts never show.

**D4 · #1 Positions** (horizontal bar)
* `DS_Songs`; filter `[No1 Market-Weeks] > 0`, Top 10 by `No1 Market-Weeks`,
  Rows `Song Label`, Columns `SUM([No1 Market-Weeks])`, colour `Platform`.
* Caption: *"Dance Monkey held a #1 position in 87 market-weeks; on YouTube the strongest
  video holds 424."*

**D5 · Views vs Best Rank** (scatter)
* `DS_Songs`; filter `[Platform] = "YouTube"` and `[Total Views] > 0`;
  Columns `AVG([Best Rank])`, Rows `AVG([Total Views])`, Detail `Item ID`.
* Set the Row axis to logarithmic (right-click axis → *Logarithmic*).
* Tooltip: `Song Label`, `Total Views`, `Chart Weeks`.
* Caption: *"1.54 trillion weekly views observed; the most-viewed charting video
  (DANCE MONKEY) accumulated 5.49B."*

**D6 · Cross-Platform Overlap** (scatter + reference line)
* `DS_Cross`; Columns `[Spotify Weeks]`, Rows `[YouTube Weeks]`, Detail `Title`,
  colour `Lead Platform`.
* Add a 45° reference line so "above the line" means YouTube-led.
* Caption: *"24,438 of 63,839 Spotify song credits (38.3%) also appear on YouTube —
  a conservative exact-match lower bound."*

**D7 · Release Velocity** (bar)
* `DS_Songs`; Columns `Lag Band` (sorted), Rows `COUNTD([Item ID])` or % of total,
  colour `Platform`.
* Caption: *"73% of Spotify and 72% of YouTube charting items arrive within 30 days
  of release. Median lag: 7 days on YouTube."*

**D8 · Median Days to Chart by Year** (line)
* `DS_Songs`; Columns `First Chart Year`, Rows `MEDIAN([Days To First Chart])`,
  colour `Platform`.
* Watch the 2025 tail: recent items have had less time to chart, so treat the last
  point with care. Say so in the subtitle — that honesty is a hiring signal.

**D9 · Writers and Producers** (two small bar charts)
* `DS_Creators`; Rows `Name`, Columns `SUM([Charting Songs])`, one sheet filtered to
  `Role = "Songwriter"`, one to `Role = "Producer"`, Top 10 each.
* Caption: *"Mauricio Rengifo writes on 235 charting songs; The Cratez produce 230."*

**D10 · Seasonality Heatmap**
* `DS_Season`; Rows `Chart Year`, Columns `Chart Month`, Colour `AVG([Avg Items])`,
  Square marks, `Platform` filter.
* Set month numbers to aliases `Jan … Dec` (right-click `Chart Month` → *Aliases*).
* Caption: *"March is the broadest month (1,904 distinct items per chart date) and October
  the thinnest (1,789) — a 6.4% swing. Charts breathe, but gently."*

### 5.5 Block E — Method sheet

A plain dashboard, no charts: five text blocks and a small table.

* Row counts by table (Spotify 857,000 / YouTube 1,757,972 / unified 2,614,972 / usable 2,614,820).
* Exclusions: 152 YouTube observations with no usable video ID; 48,444 + 20,139
  observations with impossible release dates nulled.
* Sampling: 36 of 38 Spotify markets sampled (~13 weeks/year).
* Matching rule for cross-platform, and why it is a lower bound.
* "Not in the data": genre, audio features, licensing, advertising permission.
* A `DS_Markets` table: platform × market × chart weeks × items.

---

## Step 6 — Assemble the dashboards

### 6.1 Sizing and structure

* **Size: Fixed, 1200 × 900** for the three main dashboards (Tableau Public's default
  viewport is close to this, and it screenshots cleanly at 2×).
* Build with **containers**, not floating objects, so the layout survives on other screens.
* Recommended container recipe for Dashboard 1:

```
Vertical container (whole canvas, white background, 24 px padding)
├── Title text object                (height 64)
├── Subtitle text object             (height 24)
├── Horizontal container  "KPI strip" (height 96, 6 worksheets, equal width)
├── Horizontal container  "row 2"     (height 250)
│   ├── B3 breadth line   (width 1.35×)
│   └── B4 lifetime distribution
├── Horizontal container  "row 3"     (height 250)
│   ├── B1 items by year (width 1×)
│   ├── B5 entry status  (width 1×)
│   └── A6 top-10 BAN    (width 0.6×)
└── Footer text object               (height 22, 10 px, #8B939F)
```

* Right-click the outer container → *Layout* → set padding 24, background white.
* Set each chart's *Fit* to **Entire View**. BAN sheets: *Fit* → *Entire View*, alignment
  centre.

### 6.2 The platform parameter control

Place one `Platform Selection` control in the top-right of each dashboard. Style it as a
compact dropdown (Layout → *Show as* → *Dropdown*), font 10 px. It reads as a product
feature and instantly makes the dashboard feel interactive in a demo.

### 6.3 Dashboard actions

1. **Dashboard → Actions → Add Action → Filter.**
   * Name: `Focus market`
   * Source: the Spotify map (D1a)
   * Target: `D3 Market Leaders`, `D2 Market Coverage`
   * Run on: **Select**; clear selection: *Show all values*
   This turns the map into a navigation device — the single most impressive interaction
   in the workbook.
2. **Add Action → Highlight** from `C4 Top Artists` to `C5 Artist Detail` so clicking an
   artist bar highlights their row.
3. **Add Action → Go to Sheet**: clicking a song in `C1` opens Dashboard 2. Optional,
   but it makes a recorded walkthrough feel like an app.

### 6.4 Titles and insight copy (use these verbatim or rewrite in your voice)

| Dashboard | Title | Sub-headline |
|---|---|---|
| 1 | Global Music Intelligence | 400 weekly charts · 82 market charts · 2.61M chart observations, May 2018 – Dec 2025 |
| 1 | (insight strip) | *"Most chart entries are one-week events: 41% of Spotify songs appear exactly once. The winners are not launches — they are holdings."* |
| 2 | Song & Artist Intelligence | Reach and longevity are different assets. Score both before you sign or pitch. |
| 2 | (insight) | *"Top 1,000 Spotify songs — 1.4% of all songs — hold 19.5% of all chart weeks."* |
| 3 | Market & Platform | Where the depth is, who owns the top slot, and how fast attention decays |
| 3 | (insight) | *"Attention falls 5.5× between the top 10 and ranks 51–100 — mid-chart is still valuable, and most songs never cross platforms at all."* |
| 4 | Method & Data Quality | Every number traceable: PostgreSQL → SQL → CSV → viz |

---

## Step 7 — Formatting system

A consistent system is the difference between "student project" and "hired".

### Palette

| Token | Hex | Use |
|---|---|---|
| Canvas | `#FFFFFF` | dashboard background |
| Card | `#F7F8FA` | panel backgrounds, KPI tiles |
| Ink | `#111318` | titles, key numbers |
| Body | `#3D4450` | labels, table text |
| Muted | `#8B939F` | captions, footer, axis text |
| Grid | `#E6E8EC` | gridlines, dividers |
| Spotify | `#1DB954` | Spotify marks |
| YouTube | `#E22134` | YouTube marks |
| Neutral | `#7C9EFF` | single-series charts, accents |
| Warn | `#E0B95F` | sampled-market callouts |

### Typography

* One family: **Tableau Book** (built in) or **Inter** if available in your Tableau version.
* Titles 28 px semibold, section titles 13 px semibold, axis/labels 10 px, KPI numbers 30 px.
* Numbers: right-aligned, `#,##0`; percentages one decimal.
* Never use more than three font sizes on one dashboard.

### Chart hygiene checklist

* Gridlines: off on bar charts, faint `#E6E8EC` on line charts only.
* Zero line: keep on bars, hide on scatter.
* Axis titles: sentence case, units included ("Chart weeks", not "SUM(Chart Weeks)").
* Remove the "Measure Names" pill if it appears; use colour legends instead.
* Tooltips: rewrite every one — `Song · Artist`, then 2–3 labelled numbers. Default
  tooltips with `SUM(...)` in them look unfinished.
* Legend placement: under the title, horizontal, max 2 items (plus entry status).
* Annotate one data point per chart. One annotation per chart is the single biggest
  perceived-quality upgrade you can make.

---

## Step 8 — Validation (do not skip)

Filter `Platform Selection = All platforms` and confirm each number. If any row is off,
you have joined two grains together — undo the join and use separate sources.

| Metric | Expected value |
|---|---|
| Total chart observations | **2,614,820** |
| Spotify / YouTube observations | **857,000 / 1,757,820** |
| Chart dates | **400** (3 May 2018 – 25 Dec 2025) |
| Markets | **82 rows**: 38 Spotify, 44 YouTube |
| Items tracked | **184,616** (73,942 Spotify / 110,674 YouTube) |
| Median chart lifetime | **2 weeks** Spotify, **3 weeks** YouTube |
| Songs lasting 52+ weeks | **1,024** Spotify, **2,341** YouTube |
| Longest-running song | `lovely` — **372** weeks, 36 markets (Spotify) |
| Longest-running video | `Waka Waka` — **239** weeks (YouTube) |
| Top 1,000 items' share of chart weeks | **19.5%** Spotify, **7.9%** YouTube |
| Total YouTube weekly views observed | **1,544,272,830,732** (1.54T) |
| Most-viewed charting video | `DANCE MONKEY` — **5.49B** |
| #1 market-weeks | **4,285** Spotify / **17,601** YouTube; max 87 / 424 |
| Cross-platform matches | **24,438** of 63,839 Spotify credits (**38.3%**) |
| Items charting within 30 days of release | **73%** Spotify, **72%** YouTube |
| Median days from release to first chart (items first charting in 2025) | **20** days Spotify, **7** days YouTube (all years: 17 / 7) |
| New + re-entry share of Spotify rows | **11.1%** (2018) → **13.1%** (2025) |
| Seasonality range | March **1,904** vs October **1,789** items per chart date |
| Median weekly views | **542,642** (top 10) → **98,500** (51–100) |

---

## Step 9 — Publish to Tableau Public

1. Rename the workbook: `Global Music Intelligence — Spotify & YouTube Charts 2018-2025`.
2. Hide sheets you do not want visible (right-click sheet tab → *Hide*); keep the three
   dashboards and the method sheet.
3. **Server → Tableau Public → Save to Tableau Public.** Sign in.
4. In the publish dialog:
   * Title: the same descriptive name.
   * Description: *"Weekly Spotify & YouTube chart performance across 82 market charts,
     2018–2025. Built in PostgreSQL + SQL, visualised in Tableau."*
   * Add tags: `music`, `spotify`, `youtube`, `data analysis`, `dashboard`.
   * Allow download: **yes** — recruiters do download workbooks, and it proves the build
     is real.
5. After publishing, open the viz on the web and check:
   * All three dashboards load and the parameter works.
   * The map renders (Tableau Public sometimes needs a reload for the first map render).
   * Set a **featured viz** on your profile — pick Dashboard 2 or 3, not the exec overview.
   * Add a **mobile layout** (Dashboard → *Device Preview* → Phone) so the link works on
     a recruiter's phone. Five minutes, disproportionate payoff.
6. Copy the public URL. That URL goes in your résumé, LinkedIn featured section and README.

### Screenshot set for LinkedIn and GitHub

Export at a larger size for crispness:

1. Duplicate each dashboard, set size to **2,400 × 1,800**, *Fit: Entire View*.
2. **Dashboard → Export Image** → PNG.
3. Save into `tableau/dashboard_screenshots/` — `01_executive.png`,
   `02_song_artist.png`, `03_market_platform.png`, `04_method.png`.
4. Also export one **zoomed detail** (the reach-vs-longevity scatter) on its own — that is
   your carousel image, because scatter plots read well small.

---

## Step 10 — Make it work for you

The dashboard is the evidence; this is the campaign. A good viz with no distribution gets
zero interviews.

### 10.1 GitHub and portfolio site

* Add to `README.md`, right under the intro:

```markdown
[![Global Music Intelligence dashboard](tableau/dashboard_screenshots/01_executive.png)](https://public.tableau.com/app/profile/YOUR_PROFILE)

**[▶ Open the interactive dashboard on Tableau Public](https://public.tableau.com/app/profile/YOUR_PROFILE)**
```

* Keep the repository's README structure: problem → data → method → findings → dashboard
  → limitations. Recruiters spend 60 seconds; the findings section is what they read.
* Embed the viz on a personal site with Tableau Public's embed code (Share → Embed Code).
* Record a **45-second screen capture** (OBS or Loom) of you using the parameter and the
  map action. A GIF at the top of the README outperforms any screenshot.

### 10.2 LinkedIn post (copy, then make it yours)

> **I rebuilt 2.6 million chart rows to answer one question: why do some songs last?**
>
> I pulled eight years of weekly Spotify and YouTube chart data for 82 markets — 2018 to
> 2025 — cleaned it in PostgreSQL, and built a Tableau workbook to interrogate it.
>
> Three things surprised me:
>
> 1. **Charts are not launch pads, they are holding patterns.** 41% of songs that chart on
>    Spotify appear exactly once. The median song lasts two weeks.
> 2. **Success is brutally concentrated.** The top 1,000 Spotify songs — 1.4% of everything
>    that ever charted — account for 19.5% of all chart weeks. On YouTube the same group
>    holds 7.9%. Same music, different attention economy.
> 3. **Reach and longevity are different assets.** Karol G and Diamond Platnumz both spend
>    400 weeks on chart. One does it across 42 markets, the other across 14. A hit in one
>    country and a global catalogue are not the same achievement.
>
> I also found a data-quality trap worth naming: 36 of 38 Spotify "country" charts are
> sampled roughly monthly, while YouTube is weekly everywhere. Any cross-platform
> comparison that ignores that is measuring sampling, not music.
>
> Full interactive dashboard: [link]  ·  Code and SQL: [GitHub link]
>
> Data: National Music Charts (Zenodo, CC BY 4.0). Built with PostgreSQL, SQL and Tableau.
>
> #DataAnalytics #Tableau #SQL #DataVisualization #MusicIndustry

Post tactics:

* Post **Tuesday–Thursday, 8–10 am** your local time.
* Attach **4 images** (three dashboards + the scatter). LinkedIn shows the first image
  large — use the executive overview.
* Put the link in the **first comment**, not the post body. Outbound links suppress reach.
* Reply to every comment in the first two hours; that is what actually drives distribution.
* Tag nothing and nobody you have not spoken to. Use 3–5 hashtags, not 15.

### 10.3 Carousel (document post) — 9 slides

1. Title: *"What 2.6M chart rows taught me about hit songs"*
2. The dataset: 82 markets, 400 weeks, 184,616 songs and videos
3. Method: PostgreSQL → SQL → validated CSVs → Tableau (small pipeline diagram)
4. Finding 1: 41% appear once; median life 2 weeks
5. Finding 2: top 1.4% of songs = 19.5% of chart weeks
6. Finding 3: reach ≠ longevity (Karol G vs Diamond Platnumz)
7. Finding 4: attention decays 5.5× down the chart
8. Finding 5: the sampling trap (36 of 38 Spotify markets are monthly)
9. What I would do next + link + your name/handle

### 10.4 Résumé bullets

> **Global Music Intelligence — Music Chart Analytics (PostgreSQL, SQL, Tableau)**
> * Built an end-to-end analytics project on 2.61M Spotify and YouTube chart observations
>   across 82 markets (2018–2025); designed a staging → clean → analytics PostgreSQL model
>   with typed casting, deduplication and artist normalization.
> * Diagnosed and fixed a silent data-loss defect where decimal-formatted source values
>   failed an integer cast, restoring 1.76M YouTube view and weeks-on-chart records.
> * Delivered a 3-dashboard Tableau Public workbook; surfaced that the top 1.4% of songs
>   capture 19.5% of all Spotify chart weeks and that 73% of charting songs arrive within
>   30 days of release.

### 10.5 Interview answers (rehearse these five)

1. **"Walk me through this project."** Problem → data → grain decisions → defect found →
   three findings → what you would do with more time. Ninety seconds, no tool names until
   the end.
2. **"Why did you keep streams and views separate?"** Because they measure different
   things; summing them would create a number that means nothing. I kept `metric_type`
   in the model so the distinction is enforced in the data, not just in my head.
3. **"How did you validate?"** A fixed reference table of 19 metrics produced by SQL, then
   re-checked in Tableau. I can show you the query behind every number.
4. **"What is the biggest weakness?"** Sampling: Spotify country charts are ~13 weeks a year
   against YouTube's 52, so cross-platform longevity is not like-for-like. I show weeks
   observed on the market panel instead of hiding it.
5. **"What would you do next?"** Add a proper cross-platform entity resolution step with
   confidence scoring, bring in a second source for genre and licensing, and move the
   pipeline to a scheduled dbt + warehouse model so the dashboard refreshes itself.

### 10.6 Fourteen-day launch plan

| Day | Action |
|---|---|
| 1–2 | Build Dashboard 1 and publish a "work in progress" (no post) |
| 3–4 | Build Dashboard 2; export the scatter |
| 5–6 | Build Dashboard 3 and the method sheet |
| 7 | Validation pass, formatting pass, mobile layout |
| 8 | Publish, write the README, add screenshots |
| 9 | Record the 45-second walkthrough |
| 10 | Post the LinkedIn text post with 4 images |
| 11 | Post the carousel as a document post (rewrite the hook) |
| 12 | Comment thoughtfully on 10 Tableau/analytics posts — visibility follows participation |
| 13 | Submit to Tableau Public "Viz of the Day" and r/dataisbeautiful |
| 14 | Update résumé, LinkedIn featured section, GitHub profile README |

### 10.7 Things not to claim

* Do not say "most streamed" — you have chart presence and rank, not global stream totals.
* Do not say "popular = good for brand X" — the data has no brand, genre or licensing
  information.
* Do not present the 38 Spotify markets as a complete country set — they are the markets
  this dataset covers.
* Always credit the source (CC BY 4.0). It is both a legal requirement and a credibility
  signal.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Totals are far too large | Two files joined (song grain × market-week grain) | Keep them as separate data sources; never join |
| "Publish to Tableau Public" missing | Wrong edition installed | Install **Desktop Public Edition**; Free Edition cannot publish |
| Map is empty / has unknown locations | `Global` treated as a country, or wrong geographic role | Set role Country/Region on `country`; filter `Is Country = True` |
| Dates sort as text | CSV column inferred as string | Change data type to Date on the Data Source page, then refresh the extract |
| Parameter changes nothing | Field added to Filters before `Platform Filter` calc existed | Use the `Platform Filter` calculated field, set filter to True |
| `avg_rank` looks like a constant ~100.5 | It *is* constant: every chart is full (200/100 rows) | Do not chart mean rank. Use top-10 counts, best rank or lifetime |
| Turkish/accented characters break | Encoding | Tableau reads UTF-8 by default; if not, set the file's *Text File Properties* encoding to UTF-8 |
| Dashboard slow on Tableau Public | Live CSV, too many marks | Use extracts, aggregate to the exported grains, avoid scatter with 184k marks (filter to Top N) |
| Scatter shows 184,616 points | No aggregation | Put `Markets`/`Chart Weeks` as AVG and `Item ID` on Detail |

---

## Appendix A — Field dictionary (the fields you will actually use)

`01_song_reach.csv`

| Field | Meaning |
|---|---|
| `platform` | `Spotify` or `YouTube` |
| `platform_item_id` | track or video identifier (string, never a measure) |
| `title`, `artists`, `primary_artist` | song title, full credit string, first credited artist |
| `chart_weeks` | distinct chart dates the item appears on, all markets |
| `markets` | distinct markets the item appears in |
| `avg_rank`, `best_rank`, `no1_market_weeks` | position statistics |
| `first_chart_date`, `last_chart_date` | first and last appearance |
| `release_date`, `days_to_first_chart` | release and release-to-first-chart lag |
| `first_chart_year` | year of first appearance (use for "new items") |
| `total_streams`, `total_views`, `peak_week_views` | platform-specific volume; never added together |
| `weeks_per_market`, `lifetime_band` | derived convenience fields |

`02_market_week.csv`: `platform, market_code, country, chart_date, chart_year, chart_month, chart_month_label, observations, items, top10_observations`

`03_market_summary.csv`: `+ chart_dates, top10_share_pct, first_date, last_date, coverage_type, is_country`

`04_market_leader.csv`: `platform, market_code, country, title, artists, weeks, best_rank`

`05_artists.csv`: `platform, artist_name, items, chart_weeks, markets, avg_rank, best_rank, weeks_per_market`

`06_cross_platform.csv`: `title, artists, spotify_weeks, youtube_weeks, spotify_best, youtube_best, spotify_markets, youtube_markets, combined_weeks, lead_platform`

`07_creators.csv`: `role, name, charting_songs`

`08_entry_status.csv`: `chart_year, entry_status, observations`

`09_seasonality.csv`: `chart_year, chart_month, platform, avg_items, chart_dates`

`10_concentration.csv`: `platform, top_n, total_items, total_weeks, pct_of_items, cumulative_pct`

## Appendix B — Which repository file produces which number

| Workbook element | Source of truth |
|---|---|
| All CSVs | `python/export_tableau_data.py` |
| Business query definitions | `analysis/02_business_queries.sql` (26 tagged queries) |
| Clean tables and flags | `python/clean_data.py`, `database/06_standardize_artists.sql` |
| Unified view | `database/database/09_create_unified_dataset.sql` |
| Cross-check dashboard | `python/export_dashboard_data.py` + `dashboard/` (HTML version) |

If a Tableau number and a SQL number ever disagree, the SQL is right — the CSV is a
projection of it.

---

## Appendix C — If you only have one evening

Build in this order and stop when you run out of time. Each step is independently
publishable.

1. `01_song_reach.csv` connected, extract created (15 min)
2. Six KPI BAN sheets (40 min)
3. `C1` top songs bar, `C2` reach-vs-longevity scatter, `B4` lifetime distribution (60 min)
4. Dashboard 2 assembled with the platform parameter (40 min)
5. Publish, screenshot, one LinkedIn post (30 min)

That is a credible, defensible portfolio piece. Everything else is upside.
