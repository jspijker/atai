# Allowed functions (tools)

Summary: the only tools the AI may call, in two tiers. **Tier 1** wraps the
validated Samen Analyseren (Analyse-Together) functions and is always the first
choice. **Tier 2** wraps functions from the established `openair` R package, for
analyses Tier 1 does not offer. The AI picks tools and parameters; R does all
calculations and writes the audit log.

## Selection rules

1. **Data selection, calibration and outlier filtering always use Tier 1.** These
   steps are specific to Samen Meten sensors, and the validated RIVM method should
   be used.
2. **For the analysis itself, use Tier 1 if a function exists**, otherwise Tier 2.
3. **Never use anything outside these two tiers.** The AI does not write new
   analysis code. If no tool fits, say so.
4. **Every step logs its tier, package and version**, so the jury and the resident
   can see which steps used validated RIVM functions and which used openair.

> **For the R developer:** Tier 1 tools are implemented in `scripts/run_analysis.R`,
> adapting the data-handling logic from github.com/rivm-syso/Analyse-Together
> (GPL-3). Parquet is read with `nanoparquet`; Tier 2 tools call `openair`.
>
> Analyse-Together: data-handling logic adapted (not vendored) · openair 3.x

## Data format for openair

openair expects one data frame with:
- `date` – date-time (POSIXct, timezone set explicitly, e.g. `Etc/GMT-1`)
- pollutant columns, e.g. `pm25`, `pm10`, `no2`
- `site` – sensor or station ID (for comparisons between locations)
- `ws`, `wd` – wind speed and wind direction, **only needed for wind tools**
  (source: KNMI hourly data for the nearest weather station `[verify source]`)

The bridge tool `to_openair_format` converts Tier 1 output into this format.

> **What this dataset can and cannot answer.** `data_sensors.parquet` has
> `pm25_raw`, `pm25_kal` (calibrated) and `pm10_raw` only:
> - **NO2 is not available** – reject or re-scope `no2` questions.
> - **PM10 has no calibrated field** – only raw PM10; say so and prefer PM2.5.
> - `pm1` is not in the data either.
> Wind (`ws`/`wd`) comes from KNMI, background from the reference stations; both
> are committed in `data/`, while the two sensor files come from Zenodo at runtime.

---

## Format per tool

- **Tool name** · **Tier** · **Wraps** · **Purpose** · **Inputs** · **Output** ·
  **Use when** · **Limitations**

---

## Tier 1 – Samen Analyseren (validated, first choice)

### check_data_coverage
- **Wraps**: `[real function or helper]`
- **Purpose**: How complete the data is per sensor for the period. Always first.
- **Inputs**: `sensor_ids`, `start_date`, `end_date`, `parameter` (default `pm25`)
- **Output**: % hourly values present, longest gap, first/last measurement.

### get_sensor_data
- **Wraps**: `[real data-selection function]`
- **Purpose**: Retrieve hourly measurements, calibrated where available.
- **Inputs**: `sensor_ids`, or `area` as `lat`/`lon` + `radius_km`, dates,
  `parameter`, `calibrated` (default yes)
- **Output**: dataset ID + count of sensors and measurements.
- **Note**: R selects sensors by distance, so it needs a centre as `lat`/`lon`,
  not a postcode. A postcode alone is rejected. When the resident gives a
  postcode, resolve it to a centre point **when you write the plan** and put
  `lat`/`lon` in `area` (keep `postcode` for the reader). Use the helper:
  `python scripts/postcode_to_latlon.py "<postcode>"` (PDOK Locatieserver).

### get_reference_data
- **Wraps**: `[real function for official network data]`
- **Purpose**: Retrieve data from official reference stations (Luchtmeetnet).
- **Inputs**: `station_id` or `nearest_to` (postcode), dates, `parameter`

### filter_outliers
- **Wraps**: `[real outlier-filter function]`
- **Purpose**: Remove values that are very likely measurement errors.
- **Inputs**: `dataset_id`, `method` (default: the tool's default)
- **Output**: new dataset ID; number and % removed per sensor.
- **Limitations**: real peaks (e.g. New Year's Eve) can look like outliers; report
  when more than 5% is removed.

### Sensor-quality tools (step 4, see `sensor-quality.md`)
Use the Samen Analyseren function if one exists; otherwise these are small new
R helpers, documented and tested by the team.

| Tool | Wraps | Purpose |
| --- | --- | --- |
| `detect_faulty_sensors` | `[T1 function or new helper]` | Find stuck, near-zero or constantly extreme sensors |
| `flag_high_humidity` | `[T1 function or new helper]` | Mark hours with relative humidity above `[set: 85]`% |
| `compare_with_neighbours` | `[T1 function or new helper]` | Difference of each sensor from the median of nearby sensors, over time |

### get_background
- **Wraps**: `get_reference_data` for a regional background station (default),
  or a CAMS download (stretch goal), or the GCN map value for the location.
- **Purpose**: background concentration for the same period, to compute the local
  increment (sensor − background).
- **Inputs**: `area` or `sensor_ids`, dates, `parameter`, `source`
  (`station` default, `cams`, `gcn`)
- **Output**: background time series (or yearly value for GCN) + source name for
  the audit trail.

### Tier 1 analysis and charts
- `plot_timeseries`, `plot_pollution_rose`, `bar_chart`, … `[fill in what exists]`

### to_openair_format (bridge)
- **Purpose**: convert a Tier 1 dataset (after filtering) into openair format,
  optionally joining KNMI wind data.
- **Inputs**: `dataset_id`, `add_wind` (yes/no)

---

## Tier 2 – openair (established package, second choice)

| Tool | Wraps (openair) | Answers questions like | Key settings | Limitations |
| --- | --- | --- | --- | --- |
| `average_over_time` | `timeAverage()` | "What's the average in our area?" | `avg.time` (`day`, `month`, `year`); `data.thresh` = minimum % data per period (default 75) | Averages hide peaks |
| `plot_over_time` | `timePlot()` | "How do Jan and Dec compare?" | `avg.time`, `pollutant`, `type = "site"` | Shows, does not test |
| `daily_weekly_pattern` | `timeVariation()` | "Is it better on weekends?", "Which hours are worst?" | `pollutant`, `group = "site"` | Needs ≥ 2 months for stable patterns |
| `trend_with_uncertainty` | `TheilSen()` | "Is air quality improving this year?" | `deseason = TRUE`, `avg.time = "month"` | Needs ≥ 2–3 years for a reliable trend; returns slope with confidence interval |
| `smooth_trend` | `smoothTrend()` | Visual long-term trend | `deseason = TRUE` | Visual only |
| `calendar_view` | `calendarPlot()` | "Were there unusual days last month?", "On which days was a value exceeded?" | `pollutant`, `year`, `month`, `breaks` | Daily means; no hourly peaks |
| `source_direction` | `polarPlot()` | "Does it come from the construction site / factory?" | `pollutant`, `x = "ws"` | Needs wind data and several weeks; shows direction, not cause |
| `pollution_rose` | `pollutionRose()` | Same, simpler view | `pollutant` | Same as above |
| `high_values_by_direction` | `percentileRose()` | "From which direction do the peaks come?" | `percentile = c(50, 95)` | Same as above |
| `compare_with_reference_stats` | `modStats()` | "How good is my sensor vs. the official station?" | `mod` = sensor, `obs` = reference | Requires same period and averaging |
| `scatter_vs_reference` | `scatterPlot()` | Same, as a chart | `x` = reference, `y` = sensor | — |
| `data_overview` | `summaryPlot()` | "What data do we have?" | — | Overview only |

**Not supported by either tier (answer honestly):**
- Forecasts ("next week") → refer to official forecasts.
- Proving a cause → explain what the direction analysis can and cannot show.
- Health advice for individuals → refer to GGD or GP.
