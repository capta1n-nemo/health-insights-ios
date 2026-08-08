> # ⚠️ NOT BUILD-READY — three hostile reviewers returned `needs-rework`

<!-- status: superseded — v1 — returned `needs-rework` by all three reviewers (pseudo-replication disproved by its own text). **Do not build from this.** Replaced by stress-design-v2-2026-08-08 -->
>
> **Do not implement as written.** The adversarial pass found: §4.3's weeks-level
> Oura comparison is **pseudo-replication**, disproved by the document's own text two
> lines above; an AR(1) deflation factor asserted as 2 when the cited source gives
> **2.84**; a worked example printing a band from neither of its own formulas and
> understating the honest one by 35%, on a day that is **statistically null**; a
> "≈16% by construction" null that is not derivable from the algorithm as specified,
> with every threshold resting on it; the headline's closest competitor being
> `periodContrastCard` — a section already on the same card, which §6 never looks at;
> `stress.arousalHours` being `EnergyModel.exertionHours` with different parameters;
> and the gate the whole daytime half hangs on set at |ρ| ≥ 0.6 with no power
> arithmetic, at an n that cannot decide it.
>
> **What survives: the inventory and the relay rule.** Oura's stress fields are real,
> unread, and cover 90 of the last 90 days, so grading ourselves against them is
> genuinely available — as a labelled second opinion, never blended. Backlog `N1`.

# Stress — the design (backlog N1)

_Written 2026-08-07. **Designed, not built.** Supersedes
`docs/stress-design-2026-08-06.md`, which was written before the research pass
and before the 2026-08-07 export was counted. Six of its conclusions change and
each change is marked ⚠️ **CHANGED** with the evidence that forced it. Read that
document only for its Oura-source notes; read this one for the design._

The reader's instruction:

> *"I want to rename it to stress, and research how Oura ring do this, because
> they track stress, but lets do it better because we have more data."*

The rename shipped (`0dbc9b6`): `SustainedLoadInsight.title` is "Stress load"
and `BalanceWeb.swift:362` returns "Stress". The research is the item.

**The reader's ruling, 2026-08-07, which settles the scope question:**

> **BOTH, on one card** — a daytime signal and the sustained nocturnal one, with
> Oura's own number shown beside ours as a labelled second opinion, never
> blended in.

⚠️ **Counts in this document were measured** against
`~/HealthSeed/exports/health-insights-export-new.json`, `generatedAt`
2026-08-07T07:09:11Z, Australia/Sydney. "The last 90 days" means
2026-05-10 … 2026-08-07. **Counts only — no reading from this reader's body
appears here**, per `docs/privacy-and-ip.md`.

---

## 0. The one-line answer, and the one place it refuses the obvious

One card, **"Stress"**, carrying two quantities that are never allowed to look
like each other:

- **The headline stays the weeks-scale nocturnal load** — four channels, 28 days
  against 90, unchanged in weights and unchanged in model version.
- **A daytime figure joins it**, computed by us from continuous heart rate at
  quarter-hour resolution, gated to still waking non-post-exertion time, in
  **hours** rather than on a 0–100 dial, **always printed with a derived band**,
  and at **weight 0**.
- **Oura's own stress and resilience fields are relayed beside both**, weight 0,
  under the `vascularAge` rule, with a day-by-day agreement section that is the
  card's genuinely unique feature.

⚠️ **CHANGED — the daytime figure does not move the score.** The 2026-08-06 doc
recommended it as a fifth channel at weight 0.7. Three things forbid that, and
all three arrived after it was written:

1. **The evidence.** No consumer daytime stress feature has a single published
   accuracy figure — not Oura, Whoop, Garmin, Fitbit or Samsung (Doherty et al.,
   *Transl Exerc Biomed* 2025: 14 composite scores, 10 manufacturers, none
   disclosing a formula). The two field studies that tested one against how
   people actually felt found it tracked the wrong thing: van der Mee et al.
   (*J Affect Disord Rep* 2025, n = 95, 28 days, EMA 5×/day) found Garmin's
   Stress Score associated with *positive* high-arousal emotion and **no
   association with negative emotion**, and concluded the name is "incorrect and
   misleading to consumers"; Siepe et al. (*J Psychopathol Clin Sci* 2025,
   n = 781, 3 months, up to 352 EMA observations each) found wearable and
   self-reported stress "did not overlap for most individuals". Research-grade
   ambulatory ECG reproduces it (Hachenberger et al., *Sensors* 2023, n = 26,
   7 days, posture-stratified): daytime HRV tracked positive affect at β = −0.11
   and had **no significant association with negative affect at all**.
2. **Our own coverage.** Restricted to 09:00–21:00, only **47 of the last 90
   days** carry heart rate in ≥ 24 of the 48 waking quarter-hour bins — and that
   is *before* the stillness and post-exertion gates take their cut.
3. **The derived error** (§8.3). At the by-construction null the figure's own
   95 % band is wider than the figure on every realistic day.

The ruling is honoured on **presence** — both quantities are on the card, both
are visible, both are charted. It is refused on **scoring**, and §8 says exactly
why in the card's own words. A permanent null would be the useless option, so
§8.4 states the promotion criterion and, honestly, states that on today's data
it is unlikely to be met soon.

---

## 1. The two quantities, kept visibly distinct

This is N1's point 1, and it is a rendering problem as much as a modelling one.

| | **Oura's Daytime Stress** | **This app's Stress load** | **This app's new daytime figure** |
| --- | --- | --- | --- |
| Atom | 15 minutes | one night | 15 minutes |
| Window | within one day | **28 days vs the previous 90** | within one day |
| Measured when | awake, worn, relatively inactive | asleep | awake, still, ≥ 3 h after exertion |
| Inputs | HR, HRV, finger temperature, motion | rMSSD 1.0, resting HR 0.9, respiratory rate 0.6, sleep duration 0.5 | heart rate only (§3.2 says why HRV is dropped) |
| Statistic | undisclosed vendor composite; `stress_high` is **seconds in the wearer's own top quartile** | median of each window, robust scale, one-sided weighted z, `ScoreCurve` to 0–100 | hours above the reader's own hour-of-day median by > 1 robust scale |
| Minimum | 5 days of continuous wear | 10 days in each window, ≥ 2 channels | 4 measurable hours (§9) |
| Answers | *what is my body doing right now* | *has a drift lasted weeks* | *how much of today's still time ran hot* |
| Weight on our score | **0** | **the score** | **0** |

**Three renderings keep them apart, and none of them is a caption.**

1. **Different units on screen.** The headline is 0–100 and higher is calmer,
   like every other dial in the app. The daytime figure is **hours out of
   measurable hours** — "3.2 h of 8.5 measurable" — and never a 0–100 number. A
   reader cannot confuse two numbers that are not on the same scale. This is the
   single most effective separation available and it costs nothing.
2. **Different charts.** The headline gets the existing score-over-time line.
   The daytime figure gets a quarter-hour ribbon for today and a day × hour heat
   strip for the last 28 days. Neither chart type appears twice on the card.
3. **Oura's numbers never share an axis with ours.** In the comparison section
   (§4) they appear as the *other* axis of a scatter, or as the grouping
   variable of a box plot — never as a second line on our chart. `add-chart`'s
   hatch-never-blend rule applies: one quantity drawn over another is hatched,
   not blended, and these are two quantities from two formulas.

⚠️ **`stress_high` is a rank statistic, not a strain measurement.** The API
definition is "time spent in a high stress zone (**top quartile of data**), in
seconds". Two people with entirely different physiology get the same number if
each is equally deviant from their own recent distribution, and the baseline
moves under it, so it cannot trend meaningfully over long windows. The caption
must say "against your own recent distribution" wherever it appears. The unit is
**seconds** — widely misreported as minutes, including by open-source API
wrappers.

⚠️ **Oura's four on-screen zones (Stressed / Engaged / Relaxed / Restored) are
not the three `day_summary` values (stressful / normal / restored).** The zones
are momentary states; `day_summary` is a whole-day rollup; **no published rule
maps one onto the other**, so we cannot reconstruct or sanity-check it. If both
ever surface, they render as separate things.

---

## 2. What the evidence permits, and what it forbids

Everything in §3–§5 is downstream of this section.

### 2.1 Forbidden outright

| Forbidden | Why | Source |
| --- | --- | --- |
| **LF/HF as a stress index**, in any form, ever | Every assumption fails: sympathetic nerve activity is not the major contributor to LF, and conditions that unambiguously raise sympathetic activity (exercise, myocardial ischemia) do not consistently raise LF and may lower it | Billman, *Front Physiol* 2013;4:26 |
| **Drawing two frequency-domain HRV quantities as independent series** | LFnu, HFnu and LF/HF are mathematically equivalent transforms of one another; showing several implies independent evidence that does not exist | Heathers, *Front Physiol* 2014;5:177 |
| **Calling anything here "allostatic load"** | The construct has a precise published definition: ten markers including 12-hour urinary cortisol, epinephrine, norepinephrine, DHEA-S, HbA1c and lipids. **Not one is obtainable from a wearable**, and HRV is not among them | McEwen & Stellar 1993; Seeman et al., *PNAS* 2001;98:4770 (n = 1,189) |
| **Sleep stages (deep/REM) in any arithmetic** | Consumer four-stage classification accuracy is 60–75 % | JCSM 2025 meta-analysis, 24 studies / 798 patients (PMID 39484805) |
| **Fitting our thresholds to Oura's labels** | §4.4 — this is merging by the back door | the `vascularAge` rule |
| **A multi-day alcohol HRV carry-over** | Every trace of the "2–3 drinks suppress HRV for 5 days" claim goes back to vendor blog content. The only controlled multi-day design (Strüven et al., *Nutrients* 2025, n = 40, 3 exposure + 3 post days) reported rapid normalisation | recorded as a gap, not a finding |

### 2.2 What the evidence permits, with its size

| Permitted | Size | Source |
| --- | --- | --- |
| **RMSSD as the time-domain arousal index**, at rest, over windows ≥ 30 s | RMSSD from 10 s vs 5 min: r = 0.853–0.862; at rest ICC > 0.9 from 30 s to 4 min | Shaffer & Ginsberg, *Front Public Health* 2017; PLOS ONE 2015 (PMC4586373) |
| **A 28-day median rather than a daily HRV value** | day-to-day CV of lnRMSSD is 3–13 %; ~3 days/week in trained and ~5 in recreational subjects reproduce the 7-day average; single days routinely exceed the smallest worthwhile change | Plews et al., *Eur J Appl Physiol* 2012;112:3729 and *IJSPP* 2014;9:783 |
| **Sustained nocturnal resting-HR elevation against a personal baseline** as a real signal | 63 % of COVID cases detectable pre-symptomatically vs a 28-day sliding baseline; 26/32 showed HR, step or sleep alterations | Mishra et al., *Nat Biomed Eng* 2020;4:1208 |
| **Excluding post-exertion time from a daytime arousal read** | after running: HR elevated 180–210 min, HRV depressed 270–300 min, with dose-response by intensity. After high-stress work: HRV lower 90–300 min. **The two shadows overlap almost entirely** | Presby, Jasinski & Capodilupo, *PLOS ONE* 2023;18(5):e0285332 — n = 974, 23,665 running events, 8,928 work events. Whoop's own paper |
| **A ~1-hour autocorrelation timescale in daytime heart rate** | meal / posture / stress effects modelled as AR(1) with ~1 h timescale; circadian HR amplitude 3.96 ± 1.86 bpm | Bowman et al., *Cell Rep Methods* 2021;1(4):100058 — 136,789 device-days, 927 subjects |

### 2.3 The three findings that reshape the design

**(a) A wearable "stress" number is an arousal number, and arousal has no
valence.** Excitement, a hard hour, a stressful meeting and a fever move it the
same way. This is not our caveat — it is the published conclusion of the only
peer-reviewed evaluation of a commercial stress score against momentary emotion
(van der Mee 2025). It means the *daytime* quantity must be named for arousal,
even though the *card* must be named "Stress" so the reader can find it (§7).

**(b) Daytime HRV is confounded in the direction that makes a bad day look
good.** Speaking systematically raises RSA and SDNN, and mental-stressor tasks
performed aloud yield *higher* RSA than the same tasks performed silently.
Daytime HRV measurement error runs roughly double nighttime error, from movement
and posture change. A day of back-to-back meetings — the archetypal stressful
day — is a day of near-continuous speech, which biases the very metric upward
toward "restored". ⚠️ **This is the specific reason Apple restricted Vitals to
overnight**, and the specific reason §3.2 drops the daytime HRV channel.

**(c) Apple's precedent is the honest shape, and Apple is the largest player.**
Apple ships **no** sensor-derived stress score. *State of Mind* is entirely
self-reported with zero sensor inputs. *Vitals* is overnight-only, uses five
metrics, needs 7 nights to establish a typical range, fires only when **≥ 2
metrics agree**, and deliberately names **several candidate causes** —
medications, elevation, alcohol, illness — rather than attributing the deviation
to one. Two of those three properties are already how this card works. The third
(name several causes, not one) is what §5 turns into the product.

---

## 3. The daytime signal's algorithm

### 3.1 What it is called and what it is

**`stress.arousalHours`** — *the number of still, waking, non-post-exertion hours
in which the reader's heart rate sat more than one robust scale above their own
median for that hour of day, over the trailing 28 days.*

Always rendered with its denominator and its band:

> **3.2 h of 8.5 measurable hours** — 95 % band 1.4–5.0 h.
> On a typical day about 1.4 of those hours would sit above the line by
> construction.

⚠️ **CHANGED — it is hours, not a 0–100 index, and there are no four bands.** The
2026-08-06 doc proposed `DaytimeStressIndex` on a 0–100 `ScoreCurve` with four
bands mirroring Oura's vocabulary. Both are dropped. A 0–100 dial makes it look
like the headline and like Readiness, which is the confusion §1 exists to
prevent. The four bands required four thresholds, and the only proposed way to
choose them was maximising agreement with Oura's `day_summary` — which is
merging (§4.4).

### 3.2 Inputs — and the one that is dropped

| Input | Coverage, last 90 days | Role |
| --- | --- | --- |
| `heartRate` samples | 73,654 rows, 81 of 90 days; median **67 of 96** quarter-hour bins, p10 = 34. ⚠️ **Only 47 of 90 days carry ≥ 24 of the 48 bins in 09:00–21:00** | the arousal carrier |
| `stepCount` | 90 of 90 days | motion gate |
| `activeEnergyBurned` | 83 of 90 days | motion gate + exertion-bout detection |
| Sleep intervals (`SleepNights`) | 68 of 90 nights | defines "awake" |
| Substance episodes | ⚠️ 18 events on **9 distinct days**, no dose on any | **shading only** (§5) |
| Calendar events, holiday ledger, `activeMedicationLevel` | see §5 | **attribution only, never a correction** |

⚠️ **CHANGED — daytime HRV is dropped as an input.** The 2026-08-06 doc gave it
weight 0.8 in the bin statistic. Two independent reasons, either sufficient:

- **Coverage.** SDNN is sample-resolution and does reach daylight, but thinly:
  **39 of the last 90 days** carry any reading in 09:00–21:00, with a median of
  **5** quarter-hour bins on those days and **only 9 days reaching 8**. A term
  present on a tenth of days is not a channel. rMSSD is nightly-aggregate only —
  117 rows, all stamped 00:00–01:59, alias-promoted from
  `oura.sleep.average_hrv` (`PromotionRules.swift:188`).
- **Validity.** §2.3(b). Where it *is* present it is biased upward by exactly the
  activity that characterises a stressful day.

**We have no daytime temperature at all.** `skinTemperature` and
`skinTemperatureDeviation` are 64 of 90 days each and both are sleep-derived.
Oura reads finger temperature continuously and peripheral vasoconstriction is
the most specific of their four inputs to an acute stress response. So we
reproduce **two** of Oura's four inputs (HR, motion), not three. Expect our
figure to under-detect short sharp stressors.

### 3.3 Per-day computation

For each local day, over the 96 quarter-hour bins:

1. **Gate on wakefulness.** Drop bins overlapping a detected sleep interval.
2. **Gate on stillness.** A bin is *still* when its step count is ≤ 10 and its
   active energy is below the reader's own 60th percentile of waking-bin active
   energy over the trailing 28 days. Personal, not fixed, for the same reason
   Oura's thresholds are personal — and `Baseline.robustScale` is already the
   house tool.
3. ⚠️ **Gate on the post-exertion shadow.** Drop bins within **180 minutes** of
   the end of any exertion bout. Basis: Presby 2023 measured HR still elevated
   180–210 min after a run. 180 is the shorter, coverage-preserving end of the
   published range and therefore leaves a **known upward bias** — say so.
   ⚠️ **This gate is the design's biggest unmeasured cost.** The 47-of-90 figure
   above is *before* steps 2 and 3. Slice 2 measures coverage at 120 / 180 /
   240 / 300 min and the window is chosen with the number in front of us.
4. **Require substance.** A bin needs ≥ 3 heart-rate samples to be scored.
5. **Score the bin against the reader's own hour-of-day baseline** over a
   trailing 28 days. This is the one refinement that matters: 08:00 and 22:00 are
   not the same physiological hour, and comparing both to a single daily median
   makes every morning look stressed.
   `z = (HR_bin − median(HR, same hour-of-day, 28 d)) / robustScale(same)`
6. **Mark the bin elevated** when `z > 1`. One threshold, self-referential, not
   fitted to anything. Under a normal distribution a robust scale matches the SD,
   so **≈ 16 % of still bins exceed it by construction** — which gives the card a
   *derivable null* rather than an asserted one, and that null is printed.
7. **Roll the day up.**
   - `measurableHours` = surviving bins ÷ 4
   - `arousalHours` = elevated bins ÷ 4
   - Both stored; neither is meaningful without the other.
8. **Refuse below 4 measurable hours** (§9 derives the floor). Between 4 and 6
   hours, **print the figure with its band** — thin data is a reason to print the
   error bar, not a reason to show nothing.

⚠️ **A gated-out bin is a gap, never a zero.** Oura says the same about their own
graph, and `add-chart`'s dash-means-inferred convention already has the
vocabulary.

### 3.4 Where it lives in the code

- **`DerivedSeriesID`, not `MetricType`.** `add-metric-type` lists nine
  exhaustive switches per case; `Derived/DerivedSeries.swift` exists for exactly
  "a modelled day-level quantity that should be charted and stored but is not a
  reading of the reader's body". Declared in `derivedOutputs`.
- **No engine signature change is needed.** It reads `heartRate`, `stepCount`,
  `activeEnergyBurned` and sleep intervals — all `[HealthMetricSample]` — so it
  computes inside the model. ⚠️ Note for whoever builds it: `evaluate` has **no**
  `DerivedSeriesStore` parameter in either overload, `derivedInputs` is declared
  by no model today, and the dependency graph therefore has zero edges. Do not
  design anything here that needs to read another card's derived series.
- **`.calculated`, weight 0, no reference range**, filed under the Data tab's
  `derivedScores` section ("Computed, never measured").

---

## 4. The comparison — the thing no competitor can do about itself

### 4.1 Why it is the feature

> This app holds Oura's own stress verdict and its own, day by day, on the same
> device. Oura cannot do this: they have no second opinion to be graded against.
> No other vendor can either, because none of them ingests a rival's output.

⚠️ **CHANGED — the denominators.** N1's own table says all three `daily_stress`
fields have "142 days, 90 of the last 90". Measured on the 2026-08-07 export:

| Field | Rows | Distinct days | **In the last 90** | Overlap with our usable HR days |
| --- | --- | --- | --- | --- |
| `oura.daily_stress.stress_high` | 145 | 145 | **89** | 77 |
| `oura.daily_stress.recovery_high` | 145 | 145 | **89** | 77 |
| `oura.daily_stress.day_summary` | 122 | 122 | **73** | 71 |
| `oura.daily_resilience.level` | 95 | 95 | **63** | 63 |
| `.contributors.{stress, daytime_recovery, sleep_recovery}` | 95 each | 95 | **63** | 63 |

**No Oura stress field covers 90 of the last 90.** ⚠️ **23 days across the record
— 16 of the last 90 — carry the seconds but no verdict**, so the categorical
comparison has a smaller denominator than the continuous one and those 16 days
must not silently vanish into the smaller number. The backlog rows at
`docs/backlog.md:312-318` should be corrected to match this table.

⚠️ **"Overlap with our usable HR days" above uses the ≥ 24-of-96-bins rule. The
honest waking-hours denominator is smaller and is unmeasured.** Our side gives
47 days at ≥ 24 of the 48 bins in 09:00–21:00, so the intersection with Oura's 89
is **at most 47** — and lower again after the stillness and post-exertion gates.
Slice 1 measures it. **The card prints whatever it turns out to be, not this
table's 77.**

### 4.2 ⚠️ The finding that changes what the comparison means

**59,069 of our 73,654 heart-rate rows come from `apple_health/oura`.** The
intraday carrier is mostly *Oura's own sensor*, relayed through Apple Health.
Only 14,543 rows come from the Apple Watch.

So on most days, "our daytime figure vs Oura's daytime stress" is **the same
photoplethysmogram processed two ways**. That is not worthless — it isolates the
*algorithm* difference cleanly, which is arguably the more interesting
comparison — but it is not an independent instrument check, and calling it one
would be the kind of quiet overclaim this repo's docs exist to stop.

⚠️ **CHANGED.** The 2026-08-06 doc's advantage table opens with "continuous
daytime heart rate… the within-day curve never leaves their app". That is right
about the *classification* and wrong about the *signal*.

**Consequence for the section:** agreement is computed **stratified by carrier**
— days whose HR came predominantly from the Apple Watch, and days it came from
Oura-via-Apple-Health. Watch-carried day coverage is unmeasured (slice 1). If it
is too thin to stratify, the section is labelled, in its own heading, **"same
sensor, two formulas"**.

### 4.3 What the section shows

**Day-level** — our `arousalHours / measurableHours` against Oura's day:

| # | Statistic | Form | Why this one |
| --- | --- | --- | --- |
| 1 | **Rank agreement** | Spearman ρ against `stress_high` seconds, on the shared days | Scale-free. Ours is a fraction of measurable day, theirs is seconds in their own top quartile; only the *ordering of days* is commensurable |
| 2 | **Ordinal agreement** | Three box plots of our fraction, one per `day_summary` value, with n printed on each, plus Kendall's τ-b | An **observation**, not a fit. No thresholds are chosen, so nothing is fitted to the vendor |
| 3 | **Carrier stratification** | 1 and 2 recomputed on watch-carried days | §4.2 |
| 4 | **Disagreement, named** | The days furthest apart, each with **what we hold and they do not** — the calendar block, the leave period, the modelled drug level, the substance shading, the non-wear gap | This is the product. A disagreement with a named coincidence is a finding; one without is a bug report |

**Weeks-level** — our Stress load 0–100 against `daily_resilience.level`, five
ordinal levels, on the 63 shared days: a box per level plus τ-b.
⚠️ Resilience is a composite *of composites* — its nighttime-recovery contributor
contains Sleep Score and HRV Balance, themselves undisclosed Oura composites, and
its level changes only ~2–3 times a month. **Redrawing it daily would imply a
resolution it does not have**, so it renders as a step series, not a line.

### 4.4 The four rules for this section

1. **Neither number moves the other.** Not as a prior, not as a tie-break, not as
   a "blend when confidence is low". `weight: 0`, exactly as `vascularAge`.
2. ⚠️ **CHANGED — no fitted thresholds, and no Cohen's κ.** The 2026-08-06 doc
   proposed choosing our four band thresholds by maximising κ against
   `day_summary`. **That is merging by the back door**: it makes our number a
   function of their undisclosed formula, and no leave-one-out reporting fixes
   that, because the *shape* of our statistic would still have been chosen by
   theirs. κ needs categories on both sides; we have no categories, by design.
   Spearman ρ and Kendall's τ-b need none.
3. **Print both denominators, always**, and the reason each day was excluded —
   ours (too little data) and theirs (no reading) counted separately.
4. **Disagreement is not our error, and agreement is not our validation.** Oura
   has published **zero** validation of Daytime Stress or Resilience — no n, no
   ground truth, no accuracy figure, and their science-and-research page lists no
   publication for any of their three stress features. Their only public claim is
   the unquantified sentence that the algorithm was "validated against other
   well-established solutions and by conducting surveys". **There is no gold
   standard on either side of this comparison**, and the honest phrasing is
   *"we and Oura read these N days the same way on M of them, and here is what
   the rest had in common"*.

### 4.5 How the fields are read

⚠️ **Architectural blocker the 2026-08-06 doc missed: no `InsightModel` can read
a `RawMetricSample`.** `evaluate` takes `[HealthMetricSample]` and `[VitalEvent]`
and nothing else. "Read them from the raw catalogue" is not currently possible
from a model.

**The precedent is already in the codebase and fits exactly.** `VitalEvent`
exists because "an irregular-rhythm notification is a judgement Apple already
made, with no unit and no baseline, so it could not be modelled as a `MetricType`
without inventing both" (`Insight.swift:509`). That sentence describes Oura's
stress fields word for word.

So: a **`VendorOpinion`** type and a **`VendorOpinionReader.opinions(from:
[RawMetricSample])`**, mirroring `VitalEventReader.events(from:)`
(`VitalEvent.swift:112`), with a fixed allow-list of identifiers and a default
`evaluate` overload that ignores them — so adding it touches no other model.
`RawValue.text` already models `day_summary` and `resilience.level`, with
`numericValue` deliberately nil.

⚠️ **Do not promote these to `MetricType`.** They are a vendor's opinion, not a
reading of a tissue; filing them beside heart rate is the same mistake as
dressing modelled as measured.

✅ **Backlog D28 is already done** — `RawFieldGrouping.swift:168` returns
`.stressResilience`, titled **"Stress & resilience (Oura)"**, placed deliberately
ahead of the generic `.contributors.` and `.sleep_` rules, with presentation and
seconds-of-day formatting at `RawFieldPresentation.swift:179-200` and tests at
`RawFieldPresentationTests.swift:274-316`. The 2026-08-06 doc calls it a
prerequisite; it is not.

---

## 5. What we have that Oura does not — and which one carries the advantage

N1's point 2 requires naming which one, rather than asserting that more data is
better. **The calendar carries it. Everything else is second, and two of the
2026-08-06 doc's rows must be demoted.**

| Rank | What we hold | Measured | The question Oura structurally cannot answer |
| --- | --- | --- | --- |
| **1** | **The calendar** | ⚠️ Raw event coverage is **unmeasurable from any export by design** — `HealthDataExport.swift:434` emits nothing for `.calendarEvents`, because titles and locations are the most identifying strings the app holds. The evidence is the Work-impact card's own outputs (2026-08-06): **50 working days compared in the last 56**, split 24 busy / 26 quiet, busy 6.80 h vs quiet 1.90 h, heaviest 11.14 h across 7 meetings, `workImpact.workExposure` = 2.251× a typical day | *What was that afternoon?* Oura can draw a cortisol-shaped 14:00–17:00 rise and label it "stressed". We can say **which named block it sat inside**. Attribution is the product, and nothing Oura sells attributes anything |
| **2** | **Modelled medication level** | `activeMedicationLevel`, **89 of 90 days** — the densest reader-only covariate in the export. 22 tirzepatide doses 2026-02-16 → 2026-08-03, 12 in the last 90 | *Is this a drug or a life?* And it has a **published expectation to check against**: tirzepatide raises resting HR by +2.05 bpm (95 % CI 0.96–3.13; 12 RCTs, 15,313 participants, *Eur J Med Res* 2026), the ZEPBOUND label says 1–3 bpm, and the SURMOUNT-1 ABPM substudy (n = 600) found 2–5 bpm dose-dependent at week 36. Oura reads that step as three weeks of unexplained stress |
| **3** | **Holiday ledger** | **15 periods, all detected, 59 leave days total, 12 in the last 90 across 4 periods.** ⚠️ Read by **nothing** — `HolidayLedger`'s own header says H6 is unwired | *Did the weeks-scale load actually lift on leave?* A natural experiment on exactly the window the headline scores, sitting fully populated and unread. The cheapest real win on this card |
| 4 | **The daytime HR series, kept** | 73,654 rows, 180-day lookback | ⚠️ **Demoted, see §4.2.** The advantage is **memory and inspectability** — we keep the quarter-hour series and a bad afternoon is still inspectable in March, where Oura's API returns two daily totals — **not measurement**, because most of the signal is their own sensor |
| 5 | **Gait** | walkingSpeed / stepLength / doubleSupport **90 of 90 days each**, phone-in-pocket so they survive nights the ring charged | Behaviourally independent of the four autonomic channels, and a ring has no gait. ⚠️ **But no published curve links gait to stress.** Saying so is the finding. Not shown on this card today; recorded as the strongest future channel |
| 6 | **Substance log** | ⚠️ **18 events on 9 distinct days**, 17 stimulant + 1 cannabis, **`units` and `note` nil for all 18 — there is no dose**. 5 episodes under the 24 h gap rule; only stimulant clears `minimumEpisodesToDescribe` | ⚠️ **Demoted hard.** Derived power: a stimulant effect at d = 0.59 needs ≈ 23 episodes for 80 % power (n = 7.85/d²); there are 4. **Shading and a caveat, not a stratifier.** The 2026-08-06 doc made this row 3 and proposed stratifying arousal by stimulant days; 9 days against 68 is a footnote, not a section |
| 7 | **Cuff blood pressure** | **5 days in the last 90**, against the estimator's own `minimumCalibrationPoints` = 5 and an expected 2 readings/month | At the edge of freshness. Cannot ground a daytime comparison. Real ground truth Oura structurally lacks — if the reader starts using the cuff again |

### The "better" claim, in the form it can be defended

> Oura can tell you *that* your body was aroused, on a 15-minute grid, with a
> temperature sensor we do not have and — on most days — with the same sensor
> that supplies our own daytime heart rate. **It cannot tell you what it was.**
> The calendar, the leave ledger and a modelled drug level with a published
> expected effect sit on the same device as the arousal series, with timestamps.
> Our advantage is **attribution and memory, not sensitivity.**

⚠️ **And the reverse, in the same breath.** Oura beats us on continuous daylight
temperature (we have none), on wear continuity (a ring outlasts a watch on the
charger), and on a classifier tuned across a population. **Our figure will be
noisier per quarter-hour than theirs**, and the card says so.

⚠️ **Attribution is coincidence in time, never a test.** With 9 substance days,
5 cuff days and 12 leave days in 90, none of these supports a per-day causal
claim. The disagreement list names what *else* was true that day. It never says
"because".

---

## 6. The overlap justification — answered concretely, and one collision the last doc missed

N1's point 4. Metric sets, from the code:

| Card | Window | Metrics and weights |
| --- | --- | --- |
| **Readiness** | today vs a windowed baseline | rMSSD-or-SDNN 0.40, resting HR 0.25, sleep duration 0.20, skin-temp deviation 0.10, respiratory 0.05, SpO₂ 0.05 |
| **Symptom radar** | 3 d vs 21 d, CUSUM k = 0.5 h = 6 | skin-temp deviation 1.0, skin temp 1.0, resting HR 0.9, rMSSD 0.9, SDNN 0.8, respiratory 0.8, SpO₂ 0.5 |
| **Stress load** | 28 d vs 90 d, min 10/10 | rMSSD 1.0, resting HR 0.9, respiratory 0.6, sleep duration 0.5 |
| ⚠️ **Work impact** — the fourth reader the 2026-08-06 doc omits | 56 d, ≥ 8 working days per half, night-AFTER-the-day | resting HR, rMSSD, sleep duration |

**Set relations, and they are uncomfortable:**

- **Stress load ⊂ Readiness, exactly.** All four of its metrics are Readiness
  components.
- Stress load ∩ radar = 3 of 4 (the radar has no sleep duration).
- Work impact = Stress load minus respiratory rate.

⚠️ **So on metric identity alone, the card's existing headline is already a
fourth rendering of the same nightly measurements — the window is the only thing
distinguishing it.** That is precisely what `SustainedLoadInsight`'s own header
argues, and it survives: only a 28-vs-90 comparison can see a drift that never
trips an acute threshold, because by the second week it is not unusual. But the
independence claim that most needs defending on this card is the *headline's*,
not the daytime figure's — and `docs/illness-detection-evidence-2026-08-07.md`
sharpens it: what these four channels detect is **non-specific systemic strain**,
reproduced by alcohol, hard training, poor sleep, travel, altitude and the
menstrual cycle. The caveat driver is not a disclaimer; it is a measured fact.

### Is the daytime figure a fourth window, or a fourth rendering?

**At the metric level it is genuinely new: none of those four scoring cards reads
raw intraday `heartRate` at all.** All four consume a *day* as their atom and all
four read only night-derived values. Nothing in the app scores a Tuesday
afternoon.

⚠️ **But it is not unclaimed territory, and the 2026-08-06 doc does not mention
the collision. `EnergyModel` already computes a within-day quantity from heart
rate above resting** — `exertionHours` (`Energy.swift:312`) counts hours with
HR ≥ resting + 15 bpm, and `curve` (`:327`) builds an hourly within-day drain
curve, described in the code as catching "the strain that never became a workout
— a bad commute, a stressful hour".

**The distinction is real and statable:**

| | Energy's `exertionHours` | `stress.arousalHours` |
| --- | --- | --- |
| Movement | counted **in** — it is the point | gated **out**, plus a 3 h post-bout shadow |
| Baseline | one daily resting figure | the reader's own **hour-of-day** median, 28 d |
| Purpose | drains a reservoir | flags elevation that exertion does not explain |

By construction they should be near-complementary: Energy counts the exertion,
arousal counts the elevation that is *not* exertion. **That is a testable claim
and this design refuses to assert it.**

> ⚠️ **Slice 3 is a gate, not a chore.** Compute Spearman ρ between daily
> `arousalHours` and Energy's `exertionHours` over the shared days.
> **If |ρ| ≥ 0.6, the daytime figure does not ship as a figure** — the gating
> failed, it is re-rendering Energy's drain term, and it becomes a chart on the
> Stress card or nothing at all. That is a legitimate outcome and the reader
> should be told it plainly rather than shipped a fifth view of one measurement.

**Should the daytime figure feed Readiness or the symptom radar too? No.** One
new signal into three cards is how three cards start saying the same thing.

---

## 7. Naming

N1's point 5: the reader asked for a stress card, it shipped under a name they
could not find, and they asked three more times. **The rule is findability by the
word they think in**, and the word is "stress".

| Surface | Now | Proposed |
| --- | --- | --- |
| **Card title** | "Stress load" | **"Stress"** |
| **Balance-web spoke** | "Stress" (`BalanceWeb.swift:362`) | **unchanged** |
| **Data tab — Oura's relayed fields** | "Stress & resilience (Oura)" (`RawFieldGrouping.swift:40`), under `DataDomain.unmodelled` → "Other data" | **unchanged** ✅ already shipped |
| **Data tab — our own series** | — | under `DataDomain.derivedScores` → **"Scores & estimates"**. ⚠️ That title contains no "stress", so the **series display names must**: **"Stress — daytime arousal hours"**, **"Stress — measurable hours"**, **"Stress — sustained load"** |
| **Bespoke section 1** | "Where the load is sitting" | **"Your stress through the day"** (the channel bars keep their name, nested beneath) |
| **Bespoke section 2** | — | **"Oura's opinion, and ours"** |
| **Telemetry label** | "Stress load" (`TelemetryOutboxView.swift:248`) | **"Stress"** |
| **Model types** | `SustainedLoadModel`, `SustainedLoadInsight` | **`StressModel`, `StressInsight`** — free, nothing persists a type name |
| **`InsightID` case** | `.sustainedLoad` (`Insight.swift:59`) | ⚠️ **UNCHANGED** |

⚠️ **`InsightID.sustainedLoad` must not be renamed.** It is a persisted raw
value: score history, feedback rows, the telemetry outbox and derived-series
namespacing (`DerivedSeriesID(insight, key)` builds `"sustainedLoad.…"`) all key
on it. Renaming the case renames stored data. **Leave a comment on the case
saying exactly this**, or a future session will tidy it. The consequence to
accept: the series are stored as `sustainedLoad.arousalHours` while displaying as
"Stress — daytime arousal hours". That asymmetry is correct and should be
commented too.

⚠️ **Turn the naming lesson into a check, not prose.** The Data tab's only search
is `DataTabView`'s `.searchable`. Add a test asserting that **a Data-tab search
for "stress" returns both the Oura group and this card's own derived series**. A
rule that lives in a lint outlives a rule that lives in a paragraph — and this
particular rule has already failed once, expensively.

**"Stress" not "Stress load" for the title.** Once the card holds a weeks-scale
score, a daytime figure and a comparison against Oura, "load" describes one of
three. The shortest word the reader searches for is the right title, and the
honesty lives in the caveat driver — which already says this cannot separate
stress from illness, alcohol, heat or hard training. **That sentence is
load-bearing and must survive the rename verbatim.** "Stress load" survives
inside the card as the label of the nocturnal half.

---

## 8. Weights, and where every one of them comes from

### 8.1 The score — unchanged

| Channel | Weight | Why this share | Its own known error |
| --- | --- | --- | --- |
| HRV rMSSD | **1.0** | most direct read on parasympathetic tone | Day-to-day CV of lnRMSSD is 3–13 %; single days routinely exceed the smallest worthwhile change (Plews 2012/2014). ⚠️ The 28-day median is what makes it usable, and it can now be **cited** rather than asserted. Single source (Oura), 23 days in the recent window |
| Resting heart rate | **0.9** | rises with load, measured over hours of a still supine body | Multi-source (Oura 117, Watch 139, shortcuts 111); `VitalReader.dailySeries` picks **one winning source by coverage and never blends** |
| Respiratory rate | **0.6** | sleep-derived, rises with load | ⚠️ Only 36.4 % of PCR-confirmed illnesses ever showed a ≥ 3 br/min rise, and it peaks *two days after* onset (Natarajan 2021, via `docs/illness-detection-evidence-2026-08-07.md`). It is confirmatory, not leading |
| Sleep duration | **0.5** | least specific — a short fortnight is as likely a choice as a symptom; it earns a place because sustained short sleep *causes* the other three to drift | Consumer wrist TST bias **−16.85 min** (95 % CI −26.33 to −7.38), JCSM 2025, 24 studies / 798 patients. Small against a 28-day median — say so, because it means the uncertainty here is dominated by the model, not the sensor |

⚠️ **`Feedback.swift:170` stays `sustained-load-v1`.** CHANGED from the
2026-08-06 doc, which proposed `stress-v2` because it was adding a fifth channel.
No channel is added, no weight moves, so **the number does not change meaning** —
and bumping the version would orphan the reader's stored feedback for a rename.

### 8.2 Everything else on the card, at weight 0, each saying why

| Shown | Weight | The reason it cannot carry one |
| --- | --- | --- |
| `stress.arousalHours` | **0** | §0's three reasons: no published validation exists for any consumer daytime stress feature; the two field studies that tested one found it tracks *positive* affect (van der Mee, n = 95) and does not overlap self-report for most people (Siepe, n = 781), reproduced with research-grade ECG (Hachenberger, n = 26); and §8.3's derived band is wider than the figure on any realistic day |
| Oura `stress_high`, `recovery_high` | **0** | Vendor composite, undisclosed formula. `vascularAge` rule, absolute |
| Oura `day_summary`, `resilience.level`, its 3 contributors | **0** | The same, twice over — Resilience nests Sleep Score and HRV Balance, themselves undisclosed composites |
| Gait, if ever shown here | **0** | ⚠️ **No published curve links gait to stress.** That is a finding and it is stated, not papered over. Today it is not shown on this card at all |

### 8.3 Uncertainty — derived, not cited

**(a) The daytime figure's own band.** `arousalHours` is a count of elevated bins
out of measurable bins, so its standard error is binomial:
`SE(p) = √(p(1−p)/n)`.

⚠️ **But the bins are not independent.** Bowman et al. 2021 modelled the
non-circadian component of daytime heart rate as AR(1) noise with a **~1-hour
timescale** across 136,789 device-days. So the effective number of independent
units is roughly the number of **hours**, not quarter-hours — and treating
quarter-hours as independent overstates precision by a factor of about 2.

Both figures, on a day with a 25 % elevated fraction:

| Measurable hours | 95 % band, bins independent (**a floor**) | 95 % band, one independent unit per hour |
| --- | --- | --- |
| 4 h (1.0 h estimate) | ± 0.85 h | **± 1.7 h** |
| 6 h (1.5 h estimate) | ± 1.04 h | **± 2.1 h** |
| 12 h (3.0 h estimate) | ± 1.5 h | **± 2.9 h** |

**What this means, stated as the card must state it.** The by-construction null
is ≈ 16 % of still hours. Testing an observed fraction against that null at one
independent unit per hour:

- on a **6-hour** measurable day, more than **45 %** of still hours must sit
  above the line before the day differs from the reader's own typical day at all;
- on a **12-hour** day, more than **37 %**.

So the figure can distinguish a badly elevated day from a quiet one. **It can
never resolve a small difference, and it may never be given a verdict adjective
on a normal day.** That is the honest ribbon, and it is arithmetic the reader can
check — not a borrowed error bar.

**(b) The hour-of-day baseline's own error.** The robust scale in the denominator
of every `z` is estimated from at most 28 daily values per hour-of-day bin. The
relative standard error of a sample SD is `1/√(2(n−1))` = 13.6 % at n = 28; the
MAD's asymptotic relative efficiency at the normal is ≈ 0.37, so a robust scale's
relative error is ≈ 13.6 %/√0.37 ≈ **22 %**, rising to ≈ **32 %** where an
hour-of-day bin has only 14 days. That propagates roughly proportionally into
`z`, and it is a second reason the threshold is a plain `z > 1` rather than a
finely-tuned cut.

**(c) The headline's own error.** For a roughly normal sample the median's
standard error is `1.2533σ/√n`. With 23 recent days that is **0.26 σ**, and with
68 reference days **0.15 σ**, so **each channel's departure carries a standard
error of about ± 0.30 SD**. Pooling four channels with weights 1.0/0.9/0.6/0.5
gives a Kish effective count of (Σw)²/Σw² = 9/2.42 = **3.72**, so the pooled
figure would be ± 0.16 SD **if the channels were independent**.

⚠️ **They are not.** Three of the four come from a single Oura nightly record,
and `VitalReader` picks one winning source per metric rather than blending. So
the truth lies between ± 0.16 SD and ± 0.30 SD, and **the card prints the
conservative end, ± 0.30 SD, until this reader's own inter-channel correlation is
measured** — which is computable from the export and is a slice-3 task. The band
is carried through `ScoreCurve` and rendered on the score's own scale.

### 8.4 What would earn the daytime figure a weight

A permanent null is the useless option, so the promotion criterion is stated —
along with the honest odds of meeting it.

**The criterion:** the figure must separate the reader's own busy working days
from their own quiet ones. Work impact already holds the split — **24 busy vs 26
quiet working days over 56** — and it is *this reader's* evidence, not borrowed.

⚠️ **And the honest arithmetic against it.** With ~25 days per group, the
smallest effect detectable at 80 % power is `d = 2.80·√(2/25)` ≈ **0.79** — a
large effect. Work impact's own pooled body difference across its three nocturnal
channels was **+0.445 SD**, below that floor. **So the gate is unlikely to be met
soon, and this document says so rather than implying a weight is around the
corner.** Re-run it at slice 8; report the number either way; do not add channels
until it passes.

---

## 9. Empty states — every one a `CoverageGate`

`CoverageGate` (`Presentation/CoverageGate.swift`) exists so a model cannot
withhold a figure without saying what it is waiting for, and it goes silent once
met. Every gate below is one.

| Where | Gate | The sentence's shape |
| --- | --- | --- |
| **Daytime figure, today** | need **4** measurable hours | *"2 of 4 measurable hours so far — 2 more and this can say how much of your still day ran above your own line."* |
| **4–6 measurable hours** | **no gate — show the figure with its band** | Thin data is a reason to print the error bar, not a reason to show nothing. The band will be wider than the figure and that is the honest picture |
| **Hour-of-day baseline** | need **10** days with a reading in that hour | Below it the hour is drawn as a gap, never as a zero |
| **Day-level comparison, seconds** | need **29** shared days | Derived: at n = 29 a Spearman ρ of 0.5 is detectable at 80 % power (`n = ((1.96+0.84)/atanh ρ)² + 3`). At the 77 shared days available, the detectable ρ is **0.31**; at the honest waking-hours denominator (≤ 47) it is **0.40**. Print the detectable ρ beside the observed one |
| **Day-level comparison, verdict** | need **29** shared days | 71 available today; ρ detectable ≈ 0.33 |
| **Weeks-level comparison** | need **29** shared days | 63 available; ρ detectable ≈ 0.35 |
| **Carrier stratification** | need **20** watch-carried days | ⚠️ Coverage unmeasured — slice 1. Below it the section is headed **"same sensor, two formulas"** |
| **Named-disagreement list** | need the calendar connected **and** ≥ 10 named days | Without it the list is dates with nothing beside them |
| **Headline** | existing: 10 days in each window, ≥ 2 channels | All four channels clear it today (recent 23–24, reference 68–73) |

⚠️ **A refusal must never look like an absence.** That distinction is the whole
reason `CoverageGate` is a type rather than a convention, and it is the reader's
own instruction from 2026-08-06: *"users know why things are — or are not
showing in the app."*

---

## 10. What this card may never claim

1. **Never that the daytime figure measures stress.** It measures arousal, and
   arousal has no valence — a peer-reviewed paper has already named this error
   (van der Mee 2025). The card is called "Stress" because that is the word the
   reader searches for; the *figure* inside it is called arousal, everywhere.
2. **Never LF/HF**, computed or displayed, in any form. If an upstream source
   hands us one it is relayed with Billman 2013 attached, or dropped.
3. **Never "allostatic load"**, or any implication of it. Ten canonical markers,
   none wearable-obtainable.
4. **Never an accuracy claim from the Oura comparison**, in either direction.
   There is no gold standard on either side.
5. **Never a fitted threshold.** Nothing on this card may be tuned to agree with
   `day_summary`, `stress_high` or `resilience.level`.
6. **Never a per-substance effect.** 9 substance days in 90, no dose recorded on
   any of the 18 events, and a derived floor of ~23 episodes for the one
   substance with more than one episode. Substances are shading and a caveat.
7. **Never "the injection day did this."** With tirzepatide's ~5-day half-life on
   a 7-day interval, plasma level never returns to zero and **there is no
   unexposed day to compare against**. This is structurally unanswerable, not
   thin data — the unit of attribution is an epoch of weeks. The RHR step-change
   comparison against the published +2.05 bpm is legitimate; ⚠️ and it is
   confounded by weight loss pushing the same metric the other way, which must be
   said in the same sentence.
8. **Never a multi-day alcohol or HRV "recovery window"** longer than the
   drinking night plus the following day.
9. **Never sleep stages in arithmetic.**
10. **Never "measured."** Everything computed here is `MetricSource.calculated`:
    its own family, weight 0, no reference range, filed under "Scores &
    estimates — Computed, never measured".
11. **Never that this separates stress from illness, alcohol, heat, travel,
    altitude, the menstrual cycle or hard training.** The existing caveat driver
    already says it; `docs/illness-detection-evidence-2026-08-07.md` shows it is a
    measured fact and not a hedge. **What the card adds is that for several of
    those there is now a log with timestamps that can be checked.**
12. **Never that the reader's self-report is the reference.** Van Dongen et al.
    (*SLEEP* 2003, n = 48) showed subjective sleepiness saturates while objective
    impairment keeps climbing, and subjects were "largely unaware" of the growing
    deficit. A modelled figure may legitimately disagree with how the reader
    feels, and it says so rather than being tuned to agree.

---

## 11. Build order, in shippable slices

Each slice is independently shippable, passes `./scripts/verify.sh --tests`, and
leaves the app usable. No slice both changes the score and adds UI. Push straight
to `main` — no pull requests (`ship-to-main`).

| # | Slice | Contents | Gate |
| --- | --- | --- | --- |
| **1** | **Read Oura's opinion, and measure the real denominators** | `VendorOpinion` + `VendorOpinionReader.opinions(from:)` on the `VitalEvent` precedent, with a default `evaluate` overload so no other model is touched. **No UI.** Then measure and record: shared-day counts at the waking-hours rule; the carrier split (watch vs Oura-relayed HR days); calendar event coverage **on the phone**, which no export can give | Unit tests on fixtures; **counts asserted, never values**. Output is numbers in this doc |
| **2** | **The daytime figure, headless** | `Insights/DaytimeArousal.swift` — §3.3 in full. Then measure coverage at post-exertion windows of 120/180/240/300 min and choose with the number in front of us | Synthetic-day tests: flat day, spiky day, gap-riddled day, workout day, sub-floor day. ⚠️ **Stop and ask if coverage after gating falls below ~30 of 90 days** — at that point it is a sometimes-number and §12 S4 applies |
| **3** | **The two gates that decide whether this ships** | (a) Spearman ρ between daily `arousalHours` and `EnergyModel.exertionHours`; (b) inter-channel correlation among the four nocturnal channels, which sets the pooled SE in §8.3(c). Test-target tools reading `~/HealthSeed/`, **never a fixture in the repo** | ⚠️ **|ρ| ≥ 0.6 means the figure does not ship as a figure.** Report both numbers to the reader before slice 5 |
| **4** | **Rename** | `SustainedLoadModel` → `StressModel`, title → "Stress", telemetry label, the `InsightID`-stays comment, the derived-series display names, **and the Data-tab search test** (§7). `Feedback.swift` untouched | `verify.sh` lint; `gen-symbol-index.sh` |
| **5** | **Bespoke section 1 — "Your stress through the day"** | Today's quarter-hour ribbon with its band; the 28-day day × hour heat strip; the existing channel bars nested beneath. ⚠️ **`add-chart` first**; substance shading on both, where it is the primary confound made visible rather than decoration | Mac session: `./scripts/simulator.sh run` then `shot`, **and Read the PNG**. Two cards shipped invisible on 2026-08-03 |
| **6** | **Bespoke section 2 — "Oura's opinion, and ours"** | §4.3 in full: the scatter and ρ, the three boxes and τ-b, the weeks-scale step series, the carrier stratification, both denominators, the relay caveat. ⚠️ **`docs/card-sections.md` in the same commit** — a third card taking position 6 moves four hand-written tables — and re-run `./scripts/card-map.sh` | `handover-check.sh` runs `card-map.sh --check` |
| **7** | **Attribution** | The disagreement list gains calendar blocks, **holiday-ledger leave periods (H6 — currently read by nothing)** and `activeMedicationLevel` as named coincidences, never causes. This is the "better than Oura" claim and it is last because it is worthless until 1–6 are trustworthy | Real-data check on the reader's phone (`use-the-phone`) |
| **8** | **The promotion review** (gated, optional) | Re-run §8.4's busy-vs-quiet split. Report the number whether it passes or not | If it passes the derived d ≈ 0.79 floor, bring a weight proposal to the reader. Otherwise leave weight 0 and record why |

**Stop-and-ask points, both non-negotiable:** after slice 2 (coverage after
gating) and after slice 3 (both gate numbers). Either can end the daytime half of
this design, and ending it is a legitimate outcome.

---

## 12. Open decisions for the reader

| | Question | Default if unanswered |
| --- | --- | --- |
| **S1** | The ruling was "both on one card". Is **weight 0** for the daytime half acceptable — present, charted, never scoring? | **Yes.** §0 and §8.2. The alternative is a number the published evidence says tracks the wrong emotion |
| **S2** | Title **"Stress"**, with "Stress load" surviving inside as the nocturnal half's label? | Yes — §7 |
| **S3** | Post-exertion exclusion window: **180 min** (published HR shadow 180–210) or 300 min (the HRV shadow)? | 180, measured against coverage in slice 2, with the residual upward bias named |
| **S4** | If the figure survives fewer than ~30 of 90 days after gating, does it ship as a figure at all? | **Chart only**, no figure, no gate sentence pretending it is coming |
| **S5** | Should the daytime figure feed **Readiness** or the **symptom radar**? | **No** — one signal into three cards is how three cards start saying the same thing |
| **S6** | Is the Apple Watch worn enough to give an independent carrier, or is the whole comparison "same sensor, two formulas"? | **Unmeasured — slice 1.** Whatever it says is what the heading says |
| **S7** | **Gait** on this card as a corroborating series at weight 0, with "no published curve links gait to stress" printed? | **Leave it off.** `GaitInsight` owns it; adding it here with no evidence is decoration |
| **S8** | Should the **holiday ledger** (H6, 12 leave days in 90, read by nothing) be wired for this card, or wait for its own item? | Wire it in slice 7 — it is the cheapest real attribution win available |

---

## Sources

**Peer-reviewed, load-bearing.** Billman, *Front Physiol* 2013;4:26 (LF/HF).
Heathers, *Front Physiol* 2014;5:177. Shaffer & Ginsberg, *Front Public Health*
2017;5:258, with PLOS ONE 2015 (PMC4586373) and *Life* 2024;14:837 for
ultra-short validity. Plews et al., *Eur J Appl Physiol* 2012;112:3729 and
*IJSPP* 2014;9:783. van der Mee, Koyuncu & Lemmers-Jansen, *J Affect Disord Rep*
2025;21:1–11 (n = 95). Siepe, Tutunji, Rieble, Proppert & Fried, *J Psychopathol
Clin Sci* 2025;134(8):912–925 (n = 781). Hachenberger et al., *Sensors*
2023;23(2):966 (n = 26). Presby, Jasinski & Capodilupo, *PLOS ONE*
2023;18(5):e0285332 (n = 974). Doherty, Baldwin, Lambe, Burke & Altini,
*Transl Exerc Biomed* 2025;2(2):128–144 (14 scores, 10 manufacturers). Bowman et
al., *Cell Rep Methods* 2021;1(4):100058 (136,789 device-days). Mishra et al.,
*Nat Biomed Eng* 2020;4:1208–1220. Bravi et al., *Front Physiol* 2013;4:197
(n = 13 v 13). McEwen & Stellar 1993; Seeman et al., *PNAS* 2001;98:4770
(n = 1,189). JCSM 2025 sleep-tracker meta-analysis (PMID 39484805, 24 studies /
798 patients). Van Dongen et al., *SLEEP* 2003;26(2):117–126 (n = 48). Zhang et
al., *Eur J Med Res* 2026 (12 RCTs, 15,313 participants) with the ZEPBOUND label
and the SURMOUNT-1 ABPM substudy (n = 600).

**Vendor documentation, read as claims and not as evidence.** Oura Member Care,
*Daytime Stress* and *Resilience*; Oura's *Inside the Ring* posts on Daytime
Stress, Resilience and Cumulative Stress; the Oura API v2 `daily_stress` field
definitions via CareEvolution MyDataHelps; Apple Support on *Vitals* and *State
of Mind*; Google/Fitbit Help on readiness.

⚠️ **Numbers deliberately not used**, and a later session should not adopt them:
the kcalm.app blog's uncited three-process correlation table; the transposed
marginal/conditional R² quoted secondhand from Siepe et al.; the Garmin
lab-validation preprint (bioRxiv 2025.01.06.630177), unretrievable; the AJP-Regu
2025 allostatic-load digital-phenotype paper's n and effect sizes,
unretrievable; and any figure for the "2–3 drinks suppress HRV for 5 days"
claim, which traces only to vendor blogs.

**Code read for this document:** `Insights/SustainedLoadInsight.swift`,
`Insights/Energy.swift`, `Insights/Insight.swift`, `Insights/VitalEvent.swift`,
`Insights/CalendarInsights.swift`, `Insights/ReadinessScore.swift`,
`Insights/HealthWatch.swift`, `Presentation/CoverageGate.swift`,
`Presentation/RawFieldGrouping.swift`, `Presentation/DataDomain.swift`,
`Presentation/BalanceWeb.swift`, `Ingestion/PromotionRules.swift`,
`Models/HolidayLedger.swift`, `Feedback/Feedback.swift`,
`Features/Data/DataTabView.swift`, `Features/Settings/TelemetryOutboxView.swift`.


---

## Open decisions

- S1 — The ruling was "both on one card". Is weight 0 for the daytime half acceptable: present, charted, never scoring? Default yes. The published evidence (van der Mee 2025 n=95, Siepe 2025 n=781, Hachenberger 2023 n=26) says a daytime arousal score tracks positive affect and does not overlap self-report, and no vendor has ever published an accuracy figure for one.
- S2 — Card title "Stress", with "Stress load" surviving inside the card as the nocturnal half's label? Default yes.
- S3 — Post-exertion exclusion window: 180 min (the published HR shadow is 180-210 min, Presby 2023) or 300 min (the HRV shadow)? Default 180, chosen against measured coverage in slice 2, with the residual upward bias named on the card.
- S4 — If the daytime figure survives fewer than ~30 of 90 days after the wake/stillness/post-exertion gates, does it ship as a figure at all? Default: chart only, no figure, and no coverage gate implying one is coming.
- S5 — Should the daytime figure also feed Readiness or the symptom radar? Default NO — one new signal into three cards is how three cards start saying the same thing.
- S6 — Is the Apple Watch worn enough to give an independent carrier for the Oura comparison, or is the whole comparison "same sensor, two formulas"? 59,069 of 73,654 heart-rate rows are Oura's own sensor relayed through Apple Health. UNMEASURED — slice 1 settles it, and whatever it says becomes the section heading.
- S7 — Gait on this card as a corroborating series at weight 0, with "no published curve links gait to stress" printed? Default: leave it off. GaitInsight already owns it and adding it here with no evidence is decoration.
- S8 — Should the holiday ledger (H6: 15 detected periods, 12 leave days in the last 90, currently read by nothing) be wired for this card, or wait for its own backlog item? Default: wire it in slice 7 — it is the cheapest real attribution win available.

## Build order

1. Slice 1 — Read Oura's opinion, and measure the real denominators. Add `VendorOpinion` + `VendorOpinionReader.opinions(from: [RawMetricSample])` on the existing `VitalEventReader` precedent, with a default `evaluate` overload so no other model is touched (no InsightModel can currently read a RawMetricSample at all — this is the architectural blocker the 2026-08-06 doc missed). No UI. Then measure: shared-day counts at the waking-hours rule, the carrier split (Apple Watch vs Oura-relayed heart-rate days), and calendar event coverage on the phone. Gate: unit tests on fixtures, counts asserted and never values. Note backlog D28 is already done — RawFieldGrouping.swift:168 already files these under "Stress & resilience (Oura)".
2. Slice 2 — The daytime figure, headless. `Insights/DaytimeArousal.swift`: wake gate, stillness gate, post-exertion shadow gate, >=3 samples per bin, z against the reader's own hour-of-day median over 28 days, elevated at z > 1, roll up to `arousalHours` / `measurableHours`, refuse below 4 measurable hours. Pure InsightKit, Linux-testable, no engine signature change needed. Then measure coverage at post-exertion windows of 120/180/240/300 min and choose with the number in front of us. Gate: synthetic-day tests (flat, spiky, gap-riddled, workout, sub-floor). STOP AND ASK if coverage after gating falls below ~30 of 90 days.
3. Slice 3 — The two gates that decide whether this ships at all. (a) Spearman rho between daily `arousalHours` and `EnergyModel.exertionHours` on shared days — Energy already computes a within-day HR-above-resting quantity, so the independence claim must be tested rather than asserted; |rho| >= 0.6 means the daytime figure does NOT ship as a figure. (b) Inter-channel correlation among the four nocturnal channels, which sets the pooled standard error printed on the headline. Both as test-target tools reading ~/HealthSeed/, never a fixture in the repo. Report both numbers to the reader before slice 5.
4. Slice 4 — Rename. `SustainedLoadModel` -> `StressModel`, `SustainedLoadInsight` -> `StressInsight`, title -> "Stress", telemetry label -> "Stress", derived-series display names to "Stress — daytime arousal hours" / "Stress — measurable hours" / "Stress — sustained load", and a comment on `InsightID.sustainedLoad` saying it must never be renamed (persisted raw value: score history, feedback rows, derived-series namespacing, telemetry outbox). Add a test asserting a Data-tab search for "stress" returns both the Oura group and this card's own series. `Feedback.swift:170` stays `sustained-load-v1` — no channel is added and no weight moves, so bumping it would orphan stored feedback for a rename.
5. Slice 5 — Bespoke section 1, "Your stress through the day". Today's quarter-hour arousal ribbon with its derived band; the 28-day day-by-hour heat strip; the existing channel bars nested beneath. Load `add-chart` first. Substance shading on both charts, where on this card it is the primary confound made visible rather than decoration. Gate: Mac session, `./scripts/simulator.sh run` then `shot`, and Read the PNG — two cards shipped invisible on 2026-08-03.
6. Slice 6 — Bespoke section 2, "Oura's opinion, and ours". The day-level scatter with Spearman rho, three box plots of our fraction grouped by Oura's `day_summary` with Kendall tau-b (no Cohen's kappa, no fitted thresholds — fitting our bands to their labels is merging by the back door), the weeks-scale resilience step series, the carrier stratification, both denominators with per-side exclusion reasons, and the relay caveat. Update `docs/card-sections.md` in the same commit — a third card taking position 6 moves four hand-written tables — and re-run `./scripts/card-map.sh`. Gate: `handover-check.sh` runs `card-map.sh --check`.
7. Slice 7 — Attribution. The named-disagreement list gains calendar blocks, holiday-ledger leave periods (H6, currently read by nothing) and `activeMedicationLevel` as named coincidences in time, never as causes. This is the "better than Oura" claim and it is last because it is worthless until slices 1-6 are trustworthy. Gate: real-data check on the reader's phone.
8. Slice 8 (gated, optional) — The promotion review. Re-run the busy-vs-quiet working-day split that Work impact already holds (24 busy vs 26 quiet over 56 days). The derived detection floor at ~25 per group is d ~= 0.79, and Work impact's own pooled body difference was +0.445 SD — below it — so this is expected to fail for a while. Report the number either way. If it passes, bring a weight proposal to the reader; otherwise leave the daytime figure at weight 0 and record why.

---

## Adversarial review — three hostile lenses


### Verdict: **needs-rework**

**Fatal:**
- §4.3 weeks-level comparison is pseudo-replication, and the doc supplies the proof itself. It computes Kendall's τ-b of our 0–100 score against `daily_resilience.level` over "the 63 shared days", and §9 prints a detectable ρ of 0.35 for it. Two lines above, the same section states resilience "changes only ~2–3 times a month" and refuses to draw it as a line for exactly that reason. Over 63 days (~2.1 months) that is roughly 5–6 distinct values, i.e. ~6 independent blocks, not 63 observations. Redo §9's own formula at n=6: 2.80/√3 = 1.617, tanh → detectable ρ ≈ 0.92. Nothing is detectable at this resolution. The design applies the step-function insight to the RENDERING and then throws it away in the STATISTIC, and ships a power claim understating the detectable effect by ~2.6×. This section cannot ship as a statistic; it is at most a picture.
- §3.3 step 5 never says which bins the hour-of-day baseline is estimated from, and the whole error model in §8.3(a) collapses on the answer. The formula is `z = (HR_bin − median(HR, same hour-of-day, 28 d)) / robustScale(same)` with no gating qualifier, while the bin being scored has passed the wake, stillness, ≥3-sample and 180-min post-exertion gates. If the baseline pools ungated bins it includes movement, so still bins sit systematically below a movement-inflated median and the elevated fraction is far below 16% — the "by construction" null, every band in §8.3(a), and the 45%/37% decision thresholds are all wrong. If it is gated, the doc must say so and must also state that the baseline's own denominator (still bins only, on a median of 67-of-96-bin days) is far thinner than 28×1. As written, the card's single most load-bearing number — the derived null it is proud of — is undefined. This is the difference between a derived error and an asserted one, which is the rule the doc invokes.
- §8.3(a)'s AR(1) deflation factor of 2 is asserted, and the doc's own cited source contradicts it. Bowman 2021 gives a ~1 h AR(1) timescale; at a 15-minute bin the lag-1 correlation is ρ = exp(−0.25) = 0.779, and the variance-inflation factor for a mean of AR(1) samples is (1+ρ)/(1−ρ) = 8.0, i.e. widen by √8 = 2.84×, not 2×. "One independent unit per hour" corresponds to VIF = 4, which back-solves to ρ = 0.6 and a timescale of ~0.5 h — half what the cited paper reports. (The counter-argument is that the scored series is a THRESHOLDED indicator, whose autocorrelation is not the latent HR's; but the doc performs no such calculation and cannot claim its number either way.) Every band in the §8.3(a) table is too narrow by an unquantified factor, and "anti-conservative by about 2×" is the precise failure this reader has already been burned by with the permutation null. Nothing here is derived — estimate the deflation empirically from the reader's own 47 days of bin series and print that.
- The day-level join key and the timezone rule are never stated, on a card whose unique feature is a day-level join. §3.3 says "for each local day"; Oura's `daily_stress` is keyed by Oura's own day field on the ring's local date. The doc nowhere asserts these coincide, nowhere names the timezone the 09:00–21:00 window and the 96 bins are cut in, and nowhere handles travel — despite counting 4 leave periods and 12 leave days inside the very 90-day window, and despite `CalendarModel.timeZoneChanges` already existing in this repo as the tested travel signal (docs/backlog.md:661) and going unread by this design. This reader's own record has a finding set that flipped entirely on the day boundary (3 confirmations at UTC+8, 1 at UTC, 0 at UTC−5). A one-day join slip on even 10% of ≤47 shared days moves ρ materially, and the design has no way to notice.
- The headline's uncertainty is reported at 1 SE while the daytime figure's is reported at 95%, and that asymmetry is what makes the headline look usable. §8.3(a) prints "95 % band" throughout; §8.3(c) prints "± 0.30 SD" and stops. Take it to 95%: 1.96 × 0.30 = ±0.59 SD, pushed through the shipped `ScoreCurve.through([(0,100),(0.5,80),(1.0,55),(2.0,25),(3.0,10)])` (SustainedLoadInsight.swift:140). A load of 0.6 (score ≈ 75) carries a 95% interval of load 0.01–1.19, i.e. a score band of roughly 50 to 100 — most of the dial. Worse, ±0.30 SD is NOT the conservative end as claimed: it assumes independent days within each channel, on a card whose entire premise is multi-week drift. At a lag-1 day correlation of only 0.4 the median's SE inflates by √(1.4/0.6) = 1.53× to ±0.46 SD. Ship the same 95% convention for both quantities, or the card is presenting one number honestly and one flatteringly.

**Serious:**
- §8.3(a) uses a binomial SE that conditions on `measurableHours`, but the denominator is random and correlated with the numerator: more still time means less activity means lower HR. This is a ratio estimator, not a binomial proportion, and the band conditional on n is not the band on the day's arousal. It also breaks §8.4's promotion test directly — a meeting-heavy "busy" day is a day of sitting, so nearly every waking bin passes the stillness gate, while a "quiet" day loses bins to errands and exercise plus a 3 h shadow each. The exposure being tested changes the denominator of the outcome. That is same-day activity entering through the gate rather than through the model, and it is exactly the confounder that took a substance effect from min|z| 0.91 to 0.03 on this reader's own record.
- Sample-density bias in the bin statistic is unmodelled and runs in the wrong direction. §3.3 step 4 scores a bin on ≥3 samples; §3.2 reports a median of 67-of-96 bins with p10 = 34, so the sparsest decile of days is roughly half as dense. The bin value's own sampling error is therefore ~4× larger on a 3-sample bin than on a 12-sample one, and sparse bins are correspondingly more likely to trip z > 1 by chance. Watches also sample HR more densely when HR is elevated, so density is correlated with the outcome. Sparse days will read as more aroused. Either weight bins by their sample count or require a floor high enough that the within-bin error is small against the between-bin scale — and state which.
- The figure pools two sensors inside itself with no source-selection rule, while the doc notes elsewhere that this app deliberately refuses to do that. §4.2 measures 59,069 Oura-relayed and 14,543 Watch heart-rate rows; §8.1 notes `VitalReader.dailySeries` "picks one winning source by coverage and never blends" for the nightly channels. §3.3 blends them silently for the intraday series. Two devices with different HR bias feeding one 28-day hour-of-day median means that any change in the wear mixture — the ring on the charger for three afternoons — shifts the baseline and manufactures elevation. The carrier problem is identified for the COMPARISON and ignored for the FIGURE.
- A trailing 28-day self-referential baseline is blind to anything with a timescale of ≥28 days, which is precisely what this card exists to detect. During a sustained stressful month the hour-of-day median tracks the elevation and `arousalHours` reverts toward its null — the daytime figure will read most reassuring exactly when the headline reads worst. That makes the two halves anti-correlated by construction at long timescales and is a real risk of the card contradicting itself on screen. §6's gate tests `arousalHours` against `EnergyModel.exertionHours` and never against the headline. Add that correlation to slice 3.
- The slice-3 ship/no-ship gate is a coin flip as specified. "|ρ| ≥ 0.6 means the daytime figure does not ship as a figure" is a threshold on a point estimate whose 95% CI at n ≈ 47 is about ±0.22: an observed 0.50 passes while the truth could be 0.70, and an observed 0.65 fails while the truth could be 0.42. Define the gate on the interval (e.g. fail if the CI's upper bound exceeds 0.6). Separately, 0.6 is itself an asserted threshold in a document whose §10.5 forbids asserted thresholds, with no derivation offered.
- The slice-3 gate also measures the wrong thing, because `arousalHours` and `exertionHours` are mechanically coupled through the exclusion window. I read `Energy.exertionHours` (Energy.swift:317): it is `elapsed_hours × (samples above resting+15) / (total samples)` — structurally the same fraction-above-a-personal-threshold estimator as `arousalHours`, on the same series. And every exertion bout removes 12 quarter-hour bins from arousal's denominator via the 180-min shadow. A non-zero ρ is guaranteed by the gate alone. The test cannot distinguish "re-rendering Energy's drain term" from "coupled through the shadow", which is the only question it was asked.
- There is no family, no alpha and no correction anywhere on the card. Counting: ρ and τ-b at day level, both again under carrier stratification, τ-b at weeks level, the slice-3 ρ, the inter-channel correlations, and the §8.4 busy-vs-quiet test — at least eight statistics on heavily overlapping data (the carrier strata are subsets of the pooled set). The doc's silence is worse than an invalid correction: BH under measured negative dependence (r = −0.795) has already burned this reader once, and here the dependence structure is not even characterised. State the family, state which single statistic is the headline, and pre-register it before slice 6 rather than choosing after seeing them.
- The named-disagreement list in §4.3 row 4 is a guaranteed-hit generator presented to the reader as a finding. It searches five covariate families (calendar block, leave period, modelled drug level, substance shading, non-wear gap) over the disagreeing days. From the doc's own counts, `activeMedicationLevel` covers 89 of 90 days, ~24 of 56 working days are busy, 12 days are leave and 9 carry substances — so the marginal probability that ANY given day carries at least one label is close to 1 once medication is included. "A disagreement with a named coincidence is a finding; one without is a bug report" is therefore a rule that can essentially never return the second branch. The section needs a printed base rate: what fraction of ALL days carries each label, beside the fraction of disagreeing days that does. Without that, §5's "never says because" caveat will not survive contact with the reader.
- §5's substance power calculation uses the wrong formula and an uncited effect size. `n = 7.85/d²` is the paired/one-sample requirement — (1.96+0.84)² = 7.84 — but comparing substance days against non-substance days is an unpaired two-sample design, requiring ~15.7/d² PER GROUP, i.e. ~45 per group at d = 0.59, not 23 total. The conclusion (demote to shading) is unaffected and correct, but the stated bar is understated ~4×. Separately, d = 0.59 appears with no source; I grepped the repo and docs and found nothing supporting it. Derive it or drop the number and say the effect size is unknown.
- §9's "available" column is inflated for two of its three rows. The doc corrects the seconds row (77 → ≤47 at the honest waking-hours rule) and then leaves the verdict row at "71 available today; ρ detectable ≈ 0.33" and the weeks row at "63 available", both of which come from the same ≥24-of-96 rule the doc just disowned. The verdict row's honest n is at most 47 ∩ 73, plausibly ~35–40, where the same formula gives a detectable ρ of ~0.44–0.47. Recompute the whole column at the waking-hours denominator, or the card prints a power claim it has already argued against on the line above.
- Every power and detectable-ρ figure in §9 treats calendar days as independent draws. Both series are serially correlated — weekly work rhythm (the doc's own 24 busy / 26 quiet split over 56 days), illness runs, medication epochs, leave periods — and both sides share the same physical sensor on most days (§4.2). Serial correlation inflates the FALSE-POSITIVE rate of a Fisher-z ρ test, not only the stated power, so "print the detectable ρ beside the observed one" implies a valid null that does not exist here. Use a block permutation or phase-randomised null with blocks at least a week long, and report the effective n. (Minor and swamped by this: Spearman's SE needs the ~1.06 Bonett–Wright factor, which moves the 29-day gate to ~31.)
- Speech confounds the daytime HR channel too, and the doc silently exempts it. §2.3(b) disqualifies the daytime HRV channel on the grounds that speaking raises RSA and SDNN, and that a day of back-to-back meetings is a day of near-continuous speech. It then builds the entire promotion criterion (§8.4) on busy versus quiet WORKING days — the exposure most saturated by speech — and asserts nothing about whether the retained HR channel is clean. Speech is a respiratory and postural perturbation; the claim that it moves HRV but not HR needs a citation or an explicit "unknown, and it biases the promotion test in the direction that would pass it".
- The 96-bin day is wrong twice a year and the hour-of-day baseline is wrong for a month after each transition. §3.3 hard-codes 96 quarter-hour bins per local day; Australia/Sydney has 92 on 2026-10-04 and 100 on 2026-04-05. The measured window (2026-05-10 … 2026-08-07) happens to avoid both, which is why it has not surfaced — but the card ships into October. More consequentially, after 4 October "09:00 local" is one solar hour earlier than in the preceding 27 days of the baseline; against Bowman's own cited circadian HR amplitude of 3.96 ± 1.86 bpm, that injects roughly a 1 bpm spurious offset into every hour-of-day bin for 28 days — the same order as the +2.05 bpm tirzepatide effect §5 wants to check against. Key the baseline on solar/UTC offset or rebuild it across the transition.
- `Baseline.robustScale` takes a `floor:` parameter whose own doc comment says it "is not optional in practice" because MAD is exactly zero whenever more than half the values are identical — and §3.3 never specifies a floor for intraday HR. Quarter-hour HR at a fixed hour of day across 28 days is integer-rounded and tightly clustered when the reader is still; a small or zero MAD is entirely reachable. Whenever the floor binds, `z > 1` is no longer one robust SD, and the ≈16% by-construction null the whole card is built on silently becomes something else. Name the floor and derive it from measured bin-to-bin noise. Relatedly, 15.87% holds only under normality; still-bin HR is right-skewed by residual movement, which pushes the true fraction above the line higher. Measure the null on the reader's own data instead of assuming it.

**Required changes:** Six edits, in order of what blocks shipping.

1. §3.3 step 5 — state explicitly which bins the hour-of-day median and robust scale are estimated from (gated still bins, or all bins), and name the `floor:` passed to `Baseline.robustScale` with its derivation. Then STOP asserting the 16% null: measure the reader's own elevated-fraction distribution over the 47 usable days and print that as the null, with its own spread. Everything in §8.3(a), including the 45%/37% decision thresholds, is downstream of this and must be recomputed.

2. §8.3(a) — replace the asserted "factor of about 2" with a measured deflation. Compute the lag-k autocorrelation of the thresholded indicator series on the reader's own bins and derive n_eff from it. Note in the text that Bowman's ρ = exp(−0.25) = 0.779 implies VIF = 8.0 for the latent series, so 2 is not derivable from the cited source in either direction.

3. §8.3(c) and the headline — print the 95% band, not 1 SE, so both quantities use one convention. Add the within-channel day-to-day autocorrelation to slice 3 alongside the inter-channel correlation, since ±0.30 SD is not the conservative end without it. Show the band's asymmetry after `ScoreCurve` and state plainly what §8.3(c) currently implies but never says: a mid-scale headline score carries a 95% band covering roughly half the dial.

4. §4.3 weeks-level — delete the τ-b and the §9 detectable-ρ row for resilience, or recompute both at the number of level CHANGES (~6 over 63 days, detectable ρ ≈ 0.92, i.e. nothing). Keep the step-series picture. Apply the same effective-n discipline to the day-level ρ: block permutation with week-long blocks, not Fisher-z, and print the effective n beside the observed ρ.

5. §3.3, §4.3, §11 slice 1 — add a day-boundary and timezone section. Name the join key against Oura's day field, name the timezone the local day and the 96 bins are cut in, wire `CalendarModel.timeZoneChanges` (it already exists and is tested) so travel days are excluded or re-based, and handle the 92/100-bin DST days. Report how many of the shared days shift under a ±1-day join and under UTC-vs-local, exactly as the finding-flip on this reader's record demands.

6. §9 — recompute the whole "available" column at the honest waking-hours denominator, not the ≥24-of-96 rule. §11 slice 3 — restate the ship gate on the confidence interval rather than the point estimate, derive the 0.6 or drop it, and add a second statistic that is not mechanically coupled to `exertionHours` through the 180-min shadow. §5 — fix the substance power formula to the two-sample ~15.7/d² per group, and either source d = 0.59 or remove it.

One thing the design gets right and should keep verbatim: refusing to fit thresholds to `day_summary` (§4.4 rule 2), and killing the Cohen's κ proposal. That reasoning is sound and is the strongest paragraph in the document.

### Verdict: **needs-rework**

**Fatal:**
- §3.1's worked example prints a band that comes from neither of its own two formulas, and understates the honest one by 35%. '3.2 h of 8.5 measurable hours — 95 % band 1.4–5.0 h' is ±1.8 h. Recompute from §8.3(a): p = 3.2/8.5 = 0.3765. Bins-independent (n=34 quarter-hours): SE = sqrt(0.3765*0.6235/34) = 0.0831, ×1.96 ×8.5 h = ±1.38 h → 1.8–4.6 h. One unit per hour (n=8.5), which §8.3(a) says is the honest one: SE = 0.1662, ×1.96 ×8.5 = ±2.77 h → 0.4–6.0 h. The printed ±1.8 is neither, and it sits between the floor the doc calls 'a floor' and the figure the doc calls honest. The single sentence a reader actually sees is the one number in the document that is not reproducible from the document. This is the exact failure the 'derive an error rather than citing one' rule exists to prevent, committed in the design's flagship copy.
- The same worked example is a statistically null day rendered as a headline figure. §8.3(a) says a 6-hour day needs >45% and a 12-hour day >37% to differ from the reader's own typical day. Run the identical arithmetic at n=8.5 hours: SE under the 0.16 null = sqrt(0.16*0.84/8.5) = 0.1257, ×1.96 = 0.246, so the threshold is 40.6%. The example day is 3.2/8.5 = 37.65% — below it. And §3.1 places directly beneath it 'On a typical day about 1.4 of those hours would sit above the line by construction', inviting the reader to compare 3.2 against 1.4 and read a 2.3× excess. The design's own demonstration of its honest rendering is a confident false positive.
- The '≈16% of still bins by construction' null is not derivable from the algorithm as specified, and every threshold in §8.3(a) rests on it. §3.3 step 5 defines the baseline as 'median(HR, same hour-of-day, 28 d)' and never says whether that population is gated by steps 1–3. It cannot be ungated: steps 2–3 score only still, non-post-exertion bins, which are the low tail of an ungated hour-of-day distribution, so the fraction exceeding median+1·robustScale would be far *below* 16% and the card would read permanently calmer than typical. If the baseline IS gated, §8.3(b)'s 'at most 28 daily values per hour-of-day bin' is wrong (the ~60th-percentile stillness gate plus the 180-min shadow cut it), and the 22%/32% scale errors are understated. The design must pick one and re-derive; as written the printed null, the 45%/37% significance thresholds, and the promotion gate in §8.4 all inherit an unstated assumption.
- The headline's ±0.30 SD band is zero-width at both ends of ScoreCurve and the design never states it in the units the reader sees. `ScoreCurve.through` (ScoreCurve.swift:44-46) returns `first.score` below the first anchor and `last.score` above the last, and SustainedLoadModel.score uses anchors [(0,100),(0.5,80),(1.0,55),(2.0,25),(3.0,10)]. So: at load ≥ 3.0 the card prints a confident 10 with no error bar — the most alarming reading on the card is the one that shows no uncertainty. `load` is `max(0, loadZ)`-weighted so it can never go below 0, meaning the lower half of the band is clipped at 100 too. In between, the 0.5→1.0 segment has slope −50 points/SD, so ±0.30 SD is ±15 points on the 0–100 dial — a fact stated nowhere in §8, while the weight-0 daytime figure gets three tables of bands. The scoring number's uncertainty is deferred to a formula that annihilates it at the extremes; the non-scoring number's is worked out in detail. That inversion is the honesty defect.

**Serious:**
- §8.3(c) computes the standard error of the wrong estimator. The code's `load` is `Σ w·max(0, loadZ) / Σw` (SustainedLoadInsight.swift:128) — a *rectified* weighted mean, not a weighted mean. Two consequences §8.3(c) misses: (a) the Kish effective count (Σw)²/Σw² = 9/2.42 = 3.72 is the formula for an unclamped weighted mean, so the ±0.16 SD floor does not apply; (b) rectification biases the estimator upward. With a per-channel SE of 0.30 SD, a channel whose true drift is exactly zero contributes E[max(0,X)] = 0.30/sqrt(2π) = +0.12 SD in expectation, so a reader with no drift at all scores load ≈ 0.12 → about 95, not 100. The card cannot read 'no load', and its null is 'a little load'. The clamp is a defensible design choice (the code argues it well at :123-126) but the error analysis has to be done on the estimator that ships.
- §8.3(c) omits the denominator error it correctly computes for the daytime figure. The code divides by `Baseline.robustScale(referenceValues)` — the reference spread, estimated from ~68 days. By §8.3(b)'s own method that carries a relative error of 1/sqrt(2·67)/sqrt(0.37) ≈ 14%, which propagates into every loadZ. §8.3(b) does exactly this arithmetic for the daytime baseline (22% at n=28) and §8.3(c) simply does not do it for the headline. The ±0.30 SD is therefore a floor, not a conservative end, and the doc calls it 'the conservative end'.
- §6's Energy-collision table is false on the code, which turns slice 3 from a gate into a formality it may fail for the wrong reason. `Energy.exertionHours` (Energy.swift:317-328) reads `samples.samples(of: .heartRate)` and nothing else — no step count, no active energy. Its movement row ('counted in — it is the point') is wrong: it does not measure movement, it measures HR ≥ resting + 15 bpm, which is structurally the same statistic as `arousalHours`. Worse, the code comment the design quotes approvingly at :312 says exertionHours exists to catch 'the strain that never became a workout — a bad commute, a stressful hour' — a still, non-bout, elevated-HR hour, which is precisely the set arousalHours is defined to count and which the stillness gate will *not* remove. The claim that the two are 'near-complementary by construction' is not merely untested; it is contradicted by the source the design cites for it.
- The kill gate has no denominator and no power statement — the only correlation in the document without one. §9 derives 29 shared days for a detectable ρ of 0.5 for every Oura comparison, but slice 3's |ρ| ≥ 0.6 gate against `exertionHours` gets neither. And `exertionHours` needs watch-carried heart rate (Energy.swift:315 comment: 'this needs a watch: at roughly 300 samples a day'), while §4.2 measures only 14,543 of 73,654 HR rows as Apple Watch. So the decision that can end the daytime half of this design is computed on the thinnest slice of data on the card, with an unmeasured n and no stated detectable ρ. A kill switch you cannot fire is not a gate.
- The Oura comparison has no by-construction null — the same omission the design correctly diagnoses in the 2026-08-06 doc's Cohen's-κ proposal, one level up. §4.2 establishes that 59,069 of 73,654 HR rows are Oura's own sensor. Our statistic is 'bins in the top tail of the reader's own 28-day hour-of-day distribution'; theirs is 'seconds in the wearer's own top quartile'. Two own-distribution tail counts computed from the same photoplethysmogram will correlate substantially before any algorithmic agreement exists. §9 prints the *detectable* ρ (a power figure) and never the *expected-by-construction* ρ. The card will render a guaranteed correlation under the heading 'Oura's opinion, and ours' and §4.4 rule 4's honest phrasing ('we and Oura read these N days the same way on M of them') will be describing shared plumbing. This needs a shuffled-day permutation null on the same carrier, computed in slice 1 and printed beside ρ — exactly as arousalHours prints its 16%.
- `Baseline.robustScale` is specified with no floor, and its own doc comment (Baseline.swift:112-116) says the floor 'is not optional in practice. MAD is exactly zero whenever more than half the values are identical, which a rounded daily metric reaches easily, and dividing by it produces an infinite z-score.' Heart rate is integer. In a still hour-of-day bin over 28 days a resting reader will frequently have >half the values identical → MAD = 0 → z = ∞ → every such bin flagged elevated. The existing headline code guards this with `spread > 0` and drops the channel (SustainedLoadInsight.swift:102); §3.3 step 5 has no floor and no guard. Left as written, the calmest hours of the calmest days are the ones most likely to be reported as arousal, which inverts the figure's meaning at the reading that matters most.
- The card is named for the thing §10.1 says it cannot measure, using a paper that condemns exactly that naming, and the most-seen surface is exempted without examination. §2.3(a) and §8.2 lean on van der Mee 2025 concluding a wearable stress score's name is 'incorrect and misleading to consumers' — then §7 names the card 'Stress', the telemetry label 'Stress', and marks the balance-web spoke 'unchanged'. The balance web renders the 0–100 score as a bare spoke under the word 'Stress' with no unit, no band, no caveat and none of the card-body mitigations. §7 never asks what that spoke renders. Findability is a real argument for the card title; it is not an argument for leaving the one surface that strips every caveat unexamined.
- The tirzepatide comparison cites an error where §8.3(c) already derived one that kills it. §5 rank 2 offers +2.05 bpm (95% CI 0.96–3.13) as 'a published expectation to check against' the resting-HR channel. Apply the design's own §8.3(c) arithmetic: the median's SE at 23 recent days is 0.26σ and at 68 reference days 0.15σ, giving ±0.30σ on the observed shift. With resting-HR night-to-night σ of roughly 3 bpm that is ±0.9 bpm SE, so a 95% interval of about ±2.2 bpm — the entire published CI sits inside the noise. The 'check' cannot fail and therefore is not a check. §10.7 then concedes weight loss pushes the same metric the other way over the same 22 doses, so the observable is a difference of two opposing effects of similar size compared against a published gross. Naming a confound is not the same as declining to print a number the confound makes uninterpretable.
- The denominator 'measurable hours' is manufactured and reads as observed, and one of its two biases is unnamed. Step 2 gates on active energy below the reader's *60th percentile* — a fixed-fraction cut dressed as personal, which removes ~40% of waking bins regardless of behaviour. Step 4 requires ≥3 HR samples per 15-minute bin, and Energy.swift:315 puts typical sampling at ~300/day ≈ 3 per bin, so the threshold sits at the median of the sampling rate — and PPG devices sample adaptively, more often when HR is elevated or changing. The bins admitted are therefore enriched for high-HR bins in numerator and denominator in a way that does not cancel. §3.3 step 3 names the 180-min shadow as 'a known upward bias — say so'; this second upward bias is named nowhere. 'of 8.5 measurable hours' is copy that reads as a measurement of the reader's still day and is a quantile-plus-sampling artefact.
- The daytime CoverageGate will fire on most days, making it a broken promise rather than a gate that goes silent once met. §9's sentence is '2 of 4 measurable hours so far — 2 more and this can say how much of your still day ran above your own line.' Bound it from the doc's own numbers: 47 of 90 days clear ≥24 of 48 waking bins; the marginal such day then loses ~40% to the stillness gate (24 × 0.6 ≈ 14 bins ≈ 3.5 h) before the post-exertion shadow takes anything, which is already below the 4-hour floor. The design calls this cost 'unmeasured' and defers it to slice 2, but this much is computable today from §3.2 and §3.3 and it points well below the ~30-of-90 stop-and-ask threshold. A gate that promises a figure which arrives on a minority of days is a permanent null wearing a progress bar — and S4's default ('chart only, no figure, no gate sentence pretending it is coming') is more likely the actual outcome than the fallback.
- Slice 5 ships the rendering that §10.6 forbids in prose. Substance shading on the 28-day day-by-hour heat strip marks 9 distinct days in 90 — roughly 3 visible days on a 28-day strip — with no dose recorded on any of the 18 events, directly adjacent to an arousal quantity. The house shading rule ('marks when something was logged, never what it did') is honest as a convention, but on this card the shaded thing and the charted thing are both arousal-shaped and three highlighted columns beside a heat map is a per-day causal read the reader will perform whatever §10.6 says. §5 rank 6 already demotes substances to 'shading and a caveat' on a derived power floor of ~23 episodes against 4 — the same arithmetic argues against the heat-strip overlay specifically, not just against a stratifier.
- The measured coverage counts do not describe the windows the headline uses. Every count in §3.2, §4.1 and §9 is over 'the last 90 days'. The headline's own windows are recentDays = 28 and referenceDays = 90 *before that* (SustainedLoadInsight.swift:36-38) — 118 days total. So §9's claim that 'all four channels clear it today (recent 23–24, reference 68–73)' is asserted against a window the export counts never covered. In a document whose premise is that its counts were measured rather than assumed, the headline gate's own coverage is the one thing still assumed.

**Required changes:** Four things must be re-derived before slice 2 is buildable, and one code claim corrected before slice 3 means anything.

1. §3.3 step 5 — state explicitly whether the hour-of-day baseline population is gated by steps 1–3. Then re-derive the by-construction null from that choice rather than asserting 15.87%, and re-derive §8.3(a)'s 45%/37% thresholds from the new null. Add the mandatory `floor:` argument to `robustScale` (Baseline.swift:112 says it is not optional) with the metric's measured noise floor, plus a guard that drops rather than flags a bin where the scale degenerates.

2. §3.1 — replace the worked example. Pick one band method, say which, and print the number it produces: at 3.2/8.5 the honest one-unit-per-hour band is ±2.77 h, not ±1.8 h. Then pick an example day that clears the design's own 40.6% threshold at n = 8.5, or keep this one and print what the arithmetic actually says about it — that it does not differ from a typical day. Also name the sampling-density bias from step 4's ≥3-sample rule alongside the 180-min shadow bias.

3. §8.3(c) — redo the headline's error on the estimator that ships. `load` is a rectified weighted mean (`Σ w·max(0,loadZ)/Σw`, SustainedLoadInsight.swift:128), so the Kish count does not apply; state the upward bias at the null (about +0.12 SD, score ≈ 95 not 100); fold in the ~14% relative error of `robustScale(referenceValues)`; and state the resulting band in points on the 0–100 dial at each ScoreCurve segment (±0.30 SD is ±15 points on the 0.5→1.0 segment). Say what the card renders where ScoreCurve is flat — at load ≥ 3.0 the band collapses to zero width and the worst reading on the card would print with no uncertainty at all. That is a design decision, not an implementation detail.

4. §6 — correct the Energy table. `exertionHours` reads heart rate only, no movement input, and its stated purpose ('the strain that never became a workout — a bad commute, a stressful hour') is the set arousalHours counts. Rewrite the distinction on the axes that are actually real (threshold form, hour-of-day vs daily baseline, the post-bout shadow) and drop the 'movement counted in' row. Give slice 3's ρ gate a denominator and a detectable-ρ the way §9 does for every other correlation, and state that it is computed on watch-carried days only (14,543 of 73,654 rows).

5. §4 — add a by-construction null for the agreement statistic: a shuffled-day permutation ρ on the same carrier, computed in slice 1, printed beside the observed ρ. Without it the section renders shared plumbing as a finding.

6. §5 rank 2 and §10.7 — apply §8.3(c)'s own SE to the tirzepatide comparison. If ±2.2 bpm swallows the published 0.96–3.13 CI, say the check cannot discriminate and either drop it or print it as an interval that visibly contains the null.

7. §7 — say what the balance-web spoke renders. A bare 0–100 under the word 'Stress' with no unit, band or caveat is the surface that strips every mitigation the card body carries, and marking it 'unchanged' is the one place the naming argument is not made.

8. §11 slice 5 — reconsider substance shading on the arousal heat strip specifically. 9 days in 90, no dose on any of 18 events, three visible columns beside an arousal quantity is the per-day causal read §10.6 forbids.

### Verdict: **needs-rework**

**Fatal:**
- THE HEADLINE'S CLOSEST COMPETITOR IS A SECTION ON THE SAME CARD, AND §6 NEVER LOOKS THERE. `InsightDetailView.swift:496` renders `periodContrastCard(result)` as section 4 on EVERY card, immediately above the bespoke slot; `docs/card-sections.md:224` marks `Chg` as ● for Stress load. `PeriodContrast.windowDays = 28` (`PeriodContrast.swift:40`) and `PeriodContrast.changes` (`InsightDetailView.swift:3699-3702`) is called with `resolvedContributions(result).contributions` — i.e. THIS CARD'S OWN FOUR CHANNELS. So the Stress card already shows rMSSD, resting HR, respiratory rate and sleep duration each as the last 28 days against the prior 28, standardised by the prior period's own spread. The proposed headline is a weighted pooling (1.0/0.9/0.6/0.5) of the SAME recent 28 days against a 90-day reference that overlaps the prior-28 reference by 28 of its 90 days. §6 spends its entire length defending the headline's window against Readiness (today vs baseline), the radar (3v21) and Work impact (56d) and never notices that the card renders an unpooled version of its own statistic one section above the bespoke slot. The independence argument in §6 — 'the window is the only thing distinguishing it' — is refuted by the card's own layout, not by another card.
- `stress.arousalHours` IS `EnergyModel.exertionHours` WITH DIFFERENT PARAMETERS, AND §6'S DIFFERENTIATION TABLE MISDESCRIBES THE INCUMBENT. `Energy.swift:317-328`: `exertionHours` takes `samples.samples(of: .heartRate)`, filters to `value >= restingBaseline + exertionThresholdBpm` (`:150`, 15.0 bpm) and scales by elapsed time. It reads NO step count and NO active energy. The design's table row 'Movement | counted **in** — it is the point' is therefore false about the incumbent: Energy does not measure movement in that statistic at all, it measures heart-rate elevation above a personal resting baseline over a within-day window — the identical construct, from the identical sample stream, in the identical unit (hours). Energy's own doc comment at `:311-316` states its purpose as 'the strain that never became a workout — a bad commute, a stressful hour', which is verbatim the arousal figure's stated job. What §3.3 actually proposes is five parameter changes to that estimator: a wake gate, a stillness gate, a 180-min post-exertion gate, an hour-of-day median instead of one daily resting figure, and z > 1 instead of +15 bpm. Four of the five are unambiguous IMPROVEMENTS to a statistic whose own source calls itself 'Crude, and honest about it' (`:325-327`). Shipping them as a second figure on a second card, while `Energy.swift:317` keeps computing the bad version and the Energy card keeps drawing its own within-day curve (`Energy.swift:331` `curve`, bespoke section per `card-sections.md`), gives the reader two within-day heart-rate-elevation numbers, from one sensor stream, disagreeing on two cards.
- SLICE 3 — THE GATE THE WHOLE DAYTIME HALF HANGS ON — CANNOT DECIDE ANYTHING AT THE n IT WILL RUN ON, AND IS THE WRONG TEST. §9 derives a detectable ρ for every Oura comparison (0.31 at n=77, 0.40 at n≤47) and then §11 slice 3 sets |ρ| ≥ 0.6 against `EnergyModel.exertionHours` with no power arithmetic at all. Fisher-z SE is 1/√(n−3): at the doc's own stop-and-ask floor of ~30 gated days that is 0.192, so an observed ρ = 0.60 carries a 95 % CI of roughly [0.31, 0.79] and an observed ρ = 0.45 — a comfortable pass — spans roughly [0.11, 0.70]. The gate cannot separate 'independent construct' from 'same construct' anywhere near its own threshold. Worse, ρ is structurally depressed by the very gates whose validity it is meant to test: the stillness and 180-min post-exertion gates delete exactly the bins where the two statistics agree most (high-HR post-exertion time is what `exertionHours` is mostly counting), so a low ρ is evidence the gate fired, NOT evidence a new question is being answered. As specified, slice 3 will pass on a figure that is a re-render, and the doc will read the pass as vindication.

**Serious:**
- §6's 'Metric sets, from the code' table repeats the exact omission it congratulates itself for catching. It adds Work impact as 'the fourth reader the 2026-08-06 doc omits' and then misses at least two more. `MentalHealthModel` (`MentalHealthModel.swift:58-60, 118-131`) scores 14 days against 120 with `heartRateVariabilityRMSSD` at weight 0.6 — a fifth card asking 'has the last fortnight been worse than usual' off the channel Stress load weights 1.0, on a window that sits BETWEEN the radar's 3v21 and this card's 28v90 and brackets both. `EnergyModel.evaluate` (`Energy.swift:161-176`) is a sixth: `morningCharge` is built from `sleepDurationHours` + HRV z + `restingHeartRate` — three of Stress load's four channels, off the same nightly record. The honest count of scoring cards reading the nightly rMSSD/rHR/sleep triad is six, not four, and the 'window is the only distinguisher' defence must now distinguish 28-v-90 from 14-v-120, 28-v-28 and 'today vs baseline' in one app.
- The one genuinely unique thing on the card (§4) is demoted to near-nothing by §4.2 and §4.4 in the same document. 59,069 of 73,654 heart-rate rows are Oura's own sensor relayed via Apple Health, so the comparison is one photoplethysmogram processed two ways; §4.4 then forbids any accuracy claim in either direction because there is no gold standard on either side; the shared-day denominator is 'at most 47' and unmeasured below that; and the carrier stratification that would rescue it is gated at 20 watch-carried days which are also unmeasured. What survives is a scatter with a Spearman ρ and three box plots with a τ-b, on ≤47 days, that may not be interpreted in either direction. Meanwhile the RELAY — the part the vascularAge rule actually permits — already ships: `RawFieldGrouping.swift:168` files these fields under 'Stress & resilience (Oura)' in the Data tab (the doc says so itself, ✅ D28). The reader can already see Oura's numbers. The card adds the agreement statistic, and that is one section's worth of new material.
- Slice 7's 'attribution' is Work impact's premise, restated with the confound protection removed. `WorkImpactModel` (`CalendarInsights.swift:44-59`) already joins the calendar to `restingHeartRate`, `heartRateVariabilityRMSSD` and `sleepDurationHours` over 56 days, and its header (`:12-21`) names the reason it compares working days with working days ONLY: 'a card built that way would report that meetings wreck your recovery when what it actually found is that Saturday exists.' The proposed named-disagreement list has no such rule — the busy named days will skew weekday and the quiet ones weekend, which is precisely the artefact the incumbent throws away data to avoid. The claim in §5 that 'the calendar carries the advantage' over Oura is true and it is already shipped on a different card.
- S5's own rule convicts the card. 'One signal into three cards is how three cards start saying the same thing' is invoked to keep the NEW signal out of the OLD cards, and never once applied in the other direction to the old signal being given a sixth rendering. The rule is not about direction of travel.
- The naming argument (§7) is the strongest thing in the document and it argues for a section, not for new arithmetic. The reader's complaint was findability — they asked for 'stress' three more times because the card was called 'Stress load'. Slice 4 (rename + the Data-tab search test) fixes that completely and costs nothing. Slices 2, 3, 5 and 8 fix nothing the reader complained about.
- Substance shading is proposed on both new charts (slice 5) as 'the primary confound made visible', off 18 events on 9 distinct days with `units` and `note` nil on all 18 — while a Substance Impact card with a bespoke 'Cardiovascular load' section already exists (`card-sections.md:214`). §5 row 6 and §10 rule 6 already demote substances to shading-and-a-caveat; shading a chart with a confound that has 9 days in 90 and no dose is decoration on this card too.

**Required changes:** Three edits, in order of what they save.

1. MOVE THE DAYTIME ALGORITHM INTO `Energy.swift`, DO NOT MINT A SECOND FIGURE. §3.3's gating is a real improvement to `EnergyModel.exertionHours` (`Energy.swift:317`), which today counts any heart-rate sample above `restingBaseline + 15` with no wake gate, no stillness gate, no post-exertion shadow and no hour-of-day baseline, and weights by sample count in a stream that samples irregularly. Reimplement `exertionHours` with the wake/stillness/post-exertion gates and the hour-of-day z, or add `arousalHours` as a sibling output OF ENERGY with `exertionHours` as its acknowledged parent. Either way one card owns within-day heart-rate elevation. If the figure must be visible on Stress, relay Energy's series rather than recomputing it — but note §3.4's own warning that `derivedInputs` is declared by no model and the dependency graph has zero edges, which is itself an argument for computing it once where it already lives.

2. REPLACE THE ρ GATE WITH AN INCREMENTAL-VALIDITY TEST, AND STATE ITS POWER. Correlation against `exertionHours` is confounded by the gates it is testing. The right question is whether `arousalHours` separates the busy-vs-quiet working-day split of §8.4 AFTER `exertionHours` is entered as a covariate — i.e. does it add anything the incumbent does not already carry. Derive the detectable effect the same way §9 derives detectable ρ, and state up front that at 24 busy vs 26 quiet days the floor is d ≈ 0.79 against a pooled body difference already measured at +0.445 SD, so the honest expectation is that it will not clear. If it will not clear, do not build slices 2, 3, 5 and 8.

3. REWRITE §6 AGAINST THE ACTUAL CARD, NOT AGAINST THREE OTHERS. Add `periodContrastCard` (`InsightDetailView.swift:496`, `PeriodContrast.windowDays = 28`) to the overlap table — it is section 4 of this card and it renders the headline's own channels over the headline's own recent 28 days. Add `MentalHealthModel` (14 v 120, rMSSD 0.6) and `EnergyModel.morningCharge` (sleep + HRV z + resting HR). Then answer the question the table now asks: what does the pooled 28-v-90 score tell the reader that the four unpooled 28-v-28 deltas sitting directly beneath it do not. If the answer is 'it pools them', say so and consider making the pooled figure the drivers section's summary line rather than a headline.

What should actually ship, on this evidence: slice 1 (`VendorOpinion` reader — the architectural gap is real and no model can read a `RawMetricSample` today), slice 4 (the rename and the Data-tab search test — this is the reader's actual complaint), and slice 6 reduced to ONE section under Stress load's second bespoke slot: Oura's relayed numbers beside ours, weight 0, with both denominators and the 'same sensor, two formulas' heading as the default rather than the fallback. That is a genuinely new window — nothing else in the app grades a vendor's opinion against ours. Everything else in the design is a sixth rendering of the nightly triad and a second rendering of Energy's within-day heart-rate elevation.
