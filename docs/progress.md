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

## In progress / not yet device-verified
- [ ] **Body temperature is judged in the wrong domain — the highest-value fix
      available.** Audited and confirmed: `hardLow` (35.5) is exactly the
      reconstructor's default baseline, so *any* negative skin deviation trips it
      and tanks a worst-offender-dominant score; `hardHigh` needs +2.3 °C and can
      never fire; and both temperature rows are always present with mathematically
      identical z-scores, so the same signal is counted twice. Root cause is
      provenance loss — reconstruction writes skin values as `.bodyTemperature`.
      No existing test would catch any of it. Full detail and the fix design in
      `activeContext.md`.
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

- [ ] Cardio strain from stimulants as a first-class trend. The before/after
      analysis and the 14-day load figure already exist in
      `SubstanceResponseAnalyzer`; what's missing is a decaying daily load
      *series* to trend and chart.
- [ ] Sleep-debt and circadian consistency from bedtime variance. **Blocked on a
      new signal**: no provider currently gives us a bedtime. Apple Health and
      Oura both stamp `sleepDurationHours` at the *start of the calendar day*, so
      sleep-onset time would need its own `MetricType` (a clock-hour value, with
      circular statistics — the mean of 23:30 and 00:30 is midnight, not noon)
      plus parser work in all three providers.

### Integrations
- [ ] Explain why Oura's API serves only ~4–6 months of history against years of
      ring data mirrored through Apple Health. No `next_token`, byte counts match
      record counts, so it isn't client-side truncation. Offered, not yet taken up.
- [ ] Oura pagination (`next_token`) — logged as a warning when it appears, which
      it hasn't yet. Implement on first sighting, not before.
- [ ] Oura's `heartrate` endpoint is never called despite the scope being
      requested; direct Oura contributes no heart-rate samples.
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
      minutes, and consistency no longer stuck at 0/100.
- [x] 8. Blood pressure scores from the AHA bands (the *drift counter* half is
      still outstanding — see below).
- [x] 9. Heart & Fitness Age scores from a logistic, and both ages are charted
      over time.
- [x] 4a. Colour bands on the blood-pressure chart.
- [ ] 4b. Smoothed predicted values across data gaps. `Theme.projectedStroke`
      exists for this and is unused; charts still break the line and draw nothing.
- [ ] 4c. Reference bands on the other charts that have well-known ranges.
- [ ] 1. Gate the Today summary on a data-state diff; 30-second floor on manual
      refresh. Nothing gates it today — every app open pays a full summariser
      round-trip.
- [ ] 2. "Improve Your Health" suggestions. Greenfield — zero matches for
      `suggest` anywhere in the repo.
- [ ] 3. Grounding and renewal display. `requirementStatuses` already computes
      satisfied/stale/missing and every caller discards all but `.missing`;
      nothing renders a renewal countdown.
- [ ] 7. Substance intake: date/time prompt, an edit path (`DataStore` has no
      update), the intake window drawn on the chart, more correlated vitals, and
      a section in the Vitals tab.
- [ ] 10. QA sweep: six insights still bypass `VitalReader`; Cardiovascular Risk
      still has a four-step score function; Body Composition is an unconditional
      `score: nil`; Substance Impact isn't an `InsightModel` at all, so anything
      applied "to every insight" skips it.

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
