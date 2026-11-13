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

Everything happens on **one issue** — the resident's **Research question**. One
approval starts the whole pipeline, and each stage posts its result as a comment
on that same issue. The two stages that use a Copilot agent run **inside the
Copilot app with a human checkpoint** (plan mode), not in CI; only the
deterministic R analysis runs unattended in Actions. See
[`docs/automated-workflow.md`](docs/automated-workflow.md) for the design and the
risks behind that choice.

0. A resident opens a **Research question** issue (just their question, no plan).
1. A maintainer or collaborator **approves** it by adding the `approved` label
   (the single gate — only triage/write users can add labels).
2. An **app orchestrator** (a scheduled session in the Copilot app) sees the
   approved issue and starts the `analysis-request-planner` agent in **plan
   mode**. A human reviews it in the app; on approval the agent posts the plan as
   a comment (steps 1–2) and adds the `plan-ready` label.
3. The workflow (`run-analysis.yml`, triggered by `plan-ready`) extracts the plan
   from the comment, checks it against
   `.github/skills/air-quality-analyst/assets/schemas/plan.schema.json`, and runs
   `scripts/run_analysis.R`.
4. A per-step status table, `03_results.json` and the audit log appear as a
   comment (steps 3–5); the label `results-ready` is added. All outputs are kept
   as a downloadable artifact.
5. The orchestrator sees `results-ready` and starts the `analysis-answerer` agent
   in **plan mode**. On approval it writes `04_answer.json`, assembles the run
   folder and runs `scripts/check_run.py` (step 7, the number check), and posts
   `answer.md` — the resident-facing answer with follow-ups — back to the issue
   (steps 6, 8). The label `answer-ready` is added once the number check passes.

Any stage that fails adds the `needs-attention` label and a short comment so a
human can step in.

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
2. Create the labels `research-question`, `approved`, `app-working`,
   `plan-ready`, `results-ready`, `answer-ready` and `needs-attention` (the
   answerer creates `answer-ready` automatically if it is missing).
3. Set up the **app orchestrator**: a scheduled session in the Copilot app that
   polls for `approved` and `results-ready` issues and starts the planner /
   answerer agents in plan mode (see
   [`docs/automated-workflow.md`](docs/automated-workflow.md)).
4. Connect each tool in `scripts/run_analysis.R` to the real Samen Analyseren or
   openair function, and add the data source (the stub only logs
   "not implemented").

## Try it

Open a new **Research question** issue with your question, then add the
`approved` label. The orchestrator plans it (with your approval in the app), the
analysis runs, and the answer is posted back. To exercise just the analysis
workflow, add a comment holding a `### Analysis plan (JSON)` block (see
`examples/beverwijk-issue-body.md` or `examples/beverwijk-plan.json`) and add the
`plan-ready` label, or dispatch it manually:
`gh workflow run run-analysis.yml -f issue_number=<N>`.

## Safety

- Nothing runs until someone with triage rights adds `approved`, and each
  Copilot stage pauses in the app for a human to approve before it posts.
- The issue text is never passed through the shell; the plan is read in a
  script and validated against the schema.
- `run_analysis.R` refuses any tool that is not on its allowed list.
