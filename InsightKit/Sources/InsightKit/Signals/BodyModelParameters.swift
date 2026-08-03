import Foundation

/// A height on the body where the model carries a girth.
///
/// A fixed, complete list — **every `BodyModelParameters` carries every
/// station**, measured or estimated. That is what makes morphing between two
/// scans well defined: interpolating two shapes with different station sets
/// would need a correspondence nobody has, and the obvious fallbacks (drop the
/// odd ones out, or hold a missing one still) either lose the shape or invent a
/// stationary point in the middle of a moving body.
public enum BodyStation: String, Sendable, Codable, CaseIterable, Identifiable {
    case neck, shoulder, chest, waist, hip, thigh, calf

    public var id: String { rawValue }

    /// Height above the floor as a fraction of stature.
    ///
    /// Standard anthropometric proportions. They are population means and the
    /// model says so — a scan measures the *girth* at each station, not where
    /// the station sits, so an unusually long-legged reader has their waist
    /// drawn slightly wrong and their waist measurement exactly right. Worth
    /// stating because it bounds what the picture claims.
    public var heightFraction: Double {
        switch self {
        case .neck: return 0.87
        case .shoulder: return 0.82
        case .chest: return 0.72
        case .waist: return 0.62
        case .hip: return 0.52
        case .thigh: return 0.42
        case .calf: return 0.24
        }
    }

    /// The scan site this station takes its girth from.
    public var site: BodySite {
        switch self {
        case .neck: return .neck
        case .shoulder: return .shoulderWidth
        case .chest: return .chest
        case .waist: return .waist
        case .hip: return .hip
        case .thigh: return .thigh
        case .calf: return .calf
        }
    }

    /// How much this girth moves when body mass moves.
    ///
    /// The trunk carries most of a weight change and the extremities very
    /// little — this is why a projection cannot simply scale the whole body by
    /// one number, which would slim somebody's neck at the same rate as their
    /// waist and look wrong to anybody who has ever lost weight.
    ///
    /// **A direct multiplier on the half-rate, deliberately not normalised.**
    /// The first version divided these by their own mean so they averaged one,
    /// which sounded principled and was wrong: it amplified the waist to 2.3×
    /// and forecast an 11% waist reduction for a 10% mass loss, against a
    /// literature figure nearer 6–8%. A test caught it. These are now calibrated
    /// so the waist lands in that published band — 1.4 × (r/2) = 7% of a 10%
    /// loss — and the rest fall away from it in the order weight actually
    /// leaves a body.
    public var massResponsiveness: Double {
        switch self {
        case .waist: return 1.40
        case .hip: return 0.90
        case .chest: return 0.70
        case .thigh: return 0.60
        case .neck: return 0.35
        case .shoulder: return 0.30
        case .calf: return 0.25
        }
    }
}

/// One station's girth, and whether anybody measured it.
public struct BodyStationValue: Sendable, Equatable {
    public let station: BodyStation
    public let circumferenceCentimetres: Double
    /// False where the value was estimated from height, weight and body fat
    /// rather than taken from a scan.
    ///
    /// Carried per station rather than per model because a real scan usually
    /// measures some sites and not others, and the renderer draws the estimated
    /// stretches differently — the same rule as a dashed chart line.
    public let isMeasured: Bool

    public init(station: BodyStation, circumferenceCentimetres: Double,
                isMeasured: Bool) {
        self.station = station
        self.circumferenceCentimetres = circumferenceCentimetres
        self.isMeasured = isMeasured
    }
}

/// The shape of a body, as girths up its height.
///
/// ## What this is, and what it is not
///
/// It is a **representation**, and every surface that draws it says so. It is
/// not a photograph, not the LiDAR mesh, and not a claim that the reader's body
/// has these proportions where they were not measured.
///
/// It exists in this form rather than as a stored mesh for one reason: the
/// reader asked to see their body *move* between scans and on into a forecast,
/// and a scanned mesh can do neither. Two meshes have no vertex correspondence,
/// so there is nothing to interpolate; and no mesh can be extrapolated forward
/// at all. A parametric shape can do both, and the smooth movement between
/// captures was named as the priority over the scrubber itself.
public struct BodyModelParameters: Sendable, Equatable {

    public let heightMetres: Double
    public let stations: [BodyStationValue]
    public let date: Date
    /// True where nothing was measured and the whole shape came from weight and
    /// body fat — the state a reader is in before their first scan.
    public var isWhollyEstimated: Bool { stations.allSatisfy { !$0.isMeasured } }

    public init(heightMetres: Double, stations: [BodyStationValue], date: Date) {
        self.heightMetres = heightMetres
        // Canonical order, always complete — see `BodyStation`.
        self.stations = BodyStation.allCases.compactMap { station in
            stations.first { $0.station == station }
        }
        self.date = date
    }

    public func girth(_ station: BodyStation) -> Double? {
        stations.first { $0.station == station }?.circumferenceCentimetres
    }

    /// Build from whatever the app holds.
    ///
    /// Measured sites win; the rest are estimated from height, weight and body
    /// fat so the model renders **before the reader has ever scanned**. That is
    /// deliberate: a body model that appears only after a scan cannot be the
    /// thing that persuades somebody to take one.
    public static func build(heightMetres: Double, weightKg: Double,
                             bodyFatPercentage: Double?, sex: BiologicalSex,
                             measurements: BodyMeasurements?,
                             date: Date) -> BodyModelParameters? {
        guard heightMetres > 0.5, weightKg > 0 else { return nil }
        let estimated = estimatedGirths(heightMetres: heightMetres, weightKg: weightKg,
                                        bodyFatPercentage: bodyFatPercentage, sex: sex)
        let stations = BodyStation.allCases.map { station -> BodyStationValue in
            if let measured = measurements?.mean(station.site) {
                return BodyStationValue(station: station,
                                        circumferenceCentimetres: measured,
                                        isMeasured: true)
            }
            return BodyStationValue(station: station,
                                    circumferenceCentimetres: estimated[station] ?? 0,
                                    isMeasured: false)
        }
        return BodyModelParameters(heightMetres: heightMetres, stations: stations,
                                   date: date)
    }

    /// A population-average shape scaled to this person's size.
    ///
    /// **Openly a stand-in.** Girths are taken as fractions of stature for an
    /// average build, then scaled by how far the reader's BMI and body fat sit
    /// from the middle of the range — heavier pushes the trunk out faster than
    /// the limbs, which is the same responsiveness the projection uses.
    ///
    /// It will be wrong about any particular reader in a way a scan fixes
    /// immediately. It is here so the first render is recognisably a body of
    /// roughly the right size and shape, not so anybody reads a number off it —
    /// nothing scores from these, and `isMeasured` is false on every one.
    static func estimatedGirths(heightMetres: Double, weightKg: Double,
                                bodyFatPercentage: Double?,
                                sex: BiologicalSex) -> [BodyStation: Double] {
        let heightCm = heightMetres * 100
        let bmi = weightKg / (heightMetres * heightMetres)
        // 22 is the middle of the healthy BMI band; everything below scales
        // girths away from the average build in proportion to responsiveness.
        let bmiOffset = (bmi - 22) / 22
        let fatOffset = ((bodyFatPercentage ?? (sex == .male ? 20 : 28))
                         - (sex == .male ? 20 : 28)) / 100

        // Fractions of stature for an average adult build.
        let base: [BodyStation: Double] = sex == .male
            ? [.neck: 0.215, .shoulder: 0.259, .chest: 0.552,
               .waist: 0.472, .hip: 0.545, .thigh: 0.316, .calf: 0.213]
            : [.neck: 0.194, .shoulder: 0.240, .chest: 0.545,
               .waist: 0.436, .hip: 0.585, .thigh: 0.330, .calf: 0.212]

        var out: [BodyStation: Double] = [:]
        for station in BodyStation.allCases {
            let fraction = base[station] ?? 0.3
            let response = station.massResponsiveness
            let scale = 1 + response * (bmiOffset * 0.55 + fatOffset * 0.45)
            out[station] = fraction * heightCm * max(scale, 0.5)
        }
        return out
    }

    /// The shape part-way between two, for the morph the reader asked for.
    ///
    /// `t` is clamped to 0…1. Station-wise linear: every model carries every
    /// station, so there is a value at both ends of every one and no
    /// correspondence problem to solve.
    ///
    /// A station is `isMeasured` in the result only where it was measured at
    /// **both** ends — a morph out of an estimate is still an estimate, and
    /// letting it inherit the measured end would launder a guess into a fact
    /// halfway through the animation.
    public static func interpolate(from first: BodyModelParameters,
                                   to second: BodyModelParameters,
                                   t: Double) -> BodyModelParameters {
        let t = min(max(t, 0), 1)
        let stations = BodyStation.allCases.map { station -> BodyStationValue in
            let a = first.girth(station) ?? 0
            let b = second.girth(station) ?? 0
            let measured = (first.stations.first { $0.station == station }?.isMeasured ?? false)
                && (second.stations.first { $0.station == station }?.isMeasured ?? false)
            return BodyStationValue(station: station,
                                    circumferenceCentimetres: a + (b - a) * t,
                                    isMeasured: measured)
        }
        let height = first.heightMetres + (second.heightMetres - first.heightMetres) * t
        let date = Date(timeIntervalSince1970:
            first.date.timeIntervalSince1970
            + (second.date.timeIntervalSince1970 - first.date.timeIntervalSince1970) * t)
        return BodyModelParameters(heightMetres: height, stations: stations, date: date)
    }

    /// What the shape looks like some weeks out, if the current trend holds.
    ///
    /// ## What it claims
    ///
    /// The mass change comes from `CompositionVelocity`, which is fitted from
    /// real weigh-ins and carries its own `residualSD`. This distributes that
    /// change across the stations by `massResponsiveness`, normalised so the
    /// girths move together at the rate the *whole body* is moving rather than
    /// each one scaling independently.
    ///
    /// Everything about the result is a model: nothing here was measured, no
    /// station comes back `isMeasured`, and the caller draws it as inferred.
    /// The phrase the app already uses for this shape of claim is **"if today's
    /// numbers hold"**, and it is the right one here too.
    ///
    /// Returns nil where the weight is not meaningfully moving — projecting a
    /// body forward from a slope that is inside its own noise draws a change
    /// nobody has evidence for. `CompositionVelocity.isMoving` owns that call.
    public static func project(_ current: BodyModelParameters,
                               velocity: CompositionVelocity,
                               weeks: Double) -> BodyModelParameters? {
        guard velocity.isMoving, weeks > 0, velocity.latestWeight > 0 else { return nil }
        let deltaKg = velocity.kilogramsPerWeek * weeks
        let relative = deltaKg / velocity.latestWeight

        let stations = current.stations.map { value -> BodyStationValue in
            // Used directly, not normalised — see `massResponsiveness`, where
            // normalising is recorded as a calibration error a test caught.
            let response = value.station.massResponsiveness
            // A girth is a length, and mass scales with volume — so a relative
            // mass change of r moves a circumference by roughly r/2, not r.
            // Getting this wrong doubles every forecast.
            let scale = 1 + response * relative / 2
            return BodyStationValue(station: value.station,
                                    circumferenceCentimetres:
                                        max(value.circumferenceCentimetres * scale, 1),
                                    isMeasured: false)
        }
        let date = current.date.addingTimeInterval(weeks * 7 * 24 * 3600)
        return BodyModelParameters(heightMetres: current.heightMetres,
                                   stations: stations, date: date)
    }

    /// The forecast's honest ± at a given horizon, in kilograms.
    ///
    /// `residualSD` is the typical distance of a real weigh-in from the fitted
    /// line, so it is what the band around a projection has to be drawn from —
    /// exactly as `CardioTrajectory` already does for VO₂max.
    public static func projectionSpreadKg(_ velocity: CompositionVelocity) -> Double {
        velocity.residualSD
    }
}
