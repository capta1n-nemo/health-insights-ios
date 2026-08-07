# Cycle phase and ovulation from longitudinal temperature — the published evidence

_Researched 2026-08-07 for backlog `B2-17` / `R60`, answering the reader's ask:
**"make our Cycle feature world class… use ALL of the data… even recommend days
we think are ovulation… basically use data to reduce any or all input."**_

⚠️ **Partial.** This is one stream of a four-part brief that was stopped when the
session ended. **Algorithms and classic methods are covered; ovulation-detection
device accuracy, failure modes (PCOS, perimenopause, contraception), competitor
claims and the minimum-input question are NOT.** Re-run those from `R60`.

⚠️ **Provenance rule this document follows:** everything below was read from an
abstract, PubMed record or open-access full text. Where a number lives only
behind a paywall it is marked **not obtained** rather than guessed. Two
search-snippet claims were deliberately *not* promoted to findings. That
discipline matters here — a design was refuted earlier the same day for printing
a statistic that existed nowhere.

---

## The load-bearing conclusion

> **Every temperature-only method is RETROSPECTIVE and lands ~2–3 days late.**
> Carter & Blight: detection 2.58 days after the shift (SD 1.31, n=41). Hurst
> 2022: three-over-six marks ovulation **3.26 days late** on average (n=80, 205
> cycles).
>
> **Same-cycle measurement buys the accuracy; prior cycles mostly buy a prior.**
> Oura against ovulation kits: **1.26 days** mean error, against the calendar
> method's **3.44 days** (Thigpen 2025, n=964, 1,155 cycles). And 12 cycles of
> personal history *alone* only reaches **60% within ±3 days** (Hurst).

**So the reader's ask splits in two, and the honest answers differ:**

- *"Recommend days we think are ovulation"* — **defensible retrospectively**, at
  ~1.3 days error with ring temperature. **Prospectively it is far weaker**, and
  the app must not present the two as the same claim.
- *"Reduce any or all input"* — **yes for confirmation** (temperature is
  automatic), **no for the prospective fertile window**, where the only strongly
  prospective indicator in the literature is **cervical mucus**, which is
  logged, not sensed (Ecochard 2015: peak mucus 96% sensitive for the 6-day
  fertile window, n=107, daily ultrasound reference).

---

## 1. Why "count back 14 days" fails, with numbers

| Study | n | Follicular | Luteal |
|---|---|---|---|
| Lenton 1984 | 327 luteal / 293 cycles | 12.9 geo. mean (95% 10.3–16.3) | **14.13 ± 1.41** |
| Fehring 2006 | 141 women, 1,060 cycles | 16.5 ± 3.4 | 12.4 (95% CI 8–17) |
| **Bull 2019** | **124,648 users, 612,613 cycles** | **16.9 ± 5.3** | **12.4 ± 2.4** |
| Symul 2019 | 759,078 standard cycles | median 16 | median 12–13; **~20% ≤10 days** |
| Berglund Scherwitzl 2015 | 317 women, 1,501 cycles | — | **within-user variation 1.25 days** |

1. **The luteal phase is the *more* constant phase but is not constant.** SD 2.4
   days across 612k cycles. Follicular SD is **5.3** — the folk claim is
   directionally right and quantitatively wrong by ~2×.
2. ⚠️ **Within-user luteal variation (1.25 d) is about half the between-user SD
   (2.4 d).** **This is the single strongest argument for a personal prior** —
   most population spread is between women, not within one.
3. **Only ~24% of ovulations fall on days 14–15**; 90% span cycle days 10–24
   (Symul). Only **13%** of cycles are 28 days (Bull).
4. **The errors compound, and the compounding is empirically confirmed.**
   Next-period prediction is ~1.5 d median error *after 10 prior cycles* (Li
   2022, 186,106 users / 2,047,166 cycles) ⊕ luteal SD 2.4 d ≈ ±3 days — which
   matches the measured calendar-method error of **3.44 days**. That
   correspondence is the cleanest validation of the whole chain.

---

## 2. Classic rules — and the failure mode that transfers

**Döring 1967** (n=966 women, **59,566 cycles**): strict rule Pearl index **0.8**;
combination rule **3.1**.

⚠️ **The most transferable finding in the classic literature:** of the method
failures, **~40% were incomplete temperature recording, not algorithm error**.
For a wearable app that reads temperature automatically, *this is the failure
mode the hardware removes* — and it is the strongest argument that automation
helps here.

**Three-over-six**, against an instrumented reference (Hurst 2022, n=80/205):

| Method | ±1 day | ±3 days | Mean offset |
|---|---|---|---|
| BBT three-over-six | 62.9% | 79% | **−3.26 d (late)** |
| Skin-worn axillary | 65% | 90% | −1.51 d |

⚠️ **Two incompatible definitions of "three-over-six" circulate** (0.2 °C European
vs 0.2 °F/0.1 °C US with one ≥0.4 °F). Pick one and say which.

⚠️ **Site substitution destroys the signal** — sublingual, rectal and ear all had
ICC(2,1) < 0.4 against continuous intravaginal (Nolte 2026, n=17).

**Sympto-thermal** (Frank-Herrmann 2007, n=900 women, 17,638 cycles): perfect use
**0.6**, typical use **1.8** per 100 women per 13 cycles — but **9.2 per 100 women
dropped out from dissatisfaction with the method.** That dropout number is the
one a "reduce all input" design should hold on to.

---

## 3. Modern devices — measured accuracy

| Study | Device | n | Reference | Result |
|---|---|---|---|---|
| **Thigpen 2025** | **Oura** | 964 women, 1,155 cycles | ovulation kits | detected **96.4%**; **MAE 1.26 d** vs calendar **3.44 d** (P<.001). **1.7 d on abnormally long cycles**; worse on short cycles (OR 3.56) |
| Maijala 2019 | Oura | 22 women, ~115 d each | urinary LH | luteal−follicular ΔT **0.30 °C ± 0.12** (skin) vs 0.23 ± 0.09 (oral); ovulation sensitivity **83.3%**; offset **0.6 d ± 1.5** |
| Goodale 2019 | Ava (temp, HR, HRV, resp) | 237 women, 708 cycles | urinary LH | fertile window **90% accuracy** (95% CI 0.89–0.92); claimed **prospective** |
| Niggli 2023 | wrist device | 61/205 clinical + 3,268/6,081 real-world | ovulation tests | retrospective mean error **0.31 d**; **75.4% retrospective vs 73.8% prospective** of fertile days within ±2 d |
| Shpaichler 2025 | axillary armband | 125 women, 194 cycles | Clearblue | sens **96.8%**, spec **99.1%** — **retrospective** |
| Berglund Scherwitzl 2016 | Natural Cycles | 4,054 women, 2,085 woman-yr | pregnancy | typical-use Pearl **7.0**, perfect-use **0.5**; of 143 unplanned pregnancies, **10 were the algorithm calling a fertile day safe** |

⚠️ **No published validation of Apple Watch or Fitbit wrist temperature for
ovulation exists** — confirmed by a 2022 review (Uchida, J Therm Biol). Apple's
published work here is epidemiological, not algorithmic. **Clearblue's and
OvuSense's algorithms are unpublished.** *This is the "do it better" benchmark:
most of the field publishes no accuracy figure at all.*

---

## 4. Algorithms worth building on

- **Bayesian change-point (Carter & Blight 1981)** — the most useful old paper.
  Detection 2.58 d late (SD 1.31); on *estrogen* it predicts **3.55 d before the
  LH peak**. ⚠️ And in 1981 it already proposed **accumulating a specific woman's
  observations into an aggregate prior** — the hierarchical scheme this app
  needs, forty years early.
- **HSMM (Symul & Holmes 2022, IEEE JBHI)** — **98%** on simulated data with no
  missingness, **90%** with realistic missingness, **93%** on partially-labelled
  real series. Public `HiddenSemiMarkov` R package. ⚠️ Hidden-state count, n, and
  cycle-length MAE are all **not obtained** (paywalled).
- **State-space / sequential Bayesian filtering (Fukaya 2017, Stat Med)** — the
  closest published thing to a Kalman filter over BBT, giving a sequentially
  updated predictive distribution for the next menses. ⚠️ **MAE, n and
  missing-data policy not obtained.**
- **Adherence-aware prediction (Li 2022, JAMIA)** — explicitly models the
  probability the user **skipped tracking** rather than treating a gap as a real
  cycle. Median AE ~1.5 d. Beats CNN/RNN/LSTM, *especially* past cycle day 29
  (RMSE 11.77 vs 21.92 at day 40). ⚠️ **Directly relevant to "reduce input":
  the winning model is the one that models absence.**
- **CUSUM (Royston & Abrams 1980)** — n=137 charts/21 women, detected the shift
  in all cases, but graded against the chart itself, so no independent day error.
  ⚠️ This app already runs CUSUM in the symptom radar; the machinery exists.
- ❌ **PELT applied to BBT: no publication found.**

---

## 5. ⚠️ The gap that matters most, and it is unpublished

**No published learning curve — accuracy against number of prior cycles — exists
for any of these models.** Searched Li 2022, Symul & Holmes 2022, Fukaya 2017,
Hurst 2022, Bull 2019. This is a genuine gap, not a search failure.

What *is* published are hard requirements: Li needs **10 prior cycles**; Bull
required **≥6**; Hurst's historical predictor uses **up to 12** and still only
reaches 60% at ±3 days. Symul's users logged **>16 days per cycle**, with a
stated minimum of 8–12.

⚠️ **And a finding that constrains any "it gets better as you log" promise:**
Li 2020 (378,000+ users, 4.9M cycles) found cycle and period length statistics
are **stationary over the app usage timeline** — a user's variability class does
*not* settle down with tenure. **The app must not imply that logging longer will
narrow someone's intrinsic variability.**

---

## 6. Prospective vs retrospective — the table to design from

| Method | Direction | When the answer arrives |
|---|---|---|
| Döring / three-over-six / CUSUM | **Retrospective only** | 3rd elevated day — **2.6–3.3 d after ovulation** |
| Bayesian change-point on BBT | Retrospective | 2.58 d ± 1.31 after the shift |
| Bayesian change-point on **estrogen** | **Prospective** | 3.55 d ± 1.46 before LH peak — needs an assay |
| **Cervical mucus (Ecochard 2015)** | **Prospective** | peak mucus **96%** sensitive for the 6-day window; preceded it in <10% of cycles |
| Calendar / Standard Days | Prospective, population prior | fixed days 8–19; **MAE 3.44 d** |
| Oura / Natural Cycles / axillary | **Retrospective dating** | temperature lags first positive LH by **1.9 d** |
| Ava | Claimed prospective | 90% fertile-window accuracy; independent check 73.8% prospective vs 75.4% retrospective |
| HSMM | **Retrospective labelling** | a segmentation method over completed records, not a forecaster |

---

## 7. What this means for the build

1. **Separate the two claims on screen.** "Ovulation was probably on the 14th"
   (retrospective, ±1.3 d with the ring) is a *different statement* from "your
   fertile window is likely to open on the 11th" (prospective, much weaker).
   Conflating them is the honesty failure this feature is most exposed to.
2. **The personal prior is worth real effort** — within-user luteal variation is
   half the between-user SD.
3. **Model absence explicitly.** The best next-period model wins by modelling
   skipped tracking, and Döring's failures were 40% recording gaps.
4. **State the error in days, always.** The field mostly publishes nothing;
   printing ±1.3 days with its source would be more than Oura, Apple or Flo do.
5. ⚠️ **`CyclePhaseModel.notContraceptionNotice` stays**, and these numbers are
   why: Natural Cycles' *perfect-use* Pearl index is 0.5 and **10 of 143
   unplanned pregnancies were the algorithm calling a fertile day safe.**

## Explicitly not obtained

Frank-Herrmann's fertile-days-per-cycle · Fehring's luteal SD · Bull's
>7-day-variation fraction · Fukaya's MAE/n · Symul & Holmes' state count and MAE
· the Standard Days exclusion fraction · any Ogino-Knaus primary failure rate ·
PELT-on-BBT · Clearblue/OvuSense algorithms · any Apple/Fitbit ovulation
validation · **any learning curve vs prior-cycle count.**

Two search snippets were rejected rather than cited: a "357/437 cycles (82%)"
three-over-six figure, and a claim that Ecochard showed BBT rising 2–3 days
*before* ovulation. Neither traced to a source.
