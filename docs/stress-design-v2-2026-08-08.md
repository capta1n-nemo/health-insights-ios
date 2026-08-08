# Stress — the design, v2 (backlog N1)

_Written 2026-08-08. **Designed, not built.** Supersedes
`docs/stress-design-2026-08-07.md` (v1), which was returned `needs-rework` by
all three of its adversarial reviewers. This document does not repair v1 — it
accepts the reviews' central finding and reaches the verdict v1 was refuted for
avoiding. Read v1 for its evidence tables (§2, §5) and its Oura source notes;
read this for the design._

**The reader's ruling, 2026-08-07, which stands and is not revisitable:**

> **BOTH, on one card** — a daytime signal and the sustained nocturnal one, with
> Oura's own number shown beside ours as a labelled second opinion, never
> blended in.

⚠️ All counts below were measured against
`~/HealthSeed/exports/health-insights-export-new.json` (`generatedAt`
2026-08-07T07:09:11Z) for v1 and the 2026-08-08 signal audit
(`docs/signal-audit-2026-08-08.md`), or derived in v1's adversarial reviews.
**Counts only — no reading from this reader's body appears here**, per
`docs/privacy-and-ip.md`.

⚠️ **What changed under this document since v1:** the holidays chain landed.
`SustainedLoadInsight` now scores time-since-leave at
`leaveShare = 0.10` through the shared `LeaveRecency`/`LeaveBlend` types, the
feedback version is already **`sustained-load-v2`** (`Feedback.swift:189`), and
every pre-leave score is marked non-comparable. v1's §5 rank 3 ("holiday ledger
read by nothing") and its slice 7 leave-wiring are **done** — the card already
reads the ledger, with the nothing-recorded-scores-nothing guard.

---

## 0. The verdict, stated first

**The daytime signal cannot justify itself as a figure, and this document says
so rather than designing around it.** It ships as a **rendering** — a
within-day chart of the reader's heart rate against their own hour-of-day
line — because a rendering is the substrate the card's two genuinely unique
features need: laying **Oura's opinion** and the **calendar's names** against
the reader's own day. It carries **no daily number, no band, no threshold, no
count, and no CoverageGate promising a figure later.**

The ruling is honoured on **presence**: both signals are on the card, both are
visible, Oura's number sits beside ours labelled and never blended. It is
honoured by refusing to mint a *duplicate figure* — which is what every
version of the daytime number turned out to be (§2).

Why this is the verdict and not a retreat:

1. **The figure was a re-parameterisation of a statistic another card already
   owns.** `EnergyModel.exertionHours` (`Energy.swift:317`) is
   fraction-of-time-with-HR-above-a-personal-threshold, in hours, from the same
   sample stream; its own doc comment names its purpose as "the strain that
   never became a workout — a bad commute, a stressful hour" — verbatim the
   arousal figure's job. Two within-day HR-elevation numbers on two cards,
   disagreeing, is the shipped outcome v1's slice 3 could not have prevented
   (§2.2).
2. **The figure's statistics did not survive derivation.** The "≈16% by
   construction" null was not derivable from the algorithm as specified (the
   baseline population was never stated, and `Baseline.robustScale`'s mandatory
   floor was never named); the AR(1) deflation was asserted at 2 where the
   cited source gives 2.84; and v1's own flagship worked example printed a band
   matching neither of its own formulas, on a day its own arithmetic scores as
   statistically null. A figure whose headline band cannot be reproduced from
   its own document is not a figure — it is a decoration with digits.
3. **On realistic days the honest band swallows the figure.** At one
   independent unit per hour, a 6-hour measurable day needs >45% of still hours
   elevated before it differs from the reader's own typical day at all.
4. **Coverage points below the floor.** 47 of 90 days clear the ≥24-of-48
   waking-bin rule *before* the stillness gate (which removes ~40% of waking
   bins by construction) and the post-exertion shadow. The marginal qualifying
   day lands near 3.5 measurable hours — under v1's own 4-hour floor. A figure
   that arrives on a minority of days is a permanent null wearing a progress
   bar.
5. **The promotion gate was expected to fail by its own arithmetic.** At ~25
   busy vs ~25 quiet working days the detectable effect floor is d ≈ 0.79;
   Work impact's measured pooled body difference is +0.445 SD, well under it.

**If a within-day figure is ever minted, it is minted inside `Energy`** — as
the successor to `exertionHours`, whose gates (wake, stillness, post-exertion
shadow, hour-of-day baseline) are genuine improvements to a statistic whose own
source calls itself "Crude, and honest about it" — and the Stress card would
*relay* it, exactly as it relays Oura's. One card owns within-day heart-rate
elevation. That is future work, recorded in §9, not a slice of this design.

---

## 1. Disposition of the fatal findings

Every fatal finding from the three reviews, and what v2 does about it. This
table is the contract; nothing below contradicts it.

| # | Fatal finding (short form) | v2's answer |
| --- | --- | --- |
| 1 | Weeks-level Oura comparison (τ-b vs `daily_resilience.level`) was pseudo-replication: ~6 independent level-changes in 63 days, detectable ρ ≈ 0.92, i.e. nothing — disproved by v1's own step-series argument two lines above | **The statistic is deleted.** Resilience renders as a step-series **picture only**, no τ-b, no detectable-ρ row, no agreement claim (§5.3) |
| 2 | AR(1) deflation asserted as 2; Bowman 2021's ~1 h timescale gives ρ = e^(−0.25) = 0.779 → VIF = 8.0 → ×2.84 | **Moot for the card: the count statistic is gone** (§0). Standing rule for any future statistic: autocorrelation deflation is *measured on the reader's own series*, never asserted, and 2 is not derivable from Bowman in either direction (§8 R2) |
| 3 | The worked example printed ±1.8 h — from neither of its own two formulas — on a day below its own 40.6% significance threshold, presented as a 2.3× excess | **No worked figure exists in v2.** The rendering prints no daily number. Standing rule: any example in a design doc must be reproducible from the doc's own formulas, and must state whether the example day differs from a typical one (§8 R3) |
| 4 | The "≈16% by construction" null was underivable: baseline population (gated vs ungated) unstated, `robustScale` floor unstated, MAD = 0 reachable on integer HR making z = ∞ on the calmest bins | **No threshold, no null.** The ribbon draws HR against a median ± scale band with no elevated/not-elevated cut. The baseline population is now specified (§4.2), the floor is mandatory and measured (§4.3), and a degenerate scale draws **no band** — never a zero-width one |
| 5 | The headline's closest competitor is `periodContrastCard` — section 4 of the *same card*, rendering the same four channels 28-v-28 — and v1's §6 never looked at it; nor at `MentalHealthModel` (14 v 120, rMSSD 0.6) nor `EnergyModel.morningCharge` (three of the four channels) | **§2.1 rewrites the overlap table against the actual card** and answers the question it raises: what the pooled 28-v-90 adds over the unpooled 28-v-28 sitting one section above the bespoke slot. The honest count of scoring readers of the nightly triad is six, and the missing weight registry is named (signal audit §5) |
| 6 | `stress.arousalHours` is `EnergyModel.exertionHours` with different parameters — same construct, same stream, same unit — and v1's differentiation table was false on the code ("movement counted in": Energy reads no movement input) | **No second figure is minted, anywhere** (§0). Within-day HR elevation belongs to Energy. The corrected reading of `exertionHours` is in §2.2 |
| 7 | The ship/no-ship gate — \|ρ\| ≥ 0.6 against `exertionHours` — had no power arithmetic at an n that cannot decide it (95% CI ≈ ±0.22 at n ≈ 47; wider at the ~30-day floor), was mechanically confounded by the very gates it tested, and 0.6 was itself an asserted threshold in a document forbidding asserted thresholds | **The gate is deleted along with the figure it gated.** The standing form for any future promotion question is incremental validity — does the candidate separate busy from quiet working days *after* `exertionHours` enters as a covariate — with its power stated up front (floor d ≈ 0.79 at ~25/group, against +0.445 SD measured; honest expectation: fails) (§9) |

Two further findings the reviews marked serious that reshape v2: the headline's
uncertainty was reported flatteringly (1 SE vs the daytime figure's 95%, wrong
estimator, zero-width at the curve's ends) — repaired in §3.2; and the Oura
day-level comparison has no by-construction null while sharing a sensor on most
days — repaired by gating the statistic behind a measured permutation null
(§5.2).

**What v1 got right and v2 keeps verbatim in spirit:** refusing to fit any
threshold to Oura's labels, and killing the Cohen's-κ proposal. Fitting our
statistic's shape to their undisclosed formula is merging by the back door, and
no leave-one-out reporting fixes it. All three reviewers endorsed that
paragraph; it is §5.4 rule 2 here.

---

## 2. The overlap question, answered against the actual card

The prompt for this card's whole existence is one line from 2026-08-03: the
honest version must answer a question the neighbours do not. The neighbours,
*all* of them this time:

| Reader of the nightly triad | Window | Channels shared with this card | Question it answers |
| --- | --- | --- | --- |
| Readiness | today vs baseline | all four (rMSSD 0.40, rHR 0.25, sleep 0.20 of its six) | how am I *this morning* |
| Symptom radar | 3 d vs 21 d, CUSUM | three (no sleep duration) | is something acute converging *now* |
| **This card's headline** | **28 d vs 90 d** | — | **has this lasted weeks** |
| ⚠️ `periodContrastCard` — **section 4 of this very card** (`PeriodContrast.windowDays = 28`, fed `resolvedContributions(result)`, i.e. this card's own channels) | last 28 d vs the 28 before | all four, unpooled | what changed lately, per channel |
| Work impact | 56 d, working days only | three (rHR, rMSSD, sleep) | do busy days cost the night after |
| `MentalHealthModel` | 14 d vs 120 d | one (rMSSD at 0.6) | has the last fortnight been worse |
| `EnergyModel.morningCharge` | today | three (sleep + HRV z + rHR) | what did last night put in the tank |

**Six scoring surfaces read the overnight rMSSD/rHR/sleep triad, and no
document reconciles their weights.** That is the signal audit's finding 8 (the
same signal carries five different weights in five cards; there is no weight
registry), now seven surfaces counting the unpooled contrast section. This
design does not fix the registry — that is `P-registry` scale work — but it
stops pretending the set is smaller than it is.

### 2.1 What the pooled 28-v-90 adds over the unpooled 28-v-28 one section above it

This is the question v1 never asked, and it has a real answer in two parts —
plus a concession.

1. **A different reference.** `periodContrast` compares the last 28 days with
   the 28 before them. A drift that began six or eight weeks ago has already
   contaminated that prior window: both sides are elevated, the delta reads
   ≈ 0, and the section goes quiet precisely when the situation is oldest. The
   headline's reference is the 90 days before the recent window, so the same
   drift stays visible until it is roughly a season old. **The headline is the
   only view on the card that can see an old drift; the contrast section is the
   sharper view of a new one.** They are complementary in exactly the way the
   card should say out loud.
2. **One joint statistic.** Four separate deltas invite the reader to OR them —
   and six signals each at 95% specificity, OR'd, give a 26.5% false-alarm rate
   (the arithmetic already in `SustainedLoadModel.evaluate`'s comments, learnt
   from the radar firing on a quarter of days). The pooled, clamped,
   coverage-normalised load is the correction for that, and it is what the
   score history trends.
3. **The concession.** On metric identity the headline *is* a pooling of
   nearly the same contrast the section beneath it renders. The defensible
   claim is the window arithmetic above, not novelty. The card's copy should
   relate the two ("the drivers below are this month against the last; the
   dial is this month against the season") rather than presenting them as
   unrelated instruments.

### 2.2 The Energy collision, on the corrected reading of the code

`EnergyModel.exertionHours` reads **heart rate only** — no step count, no
active energy (`Energy.swift:317-328`). It counts samples at
`≥ restingBaseline + 15 bpm` and scales by elapsed time. v1's differentiation
table ("Movement | counted in — it is the point") was false on the code; the
construct is *unexplained-or-explained HR elevation in hours*, which is the
identical construct the daytime figure proposed, minus the gates. Its stated
purpose — "the strain that never became a workout — a bad commute, a stressful
hour" — is a still, non-bout, elevated hour: the exact set the arousal figure
was defined to count.

**Consequence, and it is the design's spine: within-day heart-rate elevation
has one owner, and it is Energy.** This card mints no second number. The gates
v1 designed (wake, stillness, 180-min post-exertion shadow, hour-of-day
baseline instead of one daily resting figure) are real improvements *to
`exertionHours`* and are recorded in §9 as Energy work. If that lands, the
Stress card relays the result — the same relationship it has to Oura's number.

### 2.3 So what does the daytime *rendering* answer that nothing else does?

Three things, none of which is a measurement claim:

- **"What was that afternoon?"** — the ribbon is the only surface in the app
  where a named calendar block, a leave period, the modelled medication level
  and the substance log can be laid against the reader's own within-day line.
  Attribution needs a canvas; this is it. (Energy's bespoke within-day curve is
  a *cumulative drain* rendering — a different quantity answering "what did
  today cost", not "when did today run hot against my own typical hour".)
- **The Oura comparison needs a same-grain surface.** Oura's daytime stress is
  a 15-minute-grain product; comparing it against a nightly score is a category
  error. The ribbon is the only honest thing to put beside it.
- **Memory.** Oura's API returns two daily totals for a day in March; we keep
  the quarter-hour series. Inspectability is the advantage — v1's §4.2 already
  demoted "measurement" (59,069 of 73,654 HR rows are Oura's own sensor
  relayed through Apple Health; on most days this is one photoplethysmogram
  processed two ways).

Against the three scoring neighbours the rendering makes no claim at all — it
scores nothing, so it cannot compete with Readiness's morning verdict, the
radar's convergence test, or the headline's weeks-scale drift. That is the
justification, and it is only available to a rendering.

---

## 3. The nocturnal headline — unchanged in channels, repaired in honesty

### 3.1 What it is now (shipped state, for the record)

Four channels, 28 d vs 90 d, min 10 days each side, ≥ 2 channels, one-sided
clamped weighted mean through `ScoreCurve` — **plus, as of
`sustained-load-v2`, time-since-leave at `leaveShare = 0.10`** through
`LeaveRecency`/`LeaveBlend`: nothing-recorded-scores-nothing, the curve is a
published *fade-out shape* (de Bloom 2009; Kühnel & Sonnentag 2011) with a
floor well above zero, and the ceiling means no length of leave-drought can
move the dial more than ~5 points. The natural experiment v1 wanted ("did the
load lift on leave?") is now structurally available: the ledger and the score
history live in the same model.

| Channel | Weight | Coverage (signal audit) | Provenance (signal audit) |
| --- | ---: | ---: | --- |
| rMSSD | 1.0 | 67/90 | reasoned; **the ratio 1.0/0.9/0.6/0.5 is supported by nothing** |
| Resting HR | 0.9 | 70/90 | reasoned |
| Respiratory rate | 0.6 | 68/90 | reasoned |
| Sleep duration | 0.5 | 68/90 | reasoned, causally argued |
| Time since leave | 0.10 share | ledger | published *shape*, no published magnitude — and the copy says so |

The windows are published (Plews 2012/2014 for the 28-day median; Shaffer &
Ginsberg 2017 for RMSSD as the time-domain index); the weight *ratio* is house
judgment and the weight-provenance ledger says so. No channel changes in this
design, so the feedback version **stays `sustained-load-v2`** — a rename does
not change what the number means.

### 3.2 The uncertainty, on the estimator that ships

v1 derived the daytime figure's error in three tables and gave the headline one
flattering line. The reviews took it apart; v2 adopts their arithmetic as the
spec:

1. **One convention: 95%, both quantities.** The headline's per-channel
   departure carries an SE of ≈ ±0.30 SD (medians at n = 23 recent / 68
   reference), so the 95% band is **±0.59 SD before pooling** — and pooling
   cannot use the Kish count, because:
2. **`load` is a rectified weighted mean** (`Σ w·max(0, loadZ)/Σw`), not a
   weighted mean. Rectification biases it up: with per-channel SE 0.30, a
   channel with zero true drift contributes E[max(0,X)] ≈ +0.12 SD, so **a
   reader with no drift at all scores ≈ 95, not 100.** The card's null is "a
   little load" and the copy must never imply 100 is the resting state.
3. **±0.30 SD is a floor, not "the conservative end".** It assumes independent
   days within a channel (multi-week drift is the card's own premise; lag-1
   day correlation of only 0.4 inflates the median's SE ×1.53) and omits the
   ~14% relative error of `robustScale` at n ≈ 68. The within-channel
   day-to-day autocorrelation and the inter-channel correlation are both
   measurable from the export and are measurement-pass items (§7 M5).
4. **State the band in the units the reader sees, and state where it dies.**
   On the 0.5→1.0 `ScoreCurve` segment (slope −50 points/SD), ±0.30 SD is ±15
   points; a mid-scale score's 95% band covers roughly half the dial, and the
   honest rendering says so. Below the first anchor and above the last the
   curve is flat, so a mapped band collapses to zero width exactly at the most
   alarming reading. **Design decision: the band is computed and displayed on
   `load` in SD units** (the quantity the score is a rendering of, already
   emitted as the `pooledLoad` derived series), with the dial's band derived
   from it and annotated "≤/≥" where the curve clips. The worst reading on the
   card never prints as certain.

### 3.3 The balance-web spoke

The web renders a bare 0–100 under the word "Stress" with none of the card
body's mitigations — v1 marked it "unchanged" without examining it, and a
reviewer correctly objected. v2's answer: the spoke stays, because *every*
spoke on the web strips its card's caveats equally and singling this one out
would imply the other eight are cleaner — but the spoke's detail line (the text
a tap surfaces before the card opens) must carry the caveat driver's sentence,
and this requirement is part of the rename slice, not an aspiration.

---

## 4. The daytime rendering — "your day against your own line"

### 4.1 What it is

One chart, today by default, pannable back through days under the existing
chart conventions (`ScrollableMetricChart`, which also carries the substance
shading — the house rule, the reader's own, and not renegotiated here; it
marks *when something was logged, never what it did*, and the base-rate print
in §6 is what keeps it honest beside an arousal-shaped line).

- **The line:** quarter-hour heart rate through the waking day.
- **The band behind it:** the reader's own hour-of-day **median ± robust
  scale** over the trailing 28 days — a *typical-range ribbon*, not a
  threshold.
- **Gaps, never zeros:** bins gated out (asleep, moving, post-exertion shadow,
  < 3 samples) draw as gaps, with the gate named on scrub. A gated-out bin is
  a gap — Oura says the same about their own graph, and `add-chart`'s
  dash-means-inferred convention already has the vocabulary.
- **No number.** No hours count, no percentage, no verdict adjective, no
  daily summary anywhere on the card. The chart is the entire deliverable.

The gates keep v1's derivation (they are what make the band mean "your typical
*still* hour"): wake (sleep intervals), stillness (steps ≤ 10 and active
energy below the reader's own 60th percentile of waking-bin active energy,
28 d — and the copy calls this what it is, a quantile cut, not a measurement of
stillness), post-exertion shadow **180 min** (Presby 2023's HR shadow is
180–210 min; the shorter end preserves coverage and leaves a known upward bias
in the *displayed line*, which the scrub caption names), ≥ 3 samples per bin.

### 4.2 The baseline population, specified (fatal finding 4, part 1)

**The hour-of-day median and scale are estimated from the same gated
population the ribbon draws: still, waking, non-shadow bins with ≥ 3 samples,
trailing 28 days.** Ungated pooling would set the band from movement-inflated
values and the still line would sit permanently below it — the exact
undefined-null failure v1 shipped. The cost is a thin baseline in some hours;
the rule for that is §4.3.

DST and travel: the baseline keys on **local clock hour**, because waking life
is clock-scheduled — the 09:00 meeting moves with the clock, not the sun. The
cost, from Bowman's circadian amplitude (3.96 ± 1.86 bpm), is a transient of
order 1 bpm for up to 28 days after a transition; those days' band renders
dashed (inferred), per `add-chart`. Sydney's 92- and 100-bin DST days are
handled by building the day from actual local quarter-hours, never a hardcoded
96. Days containing a timezone change (`CalendarModel.timeZoneChanges` — it
already exists and is tested) draw the line without a band.

### 4.3 The scale floor, specified (fatal finding 4, part 2)

`Baseline.robustScale`'s own doc comment says the `floor:` parameter "is not
optional in practice" — MAD is exactly zero whenever more than half the values
are identical, which integer-rounded HR in a still hour reaches easily. The
existing headline guards this (`spread > 0` drops the channel); v1's daytime
algorithm had no guard, which would have flagged the calmest hours of the
calmest days as infinitely aroused. v2: the floor is **derived from measured
bin-to-bin noise in the measurement pass** (§7 M4), and wherever the scale
still degenerates the ribbon draws the median line with **no band** — a
degenerate scale is a fact about the data, not a license for a zero-width
certainty.

### 4.4 The sensor mixture, named

The intraday HR series blends Oura-relayed (59,069 rows) and Apple Watch
(14,543 rows) samples, while the app's nightly channels deliberately pick one
winning source and never blend (`VitalReader.dailySeries`). For a *band* the
hazard is smaller than for a count — a shifted mixture widens the band rather
than manufacturing elevation counts — but it is real: three afternoons with
the ring on the charger move the baseline. The measurement pass reports the
per-day mixture (§7 M2); if it is volatile, the band is drawn from the
dominant source only, per-day, and the scrub caption names the source. This is
the one place the rendering may need `VitalReader`'s source-selection
discipline extended to intraday data.

---

## 5. Oura beside ours — the relay, and the statistic it must earn

### 5.1 What ships first: the relay

Oura's fields are already visible in the Data tab (`RawFieldGrouping.swift`
files them under "Stress & resilience (Oura)" — backlog D28, done). What does
not exist is any way for a *model* to read them: `evaluate` takes
`[HealthMetricSample]` and `[VitalEvent]` and nothing else, and no
`InsightModel` can read a `RawMetricSample`. The precedent is exact and
already argued in the codebase: `VitalEvent` exists because "an
irregular-rhythm notification is a judgement Apple already made, with no unit
and no baseline" (`Insight.swift`) — which describes Oura's stress fields word
for word.

So: **`VendorOpinion`** + **`VendorOpinionReader.opinions(from:
[RawMetricSample])`**, mirroring `VitalEventReader.events(from:)`, fixed
allow-list, default `evaluate` overload so no other model is touched. Never
promoted to `MetricType` — a vendor's opinion is not a reading of a tissue.
Weight 0, the `vascularAge` rule, absolute.

The card's second bespoke section then renders, side by side and never on a
shared axis:

- our ribbon (§4) and headline, as ours;
- Oura's `stress_high` / `recovery_high` seconds and `day_summary` verdicts as
  theirs, labelled, with the caption "against your own recent distribution"
  wherever `stress_high` appears (it is a rank statistic — seconds in the
  wearer's own top quartile — not a strain measurement; and the unit is
  seconds, widely misreported as minutes);
- both denominators, printed, with each side's exclusion reasons counted
  separately. Measured: `stress_high`/`recovery_high` **89** of the last 90,
  `day_summary` **73**, `resilience.level` **63** — and 16 of the last 90
  carry seconds but no verdict, so the categorical denominator is smaller and
  those days must not silently vanish.

**Default heading: "Same sensor, two formulas."** 59,069 of 73,654 HR rows are
Oura's sensor relayed through Apple Health; the heading is honest by default
and is only upgraded if the measurement pass finds ≥ 20 watch-carried days to
stratify on.

### 5.2 The agreement statistic — gated, not promised

A day-level rank agreement (Spearman ρ of our day against theirs) is the one
genuinely novel statistic available — nothing else anywhere grades a vendor's
opinion against a same-device alternative. v2 keeps it as an ambition and
refuses to ship it until three measured prerequisites exist, because without
them it renders shared plumbing as a finding:

1. **A by-construction null.** Two own-distribution tail statistics computed
   from the same photoplethysmogram will correlate before any algorithmic
   agreement exists. Required: a **block-permutation null** (blocks ≥ 1 week,
   because both series carry weekly rhythm and serial correlation inflates the
   false-positive rate of a Fisher-z test, not just its power), computed on
   the same carrier, printed beside the observed ρ with the effective n.
2. **An honest denominator.** The shared-day count at the real waking-hours
   rule is *at most* 47 and unmeasured below it. Whatever the measurement pass
   counts is what prints — not v1's 77.
3. **A per-day summary on our side that is not a resurrected count.** The
   statistic needs a daily number; the card does not display one (§0). The
   summary used *inside* the statistic (e.g. time-weighted mean displacement
   above the band) is an internal quantity of this section, never surfaced as
   "your stress today", and its definition is fixed before the data is looked
   at (§8 R1: the family of statistics is pre-registered — one headline
   statistic, stated in advance; everything else is exploratory and says so).

**And the interpretation rule survives from v1 verbatim: disagreement is not
our error, and agreement is not our validation.** Oura has published zero
validation of Daytime Stress or Resilience — no n, no ground truth, no
accuracy figure. There is no gold standard on either side; the honest phrasing
is "we and Oura read these N days the same way on M of them, and here is what
the rest had in common".

### 5.3 The weeks level: a picture, not a statistic

`daily_resilience.level` changes ~2–3 times a month; over its 63 shared days
that is ~6 independent blocks, and at n ≈ 6 the detectable ρ is ≈ 0.92 —
nothing. **No τ-b, no detectable-ρ row, no agreement number at the weeks
level, ever, at any future n counted in days** (the effective n counts level
*changes*). What ships: our score line and Oura's resilience as a **step
series** on separate axes in one section, so the reader's eye can do what the
statistic cannot claim to.

### 5.4 The four rules (carried from v1, all three reviewers endorsing rule 2)

1. **Neither number moves the other.** Not as a prior, not a tie-break, not a
   low-confidence blend. Weight 0, exactly as `vascularAge`.
2. **No fitted thresholds, no Cohen's κ.** Choosing any parameter of ours by
   maximising agreement with `day_summary` is merging by the back door — our
   statistic would be a function of their undisclosed formula. We have no
   categories, by design; rank statistics need none.
3. **Print both denominators, always**, and each side's exclusion reasons,
   counted separately.
4. **No accuracy claim from the comparison, in either direction.** §5.2's
   phrasing is the ceiling.

---

## 6. Attribution — named coincidences, with the base rate printed

The "better than Oura" claim, in the only form it survived review: **our
advantage is attribution and memory, not sensitivity.** Oura can say *that*
the body ran hot, with a temperature sensor we lack and (mostly) the same PPG
that feeds our own line. It cannot say *what it was*. The calendar, the leave
ledger and a modelled drug level sit on the same device as the series, with
timestamps.

What v2 changes from v1:

- **The base rate prints.** A disagreement/elevation day annotated with "what
  else was true that day" is a guaranteed-hit generator when
  `activeMedicationLevel` alone covers 89 of 90 days: the marginal probability
  that any day carries *some* label approaches 1. So every label class prints
  its base rate — the fraction of **all** days carrying it beside the fraction
  of flagged days carrying it — or the section is a horoscope. A label whose
  two fractions match is noise and renders as such.
- **Weekday structure is respected.** Work impact compares working days with
  working days only, for a stated reason ("…what it actually found is that
  Saturday exists"). Any busy/quiet contrast this card ever draws inherits
  that rule.
- **The tirzepatide "check" is dropped; the coincidence stays.** v1 offered
  the published +2.05 bpm (95% CI 0.96–3.13) resting-HR effect as an
  expectation to check against. v1's own §8.3(c) arithmetic gives the observed
  shift an SE of ±0.9 bpm → a 95% interval of ±2.2 bpm: the entire published
  CI sits inside our noise, and weight loss pushes the same metric the other
  way across the same doses. A check that cannot fail is not a check.
  `activeMedicationLevel` remains a *named coincidence* on the timeline, never
  a quantified expectation. (Dose epochs, not injection days: with a ~5-day
  half-life on a 7-day interval there is no unexposed day; the unit of
  attribution is an epoch of weeks. Structurally unanswerable, not thin data.)
- **Substances stay shading and a caveat, with the corrected arithmetic.** 18
  events on 9 distinct days, no dose on any. v1's power figure used the
  one-sample formula (7.85/d²); the design is two-sample, ~15.7/d² **per
  group** — ~45 substance days per group at the d = 0.59 v1 cited, a figure
  that itself has no source and is withdrawn. The honest sentence: the effect
  size is unknown and the episodes are an order of magnitude short of
  estimating it.
- **Leave is already wired** (`sustained-load-v2`): the driver line, the
  blended share, and the derived output exist. The attribution section adds
  leave periods to the timeline labels — a rendering task only.
- **"Never because."** Every label is a coincidence in time. The section never
  says "because", and with the base rates printed the reader can see why.

---

## 7. The measurement pass — counts before code

Everything the reviews flagged as "unmeasured, and the design leans on it".
All counts; results recorded in this doc's next revision; nothing below ships
until its number exists. (v1's per-count privacy rule applies: counts and
shapes, never readings.)

| # | Measure | Decides |
| --- | --- | --- |
| M1 | Shared-day counts at the honest waking-hours rule, per Oura field; ±1-day join sensitivity; local-vs-UTC join sensitivity | §5.2's denominator; the join key's safety (a finding set on this reader's record has flipped entirely on the day boundary before) |
| M2 | Per-day carrier mixture (watch vs Oura-relayed), and its volatility | §4.4's band-source rule; whether "same sensor, two formulas" is heading or footnote; whether carrier stratification (≥ 20 watch days) ever runs |
| M3 | Gated coverage: days surviving wake+stillness+shadow at 120/180/240/300 min windows | Confirms or refutes §0's coverage argument with a count; sets the shadow window with the number in front of us |
| M4 | Baseline degeneracy: fraction of hour-of-day bins where MAD hits the floor, per hour; measured bin-to-bin noise | §4.3's floor value; how often the ribbon draws bandless |
| M5 | Within-channel day-to-day autocorrelation and inter-channel correlation of the four nocturnal channels | §3.2's pooled band — replaces "±0.30 is conservative" with a measured statement |
| M6 | Block-permutation null for the day-level agreement (week blocks), effective n | Whether §5.2 ever ships |
| M7 | Attribution base rates per label class | §6's printed denominators |

---

## 8. Standing rules this design binds itself to

R1. **Pre-register the statistic.** One headline statistic per section, named
    before the data is seen; everything else is exploratory and labelled so.
    At least eight statistics were latent in v1 across overlapping data with
    no family, no alpha, no correction — and BH under measured negative
    dependence has already burned this reader once.
R2. **Deflations, nulls and floors are measured on the reader's own series,
    never asserted.** The asserted-2-vs-derivable-2.84 failure is the type
    specimen.
R3. **Any worked example must be reproducible from the document's own
    formulas**, and must state whether the example day differs from a typical
    one. v1's flagship copy failed both.
R4. **A statistic's effective n counts independent units** — level changes for
    a step series, blocks for autocorrelated days — never calendar rows.
R5. **A rendering may show what a figure may not claim.** The ribbon shows
    elevation the card refuses to count; the step series shows agreement the
    card refuses to score. The refusal is stated beside the picture, which is
    what makes the picture honest.

---

## 9. Future work, explicitly not in this design

- **`exertionHours` v2 inside Energy** — the wake/stillness/shadow/hour-of-day
  gates as improvements to the statistic Energy already owns; the Stress card
  relays it if it lands. Requires its own design note; the incremental-validity
  form and its stated power floor (d ≈ 0.79 at ~25/group vs +0.445 SD
  measured — honest expectation: fails) are the promotion test if a scored
  figure is ever proposed again.
- **The weight registry** (signal audit §5) — seven surfaces read the nightly
  triad; no document defends the set.
- **Daytime temperature** — we have none (both skin-temp fields are
  sleep-derived); Oura's most stress-specific input. Nothing to design until a
  source exists.
- **Gait as a stress channel** — 90/90 coverage, behaviourally independent,
  and **no published curve links gait to stress**; stating that is the
  finding. Stays on `GaitInsight`.

---

## 10. Naming — unchanged from v1 §7, which survived review

Card title **"Stress"** ("Stress load" survives inside as the nocturnal half's
label); balance-web spoke unchanged in name but its detail line carries the
caveat driver (§3.3); `SustainedLoadModel`/`SustainedLoadInsight` may rename to
`StressModel`/`StressInsight` (free — nothing persists a type name);
**`InsightID.sustainedLoad` is never renamed** (persisted raw value: score
history, feedback rows, telemetry outbox, derived-series namespacing — the
case gets a comment saying exactly this); derived-series display names carry
the word "Stress"; and the lesson becomes a check: **a test asserting a
Data-tab search for "stress" returns both the Oura group and this card's own
series.** `Feedback` stays `sustained-load-v2` — a rename does not change what
the number means.

The card is named for the word the reader searches with; the *quantities*
inside are named for what they are (load, arousal, a vendor's opinion). The
caveat driver — this cannot tell stress from illness, alcohol, heat, travel,
altitude, the menstrual cycle or hard training — survives every rename
verbatim; `docs/illness-detection-evidence-2026-08-07.md` shows it is a
measured fact, not a hedge.

---

## 11. Build order, in shippable slices

Each slice passes `./scripts/verify.sh --tests`, ships to `main`
(`ship-to-main`), and leaves the app usable. The measurement pass (§7) is
slice 0 and produces counts, not code.

| # | Slice | Contents | Gate |
| --- | --- | --- | --- |
| 0 | **Measure** | §7 M1–M7 as test-target tools reading `~/HealthSeed/`, never fixtures in the repo. Results land in this doc | Counts asserted, never values |
| 1 | **`VendorOpinion` relay** | The reader type on the `VitalEvent` precedent, fixed allow-list, default overload. No UI | Unit tests on fixtures |
| 2 | **Rename + search test** | §10 in full — the reader's actual complaint, fixed completely, at near-zero cost | `verify.sh` lint; `gen-symbol-index.sh`; the Data-tab search test |
| 3 | **Headline honesty** | §3.2: 95% band on `load` in SD units, rectified-null copy, clip annotation; spoke detail line | Existing tests + new band tests |
| 4 | **The ribbon** | §4 in full, as a bespoke section. `add-chart` first; substance shading via `ScrollableMetricChart`; gaps never zeros; bandless where degenerate | Mac session: `simulator.sh run` + `shot`, **Read the PNG** — two cards have shipped invisible before |
| 5 | **"Same sensor, two formulas"** | §5.1's side-by-side + §5.3's step series. `docs/card-sections.md` updated in the same commit; re-run `card-map.sh` | `handover-check.sh` runs `card-map.sh --check` |
| 6 | **Attribution labels** | §6: calendar blocks, leave periods, medication epochs, base rates printed | Real-data check on the phone (`use-the-phone`) |
| 7 | **The agreement statistic** (gated) | §5.2, only if M1/M6 clear it: observed ρ beside its permutation null and effective n | The null exists and is printed, or the section does not |

**Stop-and-ask:** after slice 0, everything numeric in this design is either
confirmed or corrected in place, and the reader sees the M3 coverage number
before any daytime UI is built.

---

## 12. Open decisions for the reader

| | Question | Default if unanswered |
| --- | --- | --- |
| V1 | **The verdict itself:** the daytime half ships as a rendering — chart, gaps, band — with no daily figure anywhere. The ruling said "both signals on one card"; this honours presence while refusing a number three reviews found underivable and duplicative. Acceptable? | **Yes** — and if overruled, the figure is built inside Energy (§9), not here |
| V2 | Title "Stress", per §10? | Yes |
| V3 | The agreement statistic: gate it behind the measured permutation null (possibly never shipping), or drop the ambition now and keep §5 purely side-by-side? | **Gate it** — the null is cheap to compute and the statistic is the one genuinely novel number available |
| V4 | Substance shading on the ribbon: house rule says every chart carries it; one reviewer argued three shaded columns beside an arousal-shaped line invites a causal read the copy forbids | **Keep the house rule** — it is the reader's own, the shading marks logging not effect, and §6's base-rate print is the mitigation |
| V5 | The spoke: is the detail-line caveat (§3.3) enough, or should the web render uncertainty? | Detail line only — the web treats all nine cards alike |

---

## Sources

Carried from v1 (`docs/stress-design-2026-08-07.md` §Sources) — the
peer-reviewed list is unchanged and not repeated here; the load-bearing
additions for v2 are: de Bloom et al. 2009, *J Occup Health* 51:13–25 and
Kühnel & Sonnentag 2011, *J Organ Behav* 32:125–143 (leave fade-out shape, via
`LeaveRecency`); Bowman et al. 2021 (now used only as the reason deflation
must be *measured*: its ~1 h timescale implies VIF 8.0 at 15-min bins, not
v1's asserted 4); Presby et al. 2023 (the 180-min shadow). The v1 numbers
deliberately *not* used (kcalm.app table, the transposed Siepe R², the
unretrievable Garmin preprint, the vendor-blog alcohol claim) stay not used.

**Code read for this document:** `Insights/SustainedLoadInsight.swift` (as of
`sustained-load-v2`), `Models/LeaveRecency.swift`, `Insights/Energy.swift`
(`exertionHours`, `curve`, `morningCharge`), `Insights/PeriodContrast.swift`,
`Insights/Insight.swift`, `Insights/VitalEvent.swift`,
`Feedback/Feedback.swift:189`, plus `docs/signal-audit-2026-08-08.md` §§3.12,
3.16, 5 and the three adversarial reviews appended to
`docs/stress-design-2026-08-07.md`.
