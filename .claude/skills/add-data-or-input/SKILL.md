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
