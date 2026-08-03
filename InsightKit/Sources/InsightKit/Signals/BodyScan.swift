import Foundation

/// A place on the body a circumference is taken.
///
/// Stored as a list of `(site, side, value)` rather than as a struct with a
/// property per site, and that is the decision that makes re-parsing possible:
/// **adding a site later must not change the shape of what is already on
/// disk.** A stored scan decoded by a newer build gains the sites the newer
/// parser found and keeps the ones it did not.
public enum BodySite: String, Sendable, Codable, CaseIterable {
    case neck, chest, underbust, waist, abdomen, hip
    case shoulderWidth, inseam
    /// Taken on both sides.
    case thigh, calf, upperArm, forearm

    /// Whether the site is measured left and right rather than once.
    ///
    /// Drives `BodySymmetry`, and drives the rule that a paired site's
    /// `MetricType` carries the **mean** — two lines a centimetre apart say less
    /// than one line and a symmetry figure.
    public var isPaired: Bool {
        switch self {
        case .thigh, .calf, .upperArm, .forearm: return true
        case .neck, .chest, .underbust, .waist, .abdomen, .hip,
             .shoulderWidth, .inseam: return false
        }
    }

    /// The canonical metric this site trends as, where it has one.
    ///
    /// `nil` is deliberate and is most of them: a `MetricType` costs nine
    /// exhaustive switches and earns a chart, a Data-tab row and a reference
    /// range. The rest are scan data, shown on the scan's own page.
    public var metricType: MetricType? {
        switch self {
        case .waist: return .waistCircumference
        case .hip: return .hipCircumference
        case .chest: return .chestCircumference
        case .neck: return .neckCircumference
        case .shoulderWidth: return .shoulderWidth
        case .thigh: return .thighCircumference
        case .upperArm: return .upperArmCircumference
        case .underbust, .abdomen, .inseam, .calf, .forearm: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .neck: return "Neck"
        case .chest: return "Chest"
        case .underbust: return "Underbust"
        case .waist: return "Waist"
        case .abdomen: return "Abdomen"
        case .hip: return "Hips"
        case .shoulderWidth: return "Shoulders"
        case .inseam: return "Inseam"
        case .thigh: return "Thigh"
        case .calf: return "Calf"
        case .upperArm: return "Upper arm"
        case .forearm: return "Forearm"
        }
    }
}

public enum BodySide: String, Sendable, Codable, CaseIterable {
    case left, right
    /// A site taken once, across the middle.
    case centre
}

public struct BodyMeasurement: Sendable, Equatable, Codable {
    public let site: BodySite
    public let side: BodySide
    public let centimetres: Double

    public init(site: BodySite, side: BodySide = .centre, centimetres: Double) {
        self.site = site
        self.side = side
        self.centimetres = centimetres
    }
}

/// Every circumference one scan produced.
public struct BodyMeasurements: Sendable, Equatable, Codable {
    public let values: [BodyMeasurement]

    public init(_ values: [BodyMeasurement]) {
        self.values = values
    }

    public static let empty = BodyMeasurements([])

    public func value(_ site: BodySite, _ side: BodySide = .centre) -> Double? {
        values.first { $0.site == site && $0.side == side }?.centimetres
    }

    /// One number for a site: the value where it is taken once, the **mean** of
    /// left and right where it is paired, and a lone side where only one was
    /// measured.
    public func mean(_ site: BodySite) -> Double? {
        let matching = values.filter { $0.site == site }.map(\.centimetres)
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0, +) / Double(matching.count)
    }

    public var sites: [BodySite] {
        BodySite.allCases.filter { site in values.contains { $0.site == site } }
    }
}

/// The conditions a scan was taken under.
///
/// ## Why this is stored at all
///
/// Repeatability, not accuracy, is what the market gets wrong — every consumer
/// scanner is reviewed as "inconsistent", and the technical reviews agree on
/// why: results shift with **clothing tightness, posture, camera height and
/// lighting**. None of them record those conditions, so none of them can tell a
/// reader whether two scans are comparable, and a 2 cm "change" that is really a
/// different pair of trousers reads exactly like progress.
///
/// Recording them costs nothing at capture and is what lets `ScanComparability`
/// answer the question honestly afterwards.
public struct ScanConditions: Sendable, Equatable, Codable {

    /// What the reader was wearing, chosen from a short list and reused.
    ///
    /// A free-text field would not compare between scans, and the whole point is
    /// comparison. `.unknown` exists for a tape measurement or an imported scan.
    public enum Clothing: String, Sendable, Codable, CaseIterable {
        case minimal, formFitting, looseFitting, unknown

        public var displayName: String {
            switch self {
            case .minimal: return "Minimal / underwear"
            case .formFitting: return "Form-fitting"
            case .looseFitting: return "Loose"
            case .unknown: return "Not recorded"
            }
        }
    }

    /// Height of the device above the floor, metres.
    public let deviceHeightMetres: Double?
    /// Distance from the device to the subject, metres.
    public let subjectDistanceMetres: Double?
    /// Ambient light, lux, where the device reports it.
    public let ambientLux: Double?
    public let clothing: Clothing
    /// Hour of day, 0–23. Body measurements move within a day — abdominal girth
    /// especially — so morning against evening is a real difference, not noise.
    public let hourOfDay: Int?

    public init(deviceHeightMetres: Double? = nil, subjectDistanceMetres: Double? = nil,
                ambientLux: Double? = nil, clothing: Clothing = .unknown,
                hourOfDay: Int? = nil) {
        self.deviceHeightMetres = deviceHeightMetres
        self.subjectDistanceMetres = subjectDistanceMetres
        self.ambientLux = ambientLux
        self.clothing = clothing
        self.hourOfDay = hourOfDay
    }
}

/// One capture, whole — what is kept, and what it produced.
public struct BodyScan: Sendable, Equatable, Codable, Identifiable {

    /// How the measurements were arrived at.
    ///
    /// Recorded per scan rather than assumed from the device, because a phone
    /// that has LiDAR can still take a camera-only scan when the reader declines
    /// depth in Settings — and the two are not equally accurate, so a chart
    /// mixing them has to be able to say which is which.
    public enum CaptureMode: String, Sendable, Codable, CaseIterable {
        /// True metric depth from the LiDAR sensor.
        case lidarDepth
        /// Silhouette widths from camera segmentation, scaled by the skeleton.
        case cameraSegmentation
        /// A tape measure, entered by hand. The most accurate of the three when
        /// done carefully, and the least repeatable when not.
        case tape

        public var displayName: String {
            switch self {
            case .lidarDepth: return "LiDAR scan"
            case .cameraSegmentation: return "Camera scan"
            case .tape: return "Tape measure"
            }
        }

        /// How much to trust a circumference from this mode.
        ///
        /// Never `.high`: even with LiDAR a circumference is an ellipse fitted
        /// at a height station, and the published consumer benchmark is ±10 mm.
        /// A number this app cannot check against a tape does not get to call
        /// itself certain.
        public var confidence: InsightConfidence {
            switch self {
            case .lidarDepth: return .moderate
            case .cameraSegmentation: return .low
            case .tape: return .moderate
            }
        }
    }

    public let id: UUID
    public let capturedAt: Date
    public let mode: CaptureMode
    /// Which parser produced `measurements`. A later build sweeps every scan
    /// behind its own version and re-derives from the retained assets.
    public let parserVersion: Int
    public let measurements: BodyMeasurements
    public let conditions: ScanConditions
    /// Which assets were kept on disk, so the reader can see what this scan
    /// still holds and whether it can be re-parsed at all.
    public let retainedAssets: Set<BodyScanAsset>

    public init(id: UUID, capturedAt: Date, mode: CaptureMode, parserVersion: Int,
                measurements: BodyMeasurements, conditions: ScanConditions,
                retainedAssets: Set<BodyScanAsset>) {
        self.id = id
        self.capturedAt = capturedAt
        self.mode = mode
        self.parserVersion = parserVersion
        self.measurements = measurements
        self.conditions = conditions
        self.retainedAssets = retainedAssets
    }

    /// Whether this scan can be re-derived by a future parser.
    ///
    /// A scan whose assets were all discarded is a set of numbers and nothing
    /// more — still perfectly good history, but it will never improve. The
    /// Settings screen says so before the reader chooses to keep nothing.
    public var isReparseable: Bool {
        !retainedAssets.isEmpty && mode != .tape
    }

    /// The scan as the shape `BuildAssessmentModel` and `SomatotypeModel`
    /// already read.
    ///
    /// Returns nil without a waist and a height, which are the two the
    /// assessment cannot work without.
    ///
    /// Height comes from the caller rather than the scan: the app already holds
    /// it as `MetricType.height`, it is the one body measurement that does not
    /// change, and a scan re-deriving it every time would let a bad capture
    /// quietly move a constant.
    public func dimensions(heightMetres: Double) -> BodyDimensions? {
        guard let waist = measurements.mean(.waist), heightMetres > 0.5 else { return nil }
        return BodyDimensions(
            capturedAt: capturedAt, heightMetres: heightMetres, waistCentimetres: waist,
            hipCentimetres: measurements.mean(.hip),
            chestCentimetres: measurements.mean(.chest),
            neckCentimetres: measurements.mean(.neck),
            shoulderCentimetres: measurements.mean(.shoulderWidth),
            source: mode.dimensionSource)
    }

    /// The samples this scan contributes to the canonical series.
    ///
    /// Only the sites that earned a `MetricType`; a paired site contributes the
    /// mean. Everything else stays scan data.
    public func samples(source: MetricSource) -> [HealthMetricSample] {
        measurements.sites.compactMap { site in
            guard let metric = site.metricType, let value = measurements.mean(site) else {
                return nil
            }
            return HealthMetricSample(type: metric, value: value,
                                      start: capturedAt, source: source)
        }
    }
}

public extension BodyScan.CaptureMode {
    var dimensionSource: BodyDimensions.Source {
        switch self {
        case .lidarDepth: return .lidar
        case .cameraSegmentation: return .camera
        case .tape: return .tape
        }
    }
}
