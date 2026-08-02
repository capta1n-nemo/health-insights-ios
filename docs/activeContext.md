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

## Handover now measures itself — read this before the next one

`/handover` has three parts and the third is **non-negotiable**: end the session
by telling the user whether it was cheaper than the last one, with the table.
See `.claude/commands/handover.md` and `docs/efficiency-log.md`.

The constraint that shaped it: **token usage cannot be observed from inside a
session**, so any figure would be invented and would poison every later
comparison. Every column is recomputable from `git` and `refs/ci/*` by a session
that trusts none of the prose. The one self-reported column — re-derivations —
requires each to be *named*, with the place the fact was already written down.

The column that matters is **compounding**: being careful does not survive a
context reset, but a lint, a skill or a self-healing script does. When a problem
appears, ask whether the fix retires the *instance* or the *category*.

## Read this before writing code

**The app's structural invariants are in `docs/architecture.md` ▸ "The
structural invariants — the enums that hold the app together".** Four rules,
each held by an exhaustive switch rather than by memory:

1. **New data appears in the Data tab** — `DataDomain`.
2. **A new input appears on every input surface** — `InputKind`, and a card must
   declare a `ContributionRoute` for anything it takes.
3. **Modelled is never dressed as measured** — `MetricSource.calculated`, its
   own family, weight 0, no reference range.
4. **One axis, standardised, never two.**

**Load the `add-data-or-input` skill before touching 1 or 2**, and `add-chart`
before touching a chart. Both were written from shipped defects.

## Current focus

**Graceful-population rules (latest, 2026-08-02, night).** The user, after the
audit: *"make rules so when a new card accepts a new source of info, it
gracefully populates across the cards"* — the more connectors, the more the Data
tab and the scores fill in. Turned the audit's lessons into enforced invariants:

- **`MetricType.dataCategory`** (`MetricDataCategory.swift`, InsightKit,
  exhaustive) — every metric declares its Data-tab group, so a new connector's
  metric appears there automatically. `DataTabView.categories` is now *generated*
  from it, not hand-written. This fixed two live drifts: **sleep latency and
  vascular age** were metrics with data missing from the Data tab. Held by
  `MetricDataCategoryTests`.
- **`ContributorCandidateTests`** — every model's reported contributor metrics ⊆
  `candidateMetrics`, so a scored signal reaches every section (contributor-keyed
  *and* candidate-keyed) uniformly. Fixed the one violation: Body Composition's
  `activeMedicationLevel` was a contributor but not a candidate (added it).
- Non-metric inputs already populate the contributor sections for free via
  `auxiliaryInputs` (previous push). Documented the whole thing in the
  `add-metric-type` skill ▸ "Graceful population" and `docs/data-conventions.md`
  ▸ §4, so the next session inherits the rules.

**Sleep onset deep-dive (previous, 2026-08-02, night).** The user wanted "a pretty
graph and deep dive" on how long they take to fall asleep — is it drifting, and
why (drugs? tech? eating? too hot/cold?). Shipped as a nested Sleep section,
"How fast you fall asleep":

- **`SleepOnsetModel`** (InsightKit, 7 tests) — nightly latency trend (reusing
  `ScoreTrend` for the fitted drift + scatter) plus a **contrast-based** driver
  analysis over the four things the app can see: substances that evening,
  medication level, skin-temperature deviation, and the day's active energy.
  Median-split contrast per driver (not raw Pearson r), and **temperature is
  three-way** (warm/cool/neutral) because both extremes worsen onset and a line
  through the middle finds nothing — the reader's own example. Every driver
  sentence says "association, not proof". `unseenFactors` names what it *can't*
  see (screen time, meal timing) so their absence isn't read as "nothing else
  matters".
- **`SleepOnsetChart`** (add-chart compliant): a scatter of nightly latency
  (measured → solid points, no connecting line so no between-night value is
  invented) with the fitted drift dashed (inferred). Wraps
  `ScrollableMetricChart`.
- Wired into `sleepNightCard` after "Your fortnight"; `AppModel.sleepOnsetAnalysis()`
  assembles the series and caches (double-optional). Only builds with
  `SleepOnsetModel.minimumNights` (10) recorded onset nights — needs an Oura-style
  source, since latency comes only from the nap-aware parser.

**The cross-card data-consistency audit (previous, 2026-08-02, night).** The user:
*"I need consistent data consumption and storage in the data tab in EVERY card.
Do a full review of every card."* A nine-card audit (three parallel agents) found
one structural defect and several follow-ons.

### The structural defect

**Five of the six per-card sections are keyed on `MetricType`/`contributors`;
only "How this is weighted" can render a non-metric input** (via `otherFactors`
as a `.grounding`/`.derived` `ScoreFactor`). So every grounding fact (cholesterol,
weight goal, age/sex) and every derived quantity (substance load, risk %, sleep
debt) is structurally excluded from "What goes into this", "Full history", "How
you compare", "How far from your normal", and the Data tab. Blood Pressure is the
only clean card — all its inputs happen to be stored metrics.

### Fixed this push (the shared-renderer fix)

`InsightDetailView.auxiliaryInputs(_:)` gathers a card's non-metric inputs from
`weightedFactors`/`unweightedFactors` (the emitted factors, with shares) **plus**
its `requirements` (grounding facts the model didn't emit — age/sex on Fitness,
Heart Health, Body Comp; the weight goal). "What goes into this" now lists them
under *"Also feeding this — not a measured series"* with their share, and "Full
history" gives each a row (grounding → its entry sheet; derived → plain row).
**One change, all nine cards** — cholesterol on the risk card and the recent-load
figure on Substance Impact now appear where the reader looks for what drives the
number.

### Still open — the audit's remaining gaps, ranked (next session)

1. **Derived scores are not in the Data tab** (user asked explicitly: "your ASCVD
   or SCORE2 etc scores"). SCORE2/ASCVD/consensus risk %, heart age, fitness age
   are computed and shown but stored nowhere as data. History already exists
   (`ageHistory`, `scoreHistories`). **Build a `DataDomain` for derived scores
   with a `DomainDataScaffold` detail page** (reuse `ScoreHistoryChart`/
   `AgeHistoryChart`). Follows the data-conventions this repo now enforces.
2. **"How far from your normal" is vitals-only.** It runs `VitalSignsCheck`,
   whose specs cover no `sleep*` metric and not `activeEnergyBurned` — so
   sleep duration (drives Readiness 0.20, Sleep, Energy) and active energy can't
   appear there though they drive the score. Extend the departure section to any
   metric with enough baseline, or state the limit.
3. **Two real bugs on Body Composition** (`BodyCompositionInsight.swift`):
   - **The RFM/build scoring route is dead.** `evaluate` calls
     `Self.score(bodyFat:bmi:age:sex:)` **without `build:`** (~L121), so the
     waist-derived Relative Fat Mass override (the `score(..., build:)` overload,
     ~L420) never runs — even though `.bodyType` is offered as an input route.
   - **Height doc/code contradiction:** the dial doc (~L409) says height "stays a
     charted input at weight 0", but no height contributor is ever emitted.
4. **Inverse inconsistency on Energy:** resting HR is a *weighted* contributor row
   but is explicitly not a scoring term (only sets the exertion threshold) —
   `Energy.swift:~85`, `:481`. Give it weight 0 with a note, or drop it.
5. **"How you compare" is empty on Sleep** (no sleep metric has a published norm)
   and thin elsewhere — a literature gap. Candidate norms need research per metric.
6. **candidateMetrics/contributors asymmetry:** Sleep's 2 unused temperature
   metrics, Heart Health's unused HRV flavour, and Body Comp's
   `activeMedicationLevel` (a contributor but absent from `candidateMetrics`, so
   missing from "How far from normal"). Align the two lists per card.

**The data-conventions session (previous, 2026-08-02, evening).** From a Data-tab
screenshot: the domain rows opened the wrong places and a side effect had gone
missing. One push.

- **The root bug: logged data was invisible to observation.** `sideEffects` and
  `activeMedication` were *computed* properties reading the SwiftData store, and
  a computed read off an external object registers no SwiftUI dependency — so a
  side effect logged from the `+` menu did not appear on a Data tab already on
  screen, and the Body Comp medicine section could show stale dose counts. Both
  are now **stored `private(set) var`s** reloaded by `reloadLoggedData()` at the
  top of `recompute()` (every mutation funnels through it) and in `hydrate()`,
  like `substanceEvents`. **Generalises: SwiftData-backed logged data must be a
  stored, reloaded property, never read live from the store in a view.**
- **The Data tab's detail destinations were each their own shape** — substances
  opened the *add* page, medication opened the Body Comp *card*, side effects
  were a static inline list that opened nothing. Now every domain opens a
  read-only page built with **`DomainDataScaffold`** (title, optional
  shared-component chart, entries newest-first, standard empty state):
  `SubstanceDataView`, `MedicationDataView`, `SideEffectDataView`.
  `MedicationHistoryView` (last session's) folded into `MedicationDataView`.
- **The conventions are now enforced, not described** — the user's "so I don't
  need to keep reprompting". `docs/data-conventions.md` is the authority;
  `verify.sh` fails if a `<Domain>DataView` skips the scaffold or hand-rolls a
  raw `Chart`. See the memory router. **Read that doc before adding a data type
  or a data page.**

**The screenshot-round-2 session (previous, 2026-08-02, evening).** Four asks off
new screenshots, one push:

1. **Trend indicator was "broken" — it was hiding the steady state.** The chip
   rendered only when the score *moved*, so on a screen of daily cards only the
   one that moved showed a badge and the rest looked broken. `ScoreChange` gained
   `chipLabel` (steady = "No change"), `ScoreChangeChip` draws all three
   directions (steady = neutral, equals sign, no valence colour), and the
   dashboard shows it whenever a change exists — silence now means only "not
   enough history to judge" (which is `nil`, and the trend cards genuinely are
   there: they need 21 stored quarter-days). **Steady is a measured answer, not
   an absence.**
2. **Score-over-time charts looked stuck.** `SectionPlaceholder` gained
   `isLoading`, set only on the replay's computing arm; `emptySection` draws a
   real `ProgressView` there instead of the static tick, so "working" is
   distinct from "empty". And the card you open now **jumps the replay queue**
   (`scoreHistory(for:prioritise:)`) — it was sitting seventh behind eight cards
   the Insights list requested on open.
3. **"How you compare" — more norms, researched.** Added **lean mass via FFMI**
   (Kyle 2003, BIA-measured, needs height, labels itself kg/m²) — the fifth
   published norm. Split the section into three buckets: blood pressure moved out
   of "no norm" into **assessed-by-category** (ACC/AHA), and the **modelled**
   `activeMedicationLevel` is dropped entirely. Researched and *rejected* SDNN
   (60 s vs 5 min window mismatch), sleep duration (U-shaped, breaks monotonic
   `Norm`), BMI (non-monotonic), bone/water (BIA-specific). The exclusions are
   the honesty constraint working, not a gap.
4. **Consolidated data viewing (user chose one-screen-per-card).** `CardDataView`
   — the card-scoped Data tab. The hub's per-route view links collapsed into one
   "View all this card's data" link; routes in the hub are now purely *add*.

**The one-add-button session (previous, 2026-08-02, evening).** The user, from a
screenshot of Body Composition's "View & add" running four full-size route
blocks with four identical red buttons: *"It should just be one add button, and
this should show you the ability to add new data and view all previous data and
inputs"* — and it must stay extensible as new kinds of data arrive (dose, body
type, weight-loss goal…). One push:

- **`ViewAndAddSection` collapsed to one button.** The card carries one status
  line per route (seal, name, figure) and a single "Add or view your data"
  button — a new route costs the card a *line*, not a block.
- **`ViewAndAddHubView`** (new, Features/Grounding) is the sheet behind it: the
  full per-route anatomy — guidance, add affordances, history links — moved
  there wholesale, along with all the sheet plumbing and the file importer. Its
  `section(for:)` is now the exhaustive switch over `ContributionRoute`.
- **`ContributionRouteStatus`** is the one resolver of a route's title +
  `ContributionSummary`, read by both card rows and hub sections, so the two
  surfaces cannot describe a route differently. New route case → compile error
  here and in the hub.
- **`MedicationHistoryView`** — the previously missing "view all previous
  inputs" for medication: every dose (estimated ones labelled) and side effect,
  newest first, view-only. Reached via `ContributionSummary.medication`'s new
  `detailLabel` ("All 24 doses and side effects"); its `addLabel` is now "Log a
  dose" and the hub carries a separate "Record a side effect" button, so the
  button no longer claims a destination it doesn't open.
- **`ContributionSummary.fileImport(lastReceived:)`** — the import route
  renders through the same anatomy as every other route instead of a bespoke
  block; takes a formatted phrase, not a `Date`, so tests pin no locale.
- Docs brought forward: `card-sections.md` (redesign block + gap 10 references
  now name the hub), `progress.md`, symbol index regenerated.

**The screenshot-review session (previous, 2026-08-02, afternoon).** The user
supplied nine screenshots and all three exports (card outputs, data inventory,
model internals — build `d96ada1`, which is HEAD) for a full is-our-work-right
pass. The review produced sixteen findings; one push fixed the seven confirmed
defect classes. What matters for the next session:

### The root cause that explains "sections lost their data"

**`renderMemo[key] as? T` hits a phantom nil on a missing key when `T` is
optional.** The dictionary subscript yields `Any?.none`, and a conditional cast
of that to an optional type *succeeds* as `.some(.none)` — so every
optional-typed render memo ("bodySplit", "peerStanding.…") returned nil on its
very first ask and never ran its compute at all. That is why "What you're made
of" claimed no scale existed and "How you compare" claimed no date of birth,
on a phone whose data was fine, starting the day render memoisation shipped
(`8058595`). `RenderMemo` (InsightKit, tested) now owns the cache: unwrap
before casting, and never store a nil, so a transient empty window can't stick
either. **Generalises: `dict[key] as? Optional<T>` is always a bug.**

### What else shipped in the same push

- Placeholders stopped lying: "How far from your normal" says when a card's
  signals are simply outside the scan's coverage (Body Composition — forever)
  instead of "not enough history"; "How you compare" distinguishes missing
  DOB/sex from having nothing to compare; `needsInput` takes a `remedy:` so no
  placeholder points at a "View & add" that says "All set" or isn't on the card.
- **The stale-sync morning** (`InsightResult.isAwaitingTodaysData`): Readiness
  and Energy with ≥7 recorded days and readings ≤3 days old say "Waiting for
  today's sync" / "Waiting for last night" and **stay listed on Today**; the
  Last-night tile titles a stale night "Yesterday's night" with a sync hint.
  Fresh installs keep the old copy and stay hidden.
- Body Composition's header leads with the scored route (body fat + its
  age/sex band; BMI demoted into the sentence), `primaryValue` is the scored
  figure.
- Heart Health: centile phrases fold into the component driver lines (no more
  "58 bpm" and "60 — top 25%" as two rows), and an HRR reading with no
  baseline appears as a weight-0 "tracked, not scored — needs 7 recent days"
  row via `ScoreBlend.supportingOrTracked` instead of vanishing from every
  list.
- Formatting: "1 signals"/"1 days ago" pluralisation (three trailing counts,
  Sleep, Fitness), substance deltas share one per-metric formatter
  (`deltaLabel`) so "HRV +5%" can't sit beside an unlabelled "+3.6", BP basis
  em dash.

### Open, deliberately not done — the next session's list

- **F8, the big one: split nights are STILL split on the device** despite the
  fix being installed. 07-31 reads Oura 4.3 h vs Apple 8.7 h in the internals
  export; Oura synced *today* (daily-activity rows for 08-02 exist) yet the
  sleep history wasn't rewritten, so either the sleep endpoint quietly returned
  nothing (the cache-merge stale trap) or the parser fix fails on real data.
  **Ask the user to run Settings ▸ Troubleshooting ▸ Rebuild data from
  providers, then re-export model internals.** If the four nights (07-31,
  07-29, 07-20, 07-11) still disagree, the parser fix is broken. The
  diagnostics log around a sync will show the sleep endpoint's result.
- **F11, needs the user's decision**: Substance Impact's systolic effect rests
  on 5 clean vs 3 after-use readings and carries 88.6% of the score (dial 0,
  "BP +31 after use" on Today). The export's own footnote calls that "a hint,
  not a finding". Same medicine as `minimumTrendSpanDays` wants applying — a
  per-side pool floor or shrinkage by pool size — but the threshold shape is a
  scoring decision the user hasn't made yet. Also cross-card: the BP card
  attributes the same 150/89 to Stage 2 hypertension at face value.
- F14: Readiness's supporting-only weighted shares renormalise four wildly
  unequal signals (one is a single manual BP reading) to 25% each.
- ~~F15~~ — **closed, and the answer is worth keeping.** `ScoreHistory` applies
  `minimumContributors = 2` to days it **reconstructs**; days the app actually
  scored at the time are stored and kept as they were shown, because a stored
  point is the record of what the reader was told. `SectionCaveat.scoreFloor`
  says exactly that. The old copy claimed sub-floor days "aren't shown", which
  the user's own export contradicted the same week.
**Eighteenth push — the input rule now has three checks behind it.** The user
found the hole `InputKind` had not closed: *"there are things on the body comp
page that are not in the add and view.. body type, log a dose, import from
file."* The enum guaranteed every **declared** input reached every surface;
nothing guaranteed a card declared what it offered, and Body Composition offered
a build-override picker inside a chart and a dose button inside a section.

- **`InputKind.cardRequirement`** — exhaustive, three answers:
  `.offeredAndPrompted`, `.offeredOnly`, `.settingsOnly(reason)`. A new input
  has to say which.
- **`InputKindTests`** checks the claim rather than trusting it: every
  `mustBeOfferedOnACard` kind must appear in some shipped model's
  `contributions`, and no `settingsOnly` kind may.
- **A `verify.sh` lint** catches the half a test cannot: any `…Sheet` view under
  `Features/` must be named in `AddDataView.swift`. The test binds inputs
  somebody *declared*; this binds the ones nobody did — which is what actually
  happened. Proven to fire by adding a throwaway `ProbeSheet` and watching it
  fail.
- **`SuggestionEngine.unusedInputs`** closes the last two clauses: a
  never-used `promptsWhenNeverUsed` input becomes a dismissible row in "Improve
  your health", and Today's dismissible suggestion card renders it for free.
  Strength 0.15 — deliberately below every grounding gap, because "a feature you
  haven't tried" must never outrank "this card cannot score without it".
  Only three prompt: substances, medication, file import. The profile facts and
  the cuff reading are already prompted *per fact* by `unlocks`, which knows
  which card each is blocking; nobody is asked to have a side effect.
- **`ContributionRoute` gained `.medication` and `.bodyType`**, and
  `inputKinds` is **plural** — `.medication` stands for regimen, doses *and*
  side effects, and a singular mapping would have left two of the three
  undeclared while looking correct.
- `AppModel.usedInputs` is an exhaustive switch too: a new input has to say how
  "has this ever been used" is decided, rather than defaulting to silently
  never-prompted or permanently nagging.

**Seventeenth push — Weight management, and the app's first modelled metric.**
Three asks, all the user's.

- **Body Composition has two bespoke sections now.** *"I want to actually put
  the medication on its own section, called weight management. Meaning body comp
  will have two bespoke sections."* `secondaryBespokeSection` is a fixed
  position 6 for every card and `EmptyView` on the eight with nothing to put
  there — so the one *positional* placement rule Phase 1 bought still holds.
  `card-map.sh` now reports 15 sections; the four hand-written tables beside it
  moved with it.
- **"On board" is gone everywhere.** It was pharmacology jargon. It reads
  **"Medication in your system"** — not "in your blood", because the model is a
  whole-body compartment, and saying blood would claim a measurement nobody
  took.
- **`MetricType.activeMedicationLevel`** — the app's **only modelled metric**,
  added so the level could join "What goes into this". That chart, the baseline
  machinery and the contributor pipeline all speak `MetricType`, so nothing else
  could carry it there. `PharmacokineticsModel.dailySamples` emits a point a
  day; `AppModel.refreshMedicationLevelSamples` folds them into `samples` on
  every recompute, stripping the previous derivation first so it cannot stack.
- **Weight 0, not the 2% the user offered.** The chart draws `contributors`, not
  weights, so weight 0 gets it on screen anyway — and a weight would assert that
  more or less of a *prescribed* drug is better. What the drug is doing is
  already scored (`rateWeight`). Stated in the code and in the row's own text,
  and pinned by `MedicationLevelMetricTests`.
- Three guards keep it from reading as a measurement: `MetricSource.calculated`
  on every sample, its own `MetricFamily.pharmacology` (`.body` would suppress
  the weight-versus-drug pattern as a tautology), and no `referenceRange` — a
  band would read as a target dose.

**Sixteenth push, then reverted — the share sheet's bottom row.** *"why is it
not in the bottom like other 3 apps that support actions, I want an action."*
Built (`aaf185c`), CI green, and **refused at signing on the deploy Mac**. Now
parked. `git cherry-pick aaf185c` brings it all back.

- **The design is sound and the blocker is not code.** The bottom row is Action
  Extensions, a different mechanism from the document type that put the app in
  the row above. An extension runs in its own sandbox, so the only way it can
  hand a file to the app is an **App Group** — and App Groups is not a
  capability a free personal team can sign. `docs/deployment.md` has the exact
  errors and the two prerequisites (an Xcode account on the runner, and a paid
  Developer Program membership).
- **Reverted rather than left on `main`** because it turned a deploy *install*
  failure into a deploy *build* failure. An install failure costs one update; a
  build failure means `main` reaches the phone not at all, and every later push
  inherits it.
- **CI could never have caught it**: it builds with `CODE_SIGNING_ALLOWED=NO`.
  Green CI plus a signing failure is the expected shape of this class, and it is
  the reason the push below exists.
- What was built and is worth keeping in mind when it returns: `SharedInbox`
  (the whole cross-process contract, 7 tests, container half behind
  `#if canImport(Darwin)`), an extension that **copies bytes and nothing else**
  because a full import in an extension is how one gets killed mid-write, an
  activation rule matching `public.json` rather than "any file", and
  `AppModel.drainSharedInbox()` on launch *and* foreground — coming back from a
  share sheet resumes the app rather than launching it.

**A deploy now records *why* it failed.** The verdict was a single bit, so "the
phone was locked" and "signing refused a capability" looked identical. `ci.yml`
has written `refs/ci/errors/<sha>` from the start; `deploy.yml` now writes
`refs/deploy/errors/<sha>` the same way, and `./scripts/deploy-status.sh
--errors` reads it. It answered the question above on its first run, for
nothing. `deploy-status.sh` also stopped printing *"the build is fine — this is
the install step"*, which was a guess dressed as a finding and is now sometimes
false.

**Fifteenth push — the Data tab is searchable.** It lists every metric with
data, every cuff reading, the substance log, the regimen, side effects and the
whole unmodelled catalogue — several hundred rows on this phone — so "where is
my resting heart rate" was a scroll.

- `isVisible(_ domain:)` is a **second exhaustive switch** over `DataDomain`,
  beside `section(for:)`. A new kind of data has to say how it answers a
  search, instead of quietly never appearing in one.
- The query matches a row's name **and** its domain's title, because section
  headings are the vocabulary the reader has actually seen — "medication"
  narrows to that section rather than to nothing. Same for metric group titles:
  "sleep" keeps the whole Sleep & recovery group.
- The unmodelled catalogue also matches on its **raw identifier**, since
  `HKQuantityTypeIdentifier…` is what an export prints and this is where those
  get looked up.
- `MetricGroup.id` was `UUID()`, so every keystroke rebuilt the list as
  entirely new rows. It is the title now.

**Fourteenth push — "is it working": the medication section grew an engine.**
The user, after showing Shotsy's Results tab: *"I want the medication board
graph to be in this new Medication section, and for you to overlay weight, fat,
relevant stats onto it.. so I can see how well it's working."*

- **`MedicationResponse`** (InsightKit, 16 tests) attributes the weight record
  to the dose history. Each dose owns the stretch until the next; the weigh-ins
  nearest each boundary — within ten days, **symmetric** — give it its change.
  Out of that: the ladder table (total and kg/week per dose step), the injection
  site table, and four overall figures measured **from the first dose**, not
  from the reader's first ever weigh-in.
- **A dose step with no weigh-ins keeps its days and its count but gets no
  rate.** Dropping it shortens the denominator and inflates that step's
  kg/week — a made-up number where a dash belongs. There is a test.
- **`SectionCaveat.doseAttribution`** carries the honesty on every table:
  attribution is by timing, not cause, and early loss on a GLP-1 is faster at
  any dose, so the first rungs always flatter themselves.
- **`MedicationResponseChart` is standardised, not dual-axed.** Milligrams,
  kilograms and percent on one axis as z-scores against each series' own window
  mean. Two y-axes is how any two lines can be slid until they agree;
  `MetricOverlayChart` already refused and this follows. The scrub read-out
  prints the real values, so nothing is hidden.
- **`ResponsePoint` exists rather than reusing `NormalizedPoint`** for exactly
  one field — `isInferred` — so a curve resting on doses `TitrationEngine`
  worked out stays **dashed** after normalisation instead of becoming a solid
  guess. That is the one thing this app never rounds in its own favour.
- Injection sites are shown but explicitly **not** presented as a comparison.
  The dose sheet offers the sites already in the record (`knownInjectionSites`),
  so a hand-logged dose groups with imported ones instead of starting a second
  name for the same place.
- Still not built from Shotsy's dashboards: the **calories** panel. Dietary
  energy arrives in the import but is not a `MetricType` yet — see
  `pendingNutritionKinds`.

**Two things this push cost, both now retired as categories:**

- **A `public struct` in InsightKit has an *internal* memberwise init.** The
  app target could not construct `MedicationResponse.Analysis`, and the
  InsightKit tests could — `@testable import` sees internal. So local green,
  CI red, and the diagnostic names the *call site* in the app rather than the
  declaration missing the init. **Write the `public init` in the same edit as
  any public struct the app constructs.** Now in the `verify-before-push`
  skill. A lint was prototyped and dropped: 47 public structs in InsightKit
  have no public init and most are legitimately InsightKit-only, so the check
  needs qualified-name resolution to be worth having. Left as roadmap.
- **`ci.yml` has always written the compile errors to `refs/ci/errors/<sha>`**,
  and this session went to the GitHub Actions API to read one line of them.
  That call returned 446 KB. `./scripts/ci-status.sh --errors` now fetches the
  blob — usually under a kilobyte — and `CLAUDE.md` and both shipping skills
  say so.

**Thirteenth push — the Data tab, and the master input list.** Three things the
user asked for after seeing the twelfth on the phone.

- **Vitals is now "Data", and third.** Today · Insights · **Data** · Settings.
  The rename was overdue on its own terms: the tab holds the substance log, the
  medication regimen, side effects and the raw imported catalogue, none of
  which is a vital sign. `VitalsView` → `DataTabView`, `Features/Vitals/` →
  `Features/Data/`. **File renames are free here** — the project uses
  `PBXFileSystemSynchronizedRootGroup`, so no `pbxproj` edit is involved.
- **`InputKind` is `DataDomain` for the input side.** *"This master input list
  is now out of date, so many new things that could be input are missing, make
  sure it gets updated every time a new input is in the app, also collapse this
  into a sub menu because it will get too long."* Settings listed nine
  grounding facts, hand-written, while the app accepted eight kinds of input
  across four surfaces that each kept their own list. `weightGoal` shipped that
  morning and was in none of them, so Body Composition asked for a fact the
  settings screen had no way to set.
  - `AddDataView` is generated from `InputGroup.allCases` × `InputKind`, and
    Settings pushes to it — the sub-menu the user asked for.
  - The Today `+` menu is `AddInputMenu`, from the same enum. Four `Bool`s of
    sheet state became one `InputKind?`.
  - `View.inputSheet(_:)` holds **one** exhaustive switch saying what each
    input opens, so a new input reaches every surface at once.
  - `ContributionRoute.inputKind` is exhaustive: a card route cannot exist
    without a master-list entry.
  - `GroundingKind.isEnteredDirectly` replaced the array of nine. `InputKindTests`
    asserts every grounding kind is reachable and that no shipped model requires
    a fact with no way in — **the test that would have caught `weightGoal`.**
- **Side effects can be entered by hand** (`SideEffectEntrySheet`). They could
  previously only arrive inside a Shotsy backup, so the app held a kind of data
  it gave no way to add — the input-side twin of the display-side bug the
  twelfth push closed.
- The renewal dots ("Current for another 6 months") moved from Settings into
  `GroundingDetailView` with the facts, rather than being lost in the collapse.

**Twelfth push — the Vitals tab is generated from an enum, so it cannot go
stale again.** The user: *"we've been importing more data, making new data,
etc.. it should all be getting put into the vitals tab. Whenever we add new
data, it must have an entry in that tab.. eg substances should have a section,
medications, later when we do composition scans"*.

- **The rule is now a compile error, not a habit.** `DataDomain` (InsightKit,
  `Presentation/DataDomain.swift`) enumerates every *kind* of data the app
  holds — `metrics`, `bloodPressure`, `substances`, `medication`,
  `sideEffects`, `unmodelled` — each carrying its title and summary.
  `VitalsView.body` is `ForEach(DataDomain.allCases)` into an **exhaustive**
  `switch`, so a new domain does not build until it has a section. The app
  target has no test target; the compiler is the only thing that can hold a
  rule there, which is why this is an enum in InsightKit and not a list of
  section builders in the view.
- **`DataDomain` is not `MetricType`, deliberately.** A metric is one measured
  series; a domain is a *shape* — a dated log, paired readings, a regimen with
  a decay curve. Most of these are not series at all, which is precisely why
  they kept falling out of a screen built around series. Composition scans add
  a case when they land.
- **Side effects were parsed and then dropped on the floor.** `ShotsyImport`
  read `sideEffectRecords` correctly and `ShotsyImportService.persist` did
  `summary.sideEffects = parsed.sideEffects.count` — it *counted* them into the
  result alert and never stored one. Found only because the new
  `DataDomain.sideEffects` case demanded something to render. There is now a
  `SideEffectRecord` (`@Model`, `externalID` for idempotent re-import),
  `DataStore.loadSideEffects()` / `mergeSideEffects(_:)`, and the summary
  reports what was actually merged. **Generalises: a count assigned from
  `parsed.x.count` with no corresponding merge call is the signature of this
  bug** — the alert says "12 side effects" and means "12 seen", not "12 kept".
- Medication's Vitals section shows mg on board (`PharmacokineticsModel.level`),
  the dose count and the last dose; side effects show the six most recent with
  severity out of 10.

**Eleventh push — the new inputs are reachable, and the med chart obeys the
rules.** Five things off the user's device, all real:

- **The share sheet works** — Health Insights now appears in the app row for a
  `.shotsyjson` file, so the imported UTI was the fix. **The bottom "actions"
  list is a different mechanism** (Action Extensions) and still needs its own
  target.
- **The import hung.** It did read, parse, several hundred SwiftData inserts
  and a full re-score synchronously on the main actor, so the app froze and
  the result alert appeared afterwards — the only feedback was the freeze.
  `importSharedFile` is `async` now, the parse runs off the actor
  (`ShotsyImport.parse` is pure), `ShotsyImportService.persist` is split out
  for the main-actor half, and `isImporting` drives `ImportProgressOverlay`.
- **`ContributionRoute.fileImport`** — the user's rule: *"everytime we do a new
  input type for any cards, the input needs to also be in this add section"*.
  Body Composition offers it beside its grounding facts.
- **The Today `+` is a menu**, not a shortcut to the substance log. It offers
  substance, blood pressure, dose (when a regimen exists) and Shotsy import —
  the app's one global add affordance had been showing exactly one of its
  input types.
- **`MedicationCurveChart` wraps `ScrollableMetricChart`** and takes the card's
  `window`. It drew a fixed 90 days while the picker said "M" and could not be
  panned — the `add-chart` skill's first rule, broken by me the day after
  loading it.

`ContributionRouteTests` asserted "exactly one route" per model; that was an
incidental truth rather than the invariant, which is that a grounding route
names the model's own requirements. Rewritten to test the rule, not the count.

**Tenth push — Shotsy as a listed integration, and the UTI that was blocking
the share sheet.**

- **The share sheet would never have offered us the file.** The user's
  screenshot shows Shotsy exporting `data_080226.shotsyjson`, described as
  *"Shotsy JSON Data"* — its **own exported UTI**, not `public.json`. A
  receiving app declaring only `public.json` is never offered it, however valid
  the JSON inside. `UTImportedTypeDeclarations` now imports `com.shotsy.json`
  (extension `shotsyjson`, conforming to `public.json`/`public.data`) and the
  document type targets it. **The file extension in a screenshot was the whole
  answer** — worth remembering as a class: a share-sheet miss is a *type*
  problem before it is a code problem.
  ⚠️ **Unverified on device.** If the app still does not appear, the remaining
  cause is that the share sheet's app row is populated by **Share Extensions**,
  and document types only reach "Open With"/"Copy to". That fix is a new
  extension target (new bundle id, signing, an app group) — deliberately not
  attempted blind while deploys are failing.
- **Shotsy is now in Settings ▸ Integrations**, at the user's request, beside
  Oura and Withings. `ShotsyIntegration` conforms to `HealthIntegration` with
  the differences visible rather than papered over: no Connect button (nothing
  to authorise), `sync()` returns nothing (**there is no pull — Shotsy has no
  API**), and the status line reports **when a file last arrived**, which is
  the only truthful freshness claim it can make. `disconnect()` forgets the
  source but **keeps the imported readings** — they are the reader's history,
  and disconnecting a source is not a request to lose data.
- `ShotsyIntegrationView` carries the three steps, a `shotsy://` deep link that
  **says what to do if it does nothing** (a third-party scheme is a guess
  unless documented, and a dead button is worse than none), and a file picker
  whose accepted types include `com.shotsy.json` — a picker offering only JSON
  greys the file out.

**Ninth push — Shotsy import, the app's first file-shaped input.** Shotsy has
no API, so its JSON backup *is* the integration: the user exports and shares
it. `ShotsyImport` (InsightKit, 20 tests) parses **export version 2**, written
against the user's real 84 KB file rather than a description of it — which
mattered twice:

- **The shape is not what anyone would guess.** No top-level `medications` or
  `shots`; there is `days`, a list of single-key dicts keyed by a unix day,
  whose values map an entry *kind* to a payload. Most kinds are one object;
  `shots` and `sideEffectRecords` are arrays; `sideEffects` is a lossier
  duplicate of the latter and is deliberately ignored (merging both doubles
  every side effect).
- **The units are actively hostile** — HealthKit *canonical*, not display.
  Body fat arrives in **ppm** (331890.03 = 33.19%), dietary energy in
  **joules** (5460872.8 = 1305 kcal), macronutrients in **kilograms**
  (0.0438 = 43.8 g), exercise in seconds. Imported naively the card would have
  shown a body fat of 331,890%. `ShotsyUnit` is the single place the
  conversions live, driven by the **declared unit** with the kind as fallback,
  so a future Shotsy release that switches to percent is not divided by 10,000.

**Verified against the real file**: 21 doses, 314 measurements (body fat
29.97–33.36%, weight 110.36–124.89 kg, lean 76.98–84.00 kg — all sane),
1 side effect, schedule Mounjaro 12.5 mg every 7 d. Nutrition is reported as
`unmappedKinds` rather than dropped, because **TDEE is blocked on exactly that
data** and the conversions are now written down.

**Imported doses supersede inferred ones**, and the file proves why. The user's
real ladder is 2.5 ×3 → **4.5** → 5 ×4 → **6** → 7.5 ×5 → 10 ×3 → **11** →
back **down** to 7.5 → 12.5, at intervals from 5 to 15 days. Three of those
doses are not on Mounjaro's standard ladder at all, and a *reduction* is
something no titration model would ever predict — so `TitrationEngine`'s guess
would have been wrong in at least six ways. A guess has no business outliving
the record it stood in for.

App side: `CFBundleDocumentTypes` claims JSON at **`LSHandlerRank` Alternate**
(Owner would make a health app the phone's default JSON handler — obnoxious),
`onOpenURL` intercepts the share (guarding `isFileURL`, since the OAuth
redirect uses the same door), `ShotsyImportService.read` handles the security
scope that only fails on device, and Settings ▸ Export gains a `fileImporter`
fallback. Both routes call one `importSharedFile`. Re-sharing the same backup
is idempotent — samples key on (metric, source, instant), doses on Shotsy's id.

**Seventh and eighth pushes — "do all of it".** The user asked for the whole
remaining list. Two coherent pushes:

**A. Body Composition can place you, judge your build, and name your shape.**
- `PeerStandingModel` gains `.bodyFatPercentage`, anchored on the *same*
  Gallagher band the dial scores against. **"None of this card's signals has a
  published norm yet" is false for the first time.** The mean sits above the
  band's top edge, because a healthy range is not a population's middle.
- `BuildAssessment` — Woolcott & Bergman **RFM** (validated against DXA on
  ~12k NHANES adults; BMI is validated against nothing but itself) plus the
  waist-to-height 0.5 action line. `BodyCompositionInsight.score` has **three
  routes** now: measured fat → dimensions → BMI. A BMI of 30.9 with an 84 cm
  waist on 1.80 m is flagged non-standard and scored from the waist; the same
  BMI with a 110 cm waist is not, because the override is not an escape hatch.
- `Somatotype` — three continuous Heath–Carter components, never a label,
  `isBalanced` because most people are mixtures.

**B. The GLP-1 module.** `PharmacokineticsModel` (Bateman, ka=ke limit handled
explicitly so it cannot emit a propagating NaN), `TitrationEngine`,
`MedicationScanPayload`, SwiftData `MedicationRecord`/`DoseLogRecord`,
`MedicationCurveChart`, `MedicationSection`, `SomatotypeCard`. **The safety
posture is one flag:** every inferred dose is stored unconfirmed, drawn
**dashed**, and sits behind a confirm-or-remove row until the reader says so.
Nothing recommends or advances a dose.

Two bugs the tests caught and are worth remembering: the titration walk emitted
a dose on **both sides of every step boundary**, which sorted into a ladder
that appeared to go backwards; and my own test asserted an inferred dose had
"decayed away" at three weeks when a five-day half-life still leaves it
carrying ~28% of the level — the test was wrong, not the code.

**Still not built, deliberately:** the LiDAR capture (ARKit, unexercisable from
a sandbox), the Vision OCR scanner behind `MedicationScanner` (the seam and its
text parsing are built and tested), and TDEE (needs dietary energy promoted out
of the raw pile — the Shotsy import now supplies it, unmodelled).

⚠️ **`MetricType.activeMedicationLevel` was on that list and no longer is** —
registered later the same day at the user's request so the level could appear on
the contributors chart. See the seventeenth push above for the three guards that
keep a modelled metric from reading as a measurement.

**Sixth push — Body Composition scores velocity, not just a level.** The user's
three answers came back: body fat **0.45** ("maybe 50% max", and asked what
other systems do), a stated weight goal **yes**, the medication posture **yes**.

- Researched before choosing: published loss guidance is **0.5–1.0 %/week**,
  and lean is **20–30% of what is lost** under good conditions (adequate
  protein, resistance training). **InBody** — the clinical standard — scores
  from a baseline of 80 and moves it on lean mass *and* fat mass roughly
  symmetrically against height/sex norms, rather than treating fat as
  dominant. That supports 0.45 rather than the 0.55 originally proposed.
- Pool is now level 0.45 / rate 0.30 / quality 0.25, all in
  `CompositionVelocityModel` with an EWMA(0.10) + least-squares fit over 56
  days. Quoted with `residualSD` like every other slope in this app.
- `GroundingKind.weightGoal` (+ `WeightGoal`) — **never inferred**, because
  inferring intent from the trend makes the score circular. **Unset scores the
  rate for safety alone**, which is all that is defensible without knowing
  what the reader wanted.
- Muscle mass left the weighted pool (BIA derives it from lean — the outside
  analysis's co-linearity point, and correct) but is **charted at weight 0
  with its reason**; `ContributorsTests` caught the orphan the moment the
  weight was removed, which is the second time this session a pre-existing
  guardrail earned its keep on a widening/narrowing change.
- Not built: TDEE (needs dietary energy promoted first) — still scoped in
  `docs/planned-modules.md`, which now marks module 1 as built.

**Fifth push — a real double-count, and four modules designed.** The user
brought an outside (Gemini) analysis of their full export plus a brief for four
new modules. Three of its claims were checked against the code before anything
was acted on; the scorecard and the designs are in **`docs/planned-modules.md`**,
which is now the architecture of record for that work.

- **Confirmed defect, fixed: cumulative metrics double-counted.**
  `deviceFamily` collapses the paths one device arrives by — right for a mean,
  catastrophic for a sum. Oura writes one daily step total (~4,400) and Apple
  Health mirrors the same day as ~300 intervals adding to the same ~4,400, and
  `bucketed(statistic: .sum)` added both. **Steps and active energy read about
  double** on the Vitals list and every day-or-wider chart. Now the largest
  single path's total per bucket (`MetricAggregator`), and per source rather
  than across sources in the Vitals row. `CumulativeDoubleCountTests`.
  **Why it survived so long: z-scores were unharmed** — a doubled series has a
  doubled baseline — so every departure looked right while the absolute
  numbers were wrong. Worth remembering as a class: *a consistent scale error
  is invisible to every relative measure in this app.*
- **Wrong claim, rejected:** VO₂max does *not* mix Apple Watch and Oura;
  `VitalReader` picks one series and never blends (`VitalReader.swift:109`).
- **Cheap unlock found:** the Gallagher %BF table is already in the repo
  (`BodyCompositionInsight.healthyBodyFatRange`), so "none of this card's
  signals has a published norm" is one `PeerStandingModel` case away from
  being false.

**Fourth push — Substance Impact rebuilt as harm reduction (user ruling).**
The user's words are quoted in full in `docs/card-sections.md` ▸ "Harm
reduction"; the short version is that the dial must read **measured impact,
never disapproval of use**, and their card read 0 on a 3-vs-5-reading blood
pressure comparison. Three faults, three fixes, all shipped:

- `worstResponseShare` 0.45 / `breadthShare` 0.55 — one signal can no longer
  zero the card; only a broad response reaches the bottom. The combiner became
  **linear**, so `penaltyShares` is exact by inspection (Euler's theorem no
  longer needed — the old root-sum-square is gone).
- `severity` subtracts one standard error and discounts by the thinner pool
  against `fullEvidencePairs` (5). Thin findings are shown, named and
  headlined — just not scored at full strength — and the driver line says
  "on 3 readings after use vs 5 clean".
- `watched` went 11 → 26 metrics. **Widening is safe by construction**: a quiet
  signal lowers the breadth mean, so more vitals can only raise the score
  unless they moved. Exclusions are documented (body comp/VO₂max can't move in
  18 h; sleep onset is a decision, not an effect).
- `exposureCeilingUnmeasured` 55 — heavy use with no biometrics reads 45, not
  0, because a log without readings is evidence of use and none of harm.
- Two pre-existing guardrails earned their keep in this change, both catching
  real gaps: every watched metric needs a driver-line name (16 were missing,
  and would have been measured then silently dropped) and a legend direction.
  The second's `family != .thermal` exemption was a proxy that broke when
  blood glucose joined — harm at both ends, not thermal — so it is now the
  named set `nearestNormalIsBest`.
- `testTheUsersOwnCardNoLongerReadsZero` reconstructs their export's eight
  rows exactly; the card moves 0 → ~45 with BP still the top row at ~50%
  instead of 88.6%.

**Third push of the afternoon (the user's rulings).** Answers came back:
morning re-sleep IS one night's sleep, F15 traced-and-fixed, AI-in-score
direction chosen (below). What shipped:

- **The convention**: a nap-typed Oura record beginning before noon joins the
  night (`OuraResponseParser.isMorningReSleep`; shared rule
  `countsTowardNight(type:localStartHour:)` keeps the export's "counted"
  column honest). 07-29 now reads ~8.5 h from both sources *after the next
  Oura sync re-parses*. Afternoon/evening naps and untimed rest records stay
  excluded; a re-sleep still never provides bedtime or latency.
- **"Last night in stages"** — Sleep's bespoke slot now draws the night:
  `NightSleepDetail` (InsightKit, tested — Oura 5-min phase strings → stage
  bands, wake-day keying matching the canonical nights table, window-only
  lanes for stageless sources) + `NightSleepChart` (one lane per source, gaps
  visible, no bridging, single-night exemption like EnergyCurve). Sleep's slot
  follows the two-things-one-slot pattern with "Your fortnight" nested below,
  which also gained the empty state the docs already claimed it had.
- **F15 resolved as truth-telling, not deletion**: replay enforces the
  2-contributor floor; stored points are the record of what the app said and
  are kept. The lie was the `scoreFloor` caveat ("aren't shown") — reworded to
  distinguish reconstructed days from stored ones. `recordScores` now stores
  the same "used" count the replay does (weighted contributors when any carry
  weight), and the scrub read-out suppresses "· 0 signals" (structural zero on
  the equation card).

**Verify on the device next**: the segments table in the next model-internals
export should show the four nights' second blocks as `late_nap` counted
"yes — morning re-sleep"; the Sleep card should draw last night in stages;
after the next Oura sync the nights table should agree ~8.5/8.5 on 07-29.

- ~~F8 split nights~~ **rebuilt and re-exported on build 177: still split, values byte-identical** — the grouping fix is not the story. Diagnosis narrowed: the missing halves are almost certainly records Oura itself types `late_nap`/`rest` (a morning re-sleep), which `isNight` excludes while Apple Health's path sums every segment. The internals export now prints the raw Oura segments (type, hours, counted-or-not) for any day with several segments or a nap — the next export settles it, and the remaining question is a CONVENTION (should a morning re-sleep join the night, matching our Apple path, or stay a nap, matching Oura's own app?) — the user's call, since it moves the Sleep score materially on those nights.
- The review's full ledger with file:line references survives only in this
  entry — the scratchpad findings file dies with the container.

**The hook-and-instruments session (previous, 2026-08-02, morning).** Six pushes
(`356e534` → `8155740`), all CI-green first time, all installed. It opened with
the user granting the six-session standing ask — the shell working-directory
hook — and became a find-and-fix loop over their screenshots, diagnostics log
and the new export's own first output.

### What shipped, in order

1. **`scripts/bash-workdir-hook.sh`** — every `Bash` call is rewritten to
   `cd <repo root> && …` by a `PreToolUse` hook. The cwd round-trip category is
   retired by the harness. **Building it found a latent hole**: hook processes
   inherit the shell's *drifted* cwd, so the relatively-pathed pre-push gate
   could silently fail to run (exit 127 is non-blocking). Both hooks are now
   `$CLAUDE_PROJECT_DIR`-absolute, the rule is in `CLAUDE.md`, and `verify.sh`
   lints for relative hook commands (canaried).
2. **Five Vitals display defects** from screenshots: doubled units ("99% %",
   "1h 19m min", "185 cm m" — three call sites appending `metric.unit` by hand;
   `MetricValueFormatter.detailedString` existed for this), cumulative metrics
   showing the last *sample* instead of the day's total ("Steps: 10" at 3 pm),
   Exercise Minutes in no Vitals category at all (promotion removed it from
   Other data, nobody added the row), Readiness labelling a skin-temp deviation
   "Body temperature", and fitness-age arithmetic that didn't survive the
   reader's own subtraction (rounded vs unrounded difference).
3. **Concurrent refreshes now coalesce.** The diagnostics log showed two full
   pipelines racing from launch — every Oura GET issued twice. `RefreshGate`
   can't stop it (it reads `lastRefreshedAt`, set at *completion*);
   `refresh()` now records its running task and later callers join it. A
   forced caller (rebuild, which just cleared caches) waits it out then runs.
4. **Settings ▸ Export my data ▸ Model internals** — the third instrument:
   per-vital baselines (value, baseline, z, **days of history vs the 7-day
   floor**), substance pools (**clean N vs after-use N** behind every "+X after
   use"), the floors quoted from the constants, and the last month of nights
   per source. `VitalSignsCheck.Reading` now carries `historyDays` so the model
   states the shortfall. **Ask for it beside "card outputs" whenever the
   question is why a card judged something.**
5. **Performance + visible progress** (user report: cards slow, settings hangs,
   copy takes ages). Three real stalls: `InsightDetailView.body` ran whole
   models over 231k samples *per render* (and re-ran them on every scrub) —
   now `model.memoized(_:_:)` + a `LazyVStack`; the export screen built all
   three documents synchronously in `body` — now detached with per-section
   "Preparing…" rows; first-open breakdowns paid a full scan on main — now
   prewarmed detached after `recompute()`, generation-guarded. Plus a
   `SyncActivityPill` on every tab naming the running phase. **The rule that
   generalises: a whole-sample model run has no business inside a SwiftUI
   `body` un-memoised — body re-evaluates on every interaction.**
6. **Oura split nights** — the new export's first real output caught the third
   cause of "7.5 h reported as 4 h": Oura files a broken night as several
   same-`day` records (`period` 0,1,2…), the parser emitted each, and the day
   bucket *averages*. Four nights read at half of Apple's figure (07-31: 4.3 vs
   8.7). `parseSleep` now groups by day: durations/stages sum, rates combine
   sleep-time-weighted, efficiency in-bed-weighted (single-period nights keep
   Oura's published figure exactly), latency is the *first* period's, RHR the
   lowest low. `SplitNightTests`, shaped like the user's 07-31 night. No
   migration: next sync rebuilds Oura's history through the corrected parser.

### To verify on the device / next export

- Cards should open near-instantly and scrub smoothly; Export my data opens
  with spinners that resolve; the sync pill appears during pull-to-refresh.
- Vitals rows read "99%", "1h 19m", "185 cm"; Steps/Active Energy show the
  day's total; an Exercise Minutes row exists under Activity & mobility.
- **Next model-internals export**: the four disagreeing nights (07-31, 07-29,
  07-20, 07-11) should read the same from both sources, and the diagnostics
  log should show one "Refresh started" per trigger (joiners log "joined the
  one already running").

### Open questions surfaced by the export, deliberately not built

- **The cuff baseline starves on a source split**: systolic shows "1 of 28
  days" of baseline despite 8 readings in 30 days, because the vitals scan
  judges against one device and the readings are split across "Manual entry"
  and "Health via Apple Health" — the same physical cuff under two labels.
  Merging manual-ish sources for sparse clinical metrics is a design decision
  for the user, not a session.
- **Oura contributes no bedtime** (`sleepOnset` is Apple-Health-only — 127
  nights vs Oura's 170), so consistency is judged on fewer nights than exist.
  `bedtime_start` is already decoded; emitting onset from it needs the
  timezone question answered (the parser resolves against `Calendar.current`).
- Readiness's driver list duplicates signals (components + vitals scan, HRV
  three times); Heart Health quotes two unlabelled values for one metric
  (scored baseline vs latest centile). Both wording/design passes.

**The load-performance session (previous).** First half: `c0028f2`, CI green,
installed. "Work on load performance, fix bugs, best judgment": the two items
taken were the roadmap's own top two — the cold-launch cache decode (see
"Immediate next steps", now closed there: JSON → `SampleCacheCodec`,
965 ms → 4–6 ms on the benchmark shape, with a free one-way migration) and
gap 18 (Sleep's nine coefficients written twice, now one `SleepInsight.Weight`
table both the score and the contributors read). Not yet seen on the phone:
launch should feel visibly faster on second-and-later cold starts — the first
launch after this update still reads the legacy JSON once.

Second half, on "complete roadmap and look for high value for users and UX":
the two buildable items from `docs/data-opportunities.md`, taken in its own
ranking. **Item #1 — exercise minutes now score Fitness** (`ActivityDoseModel`:
the trailing week against WHO 2020's 150–300 min band; the first term on that
card about what the reader *does* this week rather than where their VO₂max
sits). New `MetricType.exerciseMinutes` through all eight switches +
`bucketStatistic`/`plausibleRange`; HealthKit promotes `appleExerciseTime` out
of the raw pile; Fitness primary pool rebalanced to level 0.55 / trajectory
0.25 / dose 0.20 exactly as that doc proposed, renormalising to within a point
of the old 0.7/0.3 when no dose exists. **And the Withings housekeeping** —
bookkeeping fields and already-promoted numbered measures excluded at ingest
(~80 of the export's 232 "unmodelled signals"); the ingestor asks the typed
parser's own map so promoting a type retires its raw copy automatically.
Device checks for the phone: Fitness should show "N min of exercise this week"
as a driver and in "What goes into this" at 16%; Vitals ▸ Other data should
roughly halve after the next Withings sync; a new Exercise Minutes row appears
under Activity. What was *not* buildable from here, so the roadmap's remaining
open items stand: device-only verification, provider credentials
(Hume/Ultrahuman/Garmin/Fitbit), the deferred Body Composition scan entry
(ARKit), the crowd-norms privacy decisions, and the audio-exposure tenth card
(needs the user to want a card about hearing — see data-opportunities #2).
Third half, on *"the substance card shouldn't just say zero when substances
are used — base it off actual impact"* plus a critical review of the other
cards for unused signals. **The substance dial now reads the measured
response**: the fortnight's load used to enter the penalty pool at full
strength (up to 100 alone), so regular use zeroed the dial whatever the body
did. `effectivePenalties` treats exposure as a prior — with ≥3 measured
signals it caps at 25 (one band's worth) and the effect-size severities carry
the dial; with nothing measured the load still stands alone, because exposure
is then the only evidence. One pool feeds both `score` and `penaltyShares`,
so the Euler attribution survives unchanged, and the load's row says when it
was capped and when usage is all the number rests on. **And data-opportunities
#4 shipped**: `sleepLatencyMinutes`, emitted by the *typed, nap-aware* Oura
parser only (a nap's instant onset must not become the night's figure — the
generic pipeline cannot tell them apart), scored per Ohayon 2017 at weight
0.05 funded from duration (0.30→0.27) and consistency (0.10→0.08). The
critical-review verdicts on #2/#3/#5/#6/#7 and the provider-score panel are
recorded in `docs/data-opportunities.md` ▸ "The 2026-08-01 critical review",
each with its blocker named — #6 (BMR measured-vs-predicted) is the next
cheapest build; #3 and #5 wait on a fresh export to confirm field identifiers
and per-night semantics. Device checks: Substance Impact should now show a
non-zero score if your measured response is mild (the load row will say
"capped"), and Sleep should show "Fell asleep in about N min" once Oura
re-syncs. Fifth half: **the export came back, and it earned its keep in one use.** The
user shared their card outputs and five real miscalibrations fell out — every
one a claim no test could have caught without the shipped numbers, and each
now has a test shaped like the user's own data:

- **Substance 0 was a confounded measurement, not the load** (the cap worked
  — its row read "capped"). "After use" meant *recent* and the clean baseline
  meant *years ago*: 46 cuff readings spanning 2020–2026 against a fortnight
  of logs turned six years of BP rise into "+21 mmHg after use" at 87% of the
  score. `comparisonWindowDays = 90` — both sides of the comparison now come
  from the same stretch of life. **Generalises: a before/after comparison
  inherits every long-term trend in the series unless both sides are drawn
  from the same window.** Also: the headline now names the *strongest*
  measured effect (it was hardcoded to resting HR, so the card led with good
  news while BP carried the score), and the "your heart is showing a notable
  response" safety line fires only on a measured response — heavy usage gets
  a care line honestly attributed to the log.
- **"Steps: 224 · 1.5 SD below your normal" at breakfast** — a partial day
  judged against complete-day baselines reads catastrophic every morning.
  Fitness's cumulative supporting metrics (steps, energy) are judged on the
  last *complete* day; point-in-time vitals keep today.
- **"Systolic trending up 49.3 mmHg per week"** — a per-week slope fitted
  through readings clustered inside a few days extrapolates cuff noise.
  `minimumTrendSpanDays = 14`: under a fortnight of spread, no slope.
- **Body Composition penalised the loss its own drivers called good** —
  "Weight trending down (good)" beside "110.6 · 2.1 SD below your normal" at
  a cost. The supporting direction for weight now matches the drivers'
  judgement (`false`); muscle loss still costs through the lean/muscle rows.
- **The export itself walked into the pending-replay trap its docs warn
  about**: eight cards read "none stored yet" while their replays were
  queued. `pendingHistories` now says "replay still computing — re-export in
  a few seconds", and asking is what queues the replay, so the sentence is
  also the remedy.

Not changed on purpose, from the same export: Fitness 41 / fitness age 68 is
the norm table being honest about a VO₂max of 31 at 28; risk 0.7% with the
under-40 caveat is correct; Sleep's consistency 0/100 and 6.9 h debt are the
data. The user's 150/89 cuff reading is a real Stage-2 figure and the card
says so — nothing to recalibrate there.

Fourth half: **Settings ▸ Export my data ▸ Card outputs** — the user asked
for an export of everything the cards are showing so a session can see what
they see and recalibrate. `CardStateExport` (InsightKit, 5 tests): per card,
the full shipped result plus per-declared-input data availability and a
bounded history tail; build stamp first; tens of KB by construction (a test
pins <200 KB on a 50k-sample history). **When the user shares one, read the
build stamp before diagnosing anything** — their "substance card still says
0" report predates the measured-impact fix landing on their phone, and the
export exists precisely to make that distinction visible. The handover ran
at the session's close — session 18 in `docs/efficiency-log.md`: 2 waste /
7 pushes, zero red CI, seven installs, and the re-derivation named there
(the export violating this file's own pending-replay trap on first use) is
the lesson to carry.

**The sources-and-scoring session (previous).** One push, `bff6390`, CI green,
installed. The user asked for a sweep of all nine cards: *how are the sources
contributing to the score, and how are they reflected in each section?* — with
two specific complaints, both of which turned out to be right about more cards
than they named.

### The rule that was reversed, and why the reversal is the interesting part

The session ran in two halves and the second overturned the first. After the
weighting work below shipped, the user read it and said: **"Everything that is
in 'what goes into this' should go into the overall score. That's the whole
point of that section, and the weighting should just be a list of things that
all have a weight, even if some are very low."**

That overrides a rule argued at length in three files — *an invented weight
inside a number the user is asked to trust is worse than none* — and the rule is
**still correct about what it actually says**. What it could not support is the
work it was being used for. It argues against *inventing* a weight; it was being
used to justify *not attributing* one. Those are different claims, and the gap
between them shipped as a section headed "What goes into this" listing seven
signals on Fitness of which one went into anything, and eleven on Readiness of
which none did.

**Same shape as "that technique has a fatal flaw" is not "this is impossible"**,
already in this file from an earlier session. Worth generalising once more:
*when a principle is doing load-bearing work, check that the thing it forbids is
the thing you are declining to do.*

Nothing had to be invented to fix it. The app has known how to judge a signal it
has no published scale for since `VitalSignsCheck` was written — direction-aware
departure from the reader's own normal — and `ReadinessScore` weights every one
of its own components with exactly that mapping. `SupportingSignal.score` is
that function, extended with the case where neither direction is the good one.
Weaker evidence earns a **smaller** weight, not a zero one:
`SupportingSignal.collectiveShare` is 20%, one constant, and it is the whole of
the judgement — VO₂max keeps 80% of Fitness against six supporting signals at
about 3% each, so no combination of them turns "Excellent" into "Needs work".

**Three exceptions survive and each states its reason on its own row**, enforced
by `testAnUnweightedRowAlwaysSaysWhy` — which found three bare zeroes on the
risk card while being written. Two of them are one category: *the signal feeds a
different number on this card* (VO₂max and vascular age feed heart age, not
SCORE2; the autonomic pair feeds the estimator, which is not what the dial
reads). The third is a signal that moved the way you'd want it to. **Height left
Body Composition's inputs entirely** rather than earning a weight: it is a static
attribute with no series and nothing that can change between two readings, and
the only honest label for its bar would be "this cannot change".

### "Not a weighted average" was true on one card out of four

The section said it on Cardiovascular Risk, Blood Pressure, Substance Impact and
Body Composition, and the sentence behind it conflated two different claims:
**nobody chose these proportions** (true) with **there are no proportions**
(false on three of them).

- **Body Composition and Fitness rest on one measurement** scored against a
  published range — body fat (BMI in fallback) and VO₂max. One signal had 100%
  of the number, so "no signal has a percentage share of it" described a card
  that does not exist. *(Superseded within the day by the reversal above: their
  supporting signals carry 20% between them now, so the primary measurement has
  80% rather than all of it.)*
- **Substance Impact's pool divides exactly.** `worst + 0.35·√(Σ rest²)` is
  homogeneous of degree one, so by Euler's theorem each penalty's own
  contribution `pᵢ·∂f/∂pᵢ` sums to the whole — no normalisation, no
  approximation, and it is the same arithmetic `score` runs read backwards.
- **The risk card attributes by holding a factor at its optimal value and
  re-running the equation.** This is the decision worth carrying: the obvious
  alternative is decomposing the linear predictor, and every coefficient is
  sitting in `CardiovascularRiskModel` — which would be **a second copy of all
  of them**, free to drift. `RiskAttribution` knows no coefficient. It calls
  `HeartAgeModel.riskPercent`, which is the vascular-age method the app already
  ships and exactly what the card's own *"that gap is the modifiable part"* line
  already describes. **Generalises: when you need to attribute a model's output,
  look for a re-run you can do rather than a decomposition you have to write.**

Only Blood Pressure's cuff route is genuinely unweighted — and even there
*"this is your own cuff reading from the last 24 hours, taken at face value"* is
a stronger statement than a negation.

**The basis is now stated by the model rather than inferred from whether the
weights happen to be zero.** `InsightResult.weighting` defaults to `.unstated`,
so a new insight is silent rather than claiming a basis nobody chose for it, and
a test stops any card going back to having a number with no account of it.

### A metric declared and never read is invisible, and nothing was checking

Four cards were doing it, all found by hand. The consequence is *invisible*
rather than wrong, which is why it survived a session that audited every section:
`ChartedContributions.resolve` substitutes the declared list only when a card
reports **nothing**, so on a card reporting anything at all a
declared-but-unreported input charts nowhere, links nowhere under "Full history",
and appears in no legend.

- The risk card drew VO₂max and vascular age in **its own bespoke chart** and
  declared neither.
- Heart Health's **entire** bespoke section is heart-rate recovery, and the card
  neither declared nor reported it.
- Energy's drain half is heart rate against resting — a driver line saying
  "5.2 h with your heart rate above resting" — and neither metric reached the
  chart. **Heart rate charted on no card in the app.**
- Sleep declared both absolute temperatures (`docs/card-sections.md` claimed
  they had been "wired in") and read neither, so on a device reporting only an
  absolute the temperature term silently took its neutral 75.

`testEveryDeclaredInputWithDataIsActuallyRead` closes the class. **The
interesting part is its one allowed exception**: alternatives — rMSSD or SDNN, a
deviation or an absolute. `sharesMeasurementBasis` was the obvious candidate and
is too coarse (family-wide, so VO₂max and resting heart rate share a basis and a
card could declare one, read the other, and pass). `MetricType.interchangeableGroups`
is two rows of data instead — narrow enough to be true, and generic enough that
it is not a per-model exception list, which only ever catches the models somebody
remembered to leave out of it.

### Blood pressure's dial has three routes and they were in the wrong order

The user's framing, and it was correct: a reading from the last day is the
answer; past a day the dial should shift to the estimate built on all the data.
It was ranked **below** the recent 30-day average, which answers a different
question — *where has this been sitting* — and cannot move when the person does.
Now: fresh cuff → experimental estimate → recent average as the floor for
whoever has readings and no wearable.

A second defect fell out of touching it: `hasFreshReading` was tested against a
*sample* while the value scored came from `profile.cuffSystolic`, so a stale
grounding fact could be dialled under a newer sample's freshness.

### Two smaller things worth carrying

- **A hand-written weight is a second copy of the model.** Energy's contributor
  weights were 0.6 / 0.25 / 0.15, three constants written in the card and
  appearing nowhere in `EnergyModel`, under a heading promising "the share each
  signal has of the score". `Output.terms` computes them beside the
  coefficients. **Sleep still has this shape** — nine coefficients written twice
  in one function, with a comment saying they drifted apart once already. Open,
  and recorded as gap 18 in `docs/card-sections.md`.
- **A count cannot answer "which".** The unscored signals were a caveat reading
  "5 signals tracked, not scored", and the reader's actual question is which of
  them moved the number. Naming them is what exposed how many there were —
  fifteen across the nine cards — which is what prompted the reversal above.
  Three survive, each with its reason on its own row.

**The card-consistency session (previous).** Twelve pushes, all installed, no red
CI. Driven end to end by the user reading the shipped cards on their phone and
saying what was wrong — eight rounds of it. **All four of its
device-only judgement calls were confirmed good by the user on 2026-08-01** —
the floating timeframe bar's material and gap, the 40% chevron, the
body-composition axis rescaling as you pan, and the bedtime band moving under
your finger reading as informative. None needs revisiting.

The through-line is one idea applied until it held everywhere:

### A section that vanishes is an absence the reader cannot read

Every section on `InsightDetailView` used to disappear when its data missed a
floor, and the floors are high. Measured rather than assumed: replaying the nine
models over a realistic five-signal dataset gives **four of them zero
score-history points**, so "Score over time" was absent more often than present
and the user reported it as *removed*. It had not been touched.

The fix is that every section renders on every card and says **which** kind of
empty it is. `SectionPlaceholder` (InsightKit, tested) derives each reason from
the floor its own producer gates on — `ScoreHistory.minimumContributors`,
`PatternFinder.defaultMinimumPairs`, `PeriodContrast.minimumDaysPerPeriod` — and
quotes the real shortfall, so "not enough data yet" can never appear under a card
holding two years of it.

Three distinctions in that type are load-bearing and were each a defect avoided:

- **A pending replay is not no-data.** `AppModel.scoreHistory` returns `[]` on
  first ask and replays off the main actor, so a card opened cold is empty for a
  second. `scoreHistoryIsPending(for:)` is what stops a false statement that
  corrects itself only after it has been read.
- **"Not enough history to compare" and "enough history, nothing moved" are
  opposite messages.** `PeriodContrast.comparableCount` tells them apart, sharing
  `dailyMeans` with `changes` so the two cannot disagree about which metrics
  cleared the floor.
- **"Keep recording and this fills in" is the wrong instruction for a cuff
  reading.** `needsMore` versus `needsInput`, with a test pinning that neither
  instruction appears in the other's copy.

### The same zero can be a finding or an absence

`weight: 0` and `higherIsBetter: nil` are *deliberate* on some cards — `dayStrain`
is charted and unscored on purpose — and pure absences on others, because the
screen substitutes an insight's declared inputs when it reports none. Rendered
naively every row of such a card reads "tracked, not scored · neither direction
is better", two claims no model made. **Substance Impact before its first logged
event is the live case**, found by a test written for something else.
`ChartedContributions` carries the distinction; `ContributorsTests` pins that
Substance Impact is the only insight that reaches it.

### Splitting a model is what made a chart pannable

The bedtime strip had a real argument against panning: its window *was* the
model's scoring window, so scrolling back would draw nights against a centre
fitted only on recent ones. The answer was not to loosen that. Reading the
nights is the expensive half — a filter and a daily bucket over the whole sample
set — and fitting a centre, a weekend split and a spread to a few dozen of them
is arithmetic. `CircadianConsistencyModel.nights(from:days:)` does the first
once; `evaluate(nights:)` does the second per visible range, cheap enough for a
drag. **Generalises: when a window cannot move because a fit is attached to it,
separate the read from the fit before deciding the window is fixed.**

### The card's order now has a rationale, and the map is self-checking

The order is the user's, argued position by position in `docs/card-sections.md` ▸
"The order, and why": score → why → how it moved → what changed → the card's own
subject → what feeds it → how it is weighted → you against everyone → you against
you → the findings → the appendices.

**`scripts/card-map.sh` derives the order from `InsightDetailView.body`** and
`handover-check.sh` runs `--check`, so a session cannot close while the record is
stale. It fails rather than self-heals on purpose: only the ordering is
generated, and the matrix, the gate table, the per-section feature audit and the
per-chart audit beside it are hand-written, so a red check is a prompt to
re-read. Handover step 5 spells out what a new *card* changes versus a new
*section*. **Many more cards are coming and this is the thing that will keep
telling us where the gaps are.**

### The timeframe control is pinned, on its third placement

It drives five sections spread from position 3 to 11 of fourteen. Inside "Score
over time" it vanished with that section; gated on `usesTimeframe` it was hidden
on exactly the cards where widening the window is the remedy. **Both bugs were
the control being somewhere the reader wasn't.** It is now a
`safeAreaInset(edge: .bottom)` above the tab bar — an inset rather than an
overlay, so the last section can still be scrolled clear of it.

### Heart Health has a section that speaks to a 25-year-old

"How you compare" went universal, which took Heart Health's bespoke slot with it
and exposed something worth writing down: **SCORE2 is validated 40–69 and ASCVD
40–79**, so heart age and the risk card say *nothing* to a young reader. The fix
is not to extrapolate past a validated band. Heart rate recovery is the one
cardiac marker whose published threshold is a fixed count of beats rather than a
curve through age — ≤12 bpm in the first minute marked roughly double six-year
mortality across 2 428 adults (Cole et al., *NEJM* 1999), ~26 bpm is typical on a
wrist device — so it reads the same at 25 and 65. `HeartResponseModel`, 8 tests.
It does not score: no validated 0–100 curve exists and `RecoveryScale` draws a
position between two published marks rather than a dial.

**Considered and not built: AHA Life's Essential 8.** It is the construct
designed for exactly this problem — only 32% of 20–39s hit five of eight ideal
levels, and cumulative score from 18–45 predicts midlife disease. The app has
6–7 of the components; **diet is entirely absent**. A partial LE8 needs a
decision about renormalising over what we have. Raised with the user, not taken.

### Norms exist for three metrics and no more

"How you compare" now takes each card's own inputs. `PeerStandingModel.norm(for:
age:sex:)` returns non-nil for exactly **resting heart rate, rMSSD and VO₂max**
and `nil` for everything else, and the section *names* the unnormed signals
rather than dropping them — two rows out of nine implies the other seven were
checked and found unremarkable. Returning nil rather than guessing is the whole
claim: a centile on an invented mean is indistinguishable on screen from one
built on NHANES. Blood pressure is deliberately absent even though norms exist —
it is classified into ACC/AHA bands rather than ranked. Crowd-sourced norms are
scoped in `docs/progress.md`, privacy question first; `hasPublishedNorm(_:)` is
the seam.

### The one that got worse: shell working directory

Five dead round trips to a relative path resolving in the wrong directory —
`cd InsightKit && swift test` leaves the cwd there for the *next* call. The rule
is in `CLAUDE.md` in the plainest words available and has now failed in four
consecutive sessions. **It is a tier-1 rule and tier 1 does not hold.** The
mechanical answer is a `PreToolUse` hook, which touches `.claude/settings.json`
— the user's harness config — so it needs asking for. See the efficiency roadmap.

**Closed 2026-08-01 (session 19): the user said yes, and the hook exists.**
`scripts/bash-workdir-hook.sh` rewrites every `Bash` command to
`cd <repo root> && …`, so the drift can no longer happen — proved live with a
bare `pwd` after a stray `cd InsightKit`. Building it found a second defect:
hook commands in `settings.json` inherit the *drifted* cwd, so the relatively
pathed pre-push gate could silently fail to run on a push issued after a `cd`
— both hooks are now `$CLAUDE_PROJECT_DIR`-absolute. Full account in
`docs/efficiency-log.md` ▸ the session-19 roadmap entry.

**The Phase-2 session (previous).** One push, `dc5fae6`, CI green. "Continue with
roadmap" — the open list was read back and the four buildable Phase 2 items were
taken, plus a fifth the user added on reading the plan. Body Composition's scan
entry was **deferred by the user** to its own session.

### One defect, three times: a number that dies at a string boundary

This is the finding worth carrying, because it is a *class* and the codebase
almost certainly has more of it.

- `PeerStandingModel` computes a centile. `HeartHealthScore.swift:219-226` turns
  each one into `"HRV 48 ms — top 25% for your age and sex"` and the number is
  never seen again.
- `HeartAgeAnalyser` fills `Analysis.projections` (`:146`).
  `CardiovascularRiskInsight.swift:186` reads four *other* fields off that local
  and lets it fall out of scope. Worse: the analyser's own `explanation()`
  (`:273`) writes *"The projections below run the same validated equations at
  future ages"* — and that function has **no production caller at all**, only
  `DeepDiveTests` and `HeartAgeTests`. A promise nobody could see being broken.
- `VO2Trajectory.projectedIn12Months` and `.residualSD` — the latter described in
  its own doc comment as "the honest ± on the forecast" — were read nowhere
  outside `CardioTrajectory.swift`.

**How to find the next one**: grep a model's `Output` for a public field, then
grep the app target for its name. `InsightResult` has no typed side-channel, so
anything not in `contributors`, `driverLines`, `score` or `headline` reaches the
screen only if some view calls the model directly — and mostly nothing does.

### Two threshold tables that could have drifted, and now cannot

Both are the `PressureBandTests` situation, and both were fixed by making the
duplicate impossible rather than by testing that two copies agree.

- `PeerStandingModel.Standing.phrase` held the edges 90 / 75 / 60 / 40 / 25
  inline. A strip that *shades* those bands has to read the same numbers.
  `PeerStandingModel.Band` owns them now; `phrase` reads it.
- The vitals scan's `watchZ` / `unusualZ` moved into `VitalDeparture`, and
  **`VitalSignsCheck.reading` now calls `VitalDeparture.band(z:concerning:)`**.
  One implementation, not two that agree today.

**And the strip's band is `Reading.status`, not a re-derivation from z.** Two
reasons, both real:
- **Direction matters.** `Spec.concernWhenHigh`/`concernWhenLow` mark the
  clinically meaningful way round. Colouring by `abs(z)` would paint a resting
  heart rate two SD *below* baseline — the best morning of the month — in the
  same red as the worst.
- **An absolute bound overrides a personal one.** A reading can be `.unusual` at
  a small z. `VitalDeparture.isBeyondClinicalBound` is derived by asking whether
  the z alone would have produced that band, and it exists because a red dot
  near the middle of the axis with no explanation reads as a rendering fault.

### The chrome rule is a compile error now, not a convention

`InsightSection` (over `Card`) and `NestedInsightSection` carry title, at most
one figure, content, caveat. **`caveat` has no default**, so a section cannot be
written without stating one and `.none` is a visible choice.

That is the compounding shape the efficiency log keeps asking for: it retires the
*category* — "a section can ship without saying it inferred" — rather than the
eight instances, and it needs no lint because the compiler is the gate. The old
convention was followed by four sections out of twelve.

What it replaced, measured by reading every section: footnote colour split three
ways for one job (`.tertiary`, `.secondary`, `Theme.warn`), four header fonts,
inner spacings of 8 / 10 / 12 with no rule, and **one trailing slot that changed
quantity under a fallback** — a kilogram delta, or a count of weigh-ins, same
position, nothing to tell them apart.

Moving the wording into `SectionCaveat` (InsightKit, tested) immediately caught
two shipped defects: the body-composition caption opened *"Height is your
weight"*, and pluralised *"across 1 weigh-ins"*.

### "View & add" claimed an anatomy it did not have

Its own doc comment said "the anatomy is fixed whatever the route". Read against
the code: blood pressure had a grounded summary and the other two did not; the
grounding-facts route had **no add button at all**, so its rows were the only way
in; the "all readings" link appeared only past three readings, so the screen was
unreachable exactly while a user was learning the feature; and all three routes
previewed their own contents on the card.

Now everywhere: header and figure, green grounded summary, one prominent button
into the sub-menu holding adding *and* what was added, and a link to the fuller
screen **where one exists past it**. No previews — readings, events and fact
values all moved behind the button (`GroundingDetailView` is new for the facts).

Two decisions to keep: the link is blood-pressure-only, because
`SubstanceLogView` and the grounding list already *are* the full view and two
controls pointing at one destination is what this section exists to remove; and
`ContributionSummary.bloodPressure` **defers to `CalibrationStatus`** rather than
forming a second opinion on whether it is calibrated.

### `if: always()` does not always run, and the verdict refs have a blind spot

Found while answering "why is it not deploying" on this session's own push, and
worth keeping because the *first* answer given was wrong in the familiar way.

`deploy.yml`'s last step writes `refs/deploy/{passed,failed}/<sha>` under
`if: always()`, so the reasoning "no ref at all means the job never ran" looks
sound. It is not. What actually happened to `dc5fae6`: the Mac claimed the job,
cleared checkout, team-ID resolution, keychain unlock and the build stamp, then
**stopped heartbeating ten minutes into the Xcode build**. GitHub concluded the
job `failure` with step 7 still marked `in_progress` and steps 8–9 `pending`.
A runner that dies cannot run `always()`.

So "no verdict" is three situations — still building, never claimed, died
mid-build — and `deploy-status.sh` could not tell them apart. It now prints all
three and the recipe for deciding which, rather than asserting the runner is
offline. **The tell**: `runner_name: ""` on a queued job means nobody claimed
it; a step stuck `in_progress` under a `failure` conclusion means the runner
died holding it.

Reading that costs a few hundred bytes despite the ~450 KB listing, because the
MCP tool spills oversized results to a file — `python3` over the file is the
cheap path, and the standing "never use the Actions API" rule is about reading
the *response*, not about the question being unanswerable.

**Neither case needs a re-push**: the queued run deploys when the Mac returns,
carrying the newest commit rather than the one that failed.

Same shape as the `tunnelState` guard and the Oura scope guess, one level up:
*verify a guard's premise against raw tool output before acting on its remedy* —
here the guard was `always()`, and the premise was that it always runs.

### The gate that did not need to fire

`progress.md` had carried "**Do this first**: ask the user for the data
inventory" on Phase 2 for several sessions. It gated nothing, and the reason
generalises: **every remaining item drew output a model was already computing**,
so "does the data exist" was answered by the model producing a value at all.
Each section self-gates on its own floor, which is what every existing section
does — so a card with nothing to show doesn't draw it, and nothing had to be
decided in advance. Same shape as *"this needs a product decision" is a claim
about the implementation*.

**The charts-on-the-phone session (previous).** Fifteen pushes, all installed. It
began as "here is a fresh inventory" and became a long iterate-on-the-phone loop
over the Body Composition card. What it produced, and what it cost, are both
worth reading before touching a chart here.

### The two data defects, and how they were found

- **A night crossing midnight was counted as two.**
  `HealthKitService.fetchSleep` keyed every nightly figure on
  `Calendar.startOfDay(for: segment.startDate)`. Apple Health writes a night as a
  run of stage segments, so the pre-midnight ones were filed under one day and
  the rest under the next: one night became two, the smaller a sliver. That is
  the export's `sleepDurationHours` **min of 0.01 h**, and — efficiency having
  split its numerator and denominator independently — its **2% minimum** too. It
  also dated Apple Health a day out from Oura, which stamps a night at the day it
  *ends*, and `bucketStatistic` averages same-day samples. Same "7.5 h reported
  as 4 h" shape as the nap bug, from a second cause that outlived it.
  Now `SleepNights` in InsightKit, 14 tests, keyed on `SleepOnset.night(of:)`.
  **The fix was one scroll from the bug, in a comment that named it** —
  `SleepOnset.night(of:)` said "grouping by calendar day is what the duration
  series already does and it is wrong", written by the session that fixed the
  timestamp path and left the duration path alone.
- **The export could not settle the question it was built for.** The nap fix was
  to be proved by `restingHeartRate`'s max falling from 119, but three sources
  feed that metric and the report gave one merged distribution, so 119 named
  nobody. `DataInventory` now emits per-source N/first/last/min/median/max for
  every multi-source signal. **Still unproven — ask for a fresh export.**

### What the phone now has that it did not

- **Settings ▸ Troubleshooting ▸ Rebuild data from providers.** Pull-to-refresh
  *merges*; the cache-merge keeps the samples of any source that returned nothing,
  so a provider that quietly fails to sync serves stale values forever and no
  amount of pulling dislodges them. "Refresh" and "replace" were different
  requests and only the first had a gesture. Manual entries, grounding, substance
  logs and feedback are SwiftData and untouched.
- **All nine cards got a bespoke section.** Heart Health and Readiness share
  "How this is weighted" (drawn from `contributors`' renormalised weight — no new
  type, no model change, exactly as the roadmap predicted); Body Composition got
  "What you're made of" plus a stacked-area history.
  *This bullet read "**Phase 2 is done**" until 2026-08-01, which conflated
  every card having a section with the phase's other four items. Phase 2 is now
  genuinely done — see "Current focus" — but for a different reason, and the
  conflation is why nobody noticed the same file claiming both.*
- **A scrub line on every chart.** Seven charts wrap `ScrollableMetricChart`, so
  drawing it there covered all seven at once; only the two standalone charts
  needed their own.
- **Score history is filled and graded by band.**

### Five chart lessons, in cost order — read these before touching a chart

1. **A Swift Charts gradient resolves against the mark's own bounding box, not
   the plot area.** A card scoring 15 drew the full green-amber-red ramp squeezed
   into the bottom sixth of the chart. `Theme.scoreFill(peak:)` takes the peak for
   this reason.
2. **A stacked area whose series is absent over a stretch still reserves a
   stacked offset for it**, interpolated from its first real value, while its
   polygon starts only where its data does. The two disagree and the disagreement
   is drawn — a white wedge widening to exactly the size of the first reading.
   **Give every series a value at every x, zero where the band is absent.**
3. **Band membership must not vary point to point.** Giving each day the finest
   split its own readings supported was honest and drew a row of notches. A day
   missing the muscle/bone division now borrows the ratio from the nearest day
   that measured one and is flagged `isEstimated`.
4. **A translucent overlay cannot make blue over red look blue.** Five attempts
   at hue and opacity all landed on plum, because red mixed with blue *is* purple
   — colour arithmetic, not a tuning problem. The measured composite was
   rgb(126, 88, 121): red and blue near-equal, green suppressed. **A hatch never
   mixes**: every pixel is one colour or the other. `Theme.waterHatch`.
5. **Measure the pixel, don't pick the hue.** Four of this session's eight rework
   commits are one visual iterated by eye. One measurement found the cause in a
   single step. Same shape as the launch-screen tuning in session 11, which is
   already in the ledger as *tune a visual against opinion instead of
   measurement*.

### Three things to carry from the first half of the same session

- **A measurement artefact can survive the fix aimed at it, because two causes
  produce one symptom.** The Oura nap fix was correct, deployed and installed;
  the number it was meant to move did not move, and the tempting reading was that
  the fix had failed. It hadn't — a second cause was still live.
- **An instrument that cannot attribute cannot settle anything.** The export was
  built to end "we don't have X" arguments and then merged away the one
  distinction the argument needed.
- **"Refresh" and "replace" are different requests.** Only the first had a
  gesture, and the cache-merge means a silently-failing provider serves stale
  values forever. Now Settings ▸ Troubleshooting ▸ Rebuild data from providers.

**The data-export session (previous).** The export built last session was used for
the first time, and it immediately found **two defects in signals the app
already models** — not the missing signals everyone expected.

- **Oura naps were being counted as nights.** `OuraResponseParser.SleepRecord`
  never decoded `type`, so `late_nap` and `rest` segments became
  `.sleepDurationHours` — and because `bucketStatistic` *averages* same-day
  sleep, a 7.5 h night plus a 20-minute nap reached the user as a 4 h night.
  The same records also lent their **awake** heart rate to `.restingHeartRate`,
  which seven models read, and an evening nap could become the night's
  *bedtime*, because `SleepOnset` keeps the earliest segment and −4.0 h is
  inside its plausible band. Sleep, Readiness, Energy, Heart Health, Fitness and
  Blood Pressure were all downstream of it.
- **`MetricSanitizer` had no upper bound**, only `value > 0`. Now every metric
  declares a `plausibleRange`.

**The rule this establishes**: *"we don't have X" and "X looks fine" are both
claims about the code until somebody has looked at the distribution.* Nothing in
the parser looked wrong; every test passed. What gave it away was a median sleep
of 5.62 h with a minimum of 0.01 h.

Three things worth carrying:

- **A bound must reject the impossible, never the alarming.** The artefact that
  started this was a resting heart rate of 119. It was tempting to set the
  ceiling just under it — that would have been fitting the bound to one user's
  bad record, and 119 bpm is a real resting heart rate in atrial fibrillation.
  It is an artefact because of *where it came from*, not its value. The nap
  filter removes it; the bound is for values no living person produces.
- **Order matters inside a parse loop.** The nap guard was first placed after the
  bedtime was collected, so naps still poisoned sleep onset. The fix only works
  at the top of the loop.
- **Check whether a migration is needed before building one.** The plan assumed
  the corrupted history needed a wipe-and-re-sync. It does not: `sync()` always
  pulls a 730-day window, and the cache merge already replaces *all* of a
  source's samples when it returns data. The next ordinary refresh rebuilds
  Oura's history through the corrected parser on its own.

`docs/data-opportunities.md` is new: the ranked list of signals nothing reads
yet, each with the published basis for whether it can be scored honestly, plus
how Oura's own scores should be handled. **Ask for a fresh export before
building from it** — the numbers that prove the fix are the sleep-duration
median and the resting-HR maximum.

**The card-consolidation session (previous).** Three pushes, all installed:
Phase 1 of the consistency work (`42efe4c`), the data export (`0d8bc48`), and
**seventeen insight cards merged into nine** (`367e0ab`).

`docs/card-sections.md` is the audit of record and was re-derived after each.
~~**Phase 2 — the three cards still without a bespoke section — is scoped in
`docs/progress.md` and not started.**~~ **Stale twice over, corrected
2026-08-01**: all nine got a section a session later, and Phase 2 itself closed
in `dc5fae6`. Left struck through rather than deleted because this is the
narrative of a past session, and silently rewriting history is how a reader
loses the ability to trust the dates.

### What to know before touching the insight layer

- **Nine cards.** Fitness ← Cardio Fitness + Fitness Trajectory + fitness age.
  Sleep ← Sleep Quality + Sleep Debt + Sleep Regularity. Readiness ← Readiness +
  Vitals Check + Health Watch. Heart age went to the risk card (which runs those
  equations); centiles went to Heart Health (which reads those metrics);
  Resting Heart Rate and Where You Stand were deleted as cards.
- **The maths was kept.** `VO2Trajectory`, `FitnessAgeModel`, `HeartAgeAnalyser`,
  `SleepDebtModel`, `CircadianConsistencyModel`, `VitalSignsCheck`,
  `HealthWatchModel`, `PeerStandingModel` all still exist with their tests, as
  *components*. Only the wrappers and their ids went. **Do not rebuild any of
  them** — check for the model before writing one.
- **`contributions` is derived from `requirements`, not switched over
  `InsightID`.** A sixth exhaustive switch on that enum would be the most
  expensive possible way to add a feature — it is already the most frequent CI
  break here.

### Five lessons this session, in cost order

- **A protocol member with a default must still be a protocol *requirement*.**
  Callers hold `any InsightModel`; declared only in an extension, it dispatches
  statically, every model silently gets the default, and the overrides are dead
  code **that still pass their own tests** because those hold the concrete type.
  `testOverridesSurviveExistentialDispatch` is the shape of test that catches it.
- **A merge drops behaviour silently, and only the old tests know what.** Four
  real regressions were caught by tests written for the deleted cards: weight-0
  contributions counting toward "is this day well-founded" in `ScoreHistory`, the
  vitals panel leaving the overlay chart, an irregular-rhythm flag no longer
  outranking an ordinary day, and "we couldn't judge this vital" being folded in
  with the normal ones. **When merging cards, repoint the tests rather than
  deleting them** — each one is a behaviour somebody decided on.
- **Pass `now` to every component, always.** Sleep's regularity term defaulted to
  the real present, which would have flattened every replayed day of score
  history without ever erroring. `ScoreHistory.replay` hands a model a past day
  as `now`; a component that ignores it reads a window the samples don't reach.
- **`Color` has `primary`, `secondary` and `white` — but no `tertiary`.** One red
  CI. Twelve existing `x ? Theme.foo : .secondary` ternaries compile because the
  shorthand resolves to a `Color` static. **Nothing local catches this class** —
  SwiftUI does not exist on Linux, so CI alone compiles the app target.
- **Generate a wide table rather than hand-writing it.** The 17×17 matrix was
  hand-written and its column tally was wrong by one; the generated version
  caught it. A grid that big has no reviewable failure mode by eye.

### The claim that was wrong, and the rule it restates

The plan said `dayStrain` never arrived because it had an alias but no promotion
rule. **Whoop's typed parser has been emitting it as a first-class sample all
along** (`WhoopResponseParser.swift:69`) — the gap was at the *consumption* end:
no insight read it. Same shape as the bedtime that sat "blocked on a missing
signal" for several sessions while being discarded at ingest. **"We don't have
X" is a claim about the code until somebody has looked at the data** — which is
now possible, see below.

### The feedback loop that closes this class of error

**Settings ▸ Export my data.** An inventory of every signal — modelled *and* the
imported-but-unmodelled fields behind Vitals ▸ Other data — with counts, date
ranges, sources and distributions, small enough to paste into a chat. Plus a
full JSON export. `DataInventory` in InsightKit builds it and is tested there.

**Ask the user for the inventory before deciding what to build next.** Nobody
working on this app has ever seen what is actually in their Vitals tab.

**The roadmap-continuation session (previous).** "Continue with roadmap" — the
open list was read back, and the only substantial item buildable from a sandbox
was the hydration cost left over from session 11. It was recorded as needing a
product decision first; measuring it showed it did not, and the insight pass is
now 3.7× faster with no change to what the first frame knows. See "Immediate
next steps" below for the numbers and for the one part that *does* still need
the user (the cache format). Nothing in this session has been seen on the phone.

**The loading-screen session, in four rounds of user feedback.** Built the
splash, shipped a 32-second launch with it, fixed that, replaced the animation
with a live Metal particle heart, broke the user's build for four deploys, and
tuned the result against measurements of their own reference. Every single
defect was found by the user on the phone, not by CI. Read the efficiency log's
session-11 notes before the next one — this was the most expensive session
recorded.

**The one structural thing to know before touching anything:**
`ci-status.sh` proves the code *compiles on GitHub's runners*.
`deploy-status.sh` proves it *reached the phone*, and `deploy.yml` runs on the
user's own Mac. They are different questions, the second is the one that
matters, and for most of this session only the first was being asked — which is
how "deployment triggered" got said four times over failed deploys. **A push is
not an install. Run both.**

`docs/progress.md` ▸ "App-launch loading screen" has the full account; the
things worth carrying:

- **A screen that covers a wait can become a screen that causes one.** The
  splash waited for the whole of `refresh()` before revealing Today — but that
  work had *always* run behind an already-visible app, with a spinner on the
  Today card. The feature took correctly-backgrounded work and put it in front
  of the user. **When adding a gate, check what the user could already see
  without it.** It now waits on `isHydrated` — enough data to draw Today — and
  nothing else.
- **A SwiftUI launch screen cannot cover the pre-first-frame gap.** 7–8 s of the
  report was `AppModel.init` — a `@State` default, so it runs before SwiftUI
  draws anything — doing a JSON decode of ~128k samples plus all seventeen
  insights. The app was not white by choice; it had not reached its first frame.
  Only `UILaunchScreen` in `Support/Info.plist` covers that, and it was an empty
  dict, which renders plain white. **If you are asked to fix a blank screen at
  launch, find out whether the app has drawn its first frame yet.**
- **`Sendable` for testability is `Sendable` for concurrency.** Moving hydration
  off the main actor was nearly free because `HealthMetricSample`, `InsightEngine`,
  `InsightResult` and `UserHealthProfile` were already `Sendable` — built
  platform-free so InsightKit could be tested on Linux. The same property let
  them leave the main thread. `DataStore`'s four *file*-backed cache accessors
  are now `nonisolated`; the SwiftData ones cannot follow, because `mainContext`
  is main-actor by construction.
- **A timeout must not live on the thread it is timing out.** The 20 s hard
  ceiling was polled from the `@MainActor` narration loop, so it was starved by
  exactly the main-thread work it existed to protect against. The one launch
  that needed it was the one launch that could not fire it. Now it sleeps off
  the main actor and hops back only to act.

- **CI green does not mean the user's Mac can build it.** `ci.yml` runs on
  GitHub's `macos-15`; `deploy.yml` runs on the user's own Mac, and that is the
  only machine that installs anything. Adding a `.metal` file broke *their*
  build for four consecutive deploys — Xcode 26 ships the Metal compiler as a
  separately downloadable component and their Mac does not have it — while CI
  passed every time, because GitHub's image does. **Any build input that is not
  plain Swift is a place the two environments can differ.** The shader is now
  compiled at runtime with `makeLibrary(source:)`, which needs no toolchain on
  either machine.
- **The launch heart is drawn live by Metal, not played from a file.** The video
  it replaced was 608×1078 on a screen that upscales ~2.4×, with its density and
  speed baked in — and those were exactly the complaints. `LaunchParticleField`
  (InsightKit, tested) builds the cloud; `LaunchParticleView` draws it. Density,
  colour and speed are now constants, which matters because they were tuned
  three times.
- **Tune against a measurement, not against an opinion.** "Too light, not dense
  enough" was answered by measuring the user's own reference frame — ink
  coverage 30.6%, mean saturation 53.2, mean luminance 168, darkest 5% at 125 —
  and iterating the renderer until it matched (33.4 / 53.6 / 171 / 137). The
  first attempt had been washing 82% of the way to white. Same method placed the
  caption: sweeping ink coverage in horizontal bands found 1.6% at 0.58–0.63
  against 37% where the text had been sitting.
- **A semantic colour is only semantic if the surface under it is too.** The
  status line used `.secondary` on a screen that deliberately commits to a light
  background whatever the system appearance is. On a phone in dark mode that
  resolves to a *light* grey, and the copy vanished.

**Earlier in the same session**, before the regression was reported:

- **A brief's own constraint can be half of a pair, with the other half unstated.**
  The scope said the copy "must be driven by a timer rather than by real phase
  transitions, or a fast launch will flash three messages in half a second" —
  correct, and the failure it names is real. Followed literally it produces the
  opposite lie: a status line announcing "Generating insights" while the network
  request it depends on is still out. The resolution is that neither drives it —
  **the timer paces, the phase clamps** — and the invariant underneath both is
  simpler than either: nothing replaces a line before it has been on screen long
  enough to read. When a brief explains *why* a constraint exists, check whether
  the reason has a mirror image.
- **The new state is `AppModel.launchPhase`, not `isSyncing`.** The scope had
  already identified this: one flag covered the provider round-trip and the
  FoundationModels pass, and those are exactly the two waits the copy exists to
  tell apart. `refresh()` sets `.ready` in a `defer` declared *above* the
  too-soon refresh gate, so a skipped refresh still releases the screen.
- **Every floor on this screen is one that gets dropped in a refactor**, which is
  why they are all constants in InsightKit with tests rather than magic numbers
  in the view: a minimum on-screen time so a cached launch doesn't flicker, a
  hard ceiling so a stalled refresh can't trap the user, and a minimum dwell per
  line. A launch screen that never leaves is the worst outcome available here.

**The roadmap-review session** (previous). "Let's go through roadmap" — the open
list was read back, and the two items that were both open *and* buildable from a
sandbox were taken: Sleep Regularity's own chart, and sleep onset through the
promotion rules. Both shipped in `ada3b1d`. `docs/progress.md` ▸ "The
roadmap-review session" has the detail. Three things are worth carrying:

- **A guard whose comment states a premise is a place the premise can be wrong.**
  `IngestionPipeline` promoted on `field.value.doubleValue`, commented "promotion
  is numeric by definition" — true of every metric until `.sleepOnset`, which
  derives from a timestamp. The failure mode was not an error: a rule pointed at
  a text field *matched* and promoted nothing. The one-line version of that
  roadmap item (add `bedtime_start` to the alias table) would have shipped
  looking correct and done nothing. **Before adding a row to a data table, check
  that the machinery reading it can represent the new row's type.**
- **Check the field survives ingest before writing a rule for it.**
  `GenericJSONIngestor` excludes `startDateKeys` from the field sweep, and
  `bedtime_start` is one of Oura's (`start` is Whoop's). A promotion rule aimed
  at either would match nothing, forever, silently. Written down beside the
  aliases in `PromotionRules.swift`.
- **The container's local `main` is a stale, unrelated history** — see the
  section below. This cost a round trip and is now fixed in the `ship-to-main`
  skill rather than only recorded here.

### Two container traps, both of which look like success

Neither is about this codebase; both are about the environment, and both were hit
in one session.

1. **`git checkout main` silently gives you a months-old tree.** Local `main` sat
   at `87cd998` with **no merge base at all** against `origin/main` (`9f5db1d`).
   The checkout succeeds, and `docs/progress.md` comes back as a version from
   many sessions ago. `git push -u origin main` from a `claude/*` branch has the
   same root cause — it pushes that local ref rather than your work.
   **Ship with `git push origin HEAD:main`**, which never consults the local
   branch. Corrected in the `ship-to-main` skill, with the check that proves the
   push is a fast-forward.
2. **A stop hook asks you to amend every commit. It is a closed matter.**
   Settled on 2026-07-31 and **the user has asked that it not be discussed
   again** — the remedy is a no-op and acting on it would force-push `main`. The
   `ship-to-main` skill says so at the point it fires. Don't re-derive it, don't
   explain it back, don't act on it.

   The generalisable half is worth keeping, because it has now cost six round
   trips in different disguises: **verify a guard's premise against raw tool
   output before acting on its remedy.** Same shape as the `tunnelState` deploy
   guard, the Oura scope guess, and the "script is missing" report dismissed as
   stale.

### The previous session's findings, still current

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

Then a second half, driven by the user's re-read of their own feedback list and
three fresh complaints. The findings from that half:

- **The trend chip is not "vs yesterday", and that was researched rather than
  assumed.** None of Oura, Whoop, Garmin, Apple Health, Fitbit or Withings ships
  a day-over-day delta on a daily score: day-to-day HRV variability is 3–13% and
  a genuinely hard day moves it 10–20%, so the arrow would report noise most
  days and get ignored. `ScoreChange` keeps the direction and moves the
  comparison — today against the trailing week, four weeks against the quarter.
  Full reasoning and sources in `docs/progress.md` ▸ "How trend indicators are
  rendered". **If a future session is asked to "just make it vs yesterday",
  that is a one-line change and the argument above is what to put beside it.**
- **A relative threshold needs an absolute companion.** Three instances in one
  session, all the same shape — a small denominator makes anything significant.
  Blood-pressure drift is floored at ±5 mmHg (a fit through few points claimed
  *zero* uncertainty and divided by it), the substance suggestion at 3%, and
  `ScoreChange` at two points.
- **"Completed" needed no per-suggestion definition.** The engine only emits a
  suggestion while its condition holds, so vanishing from its output *is*
  resolution by whichever of the three routes. When a feature seems to need
  per-case rules, check whether the generator already encodes them.
- **A slow tap was one call doing far too much.** Logging a substance ran the
  whole engine over the whole sample set and dropped every cache. When a
  cheap-looking interaction is slow, look for the shared recompute it reuses
  rather than the work it obviously does.
- **"That technique has a fatal flaw" is not "this is impossible".** Gap bridging
  shipped straight with an argument that a curve invents an extremum. True of
  Catmull-Rom and natural cubics; mistaken for an argument against curvature. A
  monotone cubic Hermite cannot have an interior extremum at all. The gap between
  those two claims was a shipped deviation from an explicit instruction.

### What is still not done, and why

- **`EnergyModel.exertionHours` still weights every heart-rate sample equally.**
  Deliberate and commented — a watch's own sampling gaps are not idle time, and
  using real inter-sample intervals needs a decision about what a gap means.
- **`AppModel.swift` and `InsightDetailView.swift` are the two largest app-target
  files and are deliberately unsplit.** Swift's `private` is file-scoped, so an
  extension-based split widens every member the moved code touches, and both are
  dense with private state. Three files *were* split (`OAuthIntegration`,
  `AdditionalInsights`, `HeartAge`); `BloodPressureEstimator.swift` and
  `VitalSignsInsight.swift` still hold model and insight together and are the
  remaining candidates — and being InsightKit, they carry no file-private
  coupling to the view layer, so the objection above does not apply to them.
- **New provider integrations** (Hume direct, Ultrahuman, Garmin, Fitbit) need
  the user's own developer credentials per provider and cannot be tested from
  here at all. Same for the VisionKit scanner and ECG import — device-only
  surfaces with no test path.
- ~~**On-device verification of everything since the last device-verified
  build.**~~ **Closed 2026-08-01**: twelve pushes this session, every one
  reported `installed` by `deploy-status.sh`, and eight rounds of the user
  reading the result on the phone and saying what was wrong. That loop is the
  reason this session found things CI cannot see.
- ~~**Filled `AreaMark` min/max bands** want a compile spike.~~ **Resolved
  2026-08-01**: `BodyCompositionTrendChart` ships `AreaMark(x:yStart:yEnd:)` for
  the water film and it draws correctly. The one real catch is that the overload
  takes **no `stacking:` argument** — an absolute band between two heights is
  inherently unstacked — which is a compile error, not a silent one. Recorded in
  the `add-chart` skill.
- **Oura's ~4–6 months of history** is still unexplained. Offered, not taken up.
- **The LiDAR body scan** is still open by request — explicitly a roadmap note
  rather than a build, and scoped in `docs/progress.md`. The app-launch loading
  screen that sat beside it is **done**; see "Current focus".
- **The open efficiency-roadmap items are now these** — the two this line used to
  name (`symbol-index.md` as a reflex, a session-start checklist skill) were both
  built sessions ago as `scripts/where.sh` and `.claude/skills/session-start/`,
  and this bullet had gone stale claiming otherwise. **Also now closed:** reading
  a red CI cheaply, built 2026-08-01 as `refs/ci/errors/<sha>` +
  `scripts/ci-errors.sh`. Currently open, top first:
  - **A `PreToolUse` hook that normalises the shell's working directory** (top
    item, raised again session 16). **Four** consecutive sessions have lost round
    trips to it, five in this one alone, *while the rule sits in `CLAUDE.md` in
    the plainest words available* — so the rule is not the fix. Session 16 also
    identified the mechanism precisely: the Bash tool's cwd **persists between
    calls**, so a single `cd InsightKit && swift test` silently relocates every
    later relative path. Two candidate fixes, and the second is smaller than the
    first: reject relative `scripts/…` invocations, or prepend `cd <repo root>`
    to every `Bash` call. Still not built, for the same reason: it changes
    `.claude/settings.json`, which is the user's harness config, so **ask before
    adding it**.
  - A build-environment parity check between CI and the user's Mac — the item
    that cost four deploys.
  - *Read the composited pixel before choosing another colour* (session 14's
    most expensive lesson).
  - Never `git add -A` inside a canary.
  - The false-premise guard category, now at six and probably still human. The
    one generalisable half found in session 15: **make a guard enumerate its own
    failure modes** rather than assert the one its author thought of.
  - A *"blocked on a decision" note should carry the measurement that proves the
    tradeoff is real*.

  See `docs/efficiency-log.md`, which is the authority.

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

- **One quantity drawn over another is a hatch, never a blend.** This is the
  standing approach — `Theme.hatch(light:dark:_:)`, worked example in
  `BodyCompositionTrendChart`. A translucent fill *mixes*, and the mix is a third
  colour that means nothing and is frequently nowhere near either parent: blue
  over red is purple at every ratio, because it is colour arithmetic rather than
  a tuning problem. A hatch keeps both colours because every pixel is one of
  them. Two corollaries earned the hard way: **draw the host band whole and paint
  over it** — carving the overlaid share out as its own slice removes the host's
  colour from that stretch, so nothing reads as underneath and no hue can fix it —
  and **the overlaid quantity contributes no mass to the stack**, so it wants an
  `AreaMark(x:yStart:yEnd:)` between two cumulative heights, with the span
  computed in InsightKit where it is testable.
- **When a colour looks wrong, measure the composited pixel before choosing
  another one.** Five rounds went into the water colour by eye; the measurement
  (rgb 126, 88, 121 — red and blue near-equal, green suppressed) named the cause
  in one step. Generalised: when a visual fix keeps landing in the same wrong
  place, check whether the mechanism can produce the target at all before picking
  another value for it.

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
`#if canImport(Darwin)`. **The full suite passes on Swift 6.0.3 / Ubuntu 24.04** — `swift test` prints the count, so it is not repeated here to rot.

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

- `MetricType` — **eight** switches: `displayName`, `unit` (both in
  `MetricType.swift`),
  **`family`**, **`chartStyleIndex`**, `presentation`, `maxValidInterval` (all
  four in `MetricPresentation.swift`), **`referenceRange`** (also
  `MetricPresentation.swift` — usually `nil`, and the case must say *why*;
  `.sleepOnset` is the worked example), `requiresPositiveValue`
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
  `colourSlot` (`Presentation/InsightPalette.swift` — *not* `insightTint` in
  `Theme.swift`, which now resolves through it). **Four of the five are
  exhaustive and break the build**: `modelVersion`, `prettyInsight`, `iconName`,
  `colourSlot`. Only `cadence` carries a `default:`, and it fails *silently* by
  putting the card on the wrong tab. Plus registration in `InsightEngine`, which
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

**Hydration was ~12 s on the user's data. The insight half of it is now 3.7×
faster, and the question this section used to ask does not need asking.**

It said a decision was needed first — whole history, or a recent window with the
rest loaded behind Today? — because every cheap fix was assumed to change what
the first frame knows. **That premise was wrong, and measuring it is what showed
so.** The cost was never the *volume* of data. It was the same work done over
and over: `MultiSource.breakdown` filtered all ~130k samples and sorted the
result on every call, `Array.samples(of:)` did the same, and both were called
once per metric *per insight model* — resting heart rate is read by seven of the
seventeen. Nothing about that work varies between the models.

So there was no tradeoff to put to the user. Fixed with three semantics-
preserving changes, all in InsightKit, all covered by `EvaluationMemoTests`:

- **`EvaluationMemo`, scoped to one evaluation pass** (`MultiSource.withMemo`,
  opened by `InsightEngine.evaluateAll` and `result(for:)`). Memoises
  `breakdown`, `Array.samples(of:)` and the per-source daily buckets. It is a
  `@TaskLocal`, so it lives exactly as long as the evaluation and can never go
  stale against changed data.
- **The day-bucket reuse in `SourceSeries.bucketed`.** It asked
  `Calendar.dateInterval(of:for:)` once per sample — ~400 ms of a ~470 ms
  heart-rate read. Series arrive sorted, so it now holds the previous reading's
  interval and reuses it while the next reading still falls inside.
- **The redundant re-sort in `breakdown`** — `deduplicate` already returns
  oldest → newest and `Dictionary(grouping:)` preserves that order, so each
  group was being re-sorted for nothing (78k elements, for heart rate).

Measured on a synthetic 131,400-sample / 24.7 MB set, the same benchmark either
side of the change (x86 Linux, so read the *ratios*, not the absolutes):

| stage | before | after |
| --- | --- | --- |
| `loadCachedSamples` (JSON decode) | 1002 ms | 1002 ms |
| `sanitizedVitals` + temperature | 21 ms | 19 ms |
| `evaluateAll` (17 models) | 1774 ms | **476 ms** |
| total | 2796 ms | **1564 ms** |

**Two things to carry, and one thing left.**

- **"This needs a product decision" is a claim about the implementation, and it
  can be wrong.** Exactly the shape of "no provider gives us a bedtime": a
  tradeoff recorded as inherent turned out to be an artefact of how the code was
  written. Measure before escalating a decision to the user.
- **The memo's identity check is sound, not a fingerprint.** It holds a strong
  reference to the array it was opened for, so that buffer cannot be freed while
  the memo lives, so no *other* live array can be handed its base address. Equal
  base address and equal count therefore means the same buffer, and by
  copy-on-write the same contents. Anything else misses and is computed the long
  way. `testMemoDoesNotAnswerForADifferentArray` and
  `testEqualLengthCopyIsNotTreatedAsTheSameArray` pin it.

~~**What is left is the decode, and it is now 68% of the remaining time.**~~
**Done 2026-08-01 (`c0028f2`, installed)** — the user's "work on load
performance" was the ask this note said to wait for. `SampleCacheCodec`
(InsightKit, 10 tests) interns the source and type tables and writes a fixed
28-byte record per sample; `DataStore.loadCachedSamples` tries it first and
falls back to the legacy JSON, which the next save retires, so migration is
free and one-way. Decode went **965 ms → 4–6 ms** on the benchmark shape
(file 19.6 MB → 2.9 MB). The finding worth carrying: after the byte-level fix
the decode was *still* ~145 ms, and all of it was `UUID()` — 108k syscall-fed
random ids for a field whose identity nothing needs across launches. Ids are
now one random base per decode plus a counter. **When a fix lands and the
cost stays, measure what replaced it.** The old note's dead end stands:
`PropertyListEncoder(.binary)` is slower than JSON here (2190 ms vs 1026 ms).
`synced_other.json` stays JSON — unmeasured, so deliberately untouched.

The ten-item feedback list is closed and so is every roadmap item that could be
closed from a sandbox. What remains falls into three groups.

### 1. Only the user can do these

- **The on-device walkthrough.** The launch screen and Insights *have* now been
  seen and reported on — that is how every defect in session 11 was found. The
  older items below still have not. Newest first:
  - **Cold launch — time it, and this is the one still genuinely unknown.**
    Confirmed already, from the user's own screenshots: no white screen, the
    heart draws, the animation is smooth, Insights no longer freezes. What has
    *not* been confirmed since the last three changes is the timing.
    From tapping the icon: flat `#D9D9D9` (that is `UILaunchScreen`, before any
    code), then the heart — dense rose mist, drifting slowly, ring framing the
    screen — then Today, populated, with the sync spinner still turning.
    **A sync finishing after Today appears is correct now, not a bug.**
    The negatives are the ones worth the trouble: **background the app and
    return — the splash must not come back**; a first-run install must go
    straight to onboarding with no splash; the status line must not strobe; and
    the heart must not flash at the wrong size on the handover from the static
    launch screen (it did, at 3×, when the poster was in the asset catalog's 1x
    slot — hence colour-only now).
    Past ~4 s the copy should change register entirely ("Still going — that's a
    lot of history to read"), and nothing should hold the screen past 8 s.
  - **If the launch screen is a plain grey rectangle with text and no heart**,
    the Metal shader compiled on CI but failed at runtime on the device. It
    logs to Settings ▸ Troubleshooting rather than failing silently — that is
    the first place to look, and it is the one part of the renderer no test
    here can reach.
  - **Insights ▸ Sleep Regularity ▸ "Your fortnight"** — a new chart above the
    score history. Points are the nights, the dashed line is the usual bedtime,
    the shaded band is the spread. Check the y axis reads **clock times** and not
    bare numbers (a "−1.5" there is the signed-hours encoding leaking); that
    weekend nights are squares and weekdays circles; that the night the card
    names as "furthest out" is the enlarged point; and that a second dashed line
    appears only when there is a real weekend shift.
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
- ~~Filled `AreaMark` min/max bands still want a compile spike.~~ Done — see
  above; `AreaMark(x:yStart:yEnd:)` ships in `BodyCompositionTrendChart`.
- `.sleepOnset` resolves against `Calendar.current`, not the offset the provider
  stamped. Right at home, wrong on the second night of a trip. Both HealthKit and
  Oura behave the same way, so the sources at least agree with each other.

### 3. The ten-item feedback list — five of the six deltas are closed

The six open clauses found by re-reading the list are now closed, bar the LiDAR
body scan, which is a roadmap note by request rather than a build. What is worth
carrying forward:

- **"That technique has a fatal flaw" is not "this is impossible".** Gap
  bridging shipped straight rather than smoothed, with a written argument that a
  curve invents a local extremum where nothing was measured. The argument is
  correct about Catmull-Rom and natural cubics and was mistaken for an argument
  against curvature. A monotone cubic Hermite (Fritsch–Carlson / PCHIP) cannot
  have an interior extremum at all, which is exactly the missing guarantee. The
  gap between those two claims was a shipped deviation from an explicit
  instruction.
- **A relative threshold needs an absolute companion.** This bit three times in
  one session, each time the same shape: a small denominator makes anything
  significant. Blood-pressure drift floored at ±5 mmHg because a fit through a
  handful of points claimed zero uncertainty; the substance suggestion floored
  at 3% because a tight set of clean nights makes a fifth of a bpm clear half a
  standard deviation; `ScoreChange` floored at two points for the same reason.
- **"Completed" did not need defining per suggestion.** Three bases would have
  needed three different answers. None was necessary — the engine only emits a
  suggestion while its condition holds, so disappearing from its output *is*
  resolution, by whichever route. When a feature seems to need per-case rules,
  check whether the generator already encodes them.
- **The trend indicator is not "vs yesterday", and that was researched.** Nobody
  ships it: day-to-day HRV noise (3–13%) swamps what one night changes. See
  `docs/progress.md` ▸ "How trend indicators are rendered".
- **A slow tap was one call doing far too much.** Logging a substance ran the
  whole insight engine over the whole sample set and dropped every cache. When a
  cheap-looking interaction is slow, look for the shared recompute it is reusing
  rather than for the work it obviously does.

### 4. What the six deltas turned into

Re-reading the ten-item feedback list against the code found six clauses still
open, each sitting *inside* an item whose headline was true — which is why none
was visible from the record. **Five are now closed; one is parked deliberately,
and a seventh was added by the user.**

| # | Clause | State |
| --- | --- | --- |
| 1 | Suggestion lifecycle — dismissible, on Today, pinned/collapsible on Insights, hidden once resolved | ✅ |
| 2 | Smoothed predicted values across gaps | ✅ monotone cubic, both charts |
| 3 | Blood-pressure drift counter | ✅ held-out, floored at ±5 mmHg |
| 4 | Sleep Quality's remaining Oura/Whoop/Apple inputs | ✅ efficiency, deep, REM |
| 5 | Substance log as a general data source | ✅ feeds the suggestion engine |
| 6 | Camera + LiDAR guided body scan | ⬜ roadmap note by request, scoped in `progress.md` |
| 7 | App-launch loading screen | ✅ `LaunchScreen` + tested `LaunchNarration` |

Plus three direct complaints, all fixed: the substance log page's lag (one call
running the whole engine over the whole sample set), the date picker hidden
behind a long-press, and an edit button under the minimum tap target.

**Lesson worth keeping: a multi-clause item marked `[x]` hides its unfinished
clauses.** Every one of the six sat inside an item whose headline was true. When
a feedback line has an "and also" in it, record the clauses separately.

### 5. Genuinely open work, cheapest first

The two cheapest items here — Sleep Regularity's own chart, and sleep onset
through the promotion rules — **are done**; see `docs/progress.md` ▸ "The
roadmap-review session". Two findings from them are worth carrying:

- **A guard whose comment states a premise is a place the premise can be wrong.**
  `IngestionPipeline` promoted on `field.value.doubleValue`, commented "promotion
  is numeric by definition". That was true of every metric until `.sleepOnset`,
  which derives from a timestamp — and the failure mode was not an error but a
  rule that matched and promoted nothing. The one-line version of the roadmap
  item (add `bedtime_start` to the alias table) would have shipped looking
  correct. **When adding a row to a data table, check that the machinery reading
  it can represent the new row's type.**
- **Check whether the field survives ingest before writing a rule for it.**
  `GenericJSONIngestor` excludes `startDateKeys` from the field sweep, and
  `bedtime_start` is one of Oura's. A promotion rule aimed at it would match
  nothing forever, silently. Recorded in `PromotionRules.swift` beside the
  aliases.

Still open:

- **Foundation Models structured extraction for arbitrary lab analytes**, and the
  VisionKit live scanner. Both are on the roadmap and both are device surfaces
  with no test path from here.
- **Core ML personal anomaly detection**, once there is enough history.


