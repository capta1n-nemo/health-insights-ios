# Energy, rebuilt — the design, v2 (backlog B19)

<!-- status: complete — design of record for B19 — all eleven fatal v1 findings fixed and every carried-over number recomputed. Designed, NOT built; §3.2 blocks code until Ingre 2014 is transcribed -->

_Written 2026-08-08. **Designed, not built.** Supersedes
`docs/energy-design-2026-08-07.md` (v1), which three hostile reviewers returned
`needs-rework` with a combined list of fatal findings. **Every fatal finding is
fixed here, and every number carried over from v1 has been recomputed.** v1
remains on disk as the archive of the full per-substance evidence prose and the
three review transcripts; nothing in it may be built from._

> *"I Just want more data sources to go into it, plus go and research the best
> way to calculate this. I want to use every possible data source that we have
> in our app, that is applicable to energy. Like.. every substances.. they can
> help with energy.. they should go into this, but short-lived, we just need to
> learn how substances do or do not impact me (by substance type)."*

**Evidence base for this pass** — all of it now on disk, none of it re-derived
here:

- `docs/energy-design-2026-08-07.md` — v1's citations and the three reviews.
- `docs/signal-audit-2026-08-08.md` — what every card reads and could read,
  coverage counted per metric; the weight-provenance ledger and its rules.
- `docs/sleep-debt-research-2026-08-07.md` — the two-process/sleep-debt
  framework: Van Dongen 2003 in full, the baseline problem, recovery
  non-linearity, the honest ceiling (device-derived sleep → next-day vigilance
  R² = 0.13).
- `docs/nutrition-bootstrap-research-2026-08-08.md` — energy expenditure from
  what we hold: the theatre line, wrist-device active-energy error, what
  cancels in a within-person comparison.

Coverage figures are the signal audit's counted values (90 days ending
2026-08-07). Per `docs/privacy-and-ip.md`, no reading from this reader's body
appears in this file — counts, coverage, code constants and published figures
only.

---

## The fatal findings, and where each is fixed

| # | v1 fatal finding (short form) | Fixed in |
| --- | --- | --- |
| 1 | SD/variance labels swapped — the "85% of the variance" headline was fabricated | §4.2 — recomputed: σ_model is **84% of the SD, 71% of the variance**; the fabricated sentence is deleted and its replacement derived |
| 2 | Ribbon treated σ_person (a between-subject intercept that cancels within-day) as independent per-point noise | §4.3 — **two bands**: a level band (curve slides) and a within-day contrast statement; σ_person appears only in the level band |
| 3 | Substance thresholds understated ~2× (paired d divided by per-night SD, not SD of the difference; pairing rule never stated) | §6.4 — pairing rule stated first, whole table recomputed with SD_diff = √2·SD_night, then divided by outcome coverage |
| 4 | No multiple-comparison policy over ≥20 tests | §6.5 — one pre-registered outcome per class, a stated across-class α rule, and a prohibition on BH/permutation corrections on this record (measured invalid here: backlog r = −0.795, null ~2× anti-conservative) |
| 5 | Two of four bands unreachable under the design's own parameters | §3.5 — the invented 25-point bands are deleted; bands become the **KSS scale's own published verbal anchors**, reachable by construction, with a stated clamp |
| 6 | Weight-bearing inputs were sleep timing alone — the number became a clock | §2 — the card's weight-bearing, intraday-moving content is **measured expenditure against the reader's own record**; the alertness curve is a clearly-labelled model owned by the sleep domain and relayed here |
| 7 | §3 rebuilt the shipped `SubstanceImpactInsight` without noticing it exists | §6.1 — one model, one card: the substance machinery is an **upgrade to `SubstanceImpactInsight`** (`SubstanceResponseAnalyzer.afterWindow`'s flat 18 h → per-class windows); Energy relays and links, and the reader is told the card exists |
| 8 | σ_sensor was a mean bias in quadrature, propagated through a foreign model's slope | §4.2 — deleted; the bias is named as a correction, the missing limits-of-agreement SD is named as the open item, and the "not your wearable's" sentence does not ship |
| 9 | σ_person zeroed after 12 PVT sessions, on a result from a different model family | §4.4 — never zeroed; the ±18 row and the "this curve can narrow" gate copy are deleted |
| 10 | Gate copy counted down toward substance exposures ("Nicotine 0 / 43") | §6.6 — no denominator is ever printed for a class with zero logged events; the advice test gains patterns that fail on such copy |
| 11 | §0's "sleep duration is roughly four times too strong" was a unit error | §1.2 — reframed: the shipped scale has no units, so **no published effect size can be compared with it at all** — the stronger finding; and the replacement must pass the same test before build (§3.6) |

Serious findings are folded in where they bite; the ones that changed the
design are: MAE→SD conversion on both phase errors (§4.2), the HRV
scale-consistency rule (§6.4), the GLP-1 epoch comparison withdrawn as a test
(§7.1), the missing-night MNAR widening (§8.2), the Departure-7 loophole closed
(§5), the two privacy "sits inside" sentences removed entirely (nothing in this
file states where any personal value sits relative to any interval), and
`Feedback.swift:169` (not :170) → `energy-v2` (§3.7).

---

## 1. The diagnosis — kept, corrected

### 1.1 What survives from v1 unchanged, because it is checkable

**The shipped card is not miscalibrated. It has no calibration.** The constants
in `Energy.swift` that set its entire dynamic range appear in no literature:

| Constant | `Energy.swift` | What it decides |
| --- | --- | --- |
| `fullChargeSleepHours = 8.0` | :133 | 4 h vs 8 h of sleep moves the morning charge **37.5 points** |
| `minimumMorningCharge = 25.0` | :136 | the floor |
| `recoveryPointsPerSD = 8.0` | :140 | ±2 SD of overnight HRV moves **16 points** |
| `fullDrainActiveKilocalories = 1_100.0` | :144 | 550 kcal drains **50 points** |
| `fullDrainExertionHours = 8.0` | :147 | 4 h above resting drains **50 points** |
| `trickleRechargePerHour = 2.5` | :153 | a quiet 8 h returns **20 points** |

- **HRV moves the card 16 points on an association nobody has found.** The best
  within-person study of wearable HRV against subjective vigor (Smyth/van
  Berkel 2023, n = 8, 125–386 paired observations per person) found HRV
  predicted vigor in **0 of 8** participants. Small study, stated as
  suggestive — and still the wrong direction of evidence for a term worth a
  sixth of the scale.
- **No published model converts kilocalories to alertness**, so
  `fullDrainActiveKilocalories` is an invented exchange rate by construction.

### 1.2 The sleep-strength claim, restated honestly

v1 said sleep duration was "roughly four times too strong" (37.5 points vs
9.5). Two reviewers showed that comparison is invalid: the shipped 0–100 has no
units, so its 37.5-point move **cannot be compared with any published effect
size** — and the 9.5-point figure extrapolated Kuula/Bauducco's within-person
observational slope (β = −0.19 KSS/h, adolescent actigraphy, ordinary
night-to-night variation) four hours past its fitted range, against regression
dilution and a nonlinear homeostatic response (Van Dongen 2003 shows 4 h and
6 h diverging strongly on objective performance).

**The honest version is shorter and stronger:** the shipped card moves 37.5
points on a scale with no units, no provenance and no error bar. Nothing needs
to be "four times" anything for that to be disqualifying. The 9.5-point figure
survives only as an illustration of how small the one available within-person
coefficient is — never as a ruling — and **the replacement model must pass the
same test before it ships** (§3.6): compute its own 4 h-vs-8 h swing from the
resolved Process S and print it beside 37.5. If it is not materially smaller,
the difference between the two cards is provenance and error bars, not
magnitude, and the document must say exactly that.

### 1.3 What the signal audit adds

`docs/signal-audit-2026-08-08.md` §3.4: **Energy's inputs were never the
problem.** `activeEnergyBurned` 86/90 days, `heartRate` 80/90,
`restingHeartRate` 70/90, `sleepDurationHours` 68/90, rMSSD 67/90, steps
90/90 — every input is dense. The reader's ask was "more data sources"; the
measured answer is that the *arithmetic* was the defect, and the audit's rule
now applies to everything below: **a weight is a claim, and a claim needs a
named source, a derivation with no free parameter, the reader's recorded
decision, or the word "guess" beside it.**

---

## 2. What Energy is for — the clock finding, fixed structurally

v1's fatal defect #6: after deleting the invented constants, its only
weight-bearing inputs were sleep duration and sleep timing. Every measurement
taken after waking sat at weight 0, so the number was a function of (wake time,
last night, clock) — a clock wearing a reservoir fill. The reviewer's census
also showed the design answering four other cards' questions (Oura stress →
Sustained load's, GLP-1 epochs → Sustained load's window, gait → Gait's,
substances → Substance Impact's) while giving away the one thing no other card
has: **Energy is the fleet's only intraday card.**

v2's resolution, in one sentence: **the card's weight-bearing, intraday-moving
content is measured; the model is context, clearly labelled, owned elsewhere;
and the learning lives on the card built for it.**

The card has three sections:

| Section | Content | Status |
| --- | --- | --- |
| **A. What you have actually spent** (§2.1) | today's active energy, time above resting HR and steps, each **as a percentile of the reader's own last-90-day distribution**, in its own units | **measured, weight-bearing** — this is what moves during the day |
| **B. The charge model** (§3) | the two-process alertness curve, relayed from a **sleep-domain-owned** `AlertnessModel`, drawn with its level band and stated within-day resolution | **modelled, labelled as such, weight 0 in anything measured** |
| **C. Substances** (§6) | the substance shading (already the repo rule), the per-class published windows drawn as context on today's chart, and a link row to Substance Impact, where the reader's own record is compared against the priors | **relayed — one model, one card** |

Dropped from v1's scope, each routed to its owner: the Oura stress/resilience
relay (→ Sustained load, whose question it answers; also non-independent of
this card's HR layer — 59,069 of 73,654 intraday HR rows are `apple_health/
oura`, the same sensor, so agreement is not corroboration); the GLP-1 epoch
RHR shift (→ Sustained load's 28/90 window, and see §7.1); the gait strip (→
Gait, and no published within-day gait→alertness curve exists); the holiday
ledger shading (→ the history axis where it is already planned, H6). The
symptom-radar relay stays — one sentence, honest, no recomputation.

### 2.1 Section A — the measured layer, and why it needs no invented constant

Inputs and coverage (counted, signal audit §2): `activeEnergyBurned` 86/90 ·
`heartRate` 80/90 overall, 47/90 with ≥24 daytime quarter-hour bins ·
`stepCount` 90/90 · Oura `daily_activity.resting_time` / `sedentary_time`
80/90 (measured seconds, replacing the sample-count approximation at
`Energy.swift:319-323`).

The display for each channel is **today's cumulative value against the
distribution of the reader's own previous 90 days at the same time of day** —
"by 3 pm you have burned more than you had by 3 pm on 78 of your last 86
recorded days." That is a percentile: derived arithmetic with **no free
parameter**, which is the only weight-provenance category available here,
because no kcal→alertness conversion exists and v2 does not invent one.

Two measured facts make this honest where an absolute kcal figure is not:

- **Wrist/ring active-energy error is large and mostly systematic.**
  Shcherbina 2017 (n = 60, vs indirect calorimetry): the best wrist device had
  **27% median error** for energy expenditure; none was accurate. An absolute
  kcal number therefore prints with that stated. But **a rank against your own
  record from the same device largely cancels the systematic component** — the
  same instrument mis-measures today the way it mis-measured the last 90 days —
  leaving day-to-day device noise. This is the same cancellation argument the
  nutrition research (§2.3 there) established for BIA lean-mass *changes*, and
  it is why the percentile leads and the kcal figure is the caption.
- **Never summed across channels.** kcal, minutes above resting and steps are
  unlike units; a blend would need invented exchange rates — the exact defect
  being deleted. Three rows, three units, three percentiles.

`restingHeartRate` remains the line exertion is counted above, not a term
(`Energy.swift:85-88`, unchanged rationale). Days with fewer than 24 daytime
HR bins fall back to steps (90/90) and the row says which it used. The two
Oura activity metrics are new `MetricType`s — load `add-metric-type`; the Oura
seconds are the same sensor as the HR layer, and the section must not present
the two as independent confirmation.

**What section A never claims:** that spending more or less energy today makes
the reader more or less tired. No published within-person kcal→alertness
coefficient exists (v1 §2, unchanged and re-checked). The section reports what
happened, in measured units, against the reader's own history — full stop.

---

## 3. Section B — the charge model

### 3.1 The model and its owner

**The Three-Process Model of alertness (Åkerstedt & Folkard), Ingre et al.
2014 field refit** (PLOS ONE 9(10):e108679, open access; n = 136 aircrew,
5,744 KSS ratings) — Processes S and C, U implemented and off by default, the
KSS transform. All of v1 §1's framework choice, rejected-alternatives table and
parameter table survive review and are incorporated by reference; the
parameters are **not** retranscribed here to avoid a second drifting copy.

**The model is built once, in InsightKit, owned by the sleep domain — not by
Energy.** `docs/backlog.md` B18-7 says it in terms: *"Build them against one
model rather than two."* The same S process is the sleep-debt section's
homeostatic machinery (B18-7) and the same C anchor is the ideal-timeframe
section's (B18-8). The Sleep card hosts the model's own section ("what last
night means for today"); **Energy relays the curve** exactly as it relays the
radar's verdict — a labelled read of another card's model, never a second
implementation. This is fatal finding #6's second half fixed: the clock lives
where the clock's inputs live.

### 3.2 The blocking transcription error — still blocking

v1 §1.3 stands verbatim: the Process S wake equation as transcribed
(`S(t) = ha − (ha − sw)·e^(d·t)`, d = −0.0353) approaches the **upper**
asymptote during wake, which is the sleep-recovery form. **Nothing may be
built until both equations are copied from Ingre 2014 itself and the
sleep-recovery rate obtained** (it is absent from every evidence pass so far
and may not be guessed). The test assertions that are safe now: S is monotone
between 2.4 and 14.3; the wake time-constant is 28.3 h so a 16 h day moves S
43% of the way to its asymptote; C peaks near the acrophase; KSS falls as
alertness rises.

Every worked number in this section is conditional on that resolution and is
labelled so.

### 3.3 The departures — carried, with two changes

v1 §1.4's departures survive review and carry forward: **W drawn as a hatched
no-value region** (shape published — Jewett 1999 τ = 0.67 h agreeing with the
model's own Wd⁻¹ = 0.66 h — magnitude not); **U off by default** (Ingre's own
finding once chronotype sets phase); **phase from the reader's sleep midpoint**
with the two cited phase errors (Huang 2021, Stone 2021) selected by bedtime
regularity, the selection thresholds still stated as a guess that only chooses
between cited numbers; **no wake-maintenance-zone bump** (Bes/Sagaspe 2018:
undetectable in rested subjects); **sleep debt shown, never entering the
curve shape** (Van Dongen 2004: all six models ≈ a flat line under chronic
restriction); **sleep stages never in arithmetic** (JCSM 2025: 60–75% stage
accuracy).

The two changes:

1. **Phase errors converted MAE → SD.** Huang's 0.964 h and Stone's 2.88 h are
   mean absolute errors; for a normal error, SD = 1.2533 × MAE. §4.2 uses
   1.208 h and 3.609 h. (v1 combined MAEs in quadrature as if they were SDs — a
   named category error, fixed.)
2. **The feedback loophole is closed.** v1 banned tuning the curve to
   self-report and then permitted fitting inertia amplitude and phase to it.
   v2: **feedback is recorded and fits nothing** — not S, not phase, not
   inertia. The prohibition row (§5) now says so, so the test can be written.
   Whether a *level-offset-only* fit from self-report is ever defensible (one
   reviewer argued Van Dongen 2003 impeaches the slope, not the intercept;
   another required the loophole closed) is an open decision (§10), decided by
   nobody silently.

### 3.4 The transform

```
alertness(t) = S(t) + C(t)                    // U off
KSS(t)       = clamp(9.68 − 0.46·alertness(t), 1…9)
level(t)     = 100 · (9 − KSS(t)) / 8         // KSS 1 → 100, KSS 9 → 0
```

12.5 points per KSS unit — the line that makes every error figure convertible.
The clamp is new and stated: KSS is a bounded 1–9 ordinal, the model can
produce values outside it, and near either bound the residuals cannot be
symmetric — so the band ribbon is **truncated at the bounds and the
methodology text says so** rather than drawing a band to 111.

### 3.5 Bands — the unreachable-bands finding, fixed by not inventing bands

v1 kept the shipped High/Steady/Running-low/Drained 25-point cuts; under its
own worked day (peak ≈ 69, trough ≈ 43, conditional on §3.2) two of the four
could never light and the card was a two-state clock. **v2 deletes the
invented cuts entirely.** The band vocabulary becomes the **KSS scale's own
published verbal anchors** — "alert" (KSS ≤ 3), "neither alert nor sleepy"
(4–5), "signs of sleepiness" (6–7), "fighting sleep" (8–9) — which are part of
the instrument, not a house choice, and are reachable wherever the model can
actually go. The headline is the anchor phrase and the KSS value with its
band: **"neither alert nor sleepy — about 4.5 ± 1.7 on the 9-point sleepiness
scale"**, with the 0–100 level demoted to the ScoreHistory number (§3.7) and
the chart axis. A reading near an anchor boundary is a coin flip at this
model's resolution, and printing the ± beside a 9-point value makes that
visible in a way two digits on a 0–100 never did.

### 3.6 The pre-build test the replacement must pass

Before S2 ships (build order, §9): compute, from the resolved Process S, the
model's own morning-level difference for 4 h vs 8 h of sleep, in points, and
the **points-per-hour-of-sleep around a typical night**. Both go in this
document's §0 table beside the shipped 37.5. Two commitments follow:

- If the model's 4 h-vs-8 h swing is not materially smaller than 37.5, the
  design's premise is restated: the rebuild's gain is provenance and stated
  error, not magnitude.
- If points-per-hour is small against the clock-driven diurnal swing (the
  review's illustrative figure via Kuula's β is ~2.4 points/h — indicative
  only), that is precisely why the curve is **section B and not the card's
  weight-bearing content**, and the number must appear in the methodology text
  rather than be discovered by a reader.

### 3.7 Score continuity

`Feedback.swift:169` returns `energy-v1`. The relayed curve's level is a
different quantity and ships as **`energy-v2`** (the `fitness-v2` precedent),
or every score recorded before the change becomes silently non-comparable.
The six invented constants are deleted or parked one release behind a labelled
derived series — open decision carried from v1, unchanged.

---

## 4. The uncertainty statement — rebuilt from scratch

### 4.1 What kind of error each term is

The fatal defect in v1's §4 was structural: it summed unlike error types in
one quadrature and drew the result as a per-point ribbon. The taxonomy first:

| Term | KSS | Type | Behaviour within one person's day |
| --- | --- | --- | --- |
| σ_model = 1.42 | residual SD of Ingre's **best** model (S-with-brake + C + U), in-sample, against KSS self-reports | random, per observation — **its within-day autocorrelation is not reported**, so independence is an assumption, stated | adds scatter to every point; a two-point contrast carries √2 × 1.42 **if** independent |
| σ_person = 0.84 | between-subject intercept SD | **common-mode** | slides the whole curve; **cancels exactly in any within-day comparison** |
| σ_phase = 0.364 (regular) / 1.087 (irregular) | phase error × max circadian sensitivity; SDs via 1.2533 × MAE (Huang 2021: 1.208 h; Stone 2021: 3.609 h) × 0.3011 KSS/h | mostly common-mode-in-shape: shifts the peak's *time* | moves where the curve bends, not independent scatter |
| σ_sensor | **deleted** | v1's 0.053 was the JCSM 2025 **mean bias** (−16.85 min, a CI on a mean) put in quadrature and priced through a foreign model's slope. A bias is a correction, not a spread. The per-night limits-of-agreement SD is the right quantity, **is not in any evidence pass yet**, and must be read from the paper and propagated through the model's own ∂KSS/∂TST before any sensor term ships | — |

Three consequences of the first row, stated because v1 hid them: 1.42 is
**borrowed, not derived** (v1 claimed "every term is derived" while the two
terms carrying ~97% of the variance were citations); it is the residual of a
**better model than the one shipped** (U off, no brake — dropping U alone cost
deviance χ² = 32), so it is a **floor** on the shipped configuration's error;
and it measures agreement with **self-reported** sleepiness — the same
instrument §5 says fails to track chronic restriction — in-sample, on aircrew.

### 4.2 The level band — recomputed

Quadrature of σ_model, σ_person, σ_phase (no sensor term):

| Reader state | Arithmetic | KSS | 0–100 points |
| --- | --- | --- | --- |
| Regular sleeper | √(1.42² + 0.84² + 0.364²) | **1.69** | **±21** |
| Irregular sleeper / schedule shift | √(1.42² + 0.84² + 1.087²) | **1.98** | **±25** |

The corrected decomposition sentence — v1's fabricated "85% of the variance"
deleted: **σ_model is 1.42 of 1.69 — 84% of the standard deviation, 71% of the
variance** (regular case). The direction of v1's conclusion survives the
correction — the budget is dominated by the model, and more data sources do
not narrow it — but it is now stated with the right numbers and without the
sensor comparison, which cannot be made until the limits-of-agreement SD
exists.

### 4.3 The within-day statement — the band the swing must be judged against

σ_person cancels in any morning-vs-afternoon comparison; what remains on a
two-point contrast is √2 × 1.42 = **2.01 KSS ≈ ±25 points**, under the stated
independence assumption (if the residual is positively autocorrelated within a
day the contrast is tighter; no number for that exists in the fit). The whole
diurnal swing on a well-slept day is ~26 points (conditional on §3.2).

**So the honest headline is harsher than v1's:** judged against the correct
band, the model **cannot resolve its own diurnal shape at 1 SD of a
contrast**. v1 compared the swing against a band inflated by a term that
cancels, and still called it barely-resolvable. This is why the curve is
context (section B), why the band word is a KSS anchor rather than a
25-point cut, and why the card's weight-bearing content is measured (§2.1).

How it is drawn: **one ribbon, the level band**, truncated at the scale
bounds, `AreaMark(x:yStart:yEnd:)` (`FitnessProjectionChart` precedent, load
`add-chart`); the within-day resolution is a **methodology sentence, not a
second ribbon** — two nested ribbons would imply the decomposition is more
knowable than it is. In the chronic-restriction state (§5) the ribbon is
replaced by a **hatched no-skill region** — widen-when-uncertain, honoured
this time, and hatch-never-blend per the repo rule.

The printed methodology text, rewritten per review:

> This curve is a model of sleepiness, not a measurement of it. In the study
> it was fitted on — 136 airline crew, 5,744 ratings — it missed people's own
> sleepiness ratings by about 1.7 points on the 9-point scale (about 21 on
> this one). That is agreement with a self-rating, in the fitting sample; its
> error for you has not been measured. Within one day, the difference between
> your best and worst modelled hour is about the same size as the model's own
> resolution. Nothing here is a target.

### 4.4 Personalisation — no longer promised

v1 zeroed σ_person after 12 PVT sessions and printed ±18, on a 2B-Alert result
about a **different model family predicting PVT milliseconds**. Deleted: the
±18 row, the "this curve can narrow to your own response" gate copy, and the
12-tap-test slice as a promised ribbon reduction. A PVT-based fit remains a
research direction (§10) with no promised narrowing, because nobody can
currently say by how much — twelve noisy sessions estimate an intercept, they
do not eliminate its uncertainty.

---

## 5. What it may never claim

v1 §5's prohibition table survives review intact and carries forward by
reference (vendor composites relay-only with Doherty 2025; no LF/HF; no
"allostatic load"; no tirzepatide day-attribution; no multi-day alcohol HRV
window — the "5-day" claim traces to vendor blogs only; no evening bump; no
stages in arithmetic; no post-lunch dip assertion; never present a prior as
the reader's own response; `.acuteCardiacLoad` stays an ordering heuristic at
weight 0). New and changed rows:

| Prohibition | Basis | Enforcement |
| --- | --- | --- |
| **Never fit anything to self-report feedback** — not S, not phase, not inertia amplitude | Van Dongen 2003 (SSS failed to separate 6 h from 4 h while PVT diverged) impeaches the slope; the loophole v1 left for phase/inertia is closed pending §10 | new test: feedback records reach no fitted parameter |
| **Never apply Benjamini–Hochberg or a permutation null to this reader's substance record** | measured invalid on this record: BH under negative dependence r = −0.795; permutation null ran ~2× anti-conservative (backlog, prior finding) | new test: no such correction appears in the substance path |
| **Never print an episode denominator for a substance class with zero logged events** | a countdown toward an exposure is advice wearing a gate's clothes | extend `testItNeverGivesAdvice`: fail on `N of M`-pattern copy for zero-event classes and on "unlocks"/"needs N" copy attached to caffeine, alcohol, nicotine or cannabis |
| **Never compare one person's epoch delta against a group-mean CI** | a meta-analytic CI (e.g. tirzepatide RHR +2.05, 95% CI 0.96–3.13) is the uncertainty of a mean over 15,313 people; an individual will land outside it almost always. An individual comparison needs a prediction interval, which the meta does not supply | §7.1; test asserts no group-CI comparison ships |
| **Never draw the curve's ribbon as validated during chronic restriction** | Van Dongen 2004: RRMSE 75–100% across six models — no better than a flat line | the hatched no-skill region replaces the ribbon when the (shared, sleep-owned) restriction detector fires; its threshold is a stated guess |
| **Never blend section A's channels into one number** | kcal, minutes and steps are unlike units; the exchange rate would be invented | no blended figure exists in the model output |
| **Never present the Oura seconds and the HR layer as corroborating** | same sensor: 59,069 of 73,654 intraday HR rows are `apple_health/oura` | copy review; the section labels the shared source |

---

## 6. Substances — one model, one card

### 6.1 The shipped card exists, and this design upgrades it

`InsightID.substanceImpact` is shipped. `SubstanceImpactInsight`
(`InsightKit/Sources/InsightKit/Substances/SubstanceImpactInsight.swift:16`)
already does episode-gated before/after comparison over six signals with a
flat `afterWindow = 18 h` (`SubstanceResponseAnalyzer.swift:15`), a decaying
`SubstanceLoad`, and `alternativeExplanation` on every row. v1 rebuilt this on
Energy without naming it — fatal finding #7.

v2: **the substance machinery is an upgrade to Substance Impact, not a second
implementation.**

- `SubstancePrior` (per class: τ, attribution window, direction, published
  effect, citation, `nil` where none exists) replaces the flat 18 h window
  with per-class windows — including nicotine's two-night sign flip and the
  formulation-dependent stimulant window.
- The recomputed power thresholds (§6.4) give
  `SubstanceEpisodes.minimumEpisodesToDescribe` the derivation it lacks.
- **Energy's part** is exactly what the reader asked for, where it is honest:
  the substance shading (already every chart's rule), the **published
  short-lived windows drawn as hatched context** on today's chart — per class,
  on the affected metric's own axis, never added to any number — and a link
  row: *"how substances affect you, learned from your own record, lives on
  Substance Impact."* The reader is told plainly that the card exists and why
  the learning stays there (the prior may never touch Energy's numbers, so
  Energy cannot host the comparison).

### 6.2 The reader's record — recounted, unchanged

18 events, all in the last 90 days, 9 distinct days: 17 stimulant, 1 cannabis.
Under the 24 h gap rule: **5 episodes** (4 stimulant, 1 cannabis). No dose, no
formulation, no note on any event. Zero caffeine, alcohol, nicotine events.

### 6.3 The per-class priors — carried forward

v1 §3.2's per-substance evidence survived all three reviews explicitly and
carries forward by reference (it is the best part of v1 and is not
re-transcribed): caffeine (τ ≈ 5 h, huge CYP1A2 individual spread, dose decides
whether there is an effect at all, the withdrawal confound), alcohol (same
night + next day, never longer; point it at RMSSD/night-HR, not TST), nicotine
(two nights, sign-aware, REM rebound on night 2), cannabis ("no consistent
published effect" is the permitted claim; next-day essentially nothing),
stimulant (youth-derived sleep effect −0.59 SD stated as an assumption; +5.7
bpm daytime HR; window unknowable without formulation), GLP-1 (structurally
unanswerable at day level, t½ ≈ 5 d on a 7 d interval — epochs only), and the
remaining classes (`nil` prior — a finding, not a hole).

One consistency rule the reviews forced (two incompatible HRV figures were in
play): **all HRV power arithmetic and any drawn HRV band use the raw-scale
within-person RMSSD CV of 0.37 (Hannon 2025)**. Plews' 3–13% is the CV of
**lnRMSSD** — a log-scale quantity — and may be cited only for why a single
day is uninterpretable, never as a raw-scale error bar.

### 6.4 The episode thresholds — pairing rule first, then the recomputed table

**The pairing rule, stated before any arithmetic** (v1 never stated it, which
made its n non-computable): each exposure night is paired with **one clean
night drawn from the same 90-day window, at least 48 h clear of any logged
exposure** (clear of carry-over — the stimulant window can reach 10–14 h, and
nicotine's rebound spans a second night). Drawn nights are treated as
independent of the exposure night, so:

```
SD_diff = √2 × SD_night        d = |published effect| / SD_diff
n       = (z₀.₉₇₅ + z₀.₈₀)² / d² = 7.85 / d²      (80% power, α = .05 two-sided,
                                                    ONE pre-registered outcome)
```

Adjacent-night pairing would be tighter if nights were positively
autocorrelated, but adjacent nights are exactly the contaminated ones; the
independent draw is the defensible and conservative choice.

Within-person SDs: TST SD_night = 77.41 min (Bei, 8 pooled datasets, 2,404
sleepers) → SD_diff = 109.5 min. RMSSD CV_night = 0.37 (Hannon) → CV_diff =
0.523.

Then the correction v1 also missed: **an exposure episode whose night was not
recorded contributes nothing.** Sleep-outcome coverage is 68/90 = 0.76; RMSSD
is 67/90 = 0.74 (clean control nights are plentiful, so the exposure night's
coverage is the binding factor). Required episodes = n ÷ coverage.

| Substance | Pre-registered outcome | Published effect | d (vs SD_diff) | n paired | **÷ coverage → episodes needed** | v1 printed | Reader has |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Caffeine 400 mg (lab) | TST | −70 min | 0.64 | 19 | **25** | 10 | 0 |
| Caffeine (meta) | TST | −45 min | 0.41 | 46 | **61** | 23 | 0 |
| Stimulant | TST | −0.59 SD | 0.42 | 45 | **60** | 23 | **4** |
| Alcohol, high dose | RMSSD | −21.3% | 0.41 | 47 | **64** | 24 | 0 |
| Nicotine (patch) | TST | −33 min | 0.30 | 87 | **115** | 43 | 0 |
| Cannabis | TST | −24.5 min | 0.22 | 157 | **207** | 77 | 1 |
| Alcohol, moderate | RMSSD | −9.4% | 0.18 | 243 | **327** | 122 | 0 |
| Alcohol (meta) | TST | −10.1 min | 0.09 | 922 | **~1,220** | 470 | 0 |
| Alcohol, low dose | RMSSD | −3.3% | 0.06 | 1,971 | **~2,650** | 990 | 0 |

Every v1 number roughly doubled from the SD fix and grew ~30% more from the
coverage fix — v1's printed integers were wrong by ~2.6× in total. **These are
still floors**: they assume perfect exposure logging, one outcome, and no
confounding; no correction factor for real-log violations exists, and the
table says so wherever it renders.

Notes on the outcome column: alcohol's literature points at REM, but sleep
stages are barred from arithmetic (60–75% stage accuracy), so the
pre-registered testable outcome is **RMSSD** — a stated tension, not an
oversight. Cannabis's row is nearly moot: its own prior is "no consistent
published effect", so the honest cannabis display is the prior itself, and the
threshold explains why the reader's single episode will never be contradicted
or confirmed by their own data.

### 6.5 The α policy

- **One outcome per class, pre-registered above, chosen from the literature
  before the reader's data is examined.** No other outcome may be tested
  against the log.
- When K classes carry analysable data, the per-class α is 0.05/K (the
  constant becomes (z₁₋α/2 + 0.84)²; at today's K = 2 that is ×1.2 on n; the
  table prints K = 1 numbers and the code applies the K in force).
- **No BH, no permutation null** — measured invalid on this record (§5), and
  the prohibition carries the citation to the backlog finding.

### 6.6 What the gates say — the countdown finding, fixed

- **Classes with logged events** (today: stimulant, cannabis) get the full
  honest state: episodes so far, the recomputed threshold, the smallest effect
  detectable at the current count against the published effect ("your record
  cannot yet agree or disagree with the published number"), the missing dose/
  formulation caveat, and **reachability at the observed rate** — 4 stimulant
  episodes per 90 days against a threshold of 60 is roughly **four years at
  the current rate**, and if use becomes near-daily the 24 h gap rule makes
  the count stop entirely (`SubstanceEpisodes.swift` already documents this).
  A threshold that is unreachable in principle is printed as such, never
  counted down toward. This is the reader's ask honoured at its real n:
  published priors against their record, with the episode count to change
  that stated — **and the episode count's own honesty stated too.**
- **Classes with zero events** print no denominator, no countdown, no
  "unlocks": *"No episodes of this are recorded, so nothing here is about you.
  The published short-term effect is shown above."* (Enforced, §5.)
- v1's §3.7 "the highest-value change is logging caffeine" is **withdrawn as
  card copy** — on a health card it reads as an invitation to consume. If the
  reader wants their caffeine question answered, the input design (dose in mg,
  timestamped, in the substance log rather than the daily dietary metric —
  Gardiner 2025: timing decides the effect) is in the backlog for them to
  choose, not on a card asking for it.

### 6.7 The covariate rule — the boundary flip, prevented

The step-count adjustment that collapsed a stimulant "effect" from min|z|
0.91 to 0.03 on this record stays, with the two fixes the review demanded:
the covariate is **steps in a stated exposure-relative window** (dose →
dose + window for the daytime outcome; wake → sleep-onset of the affected
night for the sleep outcome), never a calendar-day total (the 3 → 1 → 0
timezone flip is the precedent); any finding renders only if it survives
**two day-boundary definitions**; and both the unadjusted and adjusted
estimates print **as bounds** — steps are plausibly a mediator (the stimulant
causes the movement), so conditioning on them can remove real effect, and
neither number may be called "the" effect.

---

## 7. Relays and routings

### 7.1 GLP-1 — withdrawn as a test, kept as context

The day-level refusal stands (no unexposed day exists). The v1 epoch *test* —
reader's RHR shift vs the published +2.05 bpm — is withdrawn: the CI is a
group-mean's (§5), a single-subject before/after over autocorrelated daily
RHR has an effective n far below its day count, and the epoch is confounded
with concurrent weight loss (which the nutrition research confirms is the
mechanism's main observable). What ships: the medication **epoch band as
context** on the history axis, the published expectation quoted as a
population fact beside it, and no verdict. The multi-week RHR *question*
belongs to Sustained load's 28/90 window; the supported "you vs SURMOUNT-1 at
your dose" comparison is **weight and body-composition change**, which is Body
composition's, not Energy's (nutrition research §6.2 — there is no published
tirzepatide expenditure curve, and none may be invented).

### 7.2 Readiness will sometimes disagree with the curve — the stated rule

Readiness judges last night's body (HRV, RHR, temperature, respiration)
against the reader's own 28-day baseline; the relayed curve reads only sleep
timing against a population fit. On a morning where they disagree, **the card
says which question each answers** — one sentence, no reconciliation
arithmetic, no shared number: *"Readiness reads your body; this curve reads
your clock. They can disagree, and when they do, the body is the better
witness to today."* The second clause is supported (the curve has no
within-person validation at all; Readiness's baseline is at least the
reader's own), and it prevents the two-cards-contradicting-on-the-Today-tab
defect from arriving unexplained.

### 7.3 Sleep debt — owned by Sleep, per the research

`docs/sleep-debt-research-2026-08-07.md` decides this: the defensible display
is *"hours below your own recent typical"* with a live-derived band and the
KSS-saturation education copy, and it is B18-7's section on the Sleep card.
Energy does not duplicate it. What Energy inherits is the **shared
chronic-restriction detector** (one definition, sleep-owned, threshold a
stated guess) that swaps the curve's ribbon for the no-skill hatch (§4.3), and
v1's underived "±3.5 h" sleep-debt band is **deleted** — the research
document's own derivation replaces it wherever the Sleep section prints one.

---

## 8. Empty and learning states

### 8.1 The gate ladder

`CoverageGate` throughout; the card always shows (`isWorthShowing`
unconditionally true); the floor drops as in v1 — a missing night widens
rather than blanks. Changes from v1's ladder:

| State | v2 behaviour |
| --- | --- |
| No sleep source | existing `invitingInput`, unchanged |
| Nights recorded, none in 3 days | existing waiting copy, kept (written from a real defect) |
| Last night missing, ≥7 nights of history | §8.2 — MNAR-aware, not mean-imputation |
| Phase not yet anchored / regularity unknown | `need: 14` nights, **stated as a guess**, wider (±3.6 h SD) phase error until met — widen when uncertain |
| Personalisation | **row deleted** (§4.4) |
| Exertion layer | `need: 24` daytime HR quarter-hours; 47/90 days clear it; falls back to steps and says which it used |
| Per-substance | §6.6 rules |
| Oura relay rows | **moved off this card** (§2) |

### 8.2 The missing-night fallback, MNAR-aware

Nights go unrecorded non-randomly — ring charging, late nights, travel,
illness — so the missing nights are disproportionately the unusual ones, and
imputing the habitual value is mean-imputation under MNAR: it shrinks toward
typical exactly when the card should be least sure. v2: the curve draws from
the habitual **wake time** with the reader's own wake-time SD (not
night-length spread — the model needs a wake time, and v1 widened by the
wrong quantity) added to the phase term; the whole day renders in the
dash-means-inferred convention; and the copy says *"last night wasn't
recorded — this is your typical morning, which is exactly what today might
not be."* The widening is a floor, and the sentence carries what the widening
cannot.

### 8.3 The learning state is the normal state

Unchanged from v1, and truer under the recomputed thresholds: essentially
every gate is unmet, and a card showing the published curve, the measured
day, the reader's five episodes against the priors and an honest account of
how far short the record falls is more useful than a blank panel or a
confident lie.

---

## 9. Build order — revised slices

Phone-gating rule unchanged: anything whose visible output depends on `now`
being inside the data needs the phone; historical computation is
simulator-visible and testable.

| # | Slice | Notes |
| --- | --- | --- |
| S0 | Pin `now` to the newest data day behind a developer setting — **check a mechanism doesn't already exist** | enabler; simulator |
| S1 | `AlertnessModel` in InsightKit, **sleep-domain owned** — S, C, U(off), transform, clamp, level band. **Resolve §3.2 against Ingre 2014 first**; then run §3.6's pre-build test and write its numbers into this document | `swift test`, Linux-clean |
| S2 | Sleep card gains "what last night means for today" (hosts the model); Energy's chart swaps to the relayed curve: KSS-anchor headline, level ribbon, hatched inertia region, truncation, methodology text. **`Feedback` → `energy-v2`**; invented constants deleted or parked | phone; load `add-chart` |
| S3 | Phase from sleep midpoint; bedtime-spread selection of the two cited SDs; MNAR fallback of §8.2 | `swift test` + phone for today |
| S4 | Engine plumbing: `DerivedSeriesStore` reaches `evaluate` (unchanged from v1 — unblocks every card) | `swift test` |
| S5 | **Section A**: two Oura activity `MetricType`s (load `add-metric-type`), the three percentile rows, device-error caption, steps fallback | phone for today's layer |
| S6 | **Substance Impact upgrade**: `SubstancePrior`, per-class windows replacing `afterWindow = 18 h`, recomputed gates, α policy, prohibition tests (BH/permutation, zero-event denominators), covariate rule of §6.7. **Read `SubstanceImpactInsight.swift` and `SubstanceResponseAnalyzer.swift` first** | `swift test`; simulator |
| S6a | Dose + formulation on `SubstanceEvent` (load `add-data-or-input`) | unchanged from v1 |
| S7 | Energy's section C: prior-window context drawing + link row to Substance Impact; the reader-facing explanation that the learning lives there | simulator |
| S8 | Chronic-restriction hatch, wired to the shared sleep-owned detector | `swift test` |
| S9 | Radar relay sentence (kept); Readiness-disagreement sentence (§7.2) | `swift test` |

Dropped from v1's plan: old S8 (GLP-1 epoch test — withdrawn, §7.1), old S9
(Oura relay — routed to Sustained load, its own backlog row), old S11 (PVT
personalisation — no longer promised, §4.4; remains a research note).

Docs to bring forward in the same commits: `docs/card-sections.md` (Energy's
bespoke sections change; regenerate `./scripts/card-map.sh`), `docs/backlog.md`
(B19 ruling; new rows for the Sleep-card section, the Substance Impact
upgrade, and the Sustained-load Oura relay), `docs/research-notes.md`,
`docs/symbol-index.md` after S1/S5/S6.

---

## 10. Open decisions

1. **§3.2 remains blocking** — the Process S wake equation and the
   sleep-recovery rate must be copied from Ingre 2014 before S1. Every worked
   number here is conditional on it; §3.6's two committed computations run
   immediately after.
2. **Does the card keep the name "Energy"?** Recommendation unchanged: yes —
   it is the reader's word and `InsightID.energy` continuity depends on it;
   the subtitle carries "measured activity · modelled alertness". The
   alternative (splitting into an "Activity today" card and a Sleep section)
   is now structurally easy under this design and is the reader's call.
3. **A level-offset-only self-report fit** — two reviewers disagreed (§3.3).
   v2 ships with feedback fitting nothing; the question of whether a mean
   offset estimated from many feedback ratings may ever adjust the curve's
   *level* (never its slope, phase or inertia) is open and needs the reader's
   view, because it trades a cited prohibition against ~10 points of possibly
   removable offset.
4. **Delete or park the six constants** — unchanged from v1; either way
   `energy-v2` ships.
5. **The bedtime-regularity selection thresholds** (≤1.0 h / >2.0 h) remain a
   stated guess that only selects between two cited SDs. Note added per
   review: the ±1.208 h (regular) figure is Huang's *model-grade* accuracy and
   the method here is sleep-midpoint, which Stone measured at roughly half a
   model's concordance — so treating ±1.2 h as the regular-sleeper phase SD is
   **optimistic**, and if the reader wants conservatism the irregular figure
   can be used unconditionally at the cost of a ±25-point band everywhere.
6. **Caffeine's alertness term** still requires UMP's published coefficients
   (Ramakrishnan 2016), not yet in any evidence pass. Obtain or ship
   sleep-effect-only. Do not invent a term.
7. **Where caffeine is logged** (substance log vs daily dietary metric) —
   unchanged; timing decides the effect, which argues for the substance log.
8. **The chronic-restriction detector threshold** (consecutive days below the
   Sleep card's typical) is a guess wherever it is set; Van Dongen 2004 gives
   failure at 14 days and no onset. The Sleep card owns the constant; this
   card only consumes the flag.

---

## What v2 deliberately did not change

For the next reviewer's economy: the framework choice and its
rejected-alternatives table (v1 §1.1), the per-substance evidence prose (v1
§3.2), the weight-zero rationale for every non-sleep input to the *model*
(v1 §2.3 — though most rows now live on their owning cards), the GLP-1
day-level structural refusal, the named refusal of the multi-day alcohol
window, U-off-by-default, the hatched inertia region, and the prohibition
mechanism — all survived three hostile reviews explicitly and are carried
forward by reference, not re-litigated.
