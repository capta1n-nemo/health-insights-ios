# Four planned modules — architecture of record

_Written 2026-08-02 from the user's brief, alongside an outside (Gemini) analysis
of their full export. **Module 1 is built; modules 3 and 4 have their maths
built and their capture/UI outstanding; module 2 is next.** Each section gives
the data models, the service interface, the algorithm, and the UI shape, in the
order the brief asked for._

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
`HKQuantityTypeIdentifierDietaryEnergyConsumed`, which is sitting **unmodelled**
in the export (107 readings, MyFitnessPal). Without intake the service returns
`nil` and the card says so rather than guessing.

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
4. **Module 1's TDEE half** — needs dietary energy promoted out of the raw pile
   first.
5. **Modules 3 and 4** — the maths first (RFM, somatotype components are pure
   and testable); the LiDAR capture last, since only the device can run it.

## Open decisions for the user

- **Module 1 changes what the dial means.** Body fat drops 80% → 55% and
  velocity takes 45%. A reader losing weight well will see their score *rise*
  even before their body fat does. That is the intent — confirm it is wanted.
- **Weight-loss velocity needs a direction.** The bands above assume loss is the
  goal. For a reader gaining deliberately the same machinery should invert;
  simplest is a single stated goal (lose / maintain / gain) in grounding.
- **Module 2 is medical.** Confirm the posture: describe and project, never
  recommend; inferred titration always confirmed before it counts.
