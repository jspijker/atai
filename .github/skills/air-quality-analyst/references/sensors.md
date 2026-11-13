# Sensors: what they measure and their limits

Summary: what the sensors in the Samen Meten / Hollandse Luchten network measure,
how, and what that means for the certainty of an answer. Use this to explain
results and to fill the uncertainty section of every answer.

> **For the air-quality expert:** items marked `[verify]` are typical for
> low-cost sensors but must be checked against the actual sensor types and
> the Samen Meten documentation before the demo.

---

## 1. What is measured

| Quantity | What it is | Unit | Measured by |
| --- | --- | --- | --- |
| PM1 | Particles smaller than 1 micrometre | µg/m³ | Optical particle sensor `[verify]` |
| PM2.5 | Particles smaller than 2.5 micrometre ("fijnstof") | µg/m³ | Optical particle sensor |
| PM10 | Particles smaller than 10 micrometre | µg/m³ | Optical particle sensor |
| NO2 | Nitrogen dioxide, mainly from traffic | µg/m³ | Electrochemical sensor, only on some kits `[verify]` |
| Temperature, humidity | Weather at the sensor | °C, % | Built-in sensor; used for calibration |

**Plain-language explanation for residents (example):**
"The sensor sucks in air and shines a small light through it. Particles scatter the
light, and from that the sensor estimates how much fine dust is in the air. This is
cheaper than an official station, but less precise."

## 2. Sensor types in the network

| Sensor type | Projects | Measures | Notes |
| --- | --- | --- | --- |
| `[fill in]` | Hollandse Luchten | `[ ]` | `[ ]` |
| `[fill in]` | Samen Meten (other) | `[ ]` | `[ ]` |

## 3. Known limitations (explanations for residents)

The checks the AI must run for these are in `sensor-quality.md`.

1. **Humidity.** Above roughly 80–85% relative humidity, particles absorb water and
   look bigger. Optical sensors then read **too high**, typically on foggy or misty
   mornings. `[verify threshold]`
   → *Say*: "On very damp days, these sensors can show higher values than are really
   present."
2. **PM10 is less reliable than PM2.5.** Optical sensors detect large particles
   poorly. `[verify]`
   → *Say*: "PM10 values from these sensors are a rough estimate."
3. **Calibration.** Raw sensor values are corrected using nearby official stations.
   Always use **calibrated** values where available. `[verify how Samen Meten
   calibrates and which field holds calibrated values]`
4. **Placement.** Height, a nearby chimney, kitchen vent, barbecue or wall can
   strongly affect one sensor. One high sensor is not proof of bad air in the area.
5. **Sensor ageing and faults.** Sensors drift over time or break down. Sudden
   flat lines, zeros or extreme values usually mean a fault.
6. **Precision.** Two sensors next to each other will not give identical values.
   Differences smaller than about `[X]` µg/m³ (PM2.5, daily average) should not be
   presented as meaningful. `[expert to set X]`

## 4. Minimum data requirements

| Analysis | Minimum | If not met |
| --- | --- | --- |
| Any average | ≥ 75% of hourly values present in the period `[verify]` | Warn; suggest longer period |
| Comparing two periods | ≥ 2 weeks per period | Warn |
| Trend | ≥ 12 months | Do not call it a trend |
| Pollution rose | ≥ 4 weeks with varied wind directions | Do not run |
| Comparing sensors | Same period for all sensors | Align the period first |

## 5. Ready-made uncertainty sentences

Use these (adapted) in the answer's "How sure are we?" section:

- "These are measurements from low-cost sensors. They show patterns well, but
  individual values can be off by `[X]` µg/m³."
- "Sensor `[name]` had data for only `[n]`% of the period, so its result is less
  certain."
- "`[n]` values were left out as likely measurement errors (`[p]`% of the data)."
- "Several days in this period were very damp, which can make the values look
  higher than they really were."
- "This shows *when* and *from which direction* values were higher. It cannot prove
  *what* caused them."
