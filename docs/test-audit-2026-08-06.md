# InsightKit test-suite audit — 2026-08-06

**Scope.** All 139 files under `InsightKit/Tests/InsightKitTests/` (27,863 lines,
1,767 `func test`s at the audited commit), audited on seven axes: outdated
pins, weak assertions, tautologies, timezone safety, flakiness risk, coverage
holes, structure. Method: every file swept mechanically (calendars, bare
`Date()`, skip-guards, tolerances, hard-coded counts, PRNG, closed sets,
encode/decode pairs), then ~35 files read line-by-line, chosen by what the
sweeps flagged — plus the production source wherever a claim needed checking
(`WhoopResponseParser`, `SleepOnset`, `ContributionSummary`, `Feedback`).
**Nothing was edited and the suite was not run** — five branches were
concurrently adding tests, so this is a static audit; every claim below is a
`file:line` a reader can open.

The app target still has zero tests — that is backlog D5 and is not
re-litigated here. Where a finding says "nothing in the suite", it means
InsightKit, the only place a test can currently live.

---

## Fix these 15 first

Ranked by (defect probability × cost of the miss ÷ cost of the fix). 1–5 are
live gaps; 6–10 are guards that cannot fire; 11–15 are cheap hygiene with a
history behind it.

1. **`ContributionSummary.bodyMeasurements` and `.screenTime` are tested
   nowhere.** `ContributionSummaryTests.swift:223`'s hand-built `all` list
   covers seven of the nine route factories
   (`ContributionSummary.swift:51–286`); the two missing names appear in **no
   test file at all** (repo-wide grep). The three "across every route" sweeps
   (`:241` way-in, `:250` grounded-no-bar, `:256` bar-is-a-fraction) claim the
   anatomy holds everywhere and silently exclude two shipped routes — the
   CardVisibilityTests lesson exactly: a closed set populated from what existed
   when it was written. *Fix: add both to `all`, and add a companion that
   fails when a new factory is not in the list (count the static factories in
   a doc-comment contract, or switch the routes to an enum).*
2. **The Whoop sleep parser never got the 2026-08-04 timezone fix, and its
   onset output is untested.** `WhoopResponseParser.parseSleep`
   (`WhoopResponseParser.swift:89`) takes no calendar and feeds
   `SleepOnset.samples(fromSegmentStarts:)`, which defaults
   `calendar: .current` (`SleepOnset.swift:72–74`) — the same shape
   `OuraResponseParser` had before `parseSleepUTC`. The only Whoop sleep test
   (`ProviderParserPhaseBTests.swift:32–46`) asserts respiratory rate and
   duration, never `.sleepOnset`, so the TZ-dependent half is both untested
   and *untestable deterministically*. *Fix: add the forwarding
   `parseSleep(_:calendar:)` overload Oura got, a `parseSleepUTC` twin in
   `TestClock.swift`, and one onset assertion.*
3. **Two suggestion tests can skip forever in silence.**
   `SuggestionTests.swift:254` and `:278` use `XCTSkipUnless(...)` on "fixture
   failed to produce a lean/convergence". If a `HealthWatchModel` change stops
   the fixture leaning, the two tests that pin convergence-outranks-everything
   stop running and nothing says so — the ScoreAttribution 20-vs-130 trap with
   `XCTSkip` in place of `guard … continue`. *Fix: make fixture drift a
   failure, the way `SymptomRadarTests.swift:852–855` asserts "fixture
   drifted" as a precondition.*
4. **The departure-panel rule is only enforced for cards that can score on a
   five-metric fixture.** `ContributorDepartureTests.swift:27–31` sweeps every
   registered model over `GoldenDataset` (HR, RHR, rMSSD, temperature, sleep
   only) and opens `guard !contributors.isEmpty else { continue }` — so
   Fitness, Body Composition, Blood Pressure, Nutrition et al. have never had
   "every contributor is accounted for in the panel" checked, and no companion
   states which models the sweep actually examined. *Fix: run the sweep on
   `ContributorsFixture.fullCoverage` (130 days) and add the
   `testEveryRegisteredModelScoresOnTheFixture`-style companion
   (`ScoreAttributionTests.swift:839–852` is the template).*
5. **The export has no decode round-trip, anywhere.** Every
   `HealthDataExportTests` assertion is `json.contains("\"key\"")`
   (substring); `:126` is even titled "must survive the round trip" and never
   decodes. The 2026-08-05 import defect — one `decode` losing all four
   sections because `UserHealthProfile.inputs` encodes as an alternating
   key/value *array* — is precisely the shape a decode-what-you-encoded test
   in InsightKit would have caught, and the Codable types live in InsightKit
   even though the importer is app-target. The codec suites already model the
   discipline (`SampleCacheCodecTests.swift:18`, `RawCacheCodecTests.swift:20`
   — the byte-offset bug was caught only by round-trip). *Fix: one test that
   decodes `bundle().json()` back into `HealthDataExport` (add `Decodable`
   conformance if missing) and compares field-by-field.*
6. **`testMemoryAloneCannotReachStrongSigns`'s real-path half can pass
   vacuously.** `SymptomRadarTests.swift:982–988`: the through-the-real-path
   assertions sit inside `if let today, today.excess < strongSignsExcess {
   if verdict.isCarriedForward { … } }` — two conditions under which the test
   asserts nothing, with no drift guard. If the fixture stops producing a
   carried-forward day, the constant-arithmetic half (`:969–973`) still passes
   and the behavioural half evaporates. *Fix: `XCTAssertTrue` the two
   preconditions with "fixture drifted" messages.*
7. **Tolerances that cannot fail.** `NewCardTests.swift:395` pins an FFMI
   percentile as `45, accuracy: 12` — accepts 33–57, a quarter of the whole
   scale, under a comment claiming "a little under the fiftieth centile"
   (57 would satisfy the assert and refute the comment).
   `SleepQualityStagesTests.swift:115` pins "a missing breakdown should be
   neutral, not a penalty" as `bare == full, accuracy: 12` on a 0–100 score —
   a 12-point penalty passes. *Fix: assert the direction (`lessThan 50`;
   `bare >= full - ε`) plus a tight band on the computable value.*
8. **A disjunctive assertion masks its own subject.**
   `MetabolismTests.swift:113`:
   `XCTAssertTrue(result.explanation.contains("flatter") || result.drivers.isEmpty)` —
   the wording pin can rot while the unrelated `drivers.isEmpty` half keeps it
   green, and vice versa. *Fix: split into two asserts (or drop the escape
   hatch).*
9. **A self-referential comparison in CompositionVelocity.**
   `CompositionVelocityTests.swift:95`:
   `XCTAssertGreaterThan(good, good > quality ? quality : 0)` asserts, when
   `good <= quality`, only that `good > 0` — it can never fail in the
   direction it reads as testing. The next line (`good > 80`) does the real
   work. Same file `:18–26`: `falling(from:kgPerWeek:)` is **dead** (zero
   callers) and its value expression is
   `start + kgPerWeek * weeks * -1 * -1 + kgPerWeek * 0` — noise that survived
   a rewrite into `series(...)`. *Fix: replace `:95` with
   `XCTAssertGreaterThan(good, quality)`, delete `falling`.*
10. **A duplicated line where a second model was meant.**
    `ScoreHistoryReplayEquivalenceTests.swift:180–185`
    (`testAgreesAcrossModels`, "different models take different paths") runs
    `ReadinessInsight` **twice** and `SleepInsight` once — one of the three
    lines is a copy-paste and a third model (Fitness, with its profile-driven
    path) was plainly intended. *Fix: make line 183 a different model.*
11. **The stale-count lesson has one survivor.** `PresentationTests.swift:314`
    still says "so the other **330** tests can run in a sandbox" — the suite
    is 1,767 and CLAUDE.md removed its own count for exactly this reason.
    *Fix: "the rest of the suite".*
12. **A comment claims a bound the assert doesn't.**
    `LaunchParticleFieldTests.swift:176` says "the ceiling is generous (6× for
    a 4× size increase)"; `:201` asserts `< 8.0`. Small, but this repo's own
    rule ("a comment describing behaviour is still not evidence of it",
    activeContext, 2026-08-06) was coined for precisely this drift, in a test
    that exists because its own predecessor flaked. The min-of-five ratio
    design itself is healthy — no regression there. *Fix: make the comment say
    8×.*
13. **Eleven files still anchor on wall-clock `Date()` although `TestClock`
    exists.** `HeartAgeTests.swift:204`, `BaselineAndModelTests.swift:109`,
    `ScoreShapeTests.swift:71+`, `AdditionalInsightsTests.swift:5–13`,
    `BloodPressureCalibrationTests.swift:8`, `VitalDepartureTests.swift:19`,
    `MultiSourceTests.swift:75+`, `BuildAndSomatotypeTests.swift:10`,
    `MetricSanitizerTests.swift:6`, `NapContaminationTests.swift:173`,
    `PresentationTests.swift:8–11`. Most are interval-arithmetic-only and
    TZ-safe, but none is *reproducible* (a failure cannot be replayed with the
    inputs that caused it), and the profile-building ones
    (`dob = now - age × 365.2425 d`) make the model's computed age a function
    of the run date — `HeartAgeAnalyserTests` interpolates norm tables at
    "age 50" that is only approximately 50 depending on leap alignment, so a
    band-edge fixture can flip on a calendar date rather than a code change.
    *Fix: mechanical migration to `TestClock.now`/`TestClock.day` — the
    `Double` overload was added for `PresentationTests`' `29.9` probe
    (`TestClock.swift:42–46`) and `PresentationTests` never adopted it.*
14. **The silent-shrink sweeps have no census.** Four sweeps skip elements on
    a nil lookup with no companion pinning the examined set:
    `BiologicalAgeTests.swift:290` (`anchors(metric, sex:) == nil` →
    `continue` — a deleted norm table shrinks the monotonicity sweep
    silently), `ReferenceRangeTests.swift:43,57`,
    `MetricExplainerTests.swift:23,39,56`, `SectionCaveatTests.swift:78`.
    Each needs one census assert ("these N metrics have anchors/ranges/
    explanations; a change to N is a decision") — the same one-line shape that
    closed the ScoreAttribution hole. *Fix: one census test per file.*
15. **`Feedback`'s model-version registry is unpinned.**
    `Feedback.swift:153–168` maps every `InsightID` to a `-v1` key whose whole
    purpose is score comparability, and backlog #34 turns on remembering to
    bump `fitness-v1`. No test asserts the keys are **unique** (a copy-pasted
    duplicate would silently merge two cards' feedback pools) or that every
    `InsightID` has one (the switch is exhaustive, but only uniqueness is a
    semantic claim). `FeedbackTests.swift:48` uses one literal as fixture data
    and asserts nothing about the registry. *Fix: one test —
    `Set(keys).count == InsightID.allCases.count`.*

---

## 1. Outdated

- **The fixed instances, verified still fixed** (do not re-audit):
  `ContributorsFixture.fullCoverage` defaults to 130 days with the 20-day trap
  written into its doc comment (`ContributorsFixture.swift:14–29`);
  `ScoreAttributionTests.swift:839–852` derives its exemption set from
  `InsightModel.readsOnlySamples` rather than a list;
  `CardVisibilityTests.swift:72–91` replaced its behaviour-populated closed
  set with the rule stated in the failing direction. These are the templates
  the open findings above should copy.
- **The open closed-set instance** is finding 1 (`ContributionSummaryTests`
  `all`). Note the contrast case: `CalendarModelTests.swift:102–112` also
  asserts a closed field set via `Mirror`, and that one is *right* — it is
  derived from the privacy rule (any new field is a decision), and its own doc
  comment records the rule surviving a reader-approved widening.
- **Remaining callers passing explicit short fixtures are safe**:
  `DerivedSeriesTests.swift:195–234` passes `days: 40` but only ever to
  single-model (`FitnessInsight`) calls — no all-model sweep, so no hidden
  skip. `ContributorsTests.swift:23` defaults 130.
- **Stale count**: finding 11 (`PresentationTests.swift:314`, "330 tests").
- **Comment/assert drift**: finding 12 (`LaunchParticleFieldTests.swift:176`
  vs `:201`), and note `SymptomRadarTests.swift:962–967` shows the correct
  form — a test whose *reason for existing* is that a comment once claimed the
  opposite of the code, so it pins the arithmetic.
- **Cross-file sweep dependency**: `ContributorsTests.swift:188,282,307` all
  open with skip-guards whose completeness companion lives in a *different
  file* (`ScoreAttributionTests.swift:839`). Correct today; add a one-line
  comment in `ContributorsTests` naming the companion so a future split
  doesn't orphan it.

## 2. Weak assertions

- Findings 5 (substring-only export tests), 7 (±12 tolerances), 8 (disjunctive
  assert).
- `HealthDataExportTests.swift:82` — `json.contains("semaglutide")` passes
  wherever the string lands in the payload, not only in `previousMedication`;
  keys asserted by substring (`:59–61`, `:99–104`) can in principle be
  satisfied by a same-named key in a different nested object. Harmless today;
  the decode round-trip (finding 5) retires the whole class.
- Tolerance distribution is otherwise healthy: 212 uses of `accuracy: 1` on
  0–100 scores, a long tail of `1e-9` on shares that must sum to one, and the
  loose ones (`accuracy: 60` on a 99-day span in seconds,
  `PresentationTests.swift:230`) are proportionate. The two disproportionate
  ones are finding 7.
- `CardStateExportTests` / `ModelInternalsExportTests` assert markdown by
  substring — acceptable for a rendered document, and the substrings pin real
  constants (`ModelInternalsExportTests.swift:78–83` quotes
  `VitalSignsCheck`'s own values rather than restating them, which is the
  strong form).

## 3. Tautologies

- **Genuinely few.** The two differential suites that *look* like
  re-implementations are not: `ScoreHistoryReplayEquivalenceTests` keeps the
  replaced naive implementation as the reference and
  `MemoIndexEquivalenceTests` compares memoised against plain-scan answers.
  One maintenance hazard to watch: the naive reference has already been
  edited once to mirror a changed production rule
  (`ScoreHistoryReplayEquivalenceTests.swift:57–64`, weight-0 contributors) —
  every such sync is a chance for the reference to become a copy. When the
  rule changes again, change the reference *from the spec*, not by pasting.
- The one real self-referential assert is finding 9
  (`CompositionVelocityTests.swift:95`).
- `MetabolismTests` is the model of how to avoid the tautology: expectations
  derived from independent arithmetic (0.5 kg/wk → 550 kcal/day at :51–58)
  rather than from calling the formula under test.
- Mutation-testing receipts exist in two places and are worth imitating:
  `SymptomRadarTests.swift:470–472` and `:759–766` both record that a
  property-only predecessor passed under a broken rule and were rewritten
  until the mutation failed. No other suite records a mutation check.

## 4. Timezone

The 2026-08-04 discipline held almost everywhere: every
`Calendar(identifier: .gregorian)` in the suite pins a timezone (verified by
sweep — TestClock, CardioTrajectory, Presentation, SeriesSegmentation,
BodyScan, ScreenTimeImport, DayStamp, DataInventory, BodyMeasurementSource,
IngestionPipeline), Oura tests go through `parseSleepUTC`, and
`EvaluationMemoTests` / `DayStampTests` / `SubstanceEvidenceCountTests` test
*with* deliberately hostile zones (Tokyo, New York, UTC+8).

- **The gap is Whoop** — finding 2. Same shape, one door over from where the
  fix landed.
- **Deliberate `Calendar.current` couplings, all sound**, recorded so nobody
  "fixes" them: `SharedBaselineTests.swift:9–14` (documented — `VitalReader`
  defaults `.current`, so fixture and production must share it; pinning the
  test to UTC would *decouple* them); `NightSleepDetailTests.swift:10–18`,
  `CompositionVelocityTests.swift:9–15`,
  `ModelInternalsExportTests.swift:11–17`, `MultiSourceTests.swift:129`
  (all: pinned epoch, local-midnight-relative fixtures, same calendar passed
  to or defaulted by production — self-consistent in any zone). One standing
  condition: the `SharedBaselineTests` coupling is only sound while
  `VitalReader` keeps defaulting `.current`; if it ever gains an injected
  calendar, that file must move with it.
- `ScoreChangeTests.swift:144–147` carries the canonical war story in a
  comment (the `Calendar.current` fallthrough that passed only on UTC CI) —
  already fixed, kept as documentation.

## 5. Flakiness risk

- **The wall-clock lesson held.** The one timing test
  (`LaunchParticleFieldTests.swift:178–205`) is minimum-of-five, ratio-based,
  millisecond-sized, warm-up included — nothing regressed to a wall-clock
  budget anywhere in the suite (swept for `.measure`, `DispatchTime`,
  `CFAbsoluteTime`, sleeps: none).
- **All randomness is seeded.** `GoldenDataset.Seeded` (xorshift64*, fixed
  seeds per series), the two radar Monte-Carlo tests
  (`SymptomRadarTests.swift:244–247`, `:369–372`) use fixed-seed xorshift with
  the reason written down ("a calibration test that fails once a fortnight is
  a test nobody trusts"). No `SystemRandomNumberGenerator`, no `shuffled()`,
  no `arc4`.
- **No dictionary-order assumptions found in assertions**; the one
  order-preservation dependency (`Dictionary(grouping:)` in `EvaluationMemo`)
  is *pinned by test* rather than assumed
  (`MemoIndexEquivalenceTests.swift:75–97`).
- **The remaining risk is run-date dependence, not scheduling** — finding 13's
  `Date()` files. Second-order but real: age computed from a `Date()`-relative
  DOB crosses integer-band boundaries on calendar dates, not code changes.
- **Cost note, not a flake**: the two radar simulations run ~120k and up to
  2.4M model evaluations respectively (`:241–291`, `:368–414`). They are the
  right tests; they are also plausibly the most expensive in the suite. If
  suite time becomes a complaint, measure these two first before touching
  anything else.

## 6. Coverage holes — top 10, prioritised

Checked against the defect history in `docs/activeContext.md`: for each class
that shipped without a test, does one exist *now*?

1. **`ContributionSummary.bodyMeasurements` / `.screenTime`** — nothing
   (finding 1).
2. **Whoop `.sleepOnset`** — nothing, and untestable without the calendar
   overload (finding 2).
3. **`HealthDataExport` decode round-trip** — nothing; encode-side substring
   checks only (finding 5). The alternating key/value `inputs` array shape
   that broke the importer is representable and untested in the package that
   owns the types.
4. **`InsightResult` copy-forwarding, structurally** — the class recurred
   twice (`invitesInput` dropped 2026-08-05, `subheadline` dropped by the
   `appending(driverLines:)` copy). `DerivedSeriesTests.swift:256–268` pins
   the two *named* fields; the next field added to `InsightResult` is dropped
   again with no test able to notice. A `Mirror`-based compare of
   `base` vs `appended` over every child except the deliberately-changed one
   closes the category, not the instance.
5. **Departure-panel rule for the other ~10 cards** — finding 4.
6. **`Feedback` version-key uniqueness** — finding 15, and it gates backlog
   #34 (the fitness-v2 bump) happening correctly.
7. **Census asserts for anchors/ranges/explanations** — finding 14; a deleted
   `BiologicalAgeModel` norm table today fails nothing.
8. **`EnergyCurveExplainer` rendered state** — tested at the model layer and
   *never seen on any screen* (activeContext: neither the real export nor
   `SyntheticSeed` can produce an hourly curve). Not closable in this suite —
   recorded so it is not mistaken for covered. Needs hourly `SyntheticSeed`
   generation or the phone.
9. **The gait-triad promotion path** (`walkingSpeed` reading 0 days in the
   simulator against 1,093 in the export) — activeContext's open defect. The
   InsightKit half (`PromotionRules`) has tests; the loader half is a script
   and has none. Whoever picks up that defect: the cheapest pin is an
   InsightKit test that promotes a fixture raw-catalogue row for each triad
   identifier, so at least "the rules drop it" can be excluded in one run.
10. **Cross-suite completeness comments** — `ContributorsTests`' three
    skip-guard sweeps depend on a companion in another file with no pointer to
    it (Outdated, last bullet). One comment each; costs nothing; prevents the
    next reorganisation orphaning the guard.

## 7. Structure

- **The illness fixture exists three times.**
  `HealthWatchTests.history(illDays:)` (`NewCardTests.swift:120–135`) is the
  original; `SymptomRadarTests.swift:32–65` is a documented copy (generalised
  to `illWindows:`, plus a copied `singleOutlier`); `SuggestionTests` builds
  its own leaning fixture of the same shape (`:230–236`). The radar copy has
  already needed value-drift management (`:514–521` derives spreads from
  jitter to keep z in-band). Three suites now depend on one physiological
  shape — promote the generalised `illWindows:` version to
  `Support/` beside `GoldenDataset` and make the other two call it. The
  `nights(_:_:)` helper is likewise duplicated
  (`SymptomRadarTests.swift:18–24` "mirrors `nightly` in NewCardTests").
- **`TestClock` adoption is good but unfinished** — 26 files were consolidated
  (its own doc comment); finding 13 lists the eleven still on `Date()`,
  including the one (`PresentationTests`) the `Double` overload was built for.
- **Two files are past coherence size.** `SymptomRadarTests.swift` (990 lines,
  9 MARK sections: timeline, bands, memory, episodes, doses, ledger, copy,
  empty states, attribution, registration) and `ScoreAttributionTests.swift`
  (853). Both are still readable because the MARKs are disciplined, but the
  radar file now contains what are really four suites (model, episodes,
  ledger, card copy) — split along the MARKs before it doubles again.
  `SymptomRadarScorecardTests` already shows the pattern.
- **Naming is honest almost everywhere** — test names state the claim
  ("testAMissingDayDoesNotCountAsAGoodDay"), and several carry their fix date
  and mutation note in the doc comment. Two exceptions worth renaming when
  touched: `NewCardTests.swift` holds the *HealthWatch model* suite (the cards
  it was named for shipped a month ago), and `AdditionalInsightsTests.swift`
  says nothing at all ("additional to what?" — it is smoke tests for
  Sleep/Fitness/BodyComp empty and scored states).
- **Dead code in tests**: `CompositionVelocityTests.falling` (finding 9).
- **What is healthy and should be copied, not re-derived**: the codec suites'
  round-trip + refuse-everything-truncated + measured-size-claim triad
  (`SampleCacheCodecTests`, `RawCacheCodecTests`); fixture-drift preconditions
  that *fail* instead of skipping (`SymptomRadarTests.swift:852–855`);
  mutation-verified pins (`:470`, `:766`); constants quoted from production
  rather than restated (`ModelInternalsExportTests.swift:78–83`); census
  companions (`ScoreAttributionTests.swift:839`); and `GoldenDataset`'s
  stated-shape generator (gap, duplicate delivery paths, 300-samples/day)
  over recorded blobs.

---

*Audit produced in a worktree with five test-adding branches in flight; line
numbers are correct at this commit and will drift — the claims won't. When a
finding here is fixed, mark it here rather than deleting it (the backlog
rule).*
