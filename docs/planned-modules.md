# Planned modules — architecture of record

_Modules 1–4 written 2026-08-02 from the user's brief, alongside an outside
(Gemini) analysis of their full export; **5 and 6 added 2026-08-03 at the
user's request** — metabolism speed, and nutrition capture. **Module 1 is
built; modules 3 and 4 have their maths built and their capture/UI outstanding;
module 2 is next; 5 and 6 are designed only.** Each section gives the data
models, the service interface, the algorithm, and the UI shape, in the order the
brief asked for._

**Read `docs/architecture.md` first for the pipeline these plug into**, and the
`add-metric-type` / `add-insight` skills before touching either registry — a new
`MetricType` feeds eight exhaustive switches and a new `InsightID` feeds five
plus two registrations that fail silently.

---

## What the outside analysis got right, and what it missed

Recorded because acting on a wrong diagnosis is more expensive than acting on
none, and three of its claims were checked against the code before anything
below was designed.

| Claim | Verdict |
|---|---|
| Cumulative metrics double-count across sources | **Right, and worse than stated** — fixed 2026-08-02, see below |
| Body Composition weights are co-linear (lean vs muscle vs weight) | **Right** — module 1 fixes it |
| VO₂max mixes Apple Watch and Oura, adding volatility | **Wrong** — `VitalReader` picks one series and never blends; the comment at `VitalReader.swift:109` says so |
| BP estimator has drifted from cuff ground truth | **Right, and already self-reported** — the card prints "out by 13 mmHg on average"; what is missing is a *suppression* threshold, not detection |
| "No published norm yet" on Body Composition | **Right, and cheap** — Gallagher %BF cut-points are *already in the repo* (`BodyCompositionInsight.healthyBodyFatRange`); `PeerStandingModel.norm(for:age:sex:)` simply has no body-fat case |

**The double-count, in detail, because it is the one that changed numbers.**
`MetricSource.deviceFamily` collapses the paths one device arrives by, so Oura's
direct feed and its Apple Health mirror are deliberately *one* series. For a mean
or a median that is right. For a **sum** it was catastrophic: Oura writes one
daily step total (~4,400) and Apple Health mirrors the same day as ~300 interval
readings adding to the same ~4,400, and `bucketed(by:.day, statistic:.sum)` added
both. Steps and active energy read roughly **double** the truth on the Vitals
list and in every day-or-wider chart. Deduplication could never catch it: the
readings are neither the same minute nor the same value — they are a total and
its own parts.

Fixed by taking **the largest single path's total** per bucket rather than the
sum of every reading (`MetricAggregator`), and per source rather than across
sources in the Vitals row (`AppModel.vitalsSummary`). `CumulativeDoubleCountTests`
pins it. Note the z-scores were mostly *unharmed* — a consistently doubled series
has an equally doubled baseline — which is exactly why this survived: the
departures looked right while the absolute numbers were wrong.

---

## 1. Dynamic weighting — **BUILT 2026-08-02**

Shipped as designed, with the user's own weighting: level **0.45** (their
figure), rate **0.30**, quality **0.25**. `CompositionVelocity` /
`CompositionVelocityModel` in InsightKit (17 tests),
`GroundingKind.weightGoal` + `WeightGoal`, and the co-linear pool collapsed —
muscle mass is now charted at weight 0 with its reason on the row. The card's
own account of it lives in `docs/card-sections.md` ▸ "Velocity". **TDEE is not
built** — it needs dietary energy promoted out of the raw pile first, and stays
scoped below.

The design as written, kept for the parts not yet built:

## 1a. Dynamic weighting: velocity, and the end of the co-linear pool

**The brief:** make actual weight and **weight-loss velocity** high-priority, and
have rapid loss propagate through body fat, lean mass and energy expenditure.

**The problem with today's card.** Body fat carries 80%; weight, lean mass,
muscle mass, bone mass and body water carry 4% each. Those five are not five
facts. A BIA scale measures weight and impedance and *derives* the rest — lean =
weight × (1 − fat%), muscle is a fixed fraction of lean — so the pool counts two
measurements five times and calls it breadth. It is also entirely *static*: a
reader 12 kg down over three months scores the same as one who has never moved.

### Models

```swift
/// Rate of change of the body's mass and its composition, over a fitted window.
public struct CompositionVelocity: Sendable, Equatable {
    public let windowDays: Int
    /// Fitted slope, kg/week, smoothed (see `smoothing`).
    public let weightPerWeek: Double
    /// As a share of body weight — the number the safe-rate band is defined on.
    public let percentPerWeek: Double
    /// Fitted slope of lean mass, kg/week. `nil` without a scale reporting it.
    public let leanPerWeek: Double?
    /// Of the mass lost, the fraction that was lean tissue. `nil` when weight
    /// is stable or rising — the ratio is meaningless without a denominator.
    public let leanShareOfLoss: Double?
    /// Typical distance of a real weigh-in from the fitted line, in kg. Quoted
    /// with every slope, as `VO2Trajectory` and `ScoreTrend` already do.
    public let residualSD: Double
    public let weighIns: Int
}

/// The published bands the velocity is judged against.
public enum LossRateBand: String, Sendable { case gaining, maintaining, steady, rapid, veryRapid }
```

### Service

```swift
public enum CompositionVelocityModel {
    /// EWMA α — daily scale readings carry 1–2 kg of water noise, and an
    /// unsmoothed slope through them reports a trend that is mostly hydration.
    public static let smoothing = 0.10
    public static let minimumWeighIns = 6
    public static let defaultWindowDays = 56

    public static func evaluate(samples: [HealthMetricSample],
                                windowDays: Int = defaultWindowDays,
                                now: Date = Date()) -> CompositionVelocity?

    /// 0.5–1.0 %/week is the conventional safe band; above it lean loss rises
    /// steeply. Returns the band and the sentence the card says.
    public static func band(percentPerWeek: Double) -> LossRateBand
}
```

**Algorithm.** EWMA-smooth the weight series (α = 0.10, per the outside
analysis's recommendation and for the reason above), then least-squares fit over
the window; same for lean mass. `leanShareOfLoss = ΔleanFitted / ΔweightFitted`,
defined only where weight fell by more than `residualSD`.

### How the score changes

| Term | Weight | Basis |
|---|---|---|
| Body fat vs the age/sex healthy range | 0.55 | Gallagher et al. (2000) — unchanged, still the primary |
| **Loss quality** — lean share of loss | 0.25 | published: >25% of loss being lean is the sarcopenia threshold |
| **Loss rate** — %/week vs the safe band | 0.20 | 0.5–1.0 %/week |
| Supporting: **one** lean-tissue term, bone, water | 0.20 shared, as today | `SupportingSignal`, against the reader's own baseline |

Two consequences worth stating plainly:

- **The co-linearity dies.** Lean mass and muscle mass collapse into one lean
  term. Weight stops being a supporting *level* signal — its information is now
  carried by velocity, where it belongs, and where the brief asked for it.
- **The card becomes dynamic.** A reader losing 0.8 %/week with lean holding
  scores *well* even at a high body fat, which is the honest reading and the one
  today's card cannot express. `ScoreWeighting.weightedAverage` still applies and
  every row still states its basis.

**Falls out for free:** the "no published norm yet" gap. `PeerStandingModel`
gains a `.bodyFatPercentage` case from the Gallagher table already in the repo,
plus NHANES DXA percentiles if they are added later.

### TDEE

A separate service, because it is a different question and has a different
failure mode:

```swift
public struct EnergyBalance: Sendable, Equatable {
    public let tdeeEstimate: Double        // kcal/day
    public let intakeMean: Double?         // kcal/day, nil without logging
    public let deficitPerDay: Double?
    public let confidence: InsightConfidence
    public let daysCovered: Int
}

public enum EnergyBalanceModel {
    /// 7,700 kcal per kg of body mass — the conventional figure.
    public static let kcalPerKilogram = 7_700.0
    public static func evaluate(samples: [HealthMetricSample],
                                velocity: CompositionVelocity,
                                now: Date = Date()) -> EnergyBalance?
}
```

**Back-calculated, not summed.** `TDEE = meanIntake + (kgLostPerDay ×
kcalPerKilogram)` — the MacroFactor approach. Summing basal + active energy
inherits every wearable's calibration error; the back-calculation only needs
intake and the scale, and it self-corrects. It requires
`HKQuantityTypeIdentifierDietaryEnergyConsumed`, which **was** sitting
unmodelled in the export (107 readings, MyFitnessPal) and is
`MetricType.dietaryEnergy` as of 2026-08-03 — read from Apple Health and parsed
from Shotsy's joules. **This service is unblocked.** Without intake it still
returns `nil` and the card says so rather than guessing. What the reader asked
for on top of the rate — a *speed*, and the medication question — is module 5.

---

## 2. Medication & pharmacokinetics (GLP-1) — **BUILT 2026-08-02**

`GLPCompound`, `PharmacokineticsModel` (Bateman, with the ka=ke limit handled
so it cannot emit a NaN), `TitrationEngine` and `MedicationScanPayload` are in
InsightKit with 18 tests. `MedicationRecord` / `DoseLogRecord` persist it,
`MedicationCurveChart` draws it — **dashed wherever the line rests on a dose
the app inferred** — and `MedicationSection` carries the confirm-or-remove step.

**Updated 2026-08-02, later the same day — the module grew past this
description.** `MedicationResponse` (16 tests) attributes the weight record to
the dose history: per dose-step and per injection-site tables, four overall
figures, a side-effect tally, and a standardised "is it working" overlay.
It moved out of Body Composition's shared bespoke slot into a **second**
top-level bespoke section, **Weight management**. `MetricType.activeMedicationLevel`
**is registered** — it was held back until the curve had been trusted on real
doses, and the user asked for it on the contributors chart; it carries
`MetricSource.calculated`, its own `MetricFamily.pharmacology`, weight 0 and no
reference range (see `docs/architecture.md` ▸ Rule 3). "On board" is gone from
every surface, replaced by "in your system".

**Still not built:** the Vision OCR scanner behind `MedicationScanner` — the
seam and its text-parsing half are, and are tested.

Two bugs the tests caught, worth keeping: the titration walk emitted a dose on
both sides of every step boundary, which sorted into a ladder that appeared to
go *backwards*; and "the inferred dose has decayed away" was asserted at three
weeks, when a five-day half-life still leaves it carrying ~28% of the level.

The design as written:

## 2a. Medication & pharmacokinetics (GLP-1)

**The brief:** track drug, dose, schedule and half-life decay; graph active
compound; expose it as a predictor; infer a titration history; leave room for an
OCR scanner.

**Safety posture, and it constrains the design.** This models a prescription
drug. The module may **describe** what the user tells it and **never** recommend,
advance, or adjust a dose. Inferred history is inferred *visibly* — the app
already has one rule for this and it applies here: **dashed means not measured**
(see the `add-chart` skill). An inferred titration step is drawn dashed and
carries an "estimated — confirm" affordance until the user confirms it.

### Models (SwiftData)

```swift
@Model final class Medication {
    var id: UUID
    var compoundRaw: String          // GLPCompound.rawValue
    var brandName: String?           // "Mounjaro" — display only
    var startedOn: Date
    var scheduleRaw: String          // DosingSchedule.rawValue
    var isActive: Bool
    @Relationship(deleteRule: .cascade) var doses: [DoseLog]
}

@Model final class DoseLog {
    var id: UUID
    var takenAt: Date
    var milligrams: Double
    var injectionSite: String?
    /// True when this row was *extrapolated* by the titration engine rather
    /// than entered or confirmed. Drives the dashed rendering and the
    /// confirm prompt; never silently promoted.
    var isInferred: Bool
    var confirmedAt: Date?
}
```

```swift
public enum GLPCompound: String, Sendable, CaseIterable {
    case tirzepatide, semaglutide, liraglutide

    /// Published elimination half-lives.
    public var halfLifeHours: Double {
        switch self {
        case .tirzepatide: return 5 * 24     // ~5 days
        case .semaglutide: return 7 * 24     // ~1 week
        case .liraglutide: return 13         // ~13 h
        }
    }
    /// Absorption half-life — subcutaneous depot release.
    public var absorptionHalfLifeHours: Double { … }
    /// The manufacturer's standard ladder, in mg.
    public var titrationLadder: [Double] {
        switch self {
        case .tirzepatide: return [2.5, 5, 7.5, 10, 12.5, 15]
        case .semaglutide: return [0.25, 0.5, 1, 1.7, 2.4]
        case .liraglutide: return [0.6, 1.2, 1.8, 2.4, 3.0]
        }
    }
    public var titrationIntervalDays: Int { 28 }
}
```

### Service

```swift
public struct ActiveCompoundPoint: Sendable, Identifiable {
    public let date: Date
    /// mg-equivalent on board.
    public let level: Double
    /// True where the level derives from an inferred dose — the chart draws
    /// these dashed, as everything inferred in this app is.
    public let restsOnInferredDose: Bool
    public var id: Date { date }
}

public enum PharmacokineticsModel {
    /// One-compartment, first-order absorption and elimination — the Bateman
    /// function. For each dose D at tᵢ, with ka and ke from the compound:
    ///
    ///     C(t) = D · ka/(ka − ke) · (e^(−ke·Δt) − e^(−ka·Δt)),  Δt = t − tᵢ ≥ 0
    ///
    /// and levels superpose, which is what produces the accumulation to steady
    /// state a weekly injectable reaches over four to five half-lives. Doses
    /// are additive because the model is linear; that linearity is also why
    /// this is safe to precompute and store.
    public static func curve(doses: [DoseLog], compound: GLPCompound,
                             from: Date, to: Date,
                             step: TimeInterval = 6 * 3600) -> [ActiveCompoundPoint]

    /// Level at one instant — the value the score and the correlation engine read.
    public static func level(at date: Date, doses: [DoseLog],
                             compound: GLPCompound) -> Double

    /// Steady-state trough and peak for a schedule, for the "where this is
    /// heading" read-out.
    public static func steadyState(dose: Double, everyDays: Int,
                                   compound: GLPCompound) -> (trough: Double, peak: Double)
}

public enum TitrationEngine {
    /// Walk the ladder backwards from a current dose, one step per
    /// `titrationIntervalDays`, producing **inferred** dose logs for review.
    /// Never written without the user confirming — see `DoseLog.isInferred`.
    public static func inferHistory(currentDose: Double, compound: GLPCompound,
                                    startedOn: Date, now: Date = Date()) -> [DoseLog]
}
```

### The OCR seam

Architected now, implemented later, so the input layer never has to change:

```swift
public struct MedicationScanPayload: Sendable {
    public let recognisedText: [String]
    public let compound: GLPCompound?
    public let milligrams: Double?
    public let confidence: Double
}

public protocol MedicationScanner: Sendable {
    func scan(_ image: CGImage) async throws -> MedicationScanPayload
}
```

`VisionMedicationScanner` conforms later; the onboarding flow depends only on the
protocol, so it is testable today with a stub.

### Where it reaches the rest of the app

- **A new `MetricType.activeMedicationLevel`** (mg-equivalent). This is the piece
  that makes it a *predictor* rather than a diary: as a canonical metric it can
  be charted, correlated by `PatternFinder`, lagged by `LagFinder` — "your weight
  falls hardest in the three days after a dose" is exactly the shape those
  already find. Costs the eight switches in `add-metric-type`; budget for it.
- **`CompositionVelocity`** gains medication level as a covariate, which is the
  brief's "expose active compound levels as a data input for weight-loss
  prediction".
- **No new `InsightID` initially.** The medication picture belongs in Body
  Composition's bespoke slot beside the velocity, not as a tenth card. Revisit
  once it earns a card of its own.

---

## 3. LiDAR / camera dimensions and the BMI override — **MATHS BUILT 2026-08-02**

`BodyDimensions` and `BuildAssessmentModel` are in InsightKit with 6 tests:
Woolcott & Bergman RFM, the waist-to-height 0.5 action line, and the
non-standard-build flag. `BodyCompositionInsight.score` now has **three
routes** — measured fat, then dimensions, then BMI — so a waist measurement
displaces BMI wherever one exists. **The capture is not built**: ARKit cannot
be exercised from a sandbox, so the LiDAR/camera layer and its UI remain the
device-only half.

The design as written:

## 3a. LiDAR / camera dimensions and the BMI override

**The brief:** accept 3D-derived circumferences; when BMI says obese but the
structure says otherwise, flag it and adjust.

**Status.** The capture half is ARKit and **cannot be exercised from the
sandbox** — it was deferred once already for that reason (`card-sections.md`
▸ "Still open" 10). The split below is deliberate: every judgement lives in
InsightKit where it is testable today, and only the capture is device-only.

### Models

```swift
public struct BodyDimensions: Sendable, Equatable, Codable {
    public let capturedAt: Date
    public let heightMetres: Double
    public let waistCentimetres: Double
    public let hipCentimetres: Double?
    public let chestCentimetres: Double?
    public let neckCentimetres: Double?
    public let source: DimensionSource   // .lidar, .camera, .tape

    public var waistToHeight: Double { waistCentimetres / (heightMetres * 100) }
    public var waistToHip: Double? { hipCentimetres.map { waistCentimetres / $0 } }
}
```

### Service

```swift
public struct BuildAssessment: Sendable, Equatable {
    public let bmi: Double
    public let bmiCategory: String
    /// Relative Fat Mass — Woolcott & Bergman (2018), validated against DXA
    /// and materially better than BMI for exactly the case in the brief.
    ///     men:   64 − 20 × (height / waist)
    ///     women: 76 − 20 × (height / waist)
    public let relativeFatMass: Double
    /// Set when BMI says obese and central adiposity does not agree.
    public let isNonStandardBuild: Bool
    public let explanation: String
}

public enum BuildAssessmentModel {
    /// 0.5 is the published waist-to-height action line, and it is the whole
    /// of the override: a WHtR under it means the mass is not central, whatever
    /// BMI says.
    public static let waistToHeightActionLine = 0.5

    public static func evaluate(dimensions: BodyDimensions, weightKg: Double,
                                sex: BiologicalSex) -> BuildAssessment
}
```

**The override rule, stated so it cannot drift:** BMI ≥ 30 **and** WHtR < 0.5 ⇒
`isNonStandardBuild`, and the Body Composition dial prefers **RFM** over the BMI
fallback route. It never overrides a *measured* body fat — the route order stays
measured fat → RFM (when dimensions exist) → BMI. That ordering is the same
"prefer the better instrument" argument `BodyCompositionInsight.score` already
documents for fat over BMI.

---

## 4. Somatotype — **ENGINE BUILT 2026-08-02**

`Somatotype` and `SomatotypeModel` are in InsightKit with 8 tests: three
continuous Heath–Carter components from body fat (against the same Gallagher
band the dial uses), fat-free mass index, the ponderal index, and a
shoulder-to-waist lift where a tape or a scan provides it. `isBalanced` exists
because most people are mixtures and the card must be able to say so.

**Updated 2026-08-02: the card and the override are both built.**
`SomatotypeCard` renders the three components inside Body Composition's first
bespoke section, and the override is a first-class input —
`InputKind.bodyType`, `ContributionRoute.bodyType`, `BodyTypeSheet`, reachable
from the card's "View & add", the Today `+` menu and Settings. It is
`.offeredOnly`: nothing scores off it, so nobody is nagged for it.

The design as written:

## 4a. Somatotype

**The brief:** estimate ecto/meso/endomorph from frame, waist-to-shoulder and
composition; a card that explains it and lets the user override.

**The honesty constraint.** Heath–Carter, the published method, needs skinfolds
and bone breadths this app will not have. So the module must not present a
crisp label it cannot support. It reports **three continuous components** (the
Heath–Carter shape, 1–7 each) plus the dominant one, and says what it was
estimated from.

```swift
public struct Somatotype: Sendable, Equatable {
    public let endomorphy: Double     // 1–7, fatness
    public let mesomorphy: Double     // 1–7, musculoskeletal robustness
    public let ectomorphy: Double     // 1–7, linearity
    public let dominant: Component
    /// What it was derived from, so the card can say. Never "measured".
    public let basis: Basis           // .estimatedFromComposition, .userDeclared
    public let confidence: InsightConfidence
}

public enum SomatotypeModel {
    /// Endomorphy from body-fat percentile against the age/sex range;
    /// mesomorphy from the lean mass index (LBM / height²) against published
    /// norms; ectomorphy from the ponderal index (height / ∛weight).
    /// Every input is one the app already holds.
    public static func estimate(bodyFatPercentage: Double?, leanMassKg: Double?,
                                weightKg: Double, heightM: Double,
                                dimensions: BodyDimensions?,
                                age: Double, sex: BiologicalSex) -> Somatotype?
}
```

The user's override is stored as a `GroundingFact`-shaped preference, wins over
the estimate wherever it exists, and — the part that matters — **the card keeps
showing the estimate beside it**, because a disagreement between what someone
believes and what their numbers say is information rather than an error.

### UI

```swift
struct SomatotypeCard: View {          // Body Composition's bespoke slot, nested
    let somatotype: Somatotype
    @Binding var override: Somatotype.Component?
    // Triangle plot of the three components, the dominant one named,
    // one sentence on what it means, and a picker that sets `override`.
}
```

---

## Build order, and what each costs

1. **Module 1 without TDEE** — highest value, no new frameworks, kills a
   confirmed co-linearity defect and answers the brief's velocity requirement.
   All maths is InsightKit and testable today.
2. **`PeerStandingModel` gains body fat** — an afternoon; the table is already
   in the repo, and it closes "none of this card's signals has a published norm".
3. **Module 2's maths** (`PharmacokineticsModel`, `TitrationEngine`) — pure
   functions, fully testable in the sandbox. The SwiftData models and onboarding
   flow follow; `MetricType.activeMedicationLevel` last, when the curve is
   trusted, because it is the expensive registration.
4. **Module 1's TDEE half** — **unblocked 2026-08-03**, when dietary energy
   became a `MetricType`. Pure InsightKit maths, testable today.
5. **Modules 3 and 4** — the maths first (RFM, somatotype components are pure
   and testable); the LiDAR capture last, since only the device can run it.
6. **Module 5 (metabolism speed)** follows straight on from 4 — it is the same
   back-calculation plus a prediction to divide it by, and every input already
   exists. All InsightKit, all testable in the sandbox; only the card's layout
   needs the phone.
7. **Module 6 (nutrition)** — the capture is a promotion job and can go any
   time; the card wants the one decision below settled first.

## Open decisions for the user

- **Module 1 changes what the dial means.** Body fat drops 80% → 55% and
  velocity takes 45%. A reader losing weight well will see their score *rise*
  even before their body fat does. That is the intent — confirm it is wanted.
- **Weight-loss velocity needs a direction.** The bands above assume loss is the
  goal. For a reader gaining deliberately the same machinery should invert;
  simplest is a single stated goal (lose / maintain / gain) in grounding.
- **Module 2 is medical.** Confirm the posture: describe and project, never
  recommend; inferred titration always confirmed before it counts.
- **Does any nutrition row carry a published reference band?** See module 6.
  Calorie targets stay refused; a protein floor for preserving lean mass during
  rapid weight loss is the arguable case, and it is the user's call.
- **Module 5 will sometimes report a metabolism "faster" than predicted, and
  the honest first explanation is an incomplete food log.** Confirm that the
  card should say so plainly rather than let the flattering reading stand.

---

## The body scanner's visual target (2026-08-03, from the user's references)

The user supplied four reference apps and a screenshot of **our** current
"Your body over time". Read the last one first, because it is the gap:

**What we ship today is a pink polygon.** `BodySilhouetteView.outline` draws a
convex-ish blob with shoulder, waist and hip vertices. On the device it reads as
a *shield* or a kite — not a body, not the user's body, and not obviously
anything. The caption under it is honest ("A representation built from your
measurements, not a picture of you"), and the machinery beneath it is real: the
morph is driven by measured girths, the projection is right, the 12-week
timeline scrubber works, and the somatotype block below is genuinely good. The
**renderer** is the only weak link, and it was always meant to be replaceable —
`outline` is static and pure precisely so this swap costs nothing upstream.

### What each reference contributes

| Reference | The idea worth taking | Do we have the data? |
| --- | --- | --- |
| **Hume Body Pod** — segmental muscle mass, callout cards pinned to a body render, per-segment "High / Standard / Low" | **Callouts pinned to body regions** beat a table. Each is tappable (`→`) into that segment's history. | ⚠️ **No.** Segmental lean mass needs 8-electrode BIA. We must not draw per-limb muscle we cannot measure. |
| **Visbody / Styku** — cyan wireframe mesh, girth labels with leader lines to the exact site, Default / Side-by-side / ColorMetric tabs | **The mesh + leader-line labels.** This is the closest to what we already have data for. | ✅ **Yes** — seven girths land as `MetricType`s today, the rest are in the `BodyScan` payload. |
| **Comparison heatmap** — two scan dates, ±5 mm colour ramp over the body surface | **Change as a surface, not a number.** Directly answers "where did it go?" | ⚠️ Needs a mesh and two comparable scans. `ScanComparability` + the ±10 mm repeatability band already gate this correctly. |
| **Guided capture + measurements list** — silhouette overlay, 45° arm guide, foot marks, then a plain measurements table | Confirms the capture design already in this doc: drawn guides, live validators. | Design done, build not started. |

### ✅ Decided 2026-08-03 — the wireframe mesh, spinnable, with the slider kept

The user picked the **Visbody-style default-mesh screen** over the other three,
and added two requirements:

- **"manipulate and spin the model"** — a drag gesture orbits it. Not a
  gimmick: a girth is a *ring* around the body, and a front-on projection shows
  one diameter of it. Rotating is how a reader sees that waist 125 cm is a
  circumference and not a width. Pinch to zoom, double-tap to reset to front.
- **"again have the slider to see how it changes over time + preview"** — the
  12-week scrubber we already ship stays, unchanged in behaviour, driving the
  mesh instead of the polygon. It is the one thing our card has that none of the
  four references do, and the projected half must keep saying it is a
  projection.

Everything else on the card — the caption, the somatotype block, "Set it
yourself" — stays where it is. This replaces a renderer, not a screen.

**The split that makes it testable on Linux**, which is how everything in this
repo gets built: the mesh *generation* is pure geometry and belongs in
InsightKit — girths → ring vertices → lofted surface between rings → a
`BodyMesh` value type of vertices and indices, with tests on ring
circumference, monotonic interpolation and vertex count. Only the *rendering*
(SceneKit/RealityKit, the orbit gesture, the leader lines) is app-target code
that CI is the only gate for. Do not let the geometry live in the view.

**Leader lines are the hard part of the layout, not the mesh.** Each label
anchors to a projected 3D point and must not collide with its neighbours as the
model spins — so the anchor is a vertex on the girth ring, the label parks in a
left/right gutter, and labels re-sort by projected Y each frame. Hide a label
when its anchor rotates behind the body rather than letting the line cross the
mesh.

⚠️ **Colour must not be decorative here.** The reference tints some figures
amber and some cyan; ours has a meaning available and should use it —
**measured girths one hue, estimated girths another, and say so in the legend**.
That is the per-label version of the honesty the blanket caption does now, and
it is the `add-chart` dash-means-inferred rule applied to text. Do not copy the
reference's palette without giving it a meaning.

### The rest of the build order

1. **Replace the polygon with a mesh.** The single highest-value change on the
   card, and it needs no new capture — the same `BodyModelParameters` that drive
   the outline can drive a parametric mesh. SceneKit/RealityKit, a base human
   mesh, girth-driven scaling per body region. Everything above `outline` stays.
2. **Leader-line girth labels** in the Visbody style, reading the seven
   `MetricType` girths. **A label for a girth we estimated rather than measured
   must say so** — the dash-means-inferred rule from `add-chart`, applied to
   text. This is where the current caption's honesty becomes per-label instead
   of one blanket paragraph.
3. **Side-by-side and heatmap tabs**, gated on `ScanComparability` — two scans
   that are not comparable must refuse to draw a difference surface rather than
   colour in noise. The ±10 mm band means most honest heatmaps will be mostly
   grey, and that is correct.
4. **Segmental cards, only if a source appears.** Hume's per-limb muscle is the
   most attractive screen of the four and the one we have no right to draw. If
   an 8-electrode scale is ever connected it becomes reachable; until then it
   would be the exact "modelled dressed as measured" failure `MetricSource
   .calculated` exists to prevent.

### The paper the user supplied

**"Using mobile applications for body composition analysis: A technical review
of an artificial intelligence-based tool"**, *Clinical Nutrition ESPEN* (2026),
PII S2405-4577(26)00201-9 — a technical review of **MeThreeSixty®**, a
smartphone-photo body composition app.

⚠️ **Paywalled — the full text returned 403 from both ScienceDirect and the
journal, so no accuracy figure from it is quoted here and none should be
invented.** What is established from the abstract and title is the *argument*,
and the argument is the useful part:

> Smartphone-photo body composition is accessible and usable by non-experts,
> **but clinicians, researchers and users need clarity on the technical
> development and estimation process** — how the number was produced, not just
> what it is.

That is a methods-transparency claim, and it lands squarely on choices this app
has already made: `MetricSource.calculated`, its own metric family, weight 0 and
no reference range for anything modelled; "a representation built from your
measurements, not a picture of you"; `BodyScan` storing `(site, side, value)`
so a scan can be re-parsed when the method improves; and `ScanComparability`
recording the conditions rather than silently plotting incomparable scans.

**What to do with it when someone has access:** read it for the *pipeline*, which
is the part we are about to copy — two photos (front + side), silhouette
extraction, a statistical shape model fitted to the silhouettes, girths measured
off the fitted mesh rather than off the photo. Our LiDAR path is a better input
to the same back half. Extract per-site error against the reference standard and
put it here; that number is what a girth label should be allowed to claim, and
until it is known the labels should stay conservative.

**Do not** treat the review as validation of our own estimates. It reviews one
commercial tool's method; it says nothing about a girth this app inferred from
height, weight and body fat.

---

## 5. Metabolism speed — the card (user request, 2026-08-03)

The user's ask, in their words: *"I'm always wanting to know how fast my
metabolism is at the moment, and how it's sped up by Mounjaro or similar
medications, and how it's helping me lose weight — or making it harder."*

**The service for this is already designed above** — `EnergyBalanceModel`, the
back-calculated TDEE in Module 1 — and **its blocker was removed on
2026-08-03**: dietary energy is `MetricType.dietaryEnergy` now, parsed from
Shotsy's joules and read from Apple Health. What is missing is the rest: a
*speed* rather than a rate, the medication question, and a card to put them on.

### The number the user is actually asking for

TDEE in kcal/day answers "how much do I burn", not "is my metabolism fast".
Fast is a **comparison**, so the card's headline figure is a ratio:

```
speed = observedTDEE / predictedTDEE
```

- **Observed** is the back-calculation already specified:
  `meanIntake + kgLostPerDay × kcalPerKilogram`. It is the only route to a
  measured-ish figure — summing basal + active inherits every wearable's
  calibration error, and Apple's own basal energy is a *formula*, not a
  measurement (see the trap below).
- **Predicted** is `BMR + meanActiveEnergy + TEF`, where:
  - `BMR` is **Katch-McArdle when lean body mass is known** (`370 + 21.6 × LBM`),
    Mifflin-St Jeor otherwise. This app has lean mass from Withings and Shotsy,
    which is exactly the case where Katch-McArdle is the better instrument;
  - `meanActiveEnergy` is measured (`activeEnergyBurned`), not a lifestyle PAL
    multiplier somebody picked off a dropdown;
  - `TEF` ≈ 10% of intake, the conventional figure.

So 100% is "exactly what your size and your movement predict", below is
suppression, above is — usually — **not a fast metabolism**, see next.

### The failure mode that has to be on the card, not in a footnote

The back-calculation attributes **every** logging error to metabolism. A reader
who under-reports by 400 kcal/day gets a number that says their metabolism is
20% faster than predicted, and it is the most flattering possible reading of an
incomplete food diary. Under-reporting is not a fringe case: it is the normal
finding in the literature, routinely 20–30%.

Therefore:

1. **Logging completeness is a gate, not a caveat.** Days with intake ÷ days in
   the window, and below ~80% the card says "can't judge" rather than printing a
   number — the same shape as `ActivityDoseModel`'s three-recorded-day floor.
2. **A speed above ~110% names under-logging first**, in the driver line, before
   any metabolic reading. That is the honest ordering of explanations.
3. **Two weeks minimum, four preferred**, on a *smoothed* weight trend. Water
   weight swamps a fortnight of real change and endpoints are the worst possible
   estimator of it; the velocity machinery from Module 1 already smooths.

### The Mounjaro question, answered honestly

Two quantities can produce weight loss and the reader wants to know which one
the drug moved. The card splits it:

- **Intake**, measured from `dietaryEnergy`.
- **Expenditure**, from the observed TDEE above.

Both are already dated series, `activeMedicationLevel` is a third, and the
before/after window machinery plus the exponential load kernel exist in
Substance Impact — this is that shape with a different pair of quantities.

**What the evidence supports, and what the card must therefore not say.**
GLP-1 receptor agonists act principally by reducing intake. Resting expenditure
generally *falls* during weight loss, because a smaller body costs less to run;
the live research question is whether it falls more than body size alone
predicts. So:

- The expected honest finding is **"the drug moved what you eat, not what you
  burn"**, with both numbers stated.
- **Never "Mounjaro speeds up your metabolism."** No such effect is
  established, and if this card's ratio rises during treatment the more likely
  explanation is that logging got worse as appetite fell — which the card should
  say in the same breath.
- The claim that *is* worth making, and is this card's real contribution:
  **observed TDEE against predicted-for-your-current-size**, tracked across the
  medication period. That is adaptive thermogenesis, it is what "my metabolism
  has slowed" actually means, and nothing else in the app can see it.

### The trap: Apple's basal energy is not a measurement

`HKQuantityTypeIdentifierBasalEnergyBurned` sits in the raw pile and is
tempting. **Do not promote it as "your metabolism."** Apple derives it from
height, weight, age and sex — it is a formula the phone evaluated, so charting
it as a measured metabolic rate is precisely the modelled-dressed-as-measured
failure `MetricSource.calculated` exists to prevent. It is legitimate only as a
labelled comparator beside the prediction, and even then it adds little the
Katch-McArdle line does not.

### A refinement worth having, but not first

`kcalPerKilogram = 7,700` is a whole-body average. Fat tissue is ~9,400 kcal/kg
and lean ~1,800, and on a GLP-1 the lean fraction of loss is not negligible.
Where body fat percentage is trending, split the loss and weight the two — it
moves the observed figure by a few per cent, which matters only once the logging
gate above is being met.

### Shape

- Its own `InsightID` (`.metabolism`), trend cadence — see the `add-insight`
  skill for the five switches and two silent registrations.
- Contributors: `dietaryEnergy`, `bodyMass`, `activeEnergyBurned`,
  `leanBodyMass`, `activeMedicationLevel`.
- Requirements: date of birth, sex, height — all existing grounding facts, all
  needed by the prediction rather than by the observation, so a reader without
  them still gets a TDEE and loses only the ratio.
- Sections, in the order the questions arrive: the speed ratio with its
  confidence; observed against predicted; where the deficit comes from (ate
  less / moved more); what that predicts for the week's weight; and the
  medication panel when a regimen exists.

---

## 6. Nutrition capture and its card (user request, 2026-08-03)

The user's ask: *"a nutrition card in future, to capture all nutrition possible
from all sources."*

**Capture first, card second** — and the capture is mostly a promotion job
rather than new plumbing.

### What is already arriving and going nowhere

- **Apple Health** writes ~25 dietary identifiers into this app's raw "other
  data" bucket today: carbohydrates, fibre, sugar, total/saturated/mono/poly
  fat, cholesterol, protein, sodium, potassium, calcium, iron, water, caffeine
  and the rest. Nothing reads any of them.
- **Shotsy** carries protein, fat, carbs and fibre, with the kg → g conversions
  already worked out in `ShotsyUnit.pendingNutritionKinds`.
- **The camera route** (meal photo → on-device extraction) is already on the
  roadmap under camera-based input, and is the only one of the three that needs
  a model rather than a mapping.

### The promotion, and where to stop

First-class `MetricType`s for the four that have a reader in sight — **protein,
carbohydrates, total fat, fibre** — in grams, plus water and caffeine, which
earn their place for different reasons (hydration; caffeine already meets the
substance log and sleep onset). Everything else stays in the raw layer, visible
in the Data tab and unscored: per "a metric with no reader is invisible", four
more series nobody consults would be four charts nobody asked for.

The Nutrition data-tab group and the `.nutrition` metric family exist as of
2026-08-03 — they arrived with dietary energy, so the macros inherit both.

### What the card can honestly say

- **Composition** — the protein/carb/fat split, and how it moves.
- **Consistency** — how much intake varies day to day, which is a description
  rather than a judgement.
- **Completeness** — how many days were logged. This is the same figure the
  metabolism card gates on, and the two must read it from one place: a card
  saying "well logged" beside a card saying "can't judge" is one number
  disagreeing with itself.
- **Relationships from the reader's own history**, the app's existing strongest
  claim: protein against lean-mass retention while weight falls; caffeine
  against sleep onset; fibre and water against whatever they track with.

### The decision this needs from the user

**Does any nutrition row get a published reference band?** The app refuses
calorie targets deliberately, and that stays. Protein is the arguable case:
there is real evidence for a protein floor to preserve lean mass during rapid
weight loss, which is exactly the reader's situation on a GLP-1, and the app
already carries one published dose (WHO's 150–300 exercise minutes) with its
provenance stated. A protein floor is closer to that than to a calorie target —
but it is still dietary guidance, and **it is the user's call, not a session's.**

Everything else on the card is descriptive and needs no such decision.

### Order

Nutrition capture is **not** a blocker for the metabolism card — calories are
modelled already and calories are what the back-calculation needs. It is a
blocker for the metabolism card's *confidence* being any good, because a reader
who logs food properly is the reader whose energy balance can be trusted. Build
the promotion first, the card second, and let the metabolism card land whenever
it is ready.
