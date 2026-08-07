# Wearable illness detection — what the evidence actually supports

_28 studies, 2020–2025, surveyed 2026-08-07. **Read this before touching the
symptom radar or building the sick-days feature (§B11).** It is more critical
than the press coverage and, in two places, than this app's own current design._

## The headline, in three sentences

Resting heart rate, respiratory rate, HRV and skin temperature **do** shift 1–3
days before symptoms — that part is solid and replicated. Almost every famous
AUC (0.77–0.82) comes from **retrospective, case-enriched** analyses. When the
same algorithms ran **prospectively, in real time, against a real reference
test**, positive predictive value collapsed to **4–12%**, and in the only
randomised trial the physiological alerts produced **zero** confirmed
infections.

## The numbers that should govern our design

| Finding | Figure | Source |
| --- | --- | --- |
| Prospective PPV, real PCR reference | **4–10%**; 665 alerts → 512 tested → **63 confirmed (12%)** | Esmaeilpoor 2024, JMIR Form Res |
| The only RCT, physiological arm | **26 alerts → 6 tested → 0 positive.** 65% of alerts had no symptoms within 7 days | DETECT-AHEAD, Lancet Digit Health 2024 |
| False-alarm burden, DoD deployment | **11% FPR per 14-day window** ≈ 2.9 false alarms/person/year | Conroy 2022, Sci Rep |
| Respiratory-rate false positives | **34.2% of COVID-negative** people flagged in a 6-day window | Miller 2020, PLOS ONE (WHOOP) |
| Deployable-model baseline after removing temporal leakage | **AUROC 0.51** | Nestor 2023, Lancet Digit Health |
| Behavioural leakage | AUC **0.75 → 0.63** once post-test-result data is excluded | Cleary 2022, PLOS ONE |
| Pooled HRV effect | SDNN **−3.25 ms** (RMSSD CI crosses zero), I² 82–85% | Sanches 2023, JMIR |

**The arithmetic that makes this unavoidable.** An adult has ~2–4 acute
respiratory infections a year, so the prior for "today precedes an illness" is
about **1%**. At TemPredict's operating point (sens 82%, **spec 63%**) that is a
PPV near **2%**. Pushing specificity to the 97% UK workplace-screening
benchmark costs nearly all the presymptomatic sensitivity: at 99% specificity
you catch **6.8%** of cases the day before onset (Natarajan 2020).

## ⚠️ Three findings that bear directly on our code

**1. Respiratory rate alone is a confirmatory signal, not an early warning.**
Only **36.4%** of PCR-confirmed symptomatic cases ever showed a ≥3 br/min rise
above their own mean in the ±7-day window, and the elevation **peaks at D+2 —
two days *after* symptom onset** (Natarajan 2021). Measurement is not the
problem: nocturnal PPG respiratory rate is accurate to ~0.65 br/min RMSE. Roughly
two-thirds of real infections never produce a clear respiratory-rate spike.

**2. What these systems detect is non-specific systemic strain, not
respiratory illness and not a pathogen.** Stated explicitly across the
literature: 60% of *non*-COVID illnesses fired the same signal (Mishra 2020);
heart-rate elevation cannot differentiate COVID from other illness (Mitratza
review); the 2025 WE SENSE trial's endpoint is literally **blood inflammatory
markers**. The identical signature precedes **rheumatoid-arthritis flares up to
4 weeks ahead** and **IBD flares up to 7 weeks ahead** — no infection involved —
and is reproduced by alcohol, hard training, poor sleep, travel, altitude and
the menstrual cycle. **No study in this literature detects lung pathology.**

**3. Oura's own Symptom Radar has never published a single accuracy figure.**
It is validated against members' self-selected illness tags, ~2 days ahead, and
**no sensitivity, specificity, PPV or alert rate has ever been released**. Their
head of science acknowledges false positives and negatives. Empatica's Aura
holds a CE mark claiming sensitivity 0.94 with **no peer-reviewed prospective
validation** found. ⚠️ **We have a card with the same name.** Treat both vendor
claims as unvalidated, and do not let "Oura does it" stand in for evidence.

## What this changes for us

**The symptom radar's existing caution is vindicated, and its measured
false-positive rate is in line with the field.** The card firing on 26.2% of the
reader's days looked alarming; against a literature where prospective PPV is
4–12%, it is the expected shape of the problem rather than a bug in our maths.
The 2026-08-05 rebuild — a calibrated statistic, CUSUM memory, a coverage gate,
and the honest note that detection gets *slower* — is the right direction, and
this evidence says the trade it makes is the trade the field makes.

**⚠️ The fake-sick-day inversion (§B11) is the riskiest thing in the new brief,
and this is why.** The plan is to learn the correlation between calendar sick
days and radar patterns, then flag days that do not match as possible
"sick to get off work". The evidence says the physiological signal is
**absent in roughly two-thirds of genuine infections**, arrives late as often as
early, and is non-specific. So "your pattern does not look like illness" is
**not** evidence that someone was not ill — it is the expected reading for most
real illness. Building the inversion is defensible as a *research* signal
recorded for the model; **surfacing it to a person as a judgement about
honesty is not**, and would be the app's worst possible failure mode. Recommend:
compute it, store it, never show it as an accusation, and require a much higher
bar than the forward direction.

**Skin temperature is the highest-value single input** — worth **+4.9
percentage points of absolute AUC** in TemPredict, and the earliest signal to
move (mean 3 days ahead, +0.63 °C). We already ingest Oura's temperature
deviation; it should carry weight accordingly.

**Any illness-adjacent figure needs a personal baseline and a wear floor.**
Esmaeilpoor's algorithm required **18 days** of baseline before predicting at
all, and adherence is a real ceiling — motivated healthcare workers wore the
ring 87.8% of nights, and missing nights caused ~20% of misses in Alavi 2022.
This is `CoverageGate`'s job (D46).

**The honest label** is what the literature supports: *non-specific systemic
strain*. Never "respiratory", never a pathogen, never a screen. Expect **1–2
false alarms a month** at any useful sensitivity and design the copy for that —
nine times in ten it is a hard session, a late night, three drinks, or nothing.

## The citation to stop repeating

The most-cited "Apple Watch detects COVID 7 days early" paper (Hirten 2021,
Warrior Watch) has **13 events and no diagnostic accuracy whatsoever** — no AUC,
no sensitivity, no specificity, only cosinor p-values. It should not be cited as
a detection result, by us or anyone.

## Sources

Full study table with 28 entries, per-study limitations and every URL is in the
research transcript for this session. Principal sources: Mishra 2020 (Nat Biomed
Eng); Quer 2021 & 2024 (Nature Medicine; Lancet Digit Health, DETECT-AHEAD RCT);
Alavi 2022 (Nature Medicine); Mason 2022 & Smarr 2020 (Sci Rep, TemPredict);
Natarajan 2020 & 2021 (npj Digit Med); Miller 2020 (PLOS ONE); Conroy 2022 (Sci
Rep, DoD); Esmaeilpoor 2024 (JMIR Form Res, prospective); Cleary 2022 (PLOS
ONE); Nestor 2023 (Lancet Digit Health, critique); Mitratza 2022 (Lancet Digit
Health, systematic review); Singh 2024 (JMIR mHealth, meta-analysis); Sanches
2023 (JMIR, HRV meta-analysis); Chen 2024 (Digital Health); Hadid 2025 (Lancet
Digit Health, WE SENSE); Sharma 2025 (Sci Rep, RA flares).
