# Question recipes

Summary: how to turn each type of resident question into an analysis plan. Find
the question type, then follow its recipe. Tool names refer to
`references/functions.md`; **T1** = Samen Analyseren (validated, first choice),
**T2** = openair.

Every recipe that needs measurements starts with the same **standard preparation**:

1. `check_data_coverage` (T1)
2. `get_sensor_data` (T1), calibrated values
3. `filter_outliers` (T1)
4. `to_openair_format` (T1 bridge), only if a T2 tool follows; add wind data only
   if a wind tool follows

## Quick classification

| If the question is about… | Type | Recipe | Main tool |
| --- | --- | --- | --- |
| what sensors measure, units, how sensors work | Education | R1 | none |
| this period vs. another period | Temporal comparison | R2 | `plot_over_time` (T2) |
| which sensor/place is worst or best | Location | R3 | `average_over_time` (T2) |
| improving or getting worse over time | Trend | R4 | `trend_with_uncertainty` (T2) |
| unusual events, peaks | Anomaly | R5 | `calendar_view` (T2) |
| weekday vs. weekend, day vs. night | Pattern | R6 | `daily_weekly_pattern` (T2) |
| safe levels, exceeding limits | Threshold | R7 | `calendar_view` (T2) |
| my sensor vs. the official station | Reference comparison | R8 | `compare_with_reference_stats` (T2) |
| effect of a specific source | Source investigation | R9 | `source_direction` (T2) |
| next week, future | Forecast | R10 | none |

If Tier 1 turns out to offer an equivalent analysis, use that instead and update
this table.

---

## R1 – Education
- **Example**: "What different types of measurements are stored from the sensors?"
- **Do**: answer from `references/sensors.md`. Offer an example analysis.

## R2 – Temporal comparison
- **Example**: "How do the PM2.5 January values compare to the values in December?"
- **Plan**: standard preparation (both months) → `plot_over_time` with daily
  averages → `average_over_time` per month (`data.thresh = 75`).
- **Must mention**: weather differs between months; two months are not a trend;
  New Year's Eve fireworks raise PM sharply on 31 Dec – 1 Jan.

## R3 – Location
- **Example**: "Which sensor has the worst air quality in our neighbourhood?"
- **Plan**: standard preparation (same period, all sensors, ≥ 1 month) →
  `average_over_time` per site → bar chart → optional `compare_with_reference_stats`
  for the highest sensor.
- **Must mention**: placement effects; differences smaller than the sensor
  uncertainty are not meaningful.

## R4 – Trend
- **Example**: "Is air quality improving or getting worse this year?"
- **Plan**: standard preparation (as long a period as possible) →
  `trend_with_uncertainty` (`TheilSen`, `deseason = TRUE`, monthly).
- **Must mention**: the trend comes with a range of uncertainty. With less than
  2–3 years of data, say that a reliable trend cannot be determined yet and show
  `plot_over_time` instead. Sensor ageing can create a false trend.

## R5 – Anomaly
- **Example**: "Were there any unusual air quality events last month?"
- **Plan**: standard preparation, but **report** what `filter_outliers` removed
  (the removed values may be the events) → `calendar_view` for the month →
  `plot_over_time` hourly for the highest days.
- **Must mention**: a peak on several sensors at once is probably real; a peak on
  one sensor may be local or a fault.

## R6 – Pattern (weekday/weekend, time of day)
- **Example**: "Is air quality better on weekends vs. weekdays?"
- **Plan**: standard preparation (≥ 2 months) → `daily_weekly_pattern`
  (`timeVariation`), which shows day-of-week and hour-of-day patterns with
  confidence intervals.
- **Must mention**: whether the confidence intervals overlap; if they do, there is
  no clear difference.

## R7 – Threshold
- **Example**: "When do air quality values exceed safe levels?"
- **Plan**: standard preparation → `average_over_time` daily → `calendar_view`
  with `breaks` at the WHO 24-hour guideline value (see `pollutants.md`).
- **Must mention**: guideline values apply to official measurements over a set
  averaging period, not single hourly sensor values. No individual health advice.

## R8 – Reference comparison
- **Example**: "How do the sensors in my neighbourhood compare to the nearest
  official reference stations?"
- **Plan**: standard preparation + `get_reference_data` (T1, same period) →
  `to_openair_format` → `compare_with_reference_stats` + `scatter_vs_reference`.
- **Must mention**: explain the statistics in words ("on average the sensor reads
  X higher"), not as abbreviations.

## R9 – Source investigation (handle with care)
- **Example**: "What is the impact of the construction site on the PM2.5 air
  quality at my street?"
- **Plan**: standard preparation with wind data (≥ 4 weeks) → `source_direction`
  (`polarPlot`) and/or `pollution_rose`; `get_background` and plot the **local
  increment** (sensor − background) before vs. during the works, if data exist.
  The local increment removes regional effects such as weather and pollution
  from abroad.
- **Must say**: the analysis can show whether higher values come with wind from
  the site's direction. It cannot **prove** the site is the cause. For formal
  complaints, refer to the municipality or omgevingsdienst.

## R10 – Forecast (out of scope)
- **Example**: "Based on current trends, how will next week's air quality look?"
- **Do**: explain that the tool does not forecast. Refer to official forecasts
  (e.g. luchtmeetnet.nl). Offer to show the past weeks instead.
