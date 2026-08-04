# Research notes — why the app decides things the way it does

Findings from the multi-agent research runs of 2026-08-04, kept so the reasoning
survives a context reset and so the app can one day show a reader *why* a card
behaves as it does.

## ⚠️ The privacy split — read before adding to this file

**The full reports are not in this repo and must not be.** They live in
`~/HealthSeed/research/` on the user's Mac:

| File | What it is |
| --- | --- |
| `illness-detection.md` | The literature and the data science behind the symptom radar |
| `card-defect-diagnosis.md` | Root causes for every card defect reported 2026-08-04 |
| `body-mesh-design.md` | The judged design panel behind `BodyMesh` |
| `symptom-radar-spec.md` | The radar's full implementation spec |
| `health-export-audit.md` | What the app's own export does and does not carry |

They quote the reader's own physiology — noise floors, coverage, VO₂max band,
device disagreement. This repo is **public**, so per `docs/privacy-and-ip.md`
only *the shape of a finding* belongs here, never the reading. What follows is
the published-literature half, which is safe anywhere, plus conclusions stated
without personal numbers.

---

## Early illness detection: what is actually achievable

**The honest ceiling.** The widely-quoted "43% sensitivity at 95% specificity"
is Natarajan, Su & Heneghan, *npj Digital Medicine* 2020 — a convolutional
network on nightly respiration rate, heart rate and HRV, trained on 2,745
PCR-confirmed cases. It is a population model built from thousands of labelled
infections, and it is close to the ceiling for what nightly vitals can do.

**It is not a pre-symptom number**, which is the part everyone misreads. The
same paper, at 95% specificity: **15%** on the night *before* symptoms, 24% on
the day they start, 33% the day after. The 43.7% average is dominated by days
the reader already knows they are ill. The figure worth alerting on is about a
third of the headline.

**The negative is nearly worthless.** A quiet night moves the odds of being ill
from roughly 7% to roughly 4%. This is the single most important fact shaping
the card's copy: **a quiet result may never read as reassurance.**

### The base rate decides everything

Adults get 2–4 colds a year at 7–10 days each (Heikkinen & Järvinen, *Lancet*
2003); influenza adds well under a day a year (Tokars, *CID* 2018). So about 7%
of days are ill-days, and the onset window worth flagging — say three nights per
episode — is about 2.5% of nights.

At 43.7%/95% on a fully monitored year:

| Framing | Alarms/yr | False | Right when it speaks |
| --- | --- | --- | --- |
| "You are ill tonight" | ~28 | ~17 | ~40% |
| "You are about to get ill" | ~22 | ~18 | **~18%** |

The only prospective study to publish a positive predictive value (Fitbit CNN,
*JMIR Form Res* 2024, n=470) reached 90% detection at a 2% false-positive rate
and a **PPV of 4%** — 96 alerts in 100 wrong, with a good model on dense data.
That is base-rate arithmetic, not bad modelling.

**Therefore the tuning direction is the opposite of the intuitive one: give up
sensitivity, buy specificity.** A coin-flip PPV needs ~98.9% specificity, not
95%. And there is direct evidence for what happens if you don't: 88.8% of ICU
arrhythmia alarms are false, and the documented clinical response is that people
stop listening. A high false-alarm rate does not merely annoy — it destroys the
credibility of the one true positive that arrives every few years.

### Why no neural network

Supervised learning needs labelled examples of illness. A personal detector has
a handful at best, and often none — which kills training *and*, more
importantly, testing: there is no denominator to compute a sensitivity against.

Every shipped consumer feature — Oura's Symptom Radar, Apple Vitals, Whoop
Health Monitor, Garmin Health Status, Samsung, Fitbit — is **unsupervised
personal-baseline deviation detection**, not a trained classifier. The best
published real-time result (Alavi et al., *Nature Medicine* 2022: 80%
sensitivity at 87.7% specificity, median 3 days early) is a six-state finite
state machine over a running median of overnight resting heart rate. A per-person
LSTM autoencoder managed recall of 0.36. **The simple method wins, and you can
state its false-alarm rate**, which the network cannot.

How many labels before a personal accuracy figure is honest: about **10
episodes** to quote any rate, about **25** for a sensitivity estimate with a ±10
point interval. At 2–4 illnesses a year that is 3–5 years and 7–10 years
respectively.

### What actually improves detection, in order

1. **Wear the sensor more nights.** Free, and usually the largest available
   gain. Multi-night persistence is the only mechanism that makes detection
   arithmetically possible, and it requires runs of consecutive covered nights.
   Garmin's own published floor for Health Status is four nights a week.
2. **Fix the measurement stack.** Ingestion defects move more variance than any
   modelling change. See `card-defect-diagnosis.md`.
3. **Score a run of nights, not a night.** Sequential change detection (CUSUM)
   is minimax-optimal for detection delay at a fixed false-alarm rate (Page
   1954; Lorden 1971; Moustakides 1986). Empirically it beat a single-night
   detector on **both axes at once**: 80% vs 72% sensitivity *and* 87.7% vs
   83.7% specificity. Alert *duration* separates real from spurious — about 1.9
   days for non-illness against 4.3 for infection.
4. **Set thresholds from personal history, never a statistics table.** Textbook
   3-sigma rules fire several times more often than their nominal rate on real
   personal data, because residuals are heavier-tailed and more correlated than
   the textbook assumes. Replace the threshold with a **stated budget** — "tell
   me about the four most unusual stretches a year" — and display the rate it
   actually achieved.
5. **One joint statistic, never several thresholds OR'd together.** Six signals
   each at 95% specificity, OR'd, gives a 26.5% nightly false-positive rate —
   about 97 false-alarm nights a year. Holding 5% overall would demand 99.15%
   per signal.
6. **Score only in the illness direction.** Every study converges on the same
   signature: heart rate up, respiratory rate up, temperature up, HRV down,
   SpO2 down. Clamping healthy-direction deviations to zero halves false alarms
   for free and imports five studies' worth of prior without training on
   anything.
7. **Ask how the reader feels.** The largest single gain on any axis, and it is
   not a model. Symptoms alone AUC 0.71; sensors alone ~0.72; **both 0.80**. In
   a 1,688-person influenza cohort, 41 wearable features including 29 HRV
   metrics added **nothing** over eight yes/no symptom questions (0.74 → 0.74).
   In the only large randomised trial (COVID-RED, n=17,825) the wearable arm's
   likelihood ratio was **0.98–1.00 — literally zero information** — while the
   symptom-diary arm reached 4–11.
   **The specific question matters enormously**: "chills you couldn't warm up
   from" carries a likelihood ratio around 7 — one tap worth roughly the entire
   sensor stack — whereas a vague "feeling off" is worth about 2.

### Multivariate gain, honestly

The cleanest published comparison (DETECT, *Nature Medicine* 2021) gives +0.20
AUC from combining signals: resting heart rate alone scored 0.52 —
indistinguishable from a coin flip — rising to 0.72 combined. But heart rate and
HRV derived from one heartbeat-interval stream are near-redundant and must not
count as two agreeing votes. The genuinely independent channels — respiratory
rate, temperature, SpO2 — are also the quietest, which is why **closing
respiratory-rate coverage is worth more than further modelling**.

### Confounders: what survived cross-validation

Fitted and then cross-validated on contiguous time blocks, **only sleep
survives**: sleep timing and efficiency predict resting heart rate and HRV out
of sample, replicating *across devices* (so it is physiology, not one vendor's
internal consistency). Previous-day activity, medication level, day of week,
substances, body mass and calendar trend all cross-validated to ≤0.06 and
usually **negative** — worse than predicting the average.

**The trap worth remembering:** kitchen-sink models looked excellent in-sample
and cross-validated far worse than the raw signal. That is exactly what a bigger
model does on personal data — more convincingly, and therefore more dangerously.

So the confounder lever is **exclusion and annotation, not regression**: keep
known-perturbed nights out of the baseline, reset hard on a dose or device
change, and name the alternative explanation on the card rather than silently
subtracting it.

**Alcohol** is the best-documented confounder in this literature — a moderate
drinking evening moves nocturnal resting heart rate about +3 bpm with suppressed
HRV, the same size and shape as the illness threshold. A detector without
alcohol logging is partly an alcohol detector wearing an illness costume.

**GLP-1 agonists** raise resting heart rate by roughly 2–3.5 bpm on average with
larger transients during titration — enough that an unreset trailing baseline
reads every dose step as a week of illness. Use dose changes as a **baseline
reset trigger** and a *named possible* explanation, never an established cause.

---

## Sources

Natarajan, Su & Heneghan, *npj Digital Medicine* 2020 · Mishra et al., *Nature
Biomedical Engineering* 2020 · Quer et al. (DETECT), *Nature Medicine* 2021 ·
Radin et al., *Lancet Digital Health* 2020 · Alavi et al., *Nature Medicine*
2022 · Grzesiak et al., *JAMA Network Open* 2021 · COVID-RED randomised trial
(n=17,825) · Fitbit CNN, *JMIR Form Res* 2024 · Heikkinen & Järvinen, *Lancet*
2003 · Tokars et al., *CID* 2018 · Page 1954; Lorden 1971; Moustakides 1986
(sequential change detection).
