# The life of a run: files and hand-offs

Every resident question is processed as one **run**. A run is a small set of
files, each written by one step and read by the next, so that the whole analysis
is reproducible and every number can be traced back to where it came from. This
document describes those files in detail and points at a complete, checked
example.

> A run is a *working set of files*, not a committed folder. The naming
> convention is `runs/<run_id>/`, but that folder is created on demand (locally,
> or as the `out/` artifact in CI) and is **not** committed to this repository.
> The only run checked into the repository is the worked example in
> [`examples/P-2026-11-13-0001/`](../examples/P-2026-11-13-0001), referenced
> throughout this document.

## Run id

Every file in a run carries the same `run_id`, formatted
`P-YYYY-MM-DD-NNNN` (for example `P-2026-11-13-0001`). The schemas enforce this
pattern, so all files of one run stay linked together.

## The files

Each step writes exactly one file; the next step reads it. The JSON schemas live
in [`.github/skills/air-quality-analyst/assets/schemas/`](../.github/skills/air-quality-analyst/assets/schemas).

| File | Step(s) | Written by | Read by | Schema |
| --- | --- | --- | --- | --- |
| `01_request.json` | 1 Understand | AI | AI (step 2) | `request.schema.json` |
| `02_plan.json` | 2 Plan (approved) | AI + resident | R | `plan.schema.json` |
| `03_results.json` | 3 data check, 4 sensor check + background, 5 analysis | R only | AI (step 6), checker | `results.schema.json` |
| `04_answer.json` | 6 Explain | AI | checker, app | `answer.schema.json` |
| `05_check.json` | 7 Number check | checker (`check_run.py`) | app, team | `check.schema.json` |
| `audit.jsonl` | every step | R | team, reviewers | one JSON object per line |
| `answer.md` | 7 | checker (`check_run.py`) | resident, app | — (rendered answer) |
| `chart_*.svg/png`, `*.csv` | 5 | R | answer, team | — (analysis outputs) |

## What happens at each step

The steps follow the skill workflow in
[`.github/skills/air-quality-analyst/SKILL.md`](../.github/skills/air-quality-analyst/SKILL.md).
File names in brackets refer to the example run.

1. **Understand the question → `01_request.json`.**
   The AI classifies the resident's question (temporal comparison, trend,
   threshold, …), fixes the pollutant, area (as `lat`/`lon` + radius) and
   period(s), and records any assumptions. It never computes numbers here.
   *Example:* a temporal comparison of PM2.5 around central Beverwijk, December
   2024 vs January 2025.

2. **Make a plan → `02_plan.json`.**
   The AI turns the request into an ordered list of tool `steps` (each with its
   tier), plus the sensors/period/parameters, and marks it
   `approved_by_resident` once the resident agrees. R reads this file to know
   what to run. *Example:* nine steps, from `check_data_coverage` (Tier 1) to
   `average_over_time` (Tier 2).

3. **Run the analysis → `03_results.json` + `audit.jsonl` + chart/CSV files.**
   Only **R** (`scripts/run_analysis.R`) writes `03_results.json`. It runs the
   planned tools in order and records, for every step, a `status`, the
   `inputs_used`, `warnings`, any output `files`, and a list of `values`. Each
   value is the only kind of number the answer may quote and has an `id`,
   `label`, `value` and `unit` (e.g. `{"id": "median_jan", "value": 9.4,
   "unit": "µg/m³"}`). Every tool call is also appended to `audit.jsonl`, one
   JSON object per line, giving a complete audit trail. Charts and CSVs produced
   in the analysis step are written alongside.
   *Example:* four steps (`data_check`, `sensor_check`, `background`,
   `analysis`); `background` is `not_available` because that tool is not yet
   connected, and the analysis step produces `chart_daily_pm25.svg` and
   `daily_area_values.csv`.

4. **Explain the result → `04_answer.json`.**
   The AI writes the resident-facing answer (short answer, what it means, how
   sure we are, how we got this, follow-ups) using **only** numbers from
   `03_results.json`. Every number it uses is listed in `numbers_cited` together
   with the `value_id` it came from.

5. **Number check → `05_check.json` + `answer.md`.**
   `scripts/check_run.py` validates `01`–`04` against their schemas, then checks
   that **every number** in the answer traces back to a value id in
   `03_results.json`. It writes the verdict to `05_check.json`
   (`status: pass`/`fail`, with `numbers_found` / `numbers_missing`) and renders
   the human-readable `answer.md`. The answer is only published if this passes.
   *Example:* `pass`, with 13 numbers found and 0 missing.

## Rules the files must obey

- `run_id` is identical in every file (`P-YYYY-MM-DD-NNNN`).
- Only R writes `03_results.json`; the AI never invents numbers.
- Every number the AI uses is a value under a step's `values` list, and is
  listed in the answer's `numbers_cited` with its value id.
- Concentrations use one decimal; dates are ISO (`2025-01-20`) and times are in
  UTC.

## Try the example

Run the number check over the committed example to see a full, passing run:

```bash
pip install jsonschema
python scripts/check_run.py examples/P-2026-11-13-0001
```

It validates every file, confirms all numbers trace back to `03_results.json`,
and (re)writes `05_check.json` and `answer.md`. Exit code 0 means pass.
