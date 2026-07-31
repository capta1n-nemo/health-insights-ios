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
      reports Oura's vascular age beside its own. Only `dayStrain` is unread —
      Whoop isn't connected.

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
      and 330/330 pass on Linux. `scripts/bootstrap-swift.sh` installs a
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
- [x] **A generated symbol index** (`docs/symbol-index.md`, 198 types) so "where
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
- [x] **Roadmap 4c — reference bands** on the eight metrics that have a published
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

## In progress / not yet device-verified
- [ ] On-device walkthrough of the latest nine-part UI pass (CI-green, not yet
      manually confirmed on the phone) — see `activeContext.md`.
- [ ] Heart & fitness age and Fitness trajectory on the phone: both are new cards
      on the Insights tab. Worth checking the three-age comparison row renders on
      the narrowest device, and that a profile with no blood pressure shows the
      fitness half alone rather than an empty card.
- [ ] The ingestion pipeline and Vitals Check on the phone — see
      `activeContext.md` for the specific things to look at, including that the
      Oura setup screen no longer raises the "Paste from your Mac?" prompt.

## Next

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
      record counts, so it isn't client-side truncation. Offered, not yet taken up.
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
- [~] 6. Sleep Quality — respiratory rate from the night rather than the last ten
      minutes, and consistency no longer stuck at 0/100. The third clause,
      "expand inputs using additional available Oura/Apple Health data", is only
      partly met: it gained overnight blood oxygen and skin temperature, but the
      Oura parser still decodes seven fields of a sleep record and ignores the
      stage breakdown entirely. See the delta list below.
- [~] 8. Blood pressure scores from the AHA bands, and calibration honours
      "five once, then two per thirty days". **The drift counter itself was never
      built** — there is no figure anywhere saying how far the estimate has moved
      from the last cuff reading. Verified: no such quantity exists in
      `BloodPressureEstimator`.
- [x] 9. Heart & Fitness Age scores from a logistic, and both ages are charted
      over time.
- [x] 4a. Colour bands on the blood-pressure chart.
- [x] 4b. Gaps bridged with a dashed connector on the metric-detail chart,
      bounded by the metric's own join distance and by a quarter of the visible
      window, on the metric-detail chart *and* the insight overlay.
      **Deliberately straight rather than smoothed, which is not what was
      asked for** — see "The one place the build disagrees with the brief" below.
- [x] 4c. Reference bands on the eight metrics with a published normal range,
      each carrying its own caption and provenance. Heart rate deliberately gets
      none: its bounds are for the *day's* value and that chart plots raw samples.
- [x] 1. Today summary gated on a fingerprint of the results, plus a 30-second
      floor on manual refresh and a last-updated line so a floored pull reads as
      "up to date" rather than broken.
- [~] 2. "Improve Your Health" — the *engine* is done: a section on the Insights
      tab, from four bases (signals converging, your own history, a fact the app
      is missing, a signal off baseline), ranked by how well-founded each is.
      **The lifecycle half was never built** — nothing is dismissible, nothing
      appears on Today, and there is no notion of a suggestion being finished.
      See "The suggestion lifecycle" below.
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

#### The suggestion lifecycle — the largest gap

The engine generates suggestions and ranks them. Everything the feedback asked
for *around* that was never built, and this is the whole of it:

- [ ] **Suggestions are not dismissible.** There is no dismissal anywhere in the
      app — verified: no dismissal state, no store, no gesture.
- [ ] **Nothing appears on Today.** `DashboardView` has no reference to
      suggestions at all; they exist only in `InsightsListView`. The asked-for
      behaviour is that Today shows one and it reappears only when a *new*
      suggestion is generated — which needs a record of what has already been
      shown, not just what is currently true.
- [ ] **The Insights row is not the persistent reminder that was asked for.** It
      should be pinned to the top, compact and collapsed by default, expandable
      for detail, and it should retain dismissed suggestions as well as active
      ones. Today it is an ordinary card in flow order, always expanded, and
      shows only what the engine currently emits.
- [ ] **There is no notion of a suggestion being finished.** "If all associated
      tasks are completed, hide it from both Today and Insights" needs each
      suggestion to declare what completion *means* — and for the three bases
      that is three different things. A grounding gap closes when the fact is
      entered; a departure closes when the signal returns to baseline; a
      contrast from the user's own history never closes at all, because it is an
      observation rather than a task. That last one is the design question, and
      it needs answering before any of this is built.

The shape this suggests: `Suggestion` grows a stable identity that survives
regeneration (it has `id` already, and the ids are content-derived, which is most
of the way there), plus a persisted set of dismissals and a per-basis rule for
what counts as resolved. The store is the easy half.

#### The one place the build disagrees with the brief

- [ ] **"Replace dotted-line gap markers with smoothed predicted values."** The
      app bridges gaps with a **straight** dashed connector instead, on both
      charts, and the reasoning is written into `SeriesBridging`: a Catmull-Rom
      curve overshoots outside the measured range and invents a local extremum in
      the one stretch where nothing is known. The endpoints are already bucket
      aggregates — median for weight, mean for the rest — so some smoothing has
      happened; it is just not visible as curvature.

      This is recorded as an open decision rather than a closed item because it
      is a deliberate deviation from an explicit instruction, and the call is the
      user's. If a curve is wanted anyway, the honest version is a fitted
      prediction with its residual spread drawn around it — the standard
      `ScoreHistoryChart` and `VO2Trajectory` already hold themselves to — rather
      than an interpolation that looks like measurement.

#### Four smaller ones

- [ ] **A blood-pressure drift counter.** The cadence rule shipped (five readings
      to ground, two per thirty days to maintain) but the counter itself does
      not exist: nothing anywhere says how far the estimate has moved from the
      last cuff reading. That number is what tells a user *why* they are being
      asked to cuff again, and it is a small addition to
      `BloodPressureEstimator` beside the calibration phase.
- [ ] **Sleep Quality is still reading a fraction of what Oura sends.**
      `OuraResponseParser.SleepRecord` decodes seven fields. The stage breakdown
      — deep, REM, light, awake — plus sleep latency and efficiency are in every
      payload and are ignored, and they are the inputs a sleep score is normally
      built from. `.sleepOnset` now exists and is not wired into Sleep Quality
      either, though the regularity it measures is a known component of sleep
      quality. Ingestion is the work; the scoring change is small once the
      metrics exist.
- [ ] **The substance log is a data source for charts and nothing else.**
      `SubstanceWindow` lets a chart shade the after-window, but no insight, no
      pattern finder and no suggestion reads the log. The asked-for framing was a
      timestamped source "available to other parts of the app" — the obvious next
      consumer is the deep-dive correlation, which already asks whether one
      series leads another.
- [ ] **Camera + LiDAR guided body scan.** Flagged in the original feedback as a
      roadmap note rather than a build, and never recorded here until now. It
      belongs beside the other unstructured-data captures: a guided capture
      producing body measurements would feed Body Composition, which today can
      only report what a smart scale tells it.

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
