# Roadmap

Where the app is, and where it's going. The philosophy: **use every signal, get
creative with it, and be honest about confidence.**

## Shipped

### Insights
- **Readiness / Recovery** — Oura/Whoop-style daily score from HRV, resting HR,
  sleep, temperature and respiration vs. *your own* baseline (EWMA + z-scores).
- **Heart Health** — VO₂max, resting HR, HRV vs. age/sex norms + your baseline.
- **Cardiovascular risk** — combined SCORE2 + ASCVD, age-aware (validated
  40–79), shown as a consensus + range.
- **Blood Pressure** — grounding-first cuff logging + a personalised **two-feature
  (resting HR + HRV) estimator** with uncertainty. This is the "gap" most bands
  don't fill; it's front-and-centre and clearly labelled experimental.
- **Substance Impact** — private, non-judgemental logging of alcohol / nicotine /
  cannabis / stimulants / etc., then a data-driven before-vs-after of your own
  resting HR, HRV, temperature and sleep, plus a recent **cumulative
  cardiovascular-load** indicator and a safety flag on large responses.

### Creative data use
- **Temperature reconstruction** — wearables (Oura/Whoop/Hume) report only a
  nightly skin-temp *deviation*; we add it to a learned personal baseline to get
  an absolute body-temperature series that can be trended and (future) written
  back to Apple Health.

### Integrations
- **Apple Health** (live, on-device).
- **Oura**, **Whoop**, **Withings** — on-device OAuth, credentials in Keychain,
  no backend. Whoop brings HRV, resting HR, SpO₂, skin temp and **Day Strain**.

### Unstructured data
- **Blood-test photo import** — on-device Vision OCR → `LabReportParser` extracts
  cholesterol values (mmol/L or mg/dL) for you to confirm → saved as grounding.

## Next

### More "gap-filling" insights people under 30 want
- **Heart / fitness age** and lifetime-risk framing (more meaningful than a
  10-year % for the young).
- **VO₂max trajectory** and "what would move it" guidance.
- **Sleep-debt** and circadian consistency from bedtime variance.
- **Cardio strain from stimulants** as a first-class trend (using Whoop Day
  Strain + logged use).

### Integrations
- **Hume Band** — today its data flows in via **Apple Health**; a direct Hume API
  provider (incl. its own BP-trend estimate and metabolic metrics) is a fast
  follow once their developer API is confirmed.
- Ultrahuman, Garmin, Fitbit — all drop in via the `HealthIntegration` protocol.

### Unstructured data ("photograph anything")
- **Live document scanner** (VisionKit `DataScannerViewController`) for capture,
  not just library picking.
- **Foundation Models structured extraction** — use Apple's on-device LLM with
  guided generation to pull *any* lab analyte (LDL, triglycerides, HbA1c, eGFR…)
  from messy reports, not just a regex whitelist.
- **ECG import** — store a photo/PDF of a 12-lead or Apple Watch ECG with
  metadata; automated interpretation is explicitly **out of scope** (that's a
  regulated medical-device claim) — we'd surface it for a clinician, not diagnose.
- Prescriptions, discharge summaries, wearable exports — same pipeline.

### On-device ML
- **Core ML** personal anomaly-detection once enough history exists, replacing
  the classical baseline where it measurably beats it.

## Guardrails (unchanging)
- Not a medical device; not medical advice. Substance features are
  harm-reduction and descriptive, never encouragement or dosing guidance.
- Health data stays on-device; the only network calls are the user's own
  wearable APIs. No health data on any server.
