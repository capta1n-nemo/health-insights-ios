# Test results, widened to the corpus that actually exists (backlog §L1–§L5)

<!-- status: complete — design of record for the test-results waves; the value type (K13) and the parser corpus fixes (K20) already shipped, the remaining five slices are designed and NOT built -->

_Written 2026-08-09, from a plan the reader approved the same evening. **The
plan lived outside the repo** (`~/.claude/plans/`), and a plan outside the repo
does not survive a session — this document is the copy that does. Two of its
slices shipped the night it was written (`b7c18b0` the value type, `d46a81f` the
parser); the rest is designed, not built._

**The reader's ask, in their own words:** a free-form input for **any** medical
test result that lands in the Data tab with correct dates, updates to whatever
else that data touches — *cholesterol named explicitly* — and a retraining pass
over the app's models.

**Their four decisions this session, which are not revisitable without them:**

1. Sensitive results sit behind a **Face ID gate**.
2. Labs become **trendable series**.
3. Lab values reach **every card that can legitimately use them**.
4. Retrain scope is the **full constant sweep** (that half lives in
   `docs/bp-engine-design-2026-08-09.md` §Wave 3 and in `L9`–`L11`).

---

## 1. What the corpus forced

Measured against the reader's own documents — 19 PDFs, 26 My Health Record
screenshots, and the fresh export. ⚠️ **Shapes only. No reading from any of those
documents appears here or anywhere else in this repo** (`docs/privacy-and-ip.md`).

**A lab-results feature already shipped** (`Q7`, `I6`): typed, photo, PDF and
document-scanner import, a catalogue with unit conversion, per-value confidence,
SwiftData persistence, a Data-tab section and an export key. So this is
extension, not creation. What it **could not represent** was roughly two results
in five of the reader's actual record:

| Shape | Example form | Status |
|---|---|---|
| Qualitative | a word — negative / not detected / non-reactive / detected | ✅ `b7c18b0` |
| Censored | a bound rather than a value (`<`, `>`) | ✅ `b7c18b0` |
| Not measured | "specimen unsuitable", "count could not be provided" | ✅ `b7c18b0` |
| Non-blood specimen | urine, eye swab, faeces | ⬜ `L1` |
| Lab-printed `L`/`H` flags | a one-letter column | ✅ `d46a81f` |
| Report grouping | one collection episode → several documents | ⬜ `L1` |
| Uncatalogued analytes | ~35 at the time of writing; catalogue since 33 → 65 | ◐ `K8` |

**Three date traps, all live in the reader's own documents, all now handled**
(`d46a81f`):

- One laboratory prints Requested / Collected / Received / Reported / "Document
  created" on one page. **Only *Collected* is correct.**
- My Health Record wraps a report in a page whose header carries the **report**
  date; on one of the reader's own that differs from the true collection date by
  two days.
- A third prints a header `Collected:` that contradicts its own structured body
  and is *later* than its own `Completed:`.

⚠️ **Two of the three laboratories print a later, contradicting date above the
document that knows better.** The structured collection line wins, and a report
carrying only a report date yields nil with `collectedAtIsExact == false` —
never a guess. A guessed collection date is worse than none: it walks into a
trend as though it were measured.

---

## 2. The value type — shipped, and why it was the one high-risk edit

`LabValue` is `.quantitative` / `.censored(op:magnitude:)` / `.qualitative` /
`.notMeasured(reason:)`, and `measuredNumber` is **nil for all but the first**.
Both grounding paths — `LabReportParser.extract` and `AppModel.saveLabResults` —
take `measuredNumber` or take nothing.

⚠️ **The decoder accepts a bare `Double` payload permanently, not as a
migration.** `DataStore.labResults()` was a `compactMap` over a `try?` decode:
a codec that could not read the old shape would have **silently emptied the
reader's entire test-result history with no error anywhere**. `LabValueCodecTests`
pins a literal legacy payload. `DataStore.labResultsWithDrops()` now counts what
it skipped, so a codec mistake and an empty database stop looking identical.

⚠️ **And it still shipped a launch crash.** `LabResultRecord.shapeRaw` went in as
a non-optional column with no default; this repo has **no `SchemaMigrationPlan`**,
so the store failed to migrate and `DataStore.init` fatalError'd on every
existing install. See `K16` — the rule it cost is now a lint
(`scripts/check-swiftdata-schema.sh`, wired into `verify.sh`).

---

## 3. `L1` — Report grouping and specimen

New `LabReport` aggregate — lab, referrer, collectedAt, specimen, source
document, accession — plus `LabSpecimen`. Results join by `reportID`.

⚠️ **An unstated specimen must never resolve to `.blood`.** A potassium from
serum and one from plasma are different numbers, and a urine protein filed as
serum is a different test entirely. Nil is the honest answer.

`LabResultRecord` keeps the JSON-payload/projection pattern; `specimenRaw` and
`reportID` are projection columns, set in the single failable `init?`. Both must
be **optional or defaulted** — see `K16`.

Known parser debt for this slice: `isNoiseLine` discards the `specimen type`
line the specimen parser needs.

---

## 4. `L2` — Labs as trendable series

New `InsightKit/Sources/InsightKit/Documents/LabSeries.swift` —
`LabSeriesSpec` / `LabSeriesPoint` / `LabSeriesStore` — built **purely from
`[LabResult]` at read time**, so an analyte becomes trendable the moment it has
a second result, with **no registration anywhere**.

**Two shapes were considered and rejected, and the reasons are the design:**

- **35 new `MetricType` cases.** That is roughly 350 switch arms across the ten
  exhaustive switches the `add-metric-type` skill tables, and `chartStyleIndex`
  must stay contiguous. The cost is paid every time the reader has one more
  blood test.
- **`.derived(DerivedSeriesID)`.** `DerivedSeries.swift:45` says *"nothing here
  may be dressed as measured"*. A laboratory measurement filed there inverts the
  one rule that vocabulary exists to hold.

Chart: new shared `HealthInsights/DesignSystem/LabSeriesChart.swift` wrapping
`ScrollableMetricChart` — **required**, because `verify.sh` fails a raw `Chart(`
in a data page (`docs/data-conventions.md`). `PointMark` always; `LineMark` only
at ≥4 points, because a line through two annual blood tests draws a trend
nobody measured. Load the `add-chart` skill before writing it.

⚠️ `AppModel` gains a **stored** `labSeries`, rebuilt in `reloadLoggedData()`.
A computed SwiftData read is invisible to SwiftUI observation — that is the
observation trap `docs/data-conventions.md` names, and it has bitten this repo.

---

## 5. `L3` — The Face ID gate

The reader's decision: infection and STI results sit behind device
authentication.

- `LabPanel.infection` and `LabSensitivity { ordinary, protected }` as a
  **separate axis** on the catalogue entry, defaulted so existing entries
  compile unchanged. ✅ Both shipped in `189a5e1`.
- New `HealthInsights/Core/Security/SensitiveResultsGate.swift` — **app target**,
  because `LocalAuthentication` is Darwin-only and InsightKit's suite runs on
  Linux.
- Policy `.deviceOwnerAuthentication`, **not** biometrics-only. A failed Face ID
  must not lock the reader out of their own record.
- ⚠️ **The locked row discloses nothing** — no analyte names, no count, no
  dates. A row reading "Sexual health — 6 results" *is* the disclosure.
- Uncatalogued analytes **fail closed** via a keyword guard. `isProtected` is a
  projection column precisely so a protected name never enters memory on the
  unprotected path.
- `DataTabView.isVisible(_:)` must not let a search for a protected term change
  whether the locked row appears. A search box that reveals presence by
  filtering is the same leak wearing a different hat.
- Settings toggle "Protect sensitive results", default on — so a passcode-less
  phone loses access **by explicit choice** rather than by silent fallback.

⚠️ **`Support/Info.plist` has no `NSFaceIDUsageDescription`** — verified absent
2026-08-09. Without it the first `evaluatePolicy` call **crashes the app**. This
is the single most likely shipping bug in the feature and it is its own row,
`K10`, which `L3` is gated on.

---

## 6. `L4` — Batch import

All 19 PDFs at once, review grouped by report rather than by value.

⚠️ **Re-import currently duplicates every value** — `saveLabResults` upserts on
`id` and each import mints fresh UUIDs. That is live today at 1× and becomes 19×
the moment batch import ships. It is `K12`, and `L4` is gated on it.

**The regression corpus is by shape.** The reader's documents never enter this
repo (`docs/privacy-and-ip.md`). Fixtures are structurally faithful with
substituted values — one named fixture per date trap — and a new `verify.sh`
lint rejects a Medicare-number or date-of-birth shape in a tracked file.

---

## 7. `L5` — The cards half, which is the "update cholesterol too" ask

Its own reviewed commit, **because it changes what cards say**.

New `GroundingKind` cases for LDL, triglycerides, non-HDL, HbA1c, glucose,
creatinine/eGFR and TSH, each wired to the card that can legitimately use it and
**carrying the lab date**, so a stale value renders as stale rather than as
current.

⚠️ **Two gates must hold together.** `AppModel.saveLabResults` refuses
`.doubtful`, and must **additionally** refuse anything whose `measuredNumber` is
nil — so a censored or qualitative lipid can never reach SCORE2. An eGFR printed
as a bound is the assay's ceiling, not a reading, and a renal trend built on
ceilings is a fabricated trend.

This deliberately breaks `LabAnalyteCatalogTests.testOnlyTheTwoLipidsFillGroundingFacts`,
whose failure is the warning — which is exactly why this is a separate commit
from `L1`–`L4`.

---

## 8. Verification

`./scripts/verify.sh --tests` per slice, then — on the reader's Mac —
`./scripts/simulator.sh run`, `./scripts/simulator.sh shot`, and **look at the
PNG**; two cards once shipped invisible with green tests and green CI.

⚠️ **The Face ID gate cannot be falsified by the simulator**, and neither can a
SwiftData migration: a fresh install has no store to migrate, so a broken build
launches happily there. `./scripts/device-smoke.sh` after the deploy, every time
this feature touches a `@Model`.
