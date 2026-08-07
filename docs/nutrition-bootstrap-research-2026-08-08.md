# Bootstrapping Nutrition and Metabolism from what we already hold

**R60 · commissioned 2026-08-07, written 2026-08-08.** Research document — nothing
here is built.

> *"investigate how we can take the data we have, to at least populate something
> and some insights into nutrition and metabolism, some how, even if its by
> asking them for static inputs.. creative licence granted here, i know it will
> not be fully grounded, but surely we can derive something"*

## The brief's own boundary, restated because it decides everything below

§B5 #32 — meal-to-outcome / TDEE / intake-driven anything — is the one refusal
the reader **upheld**: *"I don't care, don't do it."* That forbids building
anything gated on food logging. It does **not** license leaving two cards empty.

So the question this document answers is narrow and precise: **what can these
two cards say when `dietaryEnergy` is, and will remain, zero?**

The answer has three parts, and the middle one is the deliverable:

1. A real amount, more than nothing — §6 and §7 list it.
2. **A hard mathematical limit.** Imputing intake from a prediction and then
   dividing observed by predicted returns **exactly 1.0 by construction** (§4.1).
   The Metabolism card's headline cannot be rescued by the inverse problem; the
   inverse problem *destroys* it.
3. **The theatre line** (§5): the effect these cards claim to detect is
   55–230 kcal/day; the individual-level error on the prediction they would
   detect it against is 355–608 kcal/day RMSE. **The error is larger than the
   signal.** Any "% of predicted" figure is theatre, and no amount of static
   input closes that gap.

---

## 1. What we actually hold — counted, not assumed

The brief's standing rule: *before writing "already arriving" about a source,
count its rows in the last 90 days.* Counted from
`~/HealthSeed/exports/health-insights-export-new.json` (generated 2026-08-07,
377,284 samples), by the scratchpad scripts noted at the end of this section.

**Distinct-day coverage** — which is what matters for a trend, not row count:

| Metric | Rows, all time | Rows, last 90d | Distinct days / 28 | Distinct days / 90 |
|---|---:|---:|---:|---:|
| `activeEnergyBurned` | 67,366 | 30,391 | 27 (96%) | 86 (96%) |
| `activeMedicationLevel` | 172 | 90 | 28 (100%) | 90 (100%) |
| `bodyMass` | 1,243 | 232 | **21 (75%)** | **61 (68%)** |
| `bodyFatPercentage` | 621 | 89 | 6 (21%) | 26 (29%) |
| `leanBodyMass` | 577 | 89 | **6 (21%)** | **26 (29%)** |
| `muscleMass` / `boneMass` / `bodyWaterPercentage` | 154 each | 31 each | 6 (21%) | 26 (29%) |
| `vo2Max` | 87 | 39 | — | — |
| `height` | 6 | **0** (last row 2020-10-05) | — | — |
| **`dietaryEnergy`** | **74** | **0** | **0 (0%)** | **0 (0%)** |

Every one of the ten macro rows and eleven micronutrient rows is **0 in the last
90 days**. `dietaryEnergy` last appeared 2026-03-22; over the last 365 days it
covers 14 days (4%). The gate is 80% (`NutritionLogging.completeEnough = 0.8`).
The refusal is not merely policy — it is empirically correct, and re-checking it
cost one script.

⚠️ **One correction to the brief.** It states 1,614 weights; the counted figure in
this export is **1,243** (`bodyMass`, first row 2017-06-09). The larger number may
come from the older export or from summing body-composition rows. Everything
below uses the counted figure, and the difference does not change any conclusion.

**Two measured properties of the weight series matter more than its size**, and
neither is written down anywhere in the repo:

- **Day-to-day scatter around trend: 0.37% of body mass** (from the SD of
  consecutive-day differences ÷ √2, last 180 days, 111 distinct days). That is
  *tighter* than the published comparators — CV 0.66–0.71% in healthy adults
  ([Tandfonline 2023](https://www.tandfonline.com/doi/full/10.1080/0886022X.2023.2273421)).
  A consistent morning weigh-in on a fixed scale is a genuinely good instrument.
- **Lag-1 autocorrelation of the detrended residuals: 0.74.** High, and the
  reason §4.2's error bars are not the textbook ones. A salty weekend persists
  for days; the noise is nothing like independent.

*Scripts (counts and dimensionless shapes only, never a reading — see
`docs/privacy-and-ip.md`): `scratchpad/wf_7c6344c6-584-3--nutrition-count.py`
and `…--days.py`.*

---

## 2. The resting-rate equation: one provenance error, one wrong claim

### 2.1 The equation we call Katch-McArdle is Cunningham 1991

`EnergyBalanceModel.katchMcArdleBMR` (`MetabolismInsight.swift:96-98`) implements
`370 + 21.6 × FFM` and labels it, on screen, *"Katch-McArdle, from your lean
mass"* (`:148`).

That formula is **Cunningham JJ, *Am J Clin Nutr* 1991;54:963-969** (PMID
1957828) — *"Body composition as a determinant of energy expenditure: a synthetic
review and a proposed general prediction equation."* Cunningham's 1980 work gave
`500 + 22 × FFM`; the 1991 re-analysis produced the form we ship. Katch and
McArdle popularised it through their *Exercise Physiology* textbook, and the
fitness literature renamed it after them.

Cunningham reports the equation explains **65–90% of the variation in REE**.

**This is a labelling fix, not a bug** — the arithmetic is right. But this app's
whole posture is that a reader can trace every number, and a row that names the
textbook that borrowed the equation instead of the paper that derived it fails
that on its own terms. One string.

### 2.2 The claim that it "beats Mifflin when a scale reports composition" is not supported

The doc comment at `:93-95` says Cunningham/Katch-McArdle *"is the better
instrument exactly when a scale reports body composition, which is the reader
this app is built for."* I could not find evidence for that, and found some
against it:

- **Frankenfield, Roth-Yousey & Compher, *J Am Diet Assoc* 2005;105:775-789** —
  the systematic review that made Mifflin the default — found Mifflin-St Jeor
  predicted RMR within 10% of measured for **82% of non-obese and 70% of obese**
  individuals, more than any other equation tested, with the narrowest error
  range.
- A retrospective comparison in overweight and obese adults using **DXA-measured**
  FFM found Cunningham had the **largest** mean deviation (−16.6%), worse than
  Mifflin-St Jeor (−12.6%)
  ([*Medicine* 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11365691/)).

And there is a second problem the code does not consider. Cunningham was derived
against FFM from reference methods. **Ours comes from a consumer BIA scale.**
Consumer BIA devices show **mean absolute error 2.8–3.1 kg** for fat-free mass
against DXA, with device-specific systematic offsets (one instrument
over-predicted FFM by +2.7 kg)
([*PMC6452160*](https://pmc.ncbi.nlm.nih.gov/articles/PMC6452160/);
[*PMC9813632*](https://pmc.ncbi.nlm.nih.gov/articles/PMC9813632/)). At
21.6 kcal/kg that is **±60–67 kcal/day** injected into the resting term before
the equation's own error is counted.

> **Finding.** There is no published basis for preferring Cunningham here, and a
> real basis for doubting it on BIA-derived FFM. **Do not "fix" this by switching
> to Mifflin** — §5 shows the choice cannot matter, because both are far inside
> the noise. What must change is the *sentence*, which currently asserts a
> superiority the literature does not support.

### 2.3 One thing BIA is good at, and it is the useful thing

A device's systematic offset **cancels in a difference**. Absolute lean mass from
this scale is worth ±3 kg; the *change* in lean mass measured by the same device
under the same protocol is far better than that. This is the single most
under-used fact in the data we hold, and §6.2 builds on it.

---

## 3. Ethnicity, and other resting-rate modifiers

Since the brief invites static inputs, the obvious candidate for the resting term
is ethnicity. It has a real published effect:

**Reneau J et al., *Nutrition & Diabetes* 2019;9:21** (n=114, 30% African
American) — after adjusting for age, sex, total fat mass and fat-free mass,
African American race remained the most significant negative predictor of
measured RMR, **144 kcal/day lower** than Caucasians of equivalent height,
weight, age and sex. The authors advocate race-specific equations. Notably the
difference **disappeared when truncal fat-free mass replaced total fat-free
mass** — i.e. it is organ-size distribution, not race as such.

> **Recommendation: do not ask.** Three reasons, in order of weight.
> 1. **It cannot pay for itself.** 144 kcal/day sits well inside the ±355 kcal/day
>    individual prediction error of §5. Adding it makes the number no more able to
>    answer any question the reader has.
> 2. **The paper itself says the mechanism is truncal FFM**, which a segmental
>    scale could in principle measure — a measurement beats a proxy.
> 3. Asking a reader for their race to adjust a metabolic figure is a serious ask
>    with a serious history, and this app's rule is that an ask must be paid for
>    (`NutritionInsight.requirements`, and the ⚠️ at `:449-455` about an ask whose
>    stated reason never happens). This one cannot be.

The same reasoning disposes of the other resting-rate modifiers that come up —
thyroid status, smoking, menopause. Each is real; none is worth more than the
error bar it would be added to.

---

## 4. The inverse problem

### 4.1 ⚠️ The tautology — the most important result in this document

The tempting move, and the one the brief gestures at, is: we have no intake, but
we have weight; energy balance is `intake − expenditure = storage`, so impute
intake and carry on.

**It does not work, and the failure is exact rather than approximate.**

The card computes (`MetabolismInsight.swift:138, 156, 161`):

```
observed  = intake − Δweight_per_day × 7700          // storage subtracted
predicted = BMR + activeMean + intake × 0.10
speed     = observed / predicted
```

With no food log, the only available imputation is from the prediction itself:

```
intake_hat = predicted + storage        (energy balance, rearranged)
```

Substitute:

```
observed_hat = intake_hat − storage = (predicted + storage) − storage = predicted
speed        = predicted / predicted   = 1.0
```

**The ratio is identically 1.0 for every reader, every window, every dose.** It
would render as "100% of predicted", score 100 on
`EnergyBalanceModel.score(speed:)`, and carry `.confidence` — while containing
literally zero information. It is not a weak signal; it is an arithmetic
identity wearing a percentage sign.

This is worth stating plainly because it is exactly the design a session working
from the brief alone would reach for, and it would pass tests, pass CI, ship, and
be wrong in a way no screenshot reveals.

> **Rule for the backlog: nothing may impute intake from predicted expenditure
> and then compare the result against predicted expenditure.** If intake is
> imputed, the only honest downstream figure is the imputed intake itself, with
> the full prediction error attached (§5) — never a ratio against its own source.

### 4.2 What *does* survive: energy balance from the weight trend alone

One quantity needs no prediction and no food log:

```
energy balance (kcal/day) = −Δweight_per_day × energy density
```

This is the reader's deficit, in energy units, derived from the scale alone. It
is a restatement of the weight trend — but in the unit the reader actually asks
questions in, and the app already holds every input.

Its error is the slope error, and here the measured properties from §1 matter.
For OLS slope with `n` weigh-in days spread over a `W`-day window,
`SE(b) = σ / √Σ(xᵢ − x̄)²`, with `Σ(xᵢ − x̄)² ≈ n·W²/12`. AR(1) residuals with
ρ = 0.74 inflate the slope variance by roughly `(1+ρ)/(1−ρ) = 6.7`, i.e. **×2.6
on the standard error**.

**My arithmetic**, using this reader's measured σ = 0.37% of body mass, ρ = 0.74,
their measured weigh-in coverage, and 7,700 kcal/kg:

| Window | Weigh-in days (measured) | 1 SE | **95% CI** |
|---|---:|---:|---:|
| **28 days** (what the card uses) | 21 | ≈2.0 kcal/day per kg | **≈ ±390 kcal/day** at 100 kg |
| **90 days** | 61 | ≈0.36 kcal/day per kg | **≈ ±71 kcal/day** at 100 kg |
| **180 days** | 111 | ≈0.14 kcal/day per kg | **≈ ±26 kcal/day** at 100 kg |

*(Expressed per kg of body mass so no weight is printed; multiply by the reader's
mass. The `n·W²/12` step assumes weigh-ins are spread roughly evenly, which the
measured coverage supports.)*

> **Finding — and the most actionable one here.** `EnergyBalanceModel.windowDays
> = 28` is the single reason this figure is unusable. The slope error falls
> roughly as `W^1.5`, so **going from 28 to 90 days cuts it about fivefold** and
> takes it from ±390 kcal/day (worthless) to ±71 kcal/day (a real measurement).
> The reader has 68% weigh-in coverage over 90 days and nine years of history —
> the data for the long window is already there.
>
> ⚠️ The counter-pressure is bias, not variance: a 180-day window assumes one
> linear rate over half a year, which a dose escalation violates. **90 days is
> the recommendation** — long enough to be quiet, short enough to still describe
> now.

### 4.3 Why not just use Hall's model — and what the published method actually promises

The dynamic-model literature is directly on point and should be cited by anything
built here:

- **Hall KD, *Int J Obes* 2008;32:573-576** — *"What is the required energy
  deficit per unit weight loss?"* The 3,500 kcal/lb (7,700 kcal/kg) rule is
  wrong chiefly because it ignores the dynamics: expenditure falls as the body
  shrinks, so a static rule over-predicts loss. The required deficit per unit
  loss is **larger for people with greater initial body fat**.
- **Hall KD et al., *Lancet* 2011;378:826-837** — *"Quantification of the effect
  of energy imbalance on bodyweight"*, the model behind the NIH Body Weight
  Planner.
- **Sanghvi A, Redman LM, Martin CK, Ravussin E, Hall KD, *Am J Clin Nutr*
  2015;102:353-358** — the **intake-balance method**, which is the published name
  for exactly what the brief describes. Validated in **n = 140** CALERIE
  participants over 2 years against doubly labelled water plus serial DXA. Mean
  bias **within 40 kcal/day**; RMSD between model and DLW/DXA **215 kcal/day**;
  most individual ΔEI values **within 132 kcal/day**.

Read carefully, Sanghvi is both the licence and the limit:

- ✅ It validates deriving **energy intake** from **repeated body weight plus
  baseline demographics** — no food log. That is our situation exactly.
- ⚠️ It validates a **change** in intake (ΔEI) from a **baseline**, over
  **2 years**, in a **controlled trial** with DXA. We would be asking for a
  **level** over **weeks**, from a bathroom scale.
- ⚠️ Even under those conditions the individual precision is **±132 kcal/day at
  best and 215 kcal/day RMSD** — which is *already the size of the entire effect*
  §5 is about.

> **Finding.** The intake-balance method is real, published and applicable — and
> what it licenses is an **energy-balance / implied-intake figure with a stated
> error bar over a long window**, not a metabolic verdict. Its own best-case
> precision is comparable to the effect anything downstream would claim to see.

### 4.4 Composition-aware energy density (backlog R25) is below the noise floor

R25 proposes splitting the 7,700 kcal/kg constant by composition — fat ≈9,400,
lean ≈1,800 kcal/kg (the values in **Hall 2008**).

The SURMOUNT-1 body-composition substudy (§6.1) reports **~75% of weight lost was
fat mass**. My arithmetic on that split:

```
0.75 × 9,400 + 0.25 × 1,800 = 7,500 kcal/kg
```

against the blanket 7,700 — a **2.6% correction**. On a deficit of ~600 kcal/day
that is **~16 kcal/day**, against a ±71 kcal/day error bar at the 90-day window
and ±390 at the current 28.

> **Finding: R25 is not worth building for accuracy.** It is a factor of four
> below the noise it would be added to. ⚠️ **Fix the window first** (§4.2); the
> composition split only becomes visible at 180 days, and even then it is
> marginal. This retires the R25 rationale as written — the row should be
> re-marked with this figure rather than left implying a pending accuracy gain.

---

## 5. ⚠️ The theatre line — naming it is the deliverable

The brief asks for the line past which modelled-on-modelled error is so wide the
figure is theatre. Here it is, as a comparison of two numbers.

### The effect we would be trying to detect

Adaptive thermogenesis — "my metabolism has slowed" — is the whole subject of the
Metabolism card. Its published magnitude:

| Source | Population | Adaptive thermogenesis |
|---|---|---|
| **CALERIE**, organ-mass adjusted ([*Sci Rep* 2024](https://www.nature.com/articles/s41598-024-83762-0)) | Non-obese, 25% CR, 2y | **≈55 kcal/day** |
| **Nunes CL et al., *Eur J Nutr* 2022;61:1405-1416** (n=94) | Moderate weight loss, 4 months | **−65 to −230 kcal/day**, *depending only on which of 13 methods was used on the same people* |
| **Fothergill E et al., *Obesity* 2016;24:1612-1619** (n=14 of 16) | ~40% weight loss, 6y follow-up | **−499 ± 207 kcal/day** — the extreme case, and note the SD |

Nunes is the crucial one. **The same participants, the same measurements, and the
estimate moves by 165 kcal/day purely on the analyst's choice of prediction
equation and method.** The authors conclude assessment "should be standardized
and comparisons among studies with different methodologies must be avoided."

⚠️ And the phenomenon itself is contested: *AJCN* 2022 carries
["Metabolic adaptation is an illusion, only present when participants are in
negative energy balance"](https://ajcn.nutrition.org/article/S0002-9165(22)00892-9/fulltext)
and Hall's own ["The Biggest Loser study
reinterpreted"](https://onlinelibrary.wiley.com/doi/10.1002/oby.23308). **We would
be shipping a number for a quantity the field has not agreed exists at the
magnitude claimed.**

For a reader on tirzepatide losing ~0.6% of body mass per week, the honest
expectation is the middle row: **on the order of 100 kcal/day, ±100.**

### The error on the thing we would measure it against

| Error term | Size | Source |
|---|---:|---|
| **Predicted TDEE, individual level, best equation** | **RMSE 355 kcal/day**; LoA −658 to +747; only **39% within ±10%** | Prado-Nóvoa et al., *Sci Rep* 2024, n=56, vs doubly labelled water |
| Predicted TDEE, whole sample, best equation | RMSE **608 kcal/day**; LoA −945 to +1,334; 43% within ±10% | *ibid.* |
| Wrist-worn active energy | **best device 27% median error**; none accurate | Shcherbina et al., *J Pers Med* 2017;7(2):3, n=60, vs **indirect calorimetry** |
| BIA fat-free mass → resting term | ±60–67 kcal/day | §2.2 |
| Weight slope, 28-day window | ±390 kcal/day (95%) | §4.2 |

⚠️ A note on the Shcherbina figure, because it is widely miscited including by
search engines: the reference standard was **indirect calorimetry on discrete
laboratory activities**, not doubly labelled water. It is the best available
number for wrist-worn energy expenditure, and it does not directly measure
free-living daily error.

### The line

> **The individual-level error on predicted total energy expenditure (RMSE
> 355–608 kcal/day) is between 1.5× and 10× the effect the card exists to detect
> (55–230 kcal/day). Every figure of the form "X% of predicted" is therefore
> theatre, and no static input the reader could supply changes that** — the
> largest static-input correction available is ethnicity at 144 kcal/day (§3),
> itself smaller than the error bar.

Three consequences, stated as rules:

1. **`speed`, `predictedTDEE` as a denominator, and the "% of predicted" headline
   cannot be made honest.** Not with a better equation, not with more inputs. The
   quantity is unmeasurable with these instruments.
2. **A predicted TDEE may still be shown as a *requirement estimate*** — "roughly
   what a body your size and activity needs" — provided it carries ±355 kcal/day
   or a plain-language equivalent, and is never divided into anything.
3. **The error bar is the feature.** Per the reader's standing instruction, thin
   data means print the error bar rather than show nothing. A card that says
   *"about 2,400 kcal/day, and honestly that could be 2,050 or 2,750"* respects
   them. One that says *"96% of predicted"* does not.

---

## 6. The GLP-1 angle — what is uniquely ours, and what does not exist

The reader's own ask, from the head of the metabolism section: *"I'm always
wanting to know how fast my metabolism is at the moment, and how it's sped up by
Mounjaro or similar medications."*

### 6.1 What is published

**Tirzepatide, weight and composition**

- **Jastreboff AM et al., *NEJM* 2022;387:205-216** (SURMOUNT-1, n=2,539, 72
  weeks): mean weight change **−15.0%** (5 mg), **−19.5%** (10 mg), **−20.9%**
  (15 mg), vs **−3.1%** placebo.
- **Look M et al., *Diabetes Obes Metab* 2025** (PMID 39996356), SURMOUNT-1
  body-composition substudy, **n=160** (124 tirzepatide, 36 placebo), DXA at
  baseline and week 72: weight **−21.3%**, fat mass **−33.9%**, lean mass
  **−10.9%** on tirzepatide (placebo −5.3% / −8.2% / −2.6%). **~75% of the weight
  lost was fat.**

**The mechanism is intake, not expenditure**

- **Heise T et al., *Diabetes Care* 2023;46:998-1004** — tirzepatide 15 mg
  (n=45) vs semaglutide 1 mg (n=44) vs placebo (n=28), 28 weeks. Both drugs
  significantly reduced appetite and energy intake vs placebo; **intake
  reductions did not differ between them** and were **not sufficient to explain
  the different weight outcomes.** The authors explicitly call for further work
  on tirzepatide's effects on 24-h intake, substrate use and **energy
  expenditure**.
- **Blundell J et al., *Diabetes Obes Metab* 2017;19:1242-1251** — semaglutide
  1.0 mg, n=30, 12-week crossover: **−24% total ad libitum energy intake**
  (−3,036 kJ), weight −5.0 kg predominantly fat, and — the load-bearing result —
  **resting metabolic rate adjusted for lean body mass did not differ between
  treatments.**
- **Vieira et al., *Obesity Reviews* 2026** (scoping review, 23 studies, 10
  monotherapy / 13 combination): a **neutral effect on energy expenditure** once
  studies accounting for weight and body-composition change are considered.

> ✅ **The card's existing rule is confirmed by the evidence.** *"Mounjaro speeds
> up your metabolism"* is a claim this card must never make
> (`MetabolismInsight.swift:36-42`, backlog R24). The published position is that
> GLP-1 and GIP/GLP-1 agonists reduce **intake**, and that resting expenditure
> tracks body composition with no drug-specific effect. That rule was written
> before this evidence was gathered and it holds.

### 6.2 ⚠️ What does not exist — say so plainly

**No published study measures tirzepatide's effect on energy expenditure by
whole-room calorimetry or doubly labelled water.** Heise 2023 names it as an open
question in its own conclusions; the 2026 scoping review's monotherapy arm covers
exenatide, liraglutide, semaglutide and beinaglutide — not tirzepatide-specific
expenditure.

**There is therefore no published curve of "expected metabolic adaptation at dose
X on tirzepatide" to plot a reader against.** The brief's most attractive idea —
*show the reader's trajectory against the trial population at their dose* — has
no expenditure curve behind it and must not be invented.

What *can* honestly be plotted against SURMOUNT-1 is **weight and body
composition**, where the numbers above are real, dose-resolved and from n=2,539
(n=160 for composition). The reader has `activeMedicationLevel` on **90 of the
last 90 days** and a nine-year weight series. A "you vs the trial population at
your dose" comparison on **percent weight change and percent fat-mass change** is
fully supported. The same comparison on **metabolism is not**, and the difference
between those two sentences is the whole discipline of this document.

### 6.3 The one honest metabolic statement available

There is exactly one non-tautological thing we can say about this reader's
metabolism, and the data for it is already on the phone:

```
Δ predicted resting energy = 21.6 × Δ lean mass        (Cunningham 1991)
```

- It is **arithmetic on a measured quantity**, not a comparison against a
  prediction — so §4.1 does not apply.
- It uses the *change* in BIA lean mass, where the device's systematic offset
  cancels (§2.3) — the one thing this instrument is genuinely good at.
- It answers the reader's real question in the only sense the data supports:
  **your body now costs less to run, and here is how much less, because you are
  carrying this much less lean tissue.** That is what "my metabolism has slowed"
  means for someone 20% down.
- It carries no adaptive-thermogenesis claim, so none of §5 applies to it.

⚠️ Its constraint is coverage: `leanBodyMass` is **26 distinct days in the last
90 (29%)**, so this needs a long window and must state its own error. It should
report a change over a stated period, never a daily value.

---

## 7. Static inputs, ranked by information value

Separating the ones with published mappings from the theatre, as asked.

### Worth asking — published mapping, pays for itself

| Ask | What it unlocks | Published basis |
|---|---|---|
| **Height (re-ask)** | ⚠️ **The cheapest fix in this document.** Last `height` row is **2020-10-05**; 6 rows ever, 0 in 90 days. Mifflin-St Jeor is the fallback when lean mass is absent, and it needs height. | Mifflin 1990 |
| **Supplements taken** (backlog Q8) | Directly changes micronutrient adequacy — and for several of the eight targets a supplement is the *dominant* term. Higher information value than any dietary question. | `MicronutrientTargets` (IOM DRIs via NIH ODS) already resolves floors and ceilings by sex/age |
| **Animal products eaten (yes / rarely / never)** | **Vitamin B12** and iron risk. One question, and it is the single strongest predictor of B12 inadequacy. | B12 has no plant source; IOM RDA 2.4 µg already in `MicronutrientTargets` |
| **Country / latitude — already derivable** | **Vitamin D.** SACN 2016 / PHE advise **10 µg/day for everyone in the UK aged 4+ year-round**, and specifically that autumn–winter sunlight at UK latitudes cannot maintain status. Needs only the month. | SACN *Vitamin D and Health* (2016); PHE advice, 21 July 2016 |

The vitamin D one deserves emphasis: it is a **published, population-level,
reader-independent statement** that requires *no* input we do not already have,
and it is actionable. `dietaryVitaminD` has 6 rows ever and 0 in 90 days, so the
card currently says nothing about a nutrient whose national guidance applies to
everybody, every October.

### Not worth asking — real effect, but inside the error bar

- **Ethnicity** — 144 kcal/day (§3). Real, published, and swamped.
- **Occupational activity / PAL** — we *measure* activity on 96% of days.
  A dropdown lifestyle multiplier would replace a measurement with a guess.
- **Thyroid status, smoking, menopause** — each modifies resting rate; none by
  more than the ±355 kcal/day of §5.

### Theatre — do not ask

- **Anything that feeds a "% of predicted" figure.** §5 and §4.1.
- **Self-reported typical portion sizes or "how many calories do you usually
  eat"** — this is a food log with worse accuracy and no dates, and it re-opens
  §B5 #32 through the back door.
- **Self-reported meal timing to model the thermic effect of food.** TEF is
  ~10% of intake; with intake unknown, modelling its *timing* is a decoration on
  an unknown quantity.

---

## 8. Short FFQs for micronutrient risk — what they can and cannot do

The eight targetable micronutrients (`MicronutrientTargets.targetable`) are
vitamin C, D, A, B12, calcium, iron, magnesium and zinc.

### The instruments

- **NCI Dietary Screener Questionnaire (DSQ)** — **26 items**, with **published
  scoring algorithms** regressed on NHANES 2009-2010 24-hour recalls using the
  NCI usual-intake method (**Thompson FE et al., *J Nutr* 2017;147:1226-1233**,
  PMID 28490673). Public domain, and the algorithms are downloadable from NCI.
  It yields estimates for fruit/veg, dairy, whole grains, added sugars, **fibre
  (g)** and **calcium (mg)**.
- **PrimeScreen** — 21 food items, ~5 minutes (**Rifas-Shiman SL, Willett WC,
  Lobb R, Kotch J, Dart C, Gillman MW, *Public Health Nutr* 2001;4:249-254**).
  Mean correlation **0.70 reproducibility**, **0.61** against a 131-item FFQ for
  foods and food groups, with plasma-biomarker comparison.

### ⚠️ The finding, which is a limitation

**No short screener maps to the eight targets.** Of the eight, the DSQ's
published algorithms produce **one** — calcium. Screeners are explicitly designed
to **rank** individuals on diet quality and to estimate a small number of
components; they **do not assess portion sizes and do not aim to estimate
absolutes of macro- or micronutrients**
([*Public Health Nutrition*, short-screener validity
literature](https://www.cambridge.org/core/journals/public-health-nutrition/article/validity-of-two-short-screeners-for-diet-quality-in-timelimited-settings/C328E96E341F483339E6437845694F0F)).

So a screener **cannot** feed `NutritionModel.micronutrientScore`, which compares
an intake in mg against an RDA in mg. Doing so would manufacture a milligram
figure the instrument cannot produce — the same failure the card already refuses
for modelled micronutrients (`NutritionInsight.swift:290-298`: *"a modelled
intake cannot be evidence about you"*).

> **Recommendation.** If a screener is ever built, it must produce a **risk
> flag**, never a milligram figure, and must render in a visibly different shape
> from a scored row. Coverage would be: **calcium and fibre** from DSQ's
> published algorithms; **B12** from the animal-products question; **vitamin D**
> from SACN's population advice; **iron** from sex and age, which we already
> hold. **Vitamin A, C, magnesium and zinc have no short-instrument route** — for
> those, say nothing.

---

## 9. What to build — recommendations, in order

Nothing below requires a food log, and nothing below violates §B5 #32.

**Metabolism**

1. ⚠️ **Widen the window from 28 to 90 days** (`EnergyBalanceModel.windowDays`).
   Highest value per line changed in this document: it moves the energy-balance
   figure from ±390 to ±71 kcal/day (§4.2).
2. **Ship the energy-balance figure with its error bar** — the deficit in
   kcal/day from the weight trend alone (§4.2). No intake, no prediction, no
   ratio.
3. **Ship "your body now costs less to run"** — `21.6 × Δ lean mass` over a
   stated period (§6.3). The one honest metabolic statement available.
4. **Show predicted TDEE as a requirement estimate with ±355 kcal/day stated**,
   never as a denominator (§5, consequence 2).
5. **Do not implement the intake imputation.** §4.1. Add the rule to the backlog
   so a future session does not rediscover it the expensive way.

**Nutrition**

6. **Turn the card from scoring to *targets*.** Every figure it already cites is
   computable with no log: protein floor from body mass (WHO/FAO/UNU 0.83 g/kg
   safe intake; **1.2–1.6 g/kg** for lean retention during rapid loss — which the
   SURMOUNT-1 25%-lean-loss figure makes specifically relevant to this reader),
   fibre 30 g (SACN), sodium <2 g (WHO), water 2.5/2.0 L (EFSA), vitamin D 10 µg
   (SACN). A card that says *what you need* is honest with zero rows; a card that
   says *how you did* is not.
7. **The vitamin D seasonal statement** (§7) — no new input at all.
8. **Supplements** (backlog Q8) before any dietary screener; better information,
   simpler ask.

**Documentation fixes**

9. Rename the Cunningham attribution and delete the unsupported
   better-than-Mifflin claim (§2).
10. Re-mark backlog **R25** with the 2.6% / ~16 kcal/day figure (§4.4) — it is
    below the noise floor, and the row currently implies a pending accuracy gain
    that is not there.

---

## 10. Sources

**Energy expenditure prediction**

- Mifflin MD, St Jeor ST, Hill LA, Scott BJ, Daugherty SA, Koh YO. A new predictive equation for resting energy expenditure in healthy individuals. *Am J Clin Nutr.* 1990;51(2):241-247. — [ajcn.nutrition.org](https://ajcn.nutrition.org/article/S0002-9165(23)16698-6/fulltext)
- Cunningham JJ. Body composition as a determinant of energy expenditure: a synthetic review and a proposed general prediction equation. *Am J Clin Nutr.* 1991;54:963-969. PMID 1957828. — [sciencedirect.com](https://www.sciencedirect.com/science/article/abs/pii/S0002916523319361)
- Frankenfield D, Roth-Yousey L, Compher C. Comparison of predictive equations for resting metabolic rate in healthy nonobese and obese adults: a systematic review. *J Am Diet Assoc.* 2005;105(5):775-789. — [jandonline.org](https://www.jandonline.org/article/S0002-8223(05)00149-5/abstract)
- Prado-Nóvoa O et al. Validity of predictive equations for total energy expenditure against doubly labeled water. *Sci Rep.* 2024. n=56. — [PMC11231257](https://pmc.ncbi.nlm.nih.gov/articles/PMC11231257/)
- Comparative analysis of basal metabolic rate measurement methods in overweight and obese individuals. *Medicine.* 2024. — [PMC11365691](https://pmc.ncbi.nlm.nih.gov/articles/PMC11365691/)
- Reneau J et al. Do we need race-specific resting metabolic rate prediction equations? *Nutr Diabetes.* 2019;9:21. n=114. — [PMC6662665](https://pmc.ncbi.nlm.nih.gov/articles/PMC6662665/)

**Measurement error**

- Shcherbina A, Mattsson CM, Waggott D, et al. Accuracy in wrist-worn, sensor-based measurements of heart rate and energy expenditure in a diverse cohort. *J Pers Med.* 2017;7(2):3. n=60, indirect calorimetry. — [mdpi.com](https://www.mdpi.com/2075-4426/7/2/3)
- Accuracy of bioelectrical impedance consumer devices for measurement of body composition in comparison to whole body MRI and DXA. — [PMC6452160](https://pmc.ncbi.nlm.nih.gov/articles/PMC6452160/)
- High precision but systematic offset in a standing BIA compared with DXA. — [PMC9813632](https://pmc.ncbi.nlm.nih.gov/articles/PMC9813632/)
- Day-to-day variability in euvolemic body mass. *Renal Failure.* 2023. — [tandfonline.com](https://www.tandfonline.com/doi/full/10.1080/0886022X.2023.2273421)

**Energy balance and the inverse problem**

- Hall KD. What is the required energy deficit per unit weight loss? *Int J Obes.* 2008;32(3):573-576. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/17848938/)
- Hall KD, Sacks G, Chandramohan D, et al. Quantification of the effect of energy imbalance on bodyweight. *Lancet.* 2011;378(9793):826-837. — [PMC3859816](https://pmc.ncbi.nlm.nih.gov/articles/PMC3859816/)
- Sanghvi A, Redman LM, Martin CK, Ravussin E, Hall KD. Validation of an inexpensive and accurate mathematical method to measure long-term changes in free-living energy intake. *Am J Clin Nutr.* 2015;102(2):353-358. n=140. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/26040640/)

**Adaptive thermogenesis**

- Nunes CL, Jesus F, Francisco R, et al. Adaptive thermogenesis after moderate weight loss: magnitude and methodological issues. *Eur J Nutr.* 2022;61(3):1405-1416. n=94. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/34839398/)
- Fothergill E, Guo J, Howard L, et al. Persistent metabolic adaptation 6 years after "The Biggest Loser" competition. *Obesity.* 2016;24(8):1612-1619. −499 ± 207 kcal/day. — [onlinelibrary.wiley.com](https://onlinelibrary.wiley.com/doi/full/10.1002/oby.21538)
- Effect of caloric restriction on organ size and its contribution to metabolic adaptation: ancillary analysis of CALERIE 2. *Sci Rep.* 2024. — [nature.com](https://www.nature.com/articles/s41598-024-83762-0)
- Metabolic adaptation is an illusion, only present when participants are in negative energy balance. *Am J Clin Nutr.* 2022. — [ajcn.nutrition.org](https://ajcn.nutrition.org/article/S0002-9165(22)00892-9/fulltext)
- Hall KD. Energy compensation and metabolic adaptation: "The Biggest Loser" study reinterpreted. *Obesity.* 2022. — [onlinelibrary.wiley.com](https://onlinelibrary.wiley.com/doi/10.1002/oby.23308)

**GLP-1 / GIP**

- Jastreboff AM, Aronne LJ, Ahmad NN, et al. Tirzepatide once weekly for the treatment of obesity. *N Engl J Med.* 2022;387(3):205-216. n=2,539. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/35658024/)
- Look M et al. Body composition changes during weight reduction with tirzepatide in the SURMOUNT-1 study. *Diabetes Obes Metab.* 2025. n=160. PMID 39996356. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/39996356/)
- Heise T, DeVries JH, Urva S, et al. Tirzepatide reduces appetite, energy intake, and fat mass in people with type 2 diabetes. *Diabetes Care.* 2023;46(5):998-1004. — [diabetesjournals.org](https://diabetesjournals.org/care/article/46/5/998/148546/Tirzepatide-Reduces-Appetite-Energy-Intake-and-Fat)
- Blundell J, Finlayson G, Axelsen M, et al. Effects of once-weekly semaglutide on appetite, energy intake, control of eating, food preference and body weight in subjects with obesity. *Diabetes Obes Metab.* 2017;19(9):1242-1251. n=30. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/28266779/)
- Vieira et al. Effects of GLP-1 receptor agonists (mono and combination therapy) on energy expenditure: a scoping review. *Obesity Reviews.* 2026. 23 studies. — [onlinelibrary.wiley.com](https://onlinelibrary.wiley.com/doi/10.1111/obr.70116)

**Dietary screeners and guidance**

- Thompson FE, Midthune D, Kahle L, Dodd KW. Development and evaluation of the National Cancer Institute's Dietary Screener Questionnaire scoring algorithms. *J Nutr.* 2017;147(6):1226-1233. PMID 28490673. — [pubmed](https://pubmed.ncbi.nlm.nih.gov/28490673/) · [NCI scoring procedures](https://epi.grants.cancer.gov/nhanes/dietscreen/scoring/current/)
- Rifas-Shiman SL, Willett WC, Lobb R, Kotch J, Dart C, Gillman MW. PrimeScreen, a brief dietary screening tool. *Public Health Nutr.* 2001;4(2):249-254. — [Harvard DASH](https://dash.harvard.edu/entities/publication/af26d504-f0fd-4ac6-81ba-bdf13a3bbaca)
- Validity of two short screeners for diet quality in time-limited settings. *Public Health Nutr.* — [cambridge.org](https://www.cambridge.org/core/journals/public-health-nutrition/article/validity-of-two-short-screeners-for-diet-quality-in-timelimited-settings/C328E96E341F483339E6437845694F0F)
- SACN. *Vitamin D and Health.* 2016; PHE advice 21 July 2016. — [gov.uk](https://www.gov.uk/government/news/phe-publishes-new-advice-on-vitamin-d)

---

## Appendix — claims deliberately NOT made

Recorded so a later session does not "restore" them.

| Claim | Why not |
|---|---|
| "Tirzepatide raises/lowers your metabolic rate by N kcal/day" | **No published expenditure study of tirzepatide exists.** §6.2 |
| "You are running at N% of predicted" | Tautological if intake is imputed (§4.1); unmeasurable if it is not (§5) |
| "Your metabolism has adapted by N kcal/day" | Effect 55–230, error 355–608, and method-dependent by 165 (§5) |
| A milligram figure for any micronutrient from a screener | Screeners rank, they do not quantify (§8) |
| "Katch-McArdle is better than Mifflin here" | Unsupported, with evidence against (§2.2) |
| Composition-aware kcal/kg as an accuracy improvement | 2.6%, ~16 kcal/day, below the noise (§4.4) |
