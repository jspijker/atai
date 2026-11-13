# The skill in detail

The reusable deliverable of this project is the **`air-quality-analyst` skill**
in [`.github/skills/air-quality-analyst/`](../.github/skills/air-quality-analyst).
A skill is a folder Copilot (or another agent) loads: a top-level `SKILL.md` with
the workflow and hard rules, plus reference and asset files the agent opens only
when it needs them. This document maps each file to what it does and when it is
used, so the skill can be understood and reused on its own.

## Top-level: `SKILL.md`

`SKILL.md` is the entry point. It defines:

- **Hard rules** that must never be broken — never calculate numbers in the
  agent, only use the listed tools in tier order, always show the plan first,
  always state uncertainty, never claim cause and effect, no individual health
  advice, answer in the resident's language at B1 level.
- **The eight-step workflow** — understand, plan, check data, check sensor
  quality + background, run the analysis, explain, number check, offer
  follow-ups.
- **A table pointing to the reference and asset files**, with "open when" guidance
  so the agent loads only what each step needs.

The run itself (which files each step reads and writes) is documented separately
in [`run-lifecycle.md`](run-lifecycle.md).

## `references/` — domain knowledge

| File | What it provides | Opened when |
| --- | --- | --- |
| `functions.md` | The only tools the agent may call, in two tiers: **Tier 1** wraps the validated Samen Analyseren / Analyse-Together functions (always first choice); **Tier 2** wraps `openair`. Lists each tool and its parameters. | Choosing tools and parameters (every analysis). See [`tool-status.md`](tool-status.md) for which are implemented. |
| `question-recipes.md` | How to turn each question type (temporal comparison, trend, location, anomaly, threshold, reference comparison, education) into a plan, with a shared "standard preparation" sequence. | Classifying the question and picking a recipe (every analysis). |
| `sensors.md` | What the sensors measure, how, and their limits — written to explain results to residents and fill the uncertainty section. | Explaining measurements and sensors. |
| `sensor-quality.md` | Mandatory sensor-quality checks (faulty sensors, humidity, drift, neighbour comparison) and how to get the regional background. Based mainly on Wesseling et al. (2024). | Every analysis: sensor checks, background, uncertainty. |

## `assets/` — templates, schemas and an example

| File / folder | What it provides | Used in |
| --- | --- | --- |
| `answer-template.md` | The fixed layout every resident answer follows (short answer, what it means, how sure, how we got this, follow-ups), at B1 language level. | Writing the final answer (step 6). |
| `example-run.md` | One question followed through every step, showing the exact shape each step hands to the next (invented numbers). A format reference when unsure what a step should output. | Testing / understanding the hand-offs. See also the real committed run in [`examples/P-2026-11-13-0001/`](../examples/P-2026-11-13-0001). |
| `schemas/` | JSON Schemas for every hand-off: `request`, `plan`, `results`, `answer`, `check`. These are the contract between the agent, R and the checker. | Validation at every step (enforced by `check_run.py`). |

## Reusing the skill elsewhere

To reuse the skill in another agent or application:

1. Copy the `air-quality-analyst/` folder into wherever your agent looks for
   skills (for Copilot, under `.github/skills/`).
2. Provide the tools in `references/functions.md`. In this repository they are
   implemented in `scripts/run_analysis.R`; see [`tool-status.md`](tool-status.md)
   for what is wired up.
3. Keep the JSON schemas and the number check (`scripts/check_run.py`) so every
   number in an answer stays traceable to a tool result.

The skill is licensed GPL-3.0 (see the repository `LICENSE`), consistent with the
Analyse-Together functions it builds on.
