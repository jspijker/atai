# Air-quality analysis via GitHub issues

Each resident question becomes a GitHub issue. The issue holds the approved
analysis plan (step 2). A workflow runs the plan and posts the results and the
audit log back to the issue (steps 3–5: data check, sensor check and
background, analysis). The issue is the public audit trail.

## Agreed output files (one folder per run)

Every question becomes one folder `runs/<run_id>/`. Each step writes one file;
the next step reads it. Schemas are in `.github/skills/air-quality-analyst/assets/schemas/`.

| File | Step | Written by | Read by | Schema |
| --- | --- | --- | --- | --- |
| `01_request.json` | 1 Understand | AI | AI (step 2) | `request.schema.json` |
| `02_plan.json` | 2 Plan (approved) | AI + resident | R | `plan.schema.json` |
| `03_results.json` | 3 data check, 4 sensor check and background, 5 analysis | R only | AI (step 6), checker | `results.schema.json` |
| `04_answer.json` | 6 Explain | AI | checker, app | `answer.schema.json` |
| `05_check.json` | 7 Number check | checker | app, team | `check.schema.json` |
| `audit.jsonl` | every step | R | team, jury | one JSON object per line |
| `chart_*.svg/png`, `*.csv` | 5 | R | answer, team | – |

Rules:
- `run_id` is the same in every file (`P-YYYY-MM-DD-NNNN`).
- Only R writes `03_results.json`. Every number the AI may use is a `values`
  entry with `id`, `label`, `value` and `unit`.
- The AI lists every number in its answer in `numbers_cited` with the value id.
- Concentrations 1 decimal; dates ISO (`2025-01-20`) in files; times in UTC.

## Run locally

```bash
pip install jsonschema
python scripts/check_run.py examples/P-2026-11-13-0001
```

This validates all files against their schemas, runs the number check, writes
`05_check.json`, and writes `answer.md` (the answer as the resident sees it).
Exit code 0 = pass. `examples/P-2026-11-13-0001/` is a checked-in example run (the
Beverwijk prototype, Dec 2024 vs Jan 2025) kept alongside the other sample files;
its numbers come from a Python stand-in, not yet the validated tools. Real runs
live in `runs/<run_id>/`, which is created when a plan is run.

To produce `03_results.json` with R: `Rscript scripts/run_analysis.R runs/<id>/02_plan.json runs/<id>`
(stub: tools still report `not_available` until they are connected).

The plan selects sensors by distance, so `area` needs a centre (`lat`/`lon`), not
just a postcode. Resolve a resident's postcode to coordinates with
`python scripts/postcode_to_latlon.py "1941"` (uses the free PDOK Locatieserver).

## Flow on GitHub

0. A resident opens a **Research question** issue (just their question, no plan).
   The `analysis-request-planner` agent (`.github/agents/`) reads it, does steps
   1–2 of the skill, and opens the matching **Analysis request** issue below.
1. Someone opens an issue with the **Analysis request** form and pastes the
   resident's question and the plan JSON (or the agent opens it from step 0).
2. A maintainer checks it and adds the label `run-analysis`.
3. The workflow extracts the plan, checks it against
   `.github/skills/air-quality-analyst/assets/schemas/plan.schema.json`, and runs
   `scripts/run_analysis.R`.
4. Results, audit log and a link to the run appear as a comment; the label
   `results-ready` is added. All outputs are kept as a downloadable artifact.
5. The `analysis-answerer` agent (`.github/agents/`) reads the results-ready
   issue, does steps 6–8 of the skill: it writes `04_answer.json`, assembles the
   run folder and runs `scripts/check_run.py` (step 7, the number check), and
   posts `answer.md` — the resident-facing answer with follow-ups — back to the
   issue. The label `answer-ready` is added once the number check passes.

## What your partner needs

1. A GitHub repository with Actions enabled, and a GitHub Copilot licence.
2. This folder copied into the repository root (the skill is already inside, in
   `.github/skills/air-quality-analyst/`, where Copilot looks for skills).
3. The sensor data files in a local folder `data/` (not committed; too large and
   listed in `.gitignore`).
4. Python 3 with `pip install jsonschema` for the local check; R with `jsonlite`
   and `openair` once the R tools are connected.

## Set-up

1. Copy this folder into the root of your repository.
   In repository Settings › Actions › General, set workflow permissions to
   "Read and write" if the comment step fails with a permissions error.
2. Create the labels `research-question`, `analysis-request`, `run-analysis`,
   `results-ready` and `answer-ready` (the answerer creates `answer-ready`
   automatically if it is missing).
3. Connect each tool in `scripts/run_analysis.R` to the real Samen Analyseren or
   openair function, and add the data source (the stub only logs
   "not implemented").

## Try it

Open a new issue with the form and use `examples/beverwijk-issue-body.md` as the
content (or paste `examples/beverwijk-plan.json` into the plan field).

## Safety

- Nothing runs until someone with triage rights adds `run-analysis`.
- The issue text is never passed through the shell; the plan is read in a
  script and validated against the schema.
- `run_analysis.R` refuses any tool that is not on its allowed list.
