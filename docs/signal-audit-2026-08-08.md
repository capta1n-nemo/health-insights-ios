# The signal audit — every card against every signal

**Backlog `P23`, the reader's own ask.** Written 2026-08-08 against the export
generated **2026-08-07T07:09:11Z** (build `0.1.0 (398) · 25a276b`,
`schemaVersion 4`).

> ⚠️ **This document produces no visible change, and that is the point.** It is
> the record of what every card reads, what it could read, what it refuses, and
> **which of its numbers are guesses**. Nothing here is a build instruction. A
> session that arrives at this file and starts writing Swift has misread it.

---

## Why this exists, in one paragraph

`B19` is the proof. Five constants in `Energy.swift` set that card's entire
dynamic range, **none of them appears in any literature**, and nobody noticed
until a research pass went looking. The question this document answers is: *how
many other cards are like that?* The answer, measured below, is **most of
them** — and the ones that are not are not better by accident, they are the four
that happen to sit on a published dose (`soundExposure`, `fitness`'s dose term,
`cardiovascularRisk`, `nutrition`'s targets).

---

## Method — what was counted, and how

| | |
| --- | --- |
| Source | `~/HealthSeed/exports/health-insights-export-new.json` (172 MB), outside the repo, per `docs/privacy-and-ip.md` |
| Counted with | a throwaway script over the parsed JSON — not the app, not the Data tab |
| "Coverage" means | **calendar days carrying at least one sample**, in the 90 days ending 2026-08-07 (the export's own `generatedAt`) |
| Not counted | row totals as a proxy for coverage. A row count is a trap: `physicalEffort` has 46,729 rows across **16** days |

⚠️ **Every coverage figure below was counted. None was inferred.** Eight domains
were once called "already arriving" and measured at zero rows; that is the rule
this section exists to obey.

⚠️ **No health reading appears in this document** — only counts, day-coverage,
source counts and code constants. The shape of a finding, never the reading.

### Independent confirmation of the brief's figures

| Claim | Counted here | Verdict |
| --- | --- | --- |
| 377,284 samples | 377,284 | ✅ |
| 108,611 unmodelled rows | 108,611 | ✅ |
| 64 modelled metrics | 64 metric types carry ≥1 row | ✅ |
| 149 imported-but-not-modelled identifiers | 149 distinct identifiers | ✅ |

One discrepancy, stated rather than smoothed over: the inventory file shipped
with the export reports **485,820** readings in total; the two arrays sum to
**485,895**, a difference of **75 rows**. Cause unknown. Small, but a generator
that disagrees with its own source by an unexplained amount is worth an hour
before anything is built on its totals.

---

## 0. The findings, in order of how much they matter

1. **Nutrition's entire input set is dead.** Across **19** dietary metrics the
   card scores, **0 of the last 90 days** carry a single sample. The most recent
   dietary reading of any kind is 2026-04-23. The card is not thin — it is
   empty, and has been for over three months. §3.10.
2. **Sleep scores 0.10 on a quantity another document in this repo forbids in
   arithmetic.** `Weight.restorative = 0.10` reads `sleepDeepMinutes` and
   `sleepRemMinutes`. `docs/stress-design-2026-08-07.md` §2.1 lists "sleep stages
   (deep/REM) in any arithmetic" as **forbidden outright**, on consumer
   four-stage classification accuracy of 60–75 % (JCSM 2025 meta-analysis, 24
   studies / 798 patients, PMID 39484805). Two shipped documents disagree. §3.3.
3. **Readiness — the app's flagship daily number — has six weights and no
   source for any of them.** 0.40 / 0.25 / 0.20 / 0.10 / 0.05 / 0.05. Nothing in
   `ReadinessScore.swift` and nothing in `docs/` justifies a single one. This is
   `B19`'s failure at larger scale, and it has not been named until now. §3.1.
4. **Readiness's sleep component does not do what its own comment says.** The
   comment reads *"vs a 7.5 h target (6 h ≈ 55, 8 h ≈ 90)"*; the code is
   `clamp((value − 4) / (8 − 4) × 100)`, which scores 6 h at **50** and 8 h at
   **100**. The worked examples in the comment are wrong about the line beneath
   them. §3.1.
5. **Heart Health puts its largest weight on its thinnest signal.** VO₂max
   carries **0.45** and appears on **4 of the last 90 days**. §3.5.
6. **No card's weights have ever been tested against an outcome, and cannot be.**
   Every one of the 18 cards in this export carries a `history` array of length
   **0** — **zero prediction-versus-actual pairs exist anywhere**. This is `D60`,
   reported fixed, but the fix postdates the only export that exists. `P24`
   (model accuracy) has nothing to run on. §6.
7. **Four cards cannot be audited at all from any export that exists.** The file
   is `schemaVersion 4`; `HealthDataExport.schemaVersion` in the tree is **7**.
   The v4 file carries no `calendarEvents` and no `supplements`, so Work impact,
   Travel drain, Social battery and Supplement stack have **no measurable
   coverage**. Not "no data" — *unmeasurable*, which is a different and worse
   thing to have to say. This is `D61`, and it now blocks a second workstream.
   §6.
8. **The same signal carries five different weights in five cards, and nothing
   reconciles them.** Overnight rMSSD is 38 % of Readiness, 25 % of Heart
   Health, 33 % of Sustained load, 18 % of Mental health and 25–27 % of the
   Symptom radar. Each is defensible alone; no document defends the set.
   **There is no weight registry.** §5.
9. **Gait spends 29 % of its weight on two channels that mostly say nothing.**
   `walkingSteadiness` (weight 0.5) covers **12 of 90 days**; `walkingAsymmetry`
   (weight 0.5) is **exactly 0 in 71.7 % of its 6,701 samples**. §3.13.
10. **Seven declared body-dimension metrics have never carried a row**, and the
    Symptom radar's newest and highest-weighted channel carries none either. §1.

---

## 1. The ledger — what exists

### 1.1 Declared versus present

`MetricType` declares **78** cases. **64** carry at least one row in the export.
**14 are declared and empty:**

| Empty metric | Why it is empty | Who reads it |
| --- | --- | --- |
| `waistCircumference` | | Body composition, Data tab |
| `hipCircumference` | | |
| `chestCircumference` | seven body dimensions — **no tape measure and no LiDAR capture has ever happened.** The `BodyScan` path exists; nothing has run it | |
| `neckCircumference` | | |
| `shoulderWidth` | | |
| `thighCircumference` | | |
| `upperArmCircumference` | | |
| `basalBodyTemperature` | **promoted after this export was taken.** The data exists — as raw `HKQuantityTypeIdentifierBasalBodyTemperature`, 138 rows over 126 days, **78 of the last 90** | Symptom radar, at weight **1.0** |
| `atrialFibrillationBurden` | Apple Watch has never raised one | Substance impact (`"holiday heart"`) |
| `dayStrain` | Whoop is not connected | Fitness |
| `bloodGlucose` | no CGM, no meter | Data tab only |
| `peripheralPerfusionIndex` | not written by any connected source | Data tab only |
| `dietaryWater` | never logged | Nutrition (scored, sex-specific figure) |
| `dietaryVitaminA` | never logged, and **absent from the raw layer too** | Nutrition (`MicronutrientTargets.targetable`) |

⚠️ **`basalBodyTemperature` is the one to act on.** `HealthWatchModel.watched`
gives it weight 1.0 and its doc comment argues, correctly, that it *rescues* the
thermal channel on nights the ring was on charge. On this export it rescues
nothing, because the promotion commit postdates the file. The channel is real
and unproven; the next export decides.

### 1.2 The raw catalogue — 149 identifiers, 108,611 rows

| Provider prefix | Identifiers | Rows |
| --- | ---: | ---: |
| `oura.*` | 115 | 15,861 |
| `HKQuantityTypeIdentifier*` / `HKCategoryTypeIdentifier*` | 25 | 81,364 |
| `withings.measure.*` | 8 | 1,616 |
| `apple_health.sleep_segment` | 1 | 9,770 |

**77 % of the unmodelled identifiers are Oura's, and they are almost all
composites or their sub-scores** — `daily_readiness.score`, its nine
contributors, `daily_sleep.score`, its seven, `daily_resilience.level`,
`daily_stress.*`. This is the standing refusal working as designed: a vendor
composite with an undisclosed formula may be **relayed** as a labelled second
opinion, never **blended**. See `docs/data-opportunities.md` §"Oura's own scores".

**The one Oura composite that was promoted is `vascularAge`, and the relay rule
survives it.** `HeartAgeAnalyser` reads it, reports it beside the app's own
figure with the source named, and gives it **weight 0** — it reaches the screen
and never the arithmetic. Verified at `HeartAgeAnalyser.swift:198` and
`CardiovascularRiskInsight.swift:219–224`. ✅ **This is the pattern every future
vendor score should copy.**

---

## 2. Coverage — every modelled metric, counted

Days carrying ≥1 sample, in the 90 days ending 2026-08-07.

### 2.1 Dense — 60+ days of 90

| Metric | days/90 | days/365 | rows | sources |
| --- | ---: | ---: | ---: | ---: |
| `stepCount` | 91 | 366 | 72,430 | 5 |
| `distanceWalkingRunning` | 91 | 366 | 35,168 | 4 |
| `walkingSpeed` | 90 | 362 | 16,931 | 2 |
| `walkingStepLength` | 90 | 362 | 16,930 | 2 |
| `walkingDoubleSupport` | 90 | 362 | 15,282 | 2 |
| `activeMedicationLevel` (modelled) | 90 | 172 | 172 | 1 |
| `activeEnergyBurned` | 86 | 228 | 67,366 | 5 |
| `flightsClimbed` | 82 | 338 | 3,651 | 4 |
| `heartRate` | 80 | 149 | 73,654 | 4 |
| `walkingAsymmetry` | 79 | 297 | 6,701 | 2 |
| `restingHeartRate` | 70 | 140 | 367 | 3 |
| `respiratoryRate` | 68 | 134 | 1,957 | 3 |
| `sleepDurationHours` | 68 | 128 | 249 | 2 |
| `sleepEfficiency` | 68 | 128 | 249 | 2 |
| `sleepDeepMinutes` | 68 | 128 | 245 | 2 |
| `sleepRemMinutes` | 68 | 128 | 245 | 2 |
| `heartRateVariabilityRMSSD` | 67 | 117 | 117 | 1 |
| `sleepLatencyMinutes` | 67 | 117 | 117 | 1 |
| `heartRateVariabilitySDNN` | 65 | 142 | 8,244 | 2 |
| `sleepOnset` | 64 | 120 | 240 | 2 |
| `skinTemperature` | 64 | 109 | 109 | 1 |
| `skinTemperatureDeviation` | 64 | 109 | 109 | 1 |
| `oxygenSaturation` | 63 | 110 | 217 | 2 |
| `breathingDisturbanceIndex` | 62 | 108 | 108 | 1 |
| `vascularAge` | 62 | 111 | 111 | 1 |
| `bodyMass` | 61 | 119 | 1,243 | 8 |

### 2.2 Intermittent — 10 to 59 days of 90

| Metric | days/90 | rows | note |
| --- | ---: | ---: | --- |
| `headphoneSoundDose` | 54 | 473 | derived by this app |
| `bodyTemperature` | 53 | 107 | |
| `bodyFatPercentage` | 26 | 621 | scale, ~2×/week |
| `leanBodyMass` | 26 | 577 | |
| `muscleMass` / `bodyWaterPercentage` / `boneMass` | 26 | 154 each | |
| `screenTimeMinutes` | 25 | 26 | hand-entered; **every sample is in the window** |
| `exerciseMinutes` | 20 | 4,672 | one distinct value (1); correctly `.cumulativeTotal` |
| `environmentalSoundDose` | 17 | 293 | watch-only, and the card already says so |
| `physicalEffort` | 16 | 46,729 | **the row-count trap, in one line** |
| `walkingSteadiness` | 12 | 104 | rolling window, moves late |
| `walkingHeartRateAverage` | 10 | 153 | |

### 2.3 Sparse — under 10 days of 90

| Metric | days/90 | rows | who weights it |
| --- | ---: | ---: | --- |
| `bloodPressureSystolic` | 4 | 50 | Cardiovascular risk (**mandatory**), Biological age, Blood pressure |
| `bloodPressureDiastolic` | 4 | 50 | Blood pressure |
| `vo2Max` | **4** | 87 | **Heart Health at 0.45**, Fitness at 0.55, Biological age, CV risk |
| `heartRateRecovery` | 2 | 17 | Heart Health, Fitness, Substance impact |
| `height` | **0** (last 2020-10-05) | 6 | BMI everywhere |

### 2.4 Zero of the last 90 days — the whole dietary block

`dietaryEnergy`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFat`,
`dietarySaturatedFat`, `dietarySugar`, `dietaryFibre`, `dietarySodium`,
`dietaryPotassium`, `dietaryCaffeine`, `dietaryMonounsaturatedFat`,
`dietaryPolyunsaturatedFat`, `dietaryCholesterol`, `dietaryCalcium`,
`dietaryIron`, `dietaryMagnesium`, `dietaryZinc`, `dietaryVitaminC`,
`dietaryVitaminD`, `dietaryVitaminB12` — **all 0/90**. Latest of any of them:
2026-04-23. The macros stopped a month earlier, 2026-03-22/23.

---

## 3. The card-by-card audit

21 models are registered in `InsightEngine.init`. For each: **reads today ·
weights and their provenance · could read · deliberately ignores · coverage
verdict.**

**Provenance vocabulary, used consistently below:**

| Verdict | Means |
| --- | --- |
| **published** | the number is read off a named external source |
| **derived** | computed from something else, not chosen — no tunable value exists |
| **user-set** | the reader chose it and the code says so |
| **reasoned** | argued from a stated principle, but the *magnitude* has no source |
| **inherited** | carried forward from an earlier version, origin unrecorded |
| **guessed** | a number with neither argument nor source |

---

### 3.1 Readiness — `ReadinessScore`

**Reads:** `heartRateVariabilityRMSSD` (fallback `SDNN`), `restingHeartRate`,
`sleepDurationHours`, `skinTemperatureDeviation`, `respiratoryRate`,
`oxygenSaturation`. Any-channel coverage **75 / 90 days**.

| Component | Weight | Coverage | Provenance |
| --- | ---: | ---: | --- |
| HRV vs baseline | 0.40 | 67/90 | **guessed** |
| Resting HR vs baseline | 0.25 | 70/90 | **guessed** |
| Sleep duration | 0.20 | 68/90 | **guessed** |
| Skin-temp deviation | 0.10 | 64/90 | **guessed** |
| Respiratory rate | 0.05 | 68/90 | **guessed** |
| Blood oxygen | 0.05 | 63/90 | **guessed** |

⚠️ **Six numbers, no source for any of them.** The file argues *direction*
carefully and *magnitude* not at all. These weights are mentioned exactly once
anywhere else in the tree — `docs/data-opportunities.md`, in a passage refusing
to fold Oura's resilience into Readiness *"partly built from the same HRV and
resting HR our score already weights at 0.40 and 0.25"*. That is a **correct**
double-counting argument, and it treats the two figures as given. **Nothing
anywhere derives them.**

The same passage names the fix this audit would want: *"a persistent gap is
either a bug in our weights or a real difference in what the two models value,
and the user should see either."* Oura's `daily_readiness.score` covers **66 of
the last 90 days** — a ready-made external comparator, relayed and never blended.
**Disagreement-as-the-number is the one honest way this card's weights could ever
be challenged from data the reader already has.**

**Two defects found while auditing, both checkable:**

1. **The sleep component's comment contradicts its code.** Comment: *"vs a 7.5 h
   target (6 h ≈ 55, 8 h ≈ 90)"*. Code: `clamp((value − 4) / (8 − 4) × 100)` →
   6 h = **50**, 8 h = **100**. There is no 7.5 h anywhere in the expression.
2. **The type's header lists five components; six exist.** Blood oxygen is
   missing from the doc-comment list.

**Could read, that exists:** `heartRate` (80/90) — the diurnal resting floor;
`sleepLatencyMinutes` (67/90); `breathingDisturbanceIndex` (62/90). None is
proposed here — see the standing refusals in §5.

**Deliberately ignores, and why (all correct):** Oura's `daily_readiness.score`
and its nine contributors, 66/90 days, undisclosed formula — relay only.
`oura.daily_stress.*` (89/90 days) — *no published mapping from "3,600 s of high
stress" to anything* (`data-opportunities` #9). `oura.daily_resilience.*`
(63/90) — same.

**Verdict:** the app's most-looked-at number is its least-justified. **This is
`B19`'s sibling and it should be on the backlog beside it.**

---

### 3.2 Symptom radar — `HealthWatchModel`

**Reads:** four thermal metrics, `restingHeartRate`, both HRV flavours,
`respiratoryRate`, `oxygenSaturation`.

⚠️ **The `watched` table lists eight rows and the radar has four voting
channels.** `collapsingDuplicates` folds everything sharing a `MetricFamily` into
one signal and keeps whichever leans harder — and `MetricType.family` puts both
HRV flavours in `.autonomic`, all four thermal metrics in `.thermal`, and
**`respiratoryRate` and `oxygenSaturation` together in `.respiratory`**. The
comment beside the table says this for the thermal group; it does not say it for
the other two, and the table reads as six independent weights.

| Voting channel | Weight applied | Coverage | Provenance |
| --- | ---: | ---: | --- |
| `.thermal` — `skinTemperatureDeviation`, `skinTemperature`, `bodyTemperature`, `basalBodyTemperature` | 1.0 | 64/90 with any thermal reading; **`basalBodyTemperature` 0/90 in this export** | **reasoned**, ordinally supported |
| `.cardiac` — `restingHeartRate` | 0.9 | 70/90 | **reasoned** |
| `.autonomic` — rMSSD (0.9) or SDNN (0.8), whichever leans harder | 0.9 / 0.8 | 67/90, 65/90 | **reasoned** |
| `.respiratory` — `respiratoryRate` (0.8) or `oxygenSaturation` (0.5), whichever leans harder | 0.8 / 0.5 | 68/90, 63/90 | **reasoned** |

So the effective total is **3.3–3.6** depending on which twin survives, not the
5.9 the table appears to sum to. **`oxygenSaturation`'s 0.5 only ever applies on
a day it out-leans respiratory rate** — which is a defensible design and is not
what the table looks like.

**The ordering is supported; the numbers are not.** The weight scale is declared
to be *specificity for illness*, and `docs/illness-detection-evidence-2026-08-07.md`
supports temperature ranking first — TemPredict found temperature worth **5–8
percentage points of absolute AUC** and it is the earliest signal. It does not
support 1.0 versus 0.9 versus 0.5. **This is the best-argued guessed table in the
app** — the argument is real, the magnitudes are still invented.

⚠️ **The one thing that is not guesswork here is the decision interval**, moved
5.0 → 6.0 for the max-over-two-thermometers inflation, and pinned by
`SymptomRadarTests` simulating the real path. **That is what a justified constant
looks like:** it is measured against a stated false-alarm budget rather than
chosen.

**Deliberately ignores:** everything without a physiological illness direction.
Correct, and `illness-detection-evidence` constrains it further — prospective PPV
is 4–12 %, two-thirds of genuine infections produce no clear signal, and the one
RCT's physiological arm returned **zero** confirmed infections (DETECT-AHEAD,
*Lancet Digit Health* 2024: 26 alerts → 6 tested → 0 positive).

---

### 3.3 Sleep — `SleepInsight.Weight`

**Reads:** `sleepDurationHours`, `sleepOnset`, `sleepEfficiency`,
`sleepDeepMinutes`, `sleepRemMinutes`, `sleepLatencyMinutes`,
`oxygenSaturation`, `respiratoryRate`, `breathingDisturbanceIndex`,
`skinTemperatureDeviation`, `skinTemperature`, `bodyTemperature`.

| Term | Weight | Provenance |
| --- | ---: | --- |
| `duration` | 0.27 | **inherited** (was 0.30; reduced to fund latency) |
| `regularity` | 0.18 | **published-in-part** — see below |
| `efficiency` | 0.13 | **guessed** |
| `debt` | 0.12 | **guessed** magnitude; the *quantity* is well-researched (`docs/sleep-debt-research-2026-08-07.md`) |
| `restorative` | 0.10 | ⚠️ **contradicted** — see below |
| `oxygen` | 0.07 | **guessed** |
| `latency` | 0.05 | thresholds **published** (Ohayon 2017, NSF consensus: ≤15 min appropriate, >30 inappropriate); weight **guessed** |
| `respiratory` | 0.05 | **guessed** |
| `temperature` | 0.03 | **guessed** |
| `consistency` | 0.0 | **retired**, kept visible — good practice |

**The good part, and it should be copied.** The nine coefficients sum to exactly
1, they live in one table both the score and the chart read, and **a new term is
funded out of an existing one rather than added on top**. Latency took 0.03 from
duration and 0.02 from consistency; regularity took consistency's remaining 0.08
plus the bedtime-spread 0.10 and *"not a point more"*. That conservation rule is
the single best weighting discipline in this codebase.

**⚠️ Finding 1 — `restorative = 0.10` is forbidden by another document in this
repo.** It reads deep and REM minutes. `docs/stress-design-2026-08-07.md` §2.1:
*sleep stages (deep/REM) in any arithmetic* — **forbidden outright**, because
consumer four-stage classification accuracy is 60–75 % (JCSM 2025 meta-analysis,
24 studies / 798 patients, PMID 39484805). Both documents are current and they
contradict each other. **One of them has to change, and this audit does not get
to decide which** — but the sleep card is the one carrying the weight, so it is
the one that owes an argument.

**⚠️ Finding 2 — `regularity = 0.18` is half a citation.** The code says
*"beat sleep duration head-to-head for mortality in UK Biobank (n = 88,975)"*
with **no author, no year and no venue**. The claim is almost certainly right and
is currently unverifiable from the code. A citation without a handle is a
citation the next session cannot check.

**Could read, that exists:** WASO, derivable from time-in-bed − sleep − latency,
with a published band (Ohayon 2017: ≤20 min appropriate, >50 inappropriate) —
`data-opportunities` #5, still open. `apple_health.sleep_segment` (9,770 rows,
72/90 days) already feeds stages; the **sleep-fragment** half of `P27` is
unfixed, and fragment filtering was measured to cut sleep-efficiency noise 59 %.

**Deliberately ignores:** `oura.daily_sleep.score` and its seven contributors
(66/90) — relay only. `breathingDisturbanceIndex` is charted and **not scored**,
correctly: no validated BDI→AHI conversion is published, and AASM's bands are
defined on polysomnography, not a ring.

---

### 3.4 Energy — `EnergyModel`

**Already audited and already refuted.** `B19` names five constants that set the
whole dynamic range and states plainly that **none appears in any literature**.
Two are checkable and both fail:

- Sleep duration is **~4× too strong** — the only within-person effect found
  (Kuula/Bauducco 2025, n = 205, 4,868 actigraphy nights) is β = −0.19 KSS per
  hour, so four fewer hours ≈ **9.5 points**; the card moves **37.5**.
- HRV moves the card 16 points on an association nobody has found — Smyth/van
  Berkel 2023 (n = 8, 125–386 paired observations each) found wearable HRV
  predicted subjective vigor in **0 of 8** participants.

**And the proposed replacement was also refuted** —
`docs/energy-design-2026-08-07.md` carries a not-build-ready banner after three
hostile reviews.

**What this audit adds:** the card's inputs are not the problem. `activeEnergyBurned`
86/90, `heartRate` 80/90, `restingHeartRate` 70/90, `sleepDurationHours` 68/90,
`heartRateVariabilityRMSSD` 67/90 — **every input is dense.** The reader's ask
was *"more data sources"*; the measurement says more sources cannot help, because
the published alertness curve's own resolution on a 0–100 scale is about ±21
points against a diurnal swing of about 26. **The error budget is dominated by
the model, not the inputs.** Do not let a future session re-answer this by adding
signals.

---

### 3.5 Heart Health — `HeartHealthScore`

| Component | Weight | Coverage | Provenance |
| --- | ---: | ---: | --- |
| VO₂max | **0.45** | **4 / 90 days** | **guessed** |
| Resting HR | 0.25 | 70/90 | **guessed** |
| HRV | 0.25 | 67/90 | **guessed** |
| Respiratory stability | 0.05 | 68/90 | **guessed** |

⚠️ **The largest weight sits on the second-thinnest signal on the card.** VO₂max
appears on 4 of the last 90 days (87 rows lifetime, last 2026-07-31, four
sources). Any-channel coverage is 76/90, so the card is *usually* computable —
but 0.45 of it rests on a value that is typically weeks old.

**Three uncited scoring curves, two of which say so themselves:**

- `vo2Score` — reference midpoints *"from standard cardiorespiratory-fitness
  norms"*. **Which norms?** No source. The same table is inverted by
  `FitnessAgeModel` and by `BiologicalAgeModel`, so **one uncited table sets
  three cards' idea of "average for your age"**.
- `restingHRScore` — `(85 − hr) / (85 − 50)`. Two endpoints, no source.
- `hrvScore` — `ref = max(20, 70 − (age − 20) × 0.6)`, commented *"Rough
  'healthy' reference"*. **The code volunteers that it is a guess**, which is
  more honest than most of what is above it and still a guess reaching the
  reader's screen as a number.

**Deliberately ignores:** nothing it should not. `heartRateRecovery` is declared
and covers 2/90 days — correctly contributes nothing rather than guessing.

---

### 3.6 Fitness — `FitnessInsight`

| Term | Weight | Provenance |
| --- | ---: | --- |
| VO₂max level | 0.55 | **inherited** — designed so the no-dose fallback renormalises to 0.6875/0.3125, *"within a point or two of the old 0.7 / 0.3"*. The origin of 0.7 / 0.3 is unrecorded anywhere |
| VO₂max trajectory | 0.25 | **inherited**, same |
| Activity dose | 0.20 | **published scale, guessed share** — `ActivityDoseModel` scores against WHO 2020 (150–300 min/week moderate, with a stated dose–response), and Apple's exercise minute *is* the moderate-intensity definition |

**Coverage:** `vo2Max` 4/90 (0.80 of the weight), `exerciseMinutes` 20/90 (the
remaining 0.20). **The whole card runs on two signals that between them cover 22
distinct days of the last 90.** The supporting metrics are dense —
`stepCount` 91/90, `activeEnergyBurned` 86/90, `flightsClimbed` 82/90,
`physicalEffort` 16/90 — and carry **no weight at all**.

**Could read, that exists:** `physicalEffort` is a MET by definition and has a
published intensity band table (`EffortIntensityModel`), but 16/90 days — it
would be a scored term reporting on one day in six. `HKQuantityTypeIdentifierRunningSpeed`
(191 rows, **4 days lifetime**) and `SixMinuteWalkTestDistance` (24 rows, 1 day
in 90) are both too thin to score. Say so rather than adding them.

**Deliberately ignores:** `dayStrain` is declared and has **never carried a
row** — Whoop is not connected. Harmless, but it is a candidate metric that can
never resolve, and `CandidateReachabilityTests` should be asked whether it minds.

---

### 3.7 Cardiovascular risk — `CardiovascularRiskModel`

**The best-grounded card in the app.** SCORE2 / SCORE2-OP, 2021 European Society
of Cardiology guidelines. Every coefficient is **published**; there is no
house-chosen weight in the risk figure at all.

**Coverage is the problem instead.** `bloodPressureSystolic` is **mandatory** and
covers **4 of the last 90 days** (50 rows lifetime, four sources including manual
entry). `vo2Max` 4/90. `vascularAge` 62/90 and correctly at weight 0.

**Verdict: published model, stale inputs.** The honest version of this card is
the one that prints *how old the cuff reading is* beside the risk figure — which
`InsightResult.subheadline` was added for and which the Blood Pressure card
already does.

---

### 3.8 Blood pressure — `BloodPressureEstimator`

Badged **experimental**, which is the correct confidence level. Contributor
weights come from a **fit** (`weighting == .fit`) against the reader's own cuff
readings — so they are **derived**, not chosen, and that is the right shape.

⚠️ **State the n.** 50 systolic and 50 diastolic readings lifetime, spanning
2020-10-05 → 2026-08-02, across **15 distinct days**, **4 of them in the last
90**. A per-person fit on 15 days is a fit whose error bar is wider than most of
what it would predict. The card's own "Experimental" badge carries this, and
`InsightResult.subheadline` exists precisely because this card once led with a
cuff number while the badge referred to the estimate.

---

### 3.9 Body composition — `BodyCompositionInsight`

| Term | Weight | Provenance |
| --- | ---: | --- |
| Level (body fat vs published range; BMI fallback) | 0.45 | **user-set** — *"I think it should be 45%, maybe 50% max"* (2026-08-02), and the code says so |
| Rate of change | 0.30 | **user-set**, same decision |
| Quality (lean share of change) | 0.25 | **user-set**, same decision |

⚠️ **This is the cleanest provenance on any card, and it is worth naming as a
category.** A weight the reader chose, recorded with the quote and the date, is
*not* a guess — it is a stated preference. It cannot be falsified by literature
because it is not a claim about the world. **Every card whose weights are
arbitrary should either get a source or get this treatment.**

**Coverage:** `bodyMass` 61/90 across 8 sources; `bodyFatPercentage`,
`leanBodyMass`, `muscleMass`, `bodyWaterPercentage`, `boneMass` all 26/90 (the
Withings scale, roughly twice a week). `height` **0/90 and last measured
2020-10-05** — BMI everywhere in the app rests on a six-year-old figure that
nothing prompts to refresh.

**Tracked, not scored, at weight 0 — and correct:** `activeMedicationLevel`
(modelled, 90/90), `dietaryEnergy` (0/90), `muscleMass`. A modelled drug level
must never carry weight on a card, and it does not.

**Could read, that exists:** `HKQuantityTypeIdentifierBasalEnergyBurned` — 46,356
rows but **25/90 days**, and `data-opportunities` #6 already has the honest
framing (Mifflin-St Jeor 1990 predicts BMR from four facts the app already
holds; report measured-versus-predicted, do not score it).
`HKQuantityTypeIdentifierBodyMassIndex` (46/90) is a **vendor's** BMI — the app
computes its own from mass and height, so importing it would be two BMIs
disagreeing on screen.

---

### 3.10 Nutrition — `NutritionInsight`

**Targets are published** — dietary guidance, sex- and age-specific, with the
sex requirement made **mandatory** precisely because iron differs more than
twofold between rows. That part is right.

⚠️ **And the card has no data at all.** All 19 dietary metrics: **0 of the last
90 days.** Latest reading of any kind 2026-04-23; the macros stopped
2026-03-22/23. Lifetime volumes are tiny — `dietaryEnergy` 74 rows over 30 days,
`dietaryCaffeine` 6 rows, `dietaryZinc` / `dietaryMagnesium` / `dietaryVitaminD`
/ `dietaryVitaminB12` 6 rows each, `dietaryWater` and `dietaryVitaminA` **zero,
ever**.

**This is exactly the case the reader's standing instruction was written for:
thin data means print the error bar, not show nothing — and *no* data means say
so, in the card, in those words.** The card is unhidden by rule (`isWorthShowing`
is unconditionally true since `D59`), so what it says in this state is the whole
product.

**A finding about the raw layer, counted:** six HealthKit dietary identifiers
still arrive **unmodelled** — `DietaryCalcium`, `DietaryCholesterol`,
`DietaryFatMonounsaturated`, `DietaryFatPolyunsaturated`, `DietaryIron`,
`DietaryVitaminC`, 107 rows each, **0/90 days**. They duplicate promoted metrics.
Promoting them would add nothing; **deleting the duplication would remove 642
rows of confusing shadow data from the Data tab.**

---

### 3.11 Metabolism — `MetabolismInsight`

| Constant | Value | Provenance |
| --- | ---: | --- |
| BMR instrument | Katch-McArdle | ✅ **published, and named in code** — uses lean mass, so it needs no age or sex, which is the right instrument exactly when a scale reports composition |
| `kcalPerKilogram` | 7,700 | **conventional, and the code says so** — a whole-body average, with the fat/lean split named as a planned refinement (`planned-modules.md` module 5). No handle to a source |
| `thermicEffectShare` | 0.10 | **conventional, and the code says so** — *"the conventional mixed-diet figure the guidance itself assumes"*. Which guidance is not named |
| `windowDays` / `minimumLoggedDays` | 28 / 14 | **reasoned** — *"a fortnight is the floor, water weight swamps anything shorter"* |
| `underLoggingRatio` | 1.10 | **guessed** |

⚠️ **`underLoggingRatio` is the one to look at, and its role is narrower than it
sounds.** It is a **threshold, not a multiplier**: above it, the card leads with
the food log rather than with metabolism. So it does not scale the answer — it
decides which of two answers the reader is shown. Under-reporting of dietary
intake has a large literature; **1.10 has no source in the code and no repo
document behind it**, and it is the switch that decides whether the card blames
the log or the body.

⚠️ **Two "conventional" constants are better than two guesses and still short of
a citation.** Both name themselves honestly as conventions, which is the standard
rule 1 asks for — neither gives the next session anything to check.

**Coverage:** it needs `dietaryEnergy`, which is **0/90 days**, against a
`minimumLoggedDays = 14` gate. **The card cannot run and correctly says nothing.**

---

### 3.12 Sustained load — `SustainedLoadModel`

| Channel | Weight | Coverage | Provenance |
| --- | ---: | ---: | --- |
| `heartRateVariabilityRMSSD` | 1.0 | 67/90 | **reasoned** |
| `restingHeartRate` | 0.9 | 70/90 | **reasoned** |
| `respiratoryRate` | 0.6 | 68/90 | **reasoned** |
| `sleepDurationHours` | 0.5 | 68/90 | **reasoned** — and the reason given is causal, not correlational: short sleep *causes* the other three to drift, *"so leaving it out would report the consequence and hide the cause"* |

**The windows are published; the weights are not.** `recentDays = 28` and
`referenceDays = 90` are supported by `docs/stress-design-2026-08-07.md` §2.2:
day-to-day CV of lnRMSSD is 3–13 %, and a 28-day median rather than a daily value
is the permitted read (Plews et al., *Eur J Appl Physiol* 2012;112:3729 and
*IJSPP* 2014;9:783). RMSSD as *the* time-domain arousal index is likewise
supported (Shaffer & Ginsberg, *Front Public Health* 2017). **1.0 / 0.9 / 0.6 /
0.5 is supported by nothing.**

**Deliberately ignores, and this is the card's best decision:** daytime HRV.
Speaking systematically raises RSA and SDNN, so a day of back-to-back meetings —
the archetypal stressful day — biases the metric *toward* "restored". That is the
specific reason Apple restricted Vitals to overnight. **A refusal with a
mechanism behind it is worth more than an input.**

Also correctly refused: `oura.daily_stress.stress_high` / `recovery_high`
(**89/90 days — the densest unmodelled Oura signal there is**), and
`oura.daily_resilience.level` (63/90). No published mapping exists from a
vendor's stress-seconds to anything.

---

### 3.13 Gait — `GaitModel`

| Channel | Weight | Coverage | Provenance |
| --- | ---: | ---: | --- |
| `walkingSpeed` | 1.0 | 90/90 | **guessed** |
| `walkingStepLength` | 0.7 | 90/90 | **guessed** |
| `walkingDoubleSupport` | 0.7 | 90/90 | **guessed** |
| `walkingSteadiness` | 0.5 | **12/90** | **guessed** |
| `walkingAsymmetry` | 0.5 | 79/90, but **71.7 % of 6,701 samples are exactly 0** | **guessed** |

**The stated justification does not hold up.** The comment says speed leads
*"because it is the one with three decades of literature behind it"* — and
`GaitInsight.swift` contains **zero citations**. The nearest real source is
`data-opportunities` #7: Bohannon & Williams Andrews 2011 gives gait-speed norms
and 1.0 m/s as a standard clinical cut-point, which the entry itself says
*"justifies a bound, not a curve"* — and certainly not a 1.0 : 0.7 : 0.5 ratio.

⚠️ **1.0 of the 3.4 total weight — 29 % — sits on two channels that mostly say
nothing.** Steadiness reports on 12 of 90 days by construction (it is published
on a rolling window). Asymmetry is a floor-valued signal: 71.7 % of its samples
are exactly zero, which is a healthy gait correctly reporting nothing, and which
means its z-score denominator is built mostly from a constant.

**Everything else about this card is right**, and worth saying so: 90/90 coverage
on three channels from a phone in a pocket, the only card still reporting on a
week the ring spent on charge, and the only product anywhere that names *which
half* of speed moved.

**Could read, that exists:** `StairAscentSpeed` (11/90) and `StairDescentSpeed`
(9/90) — real gait signals, too thin to weight, and honest to chart.

---

### 3.14 Sound exposure — `SoundExposureModel`

✅ **The reference implementation. Every number is published.**

| Constant | Value | Source |
| --- | --- | --- |
| `allowanceLevel` / `allowanceHours` | 80 dB(A) / 40 h per week | **WHO/ITU H.870** recreational allowance for adults |
| NIOSH REL (reported, not scored) | 85 dB(A) / 8 h, 3 dB exchange | **NIOSH** |
| window | 7 days | because the allowance is stated over a week |

**There is no house-chosen weight in this card at all.** A dose is a level times
a time and lands on 0–100 by construction. The 3 dB exchange rate is physics, not
a preference.

**Coverage, and the refusal built on it:** `headphoneSoundDose` 54/90;
`environmentalSoundDose` **17/90**, watch-only. The card **reports them
separately and never sums them**, because summing would score every day the watch
spent in a drawer as silent. **That refusal is a measurement, not a taste** — it
is exactly what "count coverage, never infer it" produces when it is done before
the design instead of after.

---

### 3.15 Biological age — `BiologicalAgeModel`

**Reads:** `vo2Max` (4/90), `heartRateVariabilityRMSSD` (67/90),
`heartRateVariabilitySDNN` (65/90), `walkingSpeed` (90/90),
`bloodPressureSystolic` (4/90), `bodyFatPercentage` (26/90).

✅ **The weights are `derived`, not chosen:** `weight: term.precision /
totalPrecision`. Nothing is fitted, there is no tunable number in the model, and
the cost — an error bar around a decade — is **printed**. That is the trade every
commercial biological age declines to make, and it is the right one.

⚠️ **But the precisions are computed from anchor tables that carry no source.**
`BiologicalAgeModel.anchors` holds six-point age curves for overnight rMSSD and
SDNN with no citation; VO₂max defers to `FitnessAgeModel.anchors`, described only
as *"The norm table"*. **A derived weight is only as justified as the curve it
was derived from**, so the honest summary is: *the weighting scheme is sound and
the tables it weighs are unattributed.*

The one anchor decision that **is** documented is a good one: the first version
used classical five-minute supine rMSSD norms, every device here reports
whole-night HRV which runs far higher, the reader's value sat off the top of the
curve and the model correctly refused to invert it. The fix was to change the
table, not to add a caveat — *"documenting a bias is not handling one, and a
comment cannot correct a table."*

`deliberatelyExcluded` names resting heart rate and says why on the card: it
barely moves with age, so inverting it would add a number and no information.
**An exclusion the reader can read is worth more than an input.**

---

### 3.16 Mental health — `MentalHealthModel`

| Channel | Weight | Coverage | Provenance |
| --- | ---: | ---: | --- |
| `stepCount` "Moving around" | 1.0 | 91/90 | **guessed** |
| `sleepOnset` "When you went to bed" | 0.9 | 64/90 | **guessed** |
| `exerciseMinutes` "Deliberate exercise" | 0.8 | **20/90** | **guessed** |
| `heartRateVariabilityRMSSD` | 0.6 | 67/90 | **guessed** — and the card's own `alternative` string says it is *"the least specific signal here"*, which is an argument for the ordering and not for 0.6 |

**What this card gets right is not its weights — it is its refusals.** Every
channel carries an `alternative` as a **stored property, not a comment**, so the
ordinary non-mood explanation travels with the finding wherever it is rendered.
And the card **never reassures**: its top band means four numbers have not moved,
and it says so in those words.

⚠️ **The exercise channel at weight 0.8 reports on 20 of the last 90 days.**
Nearly a quarter of the card's weight is on a signal present one day in four and
a half.

---

### 3.17 Substance impact — `SubstanceResponseAnalyzer`

**Reads 11+ vitals before/after logged use**, widened on the reader's direction:
*"I want almost every vital to go into this."* There is **no per-metric weight
table** — the score uses a `breadthShare` mean over everything measured, so a
vital that holds steady is evidence the response is narrow and **pulls the
deduction down**. ✅ **A design where adding a signal can only lower the score if
the signal actually moved needs no weight justification at all**, and that is the
cleanest way out of this whole problem found anywhere in the codebase.

**What is guessed here is the band table**, not the weights: `band(for load)` cuts
at **20 / 50 / 80** with no source.

**Coverage — and it is the binding constraint:** **18 substance events** in the
whole export. `atrialFibrillationBurden` is watched and has **never carried a
row**. `heartRateRecovery` covers 2/90. `bloodPressureSystolic` 4/90. The card
correctly yields nothing from the thin channels rather than guessing, and `P16`'s
note already records the honest ceiling: ~4 exposure episodes means a
per-substance panel would near-duplicate the pooled card.

⚠️ `B19` records that a design produced 2026-08-07 understated substance
thresholds by ~2× **by dividing a paired effect by the wrong SD**. Anything
touching this card's thresholds must show the SD it divided by.

---

### 3.18–3.20 The calendar cards — Work impact, Travel drain, Social battery

| Card | Facet weights | Provenance |
| --- | --- | --- |
| Work impact | `gapFacetWeight` 0.6 / `peakFacetWeight` 0.4 | **reasoned** — the gap is a median over a dozen days each side, the peak is one day, so the steadier facet leads |
| Work / Travel | `responseShareAtFullContrast` 0.65, `responseShareAtNoContrast` 0.30 | **user-directed** — the code records that the reader overruled a version where the calendar was decorative |
| Social battery | `contactFacetWeight` 0.65 / `peopleFacetWeight` 0.35 | **reasoned** — hours are a median over a dozen days, headcount is thinner and often partly unknown |
| all three | `heavyExposureLevel` 0.75 | **guessed**, and honestly scoped: it names the quadrant only, and the score itself is a curve with no step in it |

**Body channels, all three cards:** `restingHeartRate` (70/90),
`heartRateVariabilityRMSSD` (67/90), `sleepDurationHours` (68/90) — dense, and
the same three the other cards weight differently.

⚠️ **Their exposure coverage cannot be counted, and this is a defect in the
export, not in the cards.** The file is `schemaVersion 4`;
`HealthDataExport.schemaVersion` in the tree is **7**, and the v4 file carries no
`calendarEvents` array at all. So how many meetings, how many trips, how many
reviewed events — **unknown**, and unknowable until a fresh export lands. That is
`D61`, and this audit is the second workstream it now blocks.

`docs/norms-and-telemetry.md` states the rule these cards are currently outside
of: *"Every quantity the app holds or derives must reach the export, because the
export is the only route from a phone to a server-side pool."*

**Social battery's one genuinely novel decision, recorded so it is not lost:**
the *direction* of its exposure term is read off the reader's own nights rather
than assumed. For some people a full diary is restorative, and scoring their
busiest fortnight as their worst would be the app asserting a personality it
never measured. **No other card in this app or any competitor does this**, and it
is the model for any future card that scores a behaviour rather than a vital.

---

### 3.21 Supplement stack — `SupplementStackInsight`

**Upper limits are published** (Tolerable Upper Intake Levels), the finding is
the **sum across the stack** rather than any one product, and the card **states
numbers and gives no instruction**. Weighting basis is `.worstOffender`, which
needs no share table.

⚠️ **Same export gap.** `supplements` is a `schemaVersion 7` key; the v4 file
does not carry it. Coverage: **unmeasurable**.

---

## 4. The weight-provenance ledger

Every score-bearing constant in the app, one table.

| Card | Weights | Verdict |
| --- | --- | --- |
| Cardiovascular risk | SCORE2 / SCORE2-OP coefficients | ✅ **published** (ESC 2021) |
| Sound exposure | 80 dB(A)/40 h; 85 dB(A)/8 h; 3 dB exchange | ✅ **published** (WHO/ITU H.870; NIOSH) |
| Biological age | precision ÷ total precision | ✅ **derived** — but from **uncited** anchor tables |
| Blood pressure | fitted contributor weights | ✅ **derived** — n = 15 distinct days, 4 in 90 |
| Substance impact | none (breadth mean) | ✅ **structurally weightless**; band cuts 20/50/80 **guessed** |
| Body composition | 0.45 / 0.30 / 0.25 | ✅ **user-set**, quoted and dated |
| Work / Travel / Social | 0.65/0.30; 0.6/0.4; 0.65/0.35 | **reasoned** + **user-directed**; `heavyExposureLevel` 0.75 **guessed** |
| Fitness | 0.55 / 0.25 / 0.20 | 0.20 on a **published** scale; 0.55/0.25 **inherited** from an unrecorded 0.7/0.3 |
| Sleep | nine coefficients summing to 1 | `latency` thresholds **published**; `regularity` **half-cited**; `restorative` **contradicted**; the other six **guessed**. ✅ Best conservation discipline in the app |
| Symptom radar | 1.0 / 0.9 / 0.9 / 0.8 / 0.8 / 0.5 | **reasoned**, ordinally supported by TemPredict; magnitudes **guessed**. Decision interval ✅ **measured** |
| Sustained load | 1.0 / 0.9 / 0.6 / 0.5 | windows **published**; weights **guessed** |
| Mental health | 1.0 / 0.9 / 0.8 / 0.6 | **guessed** |
| Gait | 1.0 / 0.7 / 0.7 / 0.5 / 0.5 | **guessed**; the stated literature justification is not in the file |
| Heart Health | 0.45 / 0.25 / 0.25 / 0.05 | **guessed**, on three **uncited** curves, one self-described as *"Rough"* |
| Metabolism | Katch-McArdle; 7,700; 0.10; 1.10 | instrument ✅ **published**; two **conventional, self-declared, uncited**; `underLoggingRatio` **guessed** |
| Readiness | 0.40 / 0.25 / 0.20 / 0.10 / 0.05 / 0.05 | ⚠️ **guessed, all six** — the app's most-viewed number |
| Energy | five constants | ⚠️ **guessed, named, refuted** (`B19`) |

**Count: 6 cards where the numbers are published, derived or explicitly the
reader's; 11 where at least one score-bearing constant is a guess.**

---

## 5. What nothing reconciles — the missing weight registry

One signal, five cards, five different shares, no document that compares them:

| Card | rMSSD's share | of a total of |
| --- | ---: | ---: |
| Readiness | 0.40 | 1.05 → **38 %** |
| Heart Health | 0.25 | 1.00 → **25 %** |
| Sustained load | 1.0 | 3.0 → **33 %** |
| Symptom radar | 0.9 (when rMSSD out-leans SDNN) | 3.3–3.6 → **25–27 %** |
| Mental health | 0.6 | 3.3 → **18 %** |

Same for `restingHeartRate` (0.25 / 0.9 / 0.9 / 1.0 across four tables) and
`sleepDurationHours` (0.20 / 0.5 / one of nine).

**Each is arguable in isolation. The set has never been argued.** These are five
cards on one screen answering five questions with the same three numbers, and a
reader who asks *"why did Readiness fall and Sustained load not?"* is currently
owed an answer nobody has written down.

⚠️ **This is the structural finding of the audit.** `MetricType` is a registry.
`InsightID` is a registry. `DataDomain` and `InputKind` are registries with
exhaustive switches and lints behind them. **Weights are the only load-bearing
quantity in this app with no registry, no lint and no single place to read
them** — which is precisely how `B19` survived unnoticed for months.

---

## 6. What this audit cannot answer, stated plainly

1. **Whether any weight is *right*.** Nothing here validates a weight against an
   outcome, because **the data to do that does not exist**: all 18 cards in this
   export carry a `history` array of length 0. `D60` reports the cause (a lazy
   view cache returning `[]`) and reports it fixed; **the fix postdates the only
   export there is**. Until a fresh export lands, `P24` has nothing to grade and
   this audit's verdicts are about *provenance*, not accuracy.
2. **Exposure coverage for four cards.** `schemaVersion 4` versus `7`. See §3.18.
3. **Whether the reader's dietary logging stopped or the pipeline broke.** 0/90
   days is a fact; *why* is not in the file. **Do not assume it is behaviour** —
   the last macro is 2026-03-22, the last micronutrient 2026-04-23, and two
   different last-dates in one domain is the shape of a source change, not of
   someone losing interest. Worth one question to the reader before anything is
   built on it.
4. **Whether `basalBodyTemperature` earns its 1.0.** The promotion postdates the
   export. Next export decides.
5. **Whether the 75-row gap between the inventory generator and the export
   arrays matters.** Counted, unexplained, not chased.

---

## 7. The rules this audit leaves behind

1. **A weight is a claim, and a claim needs one of four things**: a named source,
   a derivation with no free parameter, the reader's own recorded decision, or
   **the word "guess" in the comment beside it**. `hrvScore`'s *"Rough 'healthy'
   reference"* is the standard to meet; every other guessed constant reads as if
   it were known.
2. **Never fund a new term by inflating the total.** `SleepInsight.Weight` sums
   to 1, new terms take from old ones, and a retired term stays visible at 0.
   Copy this everywhere.
3. **Coverage before weight.** A weight assigned before its signal's day-coverage
   was counted is a weight assigned in the dark. Heart Health's 0.45 on 4/90 and
   Gait's 1.0-of-3.4 on two near-silent channels are both this mistake.
4. **A row count is not coverage.** `physicalEffort`: 46,729 rows, 16 days.
   Always report days.
5. **A citation without author, year and venue is not a citation.** Sleep's
   `regularity` is the live example.
6. **When two documents in this repo disagree, that is a finding, not a
   tie-break.** Sleep's `restorative = 0.10` against `stress-design` §2.1 is
   recorded here and resolved by neither.
7. **The absence of a norm is temporary, and inventing one is not.**
   `docs/norms-and-telemetry.md` is the tenet: collect toward a norm, never show
   one you do not have. **Several of the guesses above are candidates to become
   real norms** — meeting hours, arousal, exposure response — and none of them is
   a candidate to be quietly kept.

---

## Appendix — provenance of this document

- Coverage, row counts, source counts, distinct-value and zero-fraction figures:
  counted from `~/HealthSeed/exports/health-insights-export-new.json`
  (`generatedAt` 2026-08-07T07:09:11Z) with a throwaway script. Recomputable.
- Weights, constants and their comments: read from the tree at the commit this
  file lands on. **Line numbers are deliberately omitted** — they drift;
  `./scripts/where.sh <name>` does not.
- Every external source named here is one already established by this repo's own
  research documents (`illness-detection-evidence-2026-08-07.md`,
  `sleep-debt-research-2026-08-07.md`, `stress-design-2026-08-07.md`,
  `data-opportunities.md`, `backlog.md` §B19) or by a standard cited in the code
  itself (WHO/ITU H.870, NIOSH, ESC SCORE2 2021, WHO 2020). **No citation was
  introduced here that this repo did not already hold**, and where no evidence
  exists the entry says so rather than reaching for one.
