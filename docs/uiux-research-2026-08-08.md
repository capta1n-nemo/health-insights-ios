# UI/UX this app should adopt — 2026-08-08 (R60)

<!-- status: complete — UI/UX patterns this app should adopt, every count read out of the worktree -->

**Research only.** No code was written and no shared file was edited. Nothing here
is scheduled or promised; a future session must deliberately promote anything it
wants to build into `docs/backlog.md`.

Every count, file path and line number below was read out of this worktree at
`2029b14` on 2026-08-08. Every API availability was read out of the installed
`iPhoneOS26.2.sdk` `.swiftinterface`, not from memory. Every citation carries
author, year, venue and — where the paper reports one — *n* and the effect. Where
no evidence exists I say so; **"no published curve exists for this" is a finding
and appears several times below.**

---

## 0. What is NEW here, against `docs/uiux-research-2026-08-06.md`

Read that file first. It is 68 lines, and **almost all of it is a recovery note
rather than research**: nineteen agents ran, the synthesis was truncated in
transit, and only the tail survived. What it actually delivers is:

| `uiux-research-2026-08-06.md` delivers | Status |
|---|---|
| A list of the eighteen surfaces the lost fleet covered | Index only, no findings |
| The reference apps and product voice those agents were given | Context, no findings |
| A pointer to `journal.jsonl` where the per-agent findings still sit | Recovery instruction |
| **One intact finding**: warm launches should skip the animated splash — invert `minimumOnScreen` (`LaunchNarration.swift:84`), mount `LaunchScreen` only after a ~300 ms grace | The only substantive design conclusion in the file |
| A warning that its top-20 ranking was a suggestion, not a commitment | Caveat |

**So the topic is, as the brief says, effectively uncovered.** Everything in
§2–§8 of this document is new. I have deliberately **not** re-derived the splash
finding, and I have **not** re-run or re-read the lost fleet — that journal is
still the cheapest way to recover the other eighteen surfaces and this document
does not replace it.

The one place I overlap is *loading and empty states*, and I approach it from a
different direction: 2026-08-06 asked "how long should the splash be", this asks
"what does a screen say when the app has decided not to tell you something".
Those do not collide.

**What this document adds that no doc in `docs/` currently holds:**

1. A single named pattern behind the reader's eight most recent UI complaints (§2).
2. An SDK-verified inventory of what iOS 26 offers this app, with the cost of the
   iOS 18 deployment floor stated (§3).
3. A disclosure model sized against this app's real cardinality — 18 cards ×
   16 sections, 78 `MetricType`, 19 `DataDomain`, 23 `InputKind` (§4).
4. **The uncertainty section (§5), which is the substantive contribution.** It
   identifies a live inferential-vs-outcome confusion in the code, and the
   experiment that quantifies what it costs.
5. Ten prioritised recommendations with surfaces and costs (§8).

---

## 1. What was measured, so nothing below is guessed

Counted from this worktree, 2026-08-08:

| Thing | Count | Where |
|---|---|---|
| Insight cards | 18 | `docs/card-sections.md` §1; one file renders all of them |
| Sections in a card's fixed sequence | 16 | `card-sections.md` §1 order table |
| `MetricType` cases | 78 | `InsightKit/Sources/InsightKit/Models/MetricType.swift` |
| `MetricDataCategory` cases | 7 (**6 rendered**) | `MetricDataCategory.swift:20–48` |
| `DataDomain` cases | 19 | `Presentation/DataDomain.swift` |
| `InputKind` cases | 23 | `Presentation/InputKind.swift` |
| `DataTabView.swift` | 1,769 lines | `Features/Data/DataTabView.swift` |
| Files using a `Material` background | 6 | `ultraThinMaterial` / `regularMaterial` |
| Files using `glassEffect` / `GlassEffectContainer` | **0** | — |
| `ConfidenceBadge` render sites | **2** | `DashboardView.swift:350`, `InsightDetailView.swift:788` |
| `ScoreDial` render sites | 2 | `DashboardView.swift:339` (72 pt), `InsightDetailView.swift:780` (96 pt) |
| Deployment target | **iOS 18.0** | `project.pbxproj:233` |
| Installed SDK | iPhoneOS 26.2, Xcode 26.3 (17C529) | `xcodebuild -version` |

⚠️ **A free finding while counting.** `MetricDataCategory.listed`'s doc comment
(`:45`) says *"The four groups the Data tab actually renders"*. There are **six**
— `nutrition` and `hearing` were added and the prose was not. Same class as the
`add-metric-type` skill's "no count here on purpose"; one-line fix, not worth its
own backlog row, but worth doing on the next touch of that file.

⚠️ **I could not count rows in the last 90 days.** The standing rule — *before
writing "already arriving" about a source, count its rows* — cannot be honoured
from a worktree: the reader's data lives on the device and in `~/HealthSeed`, not
in the repo. **So this document makes no claim anywhere that any source is
already arriving.** Where volume matters (the raw-field catalogue in §4) I say
what the code structurally guarantees, not what has landed.

---

## 2. The pattern in the reader's complaints — the most useful thing in this document

Eight complaints, gathered from `docs/backlog.md` §B13–§B17, `D27`, `D29`, `D53`:

| Row | The reader's complaint |
|---|---|
| `D53` | *"When you click the '+' button, it gets cut off and you have to scroll… why cut it short if you don't need to?"* |
| `B15-1` | steady state read `= no change =`; must read **"Stable"**, grey, flat arrow |
| `B15-2` | the fourth state, **"Learning trends"**, was not rendered at all |
| `B14` | a `>` on **every** card and every clickable section, including the small Today tiles |
| `B17` | the score bubble held the score *and* the sub-menu text, and *"often that sub menu text goes outside the bubble boundary and breaks the effect"* |
| `B16-2` | subtitle is **words only, no numbers** — *"10 · Drained"* should be *"Drained"* |
| `B13-1` | panning a chart off its data made the header **disappear** and the view **violently jump to the top** |
| `D29` / `D27` | the Data tab is *"dozens of screens of scroll"* with search the only fast path; raw rows render metadata as measurements (*"How it was measured — 0"*, *"Device model ID — 16"*) |

These read as eight unrelated chrome bugs. They are one bug, made eight times.

### The pattern: **the view is a direct projection of the model, and it inherits everything the model has — including its cardinality, its `nil`s, its field set and its arithmetic.**

Take them one at a time and the same sentence falls out:

- **`D53`, the `+` menu.** The master add list is *generated from `InputKind`*.
  `InputKind` had 9 cases when the sheet was sized and has **23** now
  (`AddInputPicker.swift:76` still pins `.presentationDetents([.large])`). The
  container was sized against a snapshot of an enum that grows. **Model
  cardinality met fixed geometry.**
- **`B17`, the score bubble.** A circle of fixed diameter was asked to hold two
  strings of unbounded length. **Model text met fixed geometry.** Same sentence.
- **`B15-2`, "Learning trends".** `AppModel.scoreChange(for:)` returned
  `ScoreChange?` and `DashboardView` was an `if let` **with no `else`**. The
  `nil` was doing three jobs — *no history*, *history but today unscored*,
  *history but not enough*. **A model absence rendered as a screen absence**, and
  the reader could not tell a card that is learning from a card that has given up.
- **`B13-1`, the vanishing header.** The same `if let` again, and the post-fix
  rationale at `MetricViewStrategy.swift:44–56` is the best description of the
  class anywhere in the repo: `visibleRange` is page-level `@State` fed **on
  every pan frame**, so `if let summary { Card { … } }` *"deleted ~110pt of
  content height while the finger was still down"*, the `ScrollView` clamped its
  offset to the shorter content, and the chart was yanked out from under the
  drag. **Identical to `B15-2`, one screen over** — same `if let`, no `else` —
  except that here the absence moved everything else on the page too. (The
  backlog cites `:120`; the fix has since moved it to `:195`, and the doc comment
  above it is now the authority.)
- **`B15-1`, `= no change =`.** The chip printed the *arithmetic* — the delta was
  below threshold — where a *finding* belonged. `ScoreChange.swift:99–106` now
  says this in the code: *"The old string described the arithmetic … and so read
  as an absence sitting where a finding should be."* **The model's internal
  vocabulary leaked into the reader's sentence.**
- **`B16-2`, "10 · Drained".** The Energy card's headline was built as
  `"\(Int(output.level.rounded())) · \(output.band)"` — the model's own level
  interpolated straight into the reader's line. **The model's number leaked into
  a human label**, and `B16-2` records it as the *only* such interpolation in
  InsightKit: one author did it once and nothing stopped them. (Fixed; the
  backlog's `Energy.swift:538` no longer points at it, which is why the quote and
  not the line is cited here.)
- **`D27`, metadata as measurements.** The raw catalogue renders every stored
  field with the same row. `HKMetadataKeyWasUserEntered` and a systolic reading
  are the same shape in the store, so they are the same shape on screen. **The
  storage schema became the presentation schema.**
- **`D29`, the Data tab's length.** `DataTabView.swift:56–57` builds its sections
  from `MetricDataCategory.listed.map { ($0, MetricType.metrics(in: $0)) }` —
  deliberately, and the comment explains why (a hand-written array had already
  dropped two real metrics). But it means **the navigation structure *is* the
  enum**: 6 sections, 75 grouped metrics, 19 `DataDomain` pages, plus every raw
  field the ledger has ever seen. Growth in the model is growth in the scroll.
- **`B14`, the missing chevrons.** The narrowest of the eight and still the same
  shape. Every `NavigationLink` *inside a `List`* got the disclosure chevron free
  from UIKit; `InsightCard` and the five `VitalsGlance` tiles are
  `NavigationLink`s **outside** a `List`, so they got nothing. The affordance was
  never authored — it was **inherited from a container**, and two views did not
  have that container. `DashboardView.swift:272–280` now says exactly this in a
  comment.

### Three laws, and why naming them is worth more than fixing eight bugs

**Law 1 — A generated set will outgrow any container sized by hand.**
`InputKind`, `DataDomain`, `MetricType` and `InsightID` are all `CaseIterable`
and all still growing. Every surface that renders one *must* be able to say what
it does at 2× its current size. A `.large` detent is not an answer; it is a
snapshot.

**Law 2 — `Optional` is not a state, but a view renders it as one.**
Every `if let` over a model value in a view is a design decision made by
omission. This app has already paid for it twice (`B15-2`, `B13-1`) and has
already invented the correct fix twice — `ScoreChangeState`
(`ScoreChange.swift:132–184`, a total enum where every case carries its own copy)
and `CoverageGate` (`CoverageGate.swift`, a type a model cannot withhold a figure
without producing). **The fix exists; it has not been generalised.**

**Law 3 — Everything the model knows reaches the screen unless a layer stops it.**
Numbers into subtitles (`B16-2`), arithmetic into findings (`B15-1`), metadata
into measurements (`D27`), storage identifiers into row titles. There is no
presentation layer between the store and the row — `DataDomain` guarantees a
thing is *seen*, and nothing guarantees it is seen *as the right kind of thing*.

### The leverage, stated plainly

This project already knows how to solve exactly this class. `DataDomain`,
`InputKind`, `MetricType` and the eleven `verify.sh` exhaustive-switch checks
exist because *"make sure" cannot mean "remember"* (`InputKind.swift:18`). That
discipline was applied to **the data layer** and stops at the boundary of the
app target.

> **The single highest-leverage recommendation in this document: extend the
> enum-plus-lint discipline from the data layer into the presentation layer.**
> `DataDomain` guarantees a new domain is rendered; nothing guarantees it stays
> *findable*. `InputKind` guarantees a new input is offered; nothing guarantees
> the menu still fits. `ScoreChangeState` guarantees one card's absence has
> words; nothing guarantees the next one will.

Concretely, §8 recommendations 1, 4, 5, 7 and 9 are all this one idea applied to
five surfaces.

---

## 3. The HIG and iOS 26: what is genuinely new and worth adopting

### 3.1 A caveat about sourcing

Apple's HIG is a JavaScript-rendered site; a plain fetch returns only the page
title. I retrieved the underlying `…/tutorials/data/design/human-interface-guidelines/<page>.json`
documents, which carry the real prose, and I quote only from those. **Where I
could not retrieve a page, I say so rather than paraphrasing from memory.** API
availability below is stronger evidence than any doc page: it was read from the
installed SDK's `.swiftinterface`, with line numbers.

### 3.2 What Apple actually says that bears on this app

From `charting-data.json`:

> "Keep a chart simple, letting people choose when they want additional details.
> Resist the temptation to pack as much data as possible into a chart."

> "Match the size of a chart to its functionality, topic, and level of detail…
> you might want to use a small chart to offer glanceable information about an
> individual item or to provide a snapshot or preview of a larger version of the
> chart that people can reveal in a different view."

From `charts.json`:

> "Let people interact with the data when it makes sense, but don't require
> interaction to reveal critical information."

> "Avoid relying solely on color to differentiate between different pieces of
> data or communicate essential information in a chart… One way to supplement
> color is to use different shapes or patterns to depict different parts of
> data."

> "Avoid using subjective terms. Subjective words — like rapidly, gradually, and
> almost — communicate your interpretation of the data. To help people form their
> own interpretations, use actual values in your descriptions."

> "Consider expanding the hit target to include the entire plot area, letting
> people scrub across the area to reveal various values."

From `loading.json`:

> "If you make people wait for loading to complete before displaying anything,
> they can interpret the lack of content as a problem with your app or game.
> Instead, consider showing placeholder text, graphics, or animations as content
> loads."

**Two of these are directly load-bearing for this repo.**

*First*, the accessibility-label rule ("use actual values") is in **productive
tension** with the reader's `B16-2` ("subtitle: words only, no numbers"), and the
resolution is clean rather than a conflict: **the visible subtitle drops the
number and the VoiceOver label keeps it.** They are different channels answering
different questions — the visible line is a glance, the spoken line is the whole
readout. `docs/accessibility-research-2026-08-07.md` establishes that 17 of 18
`*Chart.swift` files carry zero accessibility code, so this costs nothing today
and would be free to get right when that work lands.

*Second*, "avoid relying solely on color" indicts a specific pair of call sites —
see §5.3.

**And what Apple does not say.** I checked `charting-data` and `charts` for
guidance on uncertainty, estimated values, incomplete series or withheld figures.
**There is none.** The HIG has nothing to say about the central design problem of
this app. That is a finding, not a gap in my search: this app is operating past
the end of the platform's own guidance, and §5 is therefore built from the
research literature rather than from Apple.

### 3.3 iOS 26 APIs, verified in the SDK, with the deployment-floor cost

The target is **iOS 18.0** (`project.pbxproj:233`). Everything marked iOS 26
below needs `if #available(iOS 26, *)` and a maintained fallback — which is the
real cost, not the API call.

| API | Availability (from `.swiftinterface`) | Worth adopting here? |
|---|---|---|
| `View.glassEffect(_:in:)` | iOS 26.0 — `SwiftUICore …:2603` | **Defer.** See below. |
| `GlassEffectContainer` | iOS 26.0 — `SwiftUICore …:9168` | Defer |
| `glassEffectID(_:in:)`, `glassEffectUnion`, `glassEffectTransition` | iOS 26.0 — `:17668`, `:10034`, `:2939` | Defer |
| `GlassButtonStyle` | iOS 26.0 — `SwiftUI …:1325` | Low value; the app has few standalone buttons |
| `View.tabBarMinimizeBehavior(_:)` | iOS 26.0 — `SwiftUI …:9005` | **Yes** — see rec. 10 |
| `View.scrollEdgeEffectStyle(_:for:)` / `scrollEdgeEffectHidden` | iOS 26.0 — `:12441`, `:12446` | Situational; useful under the pinned timeframe picker |
| `View.backgroundExtensionEffect()` | iOS 26.0 — `:12364` | No — no edge-to-edge media here |
| `View.searchToolbarBehavior(_:)` | iOS 26.0 — `:20008` | **Yes, for the Data tab** — see rec. 6 |
| `View.presentationSizing(_:)` + `FittedPresentationSizing` | **iOS 18.0** — `SwiftUI …:11057–11059`, `:11048` | **Yes, today, no availability check** — see rec. 4 |
| `View.chartGesture(_:)` | iOS 17.0 — `Charts …:3236` | Already usable |
| `chartScrollableAxes` / `chartXVisibleDomain` / `chartScrollPosition(x:)` / `chartScrollTargetBehavior` | iOS 17.0 — `Charts …:1214–1228` | Already usable; relevant to `B13-2`'s edge affordances |
| `Chart3D` / `Chart3DContent` | iOS 26.0 — `Charts …:378`, `:415` | **No.** The `add-chart` skill already documents the overload hazard this creates |
| `AreaPlot` / `LinePlot` (function plotting) | `Charts …:2034`, `:2188` | Marginal — this app plots samples, not functions |

**On Liquid Glass specifically: my recommendation is to deliberately not adopt
it, and to write that decision down.** The reasoning is not conservatism:

- The app has **zero** `glassEffect` sites and **six** `Material` sites, so there
  is no half-migrated state to finish.
- Glass is a *legibility-cost* material: it earns its keep on controls floating
  over photography or video. This app's floating layer sits over **charts** —
  thin strokes, dashed "inferred" lines, hatched overlap (`add-chart`'s
  hatch-never-blend rule), and the substance shading that every chart carries by
  law. Those are exactly the marks a refractive material degrades.
- `docs/accessibility-research-2026-08-07.md` measured **zero**
  `accessibilityReduceTransparency` handling anywhere in the app. Adopting glass
  without it would ship a regression to the reader who has that switch on.

The two iOS 26 APIs I *would* take are `tabBarMinimizeBehavior` and
`searchToolbarBehavior`, because both give back vertical space on the two screens
that have too little of it, and neither touches how a chart renders.

---

## 4. Progressive disclosure at this app's actual scale

The numbers again: **18 cards × 16 sections ≈ 288 section instances**, gated down
per card; **75 grouped metrics in 6 Data-tab sections**; **19 `DataDomain` detail
pages**; **23 `InputKind` entries in one `+` sheet**; plus a raw-field catalogue
whose size is set by the reader's connectors and which I cannot count from here.

### 4.1 The evidence on depth vs breadth, and what it forbids

**Landauer & Nachbar (1985), CHI '85, pp. 73–78** — "Selection from alphabetic
and numeric menu trees using a touch screen: breadth, depth, and width" — found
per-screen response time fits `T = k + c·log b` (b = branching factor), in
agreement with the Hick–Hyman law for decision time and Fitts' law for movement.
**Because the per-screen cost grows only logarithmically in breadth but the
number of screens grows linearly in depth, the total favours broad and shallow.**
The result has been replicated across four decades of menu studies.

**What this forbids, for this app specifically:** the obvious fix for a long Data
tab — nest the raw fields two levels down behind a "Raw data" hub — is the wrong
direction. It converts a scrolling cost (cheap, and skimmable in parallel) into a
sequence of decisions (each one a `log b` charge plus a navigation animation plus
a lost place). `D29`'s own note already gestures at the right answer: *"collapsed
groups, or an index."* **An index is breadth-preserving. A submenu is not.**

### 4.2 The three disclosure questions this app conflates

Progressive disclosure is usually discussed as one mechanism. This app needs
three, and currently uses one control (`InsightSection`'s
`chevron.down`/`chevron.up`, `InsightSection.swift:172`) for all three:

1. **"Is there anything here?"** — should this section exist on this card at all.
   Answered today by gates, correctly, and documented in `card-sections.md`'s
   gate table.
2. **"Is there anything *new* here?"** — should it arrive open or closed. Today
   this is a per-section constant. **It should be a function of the content.**
   A section whose figure has not moved past its own noise floor is exactly the
   section that should arrive closed; a section carrying a departure is exactly
   the one that should arrive open. The app already computes the distinction —
   `ScoreChange.standardisedDelta` against `dailyThreshold`/`trendThreshold`, and
   `InsightDriver` carries "whether the line is worth looking at"
   (`Insight.swift:239–246`, written because Vitals Check scans seventeen signals
   and sixteen say "normal"). **The signal exists and disclosure does not read
   it.**
3. **"Do I want the working?"** — the deep dive. Section 8 ("How this is
   weighted") is explicitly this. It is correctly placed and correctly closed.

Conflating (2) and (3) is what makes a 16-section card feel like a wall: a reader
opening a card cannot tell "closed because it's machinery" from "closed because
nothing happened", and both look like "closed because I have to check".

### 4.3 What the reader's own rules already imply

The reader has stated two rules that pull against each other and both are right:

- *"every card should show, even if it hasn't got data yet"* (2026-08-05) and
  *"when a new data field is discovered, create a data section for it every time,
  even if we do not yet have data"* (2026-08-06) — quoted at
  `DataTabView.swift:90–93`.
- *"the Data tab has grown very long"* (`D29`).

These are only in conflict if *presence* and *prominence* are the same thing.
They need not be. **Everything stays present and findable; not everything stays
at the same weight.** The mechanism that satisfies both is an index plus
persistent ordering — never a filter, never a hidden section, and never a "show
more" that changes what exists.

---

## 5. Communicating uncertainty visually — the hardest problem, and where the app is wrong today

This is the app's identity. It is also the section where the literature is
strongest and where I found a live defect.

### 5.1 What the app does today, measured

| Mechanism | Where | Assessment |
|---|---|---|
| `InsightConfidence` — 4-level ordinal enum (`high`/`moderate`/`low`/`experimental`) | `Insight.swift:203–208` | The app's **only** structured uncertainty type |
| `ConfidenceBadge` — coloured word pill ("Validated" / "Estimate" / "Needs data" / "Experimental") | `Theme.swift:407–426` | **2 render sites total** |
| `CoverageGate` — "4 of 7 scored days so far — 3 more and …" | `CoverageGate.swift` | Excellent, and the model of what the rest should be |
| `±` stated in prose | ~10 sites, e.g. `BloodPressureEstimator.swift:895`, `InsightDetailView.swift:2362` (`"±%.0f years"`) | Honest, but text-only |
| Shaded interval bands on charts | 7 chart files, e.g. `FitnessProjectionChart.swift:137`, `SleepOnsetChart.swift:134`, `SettlingSection.swift:210` | Good; the best visual uncertainty work in the app |
| **The `ScoreDial`** | `ScoreDial.swift:12–36` | **Carries no uncertainty at all** |

**The finding that matters most.** `ScoreDial.swift:23` is
`Text("\(Int(score.rounded()))")`. The largest, first, most-looked-at element on
every one of 18 cards — a 96 pt dial on the detail screen, 72 pt on Today — prints
an integer with no interval, no band, no grain. The uncertainty is displaced to a
capsule 16 pt to its right that describes **the model's class**, not **this
number's spread**. A reader has no way to learn from the interface that a
readiness of 61 and a readiness of 64 are the same reading.

**And a second, sharper one.** `ScoreDial.swift:25` applies
`.contentTransition(.numericText())`, which animates the digits on every change.
`ScoreChange.swift:71` sets `minimumPoints = 2.0` with the comment *"Two points
on a 0–100 scale is the smallest change worth a word."* **So the dial animates —
with motion, which is the strongest attention cue available — changes that the
app's own arithmetic classifies as noise, while the chip beside it stays
correctly silent.** The two components disagree about what a point is worth. The
same pattern is on the `VitalsGlance` tiles (`DashboardView.swift:291`).

### 5.2 The inferential-vs-outcome error, and what it costs — the most important research finding here

**Hofman, Goldstein & Hullman (2020), "How Visualizing Inferential Uncertainty
Can Mislead Readers About Treatment Effects in Scientific Results", CHI '20,
Paper 327.** Two pre-registered MTurk experiments, 2,400 recruited each; after
attention checks, **n = 1,743** (Exp 1) and **n = 1,830** (Exp 2).

Participants saw the *same underlying data* drawn either as a 95% **confidence**
interval (inferential — how well the mean is known) or a 95% **prediction**
interval (outcome — how much individual results vary), then said how much they
would pay for a treatment.

- Confidence-interval condition: mean willingness to pay **80**; prediction-interval
  condition: **50**. A ~60% inflation from the choice of interval alone.
- **The effect persisted when the caption stated both**: 72 vs 54.
- Exp 2: axis rescaling reduced error but less well than prediction intervals or
  animated hypothetical outcome plots (HOPs); *"depicting inferential uncertainty
  causes participants to underestimate variability in individual outcomes."*

**Why this is not academic here.** This app draws both kinds of interval, calls
them the same thing, and renders them identically:

- `IdealSleepWindow.swift:222` computes `standardError: sd.map { $0 / √n }` — the
  standard error of a bin mean, i.e. **inferential**.
  `IdealSleepWindowSection.swift:191–194` draws it as a grey `RuleMark` whisker,
  footnoted *"The whiskers are how well each bar is known."* That footnote is
  literally accurate.
- `SocialBatteryModel.swift:89, 281` computes `halfWidth = 2.0 × standardError`
  around a pooled mean difference — also **inferential**, and there it is the
  right choice, because the card's question is genuinely *"is there an effect at
  all"* (`isDistinguishableFromZero`, `:286`, is what licenses naming a
  direction — a good decision).

The difference is the question the reader brings. "Does contact with this kind of
person drain me?" is an effect question; the inferential interval answers it. "If
I go to bed at 22:30, how will tomorrow go?" is an outcome question — and a
section titled *ideal sleep window* invites exactly that reading. Hofman et al.
show that a caption cannot rescue the mismatch (72 vs 54).

**I am deliberately not calling `IdealSleepWindowSection` a bug.** Its bars are
mean differences and its whiskers correctly describe those means. The defect is
one level up and is structural: **there is no type in this codebase that records
which kind of uncertainty an interval is**, so two intervals answering opposite
questions are named `standardError`, drawn as the same grey whisker, and read the
same way. This is Law 3 from §2 in its most consequential form. It is also the
same fix shape as `ScoreChangeState` and `CoverageGate` — see rec. 1.

### 5.3 Colour is doing two jobs at once, 16 points apart

- `Theme.color(forScore:)` (`Theme.swift:42–48`) → `good` / `warn` / `bad` by
  `ScoreBand`. Drives the dial's ring.
- `Theme.color(for: InsightConfidence)` (`Theme.swift:285–291`) → `good` for
  `.high`, `warn` for `.moderate`, `.secondary` for `.low`, `.purple` for
  `.experimental`. Drives the `ConfidenceBadge`.

In `InsightCard` (`DashboardView.swift:337–351`) these render **in the same row,
16 pt apart**. `Theme.good` (0.20, 0.72, 0.51) therefore means *"your score is
high"* on the left and *"the model is validated"* on the right. Two orthogonal
quantities on one hue channel, adjacent, with nothing to distinguish them.

This is precisely what the HIG's *"avoid relying solely on color"* warns about,
and it is worse than the usual case because the two meanings are **positively
correlated in the reader's expectation** — green next to green will be read as
one signal reinforcing itself. The app already has the right instinct elsewhere:
`Theme` carries a validated eight-hue categorical scale with measured
colour-blind ΔE floors (`Theme.swift:296–300`), and `compositionLegendColour`
splits "the colour a band is drawn in" from "the colour a band is named in"
because the two answer different questions. That reasoning has not reached the
confidence badge.

### 5.4 What the research says actually works — and what backfires

**Works: showing the distribution rather than an interval.**

- **Correll & Gleicher (2014), IEEE TVCG 20(12):2142–2151**, "Error Bars
  Considered Harmful". 240 participants across the reported experiments (368
  including piloting; MTurk, North America; 102 M / 138 F, mean age 33.3).
  Gradient and violin encodings beat bars-with-error-bars on inferential tasks:
  participants followed the expected strategy on **89.2%** of trials with violin
  and **88.5%** with gradient, against **83%** with bar charts (Tukey HSD), and
  were significantly more confident with the continuous encodings (gradient
  M = 5.12).
- The same paper's **two-sample experiment (n = 96)** found bar-with-error-bar
  readers predicted *significantly larger* effects than every alternative
  (bar M = 1.65 vs box/gradient M = 1.54, violin lower still) **and were more
  confident in those inflated predictions**. Bars inflate perceived effect.
- **Kay, Kola, Hullman & Munson (2016), CHI '16**, "When (ish) is My Bus?"
  introduced **quantile dotplots** for exactly this app's situation — a
  continuous predictive distribution on a small screen. Quantile dotplots
  reduced the variance of readers' probabilistic estimates by ≈1.15× versus
  density plots and supported more confident estimation.
- **Fernandes, Walls, Munson, Hullman & Kay (2018), CHI '18**, "Uncertainty
  Displays Using Quantile Dotplots or CDFs Improve Transit Decision-Making",
  extended this from *extracting probabilities* to *decision quality* in an
  incentivised task — the discrete and CDF displays improved decisions, textual
  uncertainty did not.

The mechanism common to all four is **frequency framing**: turning a continuous
density into countable outcomes ("18 of 20 nights fall in here") rather than a
band. That is the same lever as **Gigerenzer & Hoffrage (1995), Psychological
Review 102(4):684–704**, whose natural-frequency formats raised correct Bayesian
inferences from roughly 16% to roughly 46% across 15 problems — the single
best-replicated result in risk communication.

**Backfires 1 — removing the visual interval makes people *more* confident and
*less* accurate.** Correll & Gleicher's third experiment (**n = 48**, 24 per
condition) moved the margin of error out of the plot and into the caption.
Following the expected strategy fell from **91.6%** (visual error bars) to
**62%** (text-only) — and participants were **significantly more confident**
(p < 0.0001, M = 5.4) in the text-only condition. The authors' conclusion is
blunt: readers became "unjustifiably more confident in their incorrect
judgments". **This is the empirical case for the reader's standing rule.** "Thin
data means print the error bar, not show nothing" is not a stylistic preference;
it is the measured direction of the failure.

**Backfires 2 — verbal hedges cost more trust than numbers do.**
**van der Bles, van der Linden, Freeman & Spiegelhalter (2020), PNAS
117(14):7672–7683**, five experiments including a pre-registered national
replication and a field experiment on the BBC News site, **total n = 5,780**.
People *did* perceive greater uncertainty when it was communicated, but the
decrease in trust in the numbers and in the source was **small**, and it was
concentrated in **verbal** uncertainty ("might", "could", "around") rather than
numeric ranges. **The honest version does not cost you the reader — but hedging
words cost more than a stated range does.** For this app: prefer "61, and your
own week runs ±6 points" to "roughly 61".

**Backfires 3 — precision is read as confidence.**
**Jerez-Fernandez, Angulo & Oppenheimer (2014), Psychological Science
25(2):633–635**, "Show Me the Numbers: Precision as a Cue to Others' Confidence".
Observers treat numerical precision as a signal of the speaker's confidence.
A score printed as an unqualified integer therefore *asserts* precision it does
not have, regardless of what any badge beside it says. This is the direct
argument for rec. 2.

**Backfires 4 — measuring a thing can reduce enjoying it.**
**Etkin (2016), Journal of Consumer Research 42(6):967–984**, "The Hidden Cost of
Personal Quantification". Six experiments: measurement increased how much of an
activity people did and simultaneously **reduced how much they enjoyed it**, by
undermining intrinsic motivation — making an enjoyable activity feel like work.
This is the empirical backing for the repo's existing no-gamification stance, and
it is an argument against a specific temptation: **do not add streaks, targets or
"beat yesterday" framing to any uncertainty affordance.** A confidence indicator
that can be "improved" becomes a target.

### 5.5 Where no evidence exists — stated plainly

- **There is no published curve mapping a wearable composite score to any
  outcome**, and therefore none this app can borrow to calibrate a dial. See
  §7.1: the systematic review found none of 14 scores independently validated.
- **No study I found compares uncertainty encodings on a *composite ordinal
  index* on a phone.** Kay 2016 and Fernandes 2018 are bus arrival times; Correll
  & Gleicher and Hofman et al. are means and effect sizes on a desktop. Every
  recommendation in §8 that leans on those is an **extrapolation across task and
  form factor**, and I flag it as such rather than dressing it as a settled
  result.
- **No evidence exists on how a reader interprets a *withheld* figure** — the
  "we could compute this and have decided not to" state that `CoverageGate` was
  written for. The nearest thing is Correll & Gleicher's finding that removing a
  visible interval increases misplaced confidence, which concerns a *shown*
  figure with hidden error, not an absent one. `CoverageGate`'s design is a good
  argument from first principles and **it is not evidence-backed**; it would be
  cheap and genuinely novel to test on one reader.
- **No effect size exists for the chevron.** `B14` is right on
  affordance-theoretic grounds (Norman's *signifiers*) and there is no experiment
  I would cite for a magnitude. Do not let anyone quantify it.

---

## 6. Empty, learning and withheld states — making an absence informative

### 6.1 The three states this app must distinguish, and only partly does

`ScoreChangeState` (`ScoreChange.swift:132–184`) already nails this for one
surface. Its three cases are the general taxonomy:

| State | Meaning | Reader's next move | Today |
|---|---|---|---|
| `measured` (incl. steady) | Judged, and the answer is "nothing moved" | Nothing. This is reassurance. | ✅ "Stable", grey, flat arrow |
| `learning(CoverageGate)` | Enough data to start, not enough to judge | **Keep going** — and only this state licenses that advice | ✅ "Learning trends" + `gate.sentence` |
| `notScoredToday` | Enough history; today's sync has not happened | Fix the sync, not the behaviour | ✅ "Not scored yet" |

The doc comment at `:121–131` is the clearest statement of the principle anywhere
in the repo: the `nil` was doing three jobs, *"only 'not enough yet' is a reason
to keep going, and it was the one state the app could not say."*

**A fourth state exists in the app and has no vocabulary: `withheld`.** A figure
the app *can* compute and has decided not to show because it would mislead —
`MetricSanitizer` dropping an implausible reading, a model refusing a direction
because its interval spans zero (`SocialBattery.tooCloseToTell`, which *is*
named, correctly), a blood-pressure estimate past its calibration window. Today
these mostly render as nothing, or as the same "learning" copy, which is wrong in
a specific way: **it tells the reader to keep wearing something when the problem
is not coverage.**

### 6.2 The rule, and what it should look like

**An empty state must answer three questions: what is missing, what it would
unlock, and whether anything the reader does changes it.** `CoverageGate` answers
the first two by construction (`need`, `have`, `unit`, `unlocks`). Only the third
distinguishes *learning* from *withheld*, and it is the one that decides whether
the copy should be encouraging or explanatory.

Two things follow that are cheap:

- **`CoverageGate.progress` (`:62–65`) is computed and, as far as I can find,
  never drawn.** It returns a capped 0–1 fraction. A hairline determinate bar
  under the sentence is the standard way to make "4 of 7" feel like motion rather
  than a deficit, and it is one `ProgressView(value:)`.
- **An empty state must not change the page's height.** `B13-1` is the proof: the
  header unmounting collapsed the content and threw the scroll position. The
  general rule — *a placeholder occupies the space its content would* — is what
  Apple's `loading.json` gestures at ("showing placeholder text… as content
  loads") without stating. `ContentUnavailableView` (iOS 17) and
  `.redacted(reason: .placeholder)` are both available under the iOS 18 floor and
  both preserve layout.

### 6.3 What "informative rather than broken-looking" means concretely

The reader's own approval is on record for one line — the calendar review
section's *"It needs 10 before that figure means anything"* (`CoverageGate.swift:18–20`).
Read that sentence closely: it names the threshold, names what the threshold
buys, and **contains no apology**. It does not say "not enough data", "unable to
compute", or "check back later". That is the register the other states should
match, including `withheld`, whose honest form is something like *"Your last cuff
reading is 34 days old, so this is off its calibration — cuff again to replace
it"* rather than a blank.

---

## 7. How people read a composite 0–100 score, and what keeps one useful

### 7.1 The field this app is competing in, with its evidence base measured

**Doherty, Baldwin, Lambe, Burke & Altini (2025), "Readiness, recovery, and
strain: an evaluation of composite health scores in consumer wearables",
*Translational Exercise Biomedicine* 2(2):128–144, DOI 10.1515/teb-2025-0001.**
Identified **14 composite health scores across 10 manufacturers** (Fitbit,
Garmin, Oura, WHOOP, Polar, Samsung, Suunto, Ultrahuman, Coros and others). The
most frequent inputs were HRV (86%), resting heart rate (79%), physical activity
(71%) and sleep duration (71%). **No manufacturer disclosed its algorithmic
formula, and few provided empirical validation or peer-reviewed evidence.**

**This is the citation that justifies the reader's standing rule** — *a vendor
composite with an undisclosed formula may be RELAYED as a labelled second
opinion, never BLENDED.* It is not a stylistic preference; it is the measured
state of the field. Anything blended in from a vendor score imports an
undisclosed weighting over inputs this app already has, and imports it twice.

**Ibrahim, Beaumont & Strohacker (2024), "Exploring regular exercisers'
experiences with readiness/recovery scores produced by wearable devices: a
descriptive qualitative study", *Applied Psychophysiology and Biofeedback*
49(3):395–405, DOI 10.1007/s10484-024-09645-2.** **n = 17** WHOOP or Oura users
of ≥3 months, semi-structured interviews, reflexive thematic analysis. Users
adjusted training *and* non-exercise behaviour "to manage and optimize their
scores"; they also recognised that a device "can't really capture the
complexities of a human", and relied on self-awareness for final decisions —
**conditional rather than absolute trust**.

Two design implications, and the second is uncomfortable:

1. A reader who already holds the score conditionally will *welcome* a stated
   interval rather than be unsettled by it. This is consistent with van der Bles
   et al.'s small trust cost for numeric uncertainty.
2. **People optimise the score, including in ways that do not improve the thing
   it measures.** With Etkin (2016), that is a reason to make the *decomposition*
   more prominent than the composite — you can act on "your sleep was short", you
   can only game "your readiness is 61".

⚠️ **n = 17 is a qualitative sample.** It supports "this is a phenomenon that
occurs and here is its texture". It does not support any prevalence claim and I
make none.

### 7.2 Why a 0–100 composite is structurally hard to keep honest

**Paruolo, Saisana & Saltelli (2013), "Ratings and rankings: voodoo or science?",
*Journal of the Royal Statistical Society: Series A* 176(3):609–634.** Composite
indicators aggregate variables with weights that are *understood* to express
importance. The authors measure actual importance with Pearson's correlation
ratio (the "main effect") and find that **because the underlying variables are
correlated and heteroscedastic, nominal weights hardly ever match main effects.**
Demonstrated on five composites including the Human Development Index and two
university league tables, where declared importance and real importance were
"very different".

**This applies to this app directly, and the app is unusually exposed to it**
because its inputs are strongly correlated by construction — HRV, resting heart
rate and respiratory rate move together, which `SocialBatteryModel.swift:261–267`
already says out loud about its own standard error. A card that declares "sleep
30%, HRV 25%, activity 20%" in its "How this is weighted" section is stating
nominal weights. Paruolo et al. say those are very unlikely to be the effective
ones.

**The honest response is not to abandon the section — it is to distinguish the
two and label which is being shown.** Nominal weight is a *design decision* and
belongs in the deep dive. Effective importance is an *empirical property of this
reader's data* and is computable: vary one input across its own observed range,
hold the rest, and report how far the score moves. That is a per-reader
sensitivity analysis, it needs no new data, and it would make "How this is
weighted" the most defensible section in the app instead of its most quietly
overclaiming one.

### 7.3 Precision, granularity, and what the dial should print

Two converging results:

- **Jerez-Fernandez, Angulo & Oppenheimer (2014)** — precision is read as
  confidence (§5.4).
- **Zhang & Schwarz (2012), *Journal of Consumer Research* 39(2):248–259**, "How
  and why 1 year differs from 365 days" — the *granularity* of a quantitative
  expression is itself read as a claim about precision; finer units imply a more
  precise underlying estimate.

Together: **a 0–100 integer dial claims precision to the unit.** If the app's own
noise floor is 2 points (`ScoreChange.minimumPoints`), the dial is over-claiming
by construction, on every card, on every open.

I am **not** recommending banding the score to 0–10 or to five words. That
destroys the small-but-real movement the reader can see over a month, and it
throws away information for a presentational reason. What I recommend instead is
in rec. 2: **keep the integer and draw its grain**, so the number and its
resolution arrive together. That is the quantile-dotplot lesson (Kay 2016)
applied to a dial: show the reader the *countable* spread rather than asking them
to infer it from a word.

⚠️ **Flagged as extrapolation.** No study has tested a grain-annotated score dial.
Kay 2016 and Fernandes 2018 support discrete-outcome encodings over continuous
bands for small-screen predictive distributions; applying that to a composite
index is a reasoned bet, not a replicated result. **It should be tried on one
reader and judged by whether they can say what a 3-point move means.**

---

## 8. Ten recommendations for THIS app, prioritised

Ranked by *(honesty gained) × (surfaces reached) ÷ cost*. Costs are relative to
this repo's own history: **small** ≈ one file and a lint; **medium** ≈ a type in
InsightKit plus its call sites; **large** ≈ a new shared component plus a doc
plus a skill update.

---

**1. Give every interval a type that says which kind it is.**
*Surface:* new `Uncertainty` (or `Interval`) type in
`InsightKit/Sources/InsightKit/Presentation/`, adopted by
`IdealSleepWindow.Bin`, `SocialBatteryModel.Response`,
`BloodPressureEstimator`, `BiologicalAgeModel`, and the 7 chart files drawing
`AreaMark(x:yStart:yEnd:)`. *Cost:* **medium**.

Two cases minimum — `.aboutTheEstimate` (standard error; answers *is there an
effect*) and `.aboutTheNextReading` (predictive spread; answers *what will
happen to me*) — each carrying its own one-line explanation, exactly as
`CoverageGate` carries `unlocks` and `ScoreChangeState` carries `pendingLabel`.
Then render them differently and pin that difference in `add-chart`: a thin
whisker for the first, a shaded band for the second, never the same grey rule for
both.

*Why first:* Hofman et al. (2020) measured a ~60% inflation in perceived effect
from this exact confusion, **persisting when the caption stated both** (72 vs 54,
n = 1,743). A footnote is not a fix. And this is the third time this repo has
needed the same shape of type — after `CoverageGate` and `ScoreChangeState` — so
it is a pattern that has earned generalising.

---

**2. Put the score's grain on the score dial.**
*Surface:* `ScoreDial.swift:12–36`, both call sites
(`DashboardView.swift:339`, `InsightDetailView.swift:780`). *Cost:* **medium** —
the view is trivial; the work is that each model must emit a spread.

The dial prints `Int(score.rounded())` with nothing else. Draw the score's own
recent spread as a lighter arc segment behind the value arc, or a tick pair on
the ring — the visual equivalent of "61, and your own week runs 55–67". Several
models can already supply this: `ScoreChangeReader.dailyState` computes the
reference window's standard deviation (`ScoreChange.swift:345`) and throws it
away after standardising.

*Why:* Jerez-Fernandez et al. (2014) — an unqualified integer *asserts*
precision; Correll & Gleicher (2014, n = 48) — moving the interval out of the plot
into text dropped correct strategy from 91.6% to 62% **and raised confidence**.
The `ConfidenceBadge` 16 pt away is text, and it does not describe this number's
spread anyway.

---

**3. Stop animating movement the app classifies as noise.**
*Surface:* `ScoreDial.swift:25`, `DashboardView.swift:291`. *Cost:* **small**.

Gate `.contentTransition(.numericText())` on the same threshold the chip uses
(`ScoreChange.minimumPoints`, 2.0). Below it, the number changes without motion.

*Why:* motion is the strongest attention cue in the interface, and it is
currently spent on changes the chip beside it is deliberately silent about. Two
components in the same row disagree about what a point is worth, and the louder
one is wrong. This is the cheapest honesty win in the document.

---

**4. Size generated sheets from their content, and lint the ones that can't be.**
*Surface:* `AddInputPicker.swift:76`; a new `verify.sh` check. *Cost:* **small**.

`presentationSizing(.fitted)` is **iOS 18.0** (`SwiftUI …:11057–11059`) — no
availability check needed. Combine with `InputKind`'s existing groups so 23
entries arrive as a small number of labelled runs rather than one list.

Then the durable half: a `verify.sh` check in the style of the existing
"every input sheet is reachable from the master input list" check (`:418`), that
**fails when a surface generated from a `CaseIterable` enum is rendered inside a
fixed-height container**. `D53` was fixed once; `InputKind` will keep growing, and
Law 1 says the fix expires.

---

**5. Retire the `Optional`-into-`if let` pattern in views, by making it not compile.**
*Surface:* `AppModel.scoreChange(for:)`, `ScoreChangeReader.trend/daily/broad`,
`MetricViewStrategy.swift:120`, and any view rendering a model `Optional`.
*Cost:* **medium**.

Mark the `ScoreChange?`-returning entry points
`@available(*, deprecated, message: "Use state(for:) — an absence must carry its reason")`.
Swift then produces a warning at every site that discards a reason, which is a
compiler-held rule rather than a remembered one — exactly the argument at
`InputKind.swift:18` and `CoverageGate.swift:24–29`. The `ScoreChange?` overloads
themselves already carry the right doc comment (`:224–229`); this makes the
comment enforceable.

*Why:* `B15-2` and `B13-1` are the same bug in two files. There will be a third.

---

**6. Give the Data tab an index, not a deeper tree.**
*Surface:* `DataTabView.swift`; closes `D29` (still open, `design` tier,
`gate:decision`). *Cost:* **medium**.

A sticky section index — 6 category headers plus the raw groups — that jumps
rather than filters, so nothing is ever hidden and the reader's *"create a data
section for it every time"* rule is untouched. Pair with
`searchToolbarBehavior(_:)` (iOS 26, `SwiftUI …:20008`) to move the field into
thumb reach, behind an availability check.

*Why:* Landauer & Nachbar (1985) — per-screen cost grows as `log b` while depth
costs linearly, so **breadth wins and the obvious "hide raw fields behind a hub"
fix is the wrong direction.** An index preserves breadth; a submenu spends it.
`D29`'s own note already reaches for "an index"; this says why that half of the
note is right and the "collapsed groups" half is second-best.

---

**7. Let the evidence decide which sections arrive open.**
*Surface:* `InsightSection.swift`, `InsightDetailView.swift`, and
`docs/card-sections.md`'s "arrives open or closed" column. *Cost:* **medium**.

Replace the per-section constant with a per-render decision driven by the signal
the app already computes: `ScoreChange.standardisedDelta` past its threshold,
`InsightDriver`'s "worth looking at" flag (`Insight.swift:239–246`), a
`CoverageGate` that just cleared. Machinery sections (7, 8, 9) stay closed
always — they are the third disclosure question (§4.2) and never the second.

*Why:* a 16-section card cannot distinguish "closed because it's the working" from
"closed because nothing happened", so both read as "closed because I have to
check". The distinguishing signal exists and disclosure does not read it.

⚠️ Changing which sections open is a `card-sections.md` change in the same commit,
and `handover-check.sh` runs `card-map.sh --check`.

---

**8. Split the two jobs colour is doing on the card row.**
*Surface:* `Theme.swift:285–291` and `ConfidenceBadge` (`:407–426`);
`DashboardView.swift:337–351`. *Cost:* **small**.

Take confidence off the good/warn ramp entirely. A single neutral-grey capsule
with a differentiating *glyph* (the HIG's "supplement color… use different shapes
or patterns") leaves the semantic ramp meaning one thing: *how is this reader
doing*. `.experimental` may keep a distinct hue — it is a category, not a
position on the same scale.

While there: **"Validated" is too strong for `.high`.** It means "all required
inputs present and fresh" (`Insight.swift:204`), which is a statement about
*inputs*, not about the model having been validated against an outcome — and §7.1
establishes that no composite in this field has been. "All inputs fresh" says
what is true.

---

**9. Give raw fields a role, so metadata cannot render as a measurement.**
*Surface:* a `RawFieldRole` enum in InsightKit (`measurement` / `metadata` /
`identifier` / `unknown`), consumed by the raw rows in `DataTabView.swift`;
closes `D27`'s class rather than its instances. *Cost:* **medium**.

Only `.measurement` gets a value column and a unit. `.metadata` renders as a
labelled attribute. `.identifier` is a detail-sheet line, not a row. `.unknown`
renders the field name and the raw payload with no unit and no numeric framing —
honest, and visibly not a reading.

*Why:* *"How it was measured — 0"* and *"Device model ID — 16"* are Law 3 exactly
— the storage schema became the presentation schema. `PromotionRules` already
exists to decide when a raw field becomes canonical; this is the same decision one
step earlier and the enum makes it unavoidable. It also fixes the truncation half
of `D27` for free, because a metadata attribute can wrap where a value column
cannot.

---

**10. Reclaim vertical space on the two densest screens, and write down the Liquid Glass decision.**
*Surface:* `RootView.swift` (tab bar), the pinned timeframe picker;
`docs/card-sections.md` or a new short note. *Cost:* **small**.

`tabBarMinimizeBehavior(.onScrollDown)` (iOS 26, `SwiftUI …:9005`) behind an
availability check gives back the tab bar's height on Today, Insights and Data —
the three screens the reader has called too long. `scrollEdgeEffectStyle`
(`:12441`) can soften the pinned timeframe picker's edge.

And record the refusal: **this app should not adopt `glassEffect` yet**, because
its floating layer sits over charts whose thin strokes, dashes and hatching are
what a refractive material degrades, and because the app has **zero**
`accessibilityReduceTransparency` handling today. Written down, that is a decision
with a reason; unwritten, it will be re-litigated every session that reads the
SDK.

---

### Not recommended, and why

- **`Chart3D` (iOS 26).** The `add-chart` skill already documents the
  `Chart3DContent` overload hazard. Nothing in this app's data is genuinely
  three-dimensional; a third axis would be decoration bought with a compile
  hazard.
- **Banding the score to 0–10 or to five words.** Destroys the small real
  movement a reader can see over a month (§7.3). Draw the grain instead.
- **Streaks, targets, or any "improve your confidence" affordance.** Etkin (2016,
  six experiments) — measurement increases doing and decreases enjoying. A
  confidence indicator that can be optimised becomes a target, and this app's
  confidence classes are mostly a fact about the sensors, not about the reader.
- **Replacing the score dial with a distribution.** Tempting after §5.4 and
  wrong: it answers a question the reader is not asking at a glance, and Kay
  2016's own framing is that discrete outcome displays serve *decisions*, not
  *monitoring*. Annotate the dial; keep the dial.

---

## 9. Sources

Peer-reviewed, with what each contributes:

- **Correll, M. & Gleicher, M. (2014).** Error Bars Considered Harmful:
  Exploring Alternate Encodings for Mean and Error. *IEEE TVCG* 20(12):2142–2151.
  DOI 10.1109/TVCG.2014.2346298. 240 participants across the reported experiments
  (368 incl. piloting). Violin 89.2% / gradient 88.5% vs bar 83% correct
  strategy; text-only margins dropped correct strategy 91.6% → 62% while
  *raising* confidence (n = 48). Bars inflated predicted effect (M 1.65 vs 1.54).
  → §5.4, recs 1–2.
- **Doherty, C., Baldwin, M., Lambe, R., Burke, D. & Altini, M. (2025).**
  Readiness, recovery, and strain: an evaluation of composite health scores in
  consumer wearables. *Translational Exercise Biomedicine* 2(2):128–144.
  DOI 10.1515/teb-2025-0001. 14 scores, 10 manufacturers; HRV 86%, RHR 79%, PA
  71%, sleep 71%; **no manufacturer disclosed its formula**. → §7.1.
- **Etkin, J. (2016).** The Hidden Cost of Personal Quantification. *Journal of
  Consumer Research* 42(6):967–984. Six experiments; measurement raised activity
  and lowered enjoyment via intrinsic motivation. → §5.4, "Not recommended".
- **Fernandes, M., Walls, L., Munson, S., Hullman, J. & Kay, M. (2018).**
  Uncertainty Displays Using Quantile Dotplots or CDFs Improve Transit
  Decision-Making. *CHI '18*. DOI 10.1145/3173574.3173718. Incentivised decision
  task; discrete/CDF displays improved decisions, textual uncertainty did not.
  → §5.4.
- **Gigerenzer, G. & Hoffrage, U. (1995).** How to improve Bayesian reasoning
  without instruction: frequency formats. *Psychological Review*
  102(4):684–704. Natural-frequency framing raised correct Bayesian inferences
  from ~16% to ~46% across 15 problems. → §5.4.
- **Hofman, J. M., Goldstein, D. G. & Hullman, J. (2020).** How Visualizing
  Inferential Uncertainty Can Mislead Readers About Treatment Effects in
  Scientific Results. *CHI '20*, Paper 327. n = 1,743 and n = 1,830 after
  attention checks (2,400 recruited each). WTP 80 (CI) vs 50 (PI); 72 vs 54 with
  corrective captions. Pre-registration and data: https://osf.io/rcfy5/.
  → §5.2, rec. 1. **The most consequential citation here.**
- **Ibrahim, A. H., Beaumont, C. T. & Strohacker, K. (2024).** Exploring regular
  exercisers' experiences with readiness/recovery scores produced by wearable
  devices: a descriptive qualitative study. *Applied Psychophysiology and
  Biofeedback* 49(3):395–405. DOI 10.1007/s10484-024-09645-2. n = 17;
  conditional trust; behaviour altered to optimise the score. → §7.1.
- **Jerez-Fernandez, A., Angulo, A. N. & Oppenheimer, D. M. (2014).** Show Me the
  Numbers: Precision as a Cue to Others' Confidence. *Psychological Science*
  25(2):633–635. → §5.4, §7.3, rec. 2.
- **Kay, M., Kola, T., Hullman, J. R. & Munson, S. A. (2016).** When (ish) is My
  Bus? User-centered Visualizations of Uncertainty in Everyday, Mobile Predictive
  Systems. *CHI '16*. DOI 10.1145/2858036.2858558. Quantile dotplots reduced
  estimate variance ≈1.15× vs density plots on small screens. → §5.4, §7.3.
- **Landauer, T. K. & Nachbar, D. W. (1985).** Selection from alphabetic and
  numeric menu trees using a touch screen: breadth, depth, and width. *CHI '85*,
  pp. 73–78. `T = k + c·log b`; breadth beats depth. → §4.1, rec. 6.
- **Paruolo, P., Saisana, M. & Saltelli, A. (2013).** Ratings and rankings: voodoo
  or science? *JRSS: Series A* 176(3):609–634.
  DOI 10.1111/j.1467-985X.2012.01059.x. Nominal weights rarely match main
  effects for correlated, heteroscedastic inputs; shown on five composites incl.
  HDI. → §7.2.
- **van der Bles, A. M., van der Linden, S., Freeman, A. L. J. &
  Spiegelhalter, D. J. (2020).** The effects of communicating uncertainty on
  public trust in facts and numbers. *PNAS* 117(14):7672–7683.
  DOI 10.1073/pnas.1913678117. Five experiments incl. a BBC News field
  experiment, **total n = 5,780**. Small trust cost, concentrated in *verbal*
  uncertainty. → §5.4.
- **Zhang, Y. C. & Schwarz, N. (2012).** How and why 1 year differs from 365
  days: a conversational logic analysis of inferences from the granularity of
  quantitative expressions. *Journal of Consumer Research* 39(2):248–259.
  → §7.3.

Primary platform sources (retrieved 2026-08-08):

- **Apple, Human Interface Guidelines — "Charting data"** and **"Charts"** and
  **"Loading"**, retrieved via
  `developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`.
  Quoted verbatim in §3.2. **Neither charting page contains guidance on
  uncertainty, estimated values or incomplete data.**
- **`iPhoneOS26.2.sdk`** — `SwiftUI.framework`, `SwiftUICore.framework` and
  `Charts.framework` `arm64e-apple-ios.swiftinterface`. All availability
  annotations and line numbers in §3.3 were read from these files, not from
  documentation. Xcode 26.3 (17C529).

In-repo sources: `docs/uiux-research-2026-08-06.md`,
`docs/accessibility-research-2026-08-07.md`, `docs/card-sections.md`,
`docs/backlog.md` (§B13–§B17, `D27`, `D29`, `D53`), and the Swift files cited
inline.

---

## 10. Before acting on any of this

- Load the relevant skill first — `add-chart` before touching a chart or an
  interval encoding, `add-data-or-input` before rec. 9, `use-the-simulator`
  before claiming any of recs 2, 3, 4, 6, 7, 8 or 10 works. Recs 4 and 6 are
  detent and safe-area work, which `D53` already records as *"exactly the class
  no test can catch"*.
- Line numbers were accurate on 2026-08-08 and will drift. Conclusions will not.
- Nothing here is in `docs/backlog.md`. A session that wants to build one of
  these should add the row first, so the one list stays the one list.
- **Three of these recommendations reverse or extend documented decisions** —
  rec. 7 (which sections arrive open) touches `card-sections.md`'s audited
  tables; rec. 8 changes a shipped string; rec. 3 changes a shipped animation.
  Each needs the doc moved forward in the same commit, and rec. 7 will fail
  `handover-check.sh` until `card-map.sh` agrees.
