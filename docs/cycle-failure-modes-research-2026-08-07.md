# Who wearable cycle inference fails for — the failure modes

_Researched 2026-08-07 for `B2-17` / `R60`. Companion to
`docs/cycle-algorithms-research-2026-08-07.md`._

**Confidence key: ✅ read from the paper/abstract/label this session · ⚠️ from a
database record at one remove, verify before shipping · ❌ searched, no published
evidence found.**

---

## ⚠️ Three findings to read before anything else

### 1. Pregnancy produces exactly the luteal shift, sustained
**Adaimi et al., JMIR mHealth uHealth 2025 ✅ — n=10,318 pregnancies (Oura).**
Temperature rises become evident by **week 4** and peak at **+0.3 °C above
baseline by week 9**.

The luteal shift is **+0.29–0.33 °C**. **Magnitude cannot distinguish them —
only duration can.** So a feature that says "you're in your luteal phase" will
say it to a newly pregnant user for weeks, and a next-period prediction will be
wrong in the way that hurts most. **This is the highest-harm failure in the
whole list and it is not silent — it is affirmatively wrong and emotionally
loaded.**

### 2. Tirzepatide × oral contraceptives — and the reader takes tirzepatide
**MOUNJARO US Prescribing Information §7.2, §12.3 ✅ (verbatim from DailyMed):**
> *"Advise patients using oral hormonal contraceptives to switch to a non-oral
> contraceptive method or add a barrier method of contraception for **4 weeks
> after initiation and for 4 weeks after each dose escalation**."*

Single 5 mg dose with EE/norgestimate: **ethinyl estradiol Cmax −59%, AUC −20%;
norelgestromin AUC −23%; tmax delayed 2.5–4.5 h.**

⚠️ **Semaglutide does NOT share this.** Jordy et al., Clin Pharmacokinet 2021,
n=25 ✅ — oral semaglutide left EE and levonorgestrel AUC unaffected (ratios 1.06).

**So the behaviour is drug-specific, not class-wide. Getting it backwards in
either direction is real-world harm.** This is the evidence behind backlog Q17,
which the reader already answered **yes** to surfacing.

### 3. The distal signal is not smaller — it is noisier
A common premise, corrected. **Zhu 2021 ✅ (n=57, 193 cycles):**

| Site | Follicular | Luteal | Δ | Night-to-night SD |
|---|---|---|---|---|
| Wrist skin | 35.78 | 36.07 | **+0.29 °C** | **0.34** |
| Oral BBT | 36.25 | 36.51 | **+0.26 °C** | **0.16** |

The shift is ~1.6 SD for oral BBT and only **~0.85 SD** at the wrist. **Distal
sensors win on sampling density, not signal size.** Oura finger: +0.30 °C
(SD 0.12) vs oral +0.23 (SD 0.09) — Maijala 2019 ✅.

⚠️ And the shift is **not a step**: Gombert-Labedens 2024 (n=120) found a cosinor
oscillation fits better than a biphasic square wave. **There is no crisp "shift
day" to name.**

---

## INVALID — the referent does not exist; disable or hard-caveat

| Condition | Base rate | Detectable in-app? |
|---|---|---|
| **Anovulatory cycle in a normal-looking cycle** | **5.5–12.8%** healthy/regular (BioCycle, n=259 ✅); up to **36.7%** at mean age 41.7 (HUNT3, n=1,545 ✅) | **No — bleeding is unchanged.** Alzueta 2024 ✅: **17.2% (20/116)** of healthy women showed no detectable oscillation at all |
| **Ovulation-suppressing contraception** (COC, implant, DMPA, most POPs) | — | User-declared. ⚠️ **COCs sit tonically +0.4 to +0.6 °C above follicular baseline** (Baker 2001 ✅) — a *level* rule reads "luteal" forever; a *shift* rule finds nothing. **Neither is a correct answer.** |
| **Hormonal IUD (LNG-IUS)** | — | ❌ **No published wearable evidence either way.** Users often still ovulate and bleeding is unreliable. **Unknown, not "works".** |
| **PCOS with oligo/anovulation** | **12.1%** meet Rotterdam (95% CI 9.8–14.8, Neven 2026 ✅); **~80%** of those are phenotype A/B/D ⚠️ | ❌ **No study validates temperature ovulation detection in PCOS** |
| **Pregnancy** | — | See above. Duration only. |
| **Lactational amenorrhoea / postpartum** | — | ❌ No published evidence at all |
| **Late menopausal transition (STRAW −1)** | amenorrhoea ≥60 d | ✅ Yes, from cycle history |
| **Fever spanning the peri-ovulatory window** | — | Yes. **Not additive noise — it replaces the measured quantity.** |

⚠️ **The wearable literature has EXCLUDED these populations rather than studied
them.** Maijala enrolled 31 and dropped the 8 hormonal-contraception users to
reach n=22 ✅; Apple's study excluded hormonal contraception ✅; Shilaih excluded
frequent time-zone crossers ✅. **Absence of evidence here is a selection
artefact, not reassurance.**

---

## NOISIER — run with widened uncertainty

| Perturbation | Published magnitude |
|---|---|
| **Early menopause transition (STRAW −2)** | **≥7 d difference between consecutive cycles**, recurring within 10 — directly implementable, and it comes from the staging standard (Harlow 2012 ✅) not an app heuristic |
| **Alcohol** | RHR **+2.8 bpm**, HRV **−3.8 ms** per drink above personal average (WHOOP, **n=20,968** ✅). ❌ **Temperature effect unpublished — flag via HR, never claim a °C** |
| **Night shift** | phase delay **46 ± 33 min** ⚠️ — comparable to the between-night jitter these algorithms rely on |
| **BMI > 30** | excluding 2 obese participants improved missed ovulations **5.1% → 2.8%** (Maijala ✅, small n) |
| **Short / long cycles** | detection OR **3.56** worse in short cycles; error **1.7 vs 1.18 d** in long ones (Thigpen 2025 ✅) |
| **Travel, ambient temperature, exercise, late meals** | ❌ **all unpublished** — see gaps |

⚠️ **The averaging window matters more than most confounders.** Sleep-onset
vasodilation dominates a distal signal. Shilaih discards the first 90 and last 30
minutes of sleep ✅; Apple requires ≥4 h wear asleep ✅; Zhu requires ≥4 h
uninterrupted ✅. **Get the window wrong and it swamps everything in this table.**

---

## GLP-1s can move a user from INVALID to VALID mid-use

⚠️ Carmina & Longo 2026 (n=96 PCOS, BMI>25): six months of semaglutide restored
**ovulatory cycles in 52.5%** of previously anovulatory women. Alnaimi 2026
meta-analysis (7 trials, n=575): pregnancy **35% vs 15%**.

**Design consequence: a one-time "you have PCOS, this feature is off" gate is
wrong.** The gate must be re-evaluable — and the transition matters clinically,
because it means unexpected fertility restoration.

⚠️ Semaglutide and tirzepatide require an **8–10 week washout before
conception** ⚠️.

---

## Missing data: thresholds exist, a curve does not

❌ **No published wear-rate sensitivity analysis.** Every study states a
threshold; none justifies it or reports degradation below it.

| Study | Requirement | Consequence |
|---|---|---|
| Zhu 2021 ✅ | cycle dropped if ≥30% missing | **73/266 cycles (27.4%) dropped** |
| Shilaih 2018 ✅ | ≥80% of days across the fertile→early-luteal span | — |
| Apple 2025 ✅ | ≥4 h wear asleep | **~19.5% of cycles produced no ≥0.2 °C signal** |

**Defensible working rule: ≥70% of nights, contiguous across ~day −5 to +5, ≥4 h
sleep per counted night — and say plainly it is assembled from exclusion
criteria, not from a published dose-response.**

---

## Ceiling performance, for calibration

| Study | Device | n | Result |
|---|---|---|---|
| Thigpen 2025 ✅ | Oura | 964 women / 1,155 **ovulatory** cycles | detected **96.4%**, MAE **1.26 d** — *this is the ceiling, not the field rate* |
| Wang 2025 ✅ | Apple Watch | 260 / 889 cycles, **anovulatory NOT excluded** | completed cycles MAE **1.22 d**, 89.0% within ±2 d; **only ~80.5% produced a ≥0.2 °C signal**; simulated **false-positive 8–15%** |
| Zhu 2021 ✅ | wrist vs oral | 193 cycles | wrist **TPR 54.9%** / FPR 8.8%; oral **TPR 20.2%** / FPR 3.6% |

---

## ❌ Where the evidence genuinely does not exist

State these as gaps rather than filling them with plausible numbers:

1. Alcohol's effect on nocturnal skin temperature in °C.
2. **Ambient/room temperature as a slope (°C skin per °C ambient)** — *the most
   consequential gap for a distal-sensor product.* **Do not claim robustness to
   room temperature; there is no citable slope.**
3. Time-zone change on the nocturnal nadir.
4. Evening exercise and late meals on nocturnal distal temperature.
5. **Any validation in PCOS, perimenopause, lactational amenorrhoea, or under
   LNG-IUS / implant / POP.**
6. Any wear-rate degradation curve.
7. GLP-1 effects on the wearable temperature signal itself.

⚠️ Also flagged as unverified and **not** to be quoted: March 2010 / Bozdag 2016
PCOS prevalence (use Neven 2026 instead), Metcalf 1979 perimenopausal
percentages, the °C magnitude in Smarr 2020, and Shilaih's assertion that the
signal is *"impervious to lifestyle factors, like having sex, alcohol, or eating
prior to bed"* — that is a discussion claim, not a controlled test.
