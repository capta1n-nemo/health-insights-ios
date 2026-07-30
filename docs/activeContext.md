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

**Every card held to the standard Vitals Check was rebuilt to** (this session,
six pushes, all CI-green: `1de13c1` → `084f70f`). Driven by the user's
observation — "you've only applied these changes to the vitals check card, all
the improvements should apply to every card" — plus a ten-item feedback list and
two device screenshots that caught two of my own regressions.

Full rationale is in `docs/architecture.md` ▸ "`VitalReader`: one way to read a
vital", "Chart identity: hue alone, and a bounded number of lines", and the
patterns note under "Insights tab: the deep dive". What's worth knowing without
reading it:

- **`VitalReader` is now the only honest way to read a vital.** Four insights
  moved onto it this session; **six still bypass it** (see the audit table
  below), so this is half-done, not done. Of the four, Heart Health's was worst:
  resting heart rate came from the mean of *every* sample ever recorded, which
  over a 180-day lookback cannot move.
- **Four scores were wrong, not just imprecise.** Sleep consistency read 0/100
  (it measured fragmentation, not sleep). Blood pressure passed `score: nil`
  unconditionally. Heart age hit exactly zero from fifteen excess years on, and a
  *capped* fitness age reaches forty years of excess on the bound alone.
- **Dash is retired as identity.** It was a globally-unique (hue, dash) pair,
  measurably collision-free — and practically wrong, because a dashed line reads
  as *an estimate or a gap*. The user reported the dashes as gap markers, which
  is the correct reading of that ink. Dash now means "not measured" only.
- **The chart can't outrun its palette.** Hue alone means the *number of lines*
  must stay inside eight. `OverlaySelection` decides which are drawn and the
  legend is a picker — every signal individually tappable, ordered most-departed
  first.
- **"Away from baseline" is recent-or-sustained, not ever.** The first version
  asked "did any day depart", so a flat line with one blip three weeks ago was
  drawn as notable while the legend beside it said "steady".
- **Patterns stopped reporting their own arithmetic.** HRV against heart rate
  comes off the same beat-to-beat interval stream; it was reaching the card as
  the *top* finding at r = −0.71.

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

## Working constraint: no Swift toolchain in the sandbox

`swift` does not exist in Claude Code web sessions, so `swift test` and
`xcodebuild` cannot run before a commit. The honest workflow is: reason carefully
(the compiler can't catch you here), push, and let CI be the gate — then fix
forward on red. Things worth extra care because nothing local checks them:
key paths don't work on tuple elements (`\.volume` on a tuple is a compile
error — use `{ $0.volume }`), and don't shadow a function with a local of the
same name (`if let contrast = contrast(...)`).

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

The user's ten-item feedback list is the working agenda. Status below was
**audited against the code**, not recalled — every claim has a file reference in
the audit that produced it. Items 5, 6, 8 (score half) and 9 are done and are in
`docs/progress.md` ▸ "Every card held to the same standard".

### 1. Verified defects worth fixing first

- **Body temperature is judged in the wrong domain — start here.** Audited and
  confirmed, and it is worse than first flagged. Four compounding faults:

  1. **`hardLow` (35.5) is exactly `TemperatureReconstructor.defaultBaselineCelsius`
     (35.5).** A reconstructed value is `baseline + deviation`, so `value < hardLow`
     reduces to **`deviation < 0`**. Any cool night at all trips the bound. A
     routine −0.1 °C scores normality 32.7 (penalty 67.3), and `VitalSignsCheck.score`
     is worst-offender-dominant — so one ordinary night tanks the whole card.
  2. **`hardHigh` (37.8) can never fire on reconstructed data**: it needs
     `deviation > +2.3 °C`, while the app's own `skinTemperatureDeviation` spec
     treats ±1.5 as the outer bound of plausible. A real febrile night (Oura
     typically +0.8 to +1.2) reconstructs to 36.3–36.7 °C and is invisible to
     both bounds.
  3. **Both temperature rows are always present and double-counted.**
     `withReconstructedTemperature` returns `samples + reconstruct(samples)` —
     additive, not a replacement. Their z-scores are *mathematically identical*
     (adding a constant to every sample shifts the mean, not the SD), so the same
     physiological signal enters `penalties` twice: once correctly scaled as a
     deviation, once mis-bounded as an absolute.
  4. **Routing real thermometer readings into `readMap` made it worse, not
     better.** Reconstruction still runs unconditionally, so `.bodyTemperature`
     is now a *mixture* of core and skin values under one set of bounds — and the
     reconstructor learns its baseline from whatever absolutes exist, so a user
     with a real 36.8 °C reading gets skin deviations added to a **core**
     baseline.

  **Root cause is provenance loss**: `reconstruct()` writes its output as
  `.bodyTemperature` and erases the fact that it is skin-derived, after which no
  consumer can tell the two apart. The fix is to give skin its own identity — a
  `.skinTemperature` `MetricType`, or a `basis` flag on `HealthMetricSample` — so
  the `bodyTemperature` spec only ever sees genuine core readings. Whoop
  (`WhoopResponseParser.swift:48`) and Withings type 73
  (`WithingsResponseParser.swift:65`) route there too.

  **No test would catch any of it.** The only `bodyTemperature` fixture in the
  Vitals suite is 36.6 °C (`VitalSignsTests.swift:80`) — a genuine core reading,
  precisely the one shape where the bounds behave. `NewInsightsTests.swift:23-25`
  even builds the −0.3 deviation case whose reconstruction would be flagged
  `.unusual`, then stops at the arithmetic assertion.
- **`BloodPressureEstimator.maintenanceReadingsPerMonth = 2` is dead code.**
  Declared at `BloodPressureEstimator.swift:22` and never read. `CalibrationStatus.required`
  (:76) hard-wires to `initialCalibrationReadings` (5) forever, so the app demands
  five readings every thirty days rather than five once and two a month after.
  That is item 8's "drift counter" half, and it is a small fix.
- **Cholesterol renewal is 12 months in code, 6 in the spec.**
  `GroundingInput.swift:44-45` sets `365 * 24 * 3600`. One-line value change.
- **Cardiovascular Risk still has a step-function score.** `riskBand`
  (`CardiovascularRiskInsight.swift:189-195`) maps the whole risk range onto
  {90, 72, 45, 20} — 4.9% dials 90 and 5.1% dials 72, an 18-point drop across two
  tenths of a percentage point. Exactly the defect fixed in Vitals Check and
  Heart Age; this card was missed.
- **Body Composition is the only unconditional `score: nil`**
  (`AdditionalInsights.swift:305`). The comment says the card "narrates rather
  than scores", which may be the right call — but it means the card can never
  show a dial even with a full smart-scale dataset. Decide deliberately.
- **Blood pressure scores nil on most days.** The score is set only from a cuff
  reading under 24 hours old, or from the experimental estimate when it is
  grounded. Anyone who cuffs weekly sees an empty bubble six days in seven. The
  24-hour rule is right for *trusting* a reading; it may be wrong for *showing*
  one, and that is a product decision, not a bug.
- **Substance Impact is not an `InsightModel`.** It ships as a card but is built
  by a free function and is invisible to `InsightEngine` (which registers
  eleven models; `.substanceImpact` is not among them). It also passes
  `score: nil`. Anything applied "to every insight" silently skips it.

### 2. Score-and-reader audit, every insight

Audited card by card. "Done" means it produces a defensible score **and** reads
its inputs through `VitalReader`.

| Insight | Score | Reads via `VitalReader` |
| --- | --- | --- |
| Readiness | ✅ continuous composite | ✅ |
| Heart Health | ✅ continuous, age-adjusted | ✅ |
| Sleep Quality | ✅ five weighted components | ✅ |
| Resting HR Trend | ✅ level + drift | ✅ |
| Vitals Check | ✅ Gaussian, worst-dominant | ❌ re-implements it inline |
| Cardio Fitness | ✅ ratio to age/sex norm | ❌ `vo2Series.last?.value` |
| Cardio Trajectory | ✅ net-of-ageing slope | ⚠️ de-dupes, but fits over raw samples |
| Cardiovascular Risk | ❌ four-step function | ❌ `latestValue` |
| Heart & Fitness Age | ✅ logistic | ❌ `latestValue` |
| Blood Pressure | ⚠️ nil on most days | ❌ raw throughout |
| Body Composition | ❌ unconditional `score: nil` | ❌ |
| Substance Impact | ❌ `score: nil` | ❌ — **not an `InsightModel` at all** |

### 3. Still to read through `VitalReader`

Four insights moved onto it; six did not, and each hand-rolls the reads it
replaces:

- `CardioFitnessInsight` — `vo2Series.last?.value`, no de-duplication.
- `CardioTrajectoryInsight` — de-duplicates and checks staleness, but fits its
  regression over raw samples rather than daily values.
- `CardiovascularRiskInsight`, `HeartAgeInsight` — `samples.latestValue(...)`.
- `BloodPressureInsight` — raw throughout.
- `VitalSignsInsight` — **re-implements `VitalReader` inline.** It is where the
  fix came from, so the two agree today; they are still two copies of one rule.

### 4. Greenfield, in the user's priority order

- **Item 1 — Today summary refresh.** Nothing gates it: `RootView.swift:24`
  refreshes on every appearance and `AppModel.swift:354` summarises
  unconditionally, so every app open pays a full FoundationModels round-trip.
  Three `.refreshable` modifiers call `refresh()` with no cooldown. Needs a data
  fingerprint compared against the one stored with the last summary, plus a
  30-second floor on manual refresh.
- **Item 2 — "Improve Your Health" suggestions.** Greenfield: a case-insensitive
  grep for `suggest` across the repo returns zero matches. The closest existing
  pattern to model it on is `InsightEngine.outstandingGrounding`, which already
  does "requirement → satisfied/stale/missing" and hides what's satisfied.
- **Item 3 — grounding and renewal.** `InsightModel.requirementStatuses(profile:now:)`
  (`Insight.swift:199-204`) already returns `.satisfied`/`.stale`/`.missing` per
  requirement and every caller throws away everything but `.missing`. The
  *display* side is what's absent: nothing computes `recordedAt + freshness - now`
  or renders a countdown. To scale, `GroundingRequirement` needs a cadence
  ("N readings within W, then M per P"); today it carries only kind, mandatory
  and rationale, so blood pressure's rule lives in bespoke statics.
- **Item 7 — substance intake.** `SubstanceLogView.swift:27-30` logs immediately
  on tap with no date/time sheet, and `DataStore` offers no update path (only
  load/delete), so a mis-timed entry can only be deleted. `afterWindow = 18h`
  exists in the analyzer but is never plotted. The watched set is six metrics and
  has not changed since it was written. Nothing is reachable from the Vitals tab.

### 5. Charts — the dash rule is only half applied

An audit of every chart in the app target found the identity change landed
cleanly (no `dash:` anywhere carries series identity any more) but the *other*
half of the rule — dash means "not measured" — is not enforced:

- **`ScoreHistoryChart`'s regression fit line is drawn solid**
  (`ScoreHistoryChart.swift:109-110`). It is a value for days that were never
  scored, in `Theme.accent` at 0.5 opacity — the same hue as the *measured*
  score line at full opacity. Its ±SD envelope is correctly dashed. This is the
  one inferred line in the app and it is the one place the new rule is broken.
- **`Theme.projectedStroke` is defined and never used** (`Theme.swift:100-102`).
  Wire it to the fit line above, or delete it.
- **Three hand-rolled dash patterns express the one meaning**: `[4, 3]`
  (`MetricOverlayChart.swift:254`), `[3, 3]` (`ScoreHistoryChart.swift:110, 147`),
  `[3, 4]` (`Theme.swift:102`). A `Theme.referenceStroke` sibling would stop the
  fourth being invented.
- **Hue collisions that are not hypothetical.** Three surfaces call
  `Theme.metricColor` **without** slots — `InsightDetailView.swift:461, 486, 531`
  ("What comes first", "What changed", "Full history") — which falls back to the
  preferred slot. The colliding pairs are real: RMSSD/SDNN both 1, systolic/
  diastolic both 4, heart rate/respiratory rate both 0, SpO₂/perfusion index
  both 2, body/skin temperature both 3.
- **`Theme.insightTint` has four colliding pairs** (`Theme.swift:69-80`):
  heartAge/bloodPressure, cardioFitness/bodyComposition, heartHealth/
  restingHeartRateTrend, cardioTrajectory/substanceImpact. The doc comment claims
  safety because "never more than four are on screen at once" — but the user
  chooses which four, so two of a pair can be picked together. Same class of
  belief-about-co-occurrence that shipped wrong once already.
- **Blood pressure paints from the *source* palette**
  (`BloodPressureSections.swift:141-154` uses `Theme.sourceColor`), so systolic
  and diastolic are red/blue there and magenta on every overlay chart.
- **Its diastolic threshold rules are solid**, in the *same hue* as the measured
  diastolic line (`:134` vs `:150`) — a reference level indistinguishable from a
  measurement.

Also outstanding:

- **Gap bridging.** No smoothed or predicted bridging exists anywhere; every
  `LineMark` is `.interpolationMethod(.linear)` and charts simply break. That is
  currently deliberate and commented, but the user asked for a smoothed
  prediction across gaps, and dash is now free to express it.
- **`MultiSourceChart` shatters at zoomed-out ranges.** It buckets points
  (`:92`) and then compares those *bucket* starts against `maxValidInterval`,
  a *sample*-scale rule (`:88`, applied `:94`). Heart rate's interval is 1800 s;
  a Week window's buckets are far wider, so every point becomes its own segment.
  `NormalizedSeries.segments()` guards against exactly this with a two-day floor
  (`NormalizedSeries.swift:86-89`); `MultiSourceChart` has no floor. **This is a
  live bug, not a gap.**
- **Reference bands exist only on blood pressure** — and the thresholds for the
  other seventeen vitals are already written down, sourced and commented in
  `VitalSignsInsight.Spec.specs` (`hardLow`/`hardHigh`). They are `internal`, so
  the app target cannot see them; making `Spec` and `specs` public is most of the
  work. Metrics with well-known ranges and no bands today: SpO₂, respiratory
  rate, body temperature, blood glucose, resting/heart rate, heart-rate recovery,
  walking steadiness.
- **`ScoreComparisonChart` omits the score bands** `ScoreHistoryChart` draws, so
  65 sits in a shaded context on one screen and a bare plot on the other.
- **`OtherDataDetailView` sets no `foregroundStyle`** (`VitalsView.swift:203-212`),
  so Swift Charts supplies its own blue — off the validated palette.
- **`AgeHistoryChart` borrows slots 0 and 2**, which are heart rate's and blood
  oxygen's preferred hues. Low severity (the two ages aren't `MetricType`s and
  never share a chart with them), but worth a dedicated pair.

### 6. On-device walkthrough

CI proves it compiles, not that it behaves — and both regressions this session
were caught by the user's screenshots, not by CI. Newest first:

- **The overlay chart.** No two drawn lines share a colour. Steady signals
  (body temperature, skin temperature) are *off* the chart by default and appear
  in the list below it. The list is ordered most-departed first and every row is
  tappable on and off. Selecting more than eight shows the "colours repeat"
  warning rather than silently repeating them.
- **Heart & Fitness Age** opens with both ages plotted against the chronological
  line, and the pace sentence reads as "gaining on it" / "running ahead" rather
  than a bare slope.
- **Blood pressure** shows shaded systolic bands with the diastolic limits as
  thin rules, and the caption explaining which is which.
- **"What's driving this"** leads with departures and folds the routine lines
  behind the disclosure.

Then the older batches:

  - The **Vitals Check** card on Today — confirm it reads
    "All normal" on a quiet day and names the outlier when there is one; that
    **Other data** renders Oura's resilience `level` as text with a States tally
    rather than an empty chart; that Cardio Fitness now shows two sources (Apple
    Watch + Oura) and Heart Age prints Oura's vascular age line; and that Body
    Composition shows lean/muscle/bone/water with the fat-vs-muscle narrative.
  - Also confirm the **paste prompt is gone** from Settings ▸ Data sources ▸ Oura.
    The clipboard autofill was removed because reading `UIPasteboard` raised
    iOS's paste prompt on every appearance — "Paste from your Mac?" via Universal
    Clipboard. Do not reintroduce clipboard *reads* on that screen; writes
    (Copy buttons) are fine.
  - Older: the three-age row on Heart & Fitness Age (narrowest device); a profile
    with no blood pressure showing the fitness half alone; Heart Rate at `All`
    *and* `Y`; Weight's gap-broken line and weekly velocity; provenance badges and
    the Inactive section; drag-to-scrub; Height as a plain card; blood pressure
    from all three entry points.
- **Unexplained and open: Oura serves ~4–6 months of history, not two years.**
  A 730-day window returns 171 sleep records, 128 daily_activity, 107
  daily_readiness — with **no `next_token`**, so that is genuinely all Oura will
  serve. Meanwhile Apple Health holds 128,302 Oura-mirrored samples. Byte counts
  match the record counts, so nothing is being truncated client-side. Candidates:
  an account/subscription boundary on API history, or a ring re-pair. The user
  was offered an investigation and hasn't taken it up yet.
- **Known gap, logged not fixed: Oura pagination.** The client reads only the
  first page. `OuraProvider.describeResponse` logs a warning naming the
  collection whenever `next_token` is present. No warning has appeared in any log
  so far, so nothing is currently being lost — implement only when one does.
- **Oura's `heartrate` endpoint is never called** despite the app requesting the
  `heartrate` scope. Direct Oura contributes 0 heart-rate samples; the 53,717
  arrive via Apple Health. Dead scope unless the direct pull is wanted.
- **Next on the roadmap** (see `docs/progress.md` for the full list):
  - Cardio strain from stimulants as a first-class trend — the cheaper one. The
    before/after analysis and 14-day load figure already exist in
    `SubstanceResponseAnalyzer`; what's missing is a decaying daily load *series*
    to trend and chart.
  - Sleep-debt / circadian consistency is **blocked on a missing signal**: no
    provider gives us a bedtime. Apple Health and Oura both stamp
    `sleepDurationHours` at the start of the calendar day. It needs a new
    clock-hour `MetricType` with circular statistics (the mean of 23:30 and 00:30
    is midnight, not noon) plus parser work in all three providers.
- The pre-approved AreaMark fallback (outlined min/max bands via two `LineMark`s
  rather than a filled `AreaMark`) shipped as the default — revisit only if the
  user wants filled bands and will spend a compile-spike cycle confirming
  `AreaMark` is safe on this SDK.
