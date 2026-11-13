# Known limitations and validation status

> [!CAUTION]
> This is an experimental hackathon project. The answers it produces have **not**
> been validated by the authors. This document lists the limitations we are aware
> of; it is not a guarantee that these are the only ones. Do not use any output
> for real-life decisions.

## Validation status

- **No systematic validation.** The authors did not compare the generated
  answers against ground truth, expert review, or reference measurements in any
  structured way. Numbers may be wrong even when they trace cleanly back to
  `03_results.json`.
- **The number check only checks traceability, not correctness.**
  `scripts/check_run.py` confirms that every number in an answer comes from a
  value id produced by R. It does **not** check that the analysis itself was
  appropriate or that the number is meaningful.
- **AI-written, AI-reviewed.** The code, the skill content and much of the review
  were produced with AI assistance. Treat all of it as unverified.

## Data and sensor limitations

- **Low-cost sensors.** Hollandse Luchten kits (e.g. Sensirion SPS30, SDS011) are
  indicative, not reference-grade. Absolute PM values carry significant
  uncertainty; comparisons and relative trends are more reliable than absolute
  numbers.
- **Humidity bias.** At high relative humidity, low-cost PM sensors tend to read
  too high. The skill flags humid hours (`flag_high_humidity`) but does not fully
  correct for this effect.
- **Calibration.** Only calibrated PM2.5 is available in the sensor archive;
  there is no calibrated PM10. Raw values are used where calibration is missing.
- **Coverage gaps.** Sensors drop out, move, or report sparsely. A run can be
  based on fewer sensors or hours than expected; `check_data_coverage` warns but
  cannot invent data.
- **Time zones and hour labelling.** Sensor timestamps are UTC while reference and
  weather data use other conventions; mishandling these is a common source of
  error.

## Method limitations

- **No causal claims.** The skill is explicitly forbidden from claiming cause and
  effect. A pattern can be *consistent with* a source, never proof of one.
- **Not all tools are implemented.** Several planned tools still return
  `not_available` or "not implemented yet"; see
  [`tool-status.md`](tool-status.md). A plan that relies on them cannot produce a
  full answer yet.
- **Regional background is best-effort.** `get_background` only returns a value
  when a nearby official *achtergrond* station has data for the requested period;
  otherwise it reports `not_available`.
- **Non-determinism of the AI stages.** The planner and answerer are language
  models: the same question can yield different plans, wording, or follow-ups
  between runs. Quality varies run to run.
- **No forecasting.** The project analyses historical data only; it does not
  predict future air quality.

## Operational limitations

- **Prompt injection surface.** Issue text and comments are attacker-controllable
  and are fed to agents with `gh`/shell access. The human-in-the-loop plan-mode
  checkpoints are the main mitigation; see
  [`automated-workflow.md`](automated-workflow.md).
- **Human checkpoint required.** The two Copilot stages are intentionally **not**
  run unattended; removing the human review removes the main safety control.

For the overall design and the reasoning behind the human-in-the-loop choices,
see [`automated-workflow.md`](automated-workflow.md).
