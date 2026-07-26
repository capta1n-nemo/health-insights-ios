# Health Insights — Architecture

## Goal

Turn data from Apple Health, Oura and Withings (extensible to more sources) into
insights that aren't directly measured — starting with **heart health**,
**cardiovascular risk**, and **blood pressure** — with the heavy lifting done
**on-device** and near-zero backend.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  SwiftUI app (HealthInsights)                            │
│  Onboarding · Dashboard · Insights · Grounding · Settings    │
├──────────────────────────────────────────────────────────────┤
│  AppModel (@Observable)  — orchestrates sync + evaluation     │
├───────────────┬───────────────┬──────────────┬───────────────┤
│ Integrations  │ HealthKit     │ Intelligence │ Persistence    │
│ protocol +    │ Service       │ Foundation   │ SwiftData      │
│ registry      │ (Apple Health)│ Models (LLM) │ (grounding,    │
│ Apple/Oura/   │               │ + fallback   │  logs, state)  │
│ Withings      │               │              │                │
├──────────────────────────────────────────────────────────────┤
│  InsightKit (pure Swift package — NO HealthKit/UIKit)         │
│  Canonical models · Baseline stats · Insight models · Engine  │
└──────────────────────────────────────────────────────────────┘
        (Oura/Withings OAuth runs on-device; credentials in Keychain — no backend)
```

### InsightKit (the testable core)

`InsightKit` is a standalone Swift package with **no platform imports**, so
every clinical/statistical function is verifiable with `swift test` — no Xcode,
simulator or device. It contains:

- **Canonical models** (`MetricType`, `HealthMetricSample`, `UserHealthProfile`,
  `GroundingInput`) — the vendor-neutral vocabulary everything else speaks.
- **Baseline** — EWMA, z-score, percentile: transparent personalisation.
- **Insight models** implementing `InsightModel`, each declaring its own
  `GroundingRequirement`s and computing purely from samples + profile.
- **InsightEngine** — registry + evaluator; also unions the outstanding
  grounding prompts across insights.

The app adapts platform data into these types and renders the results.

## Data flow

1. `AppModel.refresh()` pulls samples from every **connected** integration
   (`IntegrationRegistry.syncAllConnected`) plus locally-logged manual samples.
2. Samples are normalised to `HealthMetricSample` (canonical units).
3. The user's grounding facts are loaded into a `UserHealthProfile`.
4. `InsightEngine.evaluateAll` runs each insight → `[InsightResult]`.
5. `FoundationModelSummarizer` turns the results into a plain-language summary
   (on-device LLM when available, deterministic template otherwise).
6. SwiftUI renders cards, dials, trends, and grounding prompts.

## The science (why it's honest)

| Insight | Method | Source |
|---------|--------|--------|
| Cardiovascular risk | **Combined SCORE2/SCORE2-OP + ASCVD Pooled Cohort Equations** — both computed, reported as a consensus (mean) with the min–max range as an uncertainty band; deterministic, sex-specific | SCORE2 Working Group, *Eur Heart J* 2021;42(25):2439–2454 · Goff et al., *Circulation* 2013;129(25 S2) |
| Heart health | Composite of VO₂max, resting HR, HRV vs. age/sex norms + personal baseline | Established cardiorespiratory-fitness norms |
| Blood pressure | Grounding-first (logged cuff readings + trend); **experimental** personalised estimator gated behind calibration, always with uncertainty | — |

Design principles that keep this trustworthy:

- **No invented numbers.** Risk % comes from published equations; the LLM only
  phrases results, it never produces values.
- **Confidence is always shown** (`Validated` / `Estimate` / `Needs data` /
  `Experimental`).
- **Cuffless BP is explicitly experimental** — wearable-only BP is unreliable
  without per-person calibration; the app frames it that way and leans on real
  cuff readings.

## Extensibility

- **New data source**: implement `HealthIntegration` and register it. Insights
  never change — they only see canonical samples.
- **New insight**: implement `InsightModel` (declare its grounding needs) and add
  it to `InsightEngine`. The grounding UI and dashboard pick it up automatically.
- **New metric**: add a `MetricType` case and map it in the relevant provider.
- **Future ML**: `Baseline` can be swapped/augmented with a Core ML model for
  personalised anomaly detection without touching the insight contracts.

## On-device intelligence

- **Apple Foundation Models** (`FoundationModels`, iOS 26+): the daily summary is
  generated on-device via `LanguageModelSession`, gated by availability with a
  template fallback. No health data leaves the phone.
- **Core ML** is the planned home for personalised predictive models; the MVP
  deliberately uses transparent classical statistics first.

## Privacy

- Health data is processed and stored **on the device** (SwiftData + HealthKit).
- Oura/Withings OAuth runs entirely on-device; the user's own developer
  credentials and tokens live in the iOS Keychain. No backend is required (an
  optional HTTPS-redirect helper exists only for Withings' redirect quirk).

## Not a medical device

These insights are for information and self-tracking only. They do not diagnose,
treat, or prevent disease and are not a substitute for professional medical
advice. Users should consult a clinician for health decisions and seek emergency
care for acute symptoms.

## Verification

- `cd InsightKit && swift test` — checks the risk equations against published
  worked examples and the statistics against hand-computed fixtures.
- Open `HealthInsights.xcodeproj` in Xcode 16+ and run on a device/simulator
  with Health data. (If the project won't open, regenerate it with
  `xcodegen generate`.)
