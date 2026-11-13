# Sensor quality and background

Summary: rules the AI must apply in **every** analysis that uses low-cost sensor
data, and how to compare sensors with the background (what the air would be
without local sources). Based mainly on Wesseling et al. (2024), *Air Quality,
Atmosphere & Health* 17: 979–996, doi:10.1007/s11869-023-01493-z.
`sensors.md` explains sensors to residents; this file tells the AI what to check.

> **For the air-quality expert:** thresholds marked `[set]` are to be decided by
> you. Start with the suggested values and adjust after testing.

---

## 1. Core principle

Low-cost sensors show **patterns** well but **single values** poorly. Even after
calibration a sensor still scatters, so individual readings have limited use.
Therefore:

- Prefer **groups of sensors** over one sensor.
- Prefer **daily or longer averages** over hourly values.
- Always compare with the **background** (section 4) before drawing conclusions.

## 2. Fixed sensor check (workflow step 3b)

Run these checks after `check_data_coverage` and before any analysis. Each is a
tool; R does the detection, the AI only reads and reports the outcome.

| # | Problem | Tool | Rule |
| --- | --- | --- | --- |
| 1 | **Broken sensor**: stuck value, near zero, or constantly very high | `detect_faulty_sensors` | Exclude the sensor; log the reason; tell the resident in one sentence |
| 2 | **Humidity**: optical sensors read too high in damp conditions | `flag_high_humidity` | Use calibrated values. If more than `[set: 20]`% of hours are flagged, mention it in "How sure are we?" |
| 3 | **Drift and ageing**: a sensor slowly moves away from its neighbours | `compare_with_neighbours` | If a sensor's difference from the neighbour median changes by more than `[set]` µg/m³ over the period, flag it and say its trend is unreliable |
| 4 | **Sensor-to-sensor differences**: identical sensors can behave differently | `compare_with_neighbours` | Do not rank sensors on differences smaller than `[set]` µg/m³ (daily mean) |
| 5 | **Random noise**: cannot be removed by calibration | – | Never interpret a single hourly value; use daily means or longer |
| 6 | **Placement**: most sensors sit at homes, not at background locations | `get_background` | If one sensor is much higher than both neighbours and background, mention placement as a possible reason |
| 7 | **Outlier removal can remove real peaks** | `filter_outliers` (T1) | Always report what was removed; for anomaly questions, show the removed values too |

## 3. Calibration

- Always use **calibrated** sensor values from Samen Meten when available.
- Samen Meten's calibration is a **network calibration** against reference
  stations. Wesseling et al. (2024) found that the RIVM method gives a robust
  average for the network but tolerates a few poorly corrected sensors. That is a
  further reason to report on groups of sensors rather than one sensor.
  `[verify the current calibration method and data field with RIVM]`
- Uncertainty ranges from bootstrapping the calibration are a possible future
  addition (not in the hackathon scope).

## 4. Background ("what would the air be without local sources?")

Comparing a sensor with the background separates **regional** pollution (the same
for everyone in the region, e.g. from abroad or weather) from **local** pollution
(e.g. a road, wood stove or construction site).

**Local increment = sensor value − background value (same hour or day).**

### Sources, in order of preference

| # | Source | What it is | Time resolution | Space | Use for |
| --- | --- | --- | --- | --- | --- |
| 1 | **Regional background reference station** (Luchtmeetnet) | Official measurement at a background location | Hourly | One point | Standard baseline for every comparison |
| 2 | **CAMS European air quality analysis / reanalysis** (Copernicus) | Model ensemble combined with measurements | Hourly | ~10 km grid | Baseline where no background station is near; consistency check |
| 3 | **GCN maps** (RIVM, Grootschalige Concentratiekaarten Nederland) | Model + measurements, yearly average | Year | 1 × 1 km | "Is this area above the typical yearly background?" |
| 4 | **RIVM hourly concentration maps** (Luchtmeetnet website) | Interpolation of measurements | Hourly | Fine grid | Visual comparison; check whether historical data can be downloaded `[verify]` |

Not suitable as a baseline: **forecasts** (e.g. KNMI LOTOS-EUROS forecasts). They
predict, they do not describe what happened.

### Rules for using the background

- State which background source was used in the audit trail.
- Use the **same averaging period** for sensor and background.
- A model is a **reference, not the truth**: at ~10 km, CAMS cannot see a single
  street. Say so when using it.
- If the sensor group is lower than the background for long periods, suspect a
  calibration problem rather than very clean air.

## 5. Known issues in the Hollandse Luchten dataset

Found by profiling `data_sensors.parquet` (521 kits, hourly, Jan 2020 – Dec 2025,
5.7 million rows) and `metadata_sensors.parquet` (569 kits). Use these as concrete
rules in `detect_faulty_sensors` and the data preparation. `[expert to confirm]`

| Issue | What the data shows | Rule |
| --- | --- | --- |
| Two sensor types | 313 kits Sensirion SPS30, 208 kits Nova SDS011 (`pm25_sensor` in metadata) | Always join metadata; report results per sensor type when both are present; never rank an SDS011 against an SPS30 without saying so |
| Stuck at maximum | `pm25_raw = 344.54` in 0.9% of rows; one kit for 13,417 hours | Treat 344.54 as an error value, not a measurement |
| Stuck at zero | `pm25_raw = 0` in 3.7% of rows; several kits for 6,000–15,000 hours | Runs of 0 for ≥ 24 h = faulty sensor |
| Other stuck values | 547 runs of ≥ 24 identical hourly values, in 117 kits | Flag any run ≥ 24 h `[set]` |
| Impossible values | `pm25_raw` up to 41,433; 1,985 rows above 1,000 | Exclude values above `[set: 1000]` µg/m³ |
| Error code in temp/rh | `655.35` in temp (18,834 rows) and rh (32,777 rows); temp down to −148 °C | Treat 655.35 as missing; temp outside −30…50 °C = missing |
| Wrong locations | 32,676 rows in 63 kits outside the Netherlands (lat/lon 0, or up to 78° N) | Use the kit's most common location; drop rows outside the study area |
| Means distorted by faults | June 2022: mean `pm25_kal` 32.8 vs median 6.1 µg/m³ | Run the sensor check **before** averaging; also report the median |
| Calibration and humidity | Median `pm25_kal / pm25_raw` is about 1.0 when rh > 70%, and higher at low rh | `[ask RIVM]` how the calibration treats humidity before relying on calibrated values in damp periods |
| Kits without data | 48 kits in metadata have no measurements | Ignore them in coverage counts |

Data columns: `kit_id`, `timestamp_from`, `timestamp_to` (hourly), `pm25_raw`,
`pm10_raw`, `pm25_kal` (calibrated, 98% filled), `temp`, `rh`, `pres` (5% filled),
`latitude`, `longitude`. Not in the dataset: wind, reference stations,
background. These must come from KNMI and Luchtmeetnet.

## 6. Ready-made sentences

- "Sensor `[name]` was left out because it gave the same value for `[n]` hours in
  a row, which points to a fault."
- "On `[n]`% of the hours the air was very damp. These sensors then tend to read
  too high, so the real values were probably somewhat lower."
- "Your street was on average `[x]` µg/m³ above the regional background. That
  part is probably caused by sources nearby."
- "The difference between these sensors is smaller than what we can reliably
  measure with them, so we cannot say which one is really higher."
