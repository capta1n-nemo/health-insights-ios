# Data conventions — every data type, and the shape of its pages

This file is the answer to a standing complaint: *"not only do we need to have
a data menu for every data type, but those menus need to follow at least a
minimum convention of how those subpages are built, and if there are graphs the
rules need to be followed… so i don't need to keep reprompting and checking for
this every time."* (user, 2026-08-02)

So the conventions are enforced, not described. Each numbered section below is
one convention and the mechanism that holds it. (No count in this sentence on
purpose — it said "three" while the file held four, which is the stale-count
failure this repo keeps logging.)

## 1. Every kind of data appears in the Data tab

`DataDomain` (InsightKit) enumerates every kind, and `DataTabView.section(for:)`
switches **exhaustively** over it — a new domain does not compile until it has a
section. This is the oldest of the three and predates this file; see
`DataDomain`'s own doc comment.

**A new kind of data is a `DataDomain` case.** Not a `MetricType` unless it is a
measured series — a domain is a *shape* (a dated log, paired readings, a regimen
with a decay curve).

## 2. Every domain opens a detail page, and every detail page has one shape

Tapping a domain row opens its **read-only** detail page. Read-only is the point
the Data tab kept getting wrong: substances opened the *add* screen, medication
opened the Body Composition *card*, side effects opened *nothing*. Adding lives
in the sheets the `+` menu and a card's "View & add" open; the Data tab is for
reviewing.

The shape is **`DomainDataScaffold`** (`Features/Data/DomainDataScaffold.swift`):

1. A title, inline.
2. An **optional overview** at the top — a chart or a one-line summary. Pass
   `EmptyView()` when there is nothing to plot.
3. A **list of entries, newest first**, under one header that carries the count.
4. A **standard empty state** so an empty page reads as empty, not broken.

The existing pages that already met it are the templates: `MetricDetailView`
(the richest — chart, per-source breakdown, history) for a measured series, and
`OtherDataDetailView` for unmodelled imports. The logged-data pages
(`SubstanceDataView`, `MedicationDataView`, `SideEffectDataView`) are the
scaffold directly.

**Enforcement:** `verify.sh` requires every `<Domain>DataView` under
`Features/Data` to be built with `DomainDataScaffold` (`CardDataView`, a
card-scoped browser over many domains, is the one exclusion). A page that
reinvents its own shape fails the gate.

## 3. A data page never hand-rolls a chart

If a page draws a chart it uses one of the **shared chart components**
(`SubstanceLoadChart`, `MedicationCurveChart`, `ScoreHistoryChart`, …). Those
are where the `add-chart` skill's rules already live — dash-means-inferred,
per-hue resolution, gap handling, the standardised-not-dual-axis rule, hatch
-never-blend. A raw `Chart { … }` in a domain page is exactly how those rules
get skipped.

**Enforcement:** `verify.sh` fails on a raw `Chart(` / `Chart {` in any
`<Domain>DataView`. `OtherDataDetailView` is exempt — it is the review surface
for *unmodelled* imported data, which has no shared component by definition, and
its chart is a plain line by design.

**Before adding or changing any chart, load the `add-chart` skill.** This lint
catches a raw chart in a data page; it does not check that a shared component
obeys the encoding rules, and only the skill (and the device) can.

## 4. Every data entry says what it is — no exceptions

**The reader's rule, 2026-08-06, verbatim:** *"I like how you added a 'What
breathing disturbance index is' section, to that specific data card. I want that
kind of description on EVERY data entry, make this a requirement everytime we
add a new data type."*

Every `MetricType` carries a `MetricExplanation` — two fields, roughly two
sentences each:

- **`whatItIs`** — what the number physically is and how it was obtained. Name
  the sensor, or say plainly that a human typed it in.
- **`soWhat`** — why it moves and what a change means. The half a reader cannot
  get from the name. Never advice.

**Enforcement, in two layers.** `MetricExplainer.explanation(for:)` returns a
**non-optional** `MetricExplanation` over an exhaustive switch, so a new metric
does not compile until somebody writes it one — there is no `nil` to fall
through. The type system cannot check that what they wrote is worth reading, so
`MetricExplainerTests` runs the whole of `MetricType.allCases` and fails on an
empty or stub field, on placeholder wording, on the two halves being the same
sentence, on Markdown (a `Text` prints the asterisks), and on a definition that
opens with the metric's own name.

**It used to be optional and it is not any more.** Thirty-six metrics returned
`nil` under an argument that explaining a step to somebody is condescension.
That reasoning is kept — superseded, not deleted — in the function's own doc
comment, along with why it was wrong on the merits as well as overruled: every
"obvious" metric turned out to have a real trap in it. What a phone counts as a
step and why the watch disagrees. That a weight moves two kilograms inside a day
on water alone. That no two devices' sleep-stage splits are comparable. That
every dietary figure is a sum of what was **logged**, so a gap is a missed entry
and not a fast. If a new metric seems to have nothing worth saying, that is a
sign of not having looked, not a licence to skip it.

**Where it renders:** `MetricDetailView.explainerCard`, drawn **outside** the
presentation switch since 2026-08-06 — inside it, three classes of page never
showed it (a static attribute like height, the blood-pressure pair, and any
metric whose visible window is empty, which is exactly when the question gets
asked). Raw unmodelled fields have no `MetricType` and open
`OtherDataDetailView`, which shows no explainer section at all rather than an
empty one.

## 5. A new source populates every card, by rule not by memory

The cross-card audit found a card's inputs scattered inconsistently across its
sections. The lesson, as a set of enforced rules so *"a new source gracefully
populates across the cards"* — the more connectors, the more the Data tab and the
scores fill in:

- **Every metric has a Data-tab home.** `MetricType.dataCategory`
  (`MetricDataCategory.swift`) is exhaustive, so a new connector's metric appears
  in the Data tab automatically once it declares a group — no hand-edit of the
  view. This replaced a literal array that had already dropped sleep latency and
  vascular age. Held by `MetricDataCategoryTests`.
- **A reported contributor is always a candidate.** A card's inputs live in two
  lists — `contributors` (drives "What goes into this" / "How this is weighted" /
  "Full history") and `candidateMetrics` (drives "How you compare" / "How far
  from your normal" / the overlay fallback). They must agree or a signal shows in
  some sections and vanishes from others. Held by `ContributorCandidateTests`.
- **Non-metric inputs populate the contributor sections automatically.** A
  grounding fact (cholesterol) or a derived figure (substance load) reaches "What
  goes into this" and "Full history" through
  `InsightDetailView.auxiliaryInputs`, which reads a card's `otherFactors` and
  `requirements` — no per-section wiring. A published peer norm and a
  `VitalSignsCheck` spec are **not** free; those are deliberate per-metric
  decisions.

The full checklist for teaching the app a new signal is in the `add-metric-type`
skill ▸ "Graceful population".

## The observation trap that hid a side effect

Not a page convention, but the bug that prompted this file and worth keeping:
`sideEffects` and `activeMedication` were **computed** properties reading the
SwiftData store (`dataStore.loadSideEffects()`), and a computed read off an
external object establishes **no SwiftUI observation dependency**. So a view
showing only `model.sideEffects` did not re-render when one was added — a side
effect logged from the `+` menu did not appear on a Data tab already on screen.

They are now **stored** `private(set) var`s reloaded by `reloadLoggedData()` at
the top of `recompute()` (which every mutation funnels through) and in
`hydrate()`, exactly like `substanceEvents`.

**Generalises: logged data that lives in SwiftData rather than in `samples` must
be held in a stored, reloaded property — never read live from the store inside a
view — or it is invisible to observation.** If you add a new logged domain, give
it the same treatment and reload it in `reloadLoggedData()`.
