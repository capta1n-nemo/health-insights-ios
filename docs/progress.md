# Progress

Philosophy unchanged: **use every signal, get creative with it, and be honest
about confidence.**

## Shipped

### Insights
- [x] Readiness / Recovery — HRV, resting HR, sleep, temperature, respiration
      vs. personal baseline (EWMA + z-scores).
- [x] Heart Health — VO₂max, resting HR, HRV vs. age/sex norms + baseline.
- [x] Cardiovascular risk — combined SCORE2 + ASCVD, consensus + range.
- [x] Blood Pressure — grounding-first cuff logging, two-feature experimental
      estimator, AHA category bands, mean arterial pressure, 30-day grounding
      window, full metric-detail-screen migration.
- [x] Substance Impact — private logging + before/after HR/HRV/temp/sleep +
      cumulative cardiovascular-load indicator + safety flag.
- [x] Sleep quality, cardio fitness trend, body composition, resting-HR trend.

### Creative data use
- [x] Temperature reconstruction from wearable nightly-deviation readings.
- [x] Blood-test photo import (on-device OCR → confirmed grounding values).

### Integrations
- [x] Apple Health (live, on-device).
- [x] Oura, Whoop, Withings — on-device OAuth, BYO developer credentials,
      Keychain storage, no backend.
- [x] "Other data" browser — imports every HealthKit/provider field, not just
      the metrics the app has a first-class insight for.

### App structure
- [x] Four-tab layout: Today / Vitals / Insights / Settings.
- [x] Multi-source overlay charts with provenance badges (direct API vs.
      Apple Health bridge vs. Apple Watch).
- [x] Adjustable timeframe (D/W/M/6M/Y/All) with correct chart scaling at every
      zoom level (the "All squashes into a strip" bug is fixed).
- [x] Chart lines break on data gaps instead of bridging them; long ranges are
      bucketed (mean/median/sum per the metric) instead of raw-decimated.
- [x] Active/inactive source handling — a source that's gone quiet is shown as
      history, excluded from the current average.
- [x] Per-category metric layouts (trend/range/total/bivariate/static) via
      `MetricViewStrategy`, replacing one generic screen for every metric shape.
- [x] Height (and future static attributes) get a plain value card, no chart.
- [x] Feedback ledger + privacy-preserving telemetry outbox.
- [x] Troubleshooting view (per-integration/per-metric sync diagnostics).

### CI/CD
- [x] GitHub Actions CI on a self-hosted Mac runner: `swift test` + unsigned
      app compile on every push.
- [x] Wi-Fi deploy to a pinned iPhone via `devicectl` on push to `main`.
- [x] Incremental deploy builds (no forced `clean`) for faster iteration.
- [x] Build-provenance stamp in Settings ▸ About (commit + build number).

### Developer workflow
- [x] `CLAUDE.md` + memory router, `.claude/settings.json` permissions, and a
      `/handover` slash command for cross-session continuity.
- [ ] Verify `/handover` and `CLAUDE.md` auto-load — they only register when
      the session's working directory *is* this repo (see `activeContext.md`).

## In progress / not yet device-verified
- [ ] On-device walkthrough of the latest nine-part UI pass (CI-green, not yet
      manually confirmed on the phone) — see `activeContext.md`.

## Next

### More "gap-filling" insights
- [ ] Heart/fitness age and lifetime-risk framing.
- [ ] VO₂max trajectory + "what would move it" guidance.
- [ ] Sleep-debt and circadian consistency from bedtime variance.
- [ ] Cardio strain from stimulants as a first-class trend.

### Integrations
- [ ] Hume Band direct API (today flows in via Apple Health only).
- [ ] Ultrahuman, Garmin, Fitbit — drop in via `HealthIntegration` protocol.

### Unstructured data
- [ ] Live document scanner (VisionKit) instead of library-only picking.
- [ ] Foundation Models structured extraction for arbitrary lab analytes.
- [ ] ECG photo/PDF import with metadata (no automated interpretation — that's
      a regulated medical-device claim, out of scope by design).

### Charts
- [ ] Filled `AreaMark` min/max bands (currently shipped as outlined
      `LineMark` pairs — a deliberate, pre-approved fallback for a Swift Charts
      SDK hazard; revisit only with a dedicated compile-spike).

### On-device ML
- [ ] Core ML personal anomaly detection once enough history exists.

## Guardrails (unchanging)
- Not a medical device; not medical advice. Substance features are
  harm-reduction and descriptive, never encouragement or dosing guidance.
- Health data stays on-device; the only network calls are the user's own
  wearable APIs. No health data on any server.
