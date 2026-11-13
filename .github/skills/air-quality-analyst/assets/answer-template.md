# Answer template

Summary: every answer to a resident uses this layout, in this order. Keep the
language at B1 level. Fill numbers **only** from tool results.

---

## Layout

```
**[Short answer: one sentence that answers the question directly]**

[Chart produced by the tool]

### What this means
[2–4 sentences. Explain the main result in everyday words. Compare with
something familiar where possible (e.g. the official station, the WHO guideline).]

### How sure are we?
[2–4 sentences, from references/sensors.md section 5. Always include:
data completeness, sensor limitations relevant to this question, and what the
analysis cannot show.]

### How we got this ▸  (fold-out)
- Question as understood: [...]
- Data: [sensors, period, parameter, calibrated yes/no]
- Steps: [tool 1 → tool 2 → ...], with settings
- Values removed as likely errors: [n] ([p]%)
- Software: Analyse-Together, commit [hash]; openair [version] (if used)
- Run ID: [id]  (use this to repeat the analysis exactly)

**You could also ask:**
- [follow-up question 1]
- [follow-up question 2]
```

---

## Worked example (temporal comparison)

*Question:* "How do the PM2.5 January values compare to the values in December?"

> **In January, fine dust (PM2.5) near your postcode was on average lower than in
> December: 9.8 versus 12.4 µg/m³.**
>
> *[Chart: daily PM2.5, December and January, 4 sensors]*
>
> ### What this means
> The air in January contained about a fifth less fine dust than in December. The
> highest values in December were on 31 December and 1 January, caused by the
> period around New Year's Eve. Without those two days, the difference between the
> months is smaller.
>
> ### How sure are we?
> These are low-cost sensors: they show patterns well, but single values can be off.
> One of the four sensors had data for only 68% of January, so it counts less
> heavily. A difference between two months is not a trend: weather, such as wind
> and rain, has a big influence.
>
> ### How we got this ▸
> - Question as understood: compare average PM2.5 in Dec and Jan, sensors within
>   1 km of postcode 1971
> - Data: 4 sensors, 1 Dec – 31 Jan, PM2.5, calibrated values
> - Steps: check_data_coverage (T1) → get_sensor_data (T1) → filter_outliers
>   (T1, default) → to_openair_format → plot_over_time (openair, daily) →
>   average_over_time (openair, monthly, min. 75% data)
> - Values removed as likely errors: 37 (1.3%)
> - Software: Analyse-Together, commit a1b2c3d; openair [version]
> - Run ID: 2026-11-13-0042
>
> **You could also ask:**
> - How do these sensors compare to the official station in the area?
> - Was January also lower than last year's January?

*(The numbers in this example are made up to show the format.)*

---

## Rules

- Short answer first. Never start with caveats.
- One chart per answer, unless the resident asks for more.
- Never leave out "How sure are we?".
- Do not use these words without explaining them: outlier, median, calibration,
  correlation, µg/m³ (write "micrograms per cubic metre" the first time).
- If the result is "no clear difference", say so plainly. That is a valid answer.
