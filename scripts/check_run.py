"""Check one run folder locally: schema validation, number check (step 7), readable answer.

Usage:  python scripts/check_run.py runs/<run_id>
Needs:  pip install jsonschema

Writes: runs/<run_id>/05_check.json  and  runs/<run_id>/answer.md
Exit code 0 = pass, 1 = fail.
"""
import json, re, sys
from datetime import datetime, timezone
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / ".github" / "skills" / "air-quality-analyst" / "assets" / "schemas"
FILES = {"01_request.json": "request", "02_plan.json": "plan", "03_results.json": "results", "04_answer.json": "answer"}
NUM = re.compile(r"(?<![\w.])\d+(?:[.,]\d+)?")


def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def allowed_numbers(results, request):
    """Every number the answer may contain, mapped to the value id it comes from."""
    allowed = {}
    for step in results["steps"]:
        for value_entry in step["values"]:
            if value_entry["unit"] == "date":
                date_value = datetime.fromisoformat(value_entry["value"])
                for digit in (date_value.day, date_value.year):
                    allowed.setdefault(float(digit), value_entry["id"])
            else:
                allowed.setdefault(float(value_entry["value"]), value_entry["id"])
    # inputs the resident chose or approved (radius, years of the periods) may also be quoted
    allowed.setdefault(float(request["area"]["radius_km"]), "request.radius_km")
    for period in request["periods"]:
        for key in ("start", "end"):
            allowed.setdefault(float(period[key][:4]), "request.period_year")
    return allowed


def main(run_dir):
    run = Path(run_dir)
    errors = []
    docs = {}
    for fname, schema in FILES.items():
        path = run / fname
        if not path.exists():
            errors.append(f"missing {fname}")
            continue
        docs[schema] = load(path)
        try:
            jsonschema.validate(docs[schema], load(SCHEMAS / f"{schema}.schema.json"))
        except jsonschema.ValidationError as e:
            errors.append(f"{fname}: {e.message}")
    if errors:
        print("SCHEMA ERRORS:\n  " + "\n  ".join(errors))
        sys.exit(1)

    ids = {d["run_id"] for d in (docs["request"], docs["results"], docs["answer"])} | {docs["plan"]["plan_id"]}
    if len(ids) != 1:
        print(f"run_id mismatch across files: {ids}")
        sys.exit(1)

    allowed = allowed_numbers(docs["results"], docs["request"])
    value_ids = {value_entry["id"] for step in docs["results"]["steps"] for value_entry in step["values"]}
    answer = docs["answer"]
    text = " ".join([answer["short_answer"], answer["what_it_means"], answer["how_sure"]])

    found, missing = [], []
    for match in NUM.finditer(text):
        number = float(match.group().replace(",", "."))
        if number in allowed:
            found.append({"text": match.group(), "value_id": allowed[number]})
        else:
            missing.append(match.group())
    bad_ids = [c["value_id"] for c in answer["numbers_cited"] if c["value_id"] not in value_ids]
    missing += [f"numbers_cited refers to unknown id '{i}'" for i in bad_ids]

    check = {
        "run_id": answer["run_id"],
        "status": "fail" if missing else "pass",
        "numbers_found": found,
        "numbers_missing": missing,
        "checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    jsonschema.validate(check, load(SCHEMAS / "check.schema.json"))
    (run / "05_check.json").write_text(json.dumps(check, indent=2, ensure_ascii=False), encoding="utf-8")

    md = [f"**{answer['short_answer']}**", ""]
    if answer.get("chart"):
        md += [f"![chart]({answer['chart']})", ""]
    md += ["### What this means", answer["what_it_means"], "", "### How sure are we?", answer["how_sure"], ""]
    if answer.get("how_we_got_this"):
        md += ["### How we got this"] + [f"- {line}" for line in answer["how_we_got_this"]] + [f"- Run: {answer['run_id']}", ""]
    if answer.get("follow_ups"):
        md += ["**You could also ask:**"] + [f"- {line}" for line in answer["follow_ups"]]
    (run / "answer.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(f"{check['status'].upper()}: {len(found)} numbers found, {len(missing)} missing")
    for missing_item in missing:
        print("  not in results:", missing_item)
    sys.exit(0 if check["status"] == "pass" else 1)


if __name__ == "__main__":
    main(sys.argv[1])
