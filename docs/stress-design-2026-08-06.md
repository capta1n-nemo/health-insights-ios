# Stress, done properly — the design (backlog N1)

_Written 2026-08-06. **Designed, not built.** This is the architecture of record
for the reader's instruction:_

> *"I want to rename it to stress, and research how Oura ring do this, because
> they track stress, but lets do it better because we have more data."*

The rename shipped in `0dbc9b6` (`SustainedLoadInsight.title` is already
"Stress load", and the balance web's spoke reads "Stress"). This document is the
other half — the five questions `docs/backlog.md` §N1 poses, answered with
evidence, and a concrete algorithm with a build order.

**One-line recommendation:** one card, **"Stress"**, whose headline stays the
weeks-scale load; a **daytime arousal index** computed by us at quarter-hour
resolution becomes the card's fifth channel *and* its bespoke section; and
Oura's own stress fields are relayed beside it, never merged, with the
day-by-day agreement analysis as the card's second bespoke section. Argued in
§4.

⚠️ **Coverage counts in this document were measured** from
`~/HealthSeed/exports/health-insights-export.json`, whose `generatedAt` is
2026-08-04T12:08Z; "the last 90 days" below means the 90 days before that
timestamp. **Counts only — no reading from this reader's body appears in this
file**, per `docs/privacy-and-ip.md`.

---

## 0. What the export actually holds — and one correction to N1

N1's coverage table says all three `daily_stress` fields have "142 days, 90 of
the last 90". Two of them do. `day_summary` does not, and the difference
decides how the comparison in §3 has to be scored.

| Raw field | Days total | In the last 90 | Overlap with our usable days |
| --- | --- | --- | --- |
| `oura.daily_stress.stress_high` | 142 | 89 | **77** |
| `oura.daily_stress.recovery_high` | 142 | 89 | **77** |
| `oura.daily_stress.day_summary` | 121 | 75 | **73** |
| `oura.daily_resilience.level` | 93 | 63 | 62 |
| `oura.daily_resilience.contributors.stress` | 93 | 63 | 62 |
| `oura.daily_resilience.contributors.daytime_recovery` | 93 | 63 | 62 |
| `oura.daily_resilience.contributors.sleep_recovery` | 93 | 63 | 62 |

"Our usable days" = days carrying heart rate in **at least 24 distinct
quarter-hour bins** — the minimum §6 sets before this app will compute a daytime
index at all. There are **77 of them in the last 90**.

⚠️ **21 days across the record — 14 of the last 90 — carry the seconds but no
verdict.** Oura emits `stress_high` /
`recovery_high` on days it withholds a `day_summary`, so the categorical
comparison has a smaller denominator than the continuous one. A comparison
written against 90 and silently run against 73 is exactly the sort of quiet
shrinkage this repo's docs exist to prevent — **the card must print both
denominators**.

**What our side is made of**, same window, same export, per day medians:

| Signal | Days of 90 | Median samples/day | p10 |
| --- | --- | --- | --- |
| `heartRate` | 79 | 330 | 187 |
| `heartRate`, distinct quarter-hour bins (of 96) | 79 | **67** | 42 |
| `heartRateVariabilitySDNN` | 64 | 68 | 6 |
| `stepCount` | 90 | 312 | 46 |
| `activeEnergyBurned` | 83 | 270 | 106 |
| `respiratoryRate` | 77 | 2 | 1 |

**67 of 96 quarter-hours covered on a median day is the finding that makes this
buildable.** Oura's own daytime graph updates on a 15-minute cadence; we already
hold heart rate at that cadence for two-thirds of the day, plus an intraday HRV
channel Oura's *API* does not expose at all (Oura returns daily aggregates; the
Apple Watch writes SDNN readings through the day, median 68 of them).

⚠️ **What we do not have: daytime temperature.** `skinTemperature` and
`skinTemperatureDeviation` are present (107 rows each) but are **nocturnal**
— sleep-derived. Oura reads finger temperature continuously, all day. That is
one of the four inputs to their algorithm and we cannot reproduce it. §6 states
this as an error term rather than working around it.

---

## 1. What Oura's daytime stress actually measures

From Oura's own published material (sources at the foot of this document):

- **Four signals: heart rate, HRV, skin temperature at the base of the finger,
  and motion.** Their engineering post is explicit about the physiology it is
  reading: adrenaline binds cardiac receptors and raises rate; sympathetic
  dominance lowers HRV; stress hormones constrict peripheral vessels so *finger
  temperature falls*. Motion is there to disambiguate — "physical activity can
  induce stress", and a raised heart rate on the stairs is not the same finding
  as a raised heart rate sitting still.
- **Personal baseline, recalibrated daily.** "Oura does not use fixed thresholds
  for stress. Your scores are relative to you", and the algorithm "adapts if
  your baselines change (e.g. due to aging)".
- **A 15-minute classification cadence**, and **only while still**: the graph
  "updates every 15 minutes during periods when you're awake, wearing your ring,
  and relatively inactive", and — decisive for any comparison — "Stress is only
  measured during periods of low or no movement, so spikes or gaps may reflect
  physical activity — not stress changes."
- **Four states**: `stressed` (highest), `engaged` (elevated but potentially
  productive), `relaxed` (mild recovery), `restored` (calm). The API exposes the
  day as two second-counts — `stress_high` (time in the top quartile) and
  `recovery_high` (time in the bottom quartile) — plus a categorical
  `day_summary`.
- **Five days of continuous wear** before it will say anything.
- **It is arousal, not emotion, and not necessarily bad.** Oura says so
  plainly: the score "reflects your body's physiological response, which may not
  always match how you feel", and "not all stress is bad".
- **Resilience is the weeks-scale sibling**: a **14-day** balance of three
  contributors — daytime stress load, daytime recovery, night-time recovery —
  graded Limited / Adequate / Solid / Strong / Exceptional.

### Contrast: what this app's Stress load measures

`InsightKit/Sources/InsightKit/Insights/SustainedLoadInsight.swift`:

| | Oura daytime stress | This app's Stress load |
| --- | --- | --- |
| Window | 15 minutes, within a day | **28 days against the previous 90** (`recentDays` / `referenceDays`) |
| Time of day | Waking hours, while still | **Nocturnal channels only** |
| Signals | HR, HRV, finger temperature, motion | HRV rMSSD (w 1.0), resting HR (0.9), respiratory rate (0.6), sleep duration (0.5) |
| Statistic | Vendor composite, undisclosed | Median of each window, robust scale, one-sided weighted z (`load`), `ScoreCurve` to 0–100 |
| Minimum | 5 days of wear | `minimumDays` = 10 in each window, on ≥ 2 channels |
| Answers | *What is happening to me right now* | *Has a drift lasted weeks* |

**State it plainly, because the rest of the design depends on it: these are
different quantities.** Oura's is a within-day state; ours is a weeks-scale
departure of the reader's nights from the reader's own season. Neither is a
worse version of the other, and a straight "who is right" comparison of the two
as they stand would be a category error. §3 fixes that by building a *day-level*
quantity of our own that is comparable to Oura's day-level one, and comparing
weeks-scale to weeks-scale separately.

---

## 2. What this app has that Oura does not

Each row names **the stress question it can answer that Oura structurally
cannot** — structurally, meaning Oura's hardware or API cannot see the input at
all, not merely that Oura chooses not to.

| # | What we hold | Where | The question Oura cannot answer |
| --- | --- | --- | --- |
| 1 | **Continuous daytime heart rate, and intraday HRV** | `HealthKitService.highFrequencyMetrics = [.heartRate]`, 180-day lookback; median 330 HR samples and 68 SDNN readings a day | *What was the shape of the arousal — one 20-minute spike or a four-hour plateau?* Oura's API returns the day as two totals; the within-day curve never leaves their app. We can hold the quarter-hour series **and keep it**, so a bad afternoon is still inspectable in March. |
| 2 | **Medication schedule and modelled level** | `Signals/Pharmacokinetics.swift` (absorption + elimination half-lives per GLP-1 compound), `Signals/MedicationResponse.swift`; 22 doses in the export | *Is this week's arousal the drug or the life?* A modelled plasma level is a continuous covariate with a known shape — injection day, peak, tail. Oura sees a ring; it does not know a dose exists, so a titration step reads to them as three weeks of unexplained stress. |
| 3 | **Substance log with timestamps** | `Substances/Substance.swift` (`acuteCardiacLoad` per class), `Substances/SubstanceEpisodes.swift` (24-hour episode grouping — the unit of evidence) | *Was that "stressed" hour a stressor, or was it caffeine?* This is the single biggest false-positive source in any HR/HRV arousal detector, and it is the one Oura is blind to by construction: a stimulant and a hard meeting look identical in HR and HRV while sitting still. With timestamps we can **exclude** or **stratify** — "your afternoon arousal on the 6 days you logged a stimulant, against the days you did not". |
| 4 | **Cuff blood pressure** | `Insights/BloodPressureEstimator.swift`; 50 cuff readings, and the card already reports its own error in mmHg | *Is the arousal pressor?* A cuff reading taken during a flagged stressed window is ground truth for the sympathetic story that HR and HRV can only imply. Oura has no cuff and no pressure channel at all. |
| 5 | **Gait** | `walkingAsymmetry` (6,675 rows), `walkingSteadiness` (105); `Insights/GaitInsight.swift` | *Did the load reach the way you move?* Walking asymmetry and steadiness degrade with fatigue and load, and they are a **behavioural** channel, statistically much less correlated with the four autonomic ones than they are with each other — so agreement between them is real corroboration rather than the same measurement four times. Oura is a ring on a finger; it has no gait. |
| 6 | **Calendar load** | `Models/CalendarEvent.swift` → `CalendarModel.committedHours`, `busiestDay`, `timeZoneChanges`; `Models/CalendarEventClassifier.swift`; persisted as `CalendarEventRecord`; `Insights/CalendarInsights.swift` (`WorkImpactModel`, 56-day window, working-days-only to defeat the weekend confound) | *What was that afternoon?* This is the "better" claim's centre of gravity. Oura can draw a cortisol-shaped 14:00–17:00 rise and label it "stressed". We can say **which named block it sat inside** — a five-hour meeting stack, a time-zone change, an all-day event — because the calendar is on the same phone. Nothing Oura sells can attribute arousal to a cause; attribution is the product. |
| 7 | **Screen time** | `MetricType.screenTimeMinutes`, `Documents/ScreenTimeScreenshotParser.swift`; 21 rows so far | *Was the evening restless because of the day, or because of the phone?* A behavioural exposure with a plausible arousal path, and one Oura cannot see. ⚠️ **21 rows is not a channel yet** — this is listed as an opportunity, not an input, and §6 does not score it. |
| 8 | **The reader's own logs the ring never gets**: symptoms, side effects, cycles, body scans, holidays (planned, §H of the backlog) | `DataDomain` cases `.symptoms`, `.sideEffects`, `.cycles`, `.bodyScans` | *Is this stress, or is it the second day of a virus / a side effect / the luteal phase?* Oura's own caveat — arousal ≠ emotion — is unresolvable **for them**. For us it is a query. |

**The honest form of the "we have more data" claim** is therefore not that we
have more channels. It is:

> Oura can tell you *that* your body was aroused, on a 15-minute grid, with a
> better temperature sensor than we have. It cannot tell you *what it was*.
> Every one of rows 2–8 is a candidate cause with a timestamp, sitting on the
> same device as the arousal series.

⚠️ **And the reverse must be said in the same breath, or the doc is marketing.**
Oura beats us on: continuous finger temperature (we have none in daylight);
uninterrupted wear (a ring outlasts a watch on the charger); a validated
proprietary classifier with survey-tested subjective alignment; and five years
of population tuning. Our daytime index will be **noisier per quarter-hour than
theirs**. Its advantage is attribution and memory, not sensitivity.

---

## 3. Relay, never merge — and the comparison that is the feature

### 3.1 The precedent, exactly as it stands

`vascularAge` is the rule already in the code, in three places:

- `Ingestion/PromotionRules.swift:161` promotes
  `oura.daily_cardiovascular_age.vascular_age` to its own `MetricType`, with the
  comment: *"a second opinion from a different model, and the value of a second
  opinion is that it stays separate enough to disagree."*
- `Insights/HeartAgeAnalyser.swift:118` reads it as `vascularAgeUsed` /
  `vascularAgeSource` — carried through the analysis **with its provenance
  attached**, and at `:173` it is emitted as a `MetricContribution` with
  **`weight: 0`**.
- `Insights/CardiovascularRiskInsight.swift:216` renders it as a routine driver
  line: *"\<source\> estimates your vascular age at N"*.

So the shape of a relay in this codebase is settled: **ingest it, attribute it,
weight it zero, render it as a labelled line, never let it touch the score.**
Oura's stress fields take the same path.

### 3.2 How the fields surface

| Field | Handling | Why |
| --- | --- | --- |
| `stress_high`, `recovery_high` (seconds) | **Promote** to two new derived-style channels *without* new `MetricType` cases — see below | Numeric, day-level, chartable, comparable to our own index |
| `day_summary` (text) | **Read from the raw catalogue as text.** `RawValue.text` already models it and `RawValue.doubleValue` deliberately returns nil for text | Categorical vendor verdict; never charted, only shown and compared |
| `daily_resilience.level` + three contributors | Read as text/number from the raw catalogue | The weeks-scale second opinion, compared against our headline score |

⚠️ **Do not add `MetricType` cases for these.** `add-metric-type` lists eight
exhaustive switches per case, and `Derived/DerivedSeries.swift` exists precisely
for "a modelled or vendor day-level quantity that should be charted and stored
but is not a reading of the reader's body". Oura's stress seconds are a
*vendor's opinion*, not a measurement of a tissue — filing them beside heart
rate would be the same mistake as dressing modelled as measured. They belong in
the raw catalogue (already visible under `DataDomain.unmodelled`, "Other data")
and are read from there.

⚠️ **Backlog D28 is a prerequisite of the UI half**: these fields currently
render unsorted at the bottom of the Data tab. Sorting them into a labelled
"Oura stress & resilience" group is cheap and makes the raw material of this
design visible to the reader.

### 3.3 The comparison — two levels, both agreement analyses

**This is the headline feature, and the argument for it is the reader's own:
no competitor can grade itself against Oura, because no competitor holds Oura's
output and its own on the same device.** Oura cannot do it either — they have no
second opinion to be graded against.

Two comparisons, deliberately kept apart because they are different windows:

**(a) Day-level.** Our `DaytimeStressIndex` (§6) against Oura's day, on the
**77** shared days for the seconds and **73** for the verdict:

| Statistic | Form | Why this one |
| --- | --- | --- |
| Rank agreement | Spearman ρ between our index and `stress_high` seconds | Scale-free — our index is a percentage of measurable day, theirs is seconds; only the *ordering* of days is commensurable |
| Categorical agreement | Our banded day (calm / mixed / stressed) against `day_summary`, as a 3×3 confusion table with Cohen's κ | κ, not raw agreement: on a person whose days are mostly one category, raw agreement flatters badly |
| Disagreement, named | The days where we and Oura are furthest apart, **each with what we know and they do not** — the calendar block, the substance episode, the dose day, the non-wear gap | This is the whole product. A disagreement with an explanation is a finding; a disagreement without one is a bug report |

**(b) Weeks-level.** Our Stress load score (28d vs 90d) against
`daily_resilience.level` on the **62** shared days — a five-level ordinal against
our 0–100, so Spearman ρ and a level-by-level box of our score.

⚠️ **Three rules for the comparison section, all of them learnt here already:**

1. **Neither number moves the other.** Not as a prior, not as a tie-break, not
   as a "blend when confidence is low". `weight: 0`, exactly as `vascularAge`.
2. **Print both denominators, always.** On today's export that reads: *"77 of
   the last 90 days compared — 13 had too little of our own data, 1 had no Oura
   reading"* for the seconds, and *"73 compared"* for the verdict, because
   Oura withheld a `day_summary` on 14 of the days it did send seconds. Those
   14 must not silently vanish into the smaller number.
3. **Disagreement is not our error.** The section must never be phrased as
   accuracy against a gold standard. Oura's formula is undisclosed and
   unvalidated against anything the reader can see; the honest phrasing is
   *"we and Oura read these 77 days the same way on N of them, and here is what
   the rest had in common"*.

---

## 4. The overlap question — the recommended structure, and the ones rejected

The three windows already in the app, from `SustainedLoadInsight`'s own header
table:

| Card | Window | Question |
| --- | --- | --- |
| Readiness | today vs 28 days | how am I *this morning* |
| Symptom radar | 3 days vs 21, with CUSUM memory | is something acute converging *now* |
| Stress load | 28 days vs 90 | has this lasted *weeks* |

A daytime signal is a fourth window. What makes it not a fourth rendering of one
measurement: **it is the only one with sub-day resolution.** All three existing
cards consume a *day* as their atom, so none of them can say *when* — and
"when" is the only thing that makes "why" answerable, because causes have
timestamps. Readiness reads last night; the radar reads day-grains; Stress load
reads month-grains. Nothing in the app reads a Tuesday afternoon.

### The options

**A — a separate "Daytime stress" card.** Rejected. It puts two scoring cards
with "stress" in the title on one tab, which is precisely the discoverability
failure that N1's point 5 records (the reader asked three times for a card that
existed). It also splits the Oura comparison across two cards.

**B — fold it into Stress load as a section; headline unchanged; nothing else
changes.** Rejected as insufficient, not as wrong. It is the safe half of the
recommendation, but the daytime series would then feed no score at all, which
makes it decoration on a card whose number is computed from something else.

**C — rename to "Stress"; headline stays weeks-scale; the daytime index becomes
(i) a fifth channel of that score and (ii) the card's bespoke section; the Oura
comparison becomes a second bespoke section.** ✅ **Recommended.**

**D — headline becomes today's daytime stress.** Rejected, with the strongest
argument against, because it is the tempting one. It would put a *today* number
on a Today-tab card sitting beside Readiness's *today* number, both computed
from HR and HRV — the exact duplication `SustainedLoadInsight`'s header was
written to prevent. It would also destroy the comparison in §3: a score that is
mostly today's arousal, graded against Oura's today's arousal, is close to
circular.

**E — blend our score with Oura's.** Refused outright by §3.1's rule.

### Why C

1. **One card, one number, one question.** The headline continues to answer
   *has this lasted weeks* — the question nothing else in the app or on the
   market answers, and the one the reader's own instruction implies when they
   say a stress card should tell them something Oura does not.
2. **The daytime index earns its place by making the headline better, not by
   competing with it.** As a fifth channel it is the first *waking* input the
   score has ever had. Today the card is four nocturnal channels; a reader whose
   nights are fine and whose days are brutal currently scores "Settled". That is
   a real gap and the daytime channel closes it.
3. **The bespoke section is where the sub-day resolution lives** — and §N3 (the
   reader's standing rule that every card has a bespoke section) is satisfied by
   a much better section than the one it has. The current "Where the load is
   sitting" bar list stays, nested beneath.
4. **The comparison gets a home that is not a footnote.** Position 6 (the second
   bespoke slot) exists and is currently used by two cards
   (`docs/card-sections.md` §1); "how does this compare with Oura's own verdict"
   is a genuinely different question from "how stressed have you been", on the
   same reasoning that gave Cardiovascular Risk its age-comparison slot.

### The card, section by section

| # | Section | Content |
| --- | --- | --- |
| 1 | the score | Stress load 0–100, higher = calmer. **Five channels now.** |
| 2 | What's driving this | Channel drivers, unchanged in shape; the daytime channel's line names hours, not nights |
| 3 | Score over time | Unchanged |
| 4 | What changed | Unchanged |
| 5 | **Bespoke 1 — "Your stress through the day"** | Today's quarter-hour arousal band chart; below it, the 28-day heat strip (day × hour); below that, the existing "Where the load is sitting" channel bars. ⚠️ `add-chart` before building either chart, and **both carry substance shading** — which on this card is not decoration but the primary confound made visible |
| 6 | **Bespoke 2 — "Oura's opinion, and ours"** | §3.3's two comparisons: the day-level scatter + confusion table, the weeks-level ordinal, the named-disagreement list, both denominators, and the relay caveat |
| 7–15 | unchanged | Per `docs/card-sections.md` |

⚠️ **`docs/card-sections.md` has four hand-written tables and a generated
ordering block; a third card taking position 6 changes all of them.** Bring it
forward in the same commit, and run `./scripts/card-map.sh` — `handover-check.sh`
runs `--check` and a session cannot close while it disagrees with
`InsightDetailView.body`.

⚠️ **`Feedback.swift:163` must go `sustained-load-v1` → `stress-v2`.** Adding a
fifth channel changes what the number means, and the fitness-v2 precedent is
that stored feedback against an old model version must not be read as feedback
against the new one.

---

## 5. Naming

The rule from N1's point 5: **findable by the word the reader thinks in.**

| Surface | Now | Proposed |
| --- | --- | --- |
| Card title | "Stress load" | **"Stress"** |
| Balance web spoke | "Stress" | unchanged |
| `InsightID` case | `.sustainedLoad` | **unchanged** |
| Model type | `SustainedLoadModel` | **`StressModel`**, `SustainedLoadInsight` → `StressInsight` |
| Bespoke section 1 | "Where the load is sitting" | **"Your stress through the day"** (the channel bars keep their name, nested) |
| Derived series | — | `stress.daytimeIndex` → "Daytime stress"; `stress.load` → "Stress load" |
| Telemetry label | "Stress load" (`TelemetryOutboxView.swift:95`) | "Stress" |

Two deliberate asymmetries:

- **"Stress" not "Stress load" for the title.** Once the card holds a daytime
  index, a comparison against Oura and a weeks-scale score, "load" describes one
  of the three. The shortest word the reader searches for is the right title,
  and the honesty lives in the caveat driver — which already says, in as many
  words, that this cannot separate stress from illness, alcohol, heat or hard
  training. That sentence is load-bearing and must survive the rename verbatim.
- **`InsightID.sustainedLoad` does not change.** It is a persisted raw value:
  score history, feedback rows, derived-series namespacing
  (`DerivedSeriesID(insight, key)` builds `"sustainedLoad.…"`) and the telemetry
  outbox all key on it. Renaming the case renames stored data. The *type* names
  can change freely because nothing persists them; the enum case cannot.
  ⚠️ Leave a comment on the case saying exactly this, or a future session will
  "tidy" it.

---

## 6. The algorithm

### 6.1 Inputs

| Input | Source | Role |
| --- | --- | --- |
| `heartRate` samples | HealthKit, 180-day lookback | The arousal carrier |
| `heartRateVariabilitySDNN` samples | HealthKit | The second arousal channel where present |
| `stepCount`, `activeEnergyBurned` | HealthKit | **Motion gate** — the stand-in for Oura's accelerometer |
| Sleep intervals | `Signals/SleepNights.swift` | Defines "awake"; the daytime index never reads a sleeping quarter-hour |
| Substance episodes | `SubstanceEpisodes.episodes(…)` | Stratifier and caveat, **never a correction** |
| Calendar events | `CalendarEventRecord` → `CalendarModel` | Attribution only |
| Modelled medication level | `PharmacokineticsModel` | Attribution only |

### 6.2 Per-day computation

For each local day, for each of the 96 quarter-hour bins:

1. **Gate on wakefulness.** Drop bins overlapping a detected sleep interval.
2. **Gate on stillness** — Oura's rule, reproduced with the sensors we have. A
   bin is *still* when its step count is `≤ 10 steps` and its active energy is
   below the reader's own 60th percentile of waking-bin active energy over the
   trailing 28 days. Personal, not fixed, for the same reason Oura's thresholds
   are personal — and `Baseline.robustScale` is already the house tool.
   ⚠️ **A gated-out bin is a gap, never a zero.** Oura says the same thing about
   their own graph, and the app's dash-means-inferred chart convention
   (`add-chart`) already has the vocabulary for it.
3. **Require substance.** A bin needs ≥ 3 heart-rate samples to be scored.
4. **Score the bin.** Two z-scores against the reader's *own hour-of-day
   baseline* over a trailing 28 days — this is the important refinement, and it
   is what a fixed daily baseline gets wrong: 08:00 and 22:00 are not the same
   physiological hour, and comparing both to one daily median makes every
   morning look stressed.
   - `zHR = (HR_bin − median(HR, same hour-of-day, 28d)) / robustScale(same)`
   - `zHRV = −(HRV_bin − median(HRV, same hour-of-day, 28d)) / robustScale(same)`,
     where present
   - `arousal = (1.0·zHR + 0.8·zHRV) / (coverage-normalised weight total)` —
     one joint statistic, coverage-normalised, **never a count of channels past
     a threshold**. `SustainedLoadModel` carries the note explaining why: six
     signals at 95% specificity, OR'd, give a 26.5% false-alarm rate, and that
     mistake already shipped once in the symptom radar.
5. **Band the bin** into four states, thresholds on `arousal`, chosen to mirror
   Oura's vocabulary so the comparison in §3 has commensurable categories:
   `restored < −0.5 ≤ relaxed < 0.5 ≤ engaged < 1.25 ≤ stressed`.
6. **Roll the day up:**
   - `measurableBins` = bins surviving steps 1–3
   - `stressedFraction` = stressed bins / measurableBins
   - `restoredFraction` = restored bins / measurableBins
   - **`DaytimeStressIndex` = 100 × (stressedFraction − restoredFraction)
     rescaled to 0–100 by `ScoreCurve`**, higher = calmer, the same direction as
     every other dial in the app
   - **Refuse the day** when `measurableBins < 24` (six hours). 77 of the last
     90 days clear this.

### 6.3 Feeding the score

The daytime index becomes the fifth channel of `StressModel.watched`:

```
(.daytimeStressIndex, risingIsLoad: false, weight: 0.7)
```

**Weight 0.7, and the reasoning is the same as the existing four carry.** It
sits above respiratory rate (0.6) and sleep duration (0.5) because a waking
arousal fraction is more specific to load than either — sleep duration in
particular is as likely to be a choice as a symptom, which is why it holds the
smallest share. It sits below resting heart rate (0.9) and HRV (1.0) because
those are read from a still, sleeping body over hours, and this one is read
through a noisy day at quarter-hour resolution with a proxy motion gate. Third
of five, and **explicitly provisional until §6.4's calibration has run on real
days** — if leave-one-out agreement is poor, this number comes down before the
channel comes out. The channel enters the existing machinery
unchanged — 28-day median against the 90-day reference, robust scale, one-sided
weighted z — because it is now just another daily series.

⚠️ **The daytime index is a `DerivedSeriesID`, not a `MetricType`.** One case in
`MetricType` costs eight exhaustive switches; `DerivedSeries.swift` was built
for exactly this and gives it a Data-tab home, a chart and a legend for free.
It is also declared in `derivedOutputs` so `DerivedDependencies` can see the
graph, and any card reading it declares it in `derivedInputs` — an undeclared
read comes back empty by design.

### 6.4 Calibration — supervised comparison, not blending

**The reference set: the reader's own 77 days.** This is a calibration of *our*
thresholds against *a labelled second opinion*, run offline as a test, and its
output is a number in the code — never a runtime coupling.

1. Compute `DaytimeStressIndex` for every day the export can support.
2. Join to `oura.daily_stress.stress_high` (77 days) and `day_summary` (73).
3. **Fit nothing to the vendor's number.** Choose only the four band thresholds
   in step 5 above, by maximising Cohen's κ against `day_summary` over a coarse
   grid. Four thresholds against 73 labelled days is already an aggressive
   parameter budget — hence a grid, not an optimiser, and hence step 4:
4. **Report leave-one-out κ, not fitted κ.** A fitted agreement figure on the
   same 73 days that chose the thresholds is not evidence and must never be the
   number shown on the card.
5. **Freeze the thresholds as constants with a dated comment** naming the
   sample size, the κ and the fact that they came from one person's 73 days.
   `InsightKitTests` asserts the constants exist and are ordered; it cannot
   assert they are right.
6. **Re-run only on an explicit re-calibration commit.** A threshold that drifts
   with new data is a model that grades its own homework.

⚠️ **What calibration must not become:** if κ is poor, the answer is to say so
on the card, not to add channels until the numbers agree. Agreement with Oura is
not the objective — Oura's formula is undisclosed and its ground truth is
survey-based. **The objective is a daytime index whose disagreements have named
causes.**

### 6.5 The error statement — what the card must print

Verbatim-quality material for the caveat drivers, because every one of these is
a real limit of the design and not a disclaimer:

- **No daylight temperature.** Oura reads finger temperature all day; the app's
  `skinTemperature` is nocturnal. Three of Oura's four inputs are reproduced
  here; the fourth is not, and peripheral vasoconstriction is the most specific
  of the four to an acute stress response. **Expect our index to under-detect
  short, sharp stressors** — the ones a temperature dip catches and a
  15-minute HR median smooths away.
- **Coverage is the denominator, and it moves.** A median day gives 67 of 96
  quarter-hours; the 10th-percentile day gives 42. The card prints measurable
  hours beside the index, always. A day below six hours is refused, not
  estimated.
- **The motion gate is a proxy.** Steps and active energy at bin resolution are
  a coarser stand-in for a continuous accelerometer, and a still-but-typing hour
  and a still-but-anxious hour are indistinguishable to both us and Oura.
- **Arousal is not emotion.** Oura says it; we say it; the existing caveat driver
  already says the stronger version — this cannot tell stress from illness,
  alcohol, heat or hard training. **What we add is that for three of those four
  there is now a log with timestamps that can be checked.**
- **The comparison is not an accuracy claim.** §3.3, rule 3.
- **Everything here is modelled.** `.calculated` in the sense the app already
  means it: no reference range, no peer norm, filed under the Data tab's derived
  section rather than beside readings.

---

## 7. Build order, in commits

Each commit is independently shippable, passes `./scripts/verify.sh --tests`,
and leaves the app in a state the reader can use. No commit both changes the
score and adds UI.

| # | Commit | Contents | Gate |
| --- | --- | --- | --- |
| 1 | **Read Oura's stress fields** | `OuraStressRelay` in `Integrations/`: typed accessors over the raw catalogue for `stress_high`, `recovery_high`, `day_summary`, `daily_resilience.*`. No UI. Plus backlog **D28** — sort these fields into a labelled Data-tab group | Unit tests on fixtures; coverage counts asserted, not values |
| 2 | **The daytime index, headless** | `Insights/DaytimeStress.swift` — §6.2 in full: bin gating, hour-of-day baselines, banding, day roll-up, the refusal rule. Pure InsightKit, Linux-testable | Synthetic-day tests: a flat day, a spiky day, a gap-riddled day, a workout day, a day below the six-hour floor |
| 3 | **Calibration harness** | A test-target tool that runs §6.4 over an export and prints ρ, κ, LOO-κ and the confusion table. ⚠️ Reads from `~/HealthSeed/`, never from a fixture in the repo | Runs on the reader's Mac; the thresholds land as dated constants |
| 4 | **Fifth channel** | `DaytimeStressIndex` into `StressModel.watched`; `Feedback.swift` → `stress-v2`; `derivedOutputs` declaration | Existing `SustainedLoad` tests updated; score-attribution and contributor guards pass |
| 5 | **Rename** | `SustainedLoadModel` → `StressModel`, title → "Stress", telemetry label, the `InsightID`-stays comment. `InsightID.sustainedLoad` untouched | `verify.sh` lint; `gen-symbol-index.sh` |
| 6 | **Bespoke section 1** | "Your stress through the day": today's quarter-hour band chart + 28-day heat strip + the existing channel bars nested. ⚠️ `add-chart` first; substance shading on both | Mac session: `simulator.sh run` / `shot` and **read the PNG** — two cards shipped invisible on 2026-08-03 |
| 7 | **Bespoke section 2** | "Oura's opinion, and ours": both comparisons, both denominators, the named-disagreement list, the relay caveat. `docs/card-sections.md` updated in the same commit; `card-map.sh` re-run | `handover-check.sh` runs `card-map.sh --check` |
| 8 | **Attribution** | The disagreement list gains calendar blocks, substance episodes and dose days as named causes. This is the "better than Oura" claim, and it is last because it is worthless until 1–7 are trustworthy | Real-data check on the reader's phone |

**Stop-and-ask point:** after commit 3. If leave-one-out κ is poor, the reader
should decide whether to ship the index as a channel (commit 4) or hold it as a
section-only signal. That is a product call about how much a noisy fifth channel
should be allowed to move a number they already read.

---

## 8. Open decisions for the reader

| | Question | Default if unanswered |
| --- | --- | --- |
| S1 | Title "Stress" or keep "Stress load"? | **"Stress"** — §5 |
| S2 | Should the daytime index move the headline score at all (commit 4), or stay a section? | Move it, at weight 0.7, provisional on §6.4 |
| S3 | Where should the Oura comparison live — the card's second bespoke slot, or a Settings-side "how the app grades itself" page? | The card. A comparison nobody finds is not a feature |
| S4 | Screen time: worth capturing properly so it can become a channel? 21 rows today | Not a channel; listed as an opportunity |
| S5 | Should the daytime index feed Readiness or the symptom radar too? | **No** — one new signal into three cards is how three cards start saying the same thing |

---

## Sources

Oura's published material, read 2026-08-06:

- [Inside the Ring: Understanding Oura's New Daytime Stress Feature](https://ouraring.com/blog/inside-the-ring-daytime-stress/) — the four signals and the physiology; personal baselines that adapt; validation "against other well-established solutions" plus subjective-alignment surveys
- [Daytime Stress — Oura Member Care](https://support.ouraring.com/hc/en-us/articles/21205822135315-Daytime-Stress) — the four states; the 15-minute cadence; measurement only during low or no movement; five days of wear; arousal ≠ emotion; "not all stress is bad"
- [Inside the Ring: Developing Oura's Resilience Feature](https://ouraring.com/blog/inside-the-ring-resilience-feature/) and [Resilience — Oura Member Care](https://support.ouraring.com/hc/en-us/articles/25358829055251-Resilience) — the 14-day window, three contributors, five levels
- [Oura Daily Stress Export Format](https://support.mydatahelps.org/oura-daily-stress-export-format) — `stress_high` / `recovery_high` as seconds in the top / bottom quartile; `day_summary` as a categorical
- [The Oura API](https://support.ouraring.com/hc/en-us/articles/4415266939155-The-Oura-API) — v2 endpoint surface

Code read for this document: `Insights/SustainedLoadInsight.swift`,
`Insights/CalendarInsights.swift`, `Insights/CardiovascularRiskInsight.swift`,
`Insights/HeartAgeAnalyser.swift`, `Insights/Insight.swift`,
`Insights/BloodPressureEstimator.swift`, `Derived/DerivedSeries.swift`,
`Ingestion/PromotionRules.swift`, `Ingestion/RawValue.swift`,
`Ingestion/FieldCatalogue.swift`, `Signals/Pharmacokinetics.swift`,
`Signals/MedicationResponse.swift`, `Substances/Substance.swift`,
`Substances/SubstanceEpisodes.swift`, `Models/CalendarEvent.swift`,
`Presentation/DataDomain.swift`, `Feedback/Feedback.swift`,
`HealthInsights/Core/Integrations/OuraProvider.swift`,
`HealthInsights/Core/HealthData/HealthKitService.swift`,
`HealthInsights/Features/Insights/InsightDetailView.swift`.
