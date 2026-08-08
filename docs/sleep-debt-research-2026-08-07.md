# Sleep debt: definitions, baselines and what is actually defensible

<!-- status: complete — there is no defensible individual sleep-need estimator from free-living wearable data — an open problem, not a search gap; the honest section is deviation-from-your-own-typical -->

*Research document for `B18-7` (a sleep debt section). Written 2026-08-07. No app code was changed.*

---

## Summary

Sleep debt is not one construct with one number. The literature contains at least four mutually incompatible definitions, and the one thing they all agree on is that the answer is dominated by the *baseline* — the sleep need you subtract nightly duration from — not by the sleep measurement. Van Dongen et al. (2003) estimated that baseline directly from performance data and got 8.16 h/night with a standard error of 0.73 h **and a between-person standard deviation of 3.58 h**; that between-person spread is the whole problem. Using the reader's own measured data (68 of the last 90 nights present, two sources disagreeing by an RMS of 1.33 h on nights both report), I derive an error of roughly **±11 h on any 14-night cumulative debt figure this app could compute today**, of which ±10.2 h comes from the baseline alone and grows *linearly* with the window while the measurement noise grows as √n. On the starred question: **there is no defensible individual sleep-need estimator from longitudinal wearable data, and this is an open problem, not a gap in my search.** Every validated estimate of individual sleep need in the literature requires an imposed multi-night sleep-extension protocol (9 nights at 12 h time in bed in Kitamura et al. 2016; 12 h night plus 4 h afternoon in Klerman & Dijk 2008). Free-living wearable data contains no such protocol, and the two intuitive substitutes both fail: setting baseline = habitual duration makes long-run debt *identically zero by construction*, and setting it = free-day/best-day duration inverts on this reader, whose weekend nights are on average 0.72 h **shorter** than weekday nights. The defensible section is therefore a *deviation-from-your-own-recent-typical* display with a printed band and an honest label — plus WHOOP/Oura-style "sleep need" figures **relayed** as labelled second opinions and never blended into ours.

---

## 1. Four definitions, and they do not agree

| # | Definition | Baseline used | Primary source | What it is good for |
|---|---|---|---|---|
| 1 | **Cumulative sleep loss** = Σ(need − obtained) | a *published* or *estimated* daily need | Van Dongen et al. 2003 (Fig. 3B, 4A) | Intuitive; **fails** to reconcile chronic restriction with total deprivation |
| 2 | **Cumulative excess wakefulness** = Σ(hours awake beyond a critical wake period ξ) | ξ, a critical *wake* duration estimated from the data (15.84 ± 0.73 h) | Van Dongen et al. 2003 (eqs. 3a/3b, Fig. 4B) | The only construct in that paper that fitted both restriction and deprivation with one function (83.0% of PVT variance) |
| 3 | **Potential sleep debt (PSD)** = optimal sleep duration − habitual sleep duration | OSD, the asymptote of an exponential fitted to 9 nights of 12 h time in bed | Kitamura et al. 2016 | The only *individually measured* need in the literature; requires a lab |
| 4 | **Workday/free-day discrepancy** (the social-jetlag family) | free-day sleep, treated as unrestricted | Wittmann et al. 2006 | Epidemiology of chronotype; **not** a physiological debt |

The definitional split matters more than it looks. In Van Dongen et al. 2003, cumulative sleep loss after 14 days at 4 h TIB was *significantly greater* than after 3 days of total sleep deprivation (3-day TSD loss was 23.1 ± 2.6 h; t₂₀ = 10.58, P < 0.001) — yet PVT impairment in the 4 h group after 14 days **did not exceed** the 3-day deprivation group. Definition 1 therefore predicts the wrong ordering. Definition 2 fixes it by charging 24 h of "excess wakefulness" per sleepless day rather than ~8 h of "lost sleep".

**Consequence for us:** a card that sums missed hours against a nightly target is using definition 1, the one its own authors showed does not reconcile the data. If the section says "hours" it should say *hours of sleep below your own typical*, not "sleep debt", unless we are prepared to defend a need estimate.

---

## 2. The baseline problem, stated precisely

Van Dongen, Maislin, Mullington & Dinges (2003), *Sleep* 26(2):117–126. n = 48 randomised to 8 h TIB (n = 9), 6 h (n = 13), 4 h (n = 13) for 14 consecutive nights, plus 0 h for 3 days (n = 13), all under continuous laboratory control.

Fitting PVT lapses as a function of cumulative excess wakefulness with subject-specific random effects, they estimated:

- critical wake duration **ξ = 15.84 ± 0.73 h** (estimate ± s.e.) → implied daily sleep need **8.16 ± 0.73 h**
- **between-subject s.d. of ξ = 3.58 ± 1.19 h**
- curvature θ = 0.67 ± 0.05; the model explained **83.0%** of PVT variance

That 3.58 h s.d. is the number the whole feature turns on. **If we assign the population mean need to one individual, the expected error is of order 3.6 h/night.** Over a 14-night window that is ±50 h of "debt" — an order of magnitude larger than any debt worth reporting. Derivation is trivial and checkable: error per night ≈ σ_between = 3.58 h; over T nights the baseline error is T × σ, because the same wrong baseline is subtracted every night. It does **not** average down.

Two partial rescues appear in the same paper, and both are traps:

1. **Subject-specific ξ was close to habitual wake duration** — the difference was 0.1 ± 0.5 h (mean ± s.e.), t₂₃ = 0.17, P = 0.86. Tempting. But (a) those subject-specific ξ values were produced by empirical-Bayes estimation inside the model, which shrinks each person toward the group mean, so the agreement is partly imposed by the estimator rather than discovered *(my reading of their method, not a claim the authors make)*; and (b) more decisively, **if need := habitual duration, then Σ(need − obtained) → 0 by construction** over any window long enough to define "habitual". A habitual-baseline debt metric is a deviation-from-own-average detector wearing a physiological costume.
2. **Habitual sleep duration weakly predicts vulnerability**: partial correlation (controlling for condition) between pre-study sleep duration and the rate of PVT-lapse increase during restriction, r₃₂ = 0.29, P = 0.048 — i.e. those who habitually slept longest degraded fastest. Real, but r² ≈ 8%. It supports "habitual duration carries *some* information about need"; it does not support using it as a point estimate.

Kitamura et al. 2016 measured the bias directly: **habitual duration underestimates optimal duration by about an hour, and by a variable amount.**

Kitamura S, Katayose Y, Nakazaki K, et al. *Scientific Reports* 6:35812 (2016). n = 15 healthy men, 23.3 ± 2.1 y; 2 baseline nights at 8 h TIB, then **9 consecutive nights at 12 h TIB**, exponential decay fitted to nightly total sleep time to find each person's asymptote.

- optimal sleep duration (OSD) **8.41 ± 0.18 h**, range 7.29–9.26 h
- habitual sleep duration **7.37 ± 0.27 h**, range 5.82–8.89 h
- potential sleep debt (PSD) **1.04 ± 0.24 h**, range **−0.58 to +2.73 h**
- PSD correlated with objective sleepiness (MWT) better than habitual duration did: r = −0.486, P = 0.066; adjusted r = −0.544, P = 0.029

Note the range: one participant's habitual duration *exceeded* their optimal duration. There is no monotone mapping from habitual to need.

Klerman & Dijk (2008), *Current Biology*, "Age-related reduction in the maximal capacity for sleep": 18 older and 35 younger healthy adults given 12 h night + 4 h afternoon sleep opportunity for 3–7 days; younger adults slept ~8.7 h and older adults ~1.5 h less while being *less* sleepy. ⚠️ **I verified this paper's existence, design and n, but the 8.7 h / 1.5 h figures come from secondary summaries, not from the paper text — re-verify before putting either number in the app.** The design point stands regardless: measuring sleep capacity took a multi-day extension protocol covering two-thirds of the circadian cycle.

---

## 3. Dose-response of accumulated debt onto next-day performance

### PVT

Van Dongen 2003, over 14 days of restriction, fitting lapses as a function of days:

- significant differences among the 8/6/4 h conditions in rate of change: F₂,₃₀ = 3.67, P = 0.037 (PVT), F₂,₃₀ = 5.33, P = 0.010 (digit-symbol), F₂,₃₀ = 6.19, P = 0.006 (serial add/subtract)
- 8 h TIB group: rate of change not different from zero (t₃₀ = 0.77, P = 0.45)
- **curvature for PVT lapses across days: θ = 0.78 ± 0.04 — near-linear, no plateau within 14 days**
- endpoint equivalences: 14 days at **4 h** TIB ≈ **2 nights of total sleep deprivation** for lapses and working memory; 14 days at **6 h** TIB ≈ **1 night of total sleep deprivation**

Those two equivalences are the most communicable findings in this entire literature and require no arithmetic on our part.

For scale on the underlying effect: Lim & Dinges (2010), *Psychological Bulletin* 136(3):375–389, meta-analysis of 70 articles / 147 cognitive tests, found lapses in simple attention were the largest effect of short-term sleep deprivation, **g = 0.776** (the CI is printed in the source with a sign convention inconsistent with the point estimate: [−0.96, −0.60]), versus reasoning accuracy g = −0.125, CI [−0.27, 0.02], n.s.

### KSS — and the divergence that matters most for an app

Same study, same model, same units of curvature:

- KSS rate of change differed by condition: F₂,₃₀ = 7.76, P = 0.002
- **KSS curvature across days of restriction: θ = 0.16 ± 0.03 — strongly saturating**
- KSS curvature under total deprivation: θ = 0.81 ± 0.16 — near-linear
- 8 h group: no significant increase in self-rated sleepiness (t₃₀ = 0.56, P = 0.58)

**Read that as: under chronic restriction, subjective sleepiness plateaus within a few days while objective vigilance keeps degrading near-linearly.** PVT θ = 0.78 vs KSS θ = 0.16 is an apples-to-apples comparison inside one model. This is the single most important finding for `B18-7`: *the reader's own sense of how tired they are stops tracking the accumulating cost.* A sleep-debt section whose only validation is "does this match how I feel" will be tuned to a saturating signal.

### Does accumulated debt add predictive value beyond how you feel?

Bermudez EB, Klerman EB, Czeisler CA, Cohen DA, Wyatt JK, Phillips AJK (2016), *PLoS ONE* 11(3):e0151770. n = 17 (4 F, 13 M, 18–34 y), two forced-desynchrony protocols with 42.85 h "days" (control 1:2 sleep:wake, n = 8; chronic restriction 1:3.3, n = 9). Predictors: self-rated alertness, circadian phase, hours since waking, accumulated sleep loss.

- subjective alertness alone: R² = 0.557 unadjusted, 0.728 with mixed effects
- **accumulated sleep loss was the second-best single predictor after alertness**, and the alertness + sleep-loss pair reached AIC comparable to three-variable models
- the full four-variable model had the lowest AIC overall

So accumulated debt is not redundant with self-report — consistent with the KSS saturation above. But note this was a lab forced-desynchrony protocol with n = 17, with sleep *imposed and known*.

### What does **not** exist

**No published dose-response curve maps wearable-estimated cumulative sleep debt, in free-living conditions, onto PVT or KSS.** I looked and did not find one. The two nearest published results are both lab studies with imposed schedules:

- Bermudez 2016 above (imposed sleep, n = 17)
- Manners J, Scott H, Guyett A, Stuart N, Catcheside P, Kemps E (2026), *SLEEP Advances* 7(2):zpag045. n = 24 (28 ± 9 y, 50% male), 8-day simulated shift-work protocol, **Withings Sleep Analyzer** under-mattress sensor. Next-day PVT reaction time: **R² = 0.13, P = .008**; working memory R² = 0.15, P = .023; Stroop RT R² = 0.19, P = .004. Random-forest models reached 38–52% variance for reaction-time tasks; other domains R² < 0.1. The paper notes the device shows poor-to-moderate test–retest reliability and moderate sleep/wake accuracy.

R² = 0.13 from a device-derived sleep estimate onto next-day vigilance, in a *controlled* protocol, is the honest ceiling for what this app can claim. **State that ceiling rather than implying a tighter one.**

---

## 4. Does it recover linearly? No — and the two landmark studies disagree about accumulation too

**Belenky G, Wesensten NJ, Thorne DR, Thomas ML, Sing HC, Redmond DP, Russo MB, Balkin TJ (2003)**, *Journal of Sleep Research* 12:1–12. n = 66, 7 nights at 3, 5, 7 or 9 h TIB, then **3 recovery nights at 8 h TIB**.

- PVT speed in the 7 h and 5 h groups (and lapses in the 5 h group) **stayed at the reduced-but-stable level reached during restriction, with no recovery across three 8 h nights**
- the 3 h group recovered quickly after the first recovery night, but **incompletely**, stabilising at a level comparable to the 7 h and 5 h groups
- for the 3 h and 5 h groups, speed on every recovery day remained below baseline

**Banks S, Van Dongen HPA, Maislin G, Dinges DF (2010)**, *Sleep* 33(8):1013–1026. n = 159 (22–45 y, median 29), 5 nights at 4 h TIB then **one** recovery night randomised to 0/2/4/6/8/10 h TIB.

- PVT lapses vs recovery dose: linear slope −1.38 (s.e. 0.10), t₁₁₅ = −8.89, P < 0.0001, R² = 74.98%; best fit was exponential with asymptote at baseline
- **at 10 h TIB (8.96 h actual sleep) recovery was still incomplete**: lapses 5.6 ± 7.2 vs baseline 3.1 ± 3.5, P = 0.008
- KSS: slope −0.32 (s.e. 0.04), t₁₁₅ = −8.41, P < 0.0001, R² = 67.89%; at 10 h TIB, 3.8 ± 1.6 vs baseline 3.0 ± 1.5, P = 0.007; projected full recovery required **> 10.6 h TIB**

**Ochab JK et al. (2021)**, *PLOS ONE* 16(9):e0255771. n = 19 for actigraphy / 13 for EEG-behavioural (21.5 ± 1.3 y, 12 F 1 M in the EEG subset); 4 days baseline, **10 days at 30% below individual sleep need**, then **7 days recovery**. After a full week of recovery, **only mean Stroop reaction time returned to baseline**; Stroop accuracy partially, ERPs not significantly, EEG spectral power and actigraphic rest distributions still altered. Note their sleep need was set from self-report plus baseline actigraphy — i.e. the same unvalidated baseline this document is warning about.

**Kitamura 2016** put a time constant on the other end: **1 h of potential sleep debt took four days of 12 h TIB to resolve.**

Three structural conclusions:

1. **Recovery is monotone in dose but non-linear and incomplete.** A counter that decrements 1:1 — "you slept 1 h extra, your debt fell by 1 h" — asserts a restoration that has never been observed. Banks needed >10.6 h in bed to repay five nights at 4 h, and Kitamura needed four nights of 12 h to repay one hour.
2. **Accumulation is not universally linear either.** Van Dongen saw near-linear accumulation across 14 days (θ = 0.78); Belenky saw *stabilisation at a reduced plateau* after a few days at 5 and 7 h. McCauley et al. (2013), *Sleep* 36(12):1987–1997, reconciles these with a two-state-variable model — one acting over hours-to-days, one shifting the homeostatic set-point over days-to-weeks — that exhibits a **bifurcation**: below a critical daily sleep duration impairment diverges, above it impairment settles at a new, worse equilibrium. **This is why "sleep debt" as a running scalar is a modelling choice, not a measurement.**
3. **Prior sleep history changes the response, so a scalar debt is under-determined.** Rupp TL, Wesensten NJ, Bliese PD, Balkin TJ (2009), *Sleep* 32(3):311–321: n = 24 (18–39 y), one week at 10 h TIB (Extended) vs habitual (mean 7.09 h), then 1 baseline night, **7 nights at 3 h TIB**, then 5 recovery nights at 8 h. The Extended group was more resilient during restriction and recovered faster. Two people with the same numeric "debt" but different prior histories are not in the same state. (Whether this generalises is still contested — *Sleep* ran a PRO-CON debate, "Can sleep be 'banked'?", 48(12):zsaf255. ⚠️ I saw only the title and venue for that one.)

### What does "repaying" actually restore?

Ranked by how well the evidence supports restoration:

| Outcome | Restored by catch-up sleep? | Evidence |
|---|---|---|
| Subjective sleepiness (KSS) | Largely, and fastest — but it had already saturated, so it had less to recover | Banks 2010 (still elevated at 10 h TIB, P = 0.007, but nearer baseline than PVT) |
| PVT lapses / vigilance | **Partially.** Incomplete after 1 night at 10 h TIB; incomplete after 3 nights at 8 h; incomplete after 7 days | Banks 2010; Belenky 2003; Ochab 2021 |
| Cortical/ERP measures | **No**, not within 7 days | Ochab 2021 |
| Insulin sensitivity, energy intake, body weight | **No** — weekend recovery sleep failed to prevent metabolic dysregulation | Depner CM et al. (2019), *Current Biology*: n = 36 (control 9 h n = 8; restriction 5 h n = 14; restriction + weekend recovery n = 14). Insulin sensitivity fell ~13% in SR; in the weekend-recovery group whole-body/hepatic/muscle insulin sensitivity fell ~9–27% during recurrent insufficient sleep. Weekend recovery sleep totalled ~1.1 h above baseline |
| Metabolic/endocrine markers after a *long* extension | Improved — glycometabolism, thyrotropic and HPA-axis measures improved as PSD resolved over 9 nights at 12 h TIB | Kitamura 2016 |

**The honest sentence for the card:** *catch-up sleep restores how you feel faster than it restores how you perform, and there is no evidence it restores the metabolic cost at all when the pattern repeats.*

---

## 5. ⚠️ Is there a defensible individual sleep-need estimator from longitudinal wearable data?

**No. It is an open problem. Say so plainly in the app.**

The evidence for that answer, rather than the assertion:

1. **Every measured individual need in the literature came from an imposed extension protocol.** Kitamura 2016: 9 nights at 12 h TIB, exponential asymptote. Klerman & Dijk 2008: 12 h night + 4 h afternoon for 3–7 days. Van Dongen 2003 did not measure need at all — it *inferred* a population-level critical wake duration from performance decrements, which requires a performance test the app does not administer.
2. **The habitual-duration substitute is circular.** need := habitual ⇒ debt ≡ 0 over any window long enough to estimate "habitual". Whatever such a metric shows is deviation from a rolling mean; calling it debt is a category error.
3. **The free-day / personal-best substitute is confounded and, for this reader, inverted.** Free-day sleep length reflects need *plus* accumulated debt *plus* alcohol, illness, circadian misalignment and simple opportunity. And measured from this export's last 90 days: **weekend nights average 0.72 h shorter than weekday nights** (51 weekday vs 17 weekend nights observed). An MCTQ-style free-day estimator would conclude this reader's need is *below* their weekday duration — i.e. that they are in credit for sleeping too much on Tuesdays. The estimator fails on the first person we tried it on.
4. **The between-person spread is too large for a population prior to help.** σ_between(ξ) = 3.58 ± 1.19 h (Van Dongen 2003). A prior of 8.16 h with that spread carries essentially no information about one person relative to the size of the debts we would be reporting.
5. **Genuine sleep-need variation has known biological causes we cannot observe.** Short-sleep phenotypes with identified mutations exist; this app has no genotype and should not pretend the population distribution is a person's distribution. *(I did not re-verify the short-sleeper genetics citations in this session and have deliberately not listed effect sizes for them.)*
6. **Vendors ship a "sleep need" anyway, with an undisclosed formula.** The only public description I could reach describes a scoring function of the form *baseline + strain function + debt function − naps*; the primary vendor page (whoop.com) returned HTTP 403 to fetch and the corresponding patent PDF would not extract, so I could not confirm coefficients, caps or accumulation window from a primary source. **That is exactly the profile the repo's rule was written for: a vendor composite with an undisclosed formula may be RELAYED as a labelled second opinion and must never be BLENDED into our own figure.**
7. **The nearest thing to a positive result is a reliability study, not a need estimator.** "How many nights are needed? The short-term stability of intraindividual variability in sleep parameters derived from accelerometry data in a cohort of normal sleepers", *SLEEP* 49(6):zsag040 (2026) — n = 10,412 WHOOP users (50% women, 37.75 ± 10.65 y), ~3.7 M person-nights, 86–89% agreement with PSG for sleep/wake. Reliable **intraindividual mean** estimates (r > .80) needed 2–7 nights (total sleep time: 7 nights); reliable estimates of **intraindividual variability** needed 41–65 nights (TST: 43). ⚠️ *I did not capture the author list for this paper — fill it in before citing it in a shipped doc.* This tells us how many nights a *baseline* needs. It says nothing about need.

**The one honest opportunistic estimator available to us**, and it should be labelled as experimental if built: this export contains 15 detected `holidays`. If a holiday ever produces ≥5 consecutive nights of unconstrained sleep opportunity, the *rebound* on the first such nights is, per Kitamura, a crude indicator of accumulated debt, and the asymptote across them is a crude indicator of need. Kitamura needed 9 nights to see the asymptote and had a lab; a 5-night holiday gives a lower bound with a wide, unquantified error. Ship it only with that stated, or not at all.

---

## 6. What this repo can actually compute — measured, not assumed

Counted from `~/HealthSeed/exports/health-insights-export-new.json` (generated 2026-08-07T07:09:11Z, 377,284 samples), window = last 90 days:

| Metric | rows, all time | last 365 d | last 90 d | first → last | sources in last 90 d |
|---|---|---|---|---|---|
| `sleepDurationHours` | 249 | 231 | 128 | 2024-08-19 → 2026-08-06 | Apple Health 61, Oura 67 |
| `sleepEfficiency` | 249 | 231 | 128 | same | Apple Health 61, Oura 67 |
| `sleepOnset` | 240 | 222 | 123 | same | Apple Health 61, Oura 62 |
| `sleepDeepMinutes` | 245 | 230 | 127 | same | Apple Health 60, Oura 67 |
| `sleepRemMinutes` | 245 | 230 | 127 | same | Apple Health 60, Oura 67 |
| `sleepLatencyMinutes` | 117 | 117 | 67 | 2026-03-15 → 2026-08-06 | Oura 67 |

Derived coverage facts for the last 90 days:

- **68 distinct nights of 90 (76%)**. 22 nights missing, in **10 separate gap runs**, longest missing run **5 consecutive nights**. Longest unbroken run of nights: **22**.
- **60 of 68 nights carry two sources.** Median |Apple Health − Oura| difference is **0.00 h** (Apple Health is mostly relaying Oura), but **11 of 60 nights disagree by > 0.5 h**, up to **4.13 h**, RMS difference **1.33 h**.
- Night-to-night s.d. of duration: **2.13 h**.

Two operational consequences before any physiology:

- **Naive summation double-counts.** Two rows per night with the same nominal meaning; a cumulative debt that sums rows rather than nights is wrong by roughly a factor of two.
- **A cumulative sum over a series with 24% missing nights and 5-night holes is not a cumulative sum.** Whatever is done with the gaps (skip, impute, carry forward) *is* the model, and it has to be visible.

### Derived error budget for a 14-night debt figure

Not cited — derived, from the numbers above, so it is checkable:

| Term | Derivation | Error over 14 nights |
|---|---|---|
| Baseline (need) uncertainty | 0.73 h/night (Van Dongen s.e. of the *population mean*) × 14, since the same wrong baseline is subtracted nightly and does **not** average down | **±10.2 h** |
| Missing nights | 24% missing → 3.4 expected gaps in 14; imputing at the personal mean costs σ = 2.13 h each, √3.4 × 2.13 | ±3.9 h |
| Source disagreement | half of RMS 1.33 h = 0.67 h per contested night, over the ~12.4 dual-source nights in 14 | ±2.3 h |
| **Total (quadrature)** | √(10.2² + 3.9² + 2.3²) | **≈ ±11.2 h** |

If instead the baseline were an *individual* estimate carrying the between-person spread (σ = 3.58 h), the baseline term alone would be ±50 h over 14 nights.

**So: a 14-night "you owe N hours" figure computed from this data has an error bar larger than almost any N it would print.** That is the finding. It is not a reason to show nothing — per the standing rule, thin data means print the error bar — but it is a decisive reason not to print a bare scalar.

---

## 7. What is defensible to build for `B18-7`

Ordered from most to least defensible.

1. **Rename the quantity.** Show **"hours below your own recent typical"** over a stated window, not "sleep debt". This is definition-1 arithmetic with an honest baseline label, and it is exactly what the data supports. The baseline (rolling median/mean over ≥7 nights per the *SLEEP* 49(6) reliability result, and ideally over 30+ nights for any variability claim) is a measured property of this person, not a claim about their physiology.
2. **Print the coverage, always.** "68 of the last 90 nights" belongs on the section, not in a caveat sheet. A cumulative figure over a series with a 5-night hole must say so. The gap handling must be visible on the chart — dash-means-inferred already exists in this codebase for exactly this.
3. **Print the band, not just the line.** The ±11 h derivation above is reproducible per-window from the coverage and source-disagreement actually present; compute it live rather than hard-coding it, and let it shrink when coverage improves. This is the shape the reader's rule asks for.
4. **Do not decrement 1:1 on catch-up.** If a repayment display is built at all, it must not assert restoration. The defensible copy is the Banks/Belenky finding stated qualitatively: *one long night returns some of it; in the studies, five short nights were not repaid by a single 10-hour night.*
5. **Relay, never blend.** If Oura (or any vendor) exposes a sleep-need or readiness-derived debt figure, show it in the second-opinion slot, labelled with the vendor's name and "formula not published". Do not feed it into the app's own number. I could not obtain a primary-source description of any vendor's sleep-need formula in this session — 403 on the vendor page, unextractable patent PDF — which is itself the argument.
6. **Use the two published equivalences for the education copy.** "Two weeks at 6 hours in bed produced vigilance lapses equal to one night with no sleep at all; at 4 hours, equal to two nights" (Van Dongen 2003, n = 48). It is dramatic, true, cited, and requires no arithmetic on the reader's own data.
7. **Say the KSS thing.** The section should tell the reader that self-rated sleepiness plateaus while measured vigilance keeps falling (curvature 0.16 ± 0.03 vs 0.78 ± 0.04 in the same model). It is the strongest reason for the section to exist, and it is a claim about the literature, not about them.
8. **State the open problem where the reader will look for it.** One line: *"How much sleep you personally need cannot be measured from a wearable. Every published measurement of individual sleep need required nine or more nights of unrestricted 12-hour sleep opportunity in a laboratory."* That sentence is the honest version, and it is more useful than a fabricated need.

### What to refuse

- A single headline number labelled "sleep debt: N hours" with no band. The band is bigger than N.
- Any need figure derived from free-day or best-night sleep. Reductio above: this reader's weekends are *shorter*.
- Any "you'll be back to normal after X hours of sleep" projection. Banks 2010 projected >10.6 h TIB to repay five nights at 4 h and still measured residual impairment; Ochab 2021 found seven days insufficient. There is no published curve that would let us fill in X for an individual.
- Feeding a vendor need/debt figure into our score.

---

## 8. Things I looked for and did not find

Stated plainly, because absence is a finding:

- **No published dose-response of wearable-estimated cumulative sleep debt onto PVT or KSS in free-living conditions.** Nearest: lab protocols with imposed sleep (Bermudez 2016, n = 17) and a lab simulated-shift-work study using an under-mattress device (Manners 2026, n = 24, PVT R² = 0.13).
- **No validated individual sleep-need estimator from longitudinal free-living data** — see §5.
- **No primary-source description of any consumer vendor's sleep-need formula** that I could retrieve (whoop.com 403; patent PDF unextractable).
- **No agreed accumulation window.** 14 days is the longest window with direct evidence of *continued* accumulation (Van Dongen 2003, 4 h and 6 h conditions). Belenky 2003 saw stabilisation at a plateau instead. Nothing supports an unbounded running total, and nothing supports a specific decay half-life for old debt.
- **No ICC values for the stability of individual vulnerability** in the Van Dongen 2004 abstract (n = 21, three 36-hour deprivation exposures ≥2 weeks apart). The trait-like conclusion is well supported; the numeric reliability was not available to me.

---

## 9. References, with n and effect sizes

- **Van Dongen HPA, Maislin G, Mullington JM, Dinges DF (2003).** The cumulative cost of additional wakefulness: dose-response effects on neurobehavioral functions and sleep physiology from chronic sleep restriction and total sleep deprivation. *Sleep* 26(2):117–126. n = 48 (8 h n = 9; 6 h n = 13; 4 h n = 13 for 14 nights; 0 h n = 13 for 3 days). ξ = 15.84 ± 0.73 h; implied need 8.16 ± 0.73 h; between-subject s.d. of ξ = 3.58 ± 1.19 h; model R² = 83.0%, θ = 0.67 ± 0.05. PVT-vs-days curvature 0.78 ± 0.04; KSS-vs-days curvature 0.16 ± 0.03 (restriction) vs 0.81 ± 0.16 (deprivation). Habitual-sleep × vulnerability r₃₂ = 0.29, P = 0.048.
- **Van Dongen HPA, Baynard MD, Maislin G, Dinges DF (2004).** Systematic interindividual differences in neurobehavioral impairment from sleep loss: evidence of trait-like differential vulnerability. *Sleep* 27(3):423–433. n = 21 (21–38 y), three 36-h total-deprivation exposures ≥2 weeks apart. Three stable dimensions; no ICC in the abstract.
- **Belenky G, Wesensten NJ, Thorne DR, Thomas ML, Sing HC, Redmond DP, Russo MB, Balkin TJ (2003).** Patterns of performance degradation and restoration during sleep restriction and subsequent recovery: a sleep dose-response study. *J Sleep Res* 12:1–12. n = 66; 3/5/7/9 h TIB × 7 nights + 3 recovery nights at 8 h. Recovery incomplete; 5 h and 7 h groups showed no recovery across three nights.
- **Banks S, Van Dongen HPA, Maislin G, Dinges DF (2010).** Neurobehavioral dynamics following chronic sleep restriction: dose-response effects of one night for recovery. *Sleep* 33(8):1013–1026. n = 159 (22–45 y). PVT slope −1.38 (s.e. 0.10), t₁₁₅ = −8.89, P < 0.0001, R² = 74.98%; at 10 h TIB lapses 5.6 ± 7.2 vs 3.1 ± 3.5 baseline, P = 0.008. KSS slope −0.32 (s.e. 0.04), R² = 67.89%; 3.8 ± 1.6 vs 3.0 ± 1.5, P = 0.007; projected > 10.6 h TIB for full recovery.
- **Kitamura S, Katayose Y, Nakazaki K, et al. (2016).** Estimating individual optimal sleep duration and potential sleep debt. *Scientific Reports* 6:35812. n = 15 men, 23.3 ± 2.1 y; 9 nights at 12 h TIB. OSD 8.41 ± 0.18 h; habitual 7.37 ± 0.27 h; PSD 1.04 ± 0.24 h (range −0.58 to +2.73). MWT r = −0.486 (P = 0.066), adjusted r = −0.544 (P = 0.029). 1 h of PSD took 4 days to resolve.
- **Klerman EB, Dijk D-J (2008).** Age-related reduction in the maximal capacity for sleep. *Current Biology*. 18 older, 35 younger adults; 12 h night + 4 h afternoon TIB for 3–7 days. ⚠️ Duration figures not verified against the paper text in this session.
- **Rupp TL, Wesensten NJ, Bliese PD, Balkin TJ (2009).** Banking sleep: realization of benefits during subsequent sleep restriction and recovery. *Sleep* 32(3):311–321. n = 24 (18–39 y); Extended 10 h vs Habitual (mean 7.09 h) for one week, then 7 nights at 3 h, then 5 recovery nights at 8 h.
- **Ochab JK, et al. (2021).** Observing changes in human functioning during induced sleep deficiency and recovery periods. *PLOS ONE* 16(9):e0255771. n = 19 actigraphy / 13 EEG (21.5 ± 1.3 y); 4 d baseline, 10 d at 30% below individual need, 7 d recovery. Only Stroop mean RT returned to baseline.
- **Depner CM, et al. (2019).** Ad libitum weekend recovery sleep fails to prevent metabolic dysregulation during a repeating pattern of insufficient sleep and weekend recovery sleep. *Current Biology* 29(6). n = 36 (control 9 h n = 8; SR 5 h n = 14; WR n = 14). Insulin sensitivity −13% in SR; −9% to −27% (whole-body/hepatic/muscle) in WR during recurrent insufficient sleep; ~1.1 h cumulative extra weekend sleep.
- **Lim J, Dinges DF (2010).** A meta-analysis of the impact of short-term sleep deprivation on cognitive variables. *Psychological Bulletin* 136(3):375–389. 70 articles, 147 tests; lapses in simple attention g = 0.776 (largest effect); reasoning accuracy g = −0.125, CI [−0.27, 0.02], n.s.
- **Bermudez EB, Klerman EB, Czeisler CA, Cohen DA, Wyatt JK, Phillips AJK (2016).** Prediction of vigilant attention and cognitive performance using self-reported alertness, circadian phase, hours since awakening, and accumulated sleep loss. *PLoS ONE* 11(3):e0151770. n = 17. Alertness alone R² = 0.557 (0.728 mixed-effects); accumulated sleep loss the second-best single predictor; four-variable model lowest AIC.
- **Manners J, Scott H, Guyett A, Stuart N, Catcheside P, Kemps E (2026).** Estimated sleep from an under-mattress device predicts next-day vigilance, working memory, and mental arithmetic performance. *SLEEP Advances* 7(2):zpag045. n = 24; Withings Sleep Analyzer. PVT RT R² = 0.13, P = .008; OSPAN R² = 0.15, P = .023; Stroop RT R² = 0.19, P = .004.
- **McCauley P, Kalachev LV, Мollicone DJ, Banks S, Dinges DF, Van Dongen HPA (2013).** Dynamic circadian modulation in a biomathematical model for the effects of sleep and sleep loss on waking neurobehavioral performance. *Sleep* 36(12):1987–1997. Two state variables (hours-to-days impairment; days-to-weeks homeostatic set-point); bifurcation explains the restriction/deprivation divergence.
- **Wittmann M, Dinich J, Merrow M, Roenneberg T (2006).** Social jetlag: misalignment of biological and social time. *Chronobiology International* 23(1–2):497–509. n = 501. Defines work/free-day discrepancy; late chronotypes accrue workday sleep loss and compensate on free days.
- **"How many nights are needed? The short-term stability of intraindividual variability in sleep parameters derived from accelerometry data in a cohort of normal sleepers."** *SLEEP* 49(6):zsag040 (2026). n = 10,412 WHOOP users, ~3.7 M person-nights, 86–89% PSG agreement for sleep/wake. Reliable intraindividual means (r > .80) at 2–7 nights (TST 7); reliable intraindividual variability at 41–65 nights (TST 43); 7- and 14-night iSD reliabilities .50–.58 and .61–.67. ⚠️ Author list not captured.
- **"Can sleep be 'banked'? A PRO-CON debate."** *SLEEP* 48(12):zsaf255. ⚠️ Title and venue only.

**Sources:** [Van Dongen 2003 (Sleep)](https://academic.oup.com/sleep/article-abstract/26/2/117/2709164) · [Van Dongen & Dinges, Sleep debt and cumulative excess wakefulness](https://www.med.upenn.edu/uep/assets/user-content/documents/Van_Dongen_Dinges_Sleep_26_3_2003.pdf) · [Van Dongen 2004](https://pubmed.ncbi.nlm.nih.gov/15164894/) · [Belenky 2003](https://onlinelibrary.wiley.com/doi/abs/10.1046/j.1365-2869.2003.00337.x) · [Banks 2010](https://pmc.ncbi.nlm.nih.gov/articles/PMC2910531/) · [Kitamura 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC5075948/) · [Klerman & Dijk 2008](https://www.sciencedirect.com/science/article/pii/S096098220800804X) · [Rupp 2009](https://academic.oup.com/sleep/article-abstract/32/3/311/3741695) · [Ochab 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8409667/) · [Depner 2019](https://www.cell.com/current-biology/fulltext/S0960-9822(19)30098-3) · [Lim & Dinges 2010](https://www.med.upenn.edu/uep/assets/user-content/documents/LimDinges2010MetaAnalysis.pdf) · [Bermudez 2016](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0151770) · [Manners 2026](https://academic.oup.com/sleepadvances/article/7/2/zpag045/8658230) · [McCauley 2013](https://www.med.upenn.edu/uep/assets/user-content/documents/McCaulyetal.2013.pdf) · [Wittmann 2006](https://pubmed.ncbi.nlm.nih.gov/16687322/) · [How many nights are needed? (SLEEP 2026)](https://academic.oup.com/sleep/article/49/6/zsag040/8502073) · [Can sleep be banked? PRO-CON](https://academic.oup.com/sleep/article/48/12/zsaf255/8240160)
