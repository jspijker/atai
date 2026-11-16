# Test the method in any AI assistant

The skill in `.github/skills/air-quality-analyst/` is plain text, so it does not
depend on GitHub Copilot. You can run the same steps in ChatGPT, Claude, Le
Chat, Gemini or another AI chat, and compare how they do.

| Step | Who does it | Needs |
| --- | --- | --- |
| 0 Listen, 1 Understand, 2 Plan | The AI | Only the chat and the skill files |
| 3–5 Data check, sensor check, analysis | R on your computer | R (see the README) |
| 6 Explain | The AI | The results from R |
| 7 Number check | Python on your computer | `pip install jsonschema` |

**Just want to try the first steps?** Steps 0 to 2 need nothing installed. Give the
AI the files and the prompt below, and look at the plan it writes.

## 1. Attach these files to the chat

From `.github/skills/air-quality-analyst/`:

- `SKILL.md`
- `references/functions.md`, `references/question-recipes.md`,
  `references/sensors.md`, `references/sensor-quality.md`
- `assets/schemas/request.schema.json`, `assets/schemas/plan.schema.json`,
  `assets/schemas/answer.schema.json`
- `assets/example-run.md`

If the AI can only take a few files, attach `SKILL.md`, `functions.md`,
`question-recipes.md` and the three schemas.

## 2. Get the coordinates of your postcode

The AI never writes coordinates itself. Look them up first (needs internet):

```bash
python scripts/postcode_to_latlon.py 1941
```

It prints `lat lon`, for example `52.49 4.66` for central Beverwijk.

## 3. Paste this prompt, with your question at the bottom

```text
You help me, a resident, answer a question about the air where I live.
Follow the attached air-quality-analyst skill (SKILL.md and its references
and schemas) exactly.

Rules you never break:
1. Never calculate air-quality numbers yourself. Numbers come only from
   03_results.json, which I will give you after I run the R analysis.
2. Never invent coordinates. Use the lat/lon I give you below.
3. Only use tools listed in references/functions.md.
4. No claims about the cause of pollution, no health advice.
5. Always say how sure we can be.

Work one step at a time and wait for me after each step:
Step 0 Listen: ask me at most two short questions about what I noticed and
  what I want to do with the answer.
Step 1 Understand: write 01_request.json, valid against
  request.schema.json, with run_id P-<today's date>-0001.
Step 2 Plan: explain the plan in plain words, then write 02_plan.json, valid
  against plan.schema.json, with plan_id equal to the run_id. Set
  approved_by_resident to true only after I say yes.
Then stop. I run R and paste 03_results.json back to you.
Step 6 Explain: write 04_answer.json, valid against answer.schema.json.
  Every number in short_answer, what_it_means and how_sure must appear in
  03_results.json, copied exactly with the same decimals, and be listed in
  numbers_cited.

My question: [your question]
My location: postcode [....], lat [..] lon [..]
```

## 4. Check the request and the plan

Save the two JSON files the AI wrote in a new folder `run/`, then:

```bash
python -c "import json,jsonschema; S='.github/skills/air-quality-analyst/assets/schemas/'; [print(f, 'OK') for f,s in [('01_request','request'),('02_plan','plan')] if jsonschema.validate(json.load(open('run/'+f+'.json')), json.load(open(S+s+'.schema.json'))) is None]"
```

A schema error names the field the AI got wrong.

## 5. Run the analysis and paste the results back

```bash
Rscript scripts/run_analysis.R run/02_plan.json run data
```

R refuses a plan that names a tool outside its allow list, and tools that are
not built yet return `not_available` (see [tool-status.md](tool-status.md)).
Both are useful test outcomes. Paste `run/03_results.json` into the chat and let
the AI write `04_answer.json`. Save it in `run/` and check it:

```bash
python scripts/check_run.py run
```

`PASS` means every number in the answer comes from R. `answer.md` shows the
answer as a resident would see it.

## What to compare between AIs

| Question | Why it matters |
| --- | --- |
| Did it ask before guessing (area, period, pollutant)? | Listening, not assuming |
| Is `01_request.json` the same as in the Beverwijk example for the same question? | Same question, same analysis |
| Does the plan use only allowed tools, and include the sensor checks? | The method is followed |
| Does `check_run.py` pass first time? | No invented numbers |
| Does the answer mention both the typical day and the average, and how sure we are? | The method's reporting rules |

The data in `data/` covers about 520 Hollandse Luchten sensors in
Noord-Holland from 2020 to 2025, so questions about other places or periods in
that range can be run too.
