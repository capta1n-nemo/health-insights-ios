# Cuffless blood pressure, and a better Blood Pressure card — R60

**Written 2026-08-08.** Commissioned as backlog `R60`, from the reader's words:
*"Research how we can do better experience for Blood Pressure card, and how we
can do predictive cuff less blood pressure."* The first attempt at this brief was
stopped mid-fetch on 2026-08-07 and left the topic uncovered.

Two halves, and they answer to different standards of proof:

- **The predictive half is settled, and the answer is no.** Not "no for now" —
  no on published evidence *and* no on this reader's own 50 cuff readings, which
  are re-analysed here from the export rather than argued about.
- **The experience half is wide open**, and the honest verdict on the estimator
  is what unlocks it: once the card stops trying to be a daily blood-pressure
  number, there is a genuinely valuable product underneath it.

Nothing here is built. This is the evidence and the design argument.

---

## 0. Bottom line

1. **A daily numeric BP estimate from resting heart rate and HRV cannot beat
   "your last cuff reading, aged."** Measured, on this reader's data, walk-forward:
   the estimator's mean absolute systolic error is **13.6 mmHg**; predicting the
   previous reading is **9.7 mmHg**. It loses. See §2.
2. **Fixing P15 will not rescue it.** The predictor carries no signal in this
   person: over the 180-day fit window `r(resting HR, systolic) = −0.12`, and the
   fit's residual SD (13.5 mmHg) is *larger* than the raw systolic SD it is
   meant to explain (13.3 mmHg). Fed a whole year of real resting-HR days, the
   estimate would span **10 mmHg** against occasion-to-occasion systolic
   variation of **SD 16.2 mmHg**. §2.3.
3. **This is the exact failure the literature predicted.** A calibrated cuffless
   estimator regresses toward its calibration point and fails when BP actually
   moves — measured at n=40 (Falter 2022), n=1,125 (Aurora), and most starkly at
   n=3 where a CE-marked device tracked a **−19.7 mmHg** medication response as
   **−1.0 mmHg** (Tan 2023). §3.2.
4. **No cuffless device has passed a cuffless standard.** IEEE 1708 and
   ISO 81060-3:2022 exist; ISO 81060-7 is still in draft. ESH (2022, 2023), the
   AHA and the ESC all decline to recommend cuffless devices for clinical use.
   §3.3.
5. **Apple's silence is the tell.** With >100,000 training participants and a
   >2,000-person validation study, Apple ships a 30-day *notification* with
   41.2% sensitivity and no number at all — and tells anyone who gets one to go
   and use a cuff for seven days. §3.4.
6. **We have no PPG waveform, and that is not a small gap** — it is the whole
   input every published cuffless method uses. HealthKit does not expose it;
   SensorKit does, behind an Apple-granted research entitlement. §4.
7. **The real product is timing.** The estimator's honest job is not to guess
   today's pressure but to say **when one cuff reading buys the most
   information** — and to make that reading count. §6.
8. **The biggest single accuracy win available is measurement technique, not
   modelling.** On three of this reader's six multi-reading mornings the spread
   *within one sitting* was 21–27 mmHg. No model can be worth more than that. §6.2.

---

## 1. What the code does today

`InsightKit/Sources/InsightKit/Insights/BloodPressureEstimator.swift`
(`./scripts/where.sh BloodPressureEstimator`).

The design is already unusually honest and most of it survives this review:

- Cuff readings are the trusted value; the estimate is badged experimental and
  never overrides a reading less than 24 hours old.
- `estimate(currentRestingHR:currentHRV:calibration:)` fits OLS through the
  reader's own paired (cuff, resting-HR[, HRV]) points — a *personal*
  calibration, which is the right shape.
- `drift()` grades the model by walk-forward hold-out — fit on everything before
  a reading, then predict it. This is the correct evaluation and most vendors do
  not do it.
- `statedUncertainty(fit:drift:)` prints one ± , and takes the **widest** of the
  fit's residual SD, the measured hold-out error, and a 5 mmHg floor justified by
  ISO 81060-2. "An error bar is a promise and the honest promise is the weakest
  one that is still true" — that comment is correct and should outlive the
  estimator.

The known open defect binding this brief is **P15**: `currentRestingHR` is
`samples.meanValue(.restingHeartRate)`, a ~2-year mean sitting on the calibration
set's own mean, so `b·(x − x̄) ≈ 0` and the estimate is near-static by
construction. Any accuracy ledger recorded before that is grading a constant.

**§2 shows P15 is real but is not the load-bearing problem.**

---

## 2. The measurement: racing the estimator against the reader's own data

Replicated from `~/HealthSeed/exports/health-insights-export-new.json` by porting
`buildCalibration`, `estimate` and the hold-out loop to Python and running them
against the real samples. Per `docs/privacy-and-ip.md`, what follows is the
*shape* of the finding — errors, spreads, counts, correlations — never a reading.

### 2.1 Count the rows first

Standing rule: before writing "already arriving" about a source, count its rows
in the last 90 days.

| Signal | last 90 days | last 180 days | all-time | sources in the last 90d |
| --- | --- | --- | --- | --- |
| Blood pressure (systolic; diastolic identical) | **12 readings on 4 days** | 23 | 50, spanning 2020-10-05 → 2026-08-02 | Manual entry 8, Apple Health 4 |
| Resting heart rate | 137 | 275 | 367 | Shortcuts 57, Apple Watch 13, Oura 67 |
| HRV (RMSSD) | 67 | 117 | 117 (since 2026-03-15) | Oura 67 |
| HRV (SDNN) | 4,353 | 7,772 | 8,244 | Shortcuts 4,261, Apple Watch 92 |

Two things fall out immediately.

**The calibration set is a third the size the card believes.** Under
`buildCalibration`'s 24-hour pairing, 25 of the 50 readings find a resting-HR
sample at all (resting HR only reaches back to 2024-08-07); **23 sit inside the
180-day fit window — and those 23 fall on 7 calendar days.** The card's
"fitted to 23 of your own readings" is arithmetically true and evidentially
misleading: four readings taken in one morning are one occasion, not four
independent observations. Effective degrees of freedom are nearer 7 than 23, and
every ± computed from the larger number is too narrow by roughly √3.

**The reader cuffs in bursts, not on a cadence.** 50 readings on 15 distinct days
in six years; gaps between reading-days of 1, 2, 3, 15, 32, 99, 106 and 426 days
in the paired set. The estimator's maintenance rule — "two a month" — has
essentially never been satisfied, and no amount of prompting has changed that.
Any design that depends on regular cuffing is designing for a different person.

### 2.2 The race

Walk-forward: for each reading, fit on everything strictly before it, predict it,
record the signed systolic error. Identical hold-out for every contender.

**Per reading (bursts included, n=20 predictions):**

| Predictor | MAE | RMSE | within ±5 mmHg |
| --- | --- | --- | --- |
| Shipped estimator (P15 bug intact) | 13.6 | 16.7 | 35% |
| Estimator with **P15 fixed** (that day's real resting HR + HRV) | 15.8 | 26.9 | 40% |
| **Baseline: your last cuff reading, aged** | **9.7** | **13.0** | 45% |
| Baseline: your own running mean | 11.9 | 14.2 | 30% |
| Baseline: mean of your last two readings | 9.8 | 12.9 | 45% |

**Per reading-day (bursts collapsed to one value, n=4 predictions):**

| Predictor | MAE | RMSE |
| --- | --- | --- |
| Shipped estimator (P15 bug intact) | 12.1 | 13.7 |
| Estimator with P15 fixed | 11.5 | 13.7 |
| Baseline: last cuff reading, aged | 13.5 | 16.5 |
| Baseline: your own running mean | 12.6 | 14.0 |
| Baseline: mean of your last two readings | **9.4** | 15.5 |

**Read these honestly.** n=20 and n=4 are far too few to *rank* anything; the
day-level race in particular is four predictions and settles nothing. What they
do establish is the absence of the thing that would justify shipping a number:
**the estimator never wins clearly on either framing, and on the framing with the
most points it loses to the most trivial baseline in the world by 4 mmHg.**
Fixing P15 makes it worse per-reading and no better per-day.

That is the Aurora Project result (§3.2), reproduced on one person.

### 2.3 Why — the predictor has no signal in this reader

| Window | n | slope | r | fit residual SD | raw systolic SD |
| --- | --- | --- | --- | --- | --- |
| 180-day fit window | 23 | **−0.250** mmHg/bpm | −0.12 | **13.5 mmHg** | 13.3 mmHg |
| All paired history | 25 | **+0.069** mmHg/bpm | +0.03 | 15.3 mmHg | 14.9 mmHg |
| Per reading-day | 9 | +0.64 mmHg/bpm | +0.26 | — | — |

**The slope changes sign depending on which window you fit.** That is what no
signal looks like. And in both windows the residual SD is *larger* than the SD it
set out to explain — the regression is worse than the reader's own mean, which is
the definition of a fit that has learned nothing.

The consequence for the on-screen number, which is the thing to hold on to:

> Fed **every real resting-HR sample of the last 90 days** (n=137, spanning
> 40 bpm, SD 7.5 bpm), the fitted estimate spans **10.0 mmHg** with **SD 1.9 mmHg**.
> Over a full year (n=285): span 11.3 mmHg, SD 2.1 mmHg.
> The reader's own systolic **SD across reading-days is 16.2 mmHg**.

So a fully P15-fixed estimator, driven by real daily data, reproduces about
**one-eighth** of the variation it is trying to track. P15 is a genuine bug and
should still be fixed — but fixing it converts a number that never moves into a
number that moves 2 mmHg while the truth moves 16. That is not an improvement a
reader can use; it is a more convincing wrong answer.

HRV is not the rescue either. `r(HRV, systolic) = −0.46` (n=18) and −0.62 per
reading-day (n=6) look promising until you notice n=6 occasions and no correction
for the fact that HRV and resting HR are two views of the same autonomic state.
The bivariate route does cut the residual SD (10.9 mmHg on the SDNN route) — but
that is three parameters fitted to 7 independent occasions, which is exactly the
overfit that a hold-out is designed to expose, and the hold-out above did.

### 2.4 A discrepancy to resolve, not to paper over

`~/HealthSeed/research/card-defect-diagnosis.md` (2026-08-07) records the card
printing **"±3, fitted to 34 of your own readings."** Neither number reproduces
from this export. The best residual SD any route reaches here is 10.9 mmHg
(bivariate/SDNN, 23 points), 13.5 mmHg on the route the code actually selects;
and the largest paired set available is 25 all-time, 23 in-window, against 34.

That gap has to have a cause, and it matters, because a ±3 on screen is a promise
that this data cannot support under any fit I can construct. Candidates, none
verified: the live app's HealthKit fetch windows differ from the export snapshot;
Withings readings present on device but absent here (the brief says 51 readings,
the export holds 50); or the diagnosis quoted a different quantity. **Do not
build the accuracy ledger until this is reconciled** — one of the two records is
wrong about how much evidence exists.

---

## 3. The literature

### 3.1 What cuffless methods actually measure, and why heart rate is not among them

Every published cuffless approach reads the **pulse waveform**, not the pulse
rate. Two families:

- **Pulse transit / arrival time (PTT / PAT).** Pressure raises arterial
  stiffness, which speeds the pressure wave. PTT is the propagation time between
  two arterial sites; PAT is measured from the ECG R-wave and therefore includes
  the **pre-ejection period**, a cardiac-contractility term that has nothing to do
  with pressure. Zhang, Gao, Xu, Olivier & Mukkamala (*J Appl Physiol*
  2011;111(6):1681–1686) measured the cost of that contamination directly: RMSE
  against diastolic pressure of **9.8 ± 5.8 mmHg for PAT versus 5.7 ± 2.0 mmHg
  for PTT** (p = 0.02); PAT's error was **72 ± 53% higher**. The theory and its
  limits are laid out in Mukkamala et al., *IEEE Trans Biomed Eng*
  2015;62(8):1879–1901.
- **Pulse wave analysis (PWA).** Features of a single PPG waveform's shape —
  augmentation, notch position, area ratios — fed to a regression or a network.

**Resting heart rate is in neither family, and there is a physiological reason.**
The baroreflex exists precisely to *decouple* heart rate from pressure: it slows
the heart when pressure rises and speeds it when pressure falls. Standing up
raises heart rate while pressure drops; a cold-pressor test raises pressure while
heart rate may fall. A regression of BP on resting HR is not a weak version of a
cuffless method — it is a different, and largely opposing, quantity. §2.3's
sign-flipping slope is that fact showing up in one person's data.

**Finding: no published curve exists relating within-person day-to-day resting
heart rate to within-person day-to-day blood pressure with an effect size a
consumer app could use.** I looked; what exists is population cross-sectional
association and large *between*-person heterogeneity — the MIPACT study (*Lancet
Digital Health* 2021), which collected exactly this pairing at scale, reports
distributions by demographic group rather than a within-person predictive
relationship. If someone later claims such a curve, ask for it by name.

### 3.2 The failure mode: calibration-tracking

This is the heart of the brief, and it is well evidenced.

**Falter M, Scherrenberg M, Driesen K, et al. "Smartwatch-Based Blood Pressure
Measurement Demonstrates Insufficient Accuracy." *Front Cardiovasc Med* 2022
(PMID 35898281). n = 40, Samsung Galaxy Watch Active 2.** Taffé-method analysis
found proportional bias anchored on the calibration point: at an estimated
112 mmHg the device read **+10 mmHg high**; at 142 mmHg, **0**; at 156 mmHg,
**−5 mmHg low**. The authors' own words: the watch *"tends to keep its BP
measurements closer to the calibration point than the BPs are in reality."*
Overall mean differences (−2.05 systolic, −5.58 diastolic) look fine and are
meaningless — the proportional bias cancels in the mean, which is why a
Bland-Altman summary is not a validation of a calibrated device.

**Mukkamala R, Shroff SG, Landry C, Kyriakoulis KG, Avolio AP, Stergiou GS. "The
Microsoft Research Aurora Project: Important Findings on Cuffless Blood Pressure
Measurement." *Hypertension*, published online 2 Dec 2022 (PMID 36458550).
n = 1,125 (642 auscultation arm, 483 ambulatory arm).** The decisive comparison:
PWA and PWA-PAT models were benchmarked against a **baseline model that used no
measurement at all** — only the calibration cuff BP and the time of day. The
waveform models' RMSEs were *comparable to the baseline's*. Conclusion: cuffless
devices "of no additional value" over predicting BP from the calibration reading.
The authors also flag the study's own limitation: it included **no intervention to
change BP appreciably**, so it tests the easy case and the devices still failed it.

**Tan I, Gnanenthiran SR, Chan J, et al. "Evaluation of the ability of a
commercially available cuffless wearable device to track blood pressure changes."
*J Hypertens* 2023;41(6):1003–1010. Aktiia Bracelet G1.**

- *Against 24-h ABPM, n = 41* (mean age 58 ± 14, 80% hypertensive): 24-h systolic
  **+4.9 mmHg [1.9, 7.9]**; daytime **+1.0 [−1.8, 3.8]** (n.s.); **night-time
  +15.5 [11.8, 19.1]** (p<0.001). The device recorded a night-time systolic dip of
  −4.8 ± 4.1 mmHg where ABPM measured −19.7 ± 7.4. **97.6% were misclassified as
  non-dippers, against 17.1% by ABPM.**
- *Against medication uptitration, n = 3*: home cuff monitoring recorded
  **−19.7 mmHg systolic**; the device recorded **−1.0 mmHg** (p = 0.03).
  Diastolic: **−11.5** versus **−0.8** (p = 0.04).

n=3 is three people and must be quoted as three people. But it is the cleanest
demonstration available of the failure mode's *shape*: the device was accurate in
the daytime, when the wearer sat near their calibration point, and blind to the
two occasions that mattered — night-time dipping and a real treatment response.
**A device that fails exactly when blood pressure changes has no clinical use,
because change is the only reason to measure.**

**Consensus positions.** Stergiou et al., ESH Working Group, *J Hypertens*
2022;40(8):1449–1460: cuffless devices "have specific accuracy issues, which
render the established validation protocols for cuff BP devices inadequate," and
ESH guidelines "do not recommend cuffless devices for the diagnosis and management
of hypertension." Mukkamala et al., *Hypertension* 2021 (PMID 34510915) make the
paradox explicit: BP estimates from a cuffless device *may be more accurate when
predicted by the calibration BP, or population/demographic priors, than by the
device's own measurement.* Parati et al., ESC scientific statement, *Eur J Prev
Cardiol* 2026;33(7):1058: calibrated devices "solely track BP changes relative to
the preceding cuff BP measurement," and "it remains unclear to what extent their
readings depend on the calibration BP" — the statement declines to recommend
consumer use. (The AHA's own scientific statement on cuffless devices,
*Hypertension*, DOI 10.1161/HYP.0000000000000254, is paywalled at 403 and was not
retrieved; do not cite its contents on my word.)

### 3.3 The standards, and who has passed them

| Standard | Scope | Status |
| --- | --- | --- |
| **ISO 81060-2** | Cuff (intermittent, automated) sphygmomanometers | In force. The familiar ≤5 ± 8 mmHg criterion. Not designed for cuffless. |
| **IEEE 1708-2014**, amended **1708a-2019**, revised **1708-2025** | Wearable cuffless BP devices | In force. Validation requires **a static test, a test with BP changed from the calibration point, and a test after a period has elapsed since calibration** — i.e. it was written to catch exactly the failure in §3.2. |
| **ISO 81060-3:2022** | Continuous non-invasive BP | In force. |
| **ISO/CD 81060-7** | *Intermittent or repeated-intermittent cuffless* — the category every consumer wearable is in | **Still a committee draft.** |
| **ESH 2023 recommendations** (Stergiou, Avolio et al., *J Hypertens* 2023;41(12):2074–2087) | Validation procedures for intermittent cuffless devices | Published; tailored by device type and calibration scheme. |

**Who has passed?** On the evidence I could find: nobody, against a cuffless
standard. The recurring statement in the review literature is that *no cuffless
device has been validated to ISO 81060-3:2022 or to the ESH 2023
recommendations*, and the ESC statement records the same. The validations vendors
cite are overwhelmingly against **ISO 81060-2** — a cuff standard, run in a
seated static condition, which by construction cannot detect calibration-tracking.
That is the single most important thing to know when reading a vendor claim.

### 3.4 Vendors: what they claim versus what they publish

**Samsung (Galaxy Watch).** Claim: BP from the watch after cuff calibration.
Publish: requires recalibration **every 28 days** with an upper-arm cuff. The
independent validation is Falter 2022 above (n=40) — insufficient accuracy,
calibration anchoring. A 2025 real-world study (Lee, Park, Seo & Lee, *Clinical
Hypertension* 2025;31:e21, **n = 896**, Galaxy Watch 6) found a pre-versus-post
recalibration systolic difference of **4.64 ± 4.73 mmHg** after only one week —
that is the model's own answer changing by ~5 mmHg because the anchor moved, not
because the reader's pressure did.

**Aktiia / Hilo.** The best-evidenced of the group, and worth reading carefully.
Publish: Vybornova, Polychronopoulou, Wurzner-Ghajarzadeh, Fallet, Sola & Wuerzner,
*Blood Press Monit* 2021;26(4):305–311, **n = 86**, one month, seated: mean ± SD of
differences **0.46 ± 7.75 mmHg systolic** and **0.39 ± 6.86 mmHg diastolic**,
per-subject SD 3.9 / 3.6 — passing criteria 1 and 2 of an ISO 81060-2 protocol
*adapted* for a cuffless wrist device. In July 2025 the Hilo Band (Aktiia G0
Blood Pressure Monitoring System) became the **first cuffless BP monitor cleared
by FDA for over-the-counter use** — cleared as a spot-check device, still
requiring periodic cuff calibration. Set that beside Tan 2023 (§3.2), which
studied the same device and found it blind to night-time dipping and to a
medication response. **Both are true.** Seated, near the calibration point, it is
accurate; away from it, it is not. That is the most precise statement anyone can
make about cuffless BP in 2026.

**Biobeat.** FDA-cleared 2019 (BB-613WP), PPG + pulse-wave transit time, with a
seated comparison against a sphygmomanometer in **n = 1,057** reporting high
agreement. Same caveat: a seated static comparison is the test that cannot fail
for a calibration-anchored device.

**Apple — and why the absence of a number is the finding.**
Apple ships **hypertension notifications** (Apple Watch, cleared September 2025)
and deliberately no blood-pressure value. What it does: reads the optical heart
sensor's assessment of how blood vessels respond to each beat, **passively over
rolling 30-day periods**, and notifies on a pattern consistent with chronic
hypertension. Development used training data from studies "totalling over 100,000
participants"; validation was a clinical study of "over 2,000 participants".
Reported performance from the FDA submission (via secondary coverage — the 510(k)
summary K250507 was not retrievable, so treat the figures as reported rather than
verified): **sensitivity 41.2%, specificity 92.3%.** Cohen and colleagues
(*JAMA*, 2026; PubMed 41661624) modelled it against NHANES 2017–2020 and put the
positive predictive value near **70%**.

The design logic follows directly:

- With >100k training participants and an optical sensor Apple designed itself,
  Apple is not short of data or signal. If a trustworthy daily number were
  available from a wrist PPG, Apple is the party best placed to ship it. **It
  didn't.**
- A notification degrades gracefully and a number does not. At 41.2% sensitivity
  a notification is honest — "we saw something, go check" — and its errors are
  actionable in one direction. A number carrying ±14 mmHg is not honest at any
  sensitivity, because readers act on the digits, not on the interval.
- **Apple's own recommended response to a notification is: use a third-party
  cuff for seven days and take the results to a clinician.** That is Apple
  saying, in shipped product form, that the wearable's job is to *route the
  reader to a cuff at the right moment* — which is §6 of this document.

**On relaying vendor composites.** If a Samsung or Hilo BP value ever arrives via
HealthKit, the app's standing rule applies unchanged: it may be **relayed as a
labelled second opinion, never blended** into our own figure. Their formulas are
undisclosed, their calibration anchors are invisible to us, and §3.2 says the
error is proportional to distance from an anchor we cannot see. A blended number
would inherit a bias no one on either side could compute.

---

## 4. What our data could honestly support

**We have no PPG waveform, and every method in §3.1 needs one.**

- **HealthKit exposes no photoplethysmogram.** It publishes derived quantities —
  heart rate, resting heart rate, HRV (SDNN, and RMSSD via partners), blood
  oxygen — and an ECG voltage series for `HKElectrocardiogram`. There is no
  optical waveform type. This is not an oversight to work around; it is the API's
  boundary.
- **SensorKit does expose it** — `SRPhotoplethysmogramSample` /
  `SRPhotoplethysmogramOpticalSample`, under
  `com.apple.developer.sensorkit.reader.allow`. That entitlement is granted by
  Apple to approved research studies via a SensorKit Research Proposal. It is not
  available to an ordinary App Store app, and a personal health app for one
  reader is not a research study. **Treat this as closed**, and record it here so
  no future session re-derives it.
- **Even with the waveform, §3.2 applies.** The Aurora Project had the waveforms,
  1,125 participants and Microsoft Research's resources, and beat nothing. Access
  to PPG is a necessary condition for a credible attempt, not a sufficient one.

So the honest inventory of what we have for blood pressure is: **cuff readings,
their dates, and their sources.** Resting HR and HRV are real signals about
autonomic state and belong on the card as context — they are simply not blood
pressure, and §2.3 measured how far they are from it in this reader.

### 4.1 The verdict, stated plainly as the brief requires

> **A numeric daily blood-pressure estimate, without a PPG waveform, cannot beat
> "your last cuff reading, aged." On this reader's own 50 readings it does not
> beat it — 13.6 mmHg mean absolute error against 9.7 mmHg — and the predictor it
> relies on has a within-person correlation with systolic pressure of
> approximately zero (r = −0.12 over the fit window, sign-unstable across
> windows). The app should stop printing a daily estimated blood-pressure number.**

The estimator's *machinery* should not be deleted. The hold-out loop, the
widest-of-three ±, the drift band and the calibration lifecycle are good work and
§6 reuses most of them. What should go is the claim on the front of the card that
a number derived from them is today's blood pressure.

---

## 5. What to do with the estimator instead

Three uses survive the verdict, in descending order of confidence.

**5.1 — Keep it, and show it as what it is: a check on the last reading.**
Reframed from "today's blood pressure" to "nothing in your autonomic signals has
moved since your last reading" it becomes defensible, because that is a statement
the data can carry: the fit's output moves ~2 mmHg across a year (§2.3), so a
*departure* from it is the only informative event it can produce. Requires the
P15 fix to mean anything at all, and requires that the number is never shown as
a pressure — only as an agreement/disagreement with the last cuff reading.

**5.2 — Keep the drift ledger, grade the *aged reading*, not the model.**
`drift()` already computes the right thing. Point it at the honest question:
**how wrong is your last cuff reading, as a function of how old it is?** That
curve is genuinely useful, is measurable from cuff readings alone, needs no
wearable, and is exactly what a reader needs to decide whether to cuff again.
Today it is not fittable here — 8 gaps of 1, 2, 3, 15, 32, 99, 106, 426 days with
absolute errors of 13.4, 3.5, 28.7, 5.7, 0.9, 8.5, 45.6, 28.0 mmHg, and no
discernible relationship at n=8. **Say "not enough readings to fit an ageing
curve yet" and show the eight points.** Thin data means print the error bar, not
show nothing.

**5.3 — Refuse the 30-day projection (`P15`'s second half) for now.**
There is no fitted basis for a horizon-widening band, and §2 says the level term
it would project from is uncertain to ±13 mmHg. A projection drawn on that is a
picture of noise. Revisit if 5.2 ever fits.

---

## 6. Optimal timing — the estimator's real product

The reader's own framing in the brief is right: *knowing when one cuff reading
buys the most information* may be worth more than any estimate. The evidence
supports it, and it is buildable now.

### 6.1 How much information a reading buys

- **A single reading buys little; a short protocol buys a lot.** Bello, Schwartz,
  Kronish, Oparil, Anstey, Wei, Cheung, Muntner & Shimbo, *J Am Heart Assoc*
  2018;7(20):e008658, **n = 316** untreated adults over 14 days of home
  monitoring: **three days** of home BP monitoring using the average of **two
  morning and two evening** readings is sufficient to reliably estimate mean home
  BP and diagnose out-of-clinic hypertension. Single morning or evening readings
  need more days for the same reliability.
- **The standard protocol is the "722": two readings, two occasions a day,
  seven days** — 28 readings — **with the first day discarded** because first-day
  values run high and variable. ESH guidance accepts 4–7 days (12–24 readings)
  after discarding day one.
- **Morning versus evening: both predict, differently.** The Ohasama study
  (*Hypertension* 2006) found morning and evening home BP predicted stroke
  equally as continuous variables, while *morning-predominant* hypertension —
  morning ≥135/85 with evening <135/85 — carried significantly higher risk than
  controlled BP. So a card asking for one occasion a day should ask for **morning**
  and should say why; a card asking for the pattern should ask for both.

**What this licenses the app to say.** Not "cuff twice a month to keep an
estimate alive" — a maintenance tax on a model, which the reader has ignored for
six years and was right to. Instead: **"a three-day burst, morning and evening,
two readings each, tells you where your blood pressure actually is. You last did
something like that on <date>."** The reader already *behaves* in bursts (§2.1) —
four readings on one morning, three the next day. The app should recognise the
burst as the unit, name it, and complete it, rather than counting individual
readings toward a monthly quota.

### 6.2 The largest available accuracy win is technique, not modelling

On this reader's six multi-reading mornings, the spread **within a single
sitting** was:

| occasion | readings | systolic range | SD |
| --- | --- | --- | --- |
| A | 5 | 6 mmHg | 2.2 |
| B | 3 | 9 mmHg | 4.5 |
| C | 3 | **27 mmHg** | 13.5 |
| D | 4 | **27 mmHg** | 12.4 |
| E | 3 | 6 mmHg | 3.1 |
| F | 4 | **21 mmHg** | 9.9 |

Half of these sittings disagree with themselves by more than 20 mmHg — larger
than the difference between a normal reading and stage-2 hypertension, and larger
than any error any model in this document is arguing about. Two of the three are
recent.

The published causes are well quantified and all actionable. Muntner et al.,
*Measurement of Blood Pressure in Humans: A Scientific Statement From the American
Heart Association*, *Hypertension* 2019;73(5):e35–e66, is the reference; the AMA's
derived guidance puts a **full bladder at up to +33 mmHg systolic**, the **arm
below heart level at +4 to +23 mmHg**, and the **white-coat effect at up to
+26 mmHg**. First-reading-of-a-sitting effects are of the order of ~5 mmHg
systolic from first to second reading, which is why European guidance discards it.

**So the highest-value feature on the Blood Pressure card is not an estimator.**
It is: a guided capture flow (rest, position, arm at heart level, don't talk,
empty bladder), **capture of two-to-three readings as one occasion**, discarding
or flagging the first, and a visible within-sitting spread with the honest note
that a >10 mmHg spread means the sitting should be repeated rather than believed.
This is the only intervention in this document with a documented double-digit
mmHg effect on the number the reader actually sees.

---

## 7. The card: concrete changes

Ordered by value. All respect the app's standing rules — modelled never dressed
as measured, every estimate states its own uncertainty, thin data prints the
error bar. Anything here that takes input from the reader is a new `InputKind`
and must go through `add-data-or-input`; the reading-occasion sheet in 7.2
certainly is.

**7.1 — Retire the daily estimated number from the dial and the headline.**
The dial's routing (fresh cuff → estimate → 30-day average) should become
fresh cuff → recent occasion average → "no current reading". `§4.1` is the
justification. Keep the estimate visible in its own clearly-labelled section as
5.1's agreement check, never as a pressure.

**7.2 — Make the *occasion* the unit, not the reading.**
Three places currently count individual readings and all three are wrong for it:
`buildCalibration` (23 points on 7 days, §2.1), `CalibrationStatus.recentReadings`
(the two-a-month quota), and `recentTrend` (a mean over the window). An occasion
= readings clustered within ~15 minutes; the card should show the occasion's
mean, its within-sitting spread, and how many readings it holds. This alone fixes
the overstated ± and makes the §6.2 spread visible.

**7.3 — A guided capture flow.** §6.2. Rest timer, position checklist, two-to-three
readings captured as one occasion, first flagged, spread shown.

**7.4 — Replace the maintenance nag with a burst prompt.** "Two readings a month
keeps the estimate grounded" is a tax on a model §4.1 says shouldn't exist. Replace
with the evidence-backed ask: three days, morning and evening, two readings each
(Bello 2018), and a plain statement of what the reader learns by doing it.

**7.5 — "How old is this number?" as a first-class element.** The subheadline
already carries the last cuff's age. Promote it: the card's honest primary claim
is *"this is where your blood pressure was N days ago, from an occasion of K
readings"*, with the §5.2 ageing evidence beneath it — including, today, the
honest empty state that the ageing curve is not yet fittable.

**7.6 — A hypertension-pattern statement, done Apple's way, only if it can be
earned.** Apple's feature is a 30-day pattern notification at 41.2% sensitivity
from a sensor we cannot read. We cannot replicate it and should not imply we can.
What we *can* do from cuff readings alone is state the ACC/AHA category of the
reader's recent occasions, how many occasions it rests on, and how old they are —
which the card partly does. Do not add a wearable-derived risk flag.

**7.7 — If a vendor BP value ever arrives, relay it.** Labelled, sourced, dated,
beside our own — never blended (§3.4).

---

## 8. What would change the verdict

Written so a future session can check rather than re-litigate.

1. **More reading-*occasions*.** Everything in §2 is limited by 9 paired
   occasions. Thirty occasions spread across a range of pressures would let the
   hold-out actually rank the contenders. It would not fix §2.3's zero
   correlation, which is a physiological argument, not a sample-size one.
2. **A within-person published curve for resting HR → BP** with an effect size.
   §3.1 says none exists. If one appears, it changes the prior.
3. **PPG waveform access.** SensorKit entitlement, or a device that publishes a
   waveform to HealthKit. Necessary, not sufficient (§4).
4. **A device that passes ISO 81060-7 or IEEE 1708's change-from-calibration
   test.** Not the ISO 81060-2 seated static test. This is the claim to demand.
5. **The §2.4 discrepancy resolved** — whether the live app really is printing ±3
   over 34 readings, and if so, from what.

---

## 9. Sources

Everything cited above, with what was actually verified. Where I could not
retrieve a primary source I have said so rather than paraphrasing from memory.

| # | Source | Used for | Retrieved? |
| --- | --- | --- | --- |
| 1 | Mukkamala R, et al. Evaluation of the Accuracy of Cuffless BP Measurement Devices: Challenges and Proposals. *Hypertension* 2021 (PMID 34510915) | The calibration-beats-the-device paradox | Abstract + review summary; full text 403 |
| 2 | Mukkamala R, Shroff SG, Landry C, Kyriakoulis KG, Avolio AP, Stergiou GS. The Microsoft Research Aurora Project. *Hypertension*, online 2 Dec 2022 (PMID 36458550) | n=1,125; baseline-model comparison; no added value | PMC full text |
| 3 | Falter M, Scherrenberg M, Driesen K, et al. Smartwatch-Based BP Measurement Demonstrates Insufficient Accuracy. *Front Cardiovasc Med* 2022 (PMID 35898281) | n=40; calibration anchoring, +10/0/−5 mmHg | PMC full text |
| 4 | Tan I, Gnanenthiran SR, Chan J, et al. *J Hypertens* 2023;41(6):1003–1010 | n=41 ABPM, n=3 uptitration; night-time and treatment-response blindness | PMC full text |
| 5 | Vybornova A, Polychronopoulou E, Wurzner-Ghajarzadeh A, Fallet S, Sola J, Wuerzner G. *Blood Press Monit* 2021;26(4):305–311 | Aktiia n=86; 0.46 ± 7.75 / 0.39 ± 6.86 mmHg | Abstract |
| 6 | Zhang G, Gao M, Xu D, Olivier NB, Mukkamala R. *J Appl Physiol* 2011;111(6):1681–1686 | PAT 9.8 ± 5.8 vs PTT 5.7 ± 2.0 mmHg RMSE | Abstract |
| 7 | Mukkamala R, Hahn JO, Inan OT, et al. *IEEE Trans Biomed Eng* 2015;62(8):1879–1901 | PTT–BP theory and its limits | Citation only |
| 8 | Stergiou GS, et al. ESH WG statement. *J Hypertens* 2022;40(8):1449–1460 | ESH does not recommend cuffless devices | Full abstract |
| 9 | Stergiou GS, Avolio AP, et al. ESH validation recommendations. *J Hypertens* 2023;41(12):2074–2087 | Validation must be tailored by calibration scheme | Abstract |
| 10 | Parati G, et al. ESC scientific statement. *Eur J Prev Cardiol* 2026;33(7):1058– | "Solely track BP changes relative to the preceding cuff measurement"; ISO 81060-7 in preparation; no consumer recommendation | Full text |
| 11 | IEEE Std 1708-2014 / 1708a-2019 / 1708-2025 | Static + change-from-calibration + time-since-calibration tests | Standard abstracts |
| 12 | ISO 81060-3:2022; ISO/CD 81060-7 | Continuous in force; intermittent-cuffless still a draft | ISO catalogue |
| 13 | Bello NA, Schwartz JE, Kronish IM, Oparil S, Anstey DE, Wei Y, Cheung YKK, Muntner P, Shimbo D. *J Am Heart Assoc* 2018;7(20):e008658 | n=316; 3 days × (2 morning + 2 evening) | Abstract |
| 14 | Ohasama study, *Hypertension* 2006 (morning vs evening home BP and stroke) | Morning-predominant hypertension carries higher risk | Abstract/summary |
| 15 | Muntner P, et al. Measurement of BP in Humans: AHA Scientific Statement. *Hypertension* 2019;73(5):e35–e66 | Measurement technique is the dominant error source | Citation; PDF not text-extractable here |
| 16 | AMA, "4 big ways BP measurement goes wrong" | Full bladder +33 mmHg; arm below heart +4 to +23; white-coat up to +26 | Full text (secondary; AMA does not attribute each figure individually) |
| 17 | Lee, Park, Seo & Lee. *Clinical Hypertension* 2025;31:e21 | Galaxy Watch 6, n=896; 4.64 ± 4.73 mmHg pre/post-recalibration shift | Full text |
| 18 | Apple Newsroom, 9 Sept 2025, Apple Watch Series 11 | 30-day window; >100,000 training participants; >2,000 validation; advice is to use a cuff for 7 days | Full text |
| 19 | FDA 510(k) K250507 (Apple hypertension notifications) | Sensitivity 41.2%, specificity 92.3% | ⚠️ **Not retrieved** (404). Figures are as reported in secondary coverage — verify before quoting in-app |
| 20 | Cohen J, et al. Impact of a Smartwatch Hypertension Notification Feature for Population Screening. *JAMA* 2026 (PubMed 41661624) | ~70% positive predictive value against NHANES 2017–2020 | Secondary summary |
| 21 | Aktiia/Hilo FDA 510(k) OTC clearance, July 2025 (G0 BP Monitoring System) | First cuffless BP monitor cleared OTC; still needs cuff calibration | Press release + trade coverage |
| 22 | Apple SensorKit: `SRPhotoplethysmogramSample`, `com.apple.developer.sensorkit.reader.allow` | PPG waveform is entitlement-gated to approved research | Developer docs index |
| 23 | AHA scientific statement on cuffless devices, *Hypertension*, DOI 10.1161/HYP.0000000000000254 | — | ⚠️ **Not retrieved** (403). Listed so it is not re-hunted; nothing above rests on it |
| 24 | `~/HealthSeed/exports/health-insights-export-new.json` | All of §2 | Replicated locally; scripts in the session scratchpad |

**No number in this document was invented.** Where evidence does not exist —
a within-person resting-HR-to-BP curve (§3.1), an ageing curve for a stale cuff
reading (§5.2), a cuffless device that has passed a cuffless standard (§3.3) —
the absence is stated as the finding.
