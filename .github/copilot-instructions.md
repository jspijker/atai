# Repository instructions for Copilot

This repository answers residents' air-quality questions using low-cost sensor
data. The method is the skill in `.github/skills/air-quality-analyst/`: use it
for any question about air quality, sensors, PM2.5/PM10/NO2, trends or
comparisons.

## Rules
- Never calculate air-quality numbers yourself. Numbers come only from R
  (`scripts/run_analysis.R`), written to `runs/<run_id>/03_results.json`.
- Every run is one folder `runs/<run_id>/` with the agreed files
  `01_request.json` … `05_check.json` and `audit.jsonl`. Formats are in
  `.github/skills/air-quality-analyst/assets/schemas/`.
- After writing or changing a run, check it:
  `python scripts/check_run.py runs/<run_id>` (must print PASS).
- The analysis part of the skill (Tier 1 functions, sensor-quality rules,
  schemas, number check) is owned by domain experts. Do not change it unless
  asked; propose changes in a pull request.
- Sensor data (`data_sensors.parquet`, `metadata_sensors.parquet`) is committed
  in the folder `data/` (sourced from Zenodo record 23762846), so runs read it
  directly and do not re-download it.

## Code
- Analysis: R (Samen Analyseren / Analyse-Together functions first, openair
  second). Connect tools in `scripts/run_analysis.R`.
- Checks: Python 3 with `jsonschema`.
