# What's in the data that nothing reads yet

_From the first data export (2026-08-01): 559,251 readings, 31 modelled signals,
232 imported-but-unmodelled. Ranked with the published basis for each, so a
future session can pick up an item without re-deriving whether it can be scored
honestly._

**Read `docs/card-sections.md` first** for what the nine cards currently render.

## The constraint that shapes every item here

This repo refuses to invent scoring curves. A signal with no published 0–100
mapping is **weight 0** — charted, narrated, in `contributors` for anything
later to learn from, but never folded into a score. `FitnessInsight.contributors`
is the worked example. The second mechanism worth knowing is
`VitalSignsCheck.specs`, where `skinTemperature` runs with `hardLow`/`hardHigh`
both `nil` and is judged on personal z-score alone — **that is how a signal with
no published bands can still raise an honest flag.**

## Ranked

| # | Signal | Card | Scored? | Published basis |
|---|---|---|---|---|
| 1 | ~~Apple Exercise Time (7,352)~~ **built 2026-08-01** | Fitness | **scored** | WHO 2020: 150–300 min/week moderate, with a stated dose–response. Apple's "exercise minute" *is* the moderate-intensity definition. Now `MetricType.exerciseMinutes` + `ActivityDoseModel` (weekly, missing-days-as-zero behind a 3-recorded-day floor), 0.20 of Fitness's primary pool per the rebalance below. |
| 2 | Audio exposure, environmental + headphone (19,091) | **none exists** | yes | WHO-ITU H.870, NIOSH 85 dBA/8 h. The strongest basis in the set — a dose *is* a 0–100 by construction. |
| 3 | Breathing disturbance index (Oura) | Sleep | no | None. Oura publishes no validated BDI→AHI conversion; AASM's bands are defined on polysomnography, not a ring. |
| 4 | ~~Sleep latency (median 10.5 min)~~ **built 2026-08-01** | Sleep | **scored** | Ohayon 2017 (NSF consensus): ≤15 min appropriate, 16–30 uncertain, >30 inappropriate. Now `MetricType.sleepLatencyMinutes`, emitted by the **typed, nap-aware** Oura parser only — the generic pipeline can't tell a nap's latency from a night's, the same hazard as the bedtime. Weight 0.05, funded duration 0.30→0.27 and consistency 0.10→0.08 per the caution below. |
| 5 | WASO (derivable: time-in-bed − sleep − latency) | Sleep | **yes** | Ohayon 2017 again: ≤20 min appropriate, >50 inappropriate. |
| 6 | Basal energy (45,602) | Body Composition | no — but a *prediction* exists | Mifflin-St Jeor (1990) predicts BMR from weight, height, age, sex — all four already grounding facts. Report measured-vs-predicted. |
| 7 | Walking speed (27,207) | Fitness | no — hard bound only | Bohannon & Williams Andrews 2011 gives gait-speed norms; 1.0 m/s is a standard clinical cut-point. Justifies a bound, not a curve. |
| 8 | Oura resilience level + contributors | Readiness | **never** | Second opinion — see below. |
| 9 | Oura stress seconds + day summary | Readiness, Energy | **never** | No published mapping from "3,600 s of high stress" to anything. |

### Notes that matter more than the ranking

- **#1 is first because Fitness scores nothing the user actually *does*.** VO₂max
  level (0.70) and trajectory (0.30) both move over months; exercise minutes move
  today. Suggested rebalance: level 0.55 / trajectory 0.25 / activity dose 0.20.
- **#2 has no home, and that is the finding.** 107 dBASPL is a real result — at
  107 dB the NIOSH allowance is under a minute. But none of the nine cards is
  about hearing, and Readiness's vitals scan is an *illness/departure* detector:
  putting noise dose in it would announce "your ears are unusual today" in the
  same voice as AFib burden. **Argue for a tenth card separately rather than
  smuggling it in.** If it does land in the scan, it needs a hard bound and **no
  personal z-score** — a personal baseline of "loud" is exactly what must not be
  normalised, the argument `ReadinessScore` already makes for its absolute SpO₂
  floor.
- **#3 is the highest-value sleep signal despite having no basis**, because it is
  the only one saying something the card cannot already say. Sleep infers
  disordered breathing from an SpO₂ floor at weight 0.07; BDI measures it
  directly. Pair them — BDI in the user's own top decile *and* SpO₂ under 94 is a
  screening line neither makes alone.
- **#4 and #5 must be funded out of existing weights, never added on top.**
  `SleepInsight`'s coefficients sum to 1 and have drifted apart from the declared
  contributor weights once already.
- **#5 carries a data caution**: confirm the `oura.sleep.*` fields are per-night
  before scoring anything derived from them. This card has already been burned by
  exactly that — see the nap defect in `docs/activeContext.md`.

## The 2026-08-01 critical review — what was taken, what waits, and why

Prompted by the user: *"look for opportunities to add more data sources, use
more info that's currently just in vitals and unused."* Taken this round: #1
(exercise dose) and #4 (sleep latency), both scorable against a published
basis without new information. The rest, with the blocker named so the next
session starts at the decision rather than the survey:

- **#3 BDI** — highest-value sleep signal, but building it needs the exact
  field identifier confirmed from a **fresh export** (and its per-night
  semantics; the sleep endpoint's nap hazard applies). Design already scoped
  above: pair with the SpO₂ floor as a screening line, never a score.
- **#5 WASO** — same per-night confirmation needed before deriving anything.
- **#6 BMR measured-vs-predicted** — buildable *now* (all four Mifflin-St
  Jeor inputs are grounding facts; `basalEnergyBurned` is 45k readings in the
  raw pile). Report-only on Body Composition. The next cheapest build here.
- **#7 walking speed** — a 1.0 m/s clinical cut-point justifies a vitals-scan
  hard bound, not a curve; needs a `MetricType` and a `Spec` row.
- **#2 audio exposure** — strongest basis in the set, no card to live on;
  needs the user to want a tenth card about hearing.
- **Provider scores as second opinions** — the disagreement panel scoped
  below; needs vendor-neutral `MetricType`s first.

## Oura's own scores — second opinion, never an input

`daily_sleep.score`, `daily_readiness.score`, `daily_activity.score`,
`daily_resilience.level`, `daily_stress.day_summary`. The precedent is
`docs/architecture.md` ▸ "Vascular age is a second opinion, not an input":
a provider's estimate becomes its own metric, shown beside ours, never averaged
in. Two models built on different inputs disagreeing is information.

Three rules for doing it:

1. **Name them vendor-neutrally** — `providerSleepScore`, not `ouraSleepScore`.
   Whoop Recovery and Garmin Body Battery are the same shape, and `MetricType`
   is explicit that the engine must never learn which device a number came from.
2. **A provider score must never enter `HealthWatchModel.watched` or
   `VitalSignsCheck.specs`.** Both judge departure from a personal baseline, and
   a provider score is a normalised composite whose baseline moves when the
   vendor changes its algorithm — it would raise "unusual" from a firmware
   update.
3. Folding resilience into Readiness would be *worse* than the vascular-age case
   it mirrors: Oura's resilience is partly built from the same HRV and resting HR
   our score already weights at 0.40 and 0.25, so it would double-count the same
   beat-to-beat stream that `sharesMeasurementBasis` exists to stop the patterns
   card double-counting.

**The extension worth building**: show the *disagreement* as the number.
`ScoreHistory` already replays our score per day, so "ours 71, Oura 84, and the
gap has widened three weeks running" is computable from data both sides already
store. A persistent gap is either a bug in our weights or a real difference in
what the two models value, and the user should see either.

## Housekeeping the export exposed

- ~~**~80 of the 232 "unmodelled signals" are Withings device metadata**~~ —
  **excluded at ingest 2026-08-01.** `WithingsMeasureIngestor` now drops the
  bookkeeping (`algo`, `fm`, `position`, `apppfmid`, `deviceid`,
  `hash_deviceid`, `created`, `modified`, `grpid`, `timezone`) and the numbered
  copies of types the typed parser already promotes — it asks
  `WithingsResponseParser.metricType(for:)`, so promoting a new type retires
  its raw copy automatically. `attrib`, `category` and `comment` are kept:
  facts about the measurement, not the sync. The two promotion rules aimed at
  numbered measures (`measure.12`, `measure.4`) target *unmapped* types, so
  both still fire — checked before shipping, because a rule whose field stops
  surviving ingest fails silently. Old rows leave the store on the next
  Withings sync (the cache merge replaces a returning source's samples
  wholesale); the catalogue keeps them as history.
- **`withings.measure.9/10/11` are diastolic / systolic / heart rate** from the
  BPM — a real, unmodelled blood-pressure source, though only ~31 records.
- **559,251 readings.** The hydration work in session 12 was measured against a
  synthetic 131,400-sample set. Real load is over 4× that, so the decode cost
  (which was already 68% of the remaining time) is worth re-measuring before it
  is assumed to be solved.
