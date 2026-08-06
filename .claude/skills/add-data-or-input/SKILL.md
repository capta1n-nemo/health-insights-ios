---
name: add-data-or-input
description: Add a new kind of data the app holds, or a new way for the reader to put data in. Use whenever a feature stores something new, accepts something new from the user, or adds a button/sheet/picker that takes input — including on a card. Four surfaces have to agree and three checks enforce it.
---

# Adding data, or a way to give it

Two enums hold this app together, and both exist because the same failure
happened twice: a feature shipped, reached one screen, and was invisible
everywhere else.

| | Guarantees | Where |
| --- | --- | --- |
| **`DataDomain`** | every kind of data can be **seen** | `InsightKit/Presentation/DataDomain.swift` |
| **`InputKind`** | every kind of data can be **given** | `InsightKit/Presentation/InputKind.swift` |

Both are exhaustively switched at their surfaces, because the app target has no
test target and the compiler is the only thing that can hold a rule there.

---

## A. New data the app stores

**The rule (user, 2026-08-02): *"whenever we add new data, it must have an entry
in that tab."*** The Data tab is the app's answer to "what do you actually know
about me", and that claim only holds if it is complete.

1. Add a `DataDomain` case. It won't build until it has a `title` and a
   `summary`.
2. `DataTabView` has **two** exhaustive switches and both must gain an arm:
   - `section(for:)` — what it renders;
   - `isVisible(_:)` — how it answers a **search**. "It doesn't" is a decision
     somebody makes, not a row that quietly never appears.
3. If the data is a *series*, it is a `MetricType` instead — load the
   `add-metric-type` skill, which tables the exhaustive switches that feeds.

**A domain is not a metric.** A metric is one measured series; a domain is a
*shape* — a dated log, paired readings, a regimen with a decay curve. Most are
not series at all, which is exactly why they kept falling out of a screen built
around series.

### And it must reach the EXPORT, not only the Data tab

**The reader's core tenet, 2026-08-06:**

> *"for things that have no research, we are going to do the research and find
> the 'norms' ourselves… we need to build this into the export mechanism, all
> the data points so when we combine it all at a server-level later, we can
> build these baselines and norms and global trends."*

The Data tab is how the reader *sees* their data. **The export is the only route
from a phone to a server-side pool**, and for most of what this app derives no
published norm exists — the app is being built to measure one. So a domain that
reaches the tab and not the file is a quantity that can never become a norm.

Four steps, and the last two are the ones that get skipped:

4. `HealthDataExport.exportKey(for:)` is exhaustive, so the new domain will not
   compile until it names a key. **Naming an existing key is a decision, not a
   shortcut** — `calendarEvents` deliberately names `unmodelled` and emits
   nothing, because event titles are the most identifying strings this app
   holds, and the comment there says so.
5. **Add the field to `HealthDataExport` and pass it at the construction site**
   — `DataExportView.buildFullExport()`. A key can exist and be empty: backlog
   D39 was a defaulted `cycles:` argument the app never passed, so every logged
   bleeding day exported as `[]` with nothing in the file saying so.
6. **Extend `HealthDataExportTests.fullyPopulated()`** so the new domain has
   real data in the fixture. That test decodes the payload and fails on an empty
   key; leaving your domain out of the fixture is how it passes vacuously.

⚠️ **"It is recomputable from the other keys" is not a reason to leave something
out.** Recomputability is a property of the device that still holds the raw
data; a pool has the file and nothing else. That argument was used once, to keep
derived series out, and was reversed the same day —
`HealthDataExport.exportKey(for: .generatedInsights)` keeps the superseded
reasoning.

`scripts/verify.sh` reads the parameter labels off `HealthDataExport.init` and
fails when the app target does not pass one, which is the half no test can see.
Background: `docs/norms-and-telemetry.md`.

⚠️ **The export is the *personal* file and stays faithful.** The coarsened,
cohort-stratified, no-free-text thing a pool would receive is `NormContribution`
— summaries, never dated series — and **nothing in this build sends anything.**

### The bug this keeps catching

`summary.sideEffects = parsed.sideEffects.count` — a count assigned straight
from a parse with **no corresponding merge call**. The import alert said "12
side effects" and meant "12 seen", not "12 kept". Found only because a new
`DataDomain` case demanded something to render. **Grep for that shape when an
importer looks suspicious.**

---

## B. New input from the reader

**The rule (user, 2026-08-02): *"if manual input is allowed on a card, it must
be in the View and add sub menu of the card, in the + master add button, in the
add or update section of the settings sub menu; if it's missing, or hasn't been
added for the first time, it goes into the improve your health recommendation
that can be dismissed."***

Four surfaces, and only two of them are free:

| Surface | How it stays current |
| --- | --- |
| Today's `+` menu | generated from `InputKind.allCases` — **free** |
| Settings ▸ Add or update data | generated from `InputKind.allCases` — **free** |
| A card's "View & add" | `ContributionRoute` on the model — **you must declare it** |
| "Improve your health" | `SuggestionEngine.unusedInputs` — from `cardRequirement` |

### The steps

1. **Add the `InputKind` case.** It won't build without a title, a detail, a
   symbol, a group, an `unavailableReason` and a `cardRequirement`.
2. **`cardRequirement`** is the rule, and it has three answers:
   - `.offeredAndPrompted` — on a card, **and** nudged for while never used;
   - `.offeredOnly` — on a card, never nagged (an override, or something
     already prompted for more specifically elsewhere);
   - `.settingsOnly(reason)` — Settings alone, and say why.
3. **Add a branch to `InputSheet`** in `AddDataView.swift` — the one switch
   saying what each input opens, for every surface at once.
4. **If a card takes it, give the card a `ContributionRoute`** and add it to
   that model's `contributions`. `ContributionRoute.inputKinds` is **plural**:
   one route may stand for several inputs (`.medication` is regimen + doses +
   side effects — one conversation, one button).
5. **Render the route** in `ViewAndAddSection` — exhaustive, so this is a
   compile error until done. It needs a `ContributionSummary`; add a factory in
   InsightKit where the wording is tested, not a string in the view.
6. **Teach `AppModel.usedInputs`** how "has this ever been used" is decided.
   Exhaustive, so a new input can't default to silently-never-prompted or
   permanently-nagging.

### The three checks, and why there are three

1. **`InputKindTests`** — every `mustBeOfferedOnACard` kind appears in some
   shipped model's `contributions`; no `settingsOnly` kind does.
2. **`verify.sh`** — any `…Sheet` view under `Features/` must be named in
   `AddDataView.swift`. *The test only binds inputs somebody declared; this
   binds the ones nobody did* — which is what actually happened. Body
   Composition offered a build-override picker inside a chart and a dose button
   inside a section, and nothing knew either existed.
3. **`SuggestionEngine.unusedInputs`** — the prompt, ranked at strength 0.15,
   deliberately below every grounding gap. "A feature you haven't tried" must
   never outrank "this card cannot produce a number without it".

**Keep the in-context control.** Logging a dose while looking at the curve is
the right place to do it. What changed is that it is no longer the *only* place.

---

## C. Data the app models rather than measures

Only one exists: `MetricType.activeMedicationLevel`. If you add a second, copy
all three guards:

- **`MetricSource.calculated`** on every sample, so the overlay legend, the
  per-source breakdown and the export all say *"Worked out by this app"*.
- **Its own `MetricFamily`.** Sharing a family with what it is drawn against
  suppresses the pair as a tautology — hiding the one relationship it exists to
  show.
- **Weight 0 in any score, with the reason on the row**, and **no
  `referenceRange`**. A band on a modelled quantity reads as a target.

A modelled series still belongs in `samples` — the overlay chart, the baseline
machinery and the contributor pipeline all read that one array — but fold it in
**idempotently** (strip the previous derivation first) and rebuild it rather
than caching, because it ends at *now*.

---

## D. Before you push

```bash
./scripts/verify.sh --tests
```

And bring `docs/card-sections.md` forward in the same commit if a card section
moved — `./scripts/card-map.sh` regenerates the order, and four hand-written
tables beside it do not regenerate themselves.
