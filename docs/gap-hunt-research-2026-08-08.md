# The creative gap hunt — what is missing that no row covers

<!-- status: complete — twelve ranked findings no backlog row covered, each with measured counts and an honest feasibility -->

_R60, 2026-08-08. Brief: **"use creative licence to research anything else we
are missing in the app."** Written against `docs/backlog.md` at 236 rows / 56
open, so that nothing here re-proposes something already listed. Sibling briefs
own mental health, cuffless BP, nutrition bootstrapping and UI/UX; those lanes
are deliberately left alone._

**How to read this.** Twelve findings, ranked. Each says what it is, why the
backlog does not already have it, what it needs, and an honest feasibility.
Every count is measured — from the reader's 2026-08-07 export
(`~/HealthSeed/exports/health-insights-export-new.json`, 485,820 readings,
schemaVersion 4) or from source in this tree. Every citation carries author,
year, venue and n. **Where no evidence exists I say so; "no published curve
exists for this" is a finding and appears three times below.**

⚠️ **Privacy.** `docs/privacy-and-ip.md` — the shape of a finding, never the
reading. This document prints row counts, coverage fractions and measurement
*dates*. It prints no physiological value of the reader's.

---

## What I counted before claiming anything arrives

The brief's rule: *before writing "already arriving" about a source, count its
rows in the last 90 days.* Measured against the export, window
2026-05-10 → 2026-08-07:

| Source | Total rows | Rows in last 90d | **Days covered of 90** |
|---|---:|---:|---:|
| `oura.daily_activity.non_wear_time` | 136 | 79 | **79** |
| `oura.daily_activity.sedentary_time` | 136 | 79 | **79** |
| `oura.daily_activity.met.items.mean` | 136 | 79 | **79** |
| `oura.daily_activity.inactivity_alerts` | 136 | 79 | **79** |
| `walkingSpeed` | 16,931 | 1,745 | **89** |
| `HKQuantityTypeIdentifierHeadphoneAudioExposure` | 13,802 | 1,456 | **54** |
| `bodyWaterPercentage` | 154 | 30 | **25** |
| `screenTimeMinutes` | 26 | 26 | **25** |
| `HKQuantityTypeIdentifierBasalEnergyBurned` | 46,356 | 8,453 | **24** |
| `HKCategoryTypeIdentifierAppleStandHour` | 3,213 | 276 | **21** |
| `HKQuantityTypeIdentifierAppleStandTime` | 9,868 | 667 | **19** |
| `HKQuantityTypeIdentifierEnvironmentalAudioExposure` | 5,563 | 395 | **15** |
| `HKQuantityTypeIdentifierStairAscentSpeed` | 436 | 23 | **11** |
| `HKQuantityTypeIdentifierStairDescentSpeed` | 473 | 18 | **9** |
| `HKQuantityTypeIdentifierSixMinuteWalkTestDistance` | 24 | 1 | **1** |
| `height` | 6 | 0 | **0** (last recorded 2020-10-05) |
| `HKQuantityTypeIdentifierDietaryWater` | **0** | 0 | **0** |
| `HKCategoryTypeIdentifierSexualActivity` | **0** | 0 | **0** |

Two conclusions fall straight out of that table and shape everything below.

1. **The ring is the only instrument with real recent coverage.** Oura reports
   on 79 of the last 90 days. The Watch reports Stand data on **19–21 of 90**
   and audio exposure on **15 of 90**. Anything designed on Apple Watch
   daily-cadence data would be built on a fifth of the days it needs — this
   killed one candidate outright (see *Checked and not proposed*).
2. **Two of the three signals the brief named have zero rows, ever.** Not sparse
   — absent. Water and sexual activity are answered at the bottom of this
   document rather than ranked, because a build on zero rows is not a gap, it is
   a decision about whether to ask the reader for a new habit.

Reproduce with `/private/tmp/…/scratchpad/r60-gaphunt-count90.py` (streaming
line scan over the 172 MB export; both scripts are in the session scratchpad,
not the repo).

---

## The twelve

### 1. The score series carries no model version — so any trend the app draws may be an artefact of a commit

**What it is.** `InsightScoreRecord` (`HealthInsights/Core/Persistence/PersistenceModels.swift:125-148`)
stores `insightRaw`, `day`, `score`, `confidenceRaw`, `contributorCount`. That
is the whole record. It does **not** store which version of the model produced
the number.

The two ledgers beside it do. `FeedbackRecord` (`:499-513`) and
`PredictionOutcomeRecord` (`:466-486`) both carry `modelVersion`, sourced from
`InsightID.modelVersion` (`InsightKit/Sources/InsightKit/Feedback/Feedback.swift:143`).
That property's own comment, written when Fitness went v1 → v2 on 2026-08-06,
says exactly what is wrong here:

> Carrying v1 forward would have made every score recorded before today
> silently non-comparable with every score after it, which is the one failure
> this field exists to prevent.

It prevents it in two ledgers out of three. The third is the score history —
the series `D60` was just fixed to export *"so the app could learn from
itself"*, and the series every card's trend chip and score chart is drawn from.
A Fitness score chart spanning 2026-08-06 currently plots two different
quantities on one axis and labels the step "your trend".

**Why nobody listed it.** `D60` was about the export returning `[]`, and it was
closed when data started appearing. Nobody asked what the data *means*. The
backlog's model-version discipline lives in §B5-era commit messages and in one
Swift comment, not in a row.

**What it needs.** One stored property plus a migration (see #2 — the migration
is the risk, not the property). Then two visible consequences, both cheap:
a vertical rule on every score chart at each version boundary, dashed per
`add-chart`'s dash-means-inferred convention; and a **confidence changelog** —
one screen, one row per card per version, with the date, what changed, and a
plain yes/no on whether history before it is comparable. `InsightID.modelVersion`
already carries the strings and the *reasons* in its comments; the screen is
mostly a rendering of a switch that exists.

**Feasibility: high.** `hard` tier for the ruling on what to do with the
existing unversioned history (my view: stamp it `unknown` and draw it in the
"inferred" style rather than back-dating a version onto it, because back-dating
would be the exact lie the field exists to prevent).

---

### 2. The app can write an export it cannot read, has no schema migration plan, and `fatalError`s if the store won't open

**What it is.** Three facts, all checkable in one file:

- `HealthInsights/Core/Persistence/DataStore.swift:13-26` declares a `Schema`
  of **18 `@Model` types**, with the warning comment *"A `@Model` not listed
  here silently never persists."*
- `:28-32` — if `ModelContainer(for:)` throws, the app calls `fatalError`. A
  store that cannot be opened is an app that cannot be launched, on a phone
  holding the only copy of the reader's logs.
- `grep -rn "VersionedSchema\|SchemaMigrationPlan\|MigrationStage"` over both
  targets returns **nothing**. There is no migration plan of any kind.
- `HealthDataExport.decoded(from:)` exists
  (`InsightKit/Sources/InsightKit/Text/HealthDataExport.swift:1297`) and its
  only callers are `HealthDataExportTests`. **The app can write a file it cannot
  read.** There is no restore path in the product.

**The honest version of the risk**, because overstating it would be its own
dishonesty:

- HealthKit-sourced samples are **not** at risk. They live in Health, they are
  re-fetchable, and Health is in an encrypted device backup.
- Credentials are **not** at risk. `KeychainStore.swift:23` uses
  `kSecAttrAccessibleAfterFirstUnlock`, not `…ThisDeviceOnly`, so keychain items
  restore to a new device.
- The SwiftData store lives in Application Support and is therefore included in
  an iOS backup **by default** — nothing in this tree sets
  `isExcludedFromBackup`. So the loss scenario is not "phone in a river"; it is
  **a failed migration on a device the reader still owns**, and after that
  `fatalError`, with no in-app restore.
- What only exists there: corrections, feedback, the symptom and cycle logs,
  holidays, calendar judgements, the dose log, side effects, lab results, ECG
  entries, supplements, body scans, and the score history from #1. Eighteen
  ledgers, two years of them, irreplaceable by re-sync.

And the trigger is not hypothetical. `docs/activeContext.md` records that on
2026-08-07 **eleven branches all added `Schema` entries** and an automatic merge
*"spliced them into code that read plausibly and did not parse … the `Schema`
array closed twice."*

**Why nobody listed it.** The backlog's data-integrity rows are all about the
*export* (`B20`, `D35`, `D39`, `D60`, `D61`, `Q10`, `R4`) — seven rows on
getting data out, none on getting it back in. Export was treated as the backup;
it is a one-way valve.

**What it needs.** A `VersionedSchema`/`SchemaMigrationPlan` with the current
shape pinned as v1; replacing the `fatalError` with a recoverable path that
tells the reader what happened; a `restore(from:)` that consumes what
`decoded(from:)` already parses; and a test that opens a checked-in v(n−1)
store fixture. **Feasibility: medium**, and it is the only item here whose
absence can cost two years of data rather than one feature.

---

### 3. Regime changes nobody labelled — and the app cannot tell one from a device change

**What it is.** The reader's record is not one experiment, it is a stack of
them, and the app models none of the boundaries. Every date below is from the
export's own first/last per source:

| Boundary | Date | What it is |
|---|---|---|
| Withings scale arrives | 2024-12-25 | body composition becomes daily-ish |
| **New iPhone** | 2025-04-08 | old phone keeps reporting until **2026-05-04** — 13 months of overlap |
| shotsy arrives | 2025-08-22 | a second weight/composition writer |
| `activeMedicationLevel` begins | 2026-02-16 | modelled drug level |
| Oura ring arrives | 2026-03-15 | HRV, temperature, sleep staging, stress |

**The sharp end is gait.** `walkingSpeed`, `walkingStepLength`,
`walkingDoubleSupport` and `walkingAsymmetry` come from **phones only** — no
Watch, no ring. So the "How you walked" card's entire series spans a device
swap with a 13-month overlap in which two instruments measured the same person
concurrently. And `GaitInsight.referenceDays = 365`
(`InsightKit/Sources/InsightKit/Insights/GaitInsight.swift:48`) is the app's
longest reference window, so the reference is guaranteed to straddle it.

Nothing in the app can say whether a shift in that series is the phone or the
person. **Neither can I**, from the inventory alone — the two phones' medians
differ, but over different date ranges that also contain a year of weight
change, so the comparison is confounded three ways. That is precisely the
finding: the record contains a natural experiment and a device swap on top of
each other, and the app currently attributes all of it to the reader's body.

**Why nobody listed it.** `R57` covers Core ML **anomaly** detection — point
outliers against a personal null. This is **segmentation**: where did the level
shift, and how many shifts are there. Different question, different method,
different failure mode. `B3-23` ("which instrument to believe", ✅) covers
Watch/ring/scale disagreement on the *same* metric at the *same* time; it does
not cover one instrument replacing another.

**What it needs.**

1. A **device ledger** derived from `MetricSource` first/last dates per metric —
   already computable from the sample set, exactly as `InstrumentCoverage` derives
   coverage rather than fetching it.
2. Changepoint detection per daily series. The standard exact method is PELT —
   Killick R, Fearnhead P, Eckley IA, *"Optimal detection of changepoints with a
   linear computational cost"*, **JASA 2012;107(500):1590-1598** — O(n) under a
   linear penalty, which on ≤1,100 daily points is trivial on device.
3. **The rule that makes it honest:** a changepoint within *k* days of a source
   appearing or disappearing is labelled a device change and is never narrated
   as physiology. Anything else is.

**Feasibility: medium-high.** Judgement: this is the most valuable analysis
available on a two-year record, and also the one most likely to embarrass
existing cards — which is the argument for building it, not against.

---

### 4. The wife's install is a cold start, and every score in this app is a departure from a personal baseline

**What it is.** `Q25` ruled — correctly and cheaply — that the reader's wife
installs the app on her own phone with her own Oura key, so the app stays
structurally single-user. What nothing designed is **what she sees on day 1,
day 14 and day 60**, and the answer today is: a full tab of cards that cannot
speak, because `D59` ruled that no card is ever hidden for want of data.

Read the declared minimums from source and the shape is stark:

| Model | Window | Minimum |
|---|---|---|
| `GaitInsight` | recent 28 / **reference 365** | 10 days |
| `MentalHealthModel` | recent 14 / reference 120 | 7 days |
| `HealthWatch` ledger | 90 | — |
| `BiologicalAgeModel` | 90 | `minimumDaysPerMarker`, per marker |
| `ScoreChange` trend | recent 28 / reference 90 | — |
| `CalendarInsights`, `SocialBatteryModel` | 56 | — |
| `MetabolismInsight` | 28 | 14 logged days |
| `VitalSignsInsight` | baseline 28 | 7 |
| `NutritionInsight` | 14 | 3 logged days |

A fresh install satisfies none of them for weeks and the last of them for a
year. And her record has a **different shape**, not just a shorter one: a ring,
and — unverified, it needs asking — probably no Withings scale, no Apple Watch,
no calendar integration and no shotsy. **The app has never been run against a
record with no scale.** Body Composition, Metabolism and Biological age all
read `bodyMass`/`leanBodyMass`/`bodyFatPercentage` as a matter of course.

There is also a flat blocker nobody has written down: `.github/workflows/deploy.yml`
builds on one Mac and installs to **one** paired iPhone. There is no second
install path, so `B2-17` — a whole fifth tab, built for a specific person —
currently has no route to that person.

**Why nobody listed it.** `Q25`'s answer was so much cheaper than the
alternatives (second profile, per-person baselines) that it closed the
question, and closing it moved the cold start out of view. The backlog has no
`w0` row for it because it is not a defect on the reader's phone.

**What it needs.** The projection is nearly free, because every model already
*declares* its minimum: a "what this card will be able to say, and when" line
driven off those constants, which is honest on day 1 and turns an empty card
into a countdown. Then a cold-start fixture in `SyntheticSeed` (`D55` keeps it
in step) with **no scale and no Watch**, so the no-scale path is exercised by
CI rather than discovered by her. The install route is external and needs
asking, not building.

**Feasibility: high for the projection, external for the install.**

---

### 5. Non-wear is measured, is not missing-at-random, and nothing reads it — including the module whose own header says so

**What it is.** `oura.daily_activity.non_wear_time` is in the export on **79 of
the last 90 days**. Measured over those 79 days:

| | hours/day off-wrist |
|---|---:|
| median | 0.87 |
| p75 | 3.92 |
| max | 21.32 |
| days > 2 h | **31 of 79** |
| days > 6 h | **14 of 79** |

And `InsightKit/Sources/InsightKit/Presentation/InstrumentCoverage.swift:24`
says, in its own header:

> Oura's own `non_wear_time` would separate not-worn from not-synced and is not
> yet ingested; **see the backlog.**

There is no such backlog row. `grep -n non_wear docs/backlog.md` returns one
hit, inside `B3-19`'s prose — and `B3-19` is ✅ shipped. **The code points at a
row that does not exist**, which is its own small finding about how a pointer
survives the thing it pointed to.

**Why it matters more than a coverage badge.** Every card in this app scores a
departure from a personal baseline, and every baseline is computed over
days-with-data. If wear is associated with the state being measured — and the
obvious mechanisms all run that way, illness, travel, a bad week, a flat
battery on a bad night — then the missingness is **not** ignorable, the
baseline is biased, and the z-score is biased with it. This is
missing-not-at-random in the textbook sense: Rubin DB, *"Inference and missing
data"*, **Biometrika 1976;63(3):581-592**, which is where the ignorability
conditions come from.

**On what disengagement predicts: no published curve exists for this.** I
searched for evidence linking wearable non-adherence to health outcomes and
found the useful work concentrated in digital-phenotyping for mental health —
where "data quality" as a feature has predicted relapse — which is a sibling
agent's lane, and none of it gives a curve you could score a ring-wearer
against. **Do not build a "you stopped wearing it, therefore…" claim.** The
honest product of this finding is a denominator, not an inference.

**What it needs.** A `MetricType` for non-wear (**load `add-metric-type`** —
this is the repo's most frequent CI break), the coverage surface reading it so
"reported nothing" can become "not worn" where that is known, and the real
change: **every z-score printing the number of days it was computed from.**
`D46` closed "every 'not enough yet' gate is invisible"; this is the same rule
one level up, for the gates that *did* pass.

**Feasibility: medium.**

---

### 6. Falsifiable predictions with a resolution date — the app records outcomes for exactly one card

**What it is.** `PredictionOutcomeRecord` is a good design: predicted, actual,
`modelVersion`, cohort, date. It is written from **exactly two call sites**,
both `.bloodPressure` (`HealthInsights/Core/State/AppModel.swift:2098` and
`:2100`). The other cards record nothing, ever.

`P24` (model accuracy screen, per-card prediction-vs-actual) is marked ✅. It
should be spot-checked: **a scorecard fed by one card's ledger reads to the
reader as a scorecard over all of them**, and that is a worse failure than
having no scorecard, because it manufactures confidence rather than reporting
it.

**The weaponised version — and this is the honesty identity turned into a
feature no competitor can copy.** A card states a prediction, an interval, and
**a date on which it resolves**, then grades itself in public when that date
arrives. Nothing in the app does this: today's cards state uncertainty about
*now*, never a commitment about *later*.

The strongest available worked example on this record is drug withdrawal, and
the evidence is unusually clean. **SURMOUNT-4** — Aronne LJ et al.,
*"Continued Treatment With Tirzepatide for Maintenance of Weight Reduction in
Adults With Obesity"*, **JAMA 2024;331(1):38-48** — ran a 36-week open-label
tirzepatide lead-in (mean weight reduction **20.9%**) and then randomised
**670** adults to continue or switch to placebo. From week 36 to week 88,
continued tirzepatide gave a **further 5.5% reduction**; placebo produced a
**14.0% regain**. So "here is the published trajectory if you stop, here is
your own weight series, and here is the date we will check ourselves" is a
real, dated, falsifiable claim with a citable basis.

⚠️ **Judgement, and it is the load-bearing caveat:** an n=670 trial mean is not
a prediction interval for one person, and drawing it as one would be exactly
the failure this app exists to avoid. The interval must be the *trial's*
dispersion, labelled as a population trajectory the reader can compare
themselves against — never a personal forecast.

**Why nobody listed it.** `Q10` exports prediction outcomes and `P24` renders
them, so the ledger looked finished. Nobody counted the call sites.

**What it needs.** A `resolvesOn` date on the prediction, seventeen more call
sites, and a rule that an unresolved prediction is visible while it is pending
— a prediction you only see after it resolves is a retrodiction.
**Feasibility: medium.**

---

### 7. "What would change my mind" — computed, not written

**What it is.** Every card already carries `contributors` with weights, and
`D25` closed the four sites that were leaving `componentScore`/`z` nil. That
means **the smallest change in a named input that would move the score across a
band boundary is arithmetic**, not editorial copy. One line per card: *"This
would read differently if your resting heart rate came in 4 bpm lower for three
days"* — computed from the weights that produced the number, and therefore
guaranteed to stay true when the weights change.

**Why nobody listed it.** `B5-38` ("why is my score low", ✅) looks like the
same feature and is its exact inverse. B5-38 decomposes what *is* dragging the
score down. This states what would have to be true for the card to be **wrong**
— which is the only sentence on a health card that cannot be written by a
vendor whose score is a black box, and the reason it belongs in the honesty
lane rather than the explanation lane.

**The caveat is the best part.** For a card whose range is set by invented
constants — `B19` says the Energy card has five — the honest answer to "what
would change my mind" is *"a different constant"*. Printing that is not an
embarrassment to route around; it is the strongest possible argument for
funding `B19`, rendered on the card itself.

**What it needs.** A protocol method on the insight models returning
`(input, delta, resultingBand)`, defaulting to `nil` for any card that cannot
answer, so the absence is explicit rather than silent. Prerequisite: spot-check
`D25` actually holds across all contribution sites, since this reads the fields
it fixed. **Feasibility: high.**

---

### 8. Seasons — the app's only year-long window belongs to the metric that spans a device swap

**What it is.** Read the window constants together and the temporal shape of
the app is clear: 14, 28, 56, 90, 120 days — and exactly one 365
(`GaitInsight.referenceDays`). `Timeframe` offers `.year` and `.all`, but that
is a **chart** axis; no *insight* looks past 120 days except gait, and gait's
year is the one straddling the 2025-04-08 phone change (#3).

Two years of record is now enough to see that this matters:

- **Resting heart rate has a real annual cycle.** Quer G, Gouda P, Galarnyk M,
  Topol EJ, Steinhubl SR, PLOS ONE 2020;15(2):e0227709 — **n = 92,457** adults,
  median 320 days of wear. Population mean RHR **peaks in the first week of
  January and troughs at the end of July**, with an annual amplitude of
  **2 bpm**, against a within-person day-to-day SD of **3.03**. So the seasonal
  swing is roughly two-thirds of one day's noise — small, but *systematic and
  signed*, which is the kind a rolling 28–90-day baseline absorbs into "normal"
  and then reports the transition out of as a change.
- **Sleep has one too, smaller.** Mattingly SM et al., *"The effects of seasons
  and weather on sleep patterns measured through longitudinal multimodal
  sensing"*, npj Digital Medicine 2021;4:76 — **n = 216** across four seasons.
  Effects were small but significant; the strongest were on **wake time and
  sleep duration in spring** (earlier wake, shorter sleep).
- **Steps: no pooled adult effect size exists that I could find.** Seasonal
  variation in adult physical activity is repeatedly documented, and a 2012
  review of accelerometer studies in children states outright that
  heterogeneity in samples, protocols and outcomes made meta-analysis
  impossible. **I am not putting a number on step seasonality, because there
  isn't an honest one.**

**Why nobody listed it.** Every card was specified as an answer about *now*.
Season is a property of the archive, and the backlog has no section for the
archive.

**What it needs — and it is not a seasonal adjustment.** Two years gives two
observations per month-of-year. Fitting a seasonal term on that and subtracting
it would be inventing precision. The honest build is a **chart**: one metric
folded onto month-of-year, each year drawn separately, with the interval two
years actually buys — which is wide, and looks wide. Plus one sentence the app
is currently unable to say: *"we cannot separate season from a year of
medication on this record."* **Feasibility: medium.** Value: it retires a
question that will otherwise be asked every winter.

---

### 9. The record has no records — nine years of weight, and the app shows ninety days

**What it is.** The archive goes back much further than anything reads:
`bodyMass` from **2017-06-09** (1,243 rows), `bodyFatPercentage` and
`leanBodyMass` from **2020-10-07**, Watch-era metrics from **2023-08-16**,
`walkingSteadiness` from 2024-08-05. Nothing in the app ever says *"that is
the lowest that has been since 2019"*, or *"your longest run of nights above
X"*, or *"a year ago today"*.

**Why nobody listed it.** The backlog is organised around cards, sections and
scores. A personal record is none of those — it is a fact about the archive,
and there is no §for it. It is also the only item in this document that is pure
gift rather than correction, which is exactly the kind of thing a defect-driven
list never generates.

**What it needs.** An all-time extremum per `MetricType` with its date; a
"since" line; a streak. Then the honesty rule that keeps it from being a lie:
**a record set by a different instrument is labelled as such** — the 2017–2024
weights are a different scale from the Withings one, and #3's device ledger is
what makes that labellable rather than guessed.

**Feasibility: high, and cheap.** Judgement: highest joy per line of code in
this document, and the only item that would make the reader open the app for a
reason other than worry.

---

### 10. Minutes — 1,440 MET values a day, 79 days of them, read by nothing

**What it is.** `oura.daily_activity.met` arrives with `interval: 60` and
`items.count: 1440` on **79 of the last 90 days** — a full minute-by-minute
metabolic-equivalent series. The app catalogues `met.items.mean`, `.max`,
`.min`, `.first`, `.last` as five separate scalar fields and reads the series
itself **not at all**.

**Why nobody listed it.** `B3-20` ("when you settled", ✅) shipped the
within-*night* HR/HRV curve, which makes the intraday-shape idea look done. It
is a different object: that one is nocturnal, sourced from `oura.sleep.*` at a
300 s interval; this one is the waking day at 60 s.

**What it becomes.** Intraday exposure **in its own units** — where the day's
load actually sat, in METs, drawn and never scored. That is the one thing the
Energy card could honestly be about; the Energy design's own refutation says
its single defensible claim to exist is being the fleet's only intraday card,
and that its subject must therefore be a *measured* intraday quantity rather
than a modelled alertness curve. This is that quantity, already arriving, at
79/90 coverage.

**Feasibility: medium.** The open question is storage: 1,440 points/day is
~114k points over the 79 days already available, and the ingest and Data-tab
rules (`add-data-or-input`) both apply. Judgement: store a downsampled
5-minute series and keep the minute series only for the current day, unless the
`B19` work needs otherwise.

---

### 11. Grounding facts have an expiry date; sensed facts do not

**What it is.** `GroundingKind.freshness`
(`InsightKit/Sources/InsightKit/Models/GroundingInput.swift:92-110`) is a good
piece of design: cholesterol and the risk flags go stale at 180 days, cuff BP
at 14, date of birth never, and `GroundingInput.isFresh(asOf:)` enforces it
with a comment explaining that an aged lab *"is still the best number available
and keeps being used — what it stops buying is high confidence."*

There is **no equivalent for anything sensed**. `samples.latestValue(_:)` has
no age concept at all. Height is read that way by
`MetabolismInsight.swift:149` and `BodyCompositionInsight.swift:59` and `:579`,
and the reader's height is **6 rows, last recorded 2020-10-05, zero in the last
90 days** — a nearly six-year-old measurement feeding BMI and Mifflin-St Jeor
with the same visual authority as this morning's weight.

**I checked how much it matters and the answer is: not much, and that is the
point.** Sorkin JD, Muller DC, Andres R, *"Longitudinal change in height of men
and women: implications for interpretation of the body mass index"*,
**Am J Epidemiol 1999;150(9):969-977**, **n = 2,084** (Baltimore Longitudinal
Study of Aging, men measured on average nine times over 15 years): cumulative
loss from age 30 to 70 averages **~3 cm in men**, of which **0.24 cm** accrues
across the thirties and **0.567 cm** across the forties. Six years at that rate
is a few millimetres — a BMI shift on the order of 0.1.

**So the number is fine and the silence is not.** The missing rule is *"say how
old this input is"*, not *"recompute it"*. That is a one-line presentational
change with a general form: any `latestValue` older than the card's own window
gets its date shown. **Feasibility: high.** Included at 11 rather than higher
precisely because I measured it and it is small — a document that only reports
big findings is being written to impress.

---

### 12. The refusals are the product, and they are invisible

**What it is.** In 236 backlog rows there is exactly **one ❌** (`B5-32`,
meal-to-outcome / TDEE). The kept refusal reasons in §B5, the calibration
warning in §A3, the evidence warning on §B11, `data-opportunities.md`'s standing
rule that a signal with no published 0–100 mapping is **weight 0** — this repo
has an unusually rich record of things it has decided not to claim, and **none
of it is visible in the app.**

Every competitor ships a number for stress, for hydration, for "body battery".
This app's actual differentiator is that it declines to, on stated grounds. A
reader cannot see that. An absence with a reason and an absence without one look
identical on a screen, so the differentiator currently reads as a missing
feature.

**Why nobody listed it.** `P33` shipped an in-app Research section, which
covers *why the app decides things the way it does*. Nobody wrote the
complement: **what the app will not tell you, and why.**

**What it needs.** One screen, beside the Research section, generated from the
same rows that already exist — "we do not give you a hydration number, because
[reason]; we do not blend Oura's readiness into ours, because
[`sharesMeasurementBasis`]; we do not score breathing disturbance, because no
validated BDI→AHI conversion exists." **Feasibility: high**, and it is the
cheapest thing in this document that changes what the app *is* rather than what
it knows.

---

## The three the brief named, answered

The brief named hydration, posture and libido specifically. All three are
answered here rather than ranked, because in each case the honest finding is
about the instrument, not the model — and two of the three are refusals.

### Hydration — **refuse, in writing**

**Coverage: `dietaryWater` has zero rows. Ever.** Not sparse; absent from the
inventory entirely. The only water-adjacent signal is `bodyWaterPercentage`,
154 rows, 30 in the last 90 days across 25 days, from the Withings scale — and
it is read only by Body Composition.

Three reasons this should be a written refusal rather than a build:

1. **The Withings figure is not a hydration measure you can act on.** It is a
   compartment estimate derived from the same bioimpedance measurement the fat
   estimate comes from, and it moves with the same confounders — recent food,
   recent exercise, skin temperature, foot moisture, time of day.
   `data-opportunities.md` already excluded ~80 Withings device-metadata fields
   at ingest for related reasons; this one survives because it is a real
   quantity, not because it is an actionable one.
2. **Logging water requires a new daily habit from a reader whose logging
   record argues against it.** `dietaryEnergy` is 0 rows in the last 90 despite
   MyFitnessPal writing into Health (`Q22`), and `screenTimeMinutes` reached 25
   of 90 days. A signal that only exists if he types it every day will be
   sparse, and a sparse hydration series produces exactly the intermittent,
   confidence-free card that `D46` exists to stop.
3. **There is no published curve mapping daily water intake to any outcome this
   app scores.** Intake guidance exists (EFSA, IOM adequate-intake figures) but
   adequate intake is a population reference value, not a dose–response, and
   nothing maps a day's intake to sleep, HRV, resting heart rate or readiness
   with an effect size you could weight. Saying so is the finding.

**Recommendation:** a ❌ row with those three reasons, and a line on the screen
from #12. That is worth more than a card and costs a hundredth as much.

### Posture — **the instrument does not exist here**

There is no HealthKit posture type, and `PostureAssessment` is one of the five
dead modules in `D4` (a type that appears in exactly one file — its own
declaration). The nearest real signals are `walkingDoubleSupport` (15,282 rows),
`walkingAsymmetry` (6,701) and `walkingSteadiness` (104) — gait, not posture,
and `GaitInsight` already owns all three.

The one posture-adjacent construct with a genuine evidence base is **sedentary
behaviour**, and the evidence is strong: Ekelund U et al., *"Does physical
activity attenuate, or even eliminate, the detrimental association of sitting
time with mortality?"*, **Lancet 2016;388(10051):1302-1310**, a harmonised
meta-analysis of **1,005,791** adults followed 2–18.1 years (84,609 deaths);
and Diaz KM et al., *"Patterns of
Sedentary Behavior and Mortality in U.S. Middle-Aged and Older Adults"*,
**Annals of Internal Medicine 2017;167(7):465-475**, **n = 7,985** (REGARDS,
hip accelerometer), which found **both** total sedentary time and **mean
sedentary bout length** independently associated with all-cause mortality, with
the highest risk in those high on both (≥12.5 h/d **and** ≥10 min/bout).

**But the bout is the exposure, and the bout is not measurable here.** See
*Checked and not proposed* below — Apple Stand data covers 19–21 of the last 90
days, and Oura's `sedentary_time` is a daily total with no bout structure. So
the published finding that would justify a card is precisely the one this
record cannot support. **Say that, rather than shipping a total and implying it
is the thing the papers measured.**

### Libido — **the indicator is real; the instrument is not, and the type is not what it looks like**

The brief describes libido as *"a documented early indicator with a HealthKit
type."* Two corrections, both load-bearing.

**On the type.** HealthKit's `HKCategoryTypeIdentifierSexualActivity` records
*events*, with one metadata key for whether protection was used. It is a count,
not a libido scale — there is no intensity, no desire, no direction. And on
this record it has **zero rows, ever**. So the type exists and measures
something adjacent to, but not the same as, what the brief wants.

**On the evidence, which is genuinely strong — for erectile dysfunction, not
libido.** Thompson IM et al., *"Erectile dysfunction and subsequent
cardiovascular disease"*, **JAMA 2005;294(23):2996-3002** — the placebo arm of
the Prostate Cancer Prevention Trial, **n = 9,457** men aged ≥55 at 221 US
centres, 7 years of follow-up. Incident ED carried an adjusted **HR 1.25
(95% CI 1.04–1.53, p = 0.04)** for subsequent cardiovascular events; incident
**or** prevalent ED, **HR 1.45 (95% CI 1.25–1.69, p < 0.001)**. That is a real,
sizeable, well-powered signal, and it is the basis for the "window of
curability" framing in the urology literature.

**What it does not give you is a daily instrument.** Nothing measures this
passively. The only honest capture is a periodic single question, and the
honest design is therefore narrow: a **monthly** item, not a daily log,
routed through `InputKind` like any other input (**load `add-data-or-input`**),
never scored on its own, and — critically — never surfaced as a card on a
record where the reader's own cuff readings already put blood pressure in play,
because a card that pairs those two is making a clinical inference this app has
no business making.

**Recommendation: ask before building.** This is the one item in this document
where the right next step is a question to the reader rather than a design.
Judgement: I would ship #12's refusal page first and let the reader ask for
this if they want it.

---

## Checked and not proposed, with the reason

Recording these so the next session does not spend the same budget.

| Candidate | Why not |
|---|---|
| **Sedentary bouts from Apple Stand data** | The evidence (Diaz 2017) is about *bout length*, and Apple Stand Hour covers **21 of the last 90 days**, Stand Time **19**. A bout analysis on a fifth of the days is not a bout analysis. Oura's `sedentary_time` (79/90) is a daily total with no bout structure. **The exposure the papers measured is not measurable on this record.** |
| **Sedentary/resting time as a total** | Already claimed by the Energy design's S5, and that design was refuted for other reasons. Not this lane's to re-propose. |
| **Audio exposure** | `B3-22` ("Sound you took on") is ✅ shipped. Worth noting the coverage anyway: environmental audio is **15 of 90 days**, headphone **54 of 90** — the card's "hours it could not see" caveat is carrying a lot of weight. |
| **Six-minute walk test** | 24 rows total, **1 in the last 90 days**, and the series sits at 500 m for most of its history. ⚠️ **Unverified:** I believe 500 m is Apple's reporting ceiling but did not confirm it against Apple's documentation. If it is, the finding is a *rule* rather than a card — **a series resting on its instrument's rail carries no information and must not be drawn as a flat trend**. `walkingAsymmetry` (median 0, max 100) is the second case. |
| **Stair ascent/descent speed** | 11 and 9 days of 90. Too sparse, and no card wants it. |
| **`bodyWaterPercentage` as a hydration proxy** | See hydration above. |
| **Withings BP monitor rows** | `withings.measure.9/10/11` already noted in `data-opportunities.md`; ~31 records. Sibling agent owns the BP lane. |

---

## What I did not verify, and would need to

Stated plainly so nothing here is trusted further than it was checked.

1. **Whether the wife's record has a scale, a Watch or a calendar.** #4 assumes
   a ring and little else. That assumption drives the whole cold-start design
   and it is a question, not a finding.
2. **Whether the SwiftData store is actually being captured by the reader's iOS
   backups** — i.e. whether iCloud Backup is on for this app and has quota. #2
   establishes that nothing in *code* excludes it; it does not establish that a
   backup exists.
3. **Whether `P24`'s accuracy screen visibly scopes itself to blood pressure.**
   I counted two call sites; I did not open the screen. If it already says
   "blood pressure only", #6 shrinks to the resolution-date half.
4. **Whether Apple's six-minute-walk estimate caps at 500 m.**
5. **The two-phone gait comparison is confounded** and I have not attempted to
   deconfound it. #3 proposes the method; it does not report a result.

---

## Sources

⚠️ **What was confirmed and what was not.** For every source below I confirmed
the study, the sample size and the specific result quoted in the text. Volume,
issue and page numbers were confirmed for Diaz, Ekelund, Quer and Sorkin; for
Killick, Rubin, Mattingly and Thompson they are the standard citation and are
flagged where uncertain. **No number in this document was invented** — where a
figure did not exist, the text says so instead.

- Aronne LJ et al. Continued Treatment With Tirzepatide for Maintenance of Weight Reduction in Adults With Obesity: The SURMOUNT-4 Randomized Clinical Trial. *JAMA* 2024;331(1):38-48. <https://pubmed.ncbi.nlm.nih.gov/38078870/>
- Diaz KM, Howard VJ, Hutto B et al. Patterns of Sedentary Behavior and Mortality in U.S. Middle-Aged and Older Adults: A National Cohort Study. *Ann Intern Med* 2017;167(7):465-475. n = 7,985. <https://pubmed.ncbi.nlm.nih.gov/28892811/>
- Ekelund U, Steene-Johannessen J, Brown WJ et al. Does physical activity attenuate, or even eliminate, the detrimental association of sitting time with mortality? A harmonised meta-analysis of data from more than 1 million men and women. *Lancet* 2016;388(10051):1302-1310. n = 1,005,791. <https://pubmed.ncbi.nlm.nih.gov/27475271/>
- Killick R, Fearnhead P, Eckley IA. Optimal detection of changepoints with a linear computational cost. *J Am Stat Assoc* 2012;107(500):1590-1598.
- Mattingly SM et al. The effects of seasons and weather on sleep patterns measured through longitudinal multimodal sensing. *npj Digital Medicine* 2021; doi:10.1038/s41746-021-00435-2. n = 216. <https://www.nature.com/articles/s41746-021-00435-2>
- Quer G, Gouda P, Galarnyk M, Topol EJ, Steinhubl SR. Inter- and intraindividual variability in daily resting heart rate and its associations with age, sex, sleep, BMI, and time of year: Retrospective, longitudinal cohort study of 92,457 adults. *PLOS ONE* 2020;15(2):e0227709. <https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0227709>
- Rubin DB. Inference and missing data. *Biometrika* 1976;63(3):581-592.
- Sorkin JD, Muller DC, Andres R. Longitudinal change in height of men and women: implications for interpretation of the body mass index: the Baltimore Longitudinal Study of Aging. *Am J Epidemiol* 1999;150(9):969-977. <https://pubmed.ncbi.nlm.nih.gov/10547143/>
- Thompson IM, Tangen CM, Goodman PJ, Probstfield JL, Moinpour CM, Coltman CA. Erectile dysfunction and subsequent cardiovascular disease. *JAMA* 2005;294(23):2996-3002. n = 9,457 (placebo arm, Prostate Cancer Prevention Trial). ⚠️ Volume/issue/page numbers taken from the standard citation and **not** independently confirmed against the JAMA record; the study, n, follow-up and hazard ratios were.
