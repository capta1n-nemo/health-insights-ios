# The blood-pressure engine, and the sweep behind it (backlog §L6–§L11)

<!-- status: complete — design of record for L6–L8 and the Wave 3 retraining sweep L9–L11; the sitting and both dedupe defects shipped, the engine itself is designed and NOT built, and its acceptance gate fails on today's data by design -->

_Written 2026-08-09, from a plan the reader approved the same evening. **The
plan lived outside the repo**, and a plan outside the repo does not survive a
session — this is the copy that does. One slice shipped the same night
(`189a5e1`, `BloodPressureSitting` and both duplicate-reading defects); the
engine, the chart and the loop are designed, not built._

**The reader's reframe, and it is fair:** the in-repo research refuted a
**two-predictor OLS** on resting HR and HRV. It never tested a multi-factor
model. This design takes that seriously — and then builds around the variance
decomposition rather than against it.

⚠️ **Numbers below are dispersions, counts and error statistics — never a
reading.** `docs/privacy-and-ip.md` is the rule; this repo is public and holds
one person's health data.

---

## 1. What the data says before any model is fitted

| | |
|---|---|
| Systolic samples → after dedupe → **sittings** | 52 → 42 → **20** |
| Pooled within-sitting SD | **9.6 mmHg** |
| Share of sitting-to-sitting variance that is the cuff, not the person | **28%** |
| Irreducible MAE at 1 / 2 / 3 readings per sitting | 7.7 / 5.4 / **4.4 mmHg** |
| Best trivial baseline (EWMA over sitting medians) | 10.1 mmHg |
| **Total headroom for every factor combined** | **~2–5 mmHg** |

**Read that last row before designing anything.** Twelve factors are competing
for two to five millimetres of mercury. A design that promises more than that is
promising the cuff's noise back to the reader as insight.

**`P15` is proved rather than argued now.** Twenty `predictionOutcomes` rows
tagged `bp-estimator-v2` in the fresh export show systolic predictions spanning
**6 mmHg** while actuals span **42**, and diastolic predictions spanning
**1.4 mmHg**. The shipped estimator is very nearly a constant. That is measured,
not inferred, and it is the reason this row is worth the effort.

**The covariates are real, dated, and currently ignored by the estimator:** 25
substance events, 22 GLP-1 doses with 174 modelled level samples, a dense flight
calendar, 13 side-effect entries, 19 detected holidays. One stimulant is logged
in the *same minute* as the highest systolic reading in the record. None of it
reaches the model today.

---

## 2. Shipped 2026-08-09 — the sitting, and two dedupe defects

```
ŷ(t) = L(t)                level — the reader's own recent sittings, aged (~95%)
     + Σ_f β_f · x_f(t)     factor corrections, in mmHg
```

`BloodPressureSitting` is the unit of blood pressure. **Four readings in one
morning are one observation, not four**, and every ± computed from a reading
count is too narrow by about √n.

The reader's inter-reading gap distribution is cleanly bimodal — 22 gaps under
four minutes, then nothing until 68 — so **every threshold from 5 to 60 minutes
yields the identical clustering**. The choice is therefore not a tuning
parameter, which is worth knowing before someone spends a session tuning it.

- The sitting's value is the **median**.
- Its **spread is shown, never averaged away**.
- Its weight in the regression is its own precision — a sitting that disagreed
  with itself by 30 mmHg counts for less than one that agreed within 6.

`Drift.uncertaintyFloor = 5` cites ISO 81060-2, which bounds the *cuff's mean
error*. The measured within-sitting SD is 9.6, so the floor becomes
`max(5, pooledWithinSD/√n)`. The comment's argument survives and gets stronger.

**Both duplicate defects are fixed** — a 2020 Withings reading stored ten times,
and the cross-source mirror that appears whenever the direct integration and
Apple Health are both on, silently doubling the weight of every Withings
reading. ⚠️ **Reading counts go *down* where the reader can see them: 52 → 42 on
this record. That is the correction, not a regression** — and it needs saying on
the surface, because a number falling by ten looks like data loss.

Still open from that pass: `K9` — `pairedReadings` never marks a diastolic
sample consumed, so two systolic readings sharing a timestamp both take
whichever diastolic sorted first.

---

## 3. `L6` — The engine

Every `β_f` starts at a **published population effect size with its citation**
and moves toward the reader only as that factor's own *contrast* evidence
accumulates. Fit is a weighted ridge toward the prior (Gaussian-prior MAP), so:

- a factor with no exposure **gets its prior back exactly**, and
- twelve coefficients against twenty sittings **cannot overfit** — effective
  parameters on today's data are under 1.

**Factors:** occasion / first-reading, sleep shortfall, acute alcohol, acute
stimulant, sodium, weight change, **GLP-1 level**, circadian misalignment and
jetlag, acute work stress, dehydration, time of day, unfamiliar place. Each
**reuses an existing signal** — `SubstanceResponseAnalyzer`, `JetlagModel`,
`SleepDebtModel`, `WorkImpactModel`, `PharmacokineticsModel`, `PlaceContext` —
rather than rebuilding it. A factor that needs a new signal is a different row.

⚠️ **Two priors are deliberately zero-centred with wide bands**: GLP-1
within-cycle (no published within-dosing-cycle BP curve exists) and dehydration
(the direction is genuinely disputed). They widen the band without moving the
number, which is the honest behaviour. **Inventing a number for either is the
fastest available way to make this engine dishonest** — and this repo has done
exactly that once already, in Energy v1 (`B19`).

**Adding a data field later is four steps and no engine change:** a new
`BPFactor` struct, one registry line, one prior row, one test. A stored
posterior written before the factor existed decodes fine, and the new factor
returns at its prior.

### 3.1 The gate on printing a number

`BPAcceptance` races the engine against a **fixed** panel of five trivial
baselines on walk-forward hold-out. It passes only if **all four** hold:

1. ≥12 hold-outs,
2. ≥1 mmHg margin against the **best** baseline,
3. a bootstrap CI on that margin excluding zero,
4. effective parameters ≤ holdOuts / 5.

⚠️ **On today's data this FAILS, and the card therefore prints no
blood-pressure number.** That is the design working. It prints the level with a
band, the sittings, their spreads, each factor's published figure with its
shrinkage percentage, and the measured record of how wrong it has been. When
enough sittings exist and it passes, the number appears — **because it earned
it, visibly.**

The panel is fixed in advance for the obvious reason: a baseline set chosen
after seeing the result is not a hold-out, it is a rationalisation.

---

## 4. `L7` — The chart, split in two

Today `BloodPressureChart` draws both lines on one mmHg axis, shades the
**systolic** categories only, and renders the diastolic thresholds as thin
dashed rules with a caption apologising for the compromise. `Category.diastolicRange`
already carries the other set, and its doc comment already argues for this split.

**New shape:** two plots stacked and visually joined — systolic above, diastolic
below — **each with its own y-domain and its own shaded category bands**. The
dashed-rule workaround and its caption are deleted, because the reason for them
is gone.

⚠️ **The diastolic strip has four bands, not five.** `.elevated` is defined by
systolic alone — `diastolicRange` returns the same span for both `.normal` and
`.elevated` — so offering an "Elevated" segment on the lower chart would invent
a diastolic category that does not exist. The lower strip shows Normal /
Stage 1 / Stage 2 / Crisis, **and its caption says why it is shorter.**

The highlighted band buttons stay, one strip per chart, each lit by *that
number's* own category. A third line beneath keeps the combined ACC/AHA verdict,
since a reading falls in the higher of the two bands — so the reader can see
"systolic normal, diastolic stage 1, overall stage 1" at a glance, which the
single strip cannot say today.

**One shared-component change.** `ScrollableMetricChart.scrollX` is a private
`@State`, so two stacked instances would pan independently. Add an optional
`scrollStart: Binding<Date?>?` that overrides the internal state when supplied;
all thirteen existing wrappers are unaffected. `selection` is already a
`@Binding`, so scrubbing shares for free. ⚠️ The `‹ ›` jump affordances and the
empty-window message render on the **upper chart only** — with a shared scroll
they would otherwise appear twice and move both.

### 4.1 The estimate lines

**Every point on an estimate line is predicted from data strictly before that
sitting.** It is never fitted through the point it is drawn at — this is
`drift()`'s existing discipline applied to the whole line.

- Dashed estimate line on **both** charts (dash means *modelled*, per the
  `add-chart` skill); solid actuals.
- `AreaMark(x:yStart:yEnd:)` uncertainty band, **hatched** over the category
  bands rather than washed over them. Blue-over-amber is a colour that means
  nothing; `Theme.hatch` leaves the category legible between the stripes. This
  is the skill's hatch-never-blend rule, and it is a shipped defect, not taste.
- A `RuleMark` whisker at each sitting showing the within-sitting spread the
  reader cannot see today, with an **open marker** where a sitting disagrees
  with itself by more than 10 mmHg.
- The "before vs after" ghost is the **previous replay, snapshotted verbatim**,
  at reduced opacity **in the same hue** — never a second colour. If no snapshot
  exists the row says so; it never interpolates one.
- A blunt correction table beneath: sittings, level, ±, walk-forward MAE, which
  coefficients moved. **When nothing moved it says nothing moved**, which will
  be the common case and is the point.

Chart sites: `BloodPressureChart.swift` (all the work), inherited by
`BloodPressureSections.swift` and `InsightDetailView.swift`, plus the deep dive.

### 4.2 The cuffless model stays a first-class data source

It already is — `DerivedSeriesID(.bloodPressure, "estimatedSystolic"/"estimatedDiastolic")`,
surfaced in the Data tab and carried in the export. That does not regress: the
new engine keeps publishing derived series and **widens** them to
`modelledSystolic`, `modelledDiastolic`, `levelSystolic`, `levelDiastolic` and
`modelUncertainty`, so the band is inspectable **as data** rather than only as
pixels.

That is also the correct home on honesty grounds: `DataDomain.generatedInsights`
is *"Computed, never measured"*, which is exactly what a cuffless estimate is,
and it keeps it structurally separate from the measured readings in
`DataDomain.metrics`.

---

## 5. `L8` — The two-tier loop

**On device:** the posterior is persisted in the app target, versioned by
`engineVersion` + `priorsVersion`, discarded on mismatch, and **replayed rather
than recorded** on every pass — so the correction history is always a pure
function of the reader's sittings, and a bug in one pass cannot be baked in.

**Offline:** `HealthDataExport` gains the posterior, the sittings and the
acceptance verdict (schema 7→8), so a future session can refit from a fresh
export and hand back a re-weighted `BloodPressurePriors`. Plus an env-gated
benchmark harness following `InsightPassBenchmarkTests` — reads `~/HealthSeed`,
**prints shapes, never readings.**

Also in this slice: `captureBloodPressureOutcome` currently fires only on in-app
manual entry and once per *reading*, so Apple Health and Withings readings are
never graded and one sitting writes four ledger rows. It moves to sitting-close
and fires for ingested readings too — that is `K11`.

---

## 6. Wave 3 — the measured retraining sweep (`L9`–`L11`)

**`L9` Screen time is data-limited, but the screenshots are not.** 26 readings
on 25 days, below the model's own `pairedDays >= 40` gate, and iOS Screen Time
retains only ~4 weeks, so it **cannot be back-filled**. But the reader's 46
screenshots carry far more than the daily total the app models: a named day and
total, an **hourly distribution**, a **category split** and a per-app breakdown.
**Evening screen time before bed is the physiologically plausible predictor of
sleep; the daily total is not.** Extend the parser to capture the hourly and
category data, then re-check the gate. This is a data-shape win, not a refit.

**`L10` One lab-confirmed infection date — validate, do not retrain.** A swab in
the reader's corpus gives a lab-confirmed pathogen with an **exact** date, on a
day carrying resting HR, HRV, respiratory rate and sleep. It is the **only
ground-truth infection label in the entire record**, and the reader has zero
logged sick days. ⚠️ **The date and the organism stay out of this repo** — they
are a diagnosis for a named person and this repo is public
(`docs/privacy-and-ip.md`). Both are in `~/HealthSeed`; take them from there. ⚠️ **One label cannot move constants derived from 400,000
simulated null days** — but it can tell us whether the radar fired. Use it to
validate calibration. Feeds `B11-3` / `B11-5`.

**`L11` The full constant sweep.** `docs/signal-audit-2026-08-08.md:825-850`
already lists every score-bearing constant and finds **11 cards with at least
one guess**. Readiness's six weights (`J6`) and Energy's five (`B19`) are the
worst, and both are among the reader's most-viewed numbers; the weight registry
is `J8`. `L11` is **the remainder after those three** — same discipline as §3: a
published prior where one exists, a zero-centred wide prior where none does, a
measured verdict either way.

⚠️ **Do not retrain these**: SCORE2, NIOSH/WHO sound exposure, the ACC/AHA
bands, the ISO floor. They are published, and **citing them is the honesty
claim**. Re-fitting a published standard on twenty sittings replaces evidence
with noise and keeps the authoritative-sounding name.

---

## 7. What this design will not claim

- **That the engine predicts the reader's blood pressure.** On 20 sittings with
  28% of the variance coming from the cuff, it does not — and the acceptance
  gate enforces that rather than trusting anyone's restraint.
- **That a factor is measured on the reader while its shrinkage is near zero.**
  The copy is *"published figures put this at about X — that is other people's
  average."*
- ⚠️ **That the largest available accuracy win is in this modelling at all.** It
  is not. Half the multi-reading sittings disagree with themselves by more than
  20 mmHg. **Taking three readings per sitting moves the irreducible error from
  7.7 mmHg to 4.4 — more than every factor above combined.** `L7` surfaces that
  spread on the chart and prompts a retake, and that is the highest-value thing
  in the whole design.
