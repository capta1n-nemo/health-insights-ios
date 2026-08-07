import Foundation

/// **Where something happened, stored as little of it as the job survives.**
///
/// ## The promise this type is written against
///
/// The app tells the reader nothing leaves the phone, and **a stored coordinate
/// history is the most re-identifying thing this app could ever hold** — more
/// than a heart rate, more than a medication, more than a calendar title. A
/// timeline of coordinates identifies a person from four points
/// (de Montjoye et al., *Scientific Reports* 3:1376, 2013) and identifies their
/// home, their workplace, their clinic and their partner's address as a side
/// effect. There is no version of "we anonymise it" that survives that paper.
///
/// So the design question was never *how do we protect the location history*.
/// It was **what is the least we can store and still answer the question the
/// reader asked for.** The reader's ask (backlog P32) is a confirmation card
/// carrying *"GPS map, time, why it was flagged"* — a memory aid, so they can
/// look at a flagged half-hour and remember what they were doing.
///
/// Three consequences, and every one of them is a deliberate loss of capability:
///
/// 1. **No timeline. Ever.** This type is attached to a *flagged event* and to
///    nothing else. There is no track, no breadcrumb, no visit log. What the app
///    holds is a handful of unanswered questions, not a record of a life.
/// 2. **The coordinate is borrowed, not kept.** It exists only while the event
///    is unanswered, because that is the only window in which it is doing the
///    job it was collected for. `forgettingCoordinate()` is called the moment
///    the reader confirms or corrects, and again on anything that ages out —
///    see `FlaggedEventRetention`. What survives review is
///    `PlaceFamiliarity`, which is one of four words.
/// 3. **It is coarse from the instant it is created.** `CoarseCoordinate`
///    rounds on the way in, so the precise fix is never written down anywhere,
///    not even briefly. Rounding at display time would mean the app *had* the
///    precise value and chose not to show it, which is a different and much
///    weaker promise.
///
/// ## Why a coordinate at all, rather than only "somewhere unusual"
///
/// That question is the right one and it was asked at every field here. The
/// answer for `familiarity` is *no coordinate needed* — `PlaceAnchorSet` answers
/// it by comparison and stores no coordinate for the event itself. The answer
/// for the map is that a map with no position is not a map, and the reader named
/// one specifically. So the coordinate is the **one** field that exists purely
/// for the reader's own eyes, and it is the one field with an expiry.
///
/// ⚠️ **Nothing here reaches the export.** See
/// `HealthDataExport.exportKey(for: .flaggedEvents)`, which carries the event
/// and drops the place — the same call `calendarEvents` makes about titles, with
/// more force.
public struct PlaceContext: Sendable, Equatable, Codable, Hashable {

    /// How usual this spot is for this person. **Survives review**, because it
    /// is a comparison rather than a position: knowing an event happened
    /// somewhere the reader rarely goes locates nobody.
    public let familiarity: PlaceFamiliarity

    /// A rounded fix, **held only while the event is unanswered**.
    ///
    /// Nil is the resting state of this field and is not an error: it means the
    /// app was not watching (permission absent, or the event happened while the
    /// app could not observe), or that the reader has already answered and the
    /// coordinate has been dropped.
    public let coordinate: CoarseCoordinate?

    /// Which API produced it, so a reader asking "how did you know that" gets a
    /// true answer and so `verify`-style review can see that nothing here came
    /// from continuous tracking.
    public let capture: PlaceCapture

    /// When the fix was taken — **not** when the event was. A visit-monitoring
    /// callback can arrive well after the event it ends up attached to, and a
    /// map pin drawn from a fix taken forty minutes later must say so rather
    /// than implying the app watched the whole window.
    public let capturedAt: Date?

    public init(familiarity: PlaceFamiliarity,
                coordinate: CoarseCoordinate? = nil,
                capture: PlaceCapture = .none,
                capturedAt: Date? = nil) {
        self.familiarity = familiarity
        self.coordinate = coordinate
        self.capture = capture
        self.capturedAt = capturedAt
    }

    /// Nothing was observed. The feed shows this rather than omitting the row,
    /// so "no place recorded" is visibly a state the app was in and not a
    /// feature that silently did nothing.
    public static let unobserved = PlaceContext(familiarity: .unknown)

    /// **The retention step, and the reason the coordinate is allowed to exist
    /// at all.**
    ///
    /// Called when the reader answers, and by `FlaggedEventRetention` on
    /// anything that ages out. Returns a context that keeps the comparison and
    /// has forgotten the position — including `capturedAt`, which is a second
    /// (weaker, but real) locating signal once it is the only thing left beside
    /// a familiarity.
    public func forgettingCoordinate() -> PlaceContext {
        PlaceContext(familiarity: familiarity, coordinate: nil,
                     capture: capture, capturedAt: nil)
    }

    /// Whether there is anything left to draw a map from.
    public var canDrawMap: Bool { coordinate != nil }

    /// One line for the confirmation card, in the reader's terms.
    public var sentence: String {
        switch familiarity {
        case .usual:
            return "Somewhere you often are."
        case .occasional:
            return "Somewhere you go now and then."
        case .unfamiliar:
            return "Somewhere you don't usually go."
        case .unknown:
            return capture == .none
                ? "No place recorded — the app wasn't watching."
                : "Place recorded, but not enough history to say whether it's usual."
        }
    }
}

/// How usual a spot is, and **the only part of a place that outlives an answer.**
///
/// Four words, deliberately, and none of them is a position. The scale is
/// comparative — it says how this spot ranks against the reader's own handful of
/// anchors — so it carries no information about *where* anything is. Two people
/// with identical `familiarity` histories share nothing but a habit.
public enum PlaceFamiliarity: String, Sendable, Codable, CaseIterable, Hashable {
    /// One of the reader's most-visited anchors.
    case usual
    /// A known anchor, but not a frequent one.
    case occasional
    /// Not near any anchor the app holds.
    case unfamiliar
    /// Not enough anchors yet to make the comparison, or nothing observed.
    ///
    /// ⚠️ **Different from `unfamiliar`, and the difference matters.** "Not
    /// somewhere you usually go" is a finding; "we have no idea" is the absence
    /// of one, and collapsing them would let a fresh install report every
    /// evening at home as unusual.
    case unknown

    public var displayName: String {
        switch self {
        case .usual: return "Usual place"
        case .occasional: return "Sometimes here"
        case .unfamiliar: return "Unusual place"
        case .unknown: return "Place unknown"
        }
    }
}

/// Which Core Location facility produced a fix.
///
/// ⚠️ **`continuousUpdates` is deliberately absent.** There is no case for it
/// because there is no code path that would set one: `startUpdatingLocation` is
/// never called by this app. The enum is the record of that decision in a place
/// a future change would have to edit.
public enum PlaceCapture: String, Sendable, Codable, CaseIterable, Hashable {
    /// `CLLocationManager.startMonitoringVisits` — the coarsest and lowest-power
    /// thing Core Location offers, and the default here. It reports arrivals and
    /// departures at places somebody actually stopped, not a track.
    case visit
    /// `startMonitoringSignificantLocationChanges` — cell-tower granularity,
    /// roughly 500 m and no more often than every few minutes.
    case significantChange
    /// A single `requestLocation` taken while the reader had the app open and
    /// was looking at the feed. One fix, on a screen they opened.
    case foregroundFix
    /// Nothing was captured.
    case none

    public var displayName: String {
        switch self {
        case .visit: return "Visit monitoring"
        case .significantChange: return "Significant-change monitoring"
        case .foregroundFix: return "A single fix while you had the app open"
        case .none: return "Nothing recorded"
        }
    }
}

/// **A coordinate that was rounded before it was ever stored.**
///
/// The rounding happens in `init(rounding:...)` and there is no initialiser that
/// takes a raw pair, which is the point: a precise fix cannot be written into
/// this type by accident, so it never reaches disk even for one write.
///
/// ⚠️ **Both axes are rounded to the same *ground* distance**, not to the same
/// number of decimal places. A degree of longitude is 111 km at the equator and
/// 79 km at 45° N, so a fixed decimal step would quietly be almost half as
/// coarse in the east-west direction at the reader's latitude — and
/// `precisionMetres` would then be a claim the data did not support. This app's
/// standing rule is that a stated uncertainty has to be the real one.
public struct CoarseCoordinate: Sendable, Equatable, Codable, Hashable {
    public let latitude: Double
    public let longitude: Double
    /// The size of the cell this was snapped to, in metres. **Draw a circle,
    /// never a pin** — a pin drawn from a rounded value asserts a precision that
    /// was thrown away on purpose.
    public let precisionMetres: Double

    /// Metres per degree of latitude. Constant enough for a rounding step; the
    /// real figure varies by ~1% between equator and pole and no decision here
    /// is sensitive to that.
    public static let metresPerDegreeLatitude: Double = 111_320

    /// **The default cell, and why it is this size.**
    ///
    /// 250 m is large enough that the cell contains a street rather than a
    /// doorway, and small enough that a map still shows the reader which part of
    /// town they were in — which is the entire job. It is not a privacy
    /// guarantee on its own (nothing at this scale is); it is the coarsest
    /// setting that still answers the reader's question, which is the test every
    /// field in this file had to pass.
    public static let defaultPrecisionMetres: Double = 250

    public init(rounding latitude: Double, longitude: Double,
                toMetres precision: Double = defaultPrecisionMetres) {
        let precision = Swift.max(1, precision)
        let latStep = precision / Self.metresPerDegreeLatitude
        // Longitude degrees shrink with latitude, so the step has to grow by
        // 1/cos(lat) for the cell to stay square on the ground. Floored so the
        // near-polar case cannot divide by ~0 and produce a step that wraps the
        // globe.
        let shrink = Swift.max(0.01, cos(latitude * .pi / 180))
        let lonStep = latStep / shrink
        self.latitude = (latitude / latStep).rounded() * latStep
        self.longitude = (longitude / lonStep).rounded() * lonStep
        self.precisionMetres = precision
    }

    /// Rebuild a value that was already rounded — for decoding, and for tests.
    /// **Not for a fresh fix**: it does no rounding, so passing a raw reading
    /// here is exactly the mistake the other initialiser exists to prevent.
    public init(alreadyRoundedLatitude latitude: Double, longitude: Double,
                precisionMetres: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.precisionMetres = precisionMetres
    }

    /// Rough great-circle distance in metres. Equirectangular rather than
    /// haversine: everything this is used for is a few kilometres at most, where
    /// the two agree to well inside one cell.
    public func metres(to other: CoarseCoordinate) -> Double {
        let meanLat = (latitude + other.latitude) / 2 * .pi / 180
        let dLat = (latitude - other.latitude) * Self.metresPerDegreeLatitude
        let dLon = (longitude - other.longitude) * Self.metresPerDegreeLatitude * cos(meanLat)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}

// MARK: - Anchors

/// **One place the reader turns out to go, held as a count and nothing else.**
///
/// This is what makes `PlaceFamiliarity` answerable without a history. An anchor
/// is a coarse cell plus how often it has been seen — no timestamps beyond a
/// day-resolution `lastSeenDay`, no order, no durations. From a full set of
/// anchors you can tell that somebody has a home and a workplace; you cannot
/// tell which is which, when they were at either, or in what sequence. That gap
/// is the difference between this and a location history, and it is deliberate.
public struct PlaceAnchor: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let cell: CoarseCoordinate
    /// How many separate arrivals have landed in this cell.
    public let visits: Int
    /// Day resolution on purpose. A precise timestamp beside a coarse cell
    /// re-introduces most of what the rounding removed — "the 250 m cell they
    /// were in at 03:14" is close to an address.
    public let lastSeenDay: Date

    public var id: String {
        String(format: "%.4f,%.4f", cell.latitude, cell.longitude)
    }

    public init(cell: CoarseCoordinate, visits: Int, lastSeenDay: Date) {
        self.cell = cell
        self.visits = visits
        self.lastSeenDay = lastSeenDay
    }
}

/// **The reader's handful of anchors, capped.**
///
/// ⚠️ **The cap is the privacy control, not an optimisation.** An uncapped set
/// of visited cells *is* a location history with the times filed off, and it
/// would grow into one over a year of ordinary life. Twelve is enough to hold a
/// home, a workplace, a gym, a few regular haunts and a couple of spares — which
/// is all `familiarity` needs — and far too few to reconstruct where somebody
/// spends their days. When a thirteenth arrives, the least-visited anchor is
/// forgotten.
public struct PlaceAnchorSet: Sendable, Equatable, Codable {

    /// The most anchors that will ever be held. See the type comment: this is a
    /// bound on what the app knows, not a buffer size.
    public static let maximumAnchors = 12

    /// A new cell inside this distance of an existing anchor is the same place.
    /// Slightly wider than one 250 m cell, so a fix that lands on a cell
    /// boundary does not create a phantom second anchor for the reader's own
    /// kitchen.
    public static let samePlaceMetres: Double = 400

    /// Visits at or above this make an anchor "usual". Below it, the anchor is
    /// known but occasional.
    public static let usualVisitFloor = 8

    /// How many anchors must exist before `familiarity` will say anything at
    /// all. Below this every answer is `.unknown`: with two anchors, "not one of
    /// your usual places" is true of the entire planet and tells the reader
    /// nothing.
    public static let minimumAnchorsForAJudgement = 4

    public private(set) var anchors: [PlaceAnchor]

    public init(anchors: [PlaceAnchor] = []) {
        self.anchors = anchors
    }

    /// Record an arrival, folding it into an existing anchor where one is close
    /// enough. Returns a new set; nothing here mutates in place, so a caller
    /// cannot half-apply an update.
    public func noting(_ cell: CoarseCoordinate, on day: Date,
                       calendar: Calendar = .current) -> PlaceAnchorSet {
        let dayOnly = calendar.startOfDay(for: day)
        var updated = anchors
        if let index = updated.firstIndex(where: {
            $0.cell.metres(to: cell) <= Self.samePlaceMetres
        }) {
            let existing = updated[index]
            updated[index] = PlaceAnchor(cell: existing.cell,
                                         visits: existing.visits + 1,
                                         lastSeenDay: Swift.max(existing.lastSeenDay, dayOnly))
        } else {
            updated.append(PlaceAnchor(cell: cell, visits: 1, lastSeenDay: dayOnly))
        }
        // Fewest visits go first, oldest breaking the tie — so a place seen once
        // last year is what gets forgotten, never the one seen once yesterday
        // that might be turning into a habit.
        if updated.count > Self.maximumAnchors {
            updated.sort {
                $0.visits == $1.visits ? $0.lastSeenDay > $1.lastSeenDay : $0.visits > $1.visits
            }
            updated = Array(updated.prefix(Self.maximumAnchors))
        }
        return PlaceAnchorSet(anchors: updated)
    }

    /// How usual a spot is, by comparison alone.
    ///
    /// Returns `.unknown` below `minimumAnchorsForAJudgement` — see that
    /// constant. A refusal here is the same discipline every gated figure in
    /// this app makes, and for the same reason: a comparison drawn from two
    /// reference points is not a comparison.
    public func familiarity(of cell: CoarseCoordinate) -> PlaceFamiliarity {
        guard anchors.count >= Self.minimumAnchorsForAJudgement else { return .unknown }
        guard let match = anchors
            .filter({ $0.cell.metres(to: cell) <= Self.samePlaceMetres })
            .max(by: { $0.visits < $1.visits })
        else { return .unfamiliar }
        return match.visits >= Self.usualVisitFloor ? .usual : .occasional
    }

    /// How far off a judgement is, for the feed's own empty state. Nil once the
    /// set can answer.
    public var gate: CoverageGate? {
        CoverageGate.ifShort(need: Self.minimumAnchorsForAJudgement,
                             have: anchors.count,
                             unit: "regular place",
                             unlocks: "the app can tell an unusual spot from one you're always at")
    }
}

// MARK: - Permission

/// **What the app is allowed to observe**, as a value InsightKit can reason
/// about without importing Core Location.
///
/// The app target maps `CLAuthorizationStatus` onto this in
/// `Core/Location/LocationCapture.swift`. Kept here because the pieces that have
/// to *say something* about the permission — the feed's empty state, the
/// dismissible suggestion the reader made a condition of building any of this —
/// are testable logic, and they were not going to be testable behind a
/// framework that returns a different answer on every device.
public enum LocationAccess: String, Sendable, Codable, CaseIterable, Hashable {
    /// Never asked. **The state a fresh install is in, and the one the
    /// onboarding step exists for** — the reader's condition was that the
    /// explanation comes *before* the system prompt, so the app must be able to
    /// sit here deliberately rather than prompting on first launch.
    case notAsked
    /// Asked, and declined. Nothing is captured and nothing ever asks again —
    /// iOS would not show the prompt a second time anyway, and a suggestion that
    /// cannot be acted on is a nag.
    case denied
    /// Granted while the app is open. **What the onboarding step asks for**, and
    /// the default this app stops at.
    case whileUsing
    /// Granted for visit monitoring with the app closed. A second, separate ask
    /// made from inside the feed, never from onboarding — see
    /// `LocationCapture.requestBackgroundVisits()`.
    case always
    /// No location services on this device at all, or restricted by policy.
    case unavailable

    /// Whether a place can be observed at all.
    public var capturesPlaces: Bool {
        switch self {
        case .whileUsing, .always: return true
        case .notAsked, .denied, .unavailable: return false
        }
    }

    /// Whether asking again could change anything. False for `.denied` (iOS
    /// will not re-prompt) and for `.unavailable`.
    public var isWorthAsking: Bool {
        switch self {
        case .notAsked: return true
        case .whileUsing: return false
        case .denied, .always, .unavailable: return false
        }
    }

    /// What the feed says about the permission, in the reader's terms. Nil where
    /// there is nothing to say.
    public var sentence: String? {
        switch self {
        case .notAsked:
            return "Location is off. Events are still flagged from your vitals — you just won't see where you were."
        case .denied:
            return "Location is off. Events are still flagged from your vitals; turn location on in iOS Settings if you'd like the map back."
        case .whileUsing:
            return "Places are recorded only while you have the app open."
        case .always:
            return nil
        case .unavailable:
            return "This device can't provide a location, so events are flagged from your vitals alone."
        }
    }
}
