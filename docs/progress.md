# Progress

Philosophy unchanged: **use every signal, get creative with it, and be honest
about confidence.**

**And the scope, stated by the user 2026-08-03: *"this is a master health app,
in future it will need to support every domain of health and wellbeing."*** So
the default answer to "does this domain belong here" is **yes, eventually** —
what decides the order is which data is already arriving and which questions the
reader is actually asking. See "Every domain of health" under Next for what is
already in the export and unread.

## ⚠️ This file is HISTORY. It no longer lists open work.

**Consolidated 2026-08-07.** There used to be three open-item lists — a
generated table at the top of this file, `docs/backlog.md`, and two hand-written
tables in `docs/activeContext.md`. A ground-truth pass across all three found
they **disagreed in twenty places**, with **fifteen rows describing work that
had already shipped**. Three lists is three chances to be wrong and three
handovers' worth of effort to keep in step.

**`docs/backlog.md` is the one list now**, and it is read by a script rather
than by grepping:

```bash
./scripts/backlog.sh --asks    # what the reader asked for and has NOT got
./scripts/backlog.sh --next    # the next batch, and the model it needs
```

Everything that used to be listed here is there, with an id, a wave, a stream, a
complexity tier and a gate. The rows that lived **only** here — the
"Outstanding from the 2026-08-04 Mac session" tables and the roadmap table —
were moved into §H of the backlog, keeping their numbers (`#27` → `P27`,
roadmap row 14 → `R14`), so nothing was lost in the move.

⚠️ **What this file is still for, and it is worth keeping:** the shipped record
below is the only place that says *how* something came to be the way it is, and
what found it. Several entries below still carry `- [ ]` boxes — **those are
historical**, a record of what a given session left open at the time, not a live
list. Do not work from them.

## Shipped

### Session 28 (2026-08-06) — the reader's answers, and three reversed refusals built

**`docs/backlog.md` is the authority for what is open.** §A is 24 decisions now
rather than 24 questions, and §B5 is a build list rather than a set of refusals.
Standing rule 0 governs all of it: compliance and clearance are no longer
reasons to refuse a feature.

- [x] **Biological age** (`972e2d7`) — `BiologicalAgeModel`, five markers each
      inverted through a published age norm, combined by inverse-variance
      weighting with no tunable parameter. Chronological age deliberately
      excluded; ±11 years printed rather than hidden. Bespoke section shows every
      marker's own age, error and share on one axis of years.
- [x] **Cuffless BP, ungated** (`0ea9411`) — the estimator no longer disappears
      when calibration lapses; it widens by what it has measurably been out by.
- [x] **Q2 — one ± and one cuff age** (`0ea9411`).
- [x] **Mental health** (`867129e`) — behavioural departures, never reassures,
      no diagnostic claim, deliberately off the balance web.
- [x] **Q3 the fitness age's real width** (`5330d92`) — the error bar is
      inverted through the same path as the point estimate.
- [x] **Q4 micronutrients wired** (`5330d92`) — `MicronutrientTargets` was dead
      code while the card made sex and DOB mandatory *because of it*. Logged
      nutrients score; unlogged ones are modelled from energy at weight 0.
- [x] **Q5 feedback ungated** (`5330d92`).

Later in the same session, after a scouting pass over the remaining backlog:

- [x] **Every card has a bespoke section** (`adca807`) — `bespokeSection` is
      exhaustive, `default: EmptyView()` is gone. Gait's speed decomposition,
      Nutrition's vitamins table, Metabolism's two bars, and one shared
      signed-departure strip for Stress load and Mental health.
- [x] **"Why is this score what it is"** (`964c03e`) — in the deep dive under
      the insight web, where the reader placed it. `ScoreBlend` was discarding
      every component's own sub-score; that one dropped field is why no card
      could answer this for the life of the app.
- [x] **Tokens are structurally unserialisable** (`964c03e`) — `OAuthTokens` is
      no longer `Codable`. Half of Q10.
- [x] **The radar reports on itself** (`44fb94e`) — 2 flag days of 83 judged,
      over 92% coverage, on the reader's own record. Three counters that were
      computed and thrown away on every evaluation.
- [x] **Apnoea identifiers requested** (`44fb94e`) — makes "the reader has no
      apnoea data" measurable instead of unfalsifiable. No UI.

Still open from this session, all in `docs/backlog.md`:

- [x] **The cycle tab** — all four gating decisions answered, and both slices
      built.
- [ ] **`walkingSpeed` reads 0 days in the last 90 in the simulator**, against a
      1,093-day figure measured on the raw export. Gait still scores, on its
      other two channels. Backlog D17.
- [x] **The cycle tab, slice 1** (`a8be5ae`) — the fifth tab, a calendar you
      tap, and cycle length as a **range with its spread** rather than an
      average. The blocking single-user question was asked and answered: she
      installs on her own phone with her own key.
- [x] **The cycle tab, slice 2** — the fertile window, the phase model,
      phase-aware baselines and the ring's nocturnal temperature channel.
      ⚠️ **The baselines are built but deliberately not wired into the symptom
      radar**: the radar's thresholds are calibrated against its current
      reference, so the wiring and the recalibration are one commit or neither.
      Named TODO at `PhaseAwareBaseline.swift:29`; reasoning in `backlog.md`
      §A3. The luteal false alarm is pinned as a test that asserts the *current*
      behaviour and will fail when the fix lands.
- [ ] ~~**The cycle tab is blocked on a question**~~, not on code: the app is
      structurally single-user and the tab is for the reader's wife. Three
      answers, three different builds. Backlog §A3.
- [ ] **Q11 notifications is deferred** — no `BGTaskScheduler` anywhere, so
      anything built today fires only in the foreground.

### Screen Time import, closed out (2026-08-03)

The reader's three device reports plus a fourth found while fixing them. All
four are done and tested; the OCR import feature has no open items.

- [x] **The chart's y-axis label no longer beats the real total** (`2a65453`).
      "↑ 55% from last week" sits directly above the bar chart, `classify` takes
      its context from the line above, so the axis maximum ("22h") became a
      `.weeklyTotal` and the average cross-check refused an entirely valid
      screenshot. `Result.weeklyTotal` now **chooses by agreement with the
      printed daily average** — the same check that was already used to reject —
      so the right row wins whatever OCR did to the words around it. Named-row
      and largest-wins survive as the fallback when the average is cropped off.
      Selection and check share one tolerance, with a canary for the drift.
- [x] **Re-importing a day is an accumulation, not a recency question**
      (`2a65453`). Between two `.dayExact` readings of one day the **larger**
      wins: screen time only accumulates within a day, so the bigger figure was
      captured later. Deliberately *not* "newer `recordedAt` wins" — a 23:00
      capture imported after a midday one would otherwise be overwritten by the
      partial. A week estimate is a *share* of a total, not an accumulation, so
      it still resolves by recency; a manual correction afterwards still beats
      both.
- [x] **A Week import hides the day picker** (`02fc5c3`). The date picker and
      hours/minutes wheels describe one day and a week writes seven. They return
      if the week is discarded.
- [x] **One Save** (`02fc5c3`). "Save these 7 days" is gone; the toolbar Save
      commits whichever thing is on screen. It does not dismiss when a week wrote
      nothing, because "those days already have better figures" is an outcome
      the reader has to see — dismissing would look identical to having saved.

⚠️ The two UI changes are app-target SwiftUI, so **CI is their only gate** and it
had not reported when the session closed. The parser and precedence work is
covered by 1331 local tests.

### Deploy and runner tooling (2026-08-03)

- [x] **`concurrency: deploy-to-iphone`** on `deploy.yml`, `cancel-in-progress:
      false` — deploys serialise instead of sharing the runner's `_work`. False
      deliberately: the verdict step is `if: always()`, so a cancelled run would
      push `refs/deploy/failed` for a commit nobody tried to install.
- [x] **`refs/deploy/errors` can describe a pre-build failure**
      (`.github/deploy-prebuild-failure.txt`). It only read `build.log` and
      `install.log`, so four deploys that died at *checkout* reached the reader
      as one sentence naming no step, no cause and no fix.
- [x] **`scripts/fix-runner.sh`** — the repair for two `Runner.Listener`
      processes in one installation directory, which is what killed those four.
      `runner-doctor.sh` diagnoses, this repairs; both now say so.
- [x] **`deploy.yml`'s setup note no longer says `sudo ./svc.sh stop`.** This
      runner is a LaunchAgent, so sudo makes the stop a silent no-op — the
      advice cost three password prompts during a recovery that then did nothing.
- [x] **A short sha no longer reads as "no verdict"** (`15792b3`). Both status
      scripts passed `$sha` to `git ls-remote` untouched, and the refs are keyed
      on the full 40-character hash — so naming a commit reported no result for
      one that had `passed`, `failed` and `errors` refs all pushed. Cost a
      15-minute wait and a wrong report to the user. `ci-status.sh` had it
      identically.
- [x] **The commit-signing nag is deleted** (`1f95030`) — hook registration,
      script and `commit.gpgsign` all gone at the user's instruction.


### Retrospective Screen Time import (2026-08-02)

- [x] **Screenshots file to the week they were taken, not the week they were
      imported.** `parse(_:now:)` became `parse(_:capturedAt:)` with no default,
      anchored on the image's own EXIF/TIFF date via `ImageCaptureDate` — no
      photo-library permission needed.
- [x] **Week headings are read** — relative ("Last Week's Average") and explicit
      ("20–27 Jul"), anchored on the start and always seven days.
- [x] **"Total Screen Time" on a Week view is a week**, not a day. It was one
      reclassification away from recording 99h 33m as a single day.
- [x] **Per-day estimates from the bar chart.** `ScreenTimeChartReader` (app,
      CoreGraphics) measures relative bar heights; `ScreenTimeChartGeometry` and
      `ScreenTimeWeekBreakdown` (InsightKit, tested) find the bars and apportion
      the **exact** weekly total across them by largest remainder — so the week
      sums exactly and only the split is an estimate. No flat fallback: an
      unreadable chart records the week and no days.
- [x] **`ScreenTimePrecedence`** — exact day > week estimate > manual, except a
      manual entry made *after* an import wins. `ManualSampleRecord` carries
      `provenance` and `recordedAt`; `DataStore.recordScreenTime` applies the
      rule at write time, so re-importing a screenshot is a no-op.
- [x] **Nothing is written without confirmation** — a Week screenshot fills a
      seven-row preview with its dates and figures, and says which are estimates
      and that the image carried no date when it didn't.
- [ ] **Not yet device-verified**: the bar measurement is the half CI cannot
      check. `ScreenTimeChartReader` finds the plot by looking for the tallest
      band of rows carrying saturated pixels, which is untested against a real
      screenshot — the confirmation preview exists so a bad read is caught by
      the reader rather than saved.

### The Insights-hero session (2026-08-02)

- [x] **The Insights tab opens without starting a single replay.** Its hero was
      `ScoreComparisonChart`, whose series were built by calling
      `AppModel.scoreHistory(for:)` — a 90-day replay per insight — from inside
      a view body, for every scored card. `ScoreBalanceWeb` reads
      `InsightResult.score` and the cached `ScoreChange` instead, both already
      in memory, so the hero draws on the first frame.
- [x] **The comparison chart is kept, not deleted** —
      `ScoreComparisonDetailView`, one tap away, where the replays cost only the
      reader who asked for them and nothing competes with them for the CPU. It
      is the only screen in the app that still asks for every history at once,
      and it says so.
- [x] **`BalanceWebSnapshot` + `BalanceWebGeometry`** in InsightKit, 16 tests:
      the polar geometry, the fixed spoke order, the three-spoke floor, the
      complete-reference rule, and the summary sentence. In InsightKit because
      the app target has no test target and this is the only place the hero's
      layout can be falsified at all.
- [x] **A skeleton that holds the card's height** (`ScoreBalanceWebSkeleton`,
      nine-sided, grid drawn for real) so the feed does not reflow when the
      snapshot lands, and `InsightsHeroModel` builds detached with a generation
      guard — the same discard-on-arrival rule `AppModel` uses for its replays.
- [x] **The tab is three named sections** — suggestions drawer, hero, card feed
      — with every existing trend card preserved in full and unchanged.

### The overnight session (2026-08-02)

- [x] **Score discontinuities swept as a class.** Body Composition's `49 · 15 ·
      15 · 55` chart was a noisy fitted slope crossing a fixed threshold and
      switching a 4/100 term into the blend at full weight. Four of the seven
      instances found across all 17 models are fixed —
      `CompositionVelocity.changeConfidence`, `wrongWaySpread(by:)`, the blood
      pressure ladders, and the three Sleep band tables. `ScoreCurve.through` is
      the shared replacement, `ScoreContinuityTests` sweeps every enrolled curve
      at 4000 points, and `verify.sh` fails on a reintroduced `case 6..<7:
      return 65`. **All seven are fixed and all seven are guarded** — the sweep
      and its verified-continuous list are in `activeContext.md`; do not
      re-derive them.
- [x] **Blood pressure scored both numbers.** The band came from systolic *and*
      diastolic, the position within it from systolic alone — 90/79.9 scored
      100 and 90/80.0 scored 60. Each axis now has its own continuous ladder and
      the worse one wins, which is the published "higher of the two bands" rule
      made continuous.
- [x] **Shortcuts is a native action.** `LogHealthDataIntent` with a metric
      picker generated from `MetricType.allCases`, so the reader stops
      hand-editing a URL and a new metric appears in Shortcuts for free. The URL
      transport stays and both routes call one `ingestShortcut`.
      `ShortcutIngest.url(for:on:)` round-trips against the parser for all 102
      metrics.
- [x] **Body Composition's RFM route documented as waiting, not broken**, and
      pinned working by `BodyCompositionRouteTests` so it is not rediscovered as
      rotten the day a waist measurement arrives.
- [x] **A test that asserts nothing now fails the gate.** `ZZProbeTests` had
      passed every run for several sessions while asserting nothing.
- [x] **No dead candidate declarations, proven.** `CandidateReachabilityTests`
      settles two suspicions the audit had carried for several sessions: Sleep's
      absolute temperatures and Heart Health's second HRV flavour are
      *fallbacks*, not dead declarations. Reading the code could not tell the
      difference; running it could.
- [x] **A reading its own series says cannot be right is flagged.** The reader's
      Vitamin A 170,000 mcg — a unit slip from upstream, sitting in the Data tab
      looking like a measurement. Judged against the series' own median, so it
      needs no per-analyte catalogue and works for all 130 unmodelled Oura
      series too.
- [x] **The gate itself was lying, and is fixed.** `verify.sh --tests` exited 0
      on a tree plain `verify.sh` exited 1 on — the mandated mode was the weaker
      one. See `activeContext.md`; the rule is *a recovery may only undo the
      thing it diagnosed*, and `verify.sh` now checks itself for it.

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
- [x] Four-tab layout: **Today / Insights / Data / Settings** (the third tab was
      "Vitals" and second until 2026-08-02 — renamed because it holds the
      substance log, the regimen, side effects and the raw imported catalogue,
      none of which is a vital sign, and reordered so the tabs read as *now →
      what it means → everything underneath*).
- [x] **The Data tab is complete by construction** — `DataDomain`, exhaustive.
      A new kind of data does not build until it has a section *and* an answer
      to search. See `docs/architecture.md` ▸ "The structural invariants".
- [x] **Every input reaches every input surface** — `InputKind`, exhaustive,
      generating the Today `+` menu and Settings ▸ Add or update data, with
      `cardRequirement` and three checks binding a card to declare what it
      takes.
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
- [x] **One button, however many routes (2026-08-02).** Full-size per-route
      blocks scaled to four stacked red buttons on Body Composition; the card
      now carries one status line per route and a single button into
      `ViewAndAddHubView`, which holds the full add-and-view anatomy for every
      route — including `MedicationHistoryView`, the previously missing dated
      view of doses and side effects. `ContributionRouteStatus` is the one
      exhaustive resolver of a route's name and summary, so a new kind of data
      (dose, goal, scan…) costs the card a line and cannot skip the hub.
- [x] **Data-tab detail pages follow one convention, enforced (2026-08-02).**
      Substances opened the add page, medication opened the Body Comp card, side
      effects opened nothing. Now every domain opens a read-only page built with
      `DomainDataScaffold` (`SubstanceDataView`, `MedicationDataView`,
      `SideEffectDataView`); `verify.sh` fails a `*DataView` that skips the
      scaffold or draws a raw `Chart`. Authority: `docs/data-conventions.md`.
- [x] **Logged data made observable (2026-08-02).** `sideEffects` and
      `activeMedication` were computed off the SwiftData store — invisible to
      SwiftUI observation, so a side effect logged from `+` didn't appear. Now
      stored and reloaded in `reloadLoggedData()`.
- [x] **Viewing consolidated to one screen per card (2026-08-02, round 2).**
      The user's call for "multiple data sources… viewed in a consolidated way".
      `CardDataView` is the card-scoped Data tab — the signals the card reads
      plus its logs and inputs, each opening the full record. The hub's per-route
      view links became one "View all this card's data" link; routes there are
      now purely *add*. `CardDataView.routeSection` is exhaustive over
      `ContributionRoute`.
- [x] **Two more published peer norms, and a three-way split (2026-08-02).**
      Lean mass via **FFMI** (Kyle 2003, BIA); blood pressure moved from "no
      norm" into **assessed-by-category** (ACC/AHA); the modelled medication
      level dropped from the comparison entirely. SDNN, sleep duration, BMI and
      bone/water researched and rejected with reasons — see `card-sections.md`
      ▸ "How you compare".
- [x] **The trend chip shows steady, and the score chart shows loading
      (2026-08-02).** `ScoreChange.chipLabel` + a neutral steady chip so "no
      change" is distinct from "not measured"; `SectionPlaceholder.isLoading`
      drives a spinner on the replaying score chart, and the open card jumps the
      replay queue.
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

### The hook-and-instruments session — done 2026-08-02 (`356e534` → `8155740`)

Six pushes, all installed. Full narrative in `activeContext.md` ▸ "Current
focus"; the shipped list:

- [x] **The shell working-directory hook** (`scripts/bash-workdir-hook.sh`) —
      the six-session standing ask, granted and built. Every `Bash` call is
      anchored to the repo root by the harness. Its construction found and
      closed a silent pre-push-gate bypass (hooks inherit the drifted cwd), and
      `verify.sh` now lints hook commands for relative paths.
- [x] **Five Vitals display defects** from the user's screenshots — doubled
      units, cumulative metrics showing the latest sliver instead of the day's
      total, Exercise Minutes missing from every Vitals category, a deviation
      labelled as an absolute temperature, fitness-age arithmetic that failed
      the reader's own subtraction.
- [x] **Concurrent refreshes coalesce** — the diagnostics log showed two full
      pipelines racing from launch, every provider fetched twice.
- [x] **Settings ▸ Export my data ▸ Model internals** (`ModelInternalsExport`,
      tested) — baselines with history-vs-floor, substance pool sizes, floors
      quoted from constants, a month of nights per source.
- [x] **Card-open and settings performance** — render-time model runs memoised
      (`AppModel.memoized`), the card a `LazyVStack`, export documents built
      detached behind per-section progress, breakdowns prewarmed off-main —
      plus a `SyncActivityPill` naming background work on every tab.
- [x] **Oura split nights combined** — the new export's first output caught
      the third cause of "7.5 h reported as 4 h"; a night's periods now sum
      (`SplitNightTests`). Proof item under "on the phone", below.

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
- [x] **Body Composition** — the **"view & add" scan entry** the user asked for
      (a fourth `ContributionRoute`). **Delivered by the body-scanner session
      2026-08-03, not by a later build of its own**: `.bodyMeasurements` is a
      route, `BodyCompositionInsight.contributions` declares it alongside
      `.fileImport`, `.medication` and `.bodyType`, and `ViewAndAddSection`'s
      exhaustive switch renders it. It opens `BodyMeasurementsSheet` — a tape
      today, and the ARKit capture behind the same button when that lands, which
      is why this was never blocked on the capture the way it was written up as
      being. The composition split half carries a stacked-area history
      (`BodyCompositionTrendChart`). Closed 2026-08-03 after checking the code
      rather than the note.
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

### The screenshot-review session — 2026-08-02 (`d96ada1` → `456ad61`, all installed)

Driven end to end by screenshots and exports off the phone. Twenty-four commits,
one red CI. What it established, so nothing here is re-derived:

- [x] **The Data tab** — Vitals renamed and moved to third (Today · Insights ·
      Data · Settings). The name had stopped being true: it holds the substance
      log, the regimen, side effects and the raw imported catalogue.
      `VitalsView` → `DataTabView`, in `Features/Data/`.
- [x] **`DataDomain`** — every kind of data has a Data-tab section or the app
      does not build. Two exhaustive switches: what it renders, and how it
      answers a search.
- [x] **Search on the Data tab**, matching row names *and* section headings.
- [x] **`InputKind`** — the master input list, generating the Today `+` menu and
      Settings ▸ Add or update data, with one switch saying what each opens.
- [x] **`InputKind.cardRequirement` and its three checks** — the rule that a
      card offering an input must declare it. Found and fixed three inputs on
      Body Composition that its "View & add" did not mention.
- [x] **Side effects are stored** (`SideEffectRecord`) and enterable by hand.
      They were parsed from Shotsy, counted into the import alert and thrown
      away.
- [x] **`MedicationResponse`** — dose-step and injection-site attribution, the
      four overall figures, the side-effect tally, and the standardised
      "is it working" overlay.
- [x] **Weight management** as Body Composition's *second* bespoke section, and
      "on board" replaced everywhere by "in your system".
- [x] **`MetricType.activeMedicationLevel`** — the app's first modelled metric,
      on the contributors chart at weight 0. See `docs/architecture.md` ▸ Rule 3
      for the three guards that keep it from reading as a measurement.
- [x] **`RenderMemo`** — the sticky-nil fix. `dict[key] as? Optional<T>` always
      succeeds, so every optional-typed render memo returned nil on its first
      ask and never computed.
- [x] **Shotsy import** — the share sheet, the integration entry, the UTI that
      was blocking it, and the async import with a progress overlay.
- [x] **`ci-status.sh --errors`, `deploy-status.sh --errors` and `--fresh`** —
      a red is now readable for a few hundred bytes instead of a 446 KB API call.
- [ ] **The share-sheet *action* extension is parked on signing**, not on code
      (`aaf185c`, reverted). App Groups need a paid Developer Program membership
      and an Xcode account on the runner Mac. `git cherry-pick aaf185c` restores
      it; `docs/deployment.md` has the errors verbatim.
- [x] **Calories from the Shotsy import are modelled** (2026-08-03).
      `MetricType.dietaryEnergy`, kcal, parsed from the file's joules — and from
      Apple Health's `dietaryEnergyConsumed`, removed from the raw pile in the
      same commit so it cannot arrive twice, the way `appleExerciseTime` had to
      be. **Charted at weight 0 on Body Composition** (`trackedNotScored`,
      beside the medication level), which is where intake earns its keep: the
      reader sees what went in against the weight it moved.
      **No reference range and no score, and that is the whole design** — what
      the right calorie figure is depends on what somebody is aiming for, so a
      band would be a target and a weight would make the card reward eating
      less. That is dietary advice, and it is the line this app does not cross.
      Its own `MetricFamily` and its own Data-tab group on `.behaviour`'s
      precedent: under `.activity` the pattern finder would suppress
      "ate more on the days you burned more", under `.metabolic` it would
      suppress "more calories, higher glucose", and both are real.
      The four macros stay in `pendingNutritionKinds` — each would need a
      `MetricType` and none has a reader.

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
- [x] **The nine cards, the balance web and the metric-detail pages — looked at
      on 2026-08-05, in a simulator carrying the reader's real export.** This is
      the first time these items have been *seen* rather than reasoned about,
      and the simulator can now answer them because `load-real-export.sh` puts
      237,828 real samples in the container. What rendered correctly: the
      Insights hero with all eight spokes banded by score, the grey "usual"
      underlay, the reference dots and the legend naming its window; Fitness
      carrying **its units** ("VO₂max 31 mL/kg·min"), which was the label
      collision; Blood Pressure showing the cuff pair *and* the estimate, each
      named; Nutrition and Metabolism inviting input rather than reading "No
      data yet"; the Today summary; the D/W/M/6M/Y/All control; reference
      bands, gap dashes and the substance-shading note on a metric detail page.
      **Two defects were found by looking, and both are new roadmap rows** —
      see #35 (two ± and two cuff ages on one BP screen) and the note below.
- [ ] **The Resting Heart Rate detail page is the cross-device defect, drawn.**
      Found 2026-08-05 on the simulator. The chart says "Each device is a
      separate colour, so you can spot where they disagree" and then does
      exactly that — one source spikes to ~87 on a night another reads ~55,
      which is the ~13 bpm watch-vs-ring gap the research measured, except
      larger. **The chart is honest and the summary above it is not**: "Range
      over this period — Low 49, Average 60, High 87" pools every device into
      one mean, which is the averaging `VitalReader.swift:153` does and roadmap
      #27 forbids. Fixing #27 must fix this header in the same commit, or the
      page will draw the disagreement and then average it two inches higher up.
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
- [x] **The nap fix, proved from the data — settled 2026-08-02** by the
      per-source inventory built for exactly this. `restingHeartRate` max 119
      **is Oura's own row** (min 45 / median 55 / max 119), and Oura's raw
      `lowest_heart_rate` carries the same 119 — so it is what the ring
      reported for a real night, not parser contamination, and the earlier
      ruling stands: the bound rejects the impossible, not the alarming.
      `sleepDurationHours`' merged median rose 5.62 → 5.85. **Oura's own
      median (4.94 vs Apple's 6.86) stayed low for a different reason** — the
      split-night averaging found and fixed the same day, see below.
- [x] **The midnight-crossing half, seen from data 2026-08-02.** The
      `SleepNights` rewrite held — nights where both sources report agree
      exactly in the model-internals nights table. The **0.01 h and 2% floors
      persisted**, but the fresh per-source split shows both live on the
      *Oura* rows, not Apple's — a 30-second type-`sleep` record (`oura.sleep.
      total_sleep_duration` min = 30 s), which is the split-night class below,
      not a HealthKit keying error. Clause outcome: median rose, floors traced
      to a different cause and handed to the item that owns it.
- [ ] **The split-night fix, proved from the next export** (`8155740`,
      2026-08-02 — the third cause of "7.5 h reported as 4 h"; found by the
      first model-internals export). Oura files a broken night as several
      same-`day` records and the parser emitted each, so the day bucket
      *averaged* them: four nights read at half of Apple's figure (07-31: 4.3
      vs 8.7 h). `parseSleep` now sums a night's periods. After a refresh (or
      Rebuild), re-export model internals: **the four nights (07-31, 07-29,
      07-20, 07-11) should agree across sources**, Oura's duration median
      should rise from **4.94 h**, and the 0.01 h duration / 2% efficiency
      floors should go — a lone 30-second `sleep` record on a day with a real
      night now sums into it rather than standing beside it.

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
- [x] **On the phone, the sleep fix proved from data — done 2026-08-02.** The
      user ran Rebuild and exported: median rose (5.62 → 5.85 merged), the 119
      is Oura's own (settled as real data), and the surviving 0.01 h / 2%
      floors were traced to Oura split-night records — the successor item
      above owns proving that fix.
- [ ] **On the phone, the Body Composition card after the hatch change**
      (`df5140a`). `ImagePaint` inside a Swift Charts `AreaMark` compiles, but
      whether Charts tiles it as SwiftUI does is device-only. If the chart's water
      region renders flat or oddly scaled while the bar looks right, that is the
      cause, and the fix is to draw the chart's hatch as a clipped overlay.

## Next

### AI as part of the analysis and the score — user direction, 2026-08-02

The user's words: *"I just want to use AI to be part of the analysis and the
ultimate score."* The agreed shape (proposed and accepted in the
screenshot-review session) is the **graded second opinion**, on the Blood
Pressure estimator's precedent — the app's existing pattern for an unvalidated
number living honestly beside a validated one:

1. **Phase 1 — the AI read, beside the dial.** The on-device model
   (FoundationModels, same as the Today summary) receives the same inputs a
   card's own model reads and produces its own 0–100 with a one-line rationale.
   Displayed as a clearly-labelled second opinion on the card — never blended.
   Every read is stored with the day's inputs.
2. **Phase 2 — grade it.** The same mechanism the BP estimator uses against
   cuff readings: score each AI read against the deterministic score, the
   user's "Was this accurate?" feedback, and (where one exists) next-day
   outcomes. The card shows the AI read's measured accuracy the way the BP
   card shows "out by 13 mmHg on average".
3. **Phase 3 — a share, once earned.** Only after the grading shows
   calibration does the AI read take a bounded share of the ultimate score
   (through `ScoreBlend`, as its own labelled row in "How this is weighted" —
   "AI assessment · graded ±N over M days"). The share is a constant in one
   place, like `SupportingSignal.collectiveShare`.

Constraints that make this compatible with the app's honesty rules: the AI
term must be **stored, not recomputed** (replay reads the stored reads, so
score history stays reproducible); a day with no stored read blends without
one; and the weighting row always states the basis. Not started — next
session's candidate.

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
- [x] **Why Oura's API serves only ~4–6 months of history** against years of
      ring data mirrored through Apple Health — **answered, and the answer is
      "not ours"**. No `next_token`, byte counts match record counts, so it is
      not client-side truncation; and it is not our request window either —
      `OAuthIntegration.sync()` asks for 730 days unconditionally, while the
      export confirms Oura returns 2026-03-16 onward against Apple Health's
      2024-08. The limit is Oura's. **Closed 2026-08-03 as investigated rather
      than as built**: it stayed open as a question for two sessions after it
      had been answered, which is a different thing from an open item. Apple
      Health remains the long-history source and the merge already prefers
      whichever source has the data.
- [ ] Hume Band direct API (today flows in via Apple Health only).
- [ ] Ultrahuman, Garmin, Fitbit — drop in via `HealthIntegration` protocol.

### The master add button (user request, 2026-08-02)
- [x] **The menu is built, and it is generated rather than hand-listed.**
      `InputKind` (InsightKit) is the app-wide list of every way in;
      `AddInputMenu` is the Today `+`, `AddDataView` is Settings ▸ Add or
      update data, and `InputSheet` is the one switch saying what each opens.
      Nine inputs: your details, cuff reading, substance, medication, dose,
      side effect, blood-test photo, shared file, your build. See
      `docs/architecture.md` ▸ "The structural invariants" and the
      `add-data-or-input` skill.
- [x] **A card must declare what it takes.** `ContributionRoute.inputKinds`
      (plural) maps a card's routes onto the master list, and
      `InputKind.cardRequirement` says whether an input must be on a card and
      whether a never-used one earns a dismissible prompt. Three checks
      enforce it — `InputKindTests`, a `verify.sh` lint on `…Sheet` views the
      master list cannot open, and `SuggestionEngine.unusedInputs`.
- [x] **The `+` is on all three tabs** (2026-08-03). Insights and Data had no
      add affordance at all, so the reader who noticed something missing while
      looking at what the app knows had to go back a tab to add it.
      **`View.addInputToolbar(_:)` in `AddDataView.swift` is the one shared
      component** — the toolbar item, the menu and every sheet it can open, in
      one modifier — and Today now uses it too rather than keeping the copy it
      had. The menu's *contents* already came from `InputKind`; this makes its
      *placement* one decision as well, which is what makes the remaining
      judgement call cheap: **toolbar item versus floating button is still
      device-only and unsettled**, and it is now one edit rather than three.
- [ ] **Camera-based input (AI + LiDAR) is still the open half** — test
      results beyond the shipped blood-test photo, body-composition scans,
      food for nutrition reporting.
      Scoping notes for the open half:
      - **Existing pieces it unifies**: blood-test photo import (shipped:
        on-device OCR → confirmed grounding values), the VisionKit live
        scanner (open, below), Foundation Models lab-analyte extraction
        (open, below), the LiDAR body scan (roadmap note below — ARKit,
        Pro-only, un-exercisable from a sandbox), and Body Composition's
        deferred "view & add" scan entry (gap 10 in `docs/card-sections.md`),
        which becomes a route in this menu rather than its own build.
      - **Food/nutrition is the genuinely new territory**: no `MetricType`
        exists for any dietary quantity, diet is the one absent LE8
        component (see `activeContext.md` ▸ the Life's Essential 8 note),
        and camera-based food recognition plus quantity estimation is an
        accuracy claim that needs the same honesty framework as the BP
        estimator — provenance, confidence, and its own metric rather than
        merging into anything. Nutrition metrics feed no card yet; per
        "a metric with no reader is invisible", the first food build should
        include at least one reader (Energy's intake side is the natural
        candidate).
      - **Camera + AI capture is device-only** end to end (VisionKit, ARKit,
        FoundationModels) — CI compiles it, only the phone can exercise it.
        Build the menu and manual routes first from the sandbox; land the
        capture routes in device-verifiable slices.

### Unstructured data
- [x] **Live document scanner** (VisionKit), 2026-08-03. `DocumentCameraView`
      wraps `VNDocumentCameraViewController` — the scanner Notes uses, so edge
      detection and perspective correction come from the system rather than
      from us — and `ImportLabView` leads with it, keeping the library picker
      as the second route. **It reads every page and keeps the first value
      found per kind**: a pathology report runs to several sheets and the panel
      this app reads is rarely on the first, so a one-page reader would make a
      two-page report look unreadable. `NSCameraUsageDescription` went into
      `Support/Info.plist` in the same commit — without it the camera does not
      prompt, it terminates the app. Gated on
      `VNDocumentCameraViewController.isSupported`, so a device without a
      camera sees the picker alone rather than a button that presents nothing.
      **Device-only to exercise**: CI compiles it, and nothing about a camera
      can be checked from a sandbox.
- [ ] Foundation Models structured extraction for arbitrary lab analytes.
- [ ] ECG photo/PDF import with metadata (no automated interpretation — that's
      a regulated medical-device claim, out of scope by design).

### Body scanner — the engine, the section and the data (2026-08-03)

- [x] **Seven new `MetricType`s** for the sites worth trending, with
      `referenceRange` nil and the reason stated (the published waist thresholds
      are sex- and ethnicity-specific; that switch has no sex).
- [x] **`BodyScan`** storing `(site, side, value)` so re-parsing survives a
      schema change, with `BodyScanRecord` keeping it as encoded JSON.
- [x] **`BodyScanPolicy`** — *what is used* and *what is saved*, separately,
      `retained ⊆ captured` normalised.
- [x] **`ScanComparability`** — conditions per scan, comparability verdicts, and
      a repeatability band below which a change is not a change.
- [x] **`BodyMeasurementReconciliation`** — ranked by method, authority expiring
      at 90 days, disagreements surfaced rather than resolved.
- [x] **`BodySymmetry`** and **`PostureAssessment`**, both silent below two
      floors, tested from synthetic skeletons.
- [x] **`BodyModelParameters`** and **"Your body over time"** — the body model,
      morphing between measurements and projecting forward, nested in Body
      Composition's first bespoke slot with the somatotype beneath it.
- [x] **`DataDomain.bodyScans`**, `BodyScanDataView`, and the export key.
- [x] **The tape input on all four surfaces**, and **both dead routes live** —
      `BuildAssessmentModel` and `SomatotypeModel` receive real dimensions for
      the first time since they shipped.
- [x] **HealthKit `waistCircumference` read**, so Apple Health alone can put the
      card on the RFM route.
- [x] **Settings ▸ Body scans** — the two-matrix screen (2026-08-03).
      `BodyScanSettingsView` under Settings ▸ Privacy, where it belongs because
      the second matrix is a retention choice. Both bindings write a whole
      `BodyScanPolicy` back rather than flipping a flag, so `retained ⊆
      captured` stays enforced in the initialiser that already tests it — a keep
      row for something not being collected is disabled and says so, and
      switching a capture off visibly takes its retention with it. The derived
      half is said out loud too: `canMeasure` false is a warning, `isReparseable`
      false says a future version could not re-measure these scans.
      `AppModel.bodyScanPolicy` is a **stored** property over `UserDefaults` —
      defaults are as invisible to SwiftUI observation as SwiftData is, and
      toggles that don't move when tapped is that same defect one layer over.
      **The screen says the capture does not exist yet**, because a settings
      page that reads as though it is doing something today would be the quiet
      overclaim this app's rules exist to stop.
- [x] **The 30-day reminder** (2026-08-03). `SuggestionEngine.bodyScanDue`
      calls `BodyScanCadence` and takes its wording from it, so the reminder
      and the Settings row cannot disagree about how overdue a scan is.
      Three decisions, all tested (`BodyScanSuggestionTests`, 7 tests):
      **never-scanned belongs to `unusedInputs`**, which already prompts for
      `.bodyMeasurements` — two rows about one missing measurement is the
      duplication the ranking exists to avoid, so this clause needs a last scan
      to say anything. **The id carries the state** (`body-scan-overdue`), which
      is the opposite of `unlocks`' one-id-per-kind rule and deliberately so: a
      dismissal lasts thirty days and the interval *is* thirty days, so a shared
      id would let a wave-away at day 25 silence the whole next cycle.
      **Strength sits below a grounding gap that costs a card its score** and
      climbs with the size of the hole, stopping at one interval late.
- [ ] **The ARKit capture and guided flow** — the largest remaining piece, and
      device-only. See `activeContext.md` for the design.
- [ ] **A 3D mesh instead of the silhouette.** `BodySilhouetteView.outline` is
      static and pure so a mesh can replace it without touching anything above.

### Three insight cards the user asked for (2026-08-03)

All three are the **Substance Impact shape**: something the reader does, dated,
measured against the vitals around it. That card is already a first-class
`InsightModel` with before/after windows and an exponential load kernel, so the
machinery exists — what each of these needs is a *source of events*.

- [ ] **Travel drain.** The user travels internationally and often, and it is
      draining. Events would come from the calendar (a connector this app does
      not have yet) or from a timezone/location change Apple Health can already
      witness — **a shift in timezone is a strong, free travel signal**, and
      HealthKit samples carry timezone metadata. Worth reading before building
      a calendar integration for it.
- [ ] **Stress card.** The one of the three with sensed inputs already present:
      HRV, resting heart rate, respiratory rate and sleep are all in `samples`,
      and `HealthWatch` already does multi-signal convergence. The risk is
      overlap — Readiness absorbed the vitals scan and the early warning for
      exactly this reason — so the honest version needs to answer a question
      Readiness does not, most likely *sustained* load rather than today.
- [ ] **Work impact.** Same shape as travel, same missing piece: it needs to
      know when the reader was working. Calendar again, or screen time by
      category if Apple ever exposes it. Probably drives stress rather than
      standing beside it, so build the stress card first and let work be a
      contributor to it rather than a fourth dial.

**The common blocker is an event source, not modelling.** A calendar connector
would unlock two of the three, and the timezone signal would unlock travel
without any new permission at all.

### Metabolism speed — the card the user asked for (2026-08-03)

*"I'm always wanting to know how fast my metabolism is at the moment, and how
it's sped up by Mounjaro or similar medications, and how it's helping me lose
weight — or making it harder."*

**Designed in `docs/planned-modules.md` ▸ module 5. Read that before building —
it carries the algorithm, the failure mode and the two things this card must
never say.** The short version: the back-calculated TDEE service
(`EnergyBalanceModel`) was designed in module 1 and blocked on dietary energy,
which **stopped being a blocker on 2026-08-03**. Everything below is now
buildable in the sandbox.

- [x] **`EnergyBalanceModel` — the back-calculation** (2026-08-03), and it
      is fitted to the **raw** weigh-ins rather than the smoothed ones. That is
      a correction to this item's own wording: `CompositionVelocity`'s EWMA lags
      a real trend by about nine days at α = 0.10, so over four weeks a third of
      the series is still catching up and the fitted slope under-reads — 0.36
      kg/week on a body losing exactly 0.5. Multiplied by 7,700 that is **150
      kcal a day of expenditure gone missing, which the card would have
      reported as metabolic suppression that never happened.** Smoothing is
      right for a score and wrong for this arithmetic; least squares on the raw
      series is unbiased for a linear trend with symmetric noise, which is what
      water weight is.
- [x] **The speed ratio — observed ÷ predicted** (2026-08-03). Katch-McArdle
      where a scale reports lean mass (and it then needs no age or sex at all),
      Mifflin-St Jeor otherwise — with the sex constant split rather than
      guessed when sex is unknown, so the error is bounded at ±83 kcal instead
      of landing 166 out for half of readers. Plus measured active energy and a
      10% thermic effect. **The score rewards nothing above 100%**: running
      "fast" is usually an incomplete diary, and paying the reader for it would
      be paying them to log less. Original wording follows.
      **The speed ratio — observed ÷ predicted.** A rate in kcal/day does not
      answer "is my metabolism fast"; a comparison does. Predicted is
      Katch-McArdle where lean mass is known (this app has it from Withings and
      Shotsy), Mifflin-St Jeor otherwise, plus *measured* active energy and a
      10% thermic effect — never a lifestyle multiplier off a dropdown.
- [x] **The logging gate** (2026-08-03) — and it measures completeness over
      **the reader's own logging window**, not a nominal 28 days: somebody who
      started a fortnight ago and has logged every day since is logging
      perfectly, and both terms of the subtraction are then taken over that same
      stretch, which they have to be for the arithmetic to mean anything. Below
      80% the card withholds the number and says why. Above 110% the first
      driver line names the food log. Original wording follows.
      **The logging gate, which is the whole card's honesty.** The
      back-calculation charges every logging error to metabolism, so
      under-reporting reads as a fast metabolism — and under-reporting is the
      normal finding, routinely 20–30%. Below ~80% of days logged the card says
      "can't judge" (the `ActivityDoseModel` floor's shape), and a ratio above
      ~110% names the food log first, before any metabolic reading.
- [ ] **The medication panel — still open.** The card charts
      `activeMedicationLevel` and states on the row that the evidence is about
      intake rather than expenditure, but the before/after contrast itself is
      not built: it needs a logged stretch on each side of the first dose, and
      the honest version reports the two deltas (what intake did, what
      expenditure did) rather than one number. Original scope follows.
      **The medication panel.** Intake and expenditure are both dated series and
      `activeMedicationLevel` is a third, so this is Substance Impact's
      before/after shape with a different pair of quantities. The expected
      honest finding is *"the drug moved what you eat, not what you burn"*.
      **"Mounjaro speeds up your metabolism" is a claim this card must never
      make** — no such effect is established, and a rising ratio during
      treatment is more likely a food log that got worse as appetite fell. What
      it *can* say, and what nothing else in the app can see: observed against
      predicted-for-your-current-size, tracked across the treatment period —
      which is what "my metabolism has slowed" actually means.
**The trap, which is a rule rather than a task:** do not promote Apple's
`basalEnergyBurned` as "your metabolism". It is a formula the phone evaluated
from height, weight, age and sex — the modelled-dressed-as-measured failure
this app has rules against. A labelled comparator at most.

- [ ] **Composition-aware kcal/kg, later.** Fat is ~9,400 kcal/kg and lean
      ~1,800 against the blanket 7,700, and on a GLP-1 the lean fraction of loss
      is not negligible. Worth a few per cent, once the logging gate is being
      met.

### Nutrition — capture everything, then the card (2026-08-03)

*"A nutrition card in future, to capture all nutrition possible from all
sources."* Designed in `docs/planned-modules.md` ▸ module 6.

- [x] **The macros are promoted** (2026-08-03) — ten of them, not six:
      protein, carbohydrates, total fat, saturated fat, sugar, fibre, sodium,
      potassium, water and caffeine. Sugar, saturated fat, sodium and potassium
      joined the list because the published figures the user approved name them.
      Original scope for the record: protein, carbohydrates, total fat and fibre
      as `MetricType`s in grams, plus water and caffeine. Apple Health already
      writes ~25 dietary identifiers into the raw pile and Shotsy carries four
      with the conversions worked out (`ShotsyUnit.pendingNutritionKinds`) — so
      most of this is promotion, not plumbing. The `.nutrition` family and the
      Nutrition data-tab group arrived with dietary energy on 2026-08-03 and the
      macros inherit both. Everything past those six stays raw and visible: a
      metric no card consults is a chart nobody asked for.
- [x] **The card ships** (2026-08-03). `NutritionInsight` / `NutritionModel`,
      `InsightID.nutrition`, on the Insights tab. Eight scored terms, each
      naming the body whose figure it uses — protein per kg (WHO/FAO 0.83 safe
      intake, 1.2–1.6 g/kg for holding lean mass in rapid loss, **a floor at the
      user's request**), fibre (EFSA/SACN), saturated fat and total fat as
      percentages of energy (WHO), sodium and potassium (WHO), water (EFSA,
      sex-specific and discounted to what drinks carry), caffeine (EFSA).
      Three rows are charted and unscored with the reason on each: calories (no
      published figure says what one person should eat), carbohydrates (the
      guidance is about which, not how many grams), and **sugar — because
      HealthKit reports total sugars while WHO's under-10% figure limits *free*
      sugars, so scoring one against the other would mark a reader down for
      eating fruit.** Completeness leads the card and is notable below 80%.
      11 tests, including a 4,000-point sweep of all eight curves.
- [ ] **The relationships from the reader's own history** — protein against
      lean-mass retention while weight falls, caffeine against sleep onset. The
      card scores against published figures today and says nothing yet about
      what the reader's own data shows, which is this app's strongest claim
      elsewhere. Split out rather than left inside the item above, because a
      multi-clause `[x]` hiding an unfinished clause is how six of them once
      survived a "closed" list.
- [x] **One completeness figure, read from one place** (2026-08-03).
      `NutritionLogging` owns logged-days, the window and the 80% threshold;
      both cards read it.
- [x] **Decided 2026-08-03 — published reference bands are wanted.** The
      user's words: *"I am happy with all dietary guidelines, why wouldn't I
      be?"* So a nutrition row may carry a band from a named body with its
      provenance stated, exactly as `exerciseMinutes` carries WHO's 150–300
      minutes. **What this licenses is a published band, not an app-invented
      target** — the rule that survives is the one about provenance, not a
      refusal.
- [x] **Done 2026-08-03 — and the `Band` type made two more of them fit than
      expected.** Its bounds are optional, so a floor with no ceiling ("at least
      25 g of fibre") draws honestly: fibre, potassium, sodium and caffeine all
      carry real bands with their sources on the caption. The finding worth
      keeping: a floor is expressible, so check the type before concluding a
      published figure has no home. Original wording:
      **Fixed bands go in `referenceRange`; relative ones cannot.** Only four of
      the published figures are absolute and can live on the metric: fibre
      (EFSA 25 g, SACN 30 g), sodium (WHO < 2,000 mg), potassium (WHO ≥ 3,510
      mg) and caffeine (EFSA ≤ 400 mg habitual). Protein is **per kilogram**
      (WHO/FAO 0.83 g/kg safe intake; 1.2–1.6 g/kg is the range cited for
      preserving lean mass during rapid loss, which is this reader's case),
      free sugars and saturated fat are **percentages of energy** (WHO < 10%
      each), and total water is **sex-specific** (EFSA 2.5 L men, 2.0 L women,
      food included). Those four belong in the card's own table, the way
      `HeartHealthScore` holds the age-and-sex VO₂max tables and
      `MetricType.vo2Max` returns nil.
- [x] **Done 2026-08-03 — energy keeps no band, and the nutrition card says
      why on the row.** Original wording: **Energy keeps no band on its chart,
      and that is not a refusal of guidance.** Published energy requirements are a *personal calculation*
      rather than a population band, and a deliberate deficit is the entire
      point for a reader on a GLP-1 — a band would mark intentional loss as
      out-of-range. The guidance still appears, as the metabolism card's
      predicted line with its equation named, which is the honest place for it.
      Say the word if a band on the chart is wanted anyway.
- [ ] **Meal photo → nutrition** is the camera half, already on the roadmap
      under camera-based input. It is the only one of the three sources that
      needs a model rather than a mapping, and the accuracy claim needs the same
      honesty framework as the BP estimator.

### Every domain of health — the direction, and what is already arriving (2026-08-03)

The user's scope, quoted at the top of this file: the app has to reach every
domain of health and wellbeing. The useful thing about that ambition here is
how much of it is **already in the export and unread** — `HealthKitService`
scrapes ~50 quantity types and ~28 category types into the raw "other data"
bucket, and a domain below is mostly a promotion plus a reader, not new
plumbing. Ordered by how much is already arriving.

- [x] **Symptoms are data the app can see** (2026-08-04, session 25).
      `SymptomType` / `SymptomSeverity` / `SymptomEvent` in InsightKit,
      `DataDomain.symptoms` with both Data-tab switch arms, a read-only detail
      page and an export key. **Promotion, not ingestion** — the fourteen
      categories were already arriving in the raw catalogue via
      `HealthKitService.otherCategoryIdentifiers`, so this cost no permission,
      connector or capture. Promotion *reads* rather than moves, so the raw rows
      are untouched and a bug here cannot lose data that was already exported.
      Three decisions recorded in the source: a domain rather than a metric (a
      symptom is an event, absent more often than present, and as a series a
      week without a headache would be missing data rather than a week of not
      having one); its own domain rather than folded into side effects (a side
      effect is a symptom *attributed to a medication*, and merging asserts an
      attribution nobody made); and **`notPresent` is data** — Apple's scale is
      kept unrescaled, absences are stored and rendered dimmer, and never
      counted as occurrences.
      - [ ] **Reconcile the symptom log against the hand-entered side effects.**
            Still open, and it is the half that becomes a card: what the reader
            logged by hand versus what Health already knew, in the same shape
            `BodyMeasurementReconciliation` uses. `isCommonGLP1Effect` and
            `isInfectionLike` are built and disjoint, ready for it.
> ⚠️ **CORRECTED 2026-08-05, and the correction is the important part.** This
> list used to say all eight were "arriving", "scraped" and "a promotion plus a
> reader, not new plumbing". Measured against the reader's own export — 158 raw
> identifiers, 320,913 rows — **six of the eight have zero rows. Not thin.
> Absent.** `HealthKitService.swift` requests them and nothing has ever been
> written, which is a permission or a device fact and not a build task.
>
> The failure mode is worth naming because CLAUDE.md tells the next session to
> trust this file without re-deriving it: *"arriving" was inferred from the read
> request, never checked against a row count.* Anything on this list now carries
> its measured coverage, and a domain with no measurement is marked as
> unmeasured rather than assumed present.

- [ ] **Hearing — the one with real data.** `HeadphoneAudioExposure` is
      **13,768 rows over 467 days, 56 of the last 90, 194 of the last 365**.
      It has a published dose in the same form as the exercise one — WHO/NIOSH's
      85 dB over 40 hours a week, halving the allowance per 3 dB — so it can be
      scored honestly rather than described.
      ⚠️ **It cannot be a *total* sound-exposure card.** `EnvironmentalAudio`
      exists on 14 of the last 90 days, so summing the two would invent the
      quiet hours; and the exposure *events* are effectively absent (40 days
      ever, 0 in the last 90, the headphone event fired once in 2023). Frame it
      as the headphone dose, and state the hours it could not see.
      ◐ **The substrate shipped 2026-08-06 (backlog §B5 #33):**
      `environmentalSoundDose` and `headphoneSoundDose` are canonical daily
      metrics now — each the day's equal-energy LEQ over its own sensor's
      measured hours, derived by `SoundDoseModel` from the raw dBA samples on
      the ingest path, `MetricSource.calculated`, Data tab ▸ Hearing, never
      summed. Nothing scores them yet; **what remains here is the card.**
- [ ] ~~**Daylight and UV.**~~ **Zero rows.** `TimeInDaylight` and `UVExposure`
      are not among the 158 identifiers at all. The circadian argument still
      holds and is still good, but this is a data-collection problem — find out
      why the phone writes neither — and not a card to build.
- [ ] ~~**Respiratory function.**~~ **Zero rows.** No FVC, no FEV1, no peak
      flow, no inhaler usage. The GLI-2012 reference equations are real and the
      card would be good; nothing has ever written a spirometry value here, and
      nothing will until a device or a clinic does.
- [ ] ~~**Mind.**~~ **Zero rows** for both mindful minutes and mood changes.
      The posture question stands and still needs deciding before any build.
- [ ] **Cycle and reproductive health — one real asset, and it is not the
      cycle.** `MenstrualFlow` and `SexualActivity` are **zero rows**.
      `BasalBodyTemperature` is **136 rows over 124 days, 80 of the last 90** —
      written deliberately via a Shortcut and read by nothing.
      **Use it as an independent temperature channel for the symptom radar**,
      which is worth far more than a cycle card: it survives a night the ring
      was off, which is exactly the night the radar currently goes blind.
      ⚠️ It must go through the placeholder filter first — 35 of the 136 records
      are exact zeros meaning missing (`RawMetricSample.swift:113`).
      Anything contraceptive needs FDA clearance and is out of scope entirely.
- [ ] ~~**Falls and balance.**~~ `NumberOfTimesFallen` is **zero rows** and the
      walking-steadiness *event* likewise. `walkingSteadiness` itself is real
      (105 days) and is now read by the gait card below.
- [ ] ~~**Oral health.**~~ **Zero rows.** Toothbrushing has never been written.
- [x] **Movement and gait — built 2026-08-05, and it was hiding in plain
      sight.** `walkingSpeed`, `walkingStepLength` and
      `walkingDoubleSupportPercentage` were scraped into the raw pile from the
      beginning and read by nothing, while being **the densest signal in the
      entire export: 1,093 days each, 91 of the last 90, 366 of the last 365** —
      from the iPhone alone, no wearable, no charging, no compliance gap.
      Promoted to `MetricType` and read by `GaitInsight`, which decomposes a
      speed change into step length versus cadence.

**What the list actually has in common — revised.** Two of the eight are
buildable from data that exists (Hearing, and the basal-temperature half of
Cycle). Five are **data-collection problems wearing a build's clothing**. One
was never on the list at all and turned out to be the best of them.

The rule that falls out, and it is the general one: **before writing "already
arriving" about a data source, count its rows in the last 90 days.** A read
request in `HealthKitService` proves the app asked, and nothing more.

### Symptom radar — the sickness early warning (user request, 2026-08-03)

*"I want a symptom radar / sickness early warning like Oura, as its own card."*
**Researched against Oura, Apple, Whoop, Garmin, Samsung and Fitbit, and
designed in `docs/planned-modules.md` ▸ module 7. Read that first** — it carries
the competitive table, the validation figure that shapes the whole card, and the
four things this app can do that none of the products can.

**The engine already exists.** `HealthWatchModel` has been shipping since
2026-08-02: seven weighted signals, a 3-day recent window against a 21-day
reference with a 4-day gap between them, z-scored, counted only when they move
the way illness pushes them. It is within touching distance of Oura's design and
is currently a section inside Readiness. What is missing is the card.

- [x] **The card itself** — `InsightID.symptomRadar`, daily, rendering
      `HealthWatchModel` directly. Three states on Oura's precedent (nothing
      stirring / some signs / strong signs) and a radar of the seven signals
      showing which moved and how far. Which signals moved is more actionable
      than a score.
- [x] **"No signs" must not read as reassurance.** The best published
      prospective validation of this approach — sleep resting HR, respiratory
      rate and HRV over 470 health-care workers — is **43% sensitivity at 95%
      specificity** (JMIR Formative Research, 2024). A model of this kind misses
      more than half of real infections. Every competitor puts a green tick in
      the quiet state; this card has to say what quiet actually means, and that
      is the most important sentence on it.
- [x] **Name the confounder from data the app already holds.** Apple lists
      *possible* causes generically. This app has the substance log, the GLP-1
      dose schedule and screen time, so it can say "you logged alcohol on two of
      these three nights" instead. The universal substance shading (2026-08-03)
      is the visual half of this and is already in.
- [x] **Never call a dose reaction an infection.** Nausea and fatigue after a
      GLP-1 dose are the drug working. The app knows the dose dates and the
      modelled level; no competitor does. Flagging an infection on titration day
      is the kind of wrong a reader remembers.
- [x] **Track the episode, not just the onset** — start, peak, and each signal's
      return to baseline ("day 3, two of four signals back inside your range").
      The standing criticism of Whoop's Health Monitor is that it flags a bug
      and then goes quiet.
- [x] **Grade itself against the reader's own symptom tags.** HealthKit writes
      fifteen symptom categories into this app's raw pile — nausea, fatigue,
      headache, fever, coughing — and nothing reads them. They are both the
      training signal and the honesty feature: the card can report its own hit
      rate, the way the blood-pressure estimator reports "out by 13 mmHg on
      average". **Build the symptoms domain first** (see "Every domain of
      health"); an early-warning card that cannot say how often it is right is
      the one shape this app should not ship.

### Cycle tracking — the fifth tab (user request, 2026-08-03)

*"A major feature that gets its own tab. Huge amount of work — essentially
replicate an app like Flo, but use all the data we have to be even better."*

**Designed in `docs/planned-modules.md` ▸ module 8. Read it before starting** —
it carries the competitive table (Flo, Apple, Oura, Natural Cycles, Whoop), the
regulated line this app must not cross, and the four things no period tracker
can do because they need the rest of this app.

Two things to know before any of it: **the app's other cards are wrong for a
cycling reader today** — a luteal phase raises resting heart rate and
respiratory rate and lowers HRV, which is precisely what `HealthWatchModel`
reads as illness — and **no contraceptive claim is ever available to this app**,
because that is what makes Natural Cycles a regulated Class II device.

- [ ] **Phase 1 — the log and the tab.** `DataDomain.cycles`, a `CycleEvent`
      model (period start/end, flow, symptoms), the fifth tab in `RootView`, and
      `InputKind.cycleLog` on all four input surfaces. HealthKit already writes
      `menstrualFlow`, `basalBodyTemperature` and `sexualActivity` into the raw
      pile — read them rather than asking for a history the phone already has.
- [ ] **Phase 2 — prediction from the calendar**, as a *range* with its own
      spread ("your cycles vary by ±4 days"), never a single confident date. A
      confident date is the first dishonest thing every tracker does.
- [ ] **Phase 3 — the physiology, which is the point.** `CyclePhaseModel`: the
      biphasic temperature shift for **retrospective** ovulation on Apple's
      precedent, corroborated by resting heart rate (+2–7 bpm mid-luteal), HRV
      (−12% in one SDNN study) and respiratory rate. Confirmed versus predicted
      marked on every phase boundary; an anovulatory cycle reported as
      *unconfirmed* rather than assumed.
- [ ] **Phase 4 — phase-aware baselines everywhere else.** Readiness, Sleep and
      the symptom radar all compare against a baseline that the cycle moves. Fix
      this before the radar ships to a cycling reader, or it will call a luteal
      phase an infection.
- [ ] **Phase 4b — cycle × metabolism and × energy availability.** Intake and
      resting expenditure both move across the cycle, and the metabolism card
      exists now; rapid weight loss and low energy availability disturb cycles,
      and the app holds intake, expenditure, weight velocity and the cycle in
      one place. Nobody else has both halves.
- [ ] **Phase 5 — the content layer.** Flo's real product is education tied to
      phase. A writing job more than an engineering one: scope it separately,
      because without it the tab is a chart and with somebody else's copy it is
      a liability.
- [ ] **Decision — does the tab draw a fertile window at all?** Retrospective
      ovulation is safe; a forward-looking fertile window is where the regulated
      line sits. Recommendation: not in Phase 3, and only ever with an explicit
      not-for-contraception statement.
- [ ] **Decision — surface the tirzepatide/oral-contraceptive labelling?** The
      Mounjaro label advises a non-oral or added barrier method for 4 weeks
      after initiation and 4 weeks after each dose escalation, because delayed
      gastric emptying may reduce oral contraceptive efficacy; non-oral methods
      are unaffected. This app knows the dose dates and Flo cannot. It is also
      the most medical thing the app would ever say.
- [ ] **Decision — who is the tab for?** Keyed to `biologicalSex`, to an
      explicit setting, or to whether any cycle data exists. The third is the
      most honest and the least presumptuous.
- [ ] **Settle the privacy posture first.** This repository is public
      (`docs/privacy-and-ip.md`) and cycle data is the most sensitive category
      the app will ever hold. **Flo was found by the FTC to have shared cycle
      and pregnancy events with Facebook and Google while promising privacy**
      (settled 2021) — this app's on-device-only posture is the strongest claim
      it has in this category, and it belongs on the tab rather than in
      Settings.

### Food and supplement capture — scanner, AI, and vitamins (user request, 2026-08-03)

*"Integration with MyFitnessPal, and also build a scanner into our app… leverage
onboard AI to estimate food and drinks… but also support something they don't:
vitamins! I had real trouble tracking supplements and all the unique
ingredients."*

**Designed in `docs/planned-modules.md` ▸ module 9.** Four asks, and the order
below is deliberate: one of them may already be done, one is closed with an open
window beside it, and the last is the only one whose accuracy is a research
problem.

- [ ] **First, check MyFitnessPal already works.** Its API is **private,
      partner-only, and closed to new requests** — but MFP writes nutrition to
      Apple Health, and this app has read eleven nutrition metrics out of
      HealthKit since 2026-08-03. **A reader logging in MFP today probably
      already sees it here.** Five minutes on the phone, no code. If it holds,
      the whole "integration" is one Settings row saying so. If it does not, MFP
      has a CSV export and this app already has a file-import route.
- [ ] **The barcode scanner, with the lookup on-device.** VisionKit's
      `DataScannerViewController` reads the barcode; the database is a *privacy*
      decision first: a lookup against a third-party API sends "what I am about
      to eat" to a stranger, which breaks the app's standing guarantee.
      **Open Food Facts publishes downloadable dumps** (ODbL, commercial use
      allowed) — ship or fetch an extract once and look up locally, with USDA
      FoodData Central as the second source for generic foods. A cache miss may
      offer an online lookup as an explicit per-scan choice.
- [ ] **Supplements — the ingredient problem, which is the real ask.** Every
      tracker treats a supplement as a food with a calorie count, which is
      exactly backwards: the calories are irrelevant and the ingredient list is
      the point. **NIH's Dietary Supplement Label Database carries 200,000+ US
      labels with every ingredient, its form and its amount, behind a free
      public API.** Model a supplement as a **regimen** — the app already has
      `MedicationRegimen`, doses, side effects and a decay curve — not as a
      food.
- [ ] **Sum the ingredients across the stack, against published upper limits.**
      The feature nobody ships. A multivitamin, a greens powder and a magnesium
      blend overlap constantly, and no tracker adds them up. *"Your three
      products give you 41 mg of zinc a day; the upper limit is 40"* is a
      sentence this app can produce and MyFitnessPal cannot. ULs from EFSA and
      IOM — for a supplement the upper limit matters far more than the RDA, and
      published bands are already the agreed shape.
- [x] **Promote the nine micronutrients — done 2026-08-05 (`342f00d`), and it
      was eleven.** The two unsaturated-fat splits went with them, since they sit
      in the same raw lane for the same reason. The clause "promote them together
      with the supplement work, not before" was **overtaken by a different
      argument**: raw groups carry no category, so the Data tab's Nutrition
      section is generated from `MetricType` alone and 686 rows of the reader's
      own record were filing under "Other data" at the bottom of the tab. Being
      unscored was the intent; being unfindable was not. **Still unscored by any
      card** — that half genuinely does wait for the supplement work, and it is
      where the published bands land.
- [ ] **The AI estimate, last.** Published accuracy decides the design:
      identification runs **68–86% in the real world**, and **portion estimation
      as low as 39%, 15–25% error from a 2D photo and 5–10% with depth**. So
      the flow is *photo → candidates → the reader confirms → portion → lookup*,
      never photo → a number; and **this app has depth on the roadmap already**
      (LiDAR, module 3), where a plate is a far easier subject than a torso. The
      estimate carries its own error band and is graded against hand-logged
      days, exactly as the blood-pressure estimator is — a photo-derived calorie
      figure must never be indistinguishable from a scanned label's.

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
