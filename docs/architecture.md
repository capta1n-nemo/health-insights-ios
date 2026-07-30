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
| Heart age (vascular age) | The person's own 10-year risk **inverted over age** against an optimal-risk-factor reference person of the same sex. No new equation — the shipped ones, read backwards | D'Agostino et al., *Circulation* 2008;117(6):743–753 (Framingham vascular age); same framing as JBS3 / NHS heart age |
| Fitness age | The same age/sex VO₂max norms the heart-health score marks against, interpolated into a continuous line and inverted | Cardiorespiratory-fitness norms (as above) |

Design principles that keep this trustworthy:

- **No invented numbers.** Risk % comes from published equations; the LLM only
  phrases results, it never produces values.
- **Confidence is always shown** (`Validated` / `Estimate` / `Needs data` /
  `Experimental`).
- **Cuffless BP is explicitly experimental** — wearable-only BP is unreliable
  without per-person calibration; the app frames it that way and leans on real
  cuff readings.

## Ages instead of percentages (`HeartAge.swift`, `CardioTrajectory.swift`)

A percentage is easy to shrug off; "your heart is running eight years ahead of
you" is not. Both age insights re-express models the app already has on the axis
people feel, and both are careful about the same three things:

- **Never solved outside a validated band.** `HeartAgeModel.solveAge` inverts
  each engine only inside `Engine.validatedAgeRange` (SCORE2 40–69, ASCVD 40–79)
  and returns an `isCapped` flag, which the UI says out loud ("79 or older")
  rather than printing a number produced by extrapolation. `FitnessAgeModel`
  does the same at 20–75, the extent of the norm table.
- **No fabricated lifetime risk.** The roadmap asked for lifetime framing. Nothing
  here is validated past 79, and compounding decades of 10-year risk would be
  inventing a figure, so `HeartAgeModel.projection` instead runs the *same*
  published equations at future ages they are validated for, labelled "if today's
  numbers hold". It answers "where is this heading?" without making anything up.
- **A trajectory is judged against ageing, not zero.** VO₂max falls with age
  regardless, so `VO2Trajectory` compares the least-squares slope to the norm
  line's own slope at that age (`ageTypicalChangePerYear`). Holding level scores
  *above* mid-dial, because it is genuinely a gain. `netPerYear` is that
  comparison; `fitnessYearsGained` is the trajectory's effect on fitness age
  alone. They are deliberately separate — adding them would count it twice.

"What would move it" prefers the user's own history (their busier weeks versus
their lighter ones, from a single source so a walk isn't counted twice) and falls
back to general training evidence, with `Lever.isPersonal` marking which is which.

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

## Swift patterns (going forward)

New code should follow: Swift 6, SwiftUI, `@Observable` for view-model-shaped
state (not `ObservableObject`), `NavigationStack` (not `NavigationView`),
`@MainActor` on anything that touches UI state. `AppModel`
(`HealthInsights/Core/State/AppModel.swift`) is the reference — `@Observable`,
`@MainActor`, with `@ObservationIgnored` caches for derived data that must not
retrigger a view update when filled mid-render.

One existing exception, not yet migrated: `OAuthIntegration`
(`HealthInsights/Core/Integrations/OAuthIntegration.swift`) is
`ObservableObject`/`@Published`, predating this convention. Left as-is rather
than refactored opportunistically — touch it only as part of a task that
already needs to change that file.

## Provenance and source merging

`MetricSource.deviceFamily` (`InsightKit/.../HealthMetricSample.swift`)
deliberately collapses the same physical device arriving via two paths — e.g.
Oura synced directly via its API *and* mirrored into Apple Health — into one
series, so a reading is never double-counted. `MetricSource.origin` /
`SourceOrigin` records *which* path each reading actually took (direct API vs.
Apple Health bridge vs. Apple Watch vs. manual/document), derived from the
source `id` so it survives losing the friendly display name on a persistence
round-trip. Use `origin` for labelling ("Oura via Apple Health"); use
`deviceFamily` for grouping/deduplication. Don't conflate the two.

## Static attributes vs. time-series vitals

Not every `MetricType` is a trend. `MetricType.presentation`
(`InsightKit/.../Presentation/MetricPresentation.swift`) is an **exhaustive**
switch (no `default:`) classifying each metric — adding a case fails to compile
until it's categorised:

- `.staticAttribute` — a standing fact (height). No chart, no timeframe picker,
  no log/linear toggle; rendered by `StaticAttributeCard`, formatted via
  `MetricValueFormatter` (locale-aware — `185 cm` / `6 ft 1 in`, never a bare
  metre count rounded to an integer).
- `.cumulativeTrend` — weight, body composition. Start/current/delta + a
  least-squares weekly velocity (`TrendSummary`), never first-minus-last.
- `.fluctuatingRange` — heart rate, HRV, SpO₂, sleep, etc. Min/max/mean/percentile
  (`RangeSummary`).
- `.cumulativeTotal` — steps, active energy. Bucketed **per source** and
  summed per day (`DailyTotals`) — never summed *across* sources, which would
  double-count a step taken with a phone in your pocket and a watch on your wrist.
- `.discreteBivariate` — blood pressure. The only metric addressed as a pair
  (`MetricSubject.bloodPressure`) rather than a single `MetricType`; carries its
  own AHA category bands, mean arterial pressure, and 30-day grounding split
  (`BloodPressureEstimator`).

`MetricDetailView` routes on `MetricSubject.presentation` via
`MetricViewStrategy` — a compiler-checked switch with one concrete `View` per
case, not a protocol returning `some View` (that would force `AnyView` and lose
SwiftUI's structural identity on a screen that re-renders every pan frame).

## Chart gap interpolation

`MetricType.maxValidInterval` (same file) sets the longest gap a chart line may
bridge before it breaks into a separate segment: 30 min for high-frequency
signals (heart rate, SpO₂), 24 h for daily-cadence ones (resting HR, HRV,
sleep), 14 days for infrequent ones (weight, VO₂max, blood pressure). Joining
two readings across a longer gap with a straight line asserts a trend that was
never measured, so `ScrollableMetricChart` draws one `LineMark` run per segment
from `SourceSeries.segments(maxGap:)` rather than one continuous line per
source.

Long ranges are **bucketed**, not decimated: `SourceSeries.bucketed(by:for:)`
(`InsightKit/.../Models/MetricAggregator.swift`) reduces a window to
mean/median/min/max per bucket using each metric's own rule (`bucketStatistic`
— median for weight so one water-weight day can't move the line, sum for
step-like totals, mean otherwise), which is what feeds the chart at `6M`/`Y`/`All`
zoom levels.

## BYO-Key direct API integrations (Oura / Withings / Whoop)

No backend: OAuth runs entirely on-device via `ASWebAuthenticationSession`
(`OAuthWebFlow`), and the user supplies their own developer Client ID (+ secret
where required) pasted into `ProviderSetupView`. Only the client ID is
required — `ProviderCredentialStore.credentials(for:)` treats an absent secret
as `""` rather than requiring both, because Oura's flow is PKCE and has no
secret; requiring one made that provider permanently unable to report having
credentials. Pasted values are sanitised with `.whitespacesAndNewlines` (not
just `.whitespaces` — a console copy usually carries a trailing newline) both
in the view and again in the store, so a stray character can't reach the
Keychain by either path. `CredentialValidator` gives inline feedback before the
network round-trip (catches pasting the redirect URI or console URL by
mistake) without being strict about actual key shape, since providers issue
UUIDs, hex strings and opaque tokens interchangeably.

### Scopes, 401s, and why the log must carry the response body

Oura returns **401, not 403, when a token is missing a scope** — it reserves 403
for a lapsed subscription — and names the scopes it wanted in the RFC7807
`detail` field of the body. So a token that fetches `daily_sleep` happily can
401 on `daily_resilience` in the same sync, and a log line that reads only
`HTTP 401` is undiagnosable. `ProviderAPIError` therefore unpacks every ≥400
body (`title` / `detail` / `error_description`, plus Oura's `x-trace-id`
header) into the diagnostics detail, along with a plain-English remedy per
status code.

Two more things make a partial grant visible rather than mysterious:

- The OAuth **callback** carries the scopes actually granted (`?code=…&scope=…`),
  which Oura warns "may be different than the scopes that were requested" —
  its consent screen lets the user switch scopes off individually. `connect()`
  captures that list into `OAuthTokens.grantedScopes`, logs anything withheld,
  and every sync re-states it. The token *response* has no scope field, so a
  refresh carries the stored list forward rather than losing it.
- `getJSON` refreshes the access token **once** on a 401 and retries. Without
  it, `validAccessToken()` only ever refreshed against the locally-stored
  expiry — and `isExpired` is `false` whenever the provider omitted
  `expires_in`, so a server-side revocation was unrecoverable. Refreshes are
  coalesced through a single in-flight `Task` and disabled for the rest of a
  sync once one fails, because Oura's refresh tokens are single-use: nine
  endpoints each refreshing on their own 401 would revoke the grant instead of
  repairing it.

**The scopes Oura doesn't document.** Its published scope table and OpenAPI
spec both list eight scopes (`email`, `personal`, `daily`, `heartrate`,
`workout`, `tag`, `session`, `spo2`/`spo2Daily`) and say nothing about which
endpoint needs which. Three collections need scopes that appear on neither
list, discovered only from the text of Oura's own 401 bodies:

| Collection | Scope |
| --- | --- |
| `daily_resilience` | `stress` |
| `daily_cardiovascular_age` | `heart_health` |
| `vO2_max` | `heart_health` |

`OuraProvider.requiredScope` holds that mapping, but **only to name the scope
in the summary when a rejection didn't spell it out — never to pre-empt a
call.** An earlier build skipped collections whose scope looked absent from
`grantedScopes` and got it badly wrong: Oura doesn't reliably return `scope` on
the callback, so "didn't say" was read as "granted nothing" and three
collections were withheld without ever being tried. Hence `grantedScopes` stores
`nil`, never `[]`, for an unreported grant, and nothing may withhold a request
on the strength of it. Oura's own 401 is the only authority.

A scope 401 is never retried — `ProviderAPIError.missingScope` recognises
Oura's "Token is not authorized access <scope> scope" phrasing, and a fresh
token carries the same grant, so retrying only spends a single-use refresh
token and logs the failure twice.

Enabling a scope on the Oura application does nothing by itself: the grant is
baked into the token. Nor is reconnecting always enough — with an authorization
already on file, Oura can reissue against the old grant without showing a
consent screen, so the user must revoke the app in their Oura account first.

Oura's developer console has moved to `developer.ouraring.com/applications`;
the OAuth authorize/token endpoints did not move with it.

Known gap, surfaced in the log rather than silently swallowed: Oura paginates
with `next_token` and the client reads only the first page, so
`OuraProvider.describeResponse` logs a warning naming the collection whenever
more pages exist.

## Ingestion pipeline (provider payload → vitals)

`InsightKit/Sources/InsightKit/Ingestion/`. Providers fetch bytes; the pipeline
decides what they mean. Nothing in it knows a provider by name.

```
IngestPayload (raw bytes + source + endpoint)
   → PayloadIngestor        — EnvelopeSpec says where records live and how they're dated
   → JSONFlattener          — recursive walk to typed leaves on dotted paths
   → FieldCatalogue         — persisted registry; first sighting of a path is an event
   → PromotionRuleSet       — path/leaf/suffix → MetricType (+ unit conversion), as data
   → IngestionResult        — raw samples, promoted vitals, new fields, proposals, skips
```

Four rules this design exists to enforce:

1. **Everything is captured, and the exceptions are counted.** `RawValue` is
   `number | text | flag`, so strings and booleans survive — Oura's resilience
   `level`, its sleep hypnogram, Withings' `comment`. Anything not stored
   becomes a `SkippedField` with a reason, reported in Troubleshooting, so
   "100% ingested" is auditable rather than aspirational.
2. **Numeric arrays are summarised, not exploded.** Oura's 5-minute night
   series would add ~40k samples per sync for data Apple Health already
   mirrors, so `heart_rate.items` becomes count/min/max/mean/first/last.
   `FlattenPolicy.arrayStrategy = .expand` switches a field to literal
   point-by-point capture when it earns it.
3. **A new connector is a declaration.** `GenericJSONIngestor` covers Oura and
   Whoop from an `EnvelopeSpec` alone. `WithingsMeasureIngestor` exists only
   because Withings sends `(type, value, unit)` triples instead of named
   fields — the escape hatch, not the pattern.
4. **Promotion is data, never inference.** A rule promotes; a field that merely
   *looks* like a known vital is catalogued and logged as a proposal. A
   provider renaming a field can therefore never silently rewire an insight.

`AppModel.refresh()` runs the pipeline before the cache merge and before
`recompute()`, so a field discovered this sync reaches insights in the same
sync.

## Which vitals feed which insight

Kept current deliberately — a metric with no reader is imported, charted and
then ignored, which is how `heartRate`, `walkingHeartRateAverage`,
`oxygenSaturation`, `bodyTemperature` and the whole body-composition tail sat
unused despite tens of thousands of samples.

| Metric | Read by |
| --- | --- |
| heartRate, walkingHeartRateAverage, bodyTemperature | Vitals Check |
| restingHeartRate | Readiness, RHR Trend, Heart Health, Heart Age, Vitals Check |
| HRV (SDNN / rMSSD) | Readiness, Heart Health, Vitals Check |
| oxygenSaturation | Readiness, Sleep Quality, Vitals Check |
| respiratoryRate | Readiness, Sleep Quality, Vitals Check |
| skinTemperatureDeviation | Readiness, Sleep Quality |
| sleepDurationHours | Readiness, Sleep Quality |
| vo2Max | Cardio Fitness, Cardio Trajectory, Heart Age |
| vascularAge | Heart Age (as a second opinion, never merged into ours) |
| bodyMass, bodyFatPercentage, height | Body Composition |
| leanBodyMass, muscleMass, boneMass, bodyWaterPercentage | Body Composition |
| bloodPressureSystolic/Diastolic | Blood Pressure, Heart Age, Cardiovascular Risk |
| stepCount, activeEnergyBurned | Cardio Trajectory |
| dayStrain | *(no reader — Whoop not connected)* |

## Keychain storage

Two layers: `KeychainStore` (`HealthInsights/Core/Persistence/KeychainStore.swift`)
is a generic get/set/delete wrapper over a `kSecClassGenericPassword` item,
`kSecAttrAccessibleAfterFirstUnlock`. `ProviderCredentialStore` is the typed
layer on top, namespacing keys by provider id (`"\(providerID).clientID"`,
`.clientSecret`, `.tokens`). Nothing health-related is stored here — only OAuth
client credentials and tokens.

## Verification

- `cd InsightKit && swift test` — checks the risk equations against published
  worked examples and the statistics against hand-computed fixtures. This is
  the primary local gate: no Swift toolchain runs in most agent sandboxes, so
  final compile/behaviour verification happens via the CI workflow's
  `swift test` + `xcodebuild` steps on push.
- Open `HealthInsights.xcodeproj` in Xcode 16+ and run on a device/simulator
  with Health data. (If the project won't open, regenerate it with
  `xcodegen generate`.)
