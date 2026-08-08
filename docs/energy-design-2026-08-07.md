> # ⚠️ NOT BUILD-READY — three hostile reviewers returned `needs-rework`

<!-- status: superseded — v1 — three hostile reviewers returned `needs-rework` (including a fabricated statistic). **Do not build from this.** Replaced by energy-design-v2-2026-08-08 -->
>
> **Do not implement §1–§5 as written.** The adversarial pass found, among others:
> a **fabricated statistic** in §0/§4.1 (the SD and variance labels are swapped, so
> the headline "85% of the variance" does not exist anywhere in the budget); a
> ribbon drawn as if every error term were independent when `σ_person` is a
> between-subject *intercept* that cancels in any within-day comparison; **every
> substance episode threshold understated ~2×** because a paired `d` is divided by
> the per-night SD rather than the SD of the difference, with the pairing rule never
> stated; no multiple-comparison policy across ≥20 tests; a design whose weight-bearing
> inputs are sleep timing alone, so **the number stops being a health signal and
> becomes a clock**; two of its four bands unreachable under its own parameters; and
> §3 rebuilding the shipped `SubstanceImpactInsight` without mentioning it.
>
> **What survives, and it is the valuable half: the diagnosis in §0.** The shipped
> card is not miscalibrated — it has no calibration. Five constants set its entire
> dynamic range and none appears in any literature. That finding is checkable and is
> the answer to *"the card doesn't seem accurate"*. The replacement is not.
>
> Full verdicts at the foot of this file. Backlog `B19`.

# Energy, rebuilt — the design (backlog B19)

_Written 2026-08-07. **Designed, not built.** This is the architecture of record
for the reader's re-scope of B19._

> *"I Just want more data sources to go into it, plus go and research the best
> way to calculate this. I want to use every possible data source that we have
> in our app, that is applicable to energy. Like.. every substances.. they can
> help with energy.. they should go into this, but short-lived, we just need to
> learn how substances do or do not impact me (by substance type)."*

Three asks: **every applicable source**, **a researched calculation**, and
**per-substance short-lived effects learned from the reader's own record**. All
three are answered below, and two of them are answered in a way the reader may
not expect. The document says why.

⚠️ **Coverage counts here were measured** from
`~/HealthSeed/exports/health-insights-export-new.json`, `generatedAt`
2026-08-07T07:09:11Z; "the last 90 days" means the 90 local days before that
timestamp, Australia/Sydney. **Counts and code constants only — no reading from
this reader's body appears in this file**, per `docs/privacy-and-ip.md`. Where a
derived figure of theirs matters (learned sleep need, bedtime spread, sleep
debt) the document states its *shape* against a published range and not its
value, deliberately.

---

## 0. The headline, before any of the detail

**The shipped card is not miscalibrated. It has no calibration.** Five constants
in `Energy.swift` set its entire dynamic range and none of them appears in any
literature:

| Constant | `Energy.swift` | What it decides | Published basis |
| --- | --- | --- | --- |
| `fullChargeSleepHours = 8.0` | :133 | 4 h vs 8 h moves the morning charge **37.5 points** | none — and the Sleep card already learned a personal need |
| `minimumMorningCharge = 25.0` | :136 | the floor | none |
| `recoveryPointsPerSD = 8.0` | :140 | ±2 SD of overnight HRV moves **16 points** | none |
| `fullDrainActiveKilocalories = 1_100.0` | :144 | 550 kcal drains **50 points** | none — no kcal→alertness conversion has ever been published |
| `fullDrainExertionHours = 8.0` | :147 | 4 h above resting drains **50 points** | none |
| `trickleRechargePerHour = 2.5` | :153 | a quiet 8 h returns **20 points** | none |

Two of those are checkable against evidence that does exist, and both come out
badly:

- **Sleep duration is roughly four times too strong.** The only within-person
  effect size in this evidence pass is Kuula/Bauducco 2025 (n = 205, 28
  consecutive days, 4,868 actigraphy nights): afternoon KSS β = −0.19 per hour
  of total sleep time. Four fewer hours is 0.76 KSS. On the card's own 0–100
  scale that is **9.5 points**. The card moves **37.5**. (Adolescent sample —
  indicative, not a calibration. It is still the only within-person number
  available, and it is four times smaller than the shipped coefficient.)
- **HRV moves the card 16 points on an association nobody has found.** The best
  within-person study of wearable HRV against subjective *vigor* specifically
  (Smyth/van Berkel 2023, n = 8 police officers, 15–55 weeks each, 125–386
  paired observations per person) found HRV predicted vigor in **0 of 8**
  participants. Small study; state it as suggestive. It is nonetheless the
  wrong direction of evidence for a term worth a sixth of the scale.

And the third finding is the one that reframes the whole card:

> **The honest resolution of a published alertness curve on this app's 0–100
> scale is about ±21 points (1 SD). The entire diurnal swing on a well-slept day
> is about 26 points.** More data sources do not narrow that. They cannot: 85%
> of the variance in the error budget is the model's own residual (§4).

So the answer to *"the card doesn't seem accurate"* is **not** a better blend of
more signals. It is: replace the invented arithmetic with a published one, print
the error bar it comes with, and put every other source on the card as **context
that explains why today might differ from the model** — never as another term in
one number.

**One-line recommendation:** the card's number becomes the **Three-Process Model
of alertness** (Ingre et al. 2014 refit), mapped from KSS onto 0–100, drawn as a
**ribbon not a line**; a **measured exertion layer** in its own units sits
beneath it and is never summed into it; a **per-substance published prior with
explicit decay** sits beneath that, with the reader's own episodes plotted
against it and an episode counter saying exactly how far short their record is;
and Oura's stress, resilience and readiness are **relayed, never blended**.

---

## 1. The model

### 1.1 Which framework, and why this one

**The Three-Process Model of alertness (Åkerstedt & Folkard), with the field
refit of Ingre M, Van Leeuwen W, Klemets T, Ullvetter C, Hough S, Kecklund G,
Karlsson D, Åkerstedt T, "Validating and Extending the Three Process Model of
Alertness in Airline Operations", PLOS ONE 2014;9(10):e108679 (open access).**

n = 136 aircrew, 5,744 KSS ratings from 964 sleep logs / 5,443 sleeps.

It is the only candidate that satisfies all four things this app needs at once:

1. **Every parameter is published**, so nothing has to be invented.
2. **Its only required input is sleep/wake timing**, which HealthKit supplies —
   `sleepDurationHours` (68 of the last 90 days) and `sleepOnset` (64 of 90).
3. **Its output is on a named scale** (Karolinska Sleepiness Scale, 1–9), so
   the 0–100 dial becomes a stated transform rather than a unit of its own.
4. **Its error is derivable, not borrowed** — residual SD 1.42 KSS units and
   between-subject intercept SD 0.84 KSS units, both from the field fit.

The rejected alternatives, each for a stated reason:

| Candidate | Why not |
| --- | --- |
| **SAFTE/FAST** (Hursh 2004, ASEM 75(3 Suppl):A44–A53) — the 2,880-minute reservoir | The structure is published (4 days × 24 h × 60 min × 0.5), the **fitted constants are proprietary**, and its individual-level accuracy is not established. We keep the reservoir **metaphor** for the fill; we do not claim its arithmetic. |
| **UMP / 2B-Alert** (Ramakrishnan 2016 SLEEP 39(10):1827–41; Reifman 2019 JSR 28(2):e12725) | The only published route to a *personalised* curve, and the only model family covering caffeine. Its personalisation costs **12 PVT measurements** from the user. Kept as slice S11, not as the backbone. |
| **Any vendor composite** — Garmin Body Battery, Oura Readiness, WHOOP Recovery, Fitbit Daily Readiness, Samsung Energy Score | Doherty C, Baldwin M, Lambe R, Burke D, Altini M, *Translational Exercise Biomedicine* 2025;2(2):128–144: 14 composite scores across 10 manufacturers, **none disclosed a formula**, none has independent peer-reviewed validation as a composite. This is the `vascularAge` rule with a citation attached. |
| **An HRV-driven score** | Smyth 2023 (above): vigor predicted in 0 of 8. Plews 2012/2014: day-to-day lnRMSSD CV 3–13%, so a single day is uninterpretable. HRV is relayed as a 7-day rolling mean, not a curve driver. |

### 1.2 The parameters, as published

From Ingre 2014 unless stated. **All values below are transcribed from this
project's evidence brief and must be re-read from the open-access paper before a
line of code is written — see §1.3, which flags one that cannot be right as
transcribed.**

| Process | Parameter | Value |
| --- | --- | --- |
| **S** — homeostatic | upper asymptote `ha` | 14.3 |
| | lower asymptote `la` | 2.4 |
| | wake decay rate `d` | −0.0353 / h (time constant 28.3 h) |
| **C** — circadian | amplitude `Ca` | 2.5 |
| | acrophase `p` | 16.8 h (data-optimised ≈ 15.0 h; per-chronotype 14.61–16.62 h) |
| | mesor | 0 |
| **U** — 12 h harmonic | `Ua` / `Um` | 0.5 / −0.5 |
| **W** — sleep inertia | `Wc` / `Wd` | −5.72 / −1.51 per h |
| **transfer** | KSS = `a` + `b`·alertness | a = 9.68, b = −0.46 (originals 10.6 / −0.6) |
| **fit** | residual SD | **1.42 KSS units** |
| | between-subject intercept SD | **0.84 KSS units** |

Supporting validation, used to justify the S+C backbone and **not** quotable as
this app's accuracy: Åkerstedt T, Folkard S, "Validation of the S and C
Components of the Three-Process Model of Alertness Regulation", *SLEEP*
1995;18(1):1–6 — EEG alpha power density and subjective alertness predicted with
r² > 0.70, against **group-mean** measures in constrained conditions. The
accessible abstract does not state n per group; do not quote the r² on the card.

### 1.3 ⚠️ One transcription that cannot be right, and must be resolved first

The brief renders Process S during wake as
`S(t) = ha − (ha − sw)·e^(d·t)` with `d = −0.0353`. With `d` negative,
`e^(d·t) → 0` and `S → ha = 14.3` — S **rises** through the waking day toward
the *upper* asymptote. That is the sleep-recovery form, not the wake form.

**Do not implement from this document's transcription.** Ingre 2014 is open
access. Open it, copy both equations, and confirm which asymptote each approaches
and what the sleep-recovery rate is (the recovery rate is **not** in this
evidence pass and must not be guessed — every worked number in §1.5 and §4
below is conditional on it).

The parts that are certainly right, and are enough to write the unit tests:

- S is a monotone exponential bounded between 2.4 and 14.3.
- The wake rate is 0.0353/h, i.e. a 28.3 h time constant, so over a 16 h waking
  day S falls about `1 − e^(−0.565) = 43%` of the way from its start to the
  lower asymptote. **That is a test assertion.**
- C peaks at the acrophase; alertness peaks in the late afternoon.
- KSS falls as alertness rises (`b` is negative).

### 1.4 Where this app departs from the published model, and why each

**Departure 1 — Process W (sleep inertia) is not drawn as a value.**

Ingre 2014's own finding: a deviation consistent with sleep inertia was visible
in the first hour awake, but adding Process W with the published parameters
"provided a much worse fit", which the authors attribute to the defaults being
exaggerated. **No attenuated amplitude has been published.**

The *shape* is unusually well established — Jewett ME, Wyatt JK, Ritz-De Cecco
A, Khalsa SB, Dijk DJ, Czeisler CA, *J Sleep Res* 1999;8(1):1–8 measured a
saturating-exponential time constant of **0.67 h** for subjective alertness
(1.17 h for cognitive throughput, 2–4 h to asymptote), and the three-process
model's own `Wd = −1.51/h` inverts to **0.66 h**. Two independent literatures
agreeing to two decimal places is worth stating in the card's methodology.

So: shape known, magnitude unsourced, and the full-amplitude version is large
(`Wc = −5.72` alertness units × 0.46 = 2.63 KSS = 33 points) — visibly wrong
every single morning.

**Decision:** the first 90 minutes after wake are drawn as a **hatched region
with no stated value**, captioned "waking up — the shape of this is published,
the size is not". Not a guessed dip, not a silent omission. Amplitude becomes a
per-person fit only if slice S11 lands (§7). Hatch, not a translucent fill, per
the repo's hatch-never-blend rule — load `add-chart` before drawing it.

**Departure 2 — Process U is implemented, unit-tested, and off by default.**

`Ua = 0.5` with mesor −0.5 is ~1.0 alertness unit peak-to-trough ≈ **0.46 KSS**
— about one third of the model's own 1.42 KSS residual SD. Adding U to S+C
improved fit (deviance χ² = 32, df ≈ 2, p = 0.001), **but once circadian phase
was set by chronotype the simpler S+C model fitted better**, leading the authors
to question U's validity.

We intend to set phase per person (Departure 3). That is precisely the condition
under which U became unnecessary. So U ships behind `processU: false`, with the
switch and the tests in place should a later per-person fit want it.

Mechanism, for the methodology text only: Monk TH, *Clinics in Sports Medicine*
2005;24(2):e15–e23 and Monk TH et al., *Chronobiology International* 1996 (PMID
8877121) — the dip occurs with no lunch eaten and with no knowledge of clock
time, and people who show it have a higher-amplitude, later-peaking 12 h
harmonic in their rectal temperature rhythm. **There is no published population
magnitude in KSS or PVT units under free-living conditions.** The card may never
tell this reader they dip at 3 pm.

**Departure 3 — the acrophase is estimated from the reader's own sleep timing,
not defaulted to 16.8 h.**

Huang Y, Mayer C, Cheng P, Siddula A, Burgess HJ, Drake C, Goldstein C, Walch O,
Forger DB, *SLEEP* 2021;44(10):zsab126 — DLMO mean absolute error by model in
day workers (n = 10): **0.61 h** (higher-order Kronauer, activity input), 0.71 h
(nonphotic), 1.00 h, 1.22 h (Hannay); light input was *worse* (0.83–1.49 h).
Apple Watch cohort (n = 20; 5 train / 15 test): **MAE 0.964 h, 73% within 1 h**.
Shift workers (n = 27): 2.51–2.79 h from activity, 3.60–3.81 h from light, only
44–56% within 2 h.

Independent confirmation in disrupted sleepers: Stone JE, Postnova S, Sletten TL,
Rajaratnam SMW, Phillips AJK, *SLEEP* 2021;44(2):zsaa180 — n = 45 fixed
night-shift workers, 17.0 ± 10.3 days of actigraphy before in-lab DLMO, absolute
mean error **2.88 h**, 76% within 2 h, 91% within 4 h, Lin's concordance 0.70,
**about twice the concordance of using average sleep timing as a DLMO proxy**.

We are not implementing Kronauer. We anchor the acrophase on the reader's own
sleep midpoint, which is the shortcut Stone measured as roughly half as good as
a model — **so we widen the phase error accordingly** rather than pretending to
model-grade phase:

| Reader's bedtime regularity (`sleep.bedtimeSpread`) | Phase error used | Source |
| --- | --- | --- |
| ≤ 1.0 h | **±1.0 h** | Huang 2021 Apple Watch cohort MAE 0.964 h |
| 1.0 – 2.0 h | ±1.0 h, and the card says the estimate is provisional | — |
| > 2.0 h, or a detected schedule shift | **±2.9 h** | Stone 2021 absolute mean error 2.88 h |

⚠️ **The two thresholds (1.0 h, 2.0 h) are a guess with no published basis.**
They are stated as a guess on the card. What makes the guess tolerable is that
it only *selects between two cited numbers* — it never invents one. This
reader's bedtime spread sits inside the regular band.

**Departure 4 — no evening wake-maintenance zone is drawn.**

Bes F / Sagaspe et al., *Scientific Reports* 2018;8:11012 (PMC6054682), n = 12
males, constant routine, DLMO 21:17 ± 1:09. At WMZ1 (13.5 h awake) there was
**no significant PVT improvement and no significant KSS reduction** versus the
preceding hour; it only became measurable at 37.5 h awake (Cohen's d = −0.687).
A feature nobody could detect in rested subjects is not drawn.

**Departure 5 — sleep debt is computed and shown, and never enters the intraday
curve shape.**

Van Dongen HPA, "Comparison of mathematical model predictions to experimental
data of fatigue and performance", *ASEM* 2004;75(3 Suppl):A15–A36 — the Fatigue
and Performance Modeling Workshop, six modelling teams, five scenarios. Acute
extended wakefulness (88 h): relative RMSE 28.5–42.0% for KSS, 22.2–38.0% for
PVT lapses. **Chronic sleep restriction (14 days, sleep-inertia points
excluded): RRMSE 75.3 / 82.6 / 95.4 / 96.1 / 99.5 / 99.9%** — five of six models
within a few percent of a flat horizontal line. One model's raw correlation with
the PVT data across all points was r = 0.023. No model was best or worst.

That is the regime an ordinary user actually lives in, and it is the caveat the
card must carry. It also forbids folding a debt trend into the curve's shape.

**Departure 6 — sleep stages never enter the arithmetic.**

"Performance of consumer wrist-worn sleep tracking devices compared to
polysomnography: a meta-analysis", *JCSM* 2025 (PMID 39484805, doi
10.5664/jcsm.11460): 24 studies, 798 patients. Total sleep time mean difference
**−16.85 min (95% CI −26.33 to −7.38)**, sleep efficiency −4.7%, latency +2.6
min; sleep-vs-wake sensitivity frequently > 90%, but **four-stage classification
accuracy only 60–75%**. Deep and REM minutes are present in this app (68 of 90
days each) and are refused as inputs. 60–75% is not a foundation for arithmetic.

The TST bias *is* propagated — into the error term, where it turns out to be
negligible (§4). Saying so is the point: the curve's uncertainty is dominated by
the model, not the sensor.

**Departure 7 — the card's feedback never tunes the curve.**

Van Dongen HPA, Maislin G, Mullington JM, Dinges DF, *SLEEP* 2003;26(2):117–126,
n = 48: the Stanford Sleepiness Scale showed an acute response to restriction and
then only small further increases, and **did not significantly differentiate the
6 h from the 4 h condition**, while PVT lapses in those conditions diverged
significantly (condition × rate-of-change F₂,₃₀ = 3.67, p = 0.037). Subjects were
"largely unaware" of the growing deficit.

So a curve tuned to agree with how the reader says they feel would systematically
under-weight exactly the condition it most needs to catch. **Section 12 ("Was
this accurate?") is recorded and never fed back into S.** If feedback is ever
used at all it may only fit the inertia amplitude and the phase — the two
parameters this design leaves genuinely open — and never the homeostatic term.

`Feedback.swift:170` returns `energy-v1`. This is a different quantity and must
ship as **`energy-v2`** (the `fitness-v2` / `work-impact-v2` precedent), or every
score recorded before today becomes silently non-comparable with every one after.

### 1.5 The transform, and the number the card shows

```
alertness(t) = S(t) + C(t) [+ U(t), off by default]
KSS(t)       = 9.68 − 0.46 · alertness(t)
level(t)     = 100 · (9 − KSS(t)) / 8            // KSS 1 → 100, KSS 9 → 0
```

**12.5 points of the 0–100 scale per KSS unit.** That single line is what makes
every error figure below convertible, and it is what the card's methodology
section leads with.

Worked example, from the transcribed parameters, **to be regenerated once §1.3
is resolved** — a 07:00 wake after a full night, acrophase 16.8 h, no inertia,
U off:

| Time | S | C | alertness | KSS | level |
| --- | --- | --- | --- | --- | --- |
| 07:00 | 14.30 | −2.10 | 12.20 | 4.07 | **62** |
| 16:00 | 11.06 | +2.45 | 13.51 | 3.47 | **69** |
| 23:00 | 9.17 | −0.13 | 9.03 | 5.52 | **43** |

**The whole diurnal swing on a well-slept day is about 26 points.** Hold that
against the ±21-point 1-SD ribbon derived in §4. That relationship — swing barely
larger than uncertainty — is the single most important thing this card has to
communicate, and it is why the redesign leads with a band word and a ± rather
than with two digits.

### 1.6 What stays from the shipped model

- **The reservoir fill.** `EnergyCurveChart`'s area is the right encoding — the
  quantity genuinely is "how much is left" — and its dashed morning-charge rule
  is the right convention. The fill's *height* changes meaning; the drawing does
  not. (Load `add-chart` before touching it.)
- **The four bands.** High / Steady / Running low / Drained are 25 points wide,
  i.e. **1.2 standard deviations each**. The band word is roughly at the model's
  own resolution; the two digits beside it are not. That is an argument for
  keeping the bands and demoting the digits, not for removing either.
- **`restingHeartRate` is the line, not a term** (`Energy.swift:85-88`). Unchanged
  and for the same reason.
- **`Output.terms` as the source of weights.** The pattern — the model computes
  its own decomposition beside the number it explains, and the card never
  re-derives it — survives intact. Only the terms change.

---

## 2. Every input, its weight, and where the weight comes from

### 2.1 The rule this table implements

Standing rule 4: *everything a card charts carries a weight, or says why it
cannot.* This table is the "or says why it cannot" for most of the app, and that
is the honest answer rather than an evasion. **No published model converts
kilocalories, steps, gait speed, meeting hours or HRV into alertness units.**
Inventing an exchange rate is exactly what the shipped card does and exactly
what makes it inaccurate.

**The weights that are not zero come from the model's own decomposition**, not
from constants: at each instant, `|S(t)|` and `|C(t)|` over their total, exactly
the way `Output.terms` works today. They therefore **move through the day** —
early morning is C-dominated, late evening is S-dominated — which is truthful
and which a constant never could be.

### 2.2 Inputs that carry weight

| Input | `MetricType` / where | Coverage, last 90 d | Role | Weight | Source of the weight |
| --- | --- | --- | --- | --- | --- |
| Sleep duration | `.sleepDurationHours`, `MetricType.swift:133` | **68 / 90** | Process S recovery | `\|S(t)\| / (\|S(t)\|+\|C(t)\|)` | the model's own decomposition (Ingre 2014) |
| Sleep onset / wake time | `.sleepOnset`, `:148`; `SleepOnset.night(of:)` | **64 / 90** | anchors t-since-wake **and** the acrophase | shared with S; the phase half is `\|C(t)\|`-weighted | same |
| **Learned sleep need** | derived `sleep.learnedSleepNeed`, `SleepInsight.swift:497` | 1 stored point, recomputable to 90 | replaces `fullChargeSleepHours = 8.0`, and sets ξ for the debt term | **0 — it is a parameter, not a term** | Van Dongen 2003: implied need 24 − ξ = **8.16 ± 0.73 h**. This reader's learned need sits inside that interval. *(Value withheld per `privacy-and-ip.md` — the shape is the finding: the app's own learner and a 48-subject dose-response study agree.)* |

That is the whole weight-bearing list. **Two metrics and one parameter.**

### 2.3 Inputs shown on the card at weight 0, each with its stated reason

| Input | Coverage, last 90 d | Where it appears | Why weight 0 |
| --- | --- | --- | --- |
| Sleep efficiency `.sleepEfficiency` | 68 / 90 | quality flag beside the sleep row | feeds the error term only; no published efficiency→KSS curve |
| Deep / REM minutes | 68 / 90 each | **not shown as inputs at all** | JCSM 2025: 60–75% four-stage accuracy. Named refusal, §1.4 Departure 6 |
| Oura `awake_time` / `restless_periods` / `light_sleep_duration` | 72 / 90 | fragmentation strip under the night | no published fragmentation→alertness curve. Currently read by **nothing** |
| HRV rMSSD `.heartRateVariabilityRMSSD` | 67 / 90 | **7-day rolling mean with a normal band**, its own row | Smyth 2023: vigor predicted in 0 of 8. Plews 2012/2014: day-to-day lnRMSSD CV **3–13%**; ~3 randomly-chosen days reproduce the 7-day average in trained athletes, ~5 in recreational ones. A daily value with a verdict is not defensible; the 3–13% CV is also the derived error bar on any HRV quantity |
| HRV SDNN | 65 / 90 (39 with any 09:00–21:00 reading) | fallback for the same row | same, plus: it is a *sometimes* channel, median 5 daytime quarter-hour bins on the days it exists |
| Resting heart rate `.restingHeartRate` | 70 / 90 | the exertion threshold; the GLP-1 epoch comparison | it is the **line** exertion is counted above, not a term — the shipped rationale at `Energy.swift:85-88`, unchanged |
| Heart rate `.heartRate` | 80 / 90; **77 clear ≥24 quarter-hour bins; only 47 clear ≥24 bins inside 09:00–21:00** | the exertion layer | no published kcal- or bpm-to-alertness conversion exists. ⚠️ 59,069 of 73,654 rows are `apple_health/oura` — the intraday carrier is mostly Oura's own sensor relayed through Apple Health; the genuinely independent daytime HR is the watch's 14,543 rows |
| Active energy `.activeEnergyBurned` | 86 / 90 | the exertion layer, **in kcal** | as above. The shipped `fullDrainActiveKilocalories = 1_100.0` is the invented exchange rate this design deletes |
| Steps `.stepCount` | **90 / 90** | the exertion layer's coverage fallback **and the substance-layer confounder control** | it is a covariate, not a term. Its load-bearing job is §3: on this reader's own record, `heartRate`'s apparent stimulant effect fell from min\|z\| 0.91 to **0.03** once same-day steps entered the model |
| Oura `daily_activity.resting_time` / `.sedentary_time` | 80 / 90 | replaces the sample-count approximation in `exertionHours` (`Energy.swift:319-323`) | measured seconds/day, so it *improves* the exertion layer's honesty — but the exertion layer still has no conversion to alertness |
| Gait triple `.walkingSpeed` / `.walkingStepLength` / `.walkingDoubleSupport` | **90 / 90 each** — the densest series in the export | a within-day slowing strip beneath the curve | **no published within-day gait-slowing→alertness curve exists.** Stated as a gap on the card, not hidden. Phone-in-pocket, so these survive nights the ring charged — which is why they are worth drawing at weight 0 rather than omitting |
| `workImpact.workExposure` (derived) | 1 stored point, recomputable | annotation band on the curve | no published meeting-load→alertness conversion. Reaches Energy **without Energy touching EventKit**, which is the reason to prefer it over `CalendarModel` |
| Holiday ledger `HolidayLedger` | 15 periods, 12 leave days in the last 90 | context shading on the history axis | fully populated and read by **nothing** today (its own header says H6 is unwired) |
| `activeMedicationLevel` (GLP-1) | **90 / 90 — the densest reader-only covariate** | **epoch band, never a day term** | Schneck 2024 *CPT:PSP* 13(3): t½ ≈ 5 days on a 7-day interval ⇒ **no unexposed day exists**. Structurally unanswerable at day level, not pending. §3.6 |
| GLP-1 side effects `SideEffectRecord` | 14 entries, 13 of them in the six days to 2026-08-07 | marks on the day logged | Zepbound label: fatigue 3% placebo → 5 / 6 / 7% at 5 / 10 / 15 mg. **An incidence, not a magnitude** — it cannot become a daily delta |
| Substance episodes | **5 episodes** (4 stimulant, 1 cannabis) across 9 distinct days | §3 in full | below every episode threshold in §3.7 |
| Oura `daily_stress.stress_high` / `.recovery_high` | **89 / 90** — the densest unread signal in the export | **relayed as a labelled second opinion** | Doherty 2025: formula undisclosed, no validation. **The `vascularAge` rule, absolutely.** Units are **seconds**, and the definition is a **quartile rank against the wearer's own recent distribution** — self-normalising, so it cannot be compared between people and cannot trend over long windows |
| Oura `daily_stress.day_summary` | **73 / 90** (not 89 — 16 days in the window carry the seconds and no verdict) | relayed | as above; the card must print **both denominators** |
| Oura `daily_resilience.*` | 63 / 90 | relayed | a composite of composites — Sleep Score and HRV Balance are themselves undisclosed. Changes level ~2–3 times a month, so a daily redraw implies a resolution it does not have |
| Oura readiness / sleep scores | 55–72 / 90 | **not read** | the vendor-neutral principle. Restated here rather than re-decided |
| Respiratory rate, skin temperature deviation, SpO₂ | 68 / 64 / 63 of 90 | the "the model may be wrong today" flag, **relayed from the symptom radar** | Mishra 2020 *Nat Biomed Eng* 4:1208–20: 32 COVID cases from ~5,300; **63%** detectable pre-symptomatically from extreme resting-HR elevation vs a 28-day sliding personal baseline; 22 of 25 detected at or before symptom onset. Illness is a different axis on a different timescale — relay the radar's verdict, do not recompute it |
| Screen time `.screenTimeMinutes` | 25 / 90 | not on this card | no published curve, and a quarter of the window |
| Sound dose | 17 / 54 of 90 | not on this card | out of scope; watch-only and thin |

### 2.4 Inputs that were checked and are unusable

Per standing rule 8 — *before writing "already arriving", count its rows in the
last 90 days.* These were counted.

| Input | Coverage | Consequence |
| --- | --- | --- |
| **Dietary energy, protein, carbs, fat, sugar, fibre, sodium, potassium** | **0 of the last 90 days** — last written 2026-03-22 | An intake term is not buildable on this reader today. Do not design one |
| **Dietary caffeine** `.dietaryCaffeine` | **0 of the last 90 days**; 6 rows total, last 2026-04-23 | See §3.2 — this is the highest-value logging change available, and it should land in the **substance log** (which carries a timestamp) rather than the dietary metric (a daily total). Gardiner 2025 shows timing is what matters |
| `.dayStrain` | **0 rows, ever** | The obvious Body-Battery peer input does not exist here |
| `.heartRateRecovery` | 2 of 90 | Too thin |
| `.physicalEffort` | 46,729 rows but **16 of 90 days** — watch-only | The row count is a trap the case comment already warns about. Take the day count |
| Basal energy (raw) | 25 of 90, watch-only and gappy | Backlog already warns against presenting it as "your metabolism" |
| Calendar time-zone changes | fewer than 2 found; the Travel-drain card produced no series at all | A real absence of travel, not a missing integration |
| Calendar event counts | **unmeasurable from any export by design** (`HealthDataExport.swift:430`) | Use `workImpact.workExposure`, not raw events |

### 2.5 The two pieces of engine plumbing this needs

Neither is Energy-specific, and both unblock every card:

1. **`evaluate` has no `DerivedSeriesStore` parameter** in either overload.
   `derivedInputs` is declared on the protocol (`Insight.swift:497`) with a
   default of `[]` and **no model overrides it** — the graph has zero edges. Energy
   reading `sleep.learnedSleepNeed` or `workImpact.workExposure` needs a
   *signature change in the engine*, not merely a declaration. Slice **S4**.
2. **Side effects and the holiday ledger cannot reach InsightKit at all.**
   `SideEffectRecord` lives in the app target (`PersistenceModels.swift:547`);
   `HolidayLedger`'s own header says H6 is unwired. The substance log solved the
   same problem with construction state and `InsightEngine.withSubstanceLog(_:)`
   — **that is the precedent to copy**, and `EnergyInsight(events:)` uses it in
   slice S6.

⚠️ Every derived series in the export holds **exactly one stored point**.
`DerivedSeriesStore` has no persistence; history is rebuilt per launch by a lazy
`ScoreHistory` replay. So "derived history is 1 day as exported, and is
recomputable to 90 days by `DerivedBackfill.fill`" — anything this design draws
from derived series must survive that, or wait behind a `CoverageGate`.

---

## 3. The substance layer

This is the reader's actual ask and the hardest part. The design has to hold two
things at once: **their record cannot yet answer the question**, and **a
permanent null is the useless option, not the safe one** (standing rule 0).

The resolution: **apply the published time-course as a stated prior, draw the
reader's own episodes against it, and print exactly how many more episodes it
would take before their own data could agree or disagree with it.**

### 3.1 What the reader's record actually is

- **18 events total, all inside the last 90 days**, across **9 distinct days**:
  17 stimulant, 1 cannabis.
- Under the 24-hour gap rule (`SubstanceEpisodes.swift:27`) that is **5
  episodes**: 4 stimulant, 1 cannabis.
- **There is no dose.** `SubstanceEvent.units` and `.note` are optional
  (`Substance.swift:64-66`) and **nil for all 18**. The log is class plus
  timestamp.
- Zero caffeine, zero alcohol, zero nicotine events.
- Only stimulant clears `minimumEpisodesToDescribe = 3`, and
  `SubstanceEpisodes.swift:82-91` already records that at three episodes this
  reader's record supported **zero** confirmations once same-day movement and
  sleep were controlled for.

### 3.2 The per-substance prior: decay, window, direction, effect

Each `SubstanceClass` gets a `SubstancePrior` value: a decay time constant τ, an
attribution window, an expected direction, the published effect and its source —
**and `nil` where none exists, which is a finding the card prints rather than a
hole it fills.**

#### Caffeine — τ ≈ 5 h, window: the day of intake and that night. **No next-day window.**

- Half-life ≈ 5 h, individual range roughly **1.5–9.5 h**, CYP1A2 accounts for
  > 95% of clearance and varies up to ~40-fold between individuals (Nehlig A,
  *Pharmacol Rev* 2018;70(2):384–411; the brief flags the exact bounds as
  approximate — the primary was not opened). **This is the strongest argument in
  the whole evidence pass for an error bar rather than a point estimate.**
- Sleep, pooled: TST **−45 min**, sleep efficiency **−7%**, SOL +9 min, WASO +12
  min, N1 +6.1 min, N3+N4 −11.4 min (Gardiner C, Weakley J, Burke LM, Roach GD,
  Sargent C et al., *Sleep Med Rev* 2023;69:101764, 24 studies). Derived
  cut-offs: **107 mg → 8.8 h before bed; 217.5 mg → 13.2 h.**
- **Dose decides whether there is an effect at all**: Gardiner C et al., *SLEEP*
  2025;48(4):zsae230, n = 23 males, 7 conditions, in-home partial PSG — **100 mg
  had no significant effect on objective or subjective sleep at any timing**
  including 4 h pre-bed; 400 mg delayed initiation and altered architecture at
  ≤ 12 h, greater fragmentation at ≤ 8 h, perceived quality −34.02% at 4 h
  (p = .006). Drake C, Roehrs T, Shambroom J, Roth T, *JCSM* 2013;9(11):1195–1200,
  n = 12: 400 mg cut objective TST by **1.1–1.2 h at 0, 3 *and* 6 h before bed**.
- ⚠️ **The withdrawal confound, which is why a naive coffee-vs-no-coffee card
  would be wrong.** Juliano LM, Griffiths RR, *Psychopharmacology*
  2004;176(1):1–29 (57 experimental + 9 survey studies): onset 12–24 h, **peak
  20–51 h, duration 2–9 days**, with "highly convincing" empirical support for
  fatigue, decreased energy, decreased alertness and drowsiness. **A low-caffeine
  day in a habitual user is a withdrawal exposure, not a control.** The card must
  say this or the caffeine comparison must not exist.
- ⚠️ **No published effect of caffeine on next-day heart rate, HRV or resting
  physiology exists at all.** A card charting caffeine against next-day recovery
  would be modelling something nobody has measured — and would very likely pick
  up withdrawal.
- **Alertness effect**: only the UMP family covers caffeine (Ramakrishnan 2016 —
  442 subjects, 14 studies, 9 caffeine conditions, 100–600 mg). **Its
  coefficients are not in this evidence pass. Obtain them or do not model
  caffeine's alertness effect. Do not invent a term.**
- **This app holds no caffeine data of any kind.** The class exists; the log has
  zero events; dietary caffeine has zero of the last 90 days.

#### Alcohol — window: the drinking night and the following day. **Never longer.**

- Dose-response, same night, free-living, n = 4,098: HR **+1.4 / +4.0 / +8.7
  bpm** and RMSSD **−3.3% / −9.4% / −21.3%** at low (≤0.25 g/kg) / moderate
  (>0.25–0.75) / high (>0.75) doses, first 3 h of sleep (Pietilä J, Helander E,
  Korhonen I, Myllymäki T, Kujala UM, Lindholm H, *JMIR Ment Health*
  2018;5(1):e23).
- **The most transferable number available**, because it is within-person from
  the same class of device this app reads: Grosicki GJ, Robinson AT, Joyner MJ,
  Carter JR, von Hippel W, Presby DM et al., *PLOS Digit Health*
  2026;5(3):e0001284 — n = 20,968, **5,109,185 person-days**, WHOOP 4.0,
  within-person GAMs. One extra drink above a person's own average: nocturnal
  RHR **+2.8 bpm (F) / +2.4 bpm (M)**, HRV **−3.8 ms (F) / −3.3 ms (M)**; larger
  in women and under-30s; attenuated by earlier drinking and longer
  post-drinking sleep.
- **Point it at the right outcome.** Gardiner C, Weakley J et al., *Sleep Med
  Rev* 2025;80:102030, 27 studies: total sleep time effect **non-significant**
  (−10.1 min); REM delayed and reduced **from low dose upward**. Charting alcohol
  against TST will find nothing, correctly. Chart it against REM, HRV and night
  HR.
- The two halves of the night move in opposite directions — first half
  consolidated with increased SWS, second half fragmented (Ebrahim IO, Shapiro
  CM, Williams AJ, Fenwick PB, *Alcohol Clin Exp Res* 2013;37(4):539–549;
  qualitative review that drew a published methodological critique, so treat as
  directional). **A whole-night average under-detects.**
- Window: Strüven A et al., *Nutrients* 2025 (PMC12073130 / PMID 40362779), n =
  40, 3 alcohol-free / 3 exposure (40 g women, 60 g men) / 3 post-exposure days —
  nocturnal RHR 63.6 ± 9.2 → 66.6 ± 9.0 → 64.9 ± 9.3 bpm, "rapid normalization".
  Next-day: activity down and sedentary time up (Devenney LE, Coyle KB, Verster
  JC, *J Clin Med* 2019;8(5):752, n = 25, GENEactiv), corroborated at scale by
  Grosicki.
- ⚠️ **Named refusal: the "2–3 drinks suppress HRV for up to 5 days" claim has no
  peer-reviewed source.** Every instance traceable goes back to WHOOP and Oura
  blog content and vendor-analysed member data. The only controlled multi-day
  design found reported rapid normalisation. **If this app implemented a
  multi-day alcohol carry-over it would be encoding marketing copy as
  physiology.** State it as unknown.
- Zero events logged.

#### Nicotine — τ ≈ 2–3 h, window: **two nights, sign-aware.**

- Plasma t½ 2–3 h (Benowitz NL et al., "Nicotine Pharmacology", NCBI Bookshelf
  NBK222359); repeated intake accumulates within a day, overnight abstinence
  largely clears it. **So an afternoon exposure should not be attributed to that
  night; an evening one should. The card must read the time, not the date.**
- Acute alertness benefit is real and small: Heishman SJ, Kleykamp BA, Singleton
  EG, *Psychopharmacology* 2010;210(4):453–469, 41 double-blind
  placebo-controlled studies in non-deprived subjects — Hedges g **0.34** for
  alerting attention accuracy (9 studies, n = 207) and RT (13, n = 311), **0.44**
  for short-term episodic memory accuracy (8, n = 199), 0.16 fine motor;
  non-significant for orienting accuracy (0.13) and working-memory accuracy
  (−0.11). The design excluded deprived smokers, so this is **enhancement, not
  withdrawal relief** — which matters if use is regular.
- Chronic-smoker epidemiology, PSG, n = 6,400: SOL **+5.4 min** (95% CI 2.9–7.9),
  TST **−14.0 min** (95% CI 6.4–21.7) (Zhang L, Samet J, Caffo B, Punjabi NM,
  *Am J Epidemiol* 2006;164(6):529–537). **−14 min against a night-to-night TST
  SD of 77.41 min is undetectable in one person's data at any realistic episode
  count** — the strongest single argument for printing the error bar and
  declining the point estimate.
- Acute patch in non-smokers, n = 20: TST −33 min, efficiency 89.7 → 83.5%, REM
  18.8 → 15.1%, SOL 6.7 → 18.2 min — **and a REM rebound on the following
  night** (Davila DG, Hurt RD, Offord KP, Harris CD, Shepard JW, *Am J Respir
  Crit Care Med* 1994;150(2):469–474). **The only substance here with a night-2
  effect of the opposite sign. A window that does not handle the flip reports
  noise.** n = 20, patch, not the reader's route of use.
- ⚠️ Gap: **no modern study of e-cigarettes or nicotine pouches** against
  wearable-measured sleep or next-day physiology. The evidence is a 1994 patch
  study and 2006 cigarette epidemiology.
- Zero events logged.

#### Cannabis — window ≈ 5 h inhaled (almost all recovered by ~7 h). **Next-day: essentially nothing.**

- **The permitted claim is "no consistent published effect".** Velzeboer R et
  al., *Sleep Med Rev* 2025, doi 10.1016/j.smrv.2025.102164 — 18 studies
  identified, 9 meta-analysed: cannabis did **not** consistently alter duration,
  latency, wake time, efficiency or staging. The classic REM-suppression finding
  traces to small, high-dose, methodologically limited 1972–1982 trials.
- The one well-instrumented single-dose RCT: Suraev A et al., *J Sleep Res*
  2026;e70124 (PMC12856102), n = 20 DSM-5 insomnia, crossover, 10 mg THC + 200 mg
  CBD oral, 256-channel hd-EEG. TST −24.5 min (p = 0.05), REM **−33.9 min**
  (p < 0.001, d = −1.5), REM latency +65.6 min, WASO unchanged. **Next day
  (≥ 9 h post-dose): PVT reciprocal RT 3.6 vs 3.5 ms (p = 0.468), PVT lapses 2.0
  vs 2.0, MWT 31.2 vs 33.2 min, KSS +0.42 (p = 0.02, d = 0.22).** Nothing
  objective. Oral route, insomnia patients — does not generalise to inhaled
  recreational use.
- Acute recovery: McCartney D, Arkell TR, Irwin C, McGregor IS, *Neurosci
  Biobehav Rev* 2021;126:175–193 — 80 studies / 155 trials, 106 in quantitative
  synthesis: most driving-related cognitive skills recover within **~5 h** of
  inhaling 20 mg THC, almost all within **~7 h**; oral takes longer.
- **A "cannabis hurt your next day" card has no published basis.** Say so.
- 1 event, 1 episode.

#### Stimulant — same day, and the window depends on a formulation the log does not record

- Sleep: total-sleep-time standardised effect **−0.59**, longer onset latency
  (worse with more frequent daily doses), worse efficiency (Kidwell KM, Van Dyk
  TR, Lundahl A, Nelson TD, *Pediatrics* 2015;136(6):1144–1153; 9 articles, 246
  participants, randomised, objective measurement). ⚠️ **Youth ADHD cohort.**
  Applying its magnitude to an adult is an assumption the card **states**, not
  hides.
- Daytime: resting HR **+5.7 bpm**, systolic BP +2.0 mmHg, resting HR ≥ 90 bpm in
  4.2% vs 1.7% on placebo (Mick E, McManus DD, Goldberg RJ, *Eur
  Neuropsychopharmacol* 2013;23(6):534–541; PMID 22796229 — venue confirmed via
  PubMed, full text not opened). **The most detectable substance signature
  available in this reader's data.**
- Duration differs by an order of magnitude across formulations — methylphenidate
  IR t½ 2–3 h, action ~3–4 h; MPH ER (OROS) ~10–12 h; lisdexamfetamine parent
  t½ < 1 h with active d-amphetamine t½ **10.39 h**, tmax ~3.0 h, action 10–14 h
  (Kimko HC, Cross JT, Abernethy DR, *Clin Pharmacokinet* 1999;37(6):457–470;
  Krishnan S, Zhang Y, *Clin Drug Investig* 2008; Vyvanse US PI). **An 8 am
  lisdexamfetamine dose is substantially present at 9 pm; an 8 am MPH IR dose is
  long gone. One rule would be wrong for one of them.**
- ⚠️ **The log records neither formulation nor dose.** So for this reader's 17
  stimulant events the card must say **the attribution window is unknown**, and
  offer the input that would fix it (§7 slice S6a).
- ⚠️ Gap: **no wearable-measured nocturnal effect size for therapeutic stimulants
  in adults exists.** The card may state the daytime +5.7 bpm and the
  youth-derived sleep effect, and nothing else.

#### The remaining classes — `mdma`, `psychedelic`, `dissociative`, `depressant`, `other`

**No published time-course was found for these in this evidence pass.** Their
`SubstancePrior` is `nil`, the card says "no published time-course was found for
this class", and that is a finding rather than a hole. `SubstanceClass
.acuteCardiacLoad` (`Substance.swift:42`) must stay exactly what its own doc
comment already calls it — *"an ordering heuristic grounded in the general
pharmacology, not a dose-specific clinical figure"* — at weight 0. It orders a
load indicator; it is not an effect size and may never be drawn as one.

### 3.3 How the prior is drawn

Per class, an exponential kernel over the published window:

```
prior(t) = effect · exp(−t / τ),  t ∈ [0, window]
```

with τ from the published half-life (`τ = t½ / ln 2`), `effect` in **the affected
metric's own units or SDs — never in alertness points**, and the window from
§3.2. Nicotine is the exception: two segments, night 1 negative and night 2
positive (REM rebound), because a single-sign kernel would report the rebound as
noise.

`SubstanceLoad.swift` already has exactly this machinery — an exponential kernel
with a derived saturation constant, replacing a box-car — and its comment
explains why. Reuse the shape; do not re-derive it.

The prior is drawn as a **shaded band beneath the alertness curve**, on the
substance's own axis, hatched rather than blended where it overlaps anything
(the repo's hatch-never-blend rule). **It is never added to the alertness
number.**

### 3.4 The reader's own episodes against it

For each episode, plot the observed delta in the affected metric — but
**adjusted for same-day step count**, because that is what the independent review
established on this exact record: `heartRate`'s apparent stimulant effect fell
from min|z| **0.91 to 0.03** once same-day steps entered the model. The effect
was their own movement.

Each row also carries `SubstanceEpisodes.alternativeExplanation(for:)`, which is
already implemented and is the whole honesty mechanism.

### 3.5 The episode counter — the part that answers the reader directly

**Derivation, not a citation.** Paired comparison, 80% power, α = 0.05
two-sided: `n ≈ (z₀.₉₇₅ + z₀.₈₀)² / d² = 7.85 / d²`.

Within-person SDs:
- **TST intraindividual SD = 77.41 min** — Bei et al., "How much does sleep vary
  from night-to-night?" (PMID 35811092), 8 pooled datasets, 2,404 healthy
  sleepers.
- **RMSSD within-person CV = 0.37** (SD 0.16, range 0.14–0.71) — Hannon et al.,
  *Sensors* 2025, n = 41, 424 daily observations over 14 days.

**At n = 4 episodes, the smallest detectable effect is d = √(7.85/4) = 1.40** —
about **108 minutes of lost sleep** or a **52% RMSSD collapse**. The largest
single-night effects in the entire evidence pass are caffeine 400 mg at ~66–72
min (d ≈ 0.9) and high-dose alcohol RMSSD −21.3% (d ≈ 0.58). **Both are well
below the detection floor. A per-substance effect card at n = 4 cannot detect any
real effect documented here; it would report noise as a personal finding.**

| Substance | Outcome | Published effect | d | Episodes for 80% power | This reader has |
| --- | --- | --- | --- | --- | --- |
| Caffeine (400 mg, lab) | TST | −70 min | 0.90 | **~10** | 0 |
| Caffeine (meta) | TST | −45 min | 0.58 | **~23** | 0 |
| Stimulant | TST (standardised) | −0.59 | 0.59 | **~23** | **4** |
| Alcohol, high dose | RMSSD | −21.3% | 0.58 | **~24** | 0 |
| Nicotine (patch) | TST | −33 min | 0.43 | **~43** | 0 |
| Cannabis | TST | −24.5 min | 0.32 | **~77** | **1** |
| Alcohol, moderate | RMSSD | −9.4% | 0.25 | **~122** | 0 |
| Alcohol (meta) | TST | −10.1 min | 0.13 | **~470** | 0 |
| Alcohol, low dose | RMSSD | −3.3% | 0.09 | **~990** | 0 |

⚠️ **These are floors under favourable assumptions** — clean pairing, perfectly
logged exposure and dose, one pre-specified outcome, no confounding. Real logs
violate all four: drinking co-occurs with late nights and social stress, caffeine
dose is rarely recorded in mg, and testing several outcomes across several
substances multiplies false positives. No published correction factor exists for
this setting. **Treat them as optimistic by an unknown margin, and say so.**

⚠️ **The counts are bounded by exposure episodes, not by total nights.** A
thousand clean nights do not help.

⚠️ **No published within-person night-to-night SD for nocturnal resting heart
rate from a consumer wearable exists.** Every "5–10 bpm is normal" instance
traces to non-peer-reviewed sources. So the RHR threshold **must be derived from
this reader's own nightly RHR SD and inverted** — which is better than a
citation, and matches the repo's own derive-rather-than-cite rule. Build task in
slice S7.

### 3.6 GLP-1: refused at day level, on purpose

Tirzepatide is a substance the reader takes, it has the densest coverage in the
app (`activeMedicationLevel`, 90 of 90 days), and **a within-week "injection day
effect" card is unanswerable in principle** — not thin, unanswerable. t½ ≈ 5 days
on a 7-day interval means plasma level never returns to zero, so there is no
unexposed day to compare against (Schneck K et al., *CPT Pharmacometrics Syst
Pharmacol* 2024;13(3); tmax 8–72 h, steady state ~4 weeks, steady-state trough
~2.1× the post-first-dose level).

**The correct unit of attribution is a treatment epoch of weeks**, and that is
buildable and checkable:

- Resting-HR **level shift** across the start of the current course, against the
  published expectation — label 1–3 bpm; SURMOUNT-1 ABPM substudy (*Hypertension*
  2024, n = 600: 145/152/148 on 5/10/15 mg, 155 placebo) 2–5 bpm dose-dependent
  at week 36; meta-analysis of 12 RCTs, 15,313 participants: tirzepatide
  **+2.05 bpm (95% CI 0.96–3.13)**, 5 mg +0.52 (95% CI −2.71 to 3.78, n.s.),
  semaglutide +3.35, all GLP-1RA pooled +3.47 (*Eur J Med Res* 2026,
  PMC12918571). The association **diminished over the course of treatment**.
- Fatigue as an **incidence**, marked on the days the reader logged it: 3%
  placebo → 5 / 6 / 7% at 5 / 10 / 15 mg (Zepbound US PI §6.1, term includes
  asthenia, fatigue, lethargy, malaise). **It cannot be turned into a daily
  energy delta and the card must not imply it can.**
- ⚠️ Gap: **no published within-week or dose-timing curve for tirzepatide's
  effect on resting heart rate or fatigue exists.** Report as structurally
  unanswerable, not as pending.

### 3.7 The one recommendation that follows from all of this

**The two substances with published *alertness-improving* effects are caffeine
(via UMP) and nicotine (g ≈ 0.3), and the reader has logged zero of both.** The
one they have logged most (stimulant, 4 episodes) needs ~23 and records neither
dose nor formulation.

So the highest-value change the reader could make is **logging caffeine with a
dose in milligrams and a timestamp** — because caffeine has the lowest episode
threshold on the table (~10 at 400 mg), the clearest published dose-response,
and a direct route into the only model family that covers it. That
recommendation is not advice about their health; it is a statement about what
their data can support, and it belongs in the card's coverage-gate copy.

---

## 4. The uncertainty statement

### 4.1 The derivation, term by term

Every term is **derived rather than cited** wherever the repo's rule allows it.

| Term | Value (KSS) | Where it comes from |
| --- | --- | --- |
| σ_model — the field-fit residual | **1.42** | Ingre 2014, best model (S-with-brake + C + U), n = 136, 5,744 ratings |
| σ_person — between-subject intercept | **0.84** | Ingre 2014. **Applies until the reader is personalised, and personalisation requires objective measurement — 2B-Alert learned an individual's sleep-loss phenotype within 12 PVT measurements. Without those it never drops.** |
| σ_phase — circadian phase error | **0.30** (regular) / **0.87** (irregular) | **Derived**: `dC/dp\|max = Ca · 2π/24 = 2.5 × 0.26180 = 0.6545` alertness units per hour; × \|b\| = 0.46 → **0.3011 KSS per hour of phase error**; × 1.0 h (Huang 2021 Apple Watch MAE 0.964 h) or × 2.88 h (Stone 2021). Conservative: this is the *maximum* sensitivity, at the steepest part of the cosine |
| σ_sensor — wearable TST bias | **0.053** | **Derived**: 16.85 min = 0.281 h (JCSM 2025 meta, 24 studies, 798 patients) × 0.19 KSS per hour (Kuula/Bauducco 2025 within-person afternoon β) |

Combined in quadrature:

| Reader state | Arithmetic | KSS | **0–100 points** |
| --- | --- | --- | --- |
| Un-personalised, regular sleeper | √(1.42² + 0.84² + 0.30² + 0.053²) | **1.68** | **±21** |
| Un-personalised, irregular sleeper | √(1.42² + 0.84² + 0.87² + 0.053²) | **1.86** | **±23** |
| Personalised (12 PVT tests) | √(1.42² + 0.30² + 0.053²) | **1.45** | **±18** |

**The finding that must be on the card: σ_model alone is 1.42 of the 1.68 — 72%
of the total, 85% of the variance. Adding data sources does not narrow this
ribbon. Nothing does, except objective measurement from the reader, and even that
buys about 3 of the 21 points.**

That is the honest, slightly deflating answer to *"I want more data sources to go
into it"*: more sources make the card **say more**, they do not make the number
**sharper**. The design says so explicitly rather than implying otherwise by
adding terms.

Note also that σ_sensor is 3% of the total — **so the curve's uncertainty is
dominated by the model, not by the wearable.** Worth printing, because readers
reasonably assume the opposite.

### 4.2 What the card prints

**Ribbon: ±1 SD, drawn as `AreaMark(x:yStart:yEnd:)`** — the precedent is
`FitnessProjectionChart`, which already does exactly this and whose doc comment
explains why `AreaMark(x:yStart:yEnd:)` takes no `stacking:`. Load `add-chart`
before writing it.

**Headline:** the band word first, the number and its ± second —
`"Steady · 58 ± 21"` rather than `"58 · Steady"`. Because a 25-point band is 1.2
standard deviations wide, so the word is roughly at the model's resolution and
the digits are not.

**The methodology sentence, on the card:**

> This is a model of alertness, not a measurement of it. It is the published
> three-process model, fitted on 136 airline crew and 5,744 sleepiness ratings,
> and it is right to within about 21 points of this 0–100 scale — most of which
> is the model's own error, not your wearable's. The whole difference between
> your best and worst hour on a well-slept day is about 26 points. Nothing here
> is a target.

**Two conditional sentences** that appear when they apply:

- *Chronic restriction:* "You have been short of your own sleep need for N days.
  Every biomathematical model of alertness tested against chronic restriction
  performed no better than a flat line, so this curve has no validated skill in
  the stretch you are in." (⚠️ The detector threshold — ≥ 7 consecutive days
  above ξ — **is a guess**, and the card says so.)
- *Model disagrees with you:* "This may not match how you feel, and that is not
  necessarily the model being wrong. In a 48-person study, people's own
  sleepiness ratings stopped separating 6 hours a night from 4 while their
  measured performance kept diverging. This card is not tuned to agree with you."

---

## 5. What it may never claim

Each line is enforceable, and the enforcement is named. The two already held are
marked ✅.

| Prohibition | Basis | Enforcement |
| --- | --- | --- |
| ✅ **Not calories.** The 0–100 is not an energy unit | the unit is a transform of KSS | `EnergyCurveExplainerTests.testItSaysTheUnitIsNotCalories` — keep, and extend to assert the KSS provenance |
| ✅ **No advice.** Never tells anyone to stop, push on, or rest | standing rule | `EnergyCurveExplainerTests.testItNeverGivesAdvice` — keep the phrase list, add "get an early night", "cut back", "skip" |
| **Never a measurement.** `MetricSource.calculated`, no reference range | the modelled-not-measured rule | new test: every series this card writes carries `.calculated` |
| **Never blend a vendor composite.** Oura stress / resilience / readiness / sleep score, Garmin Body Battery and Training Readiness, WHOOP Recovery / Strain, Fitbit Daily Readiness, Samsung Energy Score — **relay only, labelled** | Doherty 2025: 14 scores, 10 manufacturers, **none disclosed a formula**; Oura's own science page lists zero publications for Daytime Stress, Resilience or Cumulative Stress | new test: no Oura/vendor raw identifier may appear in the alertness arithmetic |
| **Never compute or display LF/HF as a stress index.** If an upstream source hands us one, relay it with the citation attached or drop it | Billman GE, *Front Physiol* 2013;4:26 — every assumption underpinning LF/HF fails; exercise and myocardial ischemia do not consistently raise LF and may lower it. Heathers JAJ, *Front Physiol* 2014;5:177 — LFnu, HFnu and LF/HF are mathematically equivalent transforms, so drawing several implies independent evidence that does not exist | new test |
| **Never call anything here "allostatic load"** | McEwen & Stellar 1993; Seeman TE, McEwen BS, Rowe JW, Singer BH, *PNAS* 2001;98(8):4770–5 — ten canonical markers (12 h urinary cortisol, epinephrine, norepinephrine; DHEA-S; TC:HDL; HDL; HbA1c; SBP; DBP; waist-hip). **Not one is wearable-obtainable, and HRV is not among them** | new test on the copy |
| **Never attribute a night, a day or a dose-day to a tirzepatide injection** | Schneck 2024: t½ 5 d on a 7 d interval — no unexposed day exists | §3.6; new test asserting the epoch unit |
| **Never assert a multi-day alcohol HRV window** | no peer-reviewed source; traces to WHOOP/Oura blogs. Controlled 3+3+3 design showed rapid normalisation | new test: the alcohol window constant may not exceed 2 days |
| **Never say last night's shortfall explains today** | Kuula 2025: within-person β = −0.14 KSS morning / −0.19 afternoon per hour of TST. A 45-minute shortfall is ~0.14 KSS against a 1.42 residual | copy review |
| **Never tune the curve to self-report** | Van Dongen 2003: SSS did not differentiate 6 h from 4 h while PVT diverged (F₂,₃₀ = 3.67, p = .037) | §1.4 Departure 7; feedback is recorded, never fitted |
| **Never draw an evening alertness bump** | Sagaspe/Bes 2018: undetectable at normal sleep pressure, n = 12 | §1.4 Departure 4 |
| **Never claim skill during chronic sleep restriction** | Van Dongen 2004: RRMSE 75–100% across six models | §4.2 conditional sentence |
| **Never use sleep stages in arithmetic** | JCSM 2025: 60–75% four-stage accuracy | §1.4 Departure 6 |
| **Never assert a post-lunch dip for this person** | Ingre 2014 questioned U's validity once chronotype was modelled; Monk gives no population magnitude | U off by default |
| **Never report a per-substance personal effect below its episode threshold** | §3.5 derivation | new test: the confirmation path is unreachable below `n` |
| **Never present a published prior as the reader's own response** | the whole point of §3 | new test on the two labels |
| **Never present `.acuteCardiacLoad` as an effect size** | its own doc comment: an ordering heuristic, not a clinical figure | weight 0, existing |
| **Never present basal energy as "your metabolism"** | existing backlog warning | existing |

---

## 6. The empty and learning states

Standing rule 2: every card shows, even with no data, and an empty card asks for
what it needs. `CoverageGate` (`Presentation/CoverageGate.swift:35`) is the type
that makes a withheld figure say what it is waiting for.

### 6.1 The gate ladder

**The floor drops substantially.** Today the card refuses entirely without a
sleep reading fresher than 36 h (`Energy.swift:173`). The three-process model
needs a **wake time**, and a habitual wake time is learnable — so a missing
night widens the ribbon rather than blanking the card. *Thin data is a reason to
print the error bar, not a reason to show nothing.*

| State | Gate | Sentence |
| --- | --- | --- |
| No sleep source at all | — | Existing `invitingInput`: "Connect a sleep source" |
| Nights recorded, none in 3 days | — | Existing "Waiting for last night" + `isAwaitingTodaysData`. **Keep both** — they were written from a real defect where Today lost its cards every morning |
| Nights recorded, last night missing, ≥ 7 nights of history | `need: 7, have: n, unit: "night"` | Curve draws from the **habitual** wake time, with the reader's night-length spread added to the ribbon in quadrature. The card says which it used |
| Phase not yet anchored | `need: 14, have: n, unit: "night", unlocks: "this can set the curve to your own body clock instead of the population average"` | ⚠️ **14 is a guess** — Oura requires ≥ 5 days for its own baseline, Huang's cohorts were established regular sleepers, and no published minimum exists. The card says the number is a guess |
| Bedtime regularity unknown | `need: 14, have: n` | Until met, the **wider** (±2.9 h) phase error is used. Widen when uncertain, never narrow |
| Sleep debt | `need: 14, have: n, unit: "night", unlocks: "this can total the extra hours you have spent awake"` | Σ needs a run of nights |
| Personalisation | `need: 12, have: n, unit: "tap test", unlocks: "this curve can narrow to your own response to sleep loss"` | 2B-Alert: learned within 12 PVT measurements over the first 36 h, thereafter within ~10 ms of the fully-customised model, prospectively validated n = 21. **The only published route to a narrower ribbon** |
| Exertion layer | `need: 24, have: n, unit: "quarter-hour of heart rate"` | 77 of 90 days clear it overall; **only 47 of 90 clear it inside 09:00–21:00**. Falls back to steps (90/90) and says which it used |
| Oura relay | met — 89 / 90 days | Silent. `CoverageGate.sentence` is nil once met, and this app does not nag |
| Oura verdict relay | 73 / 90 | ⚠️ **Print both denominators.** 16 days in the window carry the seconds and no `day_summary`, and a comparison written against 89 and silently run against 73 is exactly the quiet shrinkage the docs exist to prevent |

### 6.2 The per-substance gates — the reader's real state

Rendered as one row per class, always visible, `shortLabel` in the trailing
slot:

| Class | Gate | Row |
| --- | --- | --- |
| Stimulant | **4 / 23** | "4 of 23 episodes so far — 19 more and this can tell your own response apart from the published one." Plus: "The published effect is 0.59 SD. At 4 episodes the smallest effect this could detect is 1.40 SD. Your record cannot yet agree or disagree with it." Plus: **"These events record no dose and no formulation, so the window they should be attributed over is unknown."** |
| Cannabis | **1 / 77** | "1 of 77 episodes so far." And the honest prior: *the 2025 meta-analysis found no consistent effect on any sleep parameter, and the cleanest next-day trial found nothing objective at all.* |
| Caffeine | **0 / 23** (or 0 / 10 at 400 mg) | "Nothing recorded yet. This needs 23 episodes, and then this can compare your own response with the published one." Plus the §3.7 note: caffeine has the lowest threshold on the list, and logging a dose in milligrams is what unlocks it |
| Alcohol | **0 / 24** (high dose) | As above, with the outcome note: chart it against REM, HRV and night HR, not total sleep time |
| Nicotine | **0 / 43** | As above, with the two-night sign-flip note |
| MDMA, psychedelic, dissociative, depressant, other | no gate | "No published time-course was found for this class." A finding, not a hole |
| GLP-1 | **not a gate** | "This is a weekly medication with a five-day half-life, so there is no unexposed day to compare against. It is compared across treatment epochs instead." **Structurally unanswerable, not pending** |

### 6.3 The learning state is the *normal* state

For this reader, today, essentially every gate is unmet and the card is
substantially a learning state. That is correct, and it is why §3 is designed
around the prior rather than around the confirmation. **A card that shows the
published curve, the reader's five episodes against it, and an honest count of
how far short they are is more useful than either a blank panel or a confident
lie.**

---

## 7. Build order — independently shippable slices

Each slice ships to `main` on its own (no PRs), passes `./scripts/verify.sh
--tests`, and leaves the card working.

### ⚠️ Which slices need the phone

`EnergyModel.curve` **cannot be verified on a simulator at all** — the loaded
export ends before "today", so Energy sits in its waiting state. The general
rule that falls out:

- **Anything whose visible output depends on `now` being inside the data needs
  the phone.**
- **Anything computed over historical days is simulator-visible and unit-testable.**

Phone-gated: **S0's verification, S2, S5 (today's layer), S8 (the side-effect
marks), S11.** Everything else can be seen on the simulator or proved by
`swift test`.

| # | Slice | Ships | Verification |
| --- | --- | --- | --- |
| **S0** | **Make the curve visible without the phone.** Pin `now` to the newest day carrying a sleep reading, behind a developer setting. ⚠️ Check first whether a mechanism already exists — do not build a second one (`ls`/`git log` before `Write`, per CLAUDE.md) | no user-visible change | This is the enabler for every later slice's verification. Simulator |
| **S1** | **`AlertnessModel` in InsightKit** — S, C, U (off), the KSS transform, the 12.5-points-per-KSS mapping, the ribbon arithmetic. Pure functions. **Resolve §1.3 against the paper first.** | nothing wired | `swift test`, including the 43%-decay-over-16 h assertion and the §1.5 worked table. Linux-clean |
| **S2** | **Swap the card's number.** Headline becomes band + number + ±. `EnergyCurveChart` gains the ribbon (`AreaMark(x:yStart:yEnd:)`, `FitnessProjectionChart` precedent) and the hatched first-90-minutes region. Explainer rewritten; `EnergyCurveExplainerTests` extended. **Bump `Feedback` to `energy-v2`.** Delete the six invented constants (or park them for one release — open decision) | the new number | **Phone.** Load `add-chart` first |
| **S3** | **Phase from the reader's own sleep timing.** Midpoint → acrophase; `sleep.bedtimeSpread` → the ±1.0 h / ±2.9 h selection; the phase term enters the ribbon | a curve anchored to their clock | `swift test` over historical days; simulator for the history axis; phone for today |
| **S4** | **Engine plumbing: `DerivedSeriesStore` reaches `evaluate`.** Then `derivedInputs = [sleep.learnedSleepNeed, workImpact.workExposure]`. **Unblocks every card, not just this one** | `fullChargeSleepHours` becomes learned; sleep debt as a scored figure with its ±3.5 h band | `swift test`, `DerivedSafetyTests` |
| **S5** | **The exertion layer, in its own units.** Two new `MetricType`s for Oura `daily_activity.resting_time` / `.sedentary_time` (**load `add-metric-type`** — exhaustive switches, `MetricExplainer` entry each, this repo's most frequent CI break). Steps as the coverage fallback. Drawn beneath, never summed | "what you actually did today" | `swift test`; **phone** for today's layer |
| **S6** | **The substance prior.** `SubstancePrior` per `SubstanceClass` with τ, window, direction, effect, citation, `nil` where none. Per-class `CoverageGate` from §3.5. `EnergyInsight(events:)` bound via `InsightEngine.withSubstanceLog` (existing precedent) | the priors and the gates, for every class | `swift test`; simulator |
| **S6a** | **Dose and formulation on `SubstanceEvent`.** `units` exists and is nil on all 18; formulation does not exist. **Load `add-data-or-input`** — `InputKind`, four surfaces, three checks | the input that makes S7 answerable | `swift test`; simulator |
| **S7** | **The reader's episodes against the prior.** Step-adjusted deltas, per-episode error bars, the "cannot yet agree or disagree" sentence. **Derive this reader's nightly RHR SD and invert it** for the RHR threshold — the published gap | the comparison, honestly gated | `swift test` |
| **S8** | **The GLP-1 epoch layer.** `activeMedicationLevel` (90/90) as an epoch band; RHR level shift vs +2.05 bpm (95% CI 0.96–3.13); side-effect marks. Needs the same plumbing family as S4 to get `SideEffectRecord` into InsightKit | the densest signal the card doesn't read | `swift test`; **phone** for the marks — 13 of 14 entries are inside the last six days |
| **S9** | **The Oura relay.** New `MetricType`s for `stress_high` (89/90), `recovery_high` (89/90), `day_summary` (73/90), `resilience.level` (63/90) — units are **seconds**, definition is a **self-normalising quartile rank**. Relayed at weight 0 with the Doherty caveat. ⚠️ Backlog D28 (Data-tab grouping) is **already done** — `RawFieldGrouping.swift:167`, `RawFieldPresentation.swift:179-200`, tests at `RawFieldPresentationTests.swift:274-316`. Do not redo it | the labelled second opinion | `swift test`; simulator |
| **S10** | **The "may be wrong today" flag.** Relay the symptom radar's verdict; do not recompute it | one sentence, when it applies | `swift test` |
| **S11** | **Optional personalisation: a 3-minute tap test.** 12 sessions, per 2B-Alert. New `InputKind` — **load `add-data-or-input`**. The only published route to narrowing the ribbon, worth ~3 of 21 points | a narrower ribbon for a reader who wants one | **Phone.** A PVT on a simulator measures the simulator |

### Docs to bring forward in the same commits

- `docs/card-sections.md` — Energy currently has **bespoke 2 = ○**. This design
  needs two bespoke sections (the curve, and the substance layer), so the
  matrix, the ordering table and the four hand-written tables all change, and
  `./scripts/card-map.sh` must be regenerated (`handover-check.sh` runs
  `--check`).
- `docs/backlog.md` §B19 — the re-scope, and the diagnosis in §0 as the ruling
  it was owed.
- `docs/research-notes.md` — the published half of this document.
- `docs/symbol-index.md` — `./scripts/gen-symbol-index.sh` after S1, S5, S6, S9.


---

## Open decisions

- ⚠️ BLOCKING S1 — the Process S equation as transcribed cannot be right. The evidence brief renders wake-time S as S(t)=ha−(ha−sw)·e^(d·t) with d = −0.0353, which makes S RISE toward the upper asymptote 14.3 during wake. That is the sleep-recovery form. Ingre 2014 is open access: open it, copy both the wake and sleep equations, confirm which asymptote each approaches, and obtain the sleep-recovery rate (absent from this evidence pass — do not guess it). Every worked number in §1.5 and the four-hours-vs-eight comparison are conditional on this.
- Print ±1 SD or ±95%? Recommended 1 SD (±21 points), because 95% is ±41 on a 0–100 scale and spans most of it. The 95% figure goes in the methodology text. Needs the reader's call — it changes how alarming the card looks.
- Does the card keep the name 'Energy'? Recommended yes — it is the reader's word, `InsightID.energy` and its ScoreHistory continuity depend on it, and the subtitle can carry 'modelled alertness'. The alternative is renaming to 'Alertness', which is more accurate and loses the reader's own framing.
- The bedtime-regularity thresholds (≤1.0 h regular, >2.0 h irregular) are a guess with no published basis. What makes them tolerable is that they only SELECT between two cited phase errors (±1.0 h Huang 2021, ±2.9 h Stone 2021) rather than inventing one. Confirm the card states this plainly.
- The chronic-restriction detector (≥7 consecutive days of wake above ξ) is a guess. Van Dongen 2004 gives no threshold, only that all six models failed at 14 days. Needs a decision on where to trip the 'no validated skill' sentence.
- Delete the six invented constants outright, or keep the old number for one release as a labelled derived series so ScoreHistory does not jump discontinuously? Recommended: park for one release, then delete. Either way `Feedback` must move to `energy-v2` (the fitness-v2 precedent) or every pre-change score becomes silently non-comparable.
- Caffeine's alertness term needs UMP's published pharmacokinetic coefficients (Ramakrishnan 2016), which are NOT in this evidence pass. Decision: obtain them, or ship caffeine as sleep-effect-only. Do not invent a term.
- Should `SubstanceEvent` gain dose (mg) and formulation? It has `units`, nil on all 18 events, and no formulation field. Without both, the stimulant window is unknown (MPH IR 3–4 h vs lisdexamfetamine 10–14 h) and caffeine's dose-dependence (100 mg null vs 400 mg large) is unresolvable. This is an `add-data-or-input` change across four surfaces.
- Where should caffeine be logged — the substance log (has a timestamp) or `MetricType.dietaryCaffeine` (a daily total, 0 of the last 90 days)? Gardiner 2025 shows timing decides the effect, which argues for the substance log. Needs a decision before S6a.
- Does the 24-hour episode gap rule hold for a near-daily stimulant user? `SubstanceEpisodes.swift:17-27` already flags that a daily user has one continuous episode under any gap rule and can never reach three independent occasions. If this reader's stimulant use is near-daily, the ~23-episode threshold is unreachable in principle and the card must say so rather than counting down toward it.
- Energy needs two bespoke sections (curve, substances) and `docs/card-sections.md` records it at 'bespoke 2 = ○'. Confirm the second section rather than nesting substances inside the curve section — it changes the matrix, the ordering block (regenerate `./scripts/card-map.sh`) and four hand-written tables.
- Does an S0-style 'pin the clock to the newest day with data' mechanism already exist? Check before building — `BodyModelParameters` was implemented twice in one session for exactly this reason.
- Sleep debt is shown but never enters the curve shape (Van Dongen 2004 forbids it). Confirm the reader is content that a large sleep debt does NOT pull the number down — this will look like a bug to anyone who expects it to.

## Build order

1. S0 — Make the curve visible without the phone: pin `now` to the newest day carrying a sleep reading, behind a developer setting. Check first whether such a mechanism already exists. No user-visible change; it is the enabler every later slice's verification depends on.
2. S1 — `AlertnessModel` in InsightKit: Processes S and C (U implemented and off), the KSS transform, the 12.5-points-per-KSS mapping and the ribbon arithmetic, as pure functions with no wiring. Resolve the Process S equation against Ingre 2014 first. Fully unit-tested including the 43%-decay-over-16-hours assertion. Linux-clean, no phone.
3. S2 — Swap the card's number to the alertness curve. Headline becomes band + number + ±; `EnergyCurveChart` gains the uncertainty ribbon (AreaMark(x:yStart:yEnd:), FitnessProjectionChart precedent) and the hatched first-90-minutes region; explainer and its tests rewritten; Feedback bumped to `energy-v2`; the six invented constants deleted or parked. NEEDS THE PHONE.
4. S3 — Circadian phase from the reader's own sleep timing: midpoint to acrophase, bedtime spread selecting the ±1.0 h or ±2.9 h phase error, and that term entering the ribbon. Arithmetic testable over historical days; the live curve needs the phone.
5. S4 — Engine plumbing: give `evaluate` a `DerivedSeriesStore` parameter so `derivedInputs` becomes load-bearing, then read `sleep.learnedSleepNeed` and `workImpact.workExposure`. Ships sleep debt as its own scored figure with its ±3.5 h band. Unblocks every card, not just Energy. No phone.
6. S5 — The exertion layer in its own units: two new MetricTypes for Oura `daily_activity.resting_time` and `.sedentary_time` (load `add-metric-type`), steps as the coverage fallback, drawn beneath the curve and never summed into it. Phone for today's layer.
7. S6 — The substance prior: `SubstancePrior` per `SubstanceClass` carrying τ, attribution window, direction, published effect and citation — nil where none exists — plus the per-class CoverageGate from the n = 7.85/d² derivation. `EnergyInsight(events:)` bound via `InsightEngine.withSubstanceLog`. No phone.
8. S6a — Dose and formulation on `SubstanceEvent` (load `add-data-or-input`: InputKind, four surfaces, three checks). Without it the stimulant attribution window is unknown and caffeine's dose-dependence is unresolvable.
9. S7 — The reader's own episodes against the prior: step-count-adjusted deltas, per-episode error bars, the 'cannot yet agree or disagree' sentence, and this reader's nightly RHR SD derived and inverted to supply the threshold the literature does not publish. No phone.
10. S8 — The GLP-1 epoch layer: `activeMedicationLevel` (90/90 days) as an epoch band, resting-HR level shift against the published +2.05 bpm (95% CI 0.96–3.13), and side-effect marks — which need `SideEffectRecord` plumbed into InsightKit. Phone for the marks.
11. S9 — The Oura relay: new MetricTypes for `stress_high`, `recovery_high`, `day_summary` and `resilience.level`, relayed at weight 0 with the Doherty caveat, in seconds, labelled as a self-normalising quartile rank, printing both denominators. Backlog D28's Data-tab grouping is already done — do not redo it. No phone.
12. S10 — The 'this may be wrong today' flag: relay the symptom radar's verdict rather than recomputing an illness signal. No phone.
13. S11 — Optional personalisation: a 3-minute tap test, 12 sessions, per 2B-Alert — the only published route to a narrower ribbon, worth about 3 of the 21 points. New InputKind (load `add-data-or-input`). NEEDS THE PHONE.

---

## Adversarial review — three hostile lenses


### Verdict: **needs-rework**

**Fatal:**
- §3.5 — EVERY episode threshold is understated by a factor of ~2, because the wrong SD is used. `n = 7.85/d²` for a PAIRED comparison requires d = (mean difference)/(SD of the DIFFERENCE). The design divides by the per-night SD instead: 77.41 min (Bei, night-to-night intraindividual TST SD) and 0.37 (Hannon within-person RMSSD CV). For two nights the difference SD is √2 × that. Redo it: caffeine 400 mg −70 min → d = 70/109.5 = 0.64 → n ≈ 19, not 10. Stimulant −0.59 SD → n ≈ 46, not 23. Alcohol high-dose RMSSD −21.3% → 0.213/0.523 = 0.41 → n ≈ 47, not 24. Cannabis → ~155, not 77. Because n ∝ 1/d², the error is exactly ×2 on every row. The card is specified to PRINT these: §6.2 says 'Stimulant 4/23 — 19 more and this can tell your own response apart from the published one.' Shipped as designed it makes the reader a numeric promise that is wrong by a factor of two.
- §3.5 — the pairing rule is never stated, so `n` is not computable at all. 'Paired comparison' with WHAT? The adjacent non-exposure night, a matched night by day-of-week, the 90-day mean, a random draw? Adjacent nights are positively autocorrelated (smaller difference SD, smaller n); random-draw nights are ~independent (√2 × per-night SD). The choice moves every number in the table by a factor of 2 or more in either direction. A threshold the card counts down toward, whose value depends on an unstated analysis choice, is not a threshold.
- §3.5 / §5 — there is no multiple-comparison policy anywhere in the design, and the power calculation is at uncorrected α = 0.05 two-sided. The card as specified will examine ≥4 outcomes (TST, REM, RMSSD, night HR — §3.2 explicitly directs alcohol at three of them) across ≥6 substance classes. That is ≥20 tests. At a Bonferroni-equivalent α = 0.0025 the constant becomes (3.02+0.84)² = 14.9, nearly doubling n again — so the true stimulant threshold is ~90 episodes, not the 23 the card prints. §3.5 acknowledges multiplicity in a ⚠️ ('no published correction factor exists for this setting… treat them as optimistic by an unknown margin') and then does nothing. This repo already has the finding that a correction cannot be waved at: BH was measured INVALID on this reader's own record under negative dependence r = −0.795, and the permutation null ran ~2× anti-conservative (docs/backlog.md:2377-2381). The design must either pre-register ONE outcome per class before any data is examined, or state that no valid correction exists here and therefore no per-substance effect will ever be asserted — and delete the countdown, which currently implies one will be.
- §3.4 — 'adjusted for same-day step count' reintroduces the exact defect that flipped the last finding set, twice over. (a) DAY BOUNDARY: §3.3's prior is exposure-relative (t hours since dose) but the covariate is a calendar-day total. The prior review found this reader's confirmations went 3 → 1 → 0 across UTC+8 / UTC / UTC−5. §3.2 gets this right for nicotine ('read the time, not the date') and then abandons it for the covariate. Specify the covariate as steps in a stated exposure-relative window (e.g. dose → dose+τ, and separately wake→sleep-onset of the affected night) and show the finding under at least two boundary definitions before it is allowed to be drawn. (b) MEDIATOR: a stimulant plausibly CAUSES the movement — Mick 2013's +5.7 bpm and increased activity are downstream of the same dose. Conditioning on a post-exposure variable is not confounder control; it removes part of the effect by construction and can induce collider bias. The 0.91 → 0.03 collapse is evidence the unadjusted estimate was confounded, not proof that the step-adjusted estimate is the causal one. Both must be shown, labelled as bounds, and neither called 'the' effect.
- §4.1 — σ_sensor = 0.053 KSS is derived from the wrong quantity, and it is the basis of a sentence the card prints. 16.85 min is the MEAN DIFFERENCE from the JCSM 2025 meta (95% CI −26.33 to −7.38 — a CI on the mean, over 24 studies). A systematic mean bias does not belong in a quadrature sum of SDs at all; it is a correction. The random term is the SD of wearable-vs-PSG TST differences (the limits of agreement), which the design never obtains and which is far larger. Second error: it propagates through Kuula's β = 0.19 KSS/h — a foreign model's attenuated observational slope — rather than through the three-process model's own ∂KSS/∂TST, which is the only correct derivative for the error budget of the model being shipped. Consequence: the card's methodology line 'right to within about 21 points — most of which is the model's own error, not your wearable's' and the §4.1 claim 'σ_sensor is 3% of the total… worth printing, because readers reasonably assume the opposite' are both unsupported. Do not print either until the SD of differences is read from the paper and propagated through the model's own sensitivity.
- §4 — the ±21 ribbon is borrowed from a model the design does not ship, and it never widens where its own citation says the model fails. σ_model = 1.42 is labelled in §4.1 as the residual of Ingre's BEST model (S-with-brake + C + U). §1.4 Departure 2 ships U OFF; the brake appears in no parameter table in §1.2; and §1.3 says the S equation as transcribed cannot be right. The residual of the configuration actually shipped is strictly larger than 1.42 — dropping U alone cost deviance χ² = 32 — so ±21 is an understatement of the shipped model's error. Worse: §1.4 Departure 5 cites Van Dongen 2004 showing RRMSE 75–100% across six models under chronic restriction, i.e. no better than a flat line, and the design's response is a SENTENCE while the ribbon stays at ±21. §6.1 states the design's own rule — 'Widen when uncertain, never narrow' — and this violates it in the one regime the document says the reader actually lives in. In that state the honest ribbon is the SD of KSS itself, not 1.68.
- §0 — the lead finding, 'sleep duration is roughly four times too strong', is not established, and it is the justification for deleting the six constants. The arithmetic checks (37.5 pts ÷ 12.5 = 3.0 KSS vs 4 × 0.19 = 0.76 KSS), but the comparison is invalid: Kuula/Bauducco's β is a WITHIN-PERSON OBSERVATIONAL slope fitted over the range of ordinary night-to-night variation in a 205-adolescent actigraphy sample, and it is extrapolated 4 hours past that range to a 4 h vs 8 h contrast. Two biases push the same way: (i) actigraphy TST error attenuates within-person slopes by regression dilution — using the design's own JCSM 2025 citation against itself, 0.19 is a lower bound; (ii) a linear slope through habitual variation cannot represent a nonlinear homeostatic response at 4 h. The direct evidence for that contrast is Van Dongen 2003, which the design cites in §1.4 Departure 7 and which shows 4 h and 6 h diverging strongly on objective performance. Note also that the replacement model would itself move far more than 9.5 points for 4 h vs 8 h — so §0's own test condemns the model §1 proposes. Either drop the '4×' framing or re-derive it against the three-process model's own prediction.

**Serious:**
- §1.5/§4 — the document's central rhetorical claim ('the whole diurnal swing is ~26 points, hold that against the ±21 ribbon') compares two incommensurable quantities. σ_person = 0.84 KSS is a BETWEEN-SUBJECT INTERCEPT: it is common-mode across every hour of one person's day and cancels entirely from a within-day morning-vs-evening comparison. Including it in the ribbon used to judge the swing inflates the uncertainty of the shape. The card needs two bands, not one: a common-mode offset (the whole curve slides) and a shape band (how the curve bends). Drawn as one ±21 ribbon, the card implies each hour is independently uncertain by 21 points — i.e. that the curve could be flat — which is a stronger claim than the fit supports and is what will make readers conclude the card says nothing.
- §4.1 — MAE is combined in quadrature as if it were an SD. Huang 2021's 0.964 h and Stone 2021's 2.88 h are mean ABSOLUTE errors; for a normal, SD = MAE × 1.2533. So σ_phase should be 0.364 KSS (regular) and 1.09 KSS (irregular), not 0.30 / 0.87. The irregular-sleeper total becomes √(1.42²+0.84²+1.09²+0.053²) = 1.98 → ±25 points, not ±23. Small in the regular case, but it is a named category error inside a table the document presents as 'derived rather than cited'.
- §2.3 vs §3.5 — two mutually incompatible HRV variability figures are used without noticing. §2.3 says Plews' day-to-day lnRMSSD CV of 3–13% 'is also the derived error bar on any HRV quantity'; §3.5 uses Hannon's within-person RMSSD CV of 0.37 to compute the alcohol episode thresholds. Those differ by roughly a factor of 3–10 because one is on the LOG scale. As specified the card would draw an HRV row with a ±3–13% band while its own power calculation assumes the same quantity varies by 37% — i.e. the drawn band would imply a daily reading is precise enough to interpret, which §2.3 elsewhere correctly refuses. Pick the raw-scale SD for both, or state explicitly which quantity each figure describes.
- §1.4 Departure 7 / §4.1 — the blanket ban on self-report calibration over-applies its citation and locks in ~10.5 points of removable uncertainty. Van Dongen 2003's finding is that the SSS failed to differentiate 6 h from 4 h — that is about SENSITIVITY TO SLEEP LOSS (the slope), not about the person's mean level (the intercept). σ_person = 0.84 KSS = 10.5 points is a pure intercept and is exactly what a mean-offset fit from a handful of self-reports would estimate. §4.1's claim that personalisation 'requires objective measurement… without those it never drops' is therefore too strong. The defensible rule is: self-report may fit the intercept, never the homeostatic slope — which is also what §1.4 already concedes for phase and inertia.
- §3.6 / S8 — the GLP-1 epoch comparison is not a valid test as specified. (a) The published +2.05 bpm (95% CI 0.96–3.13) is the uncertainty of a GROUP MEAN across 15,313 participants; one person's epoch delta compared against it will land outside it almost always, because individual variation is far wider than the CI. The comparator must be a prediction interval for an individual, which that meta does not supply. (b) Daily RHR is strongly autocorrelated, so an epoch's effective n is far below its day count and any naive before/after SE is anti-conservative — the same class of error as the 2× anti-conservative permutation null already found on this record. (c) There is no control period and the epoch is confounded with concurrent weight loss, training and season, all of which move RHR. As written this ships a confounded, autocorrelated single-subject level-shift as a check against the literature.
- §2.3 — the Oura 'labelled second opinion' is not independent of the app's own layer, and the design does not say so. 59,069 of 73,654 intraday HR rows are `apple_health/oura` (the design's own count), and Oura's `stress_high` / `recovery_high` are computed from that same HR/HRV stream. So the exertion layer and the relayed second opinion share a sensor. Relaying is still correct under the vascularAge rule, but the card must not let the two agreeing read as corroboration — that is the statistical content of 'second opinion' and it does not hold here.
- §3.1/§3.5 — the independence assumption behind `7.85/d²` fails on this reader's actual log. 17 stimulant events across 9 distinct days collapse to 4 episodes under the 24 h gap rule; that is clustered, near-daily use, and `SubstanceEpisodes.swift:17-27` already warns that such a user 'has one continuous episode under any gap rule'. Episodes drawn from a clustered process are not independent occasions, and the control nights adjacent to them are contaminated by carry-over (the design's own stimulant window is 10–14 h for lisdexamfetamine). The open-decisions list raises this as a question; it is not a question — if use is near-daily the threshold is unreachable in principle and the countdown in §6.2 is misleading whatever number sits in it.
- §3.5 / §6.2 — thresholds are stated in episodes but the outcome is a night, and 22 of the last 90 nights have no sleep reading (68/90). An exposure episode with no measured night contributes nothing, so the effective n is ~0.76 × the episode count and every threshold needs dividing by outcome coverage. Same for RMSSD (67/90) and night HR. Unstated, this makes the countdown optimistic again on top of the two factors above.
- §6.1 — the missing-night fallback is biased in the direction that matters. 'Curve draws from the habitual wake time, with the reader's night-length spread added to the ribbon in quadrature' — but (a) night-LENGTH spread is not the uncertainty of a WAKE TIME, which is what Process S and the acrophase both need; and (b) nights go unrecorded non-randomly (ring uncharged, late night, illness, travel), so the missing nights are disproportionately the unusual ones. Imputing the habitual value is mean-imputation under MNAR: it shrinks the estimate toward typical and understates the ribbon precisely on the days the card most needs to be uncertain.
- §1.5/§4.2 — a bounded 1–9 ordinal is mapped linearly to 0–100 and then given a symmetric ±1 SD ribbon of 1.42 KSS. Near either end of the KSS scale the residuals cannot be symmetric or homoscedastic, and the ribbon crosses the bounds (a modelled level of 90 implies a band to 111). Either truncate and say so, or model on a scale where the interval is well-defined and transform the endpoints.

**Required changes:** Six edits, in order of how much they change what ships.

1. §3.5 — recompute the whole table with d = effect / (SD of the paired difference), and STATE the pairing rule that defines that SD before computing anything. If pairing is exposure-night vs an independently drawn non-exposure night, every published n doubles (stimulant 23 → 46, caffeine 400 mg 10 → 19, alcohol high-dose 24 → 47, cannabis 77 → 155). Then divide by outcome coverage (~0.76 for sleep) and multiply by the multiplicity penalty from edit 2. Do not print any countdown in §6.2 until that final number exists.

2. §3.5/§5 — add an explicit alpha policy. Pre-register exactly ONE outcome per substance class, chosen from the literature before the reader's data is touched (alcohol → REM, per §3.2; stimulant → TST; caffeine → TST). Otherwise carry the ≥20-test penalty in the power calculation ((3.02+0.84)² = 14.9, not 7.85). Add to §5's prohibition table: "Never apply BH or a permutation null to this reader's substance record" — with the measured basis already in docs/backlog.md:2377-2381 (r = −0.795; null ~2× anti-conservative), and a test asserting no such correction appears in the code.

3. §3.4 — replace "same-day step count" with an exposure-relative covariate window stated in hours since dose, matched to the same window as the outcome, and require the finding to be shown under at least two day-boundary definitions before it may be drawn. Add the mediator caveat: report BOTH the unadjusted and step-adjusted estimate as bounds, and forbid calling either "the" effect. This is the single edit that stops the design repeating the 3/1/0 boundary flip.

4. §4.1 — rebuild σ_sensor from the SD of wearable-vs-PSG TST differences (read it from the JCSM 2025 paper; the mean difference −16.85 min is a bias, not a spread, and its CI is a CI on the mean), propagated through the three-process model's OWN ∂KSS/∂TST, not through Kuula's β. Convert both phase MAEs to SDs (×1.2533). Then re-derive the totals and DELETE the sentence "most of which is the model's own error, not your wearable's" unless it survives. Requote σ_model from the configuration actually shipped (S+C, U off), not from Ingre's best model.

5. §4.2 — draw two bands, not one: a common-mode offset band containing σ_person (the whole curve slides) and a narrower shape band for within-day comparisons. Then restate the headline honestly — the 26-point swing is to be compared against the SHAPE band, not against ±21. And make the ribbon widen, not just caption, in the chronic-restriction state that §1.4 Departure 5 says has no validated skill.

6. §0 — drop or re-derive the "roughly four times too strong" claim. Kuula's within-person β cannot be extrapolated four hours past its range, and Van Dongen 2003 (already cited in this document) is the direct evidence for that contrast. The case for deleting the six constants stands on its own — they have no published basis at all — and does not need a quantified multiplier that the replacement model would itself fail.

Nothing here touches §1's choice of framework, §2's weight-zero table, §3.2's per-substance priors, §3.6's structural refusal of a day-level GLP-1 effect, or §5's prohibition list. Those are the strongest parts of the document and they should survive the rework intact.

### Verdict: **needs-rework**

**Fatal:**
- §0 and §4.1 print a fabricated statistic. "σ_model alone is 1.42 of the 1.68 — 72% of the total, 85% of the variance" has the two labels swapped: 1.42/1.678 = 84.6% is the SD ratio, and 1.42²/1.678² = 71.6% is the variance share. There is no 85% variance fraction anywhere in the budget. §0's headline — "85% of the variance in the error budget is the model's own residual" — is the sentence that justifies refusing every extra data source the reader asked for, and §4.1 marks it "the finding that must be on the card". A ruling that overrides the user's explicit request is resting on a number the document's own table refutes.
- The ribbon is drawn as if every error term were independent per point, and the card's central message depends on that being false. σ_person (0.84 KSS) is a between-subject *intercept* — it shifts this reader's whole curve up or down and cancels exactly in any within-day comparison. σ_phase shifts the peak time; it does not add independent scatter either. So ±21 points is a band on the *level*, and §1.5's flagship claim — "the whole diurnal swing is about 26 points; hold that against the ±21-point ribbon" — compares a within-day contrast against a between-person offset. The correct contrast SD, if the 1.42 residual is independent across observations, is √(2×1.42²) = 2.01 KSS = ±25 points and excludes σ_person entirely. The design never states which terms are shared and which are independent, and both the ribbon's meaning and the redesign's headline conclusion are undefined until it does.
- The printed methodology sentence "it is right to within about 21 points of this 0–100 scale" is a claim the cited number cannot support, in three ways at once. (a) 1.42 is the residual SD of the *best-fitting* model on its own fitting data — in-sample, 136 aircrew, and the document never argues transfer to a day-working adult. (b) It is the residual against *KSS self-reports*, and §1.4 Departure 7 plus §4.2's second conditional sentence tell the reader that self-report is exactly what fails to track the deficit (Van Dongen 2003: SSS did not separate 6 h from 4 h while PVT diverged). So the card's error bar measures agreement with a rating the same card declares invalid, and then presents it as the error on the reader's alertness. (c) §4.1 boasts "every term is derived rather than cited", while the two terms carrying 96.7% of the variance (1.42 and 0.84) are both straight citations. Correct copy is "in the study it was fitted on, it missed people's own sleepiness ratings by about 21 points on this scale; its error for you has not been measured."
- σ_sensor = 0.053 KSS is a mean bias masquerading as a random error, and the conclusion drawn from it is printed to the reader. The JCSM 2025 figure −16.85 min (95% CI −26.33 to −7.38) is the meta-analytic *mean difference* in TST with a CI on that mean — it is a systematic offset to be corrected, not a per-night SD to add in quadrature. The per-night error SD (limits of agreement) is the quantity needed and is roughly 3–6× larger. Compounding it, the propagation uses β = −0.19 KSS/h from Kuula/Bauducco's *adolescent actigraphy* regression rather than the three-process model's own sensitivity to sleep duration — an exchange rate borrowed from a different model to price an error in this one. On that arithmetic §4.1 prints "σ_sensor is 3% of the total — the curve's uncertainty is dominated by the model, not by the wearable. Worth printing, because readers reasonably assume the opposite." That is a reassurance about the reader's sensor derived from a number that is not the sensor's error.
- §4.1's third row sets σ_person to exactly 0 after 12 tap tests and prints ±18. Twelve noisy PVT sessions estimate a personal intercept; they do not eliminate its uncertainty, and the residual standard error of that estimate is never computed — it is simply dropped from the quadrature. Worse, the justification (2B-Alert learns an individual's phenotype within 12 PVT measurements, "thereafter within ~10 ms of the fully-customised model") is a result about the *UMP* model family predicting *PVT reaction time in milliseconds*. It cannot license zeroing the *Three-Process Model's* between-subject KSS intercept SD. §6.1 then sells this to the reader as "this curve can narrow to your own response to sleep loss" — selling a narrowing whose size is unknown.
- The per-substance coverage-gate copy in §6.2 is a countdown asking the reader to consume. "Nicotine — 0 / 43", "Alcohol — 0 / 24 ... As above", "Caffeine — 0 / 23 ... Nothing recorded yet. This needs 23 episodes, and then this can compare your own response with the published one." Rendered as always-visible rows on a health card, these read as progress bars toward 43 nicotine exposures and 24 heavy-drinking episodes. §3.7 then makes it explicit — "the highest-value change the reader could make is logging caffeine" — and §3.2 states as a virtue that nicotine's "acute alertness benefit is real" (g = 0.34). The design's own prohibition table says the card never tells anyone to push on or rest; a denominator counting down toward an exposure is the same instruction wearing a gate's clothes. §5's `testItNeverGivesAdvice` phrase list would not catch a single one of these strings.
- §0's flagship diagnosis — "sleep duration is roughly four times too strong: the card moves 37.5 points, the evidence says 9.5" — is a unit error, and the replacement is never subjected to the same test. The 9.5 comes from converting Kuula's β = −0.19 KSS/h at 12.5 points/KSS, but 12.5 points/KSS is the *new* card's transform; the document's own argument is that the shipped 0–100 has no units at all (§5: "the 0–100 is not an energy unit"). Comparing 37.5 unitless points against 9.5 KSS-derived points is not a comparison. Then the replacement's own sleep sensitivity is never computed — and cannot be from this document, because §1.3 admits the sleep-recovery rate is absent from the evidence pass and must not be guessed. If the three-process model's implied 4 h-vs-8 h swing also exceeds 9.5 points, the indictment applies to the replacement and the rebuild's premise collapses. The honest version of §0 is stronger and shorter: the shipped scale has no units, so its 37.5-point move cannot be compared with any published effect size, full stop.

**Serious:**
- §3.5's episode thresholds are understated by about 2× and the card prints them. n ≈ 7.85/d² is the paired-comparison formula, where d = Δ/SD_of_the_paired_difference. The document divides by the *night-to-night within-person SD* (TST 77.41 min, RMSSD CV 0.37). For two nights, SD_diff = √2 × SD_night unless the pairing induces correlation, which is never argued. Every threshold roughly doubles: stimulant ~46 not 23, caffeine 400 mg ~20 not 10, nicotine ~86 not 43. §6.2 prints "4 of 23 episodes so far — 19 more" as a hard denominator. The ⚠️ "optimistic by an unknown margin" hedge does not rescue a printed integer.
- §1.4 Departure 3 borrows the good number for the worse method. The ±1.0 h regular-sleeper phase error is Huang 2021's Apple Watch MAE for a *higher-order Kronauer model with activity input* — and the same paragraph says "We are not implementing Kronauer", we anchor on sleep midpoint, which Stone measured at about half a model's concordance. The design widens for irregular sleepers on that reasoning and then keeps model-grade accuracy for regular ones. Separately, MAE is not an SD: for a normal, σ ≈ 1.253 × MAE, so σ_phase should be ~0.38 / ~1.09 KSS, not 0.30 / 0.87.
- §1.4 Departure 7 carves a hole in §5's own prohibition. The table row says "Never tune the curve to self-report", enforced by "feedback is recorded, never fitted". The prose says feedback "may only fit the inertia amplitude and the phase". Fitting phase to how the reader says they feel *is* tuning the curve to self-report, and the named enforcement (feedback never enters S) would not catch it.
- Numbers the document flags as unverified are nonetheless routed into card copy. §1.2 says every parameter "must be re-read from the paper before a line of code is written"; §1.3 says the Process S equation as transcribed cannot be right and every worked number in §1.5 and §4 is conditional on resolving it. §1.5 is duly marked "to be regenerated". The 26-point swing is not — it is derived from that same table and appears verbatim in §4.2's printed methodology sentence.
- The card's realised dynamic range makes it a permanent "Steady". With S bounded [2.4, 14.3] and Ca = 2.5, alertness maxes at 16.8 → KSS 1.95 → level 88, so 100 is unreachable; the §1.5 well-slept day lives at 43–69. "Drained" (0–25) needs KSS ≥ 7, and "High" (75–100) is essentially unreachable. No clamp is specified for the negative levels the low end produces. A card whose band word almost never changes is the useless-permanent-null in a different costume, and §1.6's defence that the 25-point bands are "roughly at the model's resolution" is itself soft — a 25-point band against a ±21 SD means a reading near any boundary is close to a coin flip.
- §7 slice S4 ships "sleep debt as a scored figure with its ±3.5 h band". That ±3.5 h appears exactly once in the whole document, with no derivation, no citation and no propagation from the learned-need interval it presumably comes from. It is the one displayed error bar in the design that is neither derived nor cited — the precise thing §4 is written to prevent.
- The stimulant countdown may be counting toward an unreachable number, and the copy is already written. `SubstanceEpisodes.swift:23` states in the shipped source that a near-daily user has one continuous episode under any gap rule and can never reach three. §6.2 nonetheless specifies "4 of 23 episodes so far — 19 more and this can tell your own response apart from the published one" for a reader with 17 events across 9 days. The open-decisions list defers this, but the promise is in the design; if the threshold is unreachable in principle the sentence is a lie the app repeats daily.
- Two privacy lines are readings, not shapes. §2.2: "This reader's learned need sits inside that interval" where the interval is 8.16 ± 0.73 h. §1.4 Departure 3: "This reader's bedtime spread sits inside the regular band", i.e. ≤ 1.0 h. Both are bounded intervals on this person's physiology in a public repo, which is a reading with an error bar rather than the shape of a finding. `docs/privacy-and-ip.md` should be re-read against these two sentences specifically.
- The Oura relay needs a stated adjacency rule, not just a weight. §2.3 correctly records that `daily_stress.stress_high` is in *seconds* and is a self-normalising quartile rank against the wearer's own recent distribution, and §5 forbids blending. But §6.1/§9 place the relay on the same card as the alertness number without specifying that it may not be drawn on the same axis, in the same colour family, or in a band vocabulary that mirrors High/Steady/Running low. `daily_resilience` is a composite of composites (Sleep Score, HRV Balance, both undisclosed) whose *label* carries more implied authority than its seconds do. The vascularAge rule is about visual as much as arithmetic separation.
- Small factual drift that will cost a round trip: §1.4 cites `Feedback.swift:170` for `energy-v1`; it is at `Feedback.swift:169`. The six constants are at `Energy.swift:133/136/140/144/147/153` as stated — those check out.

**Required changes:** Seven edits before any slice ships, in order.

1. Fix the error-budget arithmetic and re-word the ruling. §0 and §4.1: σ_model is 85% of the *standard deviation* and 72% of the *variance* — the two labels are currently swapped and there is no 85% variance share. Then decompose the budget into a LEVEL band and a SHAPE band, stating for each term whether it is shared across the day (σ_person, and any model bias) or independent per point (the residual, if it even is). Only the shape band may be compared against the 26-point swing, and it is √(2×1.42²) ≈ ±25 points with σ_person removed — not ±21. Redraw the ribbon accordingly, or state in §4.2 that the ribbon is a level band and the within-day differences are not uncertain by that amount.

2. Rewrite the printed methodology sentence. Delete "it is right to within about 21 points of this 0–100 scale" and "most of which is the model's own error, not your wearable's". Replace with: "In the study it was fitted on — 136 airline crew, 5,744 ratings — it missed people's own sleepiness ratings by about 21 points on this scale. That is agreement with a rating, in-sample, and its error for you has not been measured." Drop §4.1's claim that "every term is derived": say plainly that the two terms carrying 97% of the variance are borrowed from Ingre 2014, and that the derived terms are the small ones.

3. Redo σ_sensor or delete it. −16.85 min is a mean bias — correct for it, do not add it in quadrature. If a sensor term is wanted, use the meta's limits of agreement (per-night SD), and propagate it through the three-process model's own sensitivity to TST, not through Kuula's adolescent β. Whatever comes out, the "not your wearable's" reassurance cannot ship until the propagation is through the right model.

4. Stop zeroing σ_person. Either carry a residual intercept-estimation error for the 12-session fit and show your working, or delete the ±18 row and §6.1's "this curve can narrow to your own response to sleep loss" until someone can say by how much. Note in the row that 2B-Alert's result is a different model family predicting PVT milliseconds.

5. Rewrite §6.2's gate copy so no row counts toward an exposure. For a class with zero events, the row says what is known and what is not — "no episodes of this are recorded, so nothing here is about you" — and never prints a denominator. Keep denominators only for classes the reader already logs, and only once decision 10 resolves whether the stimulant threshold is reachable at all. Extend `testItNeverGivesAdvice` to fail on any string matching a "N of M episodes" pattern for a class with zero logged events, and on "unlocks"/"needs N" copy attached to caffeine, alcohol, nicotine or cannabis.

6. Rewrite §0's diagnosis. Drop "roughly four times too strong" and the 9.5-point conversion — the shipped 0–100 has no units, so no published effect size can be compared with it. Say that instead; it is the stronger finding. Then add the test the document is missing: once §1.3 is resolved, compute the three-process model's own 4 h-vs-8 h morning swing in points and put it in the §0 table beside 37.5. If it is not materially smaller, the rebuild's premise needs restating.

7. Fix §3.5's power derivation — divide by the paired-difference SD (√2 × the night-to-night SD unless a pairing correlation is argued and sourced), regenerate the whole table, and re-derive §6.2's denominators from it. Also: close the Departure 7 loophole (phase and inertia may not be fitted to feedback either, and say so in the prohibition row so the test can be written); derive or delete the ±3.5 h sleep-debt band; correct σ_phase for MAE→SD (×1.253) and justify — or widen — the ±1.0 h regular-sleeper figure given that the method is sleep-midpoint, not Kronauer; specify the level clamp and state in §1.6 that "High" and "Drained" are effectively unreachable for a normal sleeper; and re-read the two "sits inside" sentences in §1.4 and §2.2 against docs/privacy-and-ip.md.

What survives untouched and should be said so: the vendor-composite refusal with Doherty 2025 attached, the stage-accuracy refusal, the GLP-1 structural-unanswerability ruling, the named refusal of the multi-day alcohol HRV claim, the hatched no-value inertia region, U off by default, and §5's prohibition table as a mechanism. The honesty machinery in this design is good. The arithmetic it prints is not, and the arithmetic is what reaches the reader.

### Verdict: **needs-rework**

**Fatal:**
- THE NUMBER STOPS BEING A HEALTH SIGNAL AND BECOMES A CLOCK. §2.2 is explicit: the entire weight-bearing input set is `.sleepDurationHours`, `.sleepOnset` and a parameter (`learnedSleepNeed`, declared "0 — it is a parameter, not a term"). Every measurement taken after the reader wakes up — heart rate, active energy, steps, HRV, gait, Oura stress — is at weight 0 by §2.3. So level(t) = f(wake time, last night's duration, clock). Nothing the reader does between waking and 11pm can move it. The card is still titled Energy, still headlined "how much have you got today", still sits on the Today tab, and §1.6 keeps the reservoir *fill* — an encoding whose whole meaning is "this is being spent as you go". A drawing that says "you spent this" over arithmetic that only knows what time it is, is the shipped-defect class this repo's rules exist for: modelled dressed as measured, one level up. Compare the shipped card, which at least reads `activeEnergyBurned` and intraday `heartRate` (Energy.swift:168-180). The redesign deletes the card's only measured intraday content and keeps the picture that implied it.
- TWO OF THE FOUR BANDS §1.6 SAYS TO KEEP ARE UNREACHABLE UNDER THE DESIGN'S OWN PARAMETERS. Its worked day (§1.5) peaks at **69** at the 16:00 acrophase after a full night — the `High` threshold in `Energy.swift` is **70** — and troughs at **43** at 23:00, against a `Drained` threshold of **25**. So the visible output of a well-slept day is "Steady" from wake until roughly 20:00, then "Running low", every single day. The design leans on the bands as its honesty mechanism ("the band word is roughly at the model's own resolution") while shipping a four-band dial in which two bands can never light and the one transition is set by the clock. Either the bands are recalibrated to the new range or the argument in §1.6 is withdrawn; as written it dresses a two-state clock as a four-state dial.
- §3 REBUILDS A SHIPPED CARD AND NEVER MENTIONS IT. `InsightID.substanceImpact` exists (Insight.swift:31). `SubstanceImpactInsight` (InsightKit/Sources/InsightKit/Substances/SubstanceImpactInsight.swift:16) is a first-class model whose `contributions` is `[.substanceLog]` and whose `candidateMetrics` is `SubstanceResponseAnalyzer.comparedMetrics`. `SubstanceResponseAnalyzer` already does episode-gated before/after comparison of nights following use against a clean-night baseline over six signals, with `afterWindow = 18 h`, `comparisonWindowDays = 90`, a decaying `SubstanceLoad` and `alternativeExplanation` on every row. The design's ~4,000-word §3 cites `SubstanceEpisodes.swift`, `Substance.swift` and `SubstanceLoad.swift` — the files either side of it — and names neither the analyser nor the card. S6 even calls `InsightEngine.withSubstanceLog` an "existing precedent" without saying that the precedent IS the card that already answers this question. Shipped as designed, the app carries two different answers to "what does alcohol do to me": the analyser's flat 18 h window on Substance Impact, and per-class τ kernels (caffeine 5 h, nicotine two nights with a sign flip) on Energy. Two cards disagreeing about one question is exactly what `docs/backlog.md` B18-7 forbids ("Build them against one model rather than two") and what CLAUDE.md's "Check before you Write" rule exists to catch.
- §3's OUTCOMES ARE SLEEP OUTCOMES, DRAWN UNDER AN ALERTNESS HEADLINE THAT §3.3 SAYS CAN NEVER RESPOND TO THEM. Every published effect in §3.2 is pointed at TST, sleep efficiency, REM, RMSSD or nocturnal HR — caffeine −45 min TST, alcohol RMSSD −21.3%, nicotine −14 min TST, cannabis REM −33.9 min, stimulant TST −0.59 SD. Not one is in KSS or alertness units, and §3.3 states the prior "is never added to the alertness number". So the card draws a substance→sleep analysis directly beneath a curve that structurally cannot account for it. A reader seeing "caffeine costs you 45 minutes" under an energy curve will read the curve as having priced it in. That is an implied confidence the design forbids everywhere else, and it is only avoidable by putting these rows on the card whose subject they are.

**Serious:**
- THE OVERLAP CENSUS, COUNTED. Weight-bearing: 2. `.sleepDurationHours` is already a weighted term on Sleep (plus `sleepDebt` at 12% and consistency at 8%, SleepInsight.swift:505-512), a component of Readiness (ReadinessScore.swift:100-104) and a channel of Stress load at weight 0.5 (SustainedLoadInsight.swift:54). `.sleepOnset` is already the Sleep card's, via `CircadianConsistencyModel` → the `bedtimeSpread` and `socialJetlag` derived outputs (SleepInsight.swift:562-572) — and Departure 3 reads that exact series, `sleep.bedtimeSpread`, to pick its phase error. Energy-v2 takes two metrics that three cards already score and gives them 100% of its own number.
- THE REDESIGN THROWS AWAY THE ONE THING NOTHING ELSE HAS. Across `Insights/`, `.heartRate` is read by exactly two models (Energy, VitalSigns) and `.activeEnergyBurned` by four — but Energy is the *only* card on the fleet whose number moves within a day. Readiness is a morning snapshot, Sleep is per-night, Stress load is 28 d vs 90 d, the radar is 3 d vs 21 d. "How much have you got at 3pm" is a genuine gap. The redesign answers it by demoting both intraday measurements to a weight-0 strip (§2.3, S5 "drawn beneath, never summed") and filling the gap with a cosine. It trades the card's only non-overlapping property for a re-render.
- READINESS AND ENERGY WILL CONTRADICT EACH OTHER ON THE SAME MORNING, AND THE DESIGN HAS NO RECONCILIATION RULE. `docs/card-sections.md:1137` already records that these are the two cards that score *today*. After S2 they score the same night by two incompatible methods: Readiness judges HRV, RHR, sleep, temp and respiration against the reader's OWN 28-day baseline ("which is what makes it personal", ReadinessScore.swift:6-8); Energy-v2 judges duration alone against a 136-aircrew population fit with a between-subject intercept SD of 0.84 KSS (±10.5 points) that §4.1 says never drops without 12 PVT sessions. On a morning where the reader slept 7.5 h but their HRV is 1.5 SD down, Readiness will say one thing and Energy the opposite, both on the Today tab, both about last night.
- S8 IS THE STRESS LOAD CARD'S QUESTION ON THE WRONG CARD. A resting-HR *level shift across a treatment epoch of weeks* against a published +2.05 bpm is precisely `SustainedLoadModel`: 28 days vs 90, channels `.restingHeartRate` (weight 0.9), `.heartRateVariabilityRMSSD` (1.0), `.respiratoryRate`, `.sleepDurationHours`. Putting a multi-week RHR shift on the card whose stated question is "how much have you got today" is the overlap that card's own header (SustainedLoadInsight.swift:12-24) was written to prevent.
- S9 MAKES ENERGY A FOURTH STRESS READING. `SustainedLoadInsight`'s doc comment carries the three-card table — Readiness/today, radar/acute, sustained/weeks — and names overlap as *the* trap the reader themselves flagged on 2026-08-03. S9 relays Oura `daily_stress.stress_high` and `recovery_high` (89/90 days) onto Energy. Even relayed at weight 0, that is a daily stress verdict on a card that is not the stress card. If the relay is worth having — and it may be — it belongs on `sustainedLoad`, where its self-normalising quartile definition can be contrasted with a number built from the reader's own 90-day window.
- THE CARD ENDS UP ANSWERING FOUR OTHER CARDS' QUESTIONS AND LOSING ITS OWN. Counted from §2.3 and §7: symptom radar's verdict (S10, admitted relay), Oura stress (S9 → Stress load's territory), a weeks-scale RHR epoch (S8 → Stress load's window), substance→night effects (§3 → Substance Impact), the gait triple (→ `GaitInsight`, and §2.3 concedes "no published within-day gait-slowing→alertness curve exists"), `workImpact.workExposure` (→ the Work impact card), the holiday ledger, and ~20 weight-0 rows in total. Two weighted inputs owned by three other cards, twenty unweighted rows relayed from five more. That is not a card, it is a tab.
- THE DESIGN CONCEDES THE VERDICT IN §4.1 AND DOESN'T FOLLOW IT. "σ_model alone is 1.42 of the 1.68 — 72% of the total, 85% of the variance. Adding data sources does not narrow this ribbon." Combined with §1.5's 26-point diurnal swing against a ±21-point 1 SD ribbon: the number cannot distinguish 07:00 from 16:00 at 1 SD, let alone Tuesday from Wednesday. Once you accept both sentences, the question the lens asks answers itself — what is left that a *section* could not carry?
- THE ONE NUMBER THAT DECIDES WHETHER THIS IS A HEALTH CARD IS MISSING. Nowhere does the document state how far an hour more or less sleep moves the new level. On its own cited within-person coefficient (Kuula/Bauducco β = −0.19 KSS/h) and its own transform (12.5 points per KSS), it is **~2.4 points per hour** — 11% of the ±21 ribbon and 9% of the clock-driven 26-point swing. If that is right, the clock outweighs the only health input by roughly ten to one, and §0's whole framing ("sleep duration is roughly four times too strong") has been applied without checking what it leaves behind. This figure must be computed from the resolved Process S before S1, not after.
- `AlertnessModel` IS WANTED BY THE SLEEP CARD, BY NAME. `docs/backlog.md` B18-7 (sleep debt section) says: "`EnergyModel` already reasons about homeostatic pressure — so the published two-process framework the Energy rebuild (`B19`) is researching is the same literature this section needs. **Build them against one model rather than two**." B18-8 (ideal sleep timeframe) needs the same phase machinery and already has `fittedCentre`. Three backlog items want one model; the design builds it inside Energy and mentions neither.
- THE DESIGN NEVER TELLS THE READER SUBSTANCE IMPACT EXISTS. They asked for substances "in Energy". The honest reply to that is "you already have a card for this — here is why the analysis stays there and how Energy links to it", not a silent parallel build in the same repo. As it stands the document would have the reader approve rebuilding something they already own without knowing they own it.
- DEPARTURE 5 AND THE OPEN DECISION ABOUT IT DESCRIBE A CARD WITH NOTHING TO SAY. Sleep debt is shown but forbidden from entering the curve (correctly, per Van Dongen 2004). But `sleepDebtHours` is already a Sleep-card derived output at 12% of that card's weight. So Energy would display Sleep's figure, at weight 0, next to a number it is not allowed to affect — the design's own listed open decision ("this will look like a bug to anyone who expects it to") is the reader discovering the card is a viewer for another card's numbers.

**Required changes:** Three edits, in order.

1. MOVE THE MODEL TO THE SLEEP CARD. `AlertnessModel` (S1) is a published transform of last night's sleep timing against the clock — that is a Sleep-card section titled "what last night means for today", and it is the same model B18-7 and B18-8 already need. Build it once, behind `sleep`. Sections S0, S1, S3 and S4 all survive intact under that heading; only their destination changes. The Sleep card already owns every input the model reads.

2. GIVE §3 BACK TO SUBSTANCE IMPACT. The per-class `SubstancePrior` (τ, window, direction, published effect, `nil` where none), the n = 7.85/d² episode counter and the per-class `CoverageGate` are the best part of this document and they belong on `InsightID.substanceImpact`, replacing `SubstanceResponseAnalyzer.afterWindow`'s flat 18 h with per-class windows and giving `minimumEpisodesToDescribe = 3` the power calculation it currently lacks. Read `SubstanceImpactInsight.swift` and `SubstanceResponseAnalyzer.swift` before writing a line. One model, one card. Then answer the reader plainly: their substance question is already a card, it is about to get much better, and Energy cannot host it because §3.3 forbids the prior from touching the number.

3. DECIDE WHAT ENERGY IS FOR, THEN KEEP ONLY THAT. It has one defensible claim to exist: it is the fleet's only intraday card. If it keeps that, its subject must be a *measured* intraday quantity in its own units — the exertion layer of S5 (Oura `resting_time`/`sedentary_time`, active kcal, steps), drawn honestly, with no 0–100 dial and no alertness curve on top of it. If it does not keep that, retire the card and let the Sleep section carry the model. Either way: drop S8 (route the GLP-1 epoch shift to `sustainedLoad`, whose 28/90 window it is), drop S9 (route the Oura stress relay to `sustainedLoad`), drop the gait strip (`GaitInsight` owns it, and the design concedes there is no published curve). S10's radar relay can stay wherever the card lands — it is one sentence and it is honest.

Before any of this: resolve §1.3 against Ingre 2014, then compute points-per-hour-of-sleep under the corrected Process S and put it in the document. If it lands near 2.4, the card's health content is one tenth of its clock content and that fact changes the answer to question 3.
