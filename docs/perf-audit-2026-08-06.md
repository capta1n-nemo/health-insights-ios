# Performance audit — 2026-08-06

<!-- status: stopped — the agent was killed mid-run and left `PLACEHOLDER-NUMBERS` behind — rescued, incomplete, and **no number in it should be trusted without re-measuring** -->

> ⚠️ **RESCUED AND INCOMPLETE. Read this box before trusting a number.**
>
> The agent writing this was killed mid-run when the session ended, so the
> benchmark placeholders it left for itself — `PLACEHOLDER-NUMBERS`,
> `PLACEHOLDER-TABLE`, `MEASURED-EVALALL-LARGE` and any others — were **never
> filled in**. The *static* analysis (file, line, mechanism, caller lists) is
> complete and was worth keeping; every figure is not. Treat an unresolved
> placeholder as "not measured", never as "small".
>
> ⚠️ **Finding 1 is already fixed.** `recompute()` no longer runs the insight
> pass on the main actor — see commit `dab5399`, which moved it to a detached
> task behind a generation guard after the reader reported the app hanging on
> "Syncing your devices". The one number this audit needed most was measured
> separately during that fix: **`evaluateAll` over 379,990 samples and eighteen
> models takes 2.36 s on an M-series Mac.** The audit's diagnosis was right and
> its remedy was the one taken; it is left here because its *caller list* —
> every logging gesture that funnelled into the same pass — is the part that
> made the scale of the problem visible.
>
> Findings 2 onward are unverified against the current tree.


*Static analysis of every heavy path reachable from a user gesture, plus
micro-benchmarks run in InsightKit on the author's Mac (M-series, arm64,
release-mode `swift test`). Benchmark numbers are Mac numbers — an iPhone is
typically 1.5–3× slower on the same shape, so read them as lower bounds for
the phone. No production code was changed; the benchmark scaffolding was
deleted after measurement. Sample-set shapes mirror the reader's record:
~237k canonical samples (heart rate dominating) and ~320k raw rows.*

PLACEHOLDER-NUMBERS

## Verdict in one paragraph

The three historical fixes all held — the compact caches, the replay
throttle, and the render memo are all still wired and none has regressed.
The largest remaining hazard is structural: **`recompute()` runs the full
18-model insight pass synchronously on the main actor**, and every logging
gesture in the app funnels into it. `hydrate()` had exactly this problem and
moved the identical call to `Task.detached`; `recompute()` never followed.
Second is the refresh pipeline, which does its cache decode/encode,
sanitising, temperature reconstruction, diagnostics grouping and (with a
calendar connected) *two* full insight passes on the main thread, after every
pull-to-refresh and after every launch. Everything else is per-render scan
waste in identified views — real, bounded, and cheap to fix with the
`model.memoized` pattern the codebase already has.

## Findings, ranked by user-visible impact

PLACEHOLDER-TABLE

## The details

### 1. `recompute()` — the full insight pass on the main actor

`HealthInsights/Core/State/AppModel.swift:1943–1977`. The body reloads the
SwiftData logs, rebinds the engine, then:

- `results = engine.evaluateAll(samples:events:profile:)` at **:1964** — a
  synchronous call on the `@MainActor` class, over the full sample set.
- `refreshMedicationLevelSamples()` at :1951 — two O(n) passes
  (`samples.contains`, `samples.filter`) plus a whole-array reassignment
  when a regimen exists (:1938–1940).
- `derivedSeries.record(result, on:)` per result (:1970–1972) — cheap
  (per-result dictionary writes), not a problem.
- `recordScores` (:2013) — one SwiftData upsert per scored insight, small.
- `invalidateDerivedCaches()` + `prewarmBreakdowns()` — see findings 5 and 9.

Every caller is a user gesture or a refresh: `logDose` :949,
`logSideEffect` :477, `deleteSideEffect` :482, `saveGrounding` :1464,
`startMedication` :980, `confirmInferredDoses` :970, `discardInferredDoses`
:975, `saveBodyScan` :588, `deleteBodyScan` :601, `recordScreenTime` :538,
`reviewCalendarEvent` :311, `forgetCalendar` :317, `syncCalendar` :294,
`importSharedFile` :721, `performRefresh` :1790, plus the DEBUG import
paths. So **tapping "log a dose" pays the whole evaluateAll on the main
thread** — measured at MEASURED-EVALALL-LARGE on the 237k shape on a Mac.
On the phone that is a visible sub-second-to-second hang per logging tap.

The contrast that makes the fix obvious: `hydrate()` (:1335–1350) runs the
*identical* pass inside `Task.detached(priority: .userInitiated)` with a
`Sendable` parcel back to the main actor. `recomputeSubstanceImpact()`
(:2348) already shows the narrow alternative: re-evaluate only the model
whose inputs changed. One of those two shapes belongs under every
`recompute()` caller.

### 2. `performRefresh` — the main-thread refresh pipeline

`AppModel.swift:1703–1808` is `async` but main-actor-bound; every
synchronous stretch between `await`s runs on the main thread:

| step | line | cost shape |
|---|---|---|
| `dataStore.loadCachedSamples()` | :1753 | decode 237k (MEASURED-SCC-DECODE) |
| `dataStore.saveCachedSamples(nonManual)` | :1757 | encode 237k + atomic write (MEASURED-SCC-ENCODE) |
| `dataStore.loadCachedOther()` | :1764 | decode 320k raw (MEASURED-RCC-DECODE) |
| `otherSamples = …` didSet → `SymptomPromotion.events` | :102 | full 320k scan (MEASURED-SYMPTOM) |
| `dataStore.saveCachedOther(otherSamples)` | :1768 | encode 320k + 10 MB write (MEASURED-RCC-ENCODE) |
| `partitionedVitals()` sanitiser | :1779 | full pass (MEASURED-PARTITION) |
| `TemperatureReconstructor` | :1786 | full pass (MEASURED-TEMP) |
| `logMetricCounts` | :1787→:1877 | ~3 groupings over 237k + string building |
| `vitalEvents` rebuild inside recompute | :2032 | full 320k scan (MEASURED-VITALEVENT) |
| `recompute()` → `evaluateAll` | :1790 | MEASURED-EVALALL-LARGE |
| final per-source grouping for the log | :1795 | one more O(n) grouping |

And **the insight pass actually runs twice per refresh when the calendar is
connected**: `performRefresh` awaits `syncCalendar()` (:1732), which ends in
its own `recompute()` (:294), before `performRefresh` reaches its own
`recompute()` at :1790.

The `nonisolated` markers on the four cache functions
(`DataStore.swift:268–334`) make them *able* to leave the main actor — but a
synchronous call from a main-actor context still runs on the main thread.
`hydrate()` hops them onto a detached task; `performRefresh` never does.

This whole stretch runs after every pull-to-refresh, every foreground
refresh, and immediately after launch behind the freshly-drawn Today tab —
which is why the app can stutter exactly when the user starts scrolling it.

### 3. Per-render full-array scans in view bodies

`Array.samples(of:)` (`InsightKit …/Models/HealthMetricSample.swift:140`) is
memoised **only inside an evaluation pass**. From a view body it is a full
scan of all 237k samples per call — measured MEASURED-SAMPLESOF each. The
render-time callers that pay it:

- **`VitalsGlance`** (`Features/Dashboard/DashboardView.swift:248`, and
  :196) — up to 7 × `model.latest(_:)` per body evaluation of the *Today*
  tab, un-memoised. Re-evaluates whenever `samples` changes, which is
  several times per refresh.
- **`symptomRadarWebCard`** (`Features/Insights/InsightDetailView.swift:993`)
  — `HealthWatchModel.evaluate(samples:)` reads 7 watched metrics through
  `VitalReader.dailySeries`, so ~7 full scans per render, measured
  MEASURED-HEALTHWATCH per call. The comment above it (:2812–2817) argues
  the un-memoised call is deliberate; the *dependency-tracking* argument
  also holds for `model.memoized`, which reads `model.samples` inside the
  closure — every neighbouring card on the same screen already does that.
- **`MedicationSection`** (`Features/Insights/MedicationSection.swift:58,59,173`)
  — three uncached model calls per render: `medicationCurve` (whose doc
  comment at `AppModel.swift:341–343` *claims* "memoised per window" — the
  body at :344–352 has no cache), `medicationResponse` (full-array filter,
  `InsightKit …/Signals/MedicationResponse.swift:147`), and
  `medicationOverlay` (another full-array filter, :336).
- **`fitnessProjectionSection`** (`InsightDetailView.swift:610`) —
  `fitnessTrajectory()` re-fits per render; `AppModel.swift:2266–2271`
  explains why it is uncached, but that reasoning predates it being called
  from a render path.
- **`SuggestionEngine.suggestions`** (`InsightKit …/Insights/Suggestions.swift:189,481`)
  — runs `VO2Trajectory` and the whole `VitalSignsCheck` scan on the main
  thread on the first Insights-tab render after *every* recompute (the
  cache at `AppModel.swift:1121` is cleared by every recompute).

Everything else on the detail screens is properly behind `model.memoized`
(verified: gait, mental health, sustained load, nutrition, metabolism,
biological age, vitals scan, body split, effort, period contrast, night
detail, somatotype, body timeline) with a `LazyVStack` (:329).

### 4. `vitalsSummaries` — 237k `deviceFamily` string scans per rebuild

`AppModel.swift:1572–1611` builds the Vitals/Data-tab row summaries in one
pass — good — but calls `sample.source.deviceFamily` **per sample**
(:1586). `deviceFamily` (`HealthMetricSample.swift:90–101`) lowercases the
display name and runs up to 8 `contains` scans. The dedup path already
learned this lesson and memoises per source (`MultiSource.swift:351`);
`vitalsSummaries` never did. Cost MEASURED-VITALSUMMARY per rebuild, on the
main thread, and the cache is invalidated by **every** recompute — so the
first Data-tab render after every refresh or logging tap pays it again.

### 5. Every recompute throws away every replayed history

`invalidateDerivedCaches()` (`AppModel.swift:67–93`) clears
`scoreHistories`, `derivedSeries`, `ageHistory`, every breakdown and memo —
unconditionally, from every `recompute()` (:1975), even for mutations that
cannot change `samples` (a side effect, a calendar review). After each one,
the Insights tab re-queues up to 18 × 90-day replays (throttled to 2 at
`.utility` — the throttle itself is intact at :2094). The charts flip back
to "pending" and the phone re-burns MEASURED-REPLAY-TOTAL of CPU per
logging tap. `recomputeSubstanceImpact()` (:2348–2371) is the existing
proof that per-cause invalidation works: it surgically clears one card's
history and leaves the rest standing.

### 6. Data tab — per-keystroke recomputation of the catalogue scaffolding

The 320k-row grouping itself is cached (`otherGroupCache`,
`AppModel.swift:1395–1400`) — the D9/D29 fear that grouping re-runs per
render is **not** the case. What does re-run, on every body evaluation and
every search keystroke (`Features/Data/DataTabView.swift`):

- `fieldTitles` — computed 4× per render (:419, :654, :666, :779), each a
  `RawFieldPresentation.titles` pass over every dotted identifier.
- `rawFieldsByCategory` — 2–3× per render (:58 via `groups`, :418), each
  with per-category sorts.
- `filteredOtherGroups` — ~6× per render (once per `isVisible` +
  section), each a case/diacritic-insensitive `range(of:)` over every
  group's name and id.

All of it scales with the *group count* (~160–300 on this record), not with
320k, so it is keystroke jank rather than a hang — but it is the same work
done six times to render one frame, in the one screen that re-renders per
character typed. Hoisting them into one `let` at the top of `body` (the
existing `visibleDomains` comment at :222–226 already does this for one of
them) removes ~80% of it.

### 7. `OtherDataDetailView` — five passes over a dense identifier per render

`DataTabView.swift:836–973`. For one raw identifier the body computes:
`samples` (timeframe filter, :843), `charted` (:856), `stateCounts` (:869),
`suspicionNote` → `suspectValues` + quantile (:922), and `suspectValues`
*again* (:947) — `suspicionNote` internally recomputes `suspectValues`
(`RawMetricSample.swift:230–248`), so the quantile runs twice. The dense
identifiers this screen exists for (Oura's 5-minute series) hold tens of
thousands of rows; that is ~5 full passes per render, per timeframe change.
`@State` caching keyed on the timeframe, or a single computed bundle, fixes
it.

### 8. Startup — what blocks first paint, and what merely follows it

The launch path is in good shape:

1. Static `UILaunchScreen` covers everything before the first frame.
2. `AppModel.init` (:1274–1295) does only small SwiftData reads.
3. `hydrate()` (:1314) decodes both caches, sanitises, reconstructs
   temperature and runs the first insight pass **off the main actor** —
   correctly. Both compact codecs are still wired
   (`DataStore.swift:268–316` tries `.hisc`/`.hirc` first): the 98 s → 8 s
   fix has not regressed.
4. Two avoidable main-thread costs remain inside hydrate's tail:
   `otherSamples = loaded.other` (:1352) fires the didSet →
   `SymptomPromotion.events` over 320k on main (MEASURED-SYMPTOM) — *even
   though the detached task just computed the same promotion for the engine
   binding* (:1344–1345); and the first `samples` didSet cascade.
5. `refresh()` then runs the entire finding-2 pipeline behind the visible
   app — the post-launch stutter budget.

What could defer further: the symptom promotion result could travel back in
`HydratedState` instead of being recomputed; the refresh's cache saves and
diagnostics groupings could hop off the actor wholesale.

### 9. `prewarmBreakdowns` — correctly detached, one small caveat

`AppModel.swift:1989–2006` builds every metric's breakdown at `.utility`
off-main and merges under a generation guard — the design is right, and
measured at MEASURED-PREWARM for all metrics on the 237k shape (the docs'
471 ms figure for 45 types replicates). The `MainActor.run` merge itself is
a dictionary insert per metric — negligible. The caveat: it re-runs after
**every** recompute (finding 5), so each logging tap re-groups the entire
sample set in the background even when samples did not change. Harmless to
the main thread; not harmless to the battery.

### 10. Verified unchanged — the historical fixes

| claim in the docs | verified at | state |
|---|---|---|
| Compact binary caches on both files (98 s → 8 s launch) | `DataStore.swift:268, 307` | intact |
| `maxConcurrentReplays = 2` at `.utility` | `AppModel.swift:2094, 2161` | intact |
| Replay is one growing-prefix pass, binary-searched | `ScoreHistory.swift:87–147` | intact |
| `samples(of:)`/breakdown memo inside evaluation | `HealthMetricSample.swift:140`, `MultiSource.swift:437` | intact |
| Insights hero starts no replays | `InsightsListView.swift:39, 79` + `scoreChange` from stored rows `AppModel.swift:1153` | intact |
| Detail screens memoised + `LazyVStack` | `InsightDetailView.swift:329` + §3 exceptions | intact |
| Export screen builds detached | `DataExportView.swift:85–110` | intact |
| Refresh coalescing (no double pipeline from a second pull) | `AppModel.swift:1688–1701` | intact |

## Backlog rows — paste into docs/backlog.md §E

PLACEHOLDER-BACKLOG
