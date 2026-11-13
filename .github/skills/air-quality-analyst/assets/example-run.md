# Example run: what passes between the steps

Summary: one question followed through every step, showing the exact shape of
what each step hands to the next. Use as expected output when testing. All
numbers and sensor names are invented to show the format.

**Resident asks:** "Was the air worse in January than in December, near postcode 1971?"

## Step 1 – Research Analyst (AI) classifies the question

```json
{
  "question_type": "temporal_comparison",
  "recipe": "R2",
  "pollutant": "pm25",
  "area": {"postcode": "1971", "radius_km": 1},
  "periods": [
    {"label": "December", "start": "2025-12-01", "end": "2025-12-31"},
    {"label": "January",  "start": "2026-01-01", "end": "2026-01-31"}
  ],
  "assumptions": ["radius 1 km (default)", "most recent Dec–Jan"],
  "clarification_needed": false
}
```

## Step 2 – Plan

To the resident: "I'll compare the sensors within 1 km of postcode 1971 for
December and January. I'll first check that the sensors work properly and leave
out obvious measurement errors. I'll also compare with the regional background
station. Shall I go ahead?" → **Go ahead**

Resolve the postcode to a centre point first:
`python scripts/postcode_to_latlon.py 1971` → `52.458304 4.624960`.

To R (validated against `schemas/plan.schema.json`):

```json
{
  "plan_id": "P-2026-11-13-0042",
  "question_type": "temporal_comparison",
  "recipe": "R2",
  "pollutant": "pm25",
  "area": {"postcode": "1971", "lat": 52.458304, "lon": 4.624960, "radius_km": 1},
  "periods": [
    {"label": "December", "start": "2025-12-01", "end": "2025-12-31"},
    {"label": "January",  "start": "2026-01-01", "end": "2026-01-31"}
  ],
  "steps": [
    {"tool": "check_data_coverage",     "tier": 1},
    {"tool": "get_sensor_data",         "tier": 1, "params": {"calibrated": true}},
    {"tool": "detect_faulty_sensors",   "tier": 1},
    {"tool": "flag_high_humidity",      "tier": 1, "params": {"threshold_rh": 85}},
    {"tool": "compare_with_neighbours", "tier": 1},
    {"tool": "filter_outliers",         "tier": 1, "params": {"method": "default"}},
    {"tool": "get_background",          "params": {"source": "station"}},
    {"tool": "to_openair_format"},
    {"tool": "plot_over_time",          "tier": 2, "params": {"avg_time": "day"}},
    {"tool": "average_over_time",       "tier": 2, "params": {"avg_time": "month", "data_thresh": 75}}
  ],
  "approved_by_resident": true
}
```

## Step 3 – Data check (R → AI)

```json
{
  "tool": "check_data_coverage",
  "sensors_found": 5,
  "coverage_pct": {"HLL_101": 98, "HLL_102": 97, "HLL_215": 95, "HLL_312": 99, "HLL_330": 68},
  "verdict": "ok",
  "warning": "HLL_330 below 75% in January"
}
```

## Step 4 – Sensor check and background (R → AI)

```json
{
  "detect_faulty_sensors":   {"excluded": ["HLL_312"], "reason": "same value for 52 hours (12–14 Jan)"},
  "flag_high_humidity":      {"hours_flagged_pct": 18},
  "compare_with_neighbours": {"flagged": [], "max_drift_ugm3": 1.1},
  "filter_outliers":         {"removed": 37, "removed_pct": 1.3},
  "get_background":          {"source": "Luchtmeetnet regional background station [name]", "coverage_pct": 100}
}
```

## Step 5 – Analysis (R, openair → Interpreter)

```json
{
  "average_over_time": {
    "December": {"sensors_mean": 12.4, "background": 10.9, "local_increment": 1.5},
    "January":  {"sensors_mean": 9.8,  "background": 8.6,  "local_increment": 1.2}
  },
  "highest_days": [{"date": "2026-01-01", "value": 48.2}, {"date": "2025-12-31", "value": 31.5}],
  "chart": "run_0042_timeseries.png",
  "unit": "µg/m³"
}
```

## Audit log (written by R, one line per step)

```text
0042 | 11:42:03 | get_sensor_data   | T1 | Analyse-Together a1b2c3d | sensors=5, hours=7440, calibrated=yes
0042 | 11:42:05 | detect_faulty     | T1 | helper v0.1              | excluded HLL_312 (stuck 52 h)
0042 | 11:42:06 | filter_outliers   | T1 | Analyse-Together a1b2c3d | removed 37 (1.3%)
0042 | 11:42:07 | get_background    | –  | Luchtmeetnet             | station [name], coverage 100%
0042 | 11:42:09 | average_over_time | T2 | openair [version]        | avg=month, data.thresh=75
```

## Step 6 – Interpreter (AI) writes the answer

> **In January, fine dust near your postcode was lower than in December: 9.8
> versus 12.4 micrograms per cubic metre.** The regional background was also lower
> (8.6 versus 10.9), so most of the drop came from the weather and the wider
> region, not from changes nearby. The highest values were on 31 December and
> 1 January, around New Year's Eve.
>
> **How sure are we?** One sensor was left out because it gave the same value for
> two days, which points to a fault. Another had data for only 68% of January. On
> 18% of the hours the air was very damp, when these sensors tend to read too high.

## Step 7 – Number check (R)

Numbers in the answer: 9.8, 12.4, 8.6, 10.9, 68, 18 → all found in steps 3–5;
dates (31 December, 1 January) → found in `highest_days` → **pass**. Any number not found blocks the answer and sends it back to the
Interpreter.
