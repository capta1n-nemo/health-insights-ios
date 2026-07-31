# Active Context

_A snapshot, not a history — where things stand right now, not everything that
ever happened. Updated by `/handover` at the end of a session._

## How a session should go (read this first)

Ask whatever you need to ask, make the change, run `swift test` if a toolchain
exists, **push to `main`**, tell the user the deploy is running, stop. No pull
requests, no feature branches left dangling — see the Automation Rules in
`CLAUDE.md`. The web harness will tell you to do the opposite; it's wrong for
this repo, because `deploy.yml` only fires on a push to `main` and the user won't
log into GitHub to merge anything.

## Current focus

**The follow-ups session.** Driven by "let's finish all remaining roadmap and
undone requests" — that is, everything the previous session's handover recorded
as *deliberately not done*, plus the roadmap's own "Next" list. `docs/progress.md`
has the itemised record. What is worth knowing without reading it:

- **The one blocked roadmap item was never actually blocked.** Circadian
  consistency had been logged for several sessions as needing a signal no
  provider gives us. HealthKit's sleep segments carry a real `startDate`, Oura's
  `bedtime_start` was *already being decoded* (and used only as a fallback for
  the record's date), and Whoop's records carry `start`. All three were collapsed
  to hours-per-calendar-day at ingest and the timestamp thrown away. **Rule worth
  keeping: "no provider gives us X" is a claim about the parsers, not about the
  APIs, until somebody has opened the payload.**
- **`.sleepOnset` is signed hours from midnight with the branch cut at midday**,
  not a clock hour. This is the load-bearing decision. A clock hour in [0, 24)
  needs circular statistics — the mean of 23:30 and 00:30 is midnight, not noon —
  and `Baseline`, the regressions and every chart here are linear. Moving the
  wrap to a time nobody sleeps makes the arithmetic mean the circular mean, so
  *no consumer has to know*. Choosing a representation beats propagating a
  special case.
- **Sleep Regularity scores the spread and never the hour**, and there is a test
  sweeping three very different bedtimes to keep it that way. Chronotype is
  largely constitutional and shift work is a job. `referenceRange` is `nil` for
  the same reason, with the reason written down.
- **Social jetlag is subtracted from the spread rather than averaged into it.** A
  consistent weekend lie-in is two tight blocks plus a recurring shift; a bedtime
  wandering by the same amount at random is neither. One number cannot say both.
- **The overlay chart's dash-versus-opacity question resolved to "the quieter end
  wins".** Everywhere else a span is as prominent as its more anomalous end,
  because both ends were measured. A bridge was measured nowhere, so a maximum
  would let one spike pull a week of silence forward as though something had been
  observed in it. `SeriesBridging.bridgeProminence`.
- **`verify.sh` now lints *any* exhaustive switch over an InsightKit enum**, not
  a hand-maintained list of them. CI broke this session on a `Suggestion.Basis`
  switch in `InsightsListView` that no list mentioned — the same shape as the
  `.vitalSigns` break before it. Swift already requires a `default:`-free switch
  to name every case, so the check needs no per-switch knowledge. Two canaries
  prove it fires.

### What is still not done, and why

- **On-device verification of everything since the last device-verified build.**
  Nothing in this session or the previous two has been seen on the phone. CI
  proves it compiles; both regressions two sessions ago were caught by the user's
  screenshots, not by CI.
- **`EnergyModel.exertionHours` still weights every heart-rate sample equally.**
  Deliberate and commented — a watch's own sampling gaps are not idle time, and
  using real inter-sample intervals needs a decision about what a gap means.
- **`AppModel.swift` (786 lines) and `InsightDetailView.swift` (653) are the two
  largest files and are deliberately unsplit.** Swift's `private` is file-scoped,
  so an extension-based split widens every member the moved code touches, and
  both are dense with private state. The other four splits are done.
- **New provider integrations** (Hume direct, Ultrahuman, Garmin, Fitbit) need
  the user's own developer credentials per provider and cannot be tested from
  here at all. Same for the VisionKit scanner and ECG import — device-only
  surfaces with no test path.
- **Filled `AreaMark` min/max bands** still want a dedicated compile-spike
  against the SDK hazard. Note that `SubstanceLoadChart` and now
  `EnergyCurveChart` both use a *single-series* `AreaMark` safely; the hazard was
  always about two-series filled bands.
- **Oura's ~4–6 months of history** is still unexplained. Offered, not taken up.

## Two regressions I shipped, and what they cost

Both were caught by the user's screenshots, not by CI, and both have the same
root cause: **the rule lived in the view layer where no test could reach it.**

1. **Two identical reds.** "Draw only the anomalous ones" is not by itself a
   small number — thirteen vitals with nine departing is an ordinary week, so the
   ninth line wrapped onto a hue already in use.
2. **Steady signals drawn as notable**, contradicting the legend one line below.

Fixed by moving the rule into `InsightKit/Sources/InsightKit/Presentation/OverlaySelection.swift`
and testing it against the screenshot's own shape. **Rule worth keeping: if a
piece of logic decides whether two things can look alike, or whether a number is
right, it belongs in InsightKit.** The app target has no test target — anything
that lives there is verified only by eye.

## The Oura scope answer (don't re-derive this)

Oura returns **401, not 403, for a missing scope** — it reserves 403 for a
lapsed subscription — and names the scope in the RFC7807 `detail` of the body.
Neither its published scope table nor its OpenAPI spec (v1.37, eight scopes)
documents which endpoint needs which. Learned from its own error text:

| Collection | Scope |
| --- | --- |
| `daily_resilience` | `stress` |
| `daily_cardiovascular_age` | `heart_health` |
| `vO2_max` | `heart_health` |

Also: Oura's developer console moved to `developer.ouraring.com/applications`
(the OAuth authorize/token endpoints did **not** move). And Oura does **not**
reliably return `scope` on the OAuth callback, despite documenting that it does.

## Recent architectural choices worth knowing

- **Choose a representation instead of propagating a special case.** `.sleepOnset`
  could have been a clock hour with circular statistics, and then `Baseline`,
  every regression and every chart would have had to know which metric they were
  holding. Moving the branch cut to midday made the linear machinery correct by
  construction. When one value type would make everything downstream an
  exception, look for the encoding that makes it not one.
- **"No provider gives us X" is a claim about the parsers.** Circadian consistency
  sat blocked for sessions on a signal that was in every payload and was being
  discarded at ingest. Before recording something as blocked on a missing signal,
  open the payload.
- **Merge overlapping spans before shading them.** Three logs in a morning drawn
  as three translucent rectangles compound into a darker band, which encodes *how
  many* in a channel meant to say only *whether*. Same class of error as two
  identical reds: an encoding that carries information nobody intended.
- **A generic lint beats a maintained list of lints.** The exhaustive-switch check
  named each switch individually and therefore only caught the ones somebody had
  remembered. Swift's own rule — a `default:`-free switch names every case — is
  enough to check the class rather than the instances.
- **Don't ask for a permission you don't use.** Oura's `heartrate` scope was
  requested for months and never called. Removing it costs a comment naming the
  three steps to reinstate.

- **A shared reader beats a shared convention.** Every insight "knew" it should
  read a daily, de-duplicated, windowed value; every insight wrote its own and
  got it wrong differently. `VitalReader` is the convention made a type. When you
  find the same four-line pattern in five files with five bugs, extract it —
  don't document it.
- **Freshness is reported, not enforced.** `VitalReading.isFresh` is a fact; what
  it *means* is the insight's call. Readiness drops a stale component (it's a
  claim about today); Heart Health keeps one (VO₂max updates every few weeks by
  design). A single global staleness rule would have been wrong for one of them.
- **Presentation logic that can be wrong belongs in InsightKit.** The app target
  has no test target. `OverlaySelection` and `MetricPalette` decide whether two
  lines can look alike — that is a correctness question, not a styling one, and
  both regressions this session came from having it in the view.
- **A tri-state flag beats a Bool when "we didn't check" is a real state.**
  `InsightDriver.isNotable: Bool?` — `nil` means the insight doesn't draw the
  distinction, which must not render as "everything is fine".
- **Two copies of a clinical threshold need a test binding them.** The
  blood-pressure bands exist in `Category.of` (classify) and `systolicRange`
  (shade). `PressureBandTests` sweeps every value from 80 to 210 and asserts each
  lands inside the band its own classifier assigned it.
- **Encoding that is technically safe can still be practically wrong.** The
  (hue, dash) pair was collision-free by construction and validated with a
  colour-blindness tool. It still failed, because dash carries a *meaning* to
  readers — "estimated / missing" — that no separation metric measures. Check
  what an encoding says, not just whether it's distinguishable.
- **Providers fetch bytes; the pipeline decides what they mean.** `SyncedData`
  now carries `payloads: [IngestPayload]` alongside samples. A provider's typed
  parser contributes only the handful of fields it has *unit and semantic*
  knowledge about; everything else in the document is the pipeline's job. That
  inversion is why a field Oura added this morning reaches the vitals layer with
  no code change.
- **`RawValue` is `number | text | flag`,** encoded as a bare JSON scalar. The
  bare-scalar choice is load-bearing: caches written when `RawMetricSample.value`
  was a `Double` decode straight into `.number(...)`, so the migration is free.
  There is a test pinning this — don't "tidy" it into a tagged object.
- **Numeric arrays summarise, they don't explode.** Oura's 5-minute night series
  (`heart_rate.items`, ~200/night) becomes count/min/max/mean/first/last.
  Expanding literally would add ~40k samples per sync for data Apple Health
  already mirrors. `FlattenPolicy.arrayStrategy = .expand` is the per-field
  switch if a series ever earns it. Chosen deliberately with the user.
- **Promotion is data, never inference.** `PromotionRuleSet` maps
  path/leaf/suffix → `MetricType` with unit conversion. A field that merely
  *looks* like a known vital (alias match, no rule) is catalogued and logged as
  a **proposal**. This is what stops a provider renaming a field from silently
  rewiring an insight. Also chosen deliberately with the user.
- **Empty ≠ unknown.** `OAuthTokens.grantedScopes` stores `nil`, never `[]`, and
  **nothing may withhold a request on the strength of it.** A build that skipped
  collections whose scope looked absent read "provider didn't say" as "granted
  nothing" and suppressed the very sync that would have proven the fix worked.
  The provider's own 401 is the only authority.
- **A scope 401 is never retried.** `ProviderAPIError.missingScope` recognises
  Oura's phrasing; a fresh token carries the same grant, so retrying only spends
  a single-use refresh token and logs each failure twice. Refreshes are coalesced
  through one in-flight `Task` and disabled for the rest of a sync after a
  failure, because Oura's refresh tokens are single-use — nine endpoints each
  refreshing on their own 401 would revoke the grant outright.
- **Vascular age is a second opinion, not an input.** Oura's estimate became its
  own `MetricType.vascularAge` rather than being merged into `HeartAgeInsight`'s
  own calculation. Two models built on different inputs disagreeing is
  information; averaging them away is not. VO₂max went the *other* way — Oura's
  joins the existing `.vo2Max` metric as another source, matching how heart rate
  and weight already work.
- **Ages, not just percentages.** `HeartAgeModel` inverts SCORE2/ASCVD over age
  against an optimal-risk-factor reference person (the published Framingham
  vascular-age method). No new equation — the shipped ones read backwards. Each
  engine is inverted **only inside its own validated band** (SCORE2 40–69, ASCVD
  40–79) and returns `isCapped`, which the UI voices as "79 or older" rather than
  printing an extrapolated number. `FitnessAgeModel` does the same trick on the
  VO₂max norm table `HeartHealthScore` already scores against, so the two can't
  disagree about "average for your age".
- **Lifetime risk was deliberately not faked.** The roadmap asked for lifetime
  framing. Nothing here is validated past 79 and compounding decades of 10-year
  risk would invent a number, so `HeartAgeModel.projection` runs the same
  equations at future ages they *are* validated for, labelled "if today's numbers
  hold". If a real lifetime figure is wanted it needs a different published model
  (JBS3 has one) — that's new work, not a tweak.
- **A trajectory is judged against ageing, not zero.** `VO2Trajectory` compares
  the least-squares VO₂max slope to the norm line's own slope at that age, so
  holding level scores *above* mid-dial. `netPerYear` is that comparison;
  `fitnessYearsGained` is the trajectory's effect on fitness age alone. Keep them
  separate — adding them double-counts.
- **`MetricSubject`** (not raw `MetricType`) is what a detail screen addresses,
  because blood pressure is inherently a systolic/diastolic pair.
  `MetricDetailView` keeps `init(metric:)` for backward compatibility; prefer
  `init(subject:)` when the subject might be blood pressure.
- **`ScrollableMetricChart`** owns all pan/zoom/scrub/axis-scale logic for every
  chart in the app. `MultiSourceChart` and the blood-pressure chart both wrap it.
  Any new chart type should too, rather than growing its own copy.
- **Swift Charts `Chart3DContent` overload-resolution hazard**: on the current
  SDK, a `RuleMark`/`AreaMark`/`BarMark` chain built without an explicit
  `some ChartContent` return type can silently resolve to 3D chart content and
  lose modifiers like `.lineStyle`/`.annotation`. Always give mark-building
  helpers an explicit `-> some ChartContent`. This caused two CI failures in one
  session — a known trap, not a one-off.
- **Never start a continuation line with `...`** in Swift — it parses as a
  standalone prefix `PartialRangeThrough`, not a continuation of the range above.

## The sandbox has a Swift toolchain now — use it

This section used to say the opposite, and that was the single most expensive
false belief in the repo: it meant every logic error was found by pushing and
waiting ~90 s for CI.

`InsightKit` was always meant to be platform-free, but two Darwin-only
Foundation APIs had crept in (`Measurement.formatted` and `CFBooleanGetTypeID`)
and CI runs on macOS, so nothing caught them. Both are behind
`#if canImport(Darwin)`. **330/330 tests pass on Swift 6.0.3 / Ubuntu 24.04.**

```bash
./scripts/verify.sh --tests     # installs the toolchain if absent, then runs
```

The container is rebuilt per session so the toolchain never survives, but the
gate **self-heals**: `verify.sh --tests` bootstraps Swift itself rather than
telling you to. Nothing depends on this document being read. Better still, put
`./scripts/bootstrap-swift.sh || true` in the environment's setup script and it
costs no session time at all — see `docs/deployment.md`.

`xcodebuild` is still macOS-only, so the **app target** is compiled only by CI.
Local green means InsightKit is green: the clinical maths, scoring, baselines
and parsers — which is where the bugs have actually been.

Still worth care, because nothing local checks them: key paths don't work on
tuple elements (`\.volume` on a tuple is a compile error — use `{ $0.volume }`),
and don't shadow a function with a local of the same name. `scripts/verify.sh`
checks the first of those.

Adding a `MetricType` or an `InsightID` case is deliberately load-bearing: both
feed exhaustive switches. **This bit CI again this session** — `.vitalSigns` was
added to the engine and cadence but not to the four switches, so the build broke.
The complete list, verified by grepping for the enum's last case:

- `MetricType`: `displayName`, `unit` (both in `MetricType.swift`),
  **`family`**, **`chartStyleIndex`**, `presentation`, `maxValidInterval` (all
  four in `MetricPresentation.swift`), `requiresPositiveValue`
  (`Signals/MetricSanitizer.swift`). `bucketStatistic`, `inSentence` and
  `MetricValueFormatter` are safe — the first has a `default:`, the second is
  derived from `displayName`.
  `colourSlot` and `sharesMeasurementBasis` are **derived**, not switches, so
  they no longer need touching. `chartStyleIndex` must stay contiguous from zero
  (`testStyleIndicesAreContiguousFromZero` pins it) so the metrics most likely to
  share a chart keep first claim on the eight hues.
- `InsightID`: **five switches, not three** — this list was itself stale and is
  now verified. `cadence` (`Insight.swift`), `modelVersion` (`Feedback.swift`),
  `prettyInsight` (`TelemetryOutboxView`), `iconName` (`DashboardView`),
  `insightTint` (`Theme.swift`). Only `modelVersion` and `prettyInsight` are
  exhaustive; the other three have a `default:` and so fail *silently* — wrong
  tab, wrong icon, shared hue. Plus registration in `InsightEngine`, which
  breaks nothing and simply makes the card never appear.
  **Use the `add-insight` skill rather than this summary.**
  **`primaryMetric` in `InsightDetailView` is gone** — the detail screen now
  charts `InsightResult.contributors`, which the scoring code emits itself, so
  that switch no longer exists to fall out of date.

Adding an `InsightModel` also requires `candidateMetrics` (no default
implementation, so it won't compile without one). `MetricColourSlotTests` no
longer depends on what co-occurs — it asserts that *any* set up to the palette
size resolves to distinct hues, so adding a metric to an insight can't break it
from a file that never mentions colour. That was deliberate: the previous version
encoded a belief about co-occurrence, and the belief shipped wrong.

Do this grep *before* pushing, because CI is the only thing that will tell you.

## Lesson worth keeping: suspect your own precheck first

Four deploy runs "failed to find the phone." The cause was not the phone. The
install step's guard demanded `connectionProperties.tunnelState == "connected"` —
but a paired, perfectly installable iPhone commonly reports `available (paired)`,
and `devicectl` opens the tunnel on demand. The guard was rejecting a working
device. Each failure came with a plausible user-side explanation (phone locked,
VPN, off Wi-Fi, Xcode not signed in) and each was accepted instead of questioning
the check doing the rejecting. Fixed in `122d2c6`.

Rule: when a self-written guard reports an environmental failure repeatedly,
verify the guard's premise against raw tool output before asking the user to
change anything about their environment.

## Known gotcha: memory files may not auto-load

`CLAUDE.md` and `.claude/commands/handover.md` live in **this repo's** root. If a
session's working directory is a *different* repo with this one attached
alongside, Claude Code may not discover either — `/handover` comes back "Unknown
command" and `CLAUDE.md` isn't auto-read. Slash commands are registered at session
start, so a newly-created one never works in the session that created it. Start
sessions with `health-insights-ios` as the working directory; otherwise run the
handover steps by hand and paste `CLAUDE.md` into the new chat.

## Lesson worth keeping: don't let a guess pre-empt the authority

The scope skip described above cost the user a deploy cycle and a round of
pointless account-fiddling (revoking an Oura authorisation that was already
correct). The app *inferred* that a permission was missing and acted on the
inference by not making the call — which destroyed the evidence that would have
shown the inference was wrong.

Rule: when a remote system is the authority on whether something is permitted,
ask it. A local prediction may inform a warning; it must never replace the
request. This is the same failure shape as the `tunnelState` guard below.

## Immediate next steps

The ten-item feedback list is closed and so is every roadmap item that could be
closed from a sandbox. What remains falls into three groups.

### 1. Only the user can do these

- **The on-device walkthrough.** Nothing from the last three sessions has been
  seen on a phone. Newest first:
  - **Energy ▸ Today** — an area chart of the day's curve with a dashed line at
    the morning charge, and "N spent of M" in the header. Check it renders before
    the score history, and that scrubbing reads the hour.
  - **Insights ▸ Sleep Regularity** — a new card. Check it appears at all (it
    needs five nights with a recorded sleep time), that the headline reads like
    "Regular · 23:10", and that the weekend line only shows when there is a real
    shift.
  - **Any vital chart with substance logs behind it** — faint grey vertical
    columns for the 18 hours after each log, merged where they overlap, with the
    caption underneath. Confirm they do *not* look like the horizontal reference
    bands on the same chart.
  - **An insight detail overlay with a gap in one series** — the gap should now
    cross with a dashed connector, visibly dimmer than the measured line either
    side of it.
  - **Vitals ▸ Sleep & recovery** — a "Sleep Onset" row, rendering as a clock
    time rather than a number.
  - **The overlay chart** — no two drawn lines share a colour; steady signals
    are off the chart by default and in the list below it, ordered most-departed
    first and each row tappable; more than eight selected shows the "colours
    repeat" warning rather than repeating them silently.
  - **Heart & Fitness Age** opens with both ages plotted against the
    chronological line, and the pace sentence reads as "gaining on it" / "running
    ahead" rather than a bare slope.
  - **Blood pressure** shows shaded systolic bands with the diastolic limits as
    thin rules, and the caption explaining which is which.
  - **"What's driving this"** leads with departures and folds the routine lines
    behind the disclosure.
  - **Vitals Check** on Today reads "All normal" on a quiet day and names the
    outlier when there is one; **Other data** renders Oura's resilience `level`
    as text with a States tally rather than an empty chart; Cardio Fitness shows
    two sources (Apple Watch + Oura); Heart Age prints Oura's vascular age line;
    Body Composition shows lean/muscle/bone/water with the fat-vs-muscle
    narrative.
  - **The paste prompt is gone** from Settings ▸ Data sources ▸ Oura. Clipboard
    autofill was removed because reading `UIPasteboard` raised iOS's "Paste from
    your Mac?" prompt on every appearance. Do not reintroduce clipboard *reads*
    there; writes (Copy buttons) are fine.
  - Oldest: the three-age row on Heart & Fitness Age (narrowest device); a
    profile with no blood pressure showing the fitness half alone; Heart Rate at
    `All` *and* `Y`; Weight's gap-broken line and weekly velocity; provenance
    badges and the Inactive section; drag-to-scrub; Height as a plain card; blood
    pressure from all three entry points.
- **Whether Oura's ~4–6 months of history is an account boundary or a re-pair.**
  A 730-day window returns 171 sleep records, 128 daily_activity, 107
  daily_readiness, with **no `next_token`** — so that is genuinely all Oura will
  serve, and pagination (now implemented) will not change it. Apple Health holds
  128,302 Oura-mirrored samples. Byte counts match record counts, so nothing is
  truncated client-side. Offered several sessions ago, not taken up.
- **New provider integrations** (Hume direct, Ultrahuman, Garmin, Fitbit). Each
  needs the user's own developer credentials, and nothing about them can be
  exercised from a sandbox.

### 2. Deliberate non-decisions, with the reasoning recorded

- `EnergyModel.exertionHours` weights every heart-rate sample equally. Crude, and
  says so; real inter-sample intervals need a decision about what a gap means.
- `AppModel.swift` and `InsightDetailView.swift` stay unsplit — see above.
- Filled `AreaMark` min/max bands still want a compile spike.
- `.sleepOnset` resolves against `Calendar.current`, not the offset the provider
  stamped. Right at home, wrong on the second night of a trip. Both HealthKit and
  Oura behave the same way, so the sources at least agree with each other.

### 3. Genuinely open work, cheapest first

- **A chart for Sleep Regularity's own shape.** The card reports a spread and the
  detail screen draws the score history like everything else. What it wants is a
  strip of the fortnight's onsets against their own centre — the picture of
  "regular" — and `.sleepOnset` charts as an ordinary metric today.
- **Sleep onset in the promotion rules**, so a provider that starts reporting a
  bedtime under a different field name reaches `.sleepOnset` without a parser
  change. Today three parsers each hand-build it.
- **Foundation Models structured extraction for arbitrary lab analytes**, and the
  VisionKit live scanner. Both are on the roadmap and both are device surfaces
  with no test path from here.
- **Core ML personal anomaly detection**, once there is enough history.

