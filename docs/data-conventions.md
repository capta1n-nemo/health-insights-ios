# Data conventions — every data type, and the shape of its pages

This file is the answer to a standing complaint: *"not only do we need to have
a data menu for every data type, but those menus need to follow at least a
minimum convention of how those subpages are built, and if there are graphs the
rules need to be followed… so i don't need to keep reprompting and checking for
this every time."* (user, 2026-08-02)

So the conventions are enforced, not described. Three of them, each with the
mechanism that holds it.

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
