# Progress

Philosophy unchanged: **use every signal, get creative with it, and be honest
about confidence.**

## Shipped

> **Read the next three sections as history.** They describe the seventeen-card
> era. Seventeen cards were merged into nine on 2026-07-31 — see "Card
> consolidation" below and `docs/card-sections.md` for what exists now. The
> *work* recorded here all still ships; most of it is now a component of a
> merged card rather than a card of its own.

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
- [x] Heart & fitness age — vascular age by inverting SCORE2/ASCVD against an
      optimal-factor reference person (consensus + range, each engine bounded by
      its own validated band), fitness age by inverting the VO₂max norm line, and
      risk projected at future ages the equations *are* validated for instead of
      a fabricated lifetime figure.
- [x] Fitness trajectory — VO₂max slope read against the age-typical decline
      (holding level is a gain), 12-month projection with its residual spread,
      and "what would move it" levers drawn from the user's own busier-versus-
      lighter weeks before any general evidence.
- [x] Vitals Check (Today card) — every sensed vital judged against the personal
      baseline, reporting outliers rather than averaging them away, with absolute
      clinical bounds overriding a permissive personal baseline. Gave heart rate,
      walking heart rate, blood oxygen and body temperature their first reader.
- [x] Every canonical vital now has at least one reader, and
      `docs/architecture.md` carries the metric → insight table so a future gap
      is visible. Readiness gained blood oxygen; Sleep Quality gained overnight
      blood oxygen and skin temperature; Body Composition gained lean/muscle/bone
      mass, body water and a fat-loss-versus-muscle-loss narrative; Heart Age
      reports Oura's vascular age beside its own.
      **Superseded**: `dayStrain` was recorded here as unread because Whoop
      wasn't connected. Whoop's parser has in fact been emitting it as a
      first-class sample all along; what was missing was a *reader*. It is now
      on the Fitness card, along with heart-rate recovery and walking heart
      rate, which reached the vitals scanner but never a score.

### The four cards from the top of the category
Chosen on one criterion — loved in the category *and* absent from it.

- [x] **Energy** (Today) — a body-battery reservoir: filled overnight by sleep
      against your own need and by overnight autonomic recovery, drained by
      active work *plus* time spent above your resting heart rate, which catches
      the strain that never became a workout. Garmin's version is the most-loved
      number in consumer wearables and exists nowhere else on iOS. Reports an
      hourly curve, and is honest that it is a model — a test stops it ever
      claiming `.high` confidence.
- [x] **Health Watch** (Today) — several signals leaning the same way at once,
      which is the shape of an immune response and is a different question from
      the one Vitals Check asks. Deliberately *not* worst-offender-dominant: one
      signal off is an ordinary Tuesday, so votes accumulate. Its reference
      period stops four days before the recent window starts, which is what
      routes around the contamination the golden dataset exposed — a run that has
      been building for a week is more visible rather than less.
- [x] **Sleep Debt** (Today) — the balance rather than last night, against a need
      *learned* from the user's own unconstrained nights, decaying with a
      five-day half-life so it can't ratchet to infinity over a busy month.
- [x] **Where You Stand** (Insights) — centiles against published age and sex
      norms for resting heart rate, HRV and VO₂max. VO₂max reuses the norm line
      `FitnessAgeModel` inverts, so it can't disagree with Cardio Fitness about
      what average looks like. Oriented so higher always means better, with a
      test on that — a resting heart rate of 48 is a *high* centile.

### Insight detail screens
- [x] Score over time on every scored card — replayed from raw samples so it's
      useful on first launch, and recorded going forward so a scoring change
      can't rewrite what the user was actually told.
- [x] One overlay of *every* metric behind a card, z-scored onto a shared axis
      (a log axis was tried on paper and rejected: it doesn't equalise), with a
      raw/log toggle, a validated eight-hue metric palette, and a legend that
      names each series and flags the ones with no data.
- [x] The chart's series are emitted by the scoring code itself
      (`InsightResult.contributors`), so adding an input to a score adds a line
      with no second edit — replacing a hand-written per-insight metric switch
      that had silently drifted.
- [x] Derived patterns: divergence ("more sleep, but blood oxygen is drifting
      down"), day-to-day co-movement, and which input tracks the score — all
      behind sample-count and effect-size floors, and always worded as
      associations rather than causes.

### Vitals Check, rebuilt so 100 means something
- [x] Real baselines: the day's representative value per source over a 28-day
      window, replacing `suffix(60)` — sixty *readings*, which for heart rate was
      the last five hours and moved with the very thing it was meant to detect.
- [x] Freshness: `now` is finally used, stale vitals are named and counted
      against coverage instead of silently reading as "measured today".
- [x] Continuous, direction-aware normality replacing a step function, aggregated
      worst-first and capped by coverage — so a perfect score needs everything
      you normally record measured today *and* sitting on its baseline.
- [x] Sources de-duplicated and scored separately, so two miscalibrated devices
      no longer size the standard deviation between them.
- [x] Corrected bounds, plus an HRV relative floor for the slow collapse a
      rolling z-score cannot see.
- [x] Scan widened from 7 metrics to 17: HRV SDNN (the HRV Apple Watch actually
      records), blood pressure, skin temperature, blood glucose, perfusion index,
      AFib burden, heart-rate recovery, walking steadiness and asymmetry.
- [x] Apple's own event flags read as events, not metrics — irregular rhythm,
      high/low heart rate, low cardio fitness, unsteady walking.

### Every card held to the same standard
The Vitals Check fix, applied everywhere it was also true.

- [x] `VitalReader` — one way to read a vital: the day's representative value per
      source, de-duplicated, over a 28-day window, with freshness attached.
      Readiness, Heart Health, Sleep Quality and RHR Trend all moved onto it.
      Readiness was reading a single artefact reading as a whole night's HRV;
      Heart Health took resting heart rate from the mean of *every sample ever
      recorded*, which over a 180-day lookback cannot move.
- [x] Four scores that were wrong: sleep consistency stuck at 0/100 (it was
      measuring fragmentation, not sleep), sleep's respiratory rate coming from
      the last ten minutes rather than the night, blood pressure carrying
      `score: nil` unconditionally, and heart age bottoming out at exactly zero
      from fifteen years of excess onward.
- [x] Resting Heart Rate Trend scores from two terms that can disagree — today's
      departure from baseline and the drift in bpm per week — because a single
      high morning and a month of upward drift are not the same finding.
- [x] "What's driving this" leads with departures and folds the routine majority
      behind a disclosure, with `isNotable` tri-state so an insight that doesn't
      classify its lines still shows all of them.
- [x] Both ages charted over time on Heart & Fitness Age, replayed weekly, with
      the pace reported against the one year per year everybody gets.
- [x] ACC/AHA bands shaded behind the blood-pressure chart — systolic only, with
      the diastolic limits as separate rules, because the two numbers share an
      axis but not a set of thresholds.
- [x] Charts: dash retired as identity. Every measured series is solid; dash now
      means "not measured" only. Hues resolve per chart, series are ranked by how
      far they've moved, and each one is individually tappable on and off.
      "Away from baseline" became recent-or-sustained rather than ever, so a flat
      signal with one old blip stops being drawn as notable.
- [x] Patterns stop reporting their own arithmetic — HRV against heart rate came
      off the same beat-to-beat intervals and was reaching the card as the top
      finding.

### Insights tab: the deep dive
- [x] Lagged correlation — a signal at day *d* against the score at *d+1…d+3*,
      reported only when it beats same-day. The one question Today can't ask.
- [x] Long-horizon score history with a fitted trend and its residual spread.
- [x] Cross-insight score comparison — all 0–100, so directly comparable.
- [x] Rolling 28 days vs the prior 28, standardised by the prior spread.
- [x] `contributors` filled for the trend models, so their charts carry honest
      weights rather than falling back to the declared candidate list.

### Creative data use
- [x] Temperature reconstruction from wearable nightly-deviation readings.
- [x] Blood-test photo import (on-device OCR → confirmed grounding values).

### Integrations
- [x] Apple Health (live, on-device).
- [x] Oura, Whoop, Withings — on-device OAuth, BYO developer credentials,
      Keychain storage, no backend.
- [x] "Other data" browser — imports every HealthKit/provider field, not just
      the metrics the app has a first-class insight for. Renders text and boolean
      values, tallies categorical states, and charts only numeric series.
- [x] Provider-agnostic ingestion pipeline — `RawValue` (number/text/flag),
      recursive `JSONFlattener` with array summarisation and audited skips,
      `EnvelopeSpec`-driven ingestors, a persisted `FieldCatalogue` that makes a
      provider's schema change a logged event, and data-driven `PromotionRuleSet`
      mapping to canonical vitals. A new connector is a declaration, not a parser.
- [x] Oura's undocumented `stress` and `heart_health` scopes — resilience,
      cardiovascular age and VO₂ Max reachable for the first time. Console URL
      updated to `developer.ouraring.com`.
- [x] Diagnostics that can actually diagnose: provider error bodies (RFC7807
      `detail` + `x-trace-id`) captured with a per-status remedy, granted scopes
      recorded and re-stated each sync, refresh-and-retry-once on a 401 (skipped
      for scope failures), per-collection record counts, and a per-metric,
      per-source import breakdown. Expandable detail in Troubleshooting plus a
      Share action.

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
- [x] Verified `/handover` and `CLAUDE.md` auto-load when the session's working
      directory *is* this repo — both fired in the session that shipped the age
      insights. Attaching this repo alongside a different working directory is
      still the failure mode (see `activeContext.md`).
- [x] Push-straight-to-`main` recorded as overriding the web harness's
      branch-and-draft-PR default, with the reason (`deploy.yml` only fires on a
      push to `main`, so a PR installs nothing) in `CLAUDE.md` and
      `docs/deployment.md`.
- [x] **The tests run in the sandbox.** Two Darwin-only Foundation APIs had
      crept into a package that was meant to be platform-free, and CI runs on
      macOS so nothing caught them. Both are now behind `#if canImport(Darwin)`
      and the full suite passes on Linux. `scripts/bootstrap-swift.sh` installs a
      toolchain; `scripts/verify.sh --tests` runs it *and installs it itself* if
      absent, so the gate self-heals rather than depending on a doc being read.
      Supersedes the old rule that sandboxes have no Swift.
- [x] **CI status for a few hundred bytes.** `ci.yml` records the verdict at
      `refs/ci/{passed,failed}/<sha>` and `scripts/ci-status.sh` reads it with
      `git ls-remote`. The GitHub Actions API — the only other route from a
      sandbox — returns ~450 KB per call, over 100K tokens.
- [x] **A lint for the traps that have actually broken this repo**
      (`scripts/verify.sh`): key paths on tuple elements, the `Chart3DContent`
      overload hazard, InsightKit's platform-free property, and every exhaustive
      `MetricType` switch checked *by name*. Proved with a canary case.
- [x] **Five skills** (`.claude/skills/`) so the rule-heavy procedures aren't
      re-derived each session: `ship-to-main`, `verify-before-push`,
      `add-metric-type`, `add-insight`, `add-chart`. Writing `add-insight`
      surfaced that the documented `InsightID` checklist named three switches
      when there are five.
- [x] **A generated symbol index** (`docs/symbol-index.md`) so "where
      is X" is a grep, not a hunt through 700 lines of architecture prose.
      `verify.sh` fails when it is stale.

### The bug-and-roadmap session (all CI-green, none device-verified)

- [x] **Body temperature judged in the wrong domain — fixed, and it was worse
      than documented.** Five faults, all from one loss of provenance:
      reconstruction wrote skin values as `.bodyTemperature`. `hardLow` (35.5)
      was *exactly* the reconstructor's baseline, so `value < hardLow` reduced to
      `deviation < 0`; `hardHigh` needed +2.3 °C and could never fire;
      reconstruction is additive so one signal entered the penalty pool twice
      with identical z-scores; Whoop and Withings type 73 report absolute *skin*
      °C into the same metric, pinning a Whoop user's score at zero; and — the
      undocumented one — the reconstructed series outranked a real thermometer
      for the same metric, so a 38.5 °C fever read "All normal". `.skinTemperature`
      is its own `MetricType` now, and `Spec.supersededBy` keeps one signal to
      one row. Apple's sleeping wrist temperature was in no map at all and is now
      read.
- [x] **Four cards given a dial that means something.** Cardiovascular Risk's
      four-step function → a logistic in log-risk fitted to the old anchors (4.9
      → 5.1% now costs 0.9 points, not 18). Body Composition scores body fat
      against the Gallagher age/sex range, BMI as a lower-confidence fallback.
      Blood Pressure reads the recent *pattern* when there's nothing from today.
      Blood-pressure calibration finally honours "five once, then two a month".
      Cholesterol renewal is six months, and staleness now costs confidence
      rather than passing silently.
- [x] **Substance Impact is a real `InsightModel`.** It was a free function, so
      score recording, score replay, the comparison chart and grounding
      collection all skipped it silently. It scores now, and the roadmap's
      decaying daily cardiovascular-load series is in with it — an exponential
      kernel normalised from the old box-car's own constants so the two agree.
- [x] **Every insight reads through `VitalReader`** — and `VitalReader` itself
      had a bug: it picked the source with the most history and *then* labelled
      freshness, so a quiet ring outranked a live watch and Readiness dropped the
      component entirely. Added `dailySeries`, which keeps the dates a regression
      needs.
- [x] **The metric chart stopped shattering.** It compared bucket starts against
      a *sample*-scale gap rule, so at any zoom past three days the line broke
      between every adjacent pair. Rule moved to InsightKit; four copies of one
      loop became one.
- [x] **Roadmap 4b — gap bridging.** Short gaps cross with a dashed connector,
      bounded by the metric's own join distance and by a quarter of the window.
      Straight, not smoothed: a curve invents a local extremum exactly where
      nothing is known.
- [x] **Roadmap 4c — reference bands** on every metric that has a published
      normal range, each with its own caption and provenance. Not from
      `VitalSignsCheck.Spec` — those are alarm bounds, and a band drawn between
      them shades the whole plot.
- [x] **The dash rule is whole.** `ScoreHistoryChart`'s fit line was solid, in
      the measured line's own hue. Three hand-rolled dash literals are gone.
- [x] **Colour collisions closed** — insight tints resolve per chart now, and the
      four colliding pairs became reachable the moment Substance Impact could
      score.
- [x] **Item 1 — the Today summary is gated** on a fingerprint of the results,
      with a 30-second floor on manual refresh and the last-updated time on the
      card so a floored pull doesn't read as broken.
- [x] **Item 2 — "Improve Your Health"**, on the Insights tab. Three sources
      only, ranked by how well-founded they are, with a test sweeping every line
      for prescriptive phrasing.
- [x] **Item 3 — grounding renewal.** The fourth state (`expiringSoon`) and a
      countdown, warning proportionally to each fact's own lifetime.
- [x] **Item 7 — substance intake**: a time picker, a real edit path, eleven
      watched metrics instead of six, and a row in Vitals. Still no amount, and
      the reason is written down.
- [x] **Test hygiene**: one `TestClock` for the backward-looking fixtures, and a
      `GoldenDataset` with the shapes a phone actually produces — which
      immediately showed that a *sustained* fever contaminates its own baseline.

### The follow-ups session — closing what was written down as "not done"

- [x] **Energy has a chart.** The model computed an hourly curve from the day it
      shipped and nothing drew it, so the one insight whose subject is *within* a
      day was presented like the ones whose subject is a month. An area, because
      the quantity genuinely is a volume; a plain `Chart` rather than
      `ScrollableMetricChart`, because a day is never wider than the screen and
      panning would only let you drag today off the edge.
- [x] **Health Watch and Energy reach the suggestion list.** Convergence — several
      independent signals leaning the same way — gets a `Basis` of its own,
      ranked above everything, and suppresses the same metric reappearing as a
      lone departure further down. Energy contributes the morning charge against
      the user's own best week of the quarter, which is deliberately not sleep
      duration: charge is duration *and* overnight recovery, so it separates
      seven hours that worked from seven that didn't.
- [x] **`MetricOverlayChart` bridges its gaps.** The pairing is generic in
      InsightKit and returns the endpoints themselves, because this chart encodes
      anomaly as opacity and needs both z-scores. The open question — how a dash
      interacts with per-span opacity — resolved to *the quieter end wins*: a
      bridge was measured nowhere, so taking the maximum would let one spike pull
      a week of silence forward as though something had been seen in it.
- [x] **The substance after-window is shaded**, not just stated. Overlapping
      windows merge (three coffees must not compound into a darker band, which
      would encode *how many logs* in a channel meant to say only *affected or
      not*), and the stripes have no y bounds — this chart already uses
      horizontal bands to mean a reference range.
- [x] **Three files split.** `OAuthIntegration` (858 lines) into one per
      provider; `AdditionalInsights` into one per insight plus shared phrasing;
      `HeartAge` into model, model and card. Swift's `private` is file-scoped, so
      a split always widens what the moved code touched — exactly one member.
- [x] **Oura pagination, implemented rather than warned about.** The client read
      only the first page for its whole life and logged a warning that never
      fired; a warning that has not fired is not evidence that it cannot, and the
      failure mode is silent history loss on the long back-fill a first sync
      performs. A failed page fails its whole collection rather than returning a
      truncated series, because half a history is indistinguishable downstream
      from a short one.
- [x] **The `heartrate` scope is no longer requested.** Nothing ever called the
      endpoint; it serves ~50k five-minute samples Apple Health already mirrors
      in full. Asking for a permission you never use is the one privacy smell an
      on-device app has no excuse for. Reinstating it is three named steps in a
      comment in `OuraProvider`.
- [x] **A generic exhaustive-switch lint.** The per-switch list in `verify.sh`
      only ever caught the switches somebody remembered to list, and CI broke on
      a `Suggestion.Basis` switch no list mentioned. Swift already requires a
      switch with no `default:` to name every case, so the new pass needs no
      per-switch knowledge. Proved with two canaries.

### The roadmap-review session — the two cheapest open items

- [x] **Sleep Regularity draws its own shape.** The card scores the *spread* of
      bedtimes about their own centre and the detail screen drew the score
      history like every other card — which answers "has my regularity been
      improving", not "what does my regularity look like". `SleepOnsetStripChart`
      plots the fortnight's onsets against the centre each was judged against:
      a regular sleeper is a tight column, an irregular one is scatter.

      The nights come **out of the model** (`CircadianConsistencyModel.Output.nights`,
      each carrying its own block centre) rather than being re-derived in the
      view. The weekday/weekend split is what separates a recurring lie-in from
      randomness, and a chart that recomputed it would be a second
      implementation free to disagree with the score above it — the same reason
      `InsightResult.contributors` exists. A test asserts the RMS of the drawn
      departures *is* `spreadHours`, so the picture and the number are one
      quantity rather than two that happen to agree today.

      Encodings: dash stays "inferred" (the centre lines and the spread band are
      fitted, the points are measured), hue stays identity, and weekday-versus-
      weekend rides on **symbol shape**, which nothing else here uses. The y axis
      renders clock times — an axis reading "−1.5" would leak the signed-hours
      encoding at the one place a reader is looking. A plain `Chart`, not
      `ScrollableMetricChart`, for `EnergyCurveChart`'s reason: a fixed fourteen
      nights is never wider than the screen.
- [x] **Sleep onset reaches `.sleepOnset` through the promotion rules** — and the
      one-line version of this item would have failed silently. `IngestionPipeline`
      promoted only fields with a `doubleValue`, commented *"promotion is numeric
      by definition"*; a bedtime is an ISO-8601 **string**, so a rule pointed at
      one matched and then promoted nothing, with no error raised anywhere.

      `PromotionRule.Interpretation` (`.numeric` / `.sleepOnsetTimestamp`) is the
      fix, defaulted so every existing row is untouched. The timestamp case reuses
      `SleepOnset.hoursFromMidnight` rather than reimplementing the ±6 h nap
      filter, and **re-dates the sample** to `SleepOnset.night(of:)` — a promoted
      sample is otherwise stamped at the document's own date, and one night's
      bedtime arriving on two different days depending on which route it took in
      would read as two nights. Two further declines, each with a test: a
      date-only string (`PayloadDate` reads it as midnight, and midnight is a
      real bedtime, so the invented value would be invisible), and an afternoon.

      Shipped as **aliases only, no rule**, for a reason worth checking before
      anyone adds one: `bedtime_start` is in `EnvelopeSpec.oura.startDateKeys`
      (and `start` in Whoop's), and `GenericJSONIngestor` excludes date keys from
      the field sweep — so for those two providers the field never reaches
      promotion at all and a rule aimed at it would match nothing, forever. A
      bare `start` alias was deliberately left out: every workout, cycle and
      activity record carries one.

### Card consistency, Phase 1 — one "View & add" everywhere
- [x] **`ContributionRoute`** — what each card lets the user view and add.
      Derived from each model's own `requirements`, **not** a sixth exhaustive
      switch over `InsightID`. A protocol requirement with a default in an
      extension, so a new insight compiles untouched and gets the right answer,
      while the two log-backed models (blood pressure, substances) override.
- [x] **`ViewAndAddSection`** — one section, one anatomy: a status figure, what
      you have already given, what is still missing, one way to add. Replaces
      "Add these for a better estimate", which could only ever show what was
      *missing* — so a fully-grounded card lost the section and with it any way
      to correct a mistyped value.
- [x] **Blood pressure's chart moved onto its own card**, as a shared
      `BloodPressureChart` drawn by both the insight and the metric screen. The
      metric screen keeps the calibration detail and the full dated history.
- [x] **The timeframe picker hoisted** out of "Score over time", which it
      outlived by three sections.
- [x] **"What comes first" / "What changed" ungated** from cadence.
- [x] **One placement rule** for the bespoke slot, above "Score over time".
- [x] **`InsightResult.isWorthShowing`** — one listing rule for both tabs.

### Card consolidation — seventeen insight cards into nine
- [x] **Fitness** ← Cardio Fitness + Fitness Trajectory + fitness age.
      **Sleep** ← Sleep Quality + Sleep Debt + Sleep Regularity.
      **Readiness** ← Readiness + Vitals Check + Health Watch.
      Heart age → the risk card, which runs those equations. Centiles → Heart
      Health, which reads those metrics. Resting Heart Rate and Where You Stand
      deleted as cards; both were already sources elsewhere.
- [x] **The maths was kept as components**, with its tests. Only the card
      wrappers and their `InsightID`s went.
- [x] **Signals that reached nothing now reach a card**: `dayStrain` (read by no
      insight at all), `heartRateRecovery` and `walkingHeartRateAverage` (only
      by the vitals scanner) on Fitness; the absolute temperatures on Sleep. All
      at weight 0 — real signals, no validated 0–100 curve, and an invented
      weight inside a trusted score is worse than none.
      **Superseded 2026-08-01** (`3f74f06`): all three carry a share now, judged
      against the reader's own baseline. The argument above is still right about
      *inventing* a weight and was being used to justify not *attributing* one.
- [x] **Settings ▸ Export my data** — the development feedback loop. An
      inventory small enough to paste, plus a full JSON export, covering the
      unmodelled fields nobody working on the app has ever seen.

### Card consistency, Phase 2 — the remaining unique sections
**Done 2026-08-01 (`dc5fae6`), bar the Body Composition scan entry, which the
user deferred to a later session.**

The "ask for the data inventory first" note that used to head this section did
not end up gating anything, and the reason generalises: **every remaining item
drew output a model was already computing**, so "does the data exist" was
answered by the model producing a value at all. Each new section self-gates on
its own data floor, which is what every existing section already does — so a
card with nothing to show simply doesn't draw it, and no inventory was needed to
decide that in advance.

- [x] **Three cards still have no bespoke section**: Heart Health, Body
      Composition, Readiness. **Done** — all nine cards now have one.
- [x] **One weighted-contribution card** would serve Heart Health and Readiness,
      drawn from `InsightResult.contributors` — which already carries a
      renormalised `weight`, so **no new type and no model changes are needed**.
      **Done, and the prediction held exactly**: `weightedContributionCard`, no
      new type, no model touched. It draws only `weight > 0` contributors —
      ~~Readiness appends the vitals it merely *scans* at weight 0, and a
      zero-width bar would imply they were weighed and found irrelevant when
      they were never in the average. They are a footnote instead.~~
      **Superseded 2026-08-01** (`3f74f06`): the scanned vitals share 20% of the
      number, scored by the scan's own `normality` — which was already trusted
      to decide what the card *says* while contributing nothing to the number
      underneath it.
- [x] **Body Composition** — the composition split. **Done**: "What you're made
      of", a stacked bar of fat / muscle / bone over body mass, backed by
      `BodyCompositionSplit` in InsightKit with 12 tests. Body water is a
      footnote, not a block: it is a share of tissue already drawn as muscle, so
      a block would count the same kilograms twice. A scale that disagrees with
      itself (muscle + bone > lean) collapses to one undivided lean block rather
      than drawing a bar that sums past the person's weight.
- [x] **Heart Health carries the percentile standings it absorbed** (`dc5fae6`).
      `PeerStandingStrip` — one row per metric, a 0–100 axis, the "around
      average" band picked out, one dot. **Deliberately not a distribution
      curve**: `PeerStandingModel` states in its own doc comment that these are
      normal approximations to *published summary statistics*, and the sources
      give means and spreads, not curves — drawing the bell claims a
      distribution nobody has.

      The extraction that made it safe: `Standing.phrase` held the bucket edges
      90 / 75 / 60 / 40 / 25 inline, and a strip that *shades* those bands has to
      read the same numbers or the picture and the sentence beside it drift.
      `PeerStandingModel.Band` now owns them, `phrase` reads it, and
      `PeerStandingBandTests` sweeps 0–100. Same shape as `PressureBandTests`.
- [ ] **Body Composition** — the **"view & add" scan entry** the user asked for
      (a fourth `ContributionRoute`). **Deferred by request 2026-08-01** to a
      later session. Worth knowing before picking it up: the capture it would
      point at is the camera + LiDAR body scan, which is deliberately a roadmap
      note rather than a build and is ARKit, so nothing about it can be
      exercised from a sandbox. The composition split half is done, above, and
      carries a stacked-area history (`BodyCompositionTrendChart`).
- [x] **Readiness — a z-score strip over the vitals it scans** (`dc5fae6`).
      `VitalDepartureStrip`, one row per fresh vital on a shared
      distance-from-baseline axis. The scan judges up to seventeen signals and
      reached the card as seventeen sentences; on an ordinary day sixteen say
      "in your normal range", so finding the one that doesn't was counting.

      **The band a row is drawn in *is* `Reading.status`, not a re-derivation.**
      Two things make that necessary rather than tidy. Direction matters — a
      resting heart rate two SD *below* baseline is good news, and colouring by
      `abs(z)` would paint the best morning of the month in the worst red. And
      an absolute clinical bound overrides a personal one, so a reading can be
      `.unusual` at a small z; `isBeyondClinicalBound` marks those, because a red
      dot in the middle of the axis with no explanation reads as a rendering
      fault. The thresholds themselves moved into `VitalDeparture` and
      `VitalSignsCheck.reading` now calls it, so there is one implementation
      rather than two that agree today.

      Vitals with no baseline and vitals that are stale **leave the axis** and
      become the caveat. A mark at the origin would say "measured, and
      ordinary", which is the opposite of "we could not judge this" — the same
      decision `weightedContributionCard` already makes for weight-0 rows.
- [x] **Both projections are drawn** (`dc5fae6`). The risk card's was the
      starker case: `HeartAgeAnalyser` fills `Analysis.projections`,
      `CardiovascularRiskInsight` reads four other fields off that value and
      lets it fall out of scope — and the analyser's own `explanation()` writes
      *"The projections below run the same validated equations at future ages"*.
      There was no section below, and that function has no production caller at
      all (only `DeepDiveTests` and `HeartAgeTests`), so it was a promise nobody
      could even see being broken.

      Framing preserved exactly as recorded: **"if today's numbers hold"**,
      never a lifetime figure, and a capped engine says "79 or older" rather
      than printing an extrapolated number.

      Fitness draws `projectedIn12Months` with `residualSD` as a band —
      described in its own doc comment as "the honest ± on the forecast" and
      read by nothing outside `CardioTrajectory.swift`. The whole chart is
      dashed, because none of it was measured; the single solid point is today's
      smoothed value, which is. The band is `AreaMark(x:yStart:yEnd:)`, which
      takes no `stacking:`.
- [x] **The two chrome rules, applied once** (`dc5fae6`). `InsightSection` over
      `Card` — title, at most one figure, content, caveat — and
      `NestedInsightSection` for a second picture inside one bespoke slot.

      **`caveat` has no default**, so omitting it is a compile error and `.none`
      is a choice somebody made. That is the compounding half: it retires the
      *category* rather than the eight instances, and needs no lint because the
      compiler is the gate. What it replaced: footnote colour split three ways
      for one job (`.tertiary`, `.secondary`, `Theme.warn`), four header fonts,
      inner spacings of 8 / 10 / 12 with no rule, and a footnote *presence* that
      was arbitrary — "What comes first", a lag fitted through however many days
      two series happen to overlap on, was the most inferential claim on the
      screen and the only one with no caveat at all.

      **One slot, one quantity.** The body-composition trend's trailing figure
      showed a kilogram delta *or* a count of weigh-ins, in the same position,
      with nothing to tell a reader which. The count moved into the caveat.

      The wording lives in `SectionCaveat` in InsightKit: the app target has no
      test target and the wording is the honesty claim, so it is the part that
      can actually be wrong. Two defects it caught on the way in — the
      body-composition caption opened *"Height is your weight"*, and pluralised
      "across 1 weigh-ins".
- [x] **"View & add" has the one anatomy it already claimed to have**
      (`dc5fae6`, asked for this session). Its doc comment said "the anatomy is
      fixed whatever the route" and it was not: blood pressure had a grounded
      summary and the other two did not, the grounding-facts route had **no add
      button at all** (its rows were the only way in), the "all readings" link
      appeared only past three readings — so the screen was unreachable exactly
      while a user was learning the feature — and all three routes previewed
      their own contents on the card.

      Now, everywhere: header and figure, a green grounded / not-grounded
      summary, one prominent button into the sub-menu that holds adding *and*
      what was added, and a link to the fuller screen where one exists past it.
      **No previews** — the three readings, the three events and the fact values
      all moved behind the button, into `GroundingDetailView` for the facts.

      Two decisions worth keeping. The link is present only on blood pressure,
      because it is the only route with somewhere further to go (the sheet takes
      a reading; the metric screen holds the dated history, the chart and the
      calibration detail). `SubstanceLogView` and the grounding list already
      *are* the full view, and two controls pointing at one destination is the
      thing this section was built to remove. And `ContributionSummary` computes
      the grounded state in InsightKit, where blood pressure **defers to
      `CalibrationStatus`** rather than forming a second opinion on whether it is
      calibrated — that type owns the five-then-two rule and its wording.

### Sources, scoring and the weighting section (2026-08-01, `bff6390`, installed)

Driven by the user reading the shipped cards: *"if a source goes into a chart, it
should go into the score, and it should show in 'what goes into this' — many
details are in 'what's driving this' but not the others"*, and *"many say it's
not weighted, when almost every score should be weighted"*.

- [x] **Every card states how its number is formed.** `ScoreWeighting` on
      `InsightResult`, defaulting to `.unstated` so a new insight is silent
      rather than claiming a basis nobody chose for it. Six cases, each with its
      own sentence above the bars — the renormalisation note belongs to a
      weighted average alone, and printing it over an equation's
      held-at-optimal shares would describe a calculation nobody ran.
- [x] **Three of the four "Not a weighted average" cards had computable shares.**
      Body Composition and Fitness rest on one measurement (`singleMeasure`);
      Substance Impact's pool divides exactly by Euler's theorem
      (`penaltyShares`); the risk card attributes by holding each factor at its
      optimal value and re-running the equation (`RiskAttribution`), which
      **reuses `HeartAgeModel.riskPercent` unchanged** rather than decomposing
      the linear predictor — the coefficients are sitting in
      `CardiovascularRiskModel` and a second copy is the `PressureBandTests`
      defect one level up. Only Blood Pressure's cuff route is genuinely
      unweighted, and it now says *what it is* rather than what it isn't.
- [x] **The risk card's non-metric inputs reach the section.** `ScoreFactor`
      carries a grounding fact or a derived quantity beside `MetricContribution`,
      renormalised **together** because they are shares of one number.
      `MetricContribution` stays the single statement of a metric's share, so
      the overlay legend and this section cannot drift. Age and sex arrive as
      one **locked** row: they carry the largest share and are the one thing
      nobody can act on.
- [x] **Blood pressure routes the dial the way the user described.** A cuff
      reading from the last 24 hours wins outright. Past a day the experimental
      estimate takes over — the only route that is a statement about *now*,
      reading today's resting heart rate and HRV through a regression fitted to
      the person's own readings. The recent average drops to the floor beneath
      it, for whoever has cuff readings and no wearable to estimate from.
      A second defect fell out: `hasFreshReading` was tested against a *sample*
      while the value came from `profile.cuffSystolic`, so a stale grounding
      fact could be dialled under a newer sample's freshness.
- [x] **Four cards read or drew a metric that reached "What goes into this" on
      no card.** All four fixed, and the invariant that catches the next one is
      `ContributorsTests.testEveryDeclaredInputWithDataIsActuallyRead`. See
      `docs/card-sections.md` ▸ "Declared and never read".
- [x] **Energy's weights come from its model.** They were 0.6 / 0.25 / 0.15,
      three constants written in the card, appearing nowhere in `EnergyModel` —
      under a heading promising "the share each signal has of the score". Now
      `EnergyModel.Output.terms`, beside the coefficients.
- [x] **"Charted, not scored" is a named list, not a count.** Fitness has five
      and Readiness eleven, and *which* is the question a count cannot answer.
- [x] **Then the weight-0 rule itself was reversed** (`3f74f06`, installed), at
      the user's direction after reading the above on the phone. Everything a
      card charts carries a share; supporting signals are judged against the
      reader's own baseline — the mapping `ReadinessScore` already uses — and
      share `SupportingSignal.collectiveShare` (20%) between them, so the
      primary measurement still decides what the card says. Three exceptions
      survive and each states its reason on its own row, enforced by
      `testAnUnweightedRowAlwaysSaysWhy`. Height left Body Composition's inputs
      rather than earning a weight: a static attribute with no series has no
      honest bar. See `docs/card-sections.md` ▸ "Everything charted carries a
      share" for the per-card numbers, and `docs/activeContext.md` for why the
      original rule could not support the work it was doing.

## In progress / not yet device-verified

- [x] **The card-consistency session (2026-08-01), all twelve pushes installed
      and reviewed on the phone by the user as they landed.** Eight rounds of
      feedback drove it, so this one is device-verified by construction rather
      than pending. What it established, so a later session does not re-derive
      it: every section renders on every card and says which kind of empty it
      is; the order has a written rationale; `scripts/card-map.sh` keeps
      `docs/card-sections.md` honest and `handover-check.sh` enforces it.
- [x] **The four judgement calls from that session that only the phone can
      settle — all four confirmed good by the user on 2026-08-01.** None needs
      revisiting; the values they pin are the ones to keep.
      - **The floating timeframe bar** — `.bar` material and an 8pt gap above
        the tab bar read as floating rather than as the card ending, and the
        `safeAreaInset` leaves the disclaimer scrollable clear of it. This was
        the control's *third* placement and the first two both failed by being
        somewhere the reader wasn't; it is settled.
      - **The chevron at 40% opacity on an open section.** Eleven at full accent
        down one card looked like a row of alarms; 40% was a guess made without
        seeing it and it was right.
      - **`BodyCompositionTrendChart` rescaling its y-axis as you pan**, now
        that the picker is a zoom rather than a filter.
      - **The bedtime strip's band moving under your finger** as it re-fits per
        window — reads as informative rather than as jitter. Which is the
        payoff for splitting `CircadianConsistencyModel` into
        `nights(from:days:)` and `evaluate(nights:)`: the alternative was to
        leave the window fixed, and the split is what made the movement mean
        something rather than being noise.
- [ ] **Give Heart Health's new section a second look on a young profile.**
      `HeartResponseModel` exists to say something to a reader under 40, and the
      one thing no test can check is whether it actually does. Needs a device
      with a recorded workout — heart rate recovery only exists on days with a
      hard effort.

- [ ] **Phase 2's five new sections on the phone** (`656bb9c`, **installed**).
      CI proves they compile; the app target has no test target and SwiftUI does
      not exist on Linux, so the device is the only gate for what they draw.
      - ~~**Heart Health ▸ "How you compare"** — three centile rows under the
        weighting.~~ **Superseded 2026-08-01**: it is no longer under the
        weighting, no longer Heart Health's, and no longer three rows. It is a
        universal section taking each card's own metrics, and it now also lists
        the signals with no published norm. The dot's position must still agree
        with the phrase beside it, and a metric with no recent reading must
        still be absent rather than drawn at zero.
      - **"How far from your normal"** — no longer Readiness-only; every card
        gets it, narrowed to its own metrics, and Readiness keeps the full
        seventeen-vital scan. The shaded band must line
        up with which vitals the card above calls unusual. Two specific things:
        a vital below baseline in the *harmless* direction must not be red, and
        a row with a ⚠️ is one an absolute clinical bound pushed to unusual, so
        it can legitimately sit near the middle of the axis. That marker exists
        so it doesn't read as a rendering fault.
      - **Fitness ▸ "Where this is heading"** — visibly dashed with one solid
        dot at today, and the ± band rendering as a *band* rather than filling
        down to the axis. `AreaMark(x:yStart:yEnd:)` is only device-proven for
        the water film so far.
      - **Risk ▸ "If today's numbers hold"** — reads "at 60", "at 70", "79 or
        older". Never an extrapolated age.
      - **"View & add" on all six cards that have it** — no readings, events or
        fact values on the card; a green seal or a bar; one button; the
        all-details link present even under four readings. The grounding route
        has a button at all now, which it did not before.
      - **Every card** — one footnote colour, and "What comes first" carrying a
        caveat naming the overlap it was fitted through.
- [ ] **Phase 1 of the card-consistency work** (`42efe4c`, installed). The
      things to look at: the BP card carries its own chart and adds a reading
      without leaving the screen; a grounded card shows what is set as well as
      what is missing; Substance Impact can log from its own card; a card with a
      thin history still has a timeframe picker; a daily card (Readiness,
      Energy) can now show "What comes first" / "What changed".
- [x] On-device walkthrough of the nine-part UI pass — **overtaken 2026-08-01**
      by eight rounds of the user reading the shipped cards and reporting back,
      which is the same walkthrough done adversarially.
- [ ] **The nine cards on the phone** (`c2afd04`, installed). Neither "Heart &
      Fitness Age" nor "Fitness Trajectory" exists any more — this item used to
      name both. What to look at now: Fitness carries VO₂max, its trajectory and
      fitness age; the risk card carries heart age; Heart Health shows the
      percentile standings it absorbed; Readiness names an outlier vital and
      warns when several signals lean together; Sleep opens with last night.
      A profile with no blood pressure should still score Fitness — that
      asymmetry is the reason the two ages were split.
- [ ] The ingestion pipeline on the phone — see `activeContext.md`, including
      that the Oura setup screen no longer raises the "Paste from your Mac?"
      prompt. (Vitals Check is no longer a card; its scan is a Readiness
      component.)
- [ ] **The nap fix, proved from the data rather than by eye** (`c2afd04`).
      Pull to refresh, then Settings ▸ Export my data ▸ inventory. Two numbers
      settle it: `sleepDurationHours` median should rise from **5.62 h**, and
      `restingHeartRate` max should fall from **119**. No re-sync is needed —
      `sync()` pulls 730 days and the cache merge replaces a source's samples
      wholesale, so an ordinary refresh rebuilds Oura's history.
      **Attempted 2026-08-01 and it could not be settled either way**, which is
      the finding. The export gives one merged distribution per signal, and
      three sources feed `restingHeartRate`, so a maximum of 119 names nobody.
      Fixed at the root: the inventory now carries a per-source breakdown for
      every multi-source signal (`DataInventory.SourceStat`). **Re-export and
      the two numbers become decidable** — read 119 off the *Oura* row, not the
      merged one.
- [ ] **The other half of the same defect, now fixed but not yet seen**
      (this session). `HealthKitService.fetchSleep` keyed every nightly figure
      on the calendar day each *segment* started, so a night crossing midnight
      became two — the smaller a sliver. That is where the export's
      `sleepDurationHours` **min of 0.01 h** and `sleepEfficiency` **min of 2%**
      came from, and it is a second cause of the exact "7.5 h night reported as
      4 h" symptom the Oura fix chased: Apple Health dated a night by its start
      and Oura by its end, and `bucketStatistic` averages same-day samples, so
      the two sources were a day apart and averaged into each other.
      All of it now runs through `SleepNights` in InsightKit (14 tests), which
      keys on `SleepOnset.night(of:)` — the rule the onset series already used,
      and whose own doc comment had named the duration series as doing this
      wrong. **After a refresh, expect the sleep median to rise and the 0.01 h
      and 2% floors to disappear.**

- [x] **A scrub line on every chart** (`4ba0c91`, installed). Only the energy
      curve had one. Added once inside `ScrollableMetricChart`, which seven charts
      wrap, plus the two standalone charts — `SleepOnsetStripChart` and
      `BodyCompositionTrendChart` — which also gained the readouts they had no way
      to show.
- [x] **Score history filled and graded by its band** (`ff0a612`, installed).
      Green high, amber middle, red low. `Theme.scoreFill(peak:)` takes the peak
      because a Swift Charts gradient resolves against the mark's bounding box,
      not the plot area — a card scoring 15 drew the whole ramp inside fifteen
      points. `ScoreComparisonChart` is deliberately left as lines: it overlays
      several scores each with its own tint, and one shared fill would destroy the
      distinction it exists to draw.
- [x] **Rebuild data from providers** (`3f3d3a1`, installed), in Settings ▸
      Troubleshooting. The cache-merge keeps a silent source's stale samples
      forever; this is the only way to force a re-parse, and the only way to be
      certain a parser fix took effect.
- [x] **`refs/ci/errors/<sha>` + `scripts/ci-errors.sh`** (`e9188c2`). The
      roadmap's top open item. `app-build` greps its own log and pushes the
      failing lines as a git ref; reading why CI went red is now a few hundred
      bytes instead of ~40 K tokens of build-step noise.
- [ ] **On the phone, the sleep fix proved from data** — pull to refresh (or
      Settings ▸ Troubleshooting ▸ **Rebuild data from providers**, which is
      stronger), then export the inventory. Three things settle at once: whether
      `sleepDurationHours`' median rises and its 0.01 h floor disappears, whether
      `sleepEfficiency`'s 2% floor goes, and — from the **new per-source
      breakdown** — whether `restingHeartRate`'s 119 was ever Oura's.
- [ ] **On the phone, the Body Composition card after the hatch change**
      (`df5140a`). `ImagePaint` inside a Swift Charts `AreaMark` compiles, but
      whether Charts tiles it as SwiftUI does is device-only. If the chart's water
      region renders flat or oddly scaled while the bar looks right, that is the
      cause, and the fix is to draw the chart's hatch as a clipped overlay.

## Next

### From the data-opportunities ranking (2026-08-01, second half)

- [x] **#1 — Exercise minutes score Fitness.** `MetricType.exerciseMinutes`
      (HealthKit's `appleExerciseTime`, promoted out of the raw pile) feeds
      `ActivityDoseModel`: the trailing week's minutes against WHO 2020's
      150–300 min moderate-activity band — the one activity signal with a
      published dose, because Apple's exercise minute *is* the guideline's
      moderate-intensity definition. Weekly, never daily (the guideline says
      nothing about spread, so `.exerciseMinutes` deliberately has no daily
      `referenceRange`); missing days count as zero behind a 3-recorded-day
      floor, so a barely-worn watch returns "can't judge" rather than a damning
      number. Fitness's primary pool rebalanced to level 0.55 / trajectory
      0.25 / dose 0.20 as `docs/data-opportunities.md` proposed; with no dose
      data the other two renormalise to within a point of the old 0.7/0.3, so
      a watchless profile sees the number it saw yesterday. 8 tests
      (`ActivityDoseTests`), including the primary-term-beats-supporting
      dedup and the two-devices-don't-double-count case.
- [x] **Housekeeping — Withings bookkeeping excluded at ingest.** ~80 of the
      export's 232 "unmodelled signals" were `.algo`/`.fm`/sync-stamp noise
      plus numbered copies of measures the typed parser already promotes.
      `WithingsMeasureIngestor` now drops both — asking
      `WithingsResponseParser.metricType(for:)` so the exclusion can't drift —
      and keeps `attrib`, `category`, `comment`. Both promotion rules aimed at
      numbered measures target unmapped types and still fire.

- [x] **Substance Impact scores measured impact, not usage** (2026-08-01, user
      direction). The load is a prior on exposure: it stands alone only while
      nothing is measured, phases toward a 25-point cap as up to three signals
      report, and the effect-size severities — which were always the measured
      half — carry the dial from there. `effectivePenalties` is the one pool
      `score` and `penaltyShares` both read, so the exact Euler attribution
      survives; the load's own row says "capped — your measured response
      carries the score" or "usage is all this number can rest on" as
      appropriate. Four new tests, including heavy-use-with-mild-measured-
      response scoring above 60 while the same usage with a 2-SD heart
      response still scores under 25.
- [x] **#4 — Sleep latency scores the night** (data-opportunities ranking).
      `MetricType.sleepLatencyMinutes` from Oura's `latency` field, decoded in
      the typed parser *behind the nap filter* — every nap and rest segment
      carries a latency too, and promoting the field generically would let a
      doze's instant onset become the night's figure (the bedtime defect, one
      field over). Scored per Ohayon 2017 (≤15 min → 100, floor 30 past an
      hour), weight 0.05 funded from duration and consistency so the table
      still sums to 1. Reference band on the Vitals chart from the same
      consensus panel as the efficiency band.

- [x] **Settings ▸ Export ▸ Card outputs** (2026-08-01, user request). The
      card-level counterpart of the data inventory: every card's live result —
      score, headline, confidence, weighting basis, all driver lines, every
      weighted share with its own detail string, the charted-not-scored rows —
      plus, per declared input, whether data exists at all (count, span,
      latest, sources), a bounded 21-day score-history tail, the grounding
      facts through their own formatters, and the **build stamp first**,
      because "the fix didn't work" and "the fix isn't installed" look
      identical from a screenshot. `CardStateExport` in InsightKit, 5 tests,
      including one pinning the document stays under 200 KB on a 50k-sample
      history — it is aggregates and wording only, sized to paste into a chat.
      **This is the instrument for recalibration requests**: it shows what the
      user is seeing, not what the code intends.

- [x] **The first card-outputs export, acted on** (2026-08-02). Five
      miscalibrations found and fixed, each with a test shaped like the user's
      own data: the substance comparison is contemporaneous (90 days both
      sides — a six-year cuff history had been posing as the clean baseline
      for a fortnight of logs, turning years of BP rise into "+21 mmHg after
      use" at 87% of the score); the substance headline names the strongest
      measured effect and the safety line fires only on a measured response;
      Fitness's cumulative supporting metrics are judged on the last complete
      day (steps at breakfast are not a low day); a BP per-week slope needs a
      fortnight of spread ("49.3 mmHg per week" from clustered readings was
      cuff noise extrapolated); Body Composition's weight direction matches
      its own drivers (loss the card calls good no longer costs 20%-pool
      points); and the export distinguishes a pending replay from an empty
      history. See `docs/activeContext.md` ▸ "Fifth half" for what was
      deliberately *not* changed.

### More "gap-filling" insights
Listed cheapest-first — the second one can't start without new plumbing.

- [x] Cardio strain from stimulants as a first-class trend — shipped. An
      exponential kernel with a 7-day half-life, normalised from the box-car's
      own constants so the card's figure and the chart's line are one quantity.
      The card's number now peaks higher and tails off where it used to hold flat
      for a fortnight and vanish overnight.
- [x] **Sleep Regularity — and the signal was never missing.** This was logged as
      blocked because "no provider gives us a bedtime". That was true of what the
      app *ingested* and false of what the providers *serve*: HealthKit's sleep
      segments carry a real `startDate`, Oura's `bedtime_start` was already being
      decoded and used only as a fallback for the record's date, and Whoop's
      records carry `start`. All three were collapsed to hours-per-calendar-day
      on the way in and the timestamp discarded.

      The encoding is the part worth keeping. The proposed clock hour in [0, 24)
      needs circular statistics — the mean of 23:30 and 00:30 is midnight, not
      noon — and this app's whole baseline machinery is linear. `.sleepOnset`
      instead stores **signed hours from midnight with the branch cut at
      midday**, where no real bedtime falls: the arithmetic mean is then the
      circular mean, for free, and no consumer changes.

      The card scores the *spread* and deliberately never the hour — chronotype
      is constitutional and shift work is a job — with a test sweeping three very
      different bedtimes to assert a regular sleeper is never marked down.
      Social jetlag is reported on its own line and removed from the spread, so a
      consistent weekend lie-in reads as regular rather than as randomness.

### Integrations
- [ ] Explain why Oura's API serves only ~4–6 months of history against years of
      ring data mirrored through Apple Health. No `next_token`, byte counts match
      record counts, so it isn't client-side truncation. **Narrowed 2026-08-01**:
      it is not our request window either — `OAuthIntegration.sync()` asks for
      730 days unconditionally, and the export confirms Oura returns 2026-03-16
      onward against Apple Health's 2024-08. The limit is Oura's; nothing on our
      side is worth re-investigating.
- [ ] Hume Band direct API (today flows in via Apple Health only).
- [ ] Ultrahuman, Garmin, Fitbit — drop in via `HealthIntegration` protocol.

### Unstructured data
- [ ] Live document scanner (VisionKit) instead of library-only picking.
- [ ] Foundation Models structured extraction for arbitrary lab analytes.
- [ ] ECG photo/PDF import with metadata (no automated interpretation — that's
      a regulated medical-device claim, out of scope by design).

### The ten-item feedback list (the working agenda)
Status audited against the code, not recalled — see `activeContext.md` ▸
"Immediate next steps" for the file references behind each line.

- [x] 5. Every contributing source listed in the drill-down; the Sleep Quality
      "five components, four metrics" gap explained rather than hidden.
- [x] 6. Sleep Quality — respiratory rate from the night rather than the last ten
      minutes, consistency no longer stuck at 0/100, and the inputs expanded
      twice: first overnight blood oxygen and skin temperature, then the stage
      breakdown (efficiency, deep, REM) that all three providers were sending and
      all three parsers were discarding. See "Sleep Quality reads the stage
      breakdown now" below.
- [x] 8. Blood pressure scores from the AHA bands, calibration honours "five
      once, then two per thirty days", and the drift counter exists — held-out
      error against the fit's own claimed uncertainty, floored at ±5 mmHg. See
      "A blood-pressure drift counter" below.
- [x] 9. Heart & Fitness Age scores from a logistic, and both ages are charted
      over time.
- [x] 4a. Colour bands on the blood-pressure chart.
- [x] 4b. Gaps bridged with a dashed connector on the metric-detail chart,
      bounded by the metric's own join distance and by a quarter of the visible
      window, on the metric-detail chart *and* the insight overlay. Crossed with
      a monotone cubic Hermite curve (`GapBridge.smoothed`) — smoothed as asked,
      and provably free of the invented extremum that ruled out a naive cubic.
      Still dashed. See "the brief was right" below.
- [x] 4c. Reference bands on every metric with a published normal range,
      each carrying its own caption and provenance. Heart rate deliberately gets
      none: its bounds are for the *day's* value and that chart plots raw samples.
- [x] 1. Today summary gated on a fingerprint of the results, plus a 30-second
      floor on manual refresh and a last-updated line so a floored pull reads as
      "up to date" rather than broken.
- [x] 2. "Improve Your Health" — the engine (four bases, ranked by how
      well-founded each is) *and* the lifecycle: dismissible on both surfaces,
      one card on Today, a pinned collapsible reminder on Insights that keeps
      what you dismissed, thirty-day expiry, and resolution inferred from the
      engine no longer emitting the suggestion. See "The suggestion lifecycle —
      done" below.
- [x] 3. Grounding renewal — a fourth state (`expiringSoon`) and a countdown in
      Settings, warning proportionally to each fact's own lifetime. A cadence
      type on `GroundingRequirement` was *not* needed: blood pressure's
      five-then-two rule lives in `CalibrationStatus.Phase`, where the fit it
      protects is.
- [x] 7. Substance intake: press-and-hold sets a time, entries are re-timeable,
      the watched set went from six metrics to eleven, and it has a Vitals row.
      The after-window is now shaded behind the per-vital charts, merged where
      spans overlap. Still no amount — recording quantity would make it a dosing
      record. One clause of the original ask is only partly met: the log is a
      timestamped source *charts* can consume, and nothing else reads it — see
      the delta list below.
- [x] 10. QA sweep done: all four. Every insight reads through `VitalReader`
      (which had its own source-selection bug), Cardiovascular Risk is
      continuous, Body Composition scores, and Substance Impact is a registered
      `InsightModel`.

### The delta from the ten-item feedback — re-read against the code

The ten-item list was worked through over several sessions and then re-read
line by line against what actually shipped. Most of it is genuinely closed. Six
clauses are not, and they were not visible from the summary lines above because
each sits *inside* an item that is otherwise done. Each was verified by grep, not
recalled.

#### The suggestion lifecycle — done

- [x] **Dismissible, on both surfaces.** Persisted by content-derived id, so
      "the same suggestion" means the same thing across a regeneration.
- [x] **Today has a suggestion card** — the single best-founded one, with a
      dismiss control. It had none at all; the engine shipped and this surface
      was never built.
- [x] **Insights is the persistent reminder**: pinned above everything, collapsed
      to a count by default, expandable, and keeping dismissed rows dimmed with a
      restore button — which is what makes dismissing on Today safe rather than
      destructive.
- [x] **A dismissal lasts thirty days**, or until something genuinely new
      appears. New findings have new ids and so were never dismissed, which is
      the whole mechanism.
- [x] **"Completed" needed no per-suggestion definition.** Per-basis rules would
      have needed three different answers — a grounding gap closes when the fact
      is entered, a departure closes when the signal returns, a contrast from
      your own history never closes at all. None of it was necessary: the engine
      only emits a suggestion while its condition holds, so disappearing from its
      output *is* resolution by whichever route, and the dismissal it left behind
      is pruned.

#### The place the build disagreed with the brief — resolved, and the brief was right

- [x] **Gaps are crossed with a smoothed prediction now.** The first answer was a
      straight dashed line plus an argument: a curve through two endpoints
      overshoots and invents a local extremum in the one stretch where nothing is
      known. That argument is sound *about Catmull-Rom and natural cubics* and it
      was mistaken as an argument against curvature. A **monotone cubic Hermite**
      — Fritsch–Carlson, the construction behind PCHIP — is built to guarantee
      exactly the missing property: no interior extremum, and the curve never
      leaves the interval its two measured endpoints define. Both facts are
      pinned by tests. Still dashed: smoothing changes nothing about the fact
      that nobody measured it.

      Worth keeping as a lesson — "that technique has a fatal flaw" is not the
      same claim as "this is impossible", and the gap between them was a shipped
      deviation from an explicit instruction.

#### The rest

- [x] **A blood-pressure drift counter.** Measured by holding each cuff reading
      out and fitting on the ones before it — scoring a fit against readings it
      was fitted through reports how well least squares interpolates, which
      always flatters. Judged against the fit's own claimed uncertainty, floored
      at ±5 mmHg (ISO 81060-2, the accuracy the cuff itself is held to), because
      a fit through a handful of points can claim a residual spread of nearly
      zero and for a person whose readings sit on a line claimed exactly zero.
- [x] **Sleep Quality reads the stage breakdown now.** `.sleepEfficiency`,
      `.sleepDeepMinutes` and `.sleepRemMinutes` are canonical metrics, parsed
      from Oura, Whoop *and* Apple Health — all three were sending them and all
      three parsers were discarding them, so the card scored a night by its
      length and its breathing while the composition of that night sat unread in
      the same payload.

      Deep and REM are scored as a **share of the night, never as a minute
      target**. A six-hour sleeper with textbook proportions has a duration
      problem, which the duration term already scores; a minutes target would
      charge them twice for one short night. Efficiency gets a real band (≥85%,
      the National Sleep Foundation consensus figure); the stages get none, and
      the reason is written down.
- [x] **The substance log feeds the suggestion engine.** The strongest adverse
      response — the nights after a log against the nights after nothing — now
      surfaces as a `yourOwnData` suggestion with both night counts stated. Gated
      on effect size *and* an absolute floor, because a person whose clean nights
      sit in a very tight band gets a tiny divisor and a fifth of a bpm would
      otherwise clear half a standard deviation.
- [x] **App-launch loading screen.** `LaunchScreen.swift` draws it, and the parts
      that can be *wrong* live in `Presentation/LaunchNarration.swift` in
      InsightKit, with tests — the app target has no test target and the two
      failure modes here are both invisible to a compiler.

      Shipped: a centred `heart.fill` breathing on a 2.6 s cycle with three
      staggered rings radiating out of it, a status line rotating every 1.25 s,
      a cross-dissolve into the tabs, and a separate reassurance register past
      7 s. `AppModel.launchPhase` is the new signal — `isSyncing` was one flag
      over two waits that feel nothing alike.

      **The timer paces, the phase clamps**, and the two constraints in the
      original scope turn out to pull in opposite directions. Phase-driven alone,
      a warm launch flashes three messages in half a second. Timer-driven alone —
      which is what the scope asked for — it announces "Generating insights"
      while the network request it depends on is still out. So the timer sets the
      pace and the phase sets a *window*: never a line whose phase hasn't been
      reached (the ceiling), and skip ahead rather than narrate a wait that has
      already finished (the floor). The invariant the tests actually pin is the
      simpler one underneath both: **nothing replaces a line before it has been
      on screen long enough to read** — not a phase that jumped three steps, not
      the handover into the reassurance copy.

      Three floors exist because each is the kind that gets dropped in a
      refactor. `minimumOnScreen` (0.9 s) stops a fully-cached launch from
      flickering the splash in and out inside a quarter-second, which is worse
      than never showing it. `hardCeiling` (20 s) releases the screen whatever
      the phase says, because a splash that never leaves is the worst thing this
      file could ship and it only takes one refresh path that forgets to reach
      `.ready` — `AppModel.refresh()` therefore sets `.ready` in a `defer`
      declared *above* the too-soon refresh gate. And the last line of each
      phase is the one a slow step parks on, so it is never the joke.

      Two smaller ones, both about not lying: no progress bar, because the launch
      has no measurable fraction complete and a bar filling at a rate unrelated
      to the work is a lie the user learns to distrust. And the splash sits on
      `systemGroupedBackground` — the same colour every tab uses — because a
      cross-dissolve between two different backgrounds carries a flash with it.

      `isLaunching` is decided in `AppModel.init` from `hasCompletedOnboarding`
      rather than in the view: `@State` cannot read the environment for its
      default, and one blank frame is the exact thing being fixed. It only ever
      goes true → false, so the splash cannot reappear on a later foreground —
      `RootView.task` runs again then, and a splash over a warm app would be a
      worse bug than the blank screen this replaces.

      **The first version of the above shipped a 32-second launch, and the user
      reported it.** Three causes, only one of them new. Written out because the
      shape of the mistake is more reusable than the fix:

      - **The screen gated the app instead of bridging to it.** It waited for
        the whole of `refresh()` — network sync, ingest, insight pass, on-device
        summary — before revealing Today. Before the launch screen existed, the
        tabs were up from the first frame and every bit of that ran *behind*
        them, with a spinner on the Today card saying so. So the feature took
        work that was already correctly backgrounded and put it in front of the
        user. `shouldDismiss` now takes `hasContent`, fed by `isHydrated`:
        **the screen waits for enough data to draw Today and nothing else.**
      - **A SwiftUI launch screen cannot cover the pre-first-frame gap**, and
        7–8 s of the report was exactly that gap. `AppModel` is a `@State`
        default, so its `init` ran before SwiftUI drew anything — and its `init`
        did the whole hydration: a JSON decode of a six-figure sample array, the
        sanitiser, the temperature reconstruction and all seventeen insights.
        The app was not white by choice; it had not reached its first frame.
        Fixed twice over: `UILaunchScreen` was an empty dict (= plain white) and
        now carries a launch colour, which needs no code and appears instantly;
        and hydration moved to an async `hydrate()` with the
        expensive half on a detached task. **That hop was free because the
        engine and sample types were already `Sendable` — built platform-free so
        they could be tested on Linux, which turns out to be the same property
        that lets them leave the main thread.**
      - **The animation froze for ten seconds** because it was drawn in SwiftUI
        on the main thread — `TimelineView` at display rate, a shadowed symbol
        and a full-screen gradient every frame — so it stopped dead exactly when
        real work started, which is when a loading animation most needs to move.
        It became a hardware-decoded video, and then — see below — a live Metal
        render. `RootView` also stopped applying `.opacity`/`.scaleEffect` to
        the whole `TabView`, which forced four tabs of lists and charts through
        an offscreen buffer for every frame of the transition.

      And one that is worth its own line, because it is a general trap:
      **the hard ceiling could not fire.** It was polled from the `@MainActor`
      narration loop, so it was starved by precisely the main-thread work it
      existed to protect against — the one launch that needed a ceiling was the
      one launch that could not use it. It now sleeps off the main actor and
      hops back only to act. **A timeout must not live on the thread it is
      timing out.**

      **Then the animation was replaced a second time, and this is what ships.**
      The video was the user's own Gemini render, cropped out of a phone mockup
      and de-captioned — but it was 608×1078 on a screen that upscales it ~2.4×,
      with its dot density and its speed fixed at generation time. All three of
      those were the next round of feedback, and none is fixable inside a file:
      you cannot add dots to a video. It is now generated live —
      `LaunchParticleField` (InsightKit, nine tests) builds an 85k/240k point
      cloud on the implicit heart surface by ray-bisection; `LaunchParticleView`
      draws it as Metal point sprites, turning once every eighteen seconds.

      Four things that cost a round trip each and are worth not repeating:

      - **A `.metal` file broke the user's build and CI could not see it.**
        Xcode 26 ships the Metal compiler as a separately downloadable
        component; GitHub's `macos-15` image has it and the user's Mac does not,
        so `CompileMetalFile` failed with exit 65 on the only machine that
        installs anything while CI stayed green. The shader is now compiled at
        runtime with `makeLibrary(source:)`, which needs no toolchain anywhere.
        **Any build input that is not plain Swift is a place the two build
        environments can differ.**
      - **`UILaunchScreen`'s image was drawn at 3×.** The poster went into the
        asset catalog's *1x* slot, so iOS read 1179×2556 as points and drew it
        centred and cropped on a 3× screen — the heart flashed in enormous, then
        cut to size. The launch screen is colour-only now: a flat colour cannot
        be the wrong size, and guessing at the right scale slot costs a deploy
        cycle to test.
      - **Density and colour were matched by measurement, not by eye.** The
        first version read as "too light, not dense enough" and measuring the
        user's own reference frame said exactly why: ink coverage 30.6% against
        15.9%, saturation 53.2 against 23.7, darkest 5% at 125 against 187. The
        highlight was mixing 82% of the way to white. Now 33.4 / 53.6 / 137.
      - **The status line was placed where the mist is thickest.** Sweeping ink
        coverage in horizontal bands: 1.6% at 0.58–0.63, 37% at 0.74–0.79 —
        where it had been, because that is where the *reference* put its
        caption, and this ring has no gap there. It also used `.secondary` on a
        screen that commits to a light background whatever the system says, so
        on a phone in dark mode it resolved to light grey and vanished.

      The splash is **always light**, on `#D9D9D9`, and `UILaunchScreen` uses
      the same colour so the static-to-live handoff has nothing to see.

- [ ] **Camera + LiDAR guided body scan.** Flagged in the original feedback as a
      roadmap note rather than a build, and deliberately left as one. It belongs
      beside the other unstructured-data captures: a guided capture producing
      body measurements would feed Body Composition, which today can only report
      what a smart scale tells it. Scoping notes for whoever picks it up:
      `ARKit`'s `sceneReconstruction` needs a LiDAR device (Pro models only), the
      guided-capture UX is the hard part rather than the mesh, and circumference
      estimates from a mesh have no validated accuracy claim — so anything it
      produces should enter as its own metric with its own provenance, never
      merged into a scale's figures. Same rule as vascular age: two models
      disagreeing is information, averaging them away is not.

### The performance and interaction pass

- [x] **Cold-launch hydration: the insight pass is 3.7× faster, and it needed no
      product decision at all.** This was logged as blocked on a question for the
      user — read the whole history on launch, or a recent window with the rest
      loaded behind Today? — on the assumption that every cheap fix changes what
      the first frame knows. Measuring it first showed the premise was wrong.

      The cost was not the volume of data; it was the same work repeated.
      `MultiSource.breakdown` filtered all ~130k samples and sorted the survivors
      on **every** call, `Array.samples(of:)` did the same (and is the base of
      `latest` / `latestValue` / `meanValue`), and both were called once per
      metric *per insight model* — resting heart rate is read by seven of the
      seventeen. Separately, `SourceSeries.bucketed` asked
      `Calendar.dateInterval(of:for:)` once per sample, which was ~400 ms of a
      ~470 ms heart-rate read on its own.

      Three semantics-preserving changes, all in InsightKit:
      `EvaluationMemo` (a `@TaskLocal` memo scoped to one `evaluateAll`, so it
      cannot outlive the data it was built from); day-interval reuse in
      `bucketed`, which holds the previous reading's interval while the next one
      still falls inside it; and dropping a re-sort of each group in `breakdown`
      that `deduplicate` had already done.

      Same benchmark either side, 131,400 samples / 24.7 MB (x86 Linux — the
      ratios travel, the absolutes don't): `evaluateAll` 1774 → **476 ms**,
      whole hydration block 2796 → **1564 ms**.

      Two things worth keeping. **"This needs a product decision" is a claim
      about the implementation and it can be wrong** — the same shape as "no
      provider gives us a bedtime", which also turned out to be a fact about the
      parsers rather than the world. And **a cache is only worth having if its
      answers are provably the uncached ones**: `EvaluationMemo`'s identity check
      is a buffer-identity argument rather than a fingerprint, and
      `EvaluationMemoTests` asserts both that memoised results match uncached
      ones and that a memo never answers for an array it was not opened for.

      The decode half is **not** covered by this item — see the separate open one
      below, deliberately not folded in here. A multi-clause `[x]` hiding an
      unfinished clause is how six of them once survived a "closed" list.
- [x] **Shrink the cold-launch decode** — **done 2026-08-01 (`c0028f2`,
      installed).** This item said "needs the user" because a format change
      needs a migration path; the user's "work on load performance" was the
      go-ahead, and the migration path is the safe half of the design:
      `loadCachedSamples` tries the compact file first and falls back to the
      legacy JSON, which the next save retires, so nothing is lost on the way
      through and a downgraded build merely re-syncs.

      `SampleCacheCodec` (InsightKit, 10 tests): each distinct source and
      metric type written once in two small tables, then a fixed 28-byte
      record per sample. On the same benchmark shape as the row above
      (~108k samples, x86 Linux, read the ratios): decode **965 ms → 4–6 ms**,
      encode 1 450 ms → 75 ms, file 19.6 MB → 2.9 MB. Two findings worth
      keeping:

      - **The per-sample UUID was the file's biggest field and its identity
        was needed by nothing** — SwiftUI list identity within a session;
        dedup keys on family/minute/value, the cache merge on `source.id`.
        And regenerating with `UUID()` was itself measured at **145 ms for
        108k calls — the entire remaining decode cost** — so ids are minted
        from one random base per decode plus a counter. When a fix lands and
        the cost stays, measure what replaced it.
      - A malformed, truncated or legacy file decodes to `nil` and falls
        back — never a crash or a half-read — and a record whose metric type
        a future build retired is skipped, not fatal. The `RawValue`
        bare-scalar pin is untouched: this codec covers `[HealthMetricSample]`
        only; the smaller `synced_other.json` stays JSON, unmeasured and
        deliberately unchanged.
- [x] **The substance log page was slow because one call did far too much.**
      Tapping a chip called `recompute()`, which evaluates all seventeen insights
      across the whole sample set and then discards every derived cache. Exactly
      one model reads the log and not one of those caches does, so the three
      mutations now re-evaluate that one insight and invalidate only what a
      changed result affects.
- [x] **The date picker is the default path**, pre-filled with now, rather than
      hidden behind a long-press nobody discovers.
- [x] **Edit is a real control** — a bordered capsule with a word in it, not a
      caption-sized pencil under the 44pt minimum target inside a run of
      secondary text.
- [x] **Direction next to every score**, on Today and Insights cards. See below
      for why it is not "vs yesterday".

### Test and file hygiene
- [x] Shared test clock — narrow version, as scoped. The obvious "one `Clock` for
      the whole target" was audited and rejected: two files model a forward
      timeline with a movable `now`, one uses `Calendar.current` deliberately
      (production `VitalReader` defaults to it), and one fixture needs a
      fractional `daysAgo: 29.9`. Five files are safely in scope. See
      `activeContext.md` ▸ 6.
- [x] A golden dataset — a seeded *generator* rather than a recorded blob, so
      each shape is stated in a readable line. It immediately found that a
      sustained fever contaminates its own rolling baseline.
- [x] Split the largest files. All four done. `AppModel.swift` (786) and
      `InsightDetailView.swift` (653) are now the largest and are deliberately
      **not** split: Swift's `private` is file-scoped, so an extension-based
      split of either widens every member the moved code touches, and both are
      dense with private state.

### Charts
- [x] ~~Filled `AreaMark` min/max bands~~ — **done 2026-08-01.**
      `AreaMark(x:yStart:yEnd:)` ships in `BodyCompositionTrendChart` as the water
      film and draws correctly. The overload takes no `stacking:` argument, which
      is a compile error rather than a silent one. See the `add-chart` skill.

### Crowd-sourced norms — "How you compare" for the signals nobody has published

"How you compare" renders on every card as of 2026-08-01 and places each of the
card's inputs against a published age-and-sex distribution. **Exactly three
metrics have one**: resting heart rate, rMSSD and VO₂max. Every other signal the
app reads is listed by name under "No published norms for these yet".

That is a gap in the literature rather than in anybody's data, and it is
concentrated in precisely the signals only wearables measure — heart rate
recovery, day strain, walking heart rate, sleep efficiency, skin-temperature
deviation. The research has not caught up with the hardware.

The open item is to compare those against other people using this app.
Specifics, in the order they need deciding:

- [ ] **Nothing leaves the phone today, and that must stay true until the user
      opts in per signal.** Every number in the app is currently local or
      provider-sourced; a comparison feature is the first thing that would
      change that, and it changes the app's privacy claim rather than adding to
      it. Opt-in per metric, not one blanket switch.
- [ ] **A distribution needs a denominator before it means anything.** A centile
      against forty other users is noise wearing a number. Decide the floor —
      per age band and sex, not overall — and show "not enough people yet"
      below it, the same way `SectionPlaceholder` handles every other floor.
- [ ] **Aggregate on the server, never share rows.** What comes back should be
      a mean and a spread per (metric, age band, sex), which is all
      `PeerStandingModel.Norm` needs. That also keeps the client unchanged:
      `norm(for:age:sex:)` returns a `Norm?` today and would return a fetched
      one instead of `nil`.
- [ ] **Say which kind of norm a row rests on.** A published NHANES-derived
      centile and an in-app one are different claims and must not render
      identically — `SectionCaveat.approximateNorms` currently speaks for the
      published case only.
- [ ] Decide whether a user contributes automatically once they consume, or
      whether the two are separate choices.

Nothing here is started. `PeerStandingModel.hasPublishedNorm(_:)` is the seam.

### On-device ML
- [ ] Core ML personal anomaly detection once enough history exists.

## How trend indicators are rendered, and why

Researched rather than guessed, because the obvious design is wrong. Surveying
what Oura, Whoop, Garmin, Apple Health, Fitbit and Withings actually ship:

- **Not one of them renders a day-over-day delta on a daily score.** Every one
  compares a short window against a longer one, or renders position within a
  personal range.
- The reason is arithmetic. Day-to-day variability in HRV sits around 5% and is
  reported between 3% and 13% depending on method, while a genuinely hard day
  moves it 10–20%. An arrow driven by yesterday reports noise most days, and an
  indicator that is usually wrong gets ignored — which costs more than not
  having one.
- **Colour is valence, never direction.** Whoop's green/yellow/red, Oura's
  Optimal→Pay Attention, Garmin's Balanced/Unbalanced — and Garmin's
  "Unbalanced" covers *above or below*, which is the proof that direction and
  valence are different axes.
- **"Not enough data" is a first-class state**, not a blank: Apple's "Needs More
  Data", Garmin's "No status".
- **Static is suppressed.** Apple omits a trend outright when nothing moved.

So `ScoreChange` keeps the direction the brief asked for and moves the
comparison somewhere the signal survives: today against the trailing week for
daily cards, four weeks against the trailing quarter for trend cards. The move
is standardised against the reference window's own spread, with a two-point
absolute floor, and Today is held to a stricter bar than Insights because it is
seen an order of magnitude more often.

## Guardrails (unchanging)
- Not a medical device; not medical advice. Substance features are
  harm-reduction and descriptive, never encouragement or dosing guidance.
- Health data stays on-device; the only network calls are the user's own
  wearable APIs. No health data on any server.
