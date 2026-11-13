# Tool implementation status

The analysis tools the skill may call are listed in
[`.github/skills/air-quality-analyst/references/functions.md`](../.github/skills/air-quality-analyst/references/functions.md)
and implemented in [`scripts/run_analysis.R`](../scripts/run_analysis.R). Not all
of them are fully wired up yet. `run_analysis.R` keeps an explicit **allow list**:
a plan that names a tool outside this list is rejected before anything runs.

Status values:

- **implemented** — runs and produces real values from the committed data.
- **best-effort** — implemented, but returns `not_available` when the required
  data is missing for the requested pollutant/period.
- **not implemented** — on the allow list but returns a "not implemented yet"
  result (`status: not_available`) instead of a calculation.

## Tier 1 — Samen Analyseren / Analyse-Together (adapted)

| Tool | Status | Notes |
| --- | --- | --- |
| `check_data_coverage` | implemented | Counts sensors and flags low coverage. |
| `get_sensor_data` | implemented | Selects and loads sensor measurements for the area/period. |
| `detect_faulty_sensors` | implemented | Flags broken/implausible sensors. |
| `flag_high_humidity` | implemented | Flags hours of high relative humidity (read-too-high risk). |
| `filter_outliers` | implemented | Removes impossible/outlier values. |
| `get_background` | best-effort | Picks the nearest official *achtergrond* station; returns `not_available` if no station has data for the period/pollutant. |
| `to_openair_format` | implemented | Bridges prepared data into the Tier 2 (openair) format. |
| `compare_with_neighbours` | not implemented | Neighbour comparison for the sensor check. |

## Tier 2 — openair

| Tool | Status | Notes |
| --- | --- | --- |
| `average_over_time` | implemented | Daily/period averages per sensor and for the area. |
| `plot_over_time` | not implemented | Time-series plot. |
| `source_direction` | not implemented | Links concentrations to wind direction. |
| `pollution_rose` | not implemented | Pollution rose by wind direction. |
| `high_values_by_direction` | not implemented | High values grouped by wind direction. |

## Connecting a tool

To implement a "not implemented" tool, replace its `not_impl(...)` entry in the
`tools` list in `scripts/run_analysis.R` with a real function that returns the
same result shape (`step`, `status`, `inputs_used`, `values`, `warnings`,
`files`) and writes its numbers as `values` entries. Keep it on the allow list so
plans may reference it. See the implemented Tier 1/Tier 2 tools in the same file
as templates.
