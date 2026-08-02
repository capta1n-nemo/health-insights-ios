import Foundation

/// What a card section is not telling you.
///
/// ## Why this is a type and not a `Text` at the bottom of each section
///
/// Read across `InsightDetailView` before this existed, the footnote was three
/// colours doing one job (`.tertiary`, `.secondary`, `Theme.warn`) and its
/// *presence* was arbitrary. Score history caveated its floor; "What comes
/// first" — a lag fitted through a short series, the most inferential claim on
/// the screen — said nothing at all. The pattern is familiar: a rule that lives
/// in the view layer is verified only by eye, and the app target has no test
/// target.
///
/// Making it a required argument of `InsightSection` turns "did anyone remember
/// the caveat" into a compile error. Making it a *type* is what lets the wording
/// be tested — and the wording is the honesty claim, so it is the part that can
/// actually be wrong.
///
/// `.none` is a real answer, not an omission: a section that plots measured
/// readings and says nothing more is entitled to say nothing more.
public struct SectionCaveat: Sendable, Equatable {

    /// What kind of gap between what is drawn and what was measured.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// Measured, reported, nothing inferred.
        case none
        /// Rebuilt from history as it stood on each past day.
        case replayed
        /// A line or trend fitted through points.
        case fitted
        /// Derived from something else that was measured.
        case estimated
        /// A value for a time that has not happened.
        case projected
        /// Some of the inputs are absent, stale or unjudgeable.
        case partial
        /// A published approximation rather than a lookup into real data.
        case approximate

        /// How far the section's content sits from something measured. Used
        /// only to pick the surviving kind when two caveats are joined, so a
        /// section that both replays *and* projects classifies as the stronger
        /// claim rather than as whichever was written first.
        var strength: Int {
            switch self {
            case .none: return 0
            case .partial: return 1
            case .approximate: return 2
            case .replayed: return 3
            case .fitted: return 4
            case .estimated: return 5
            case .projected: return 6
            }
        }
    }

    public let kind: Kind
    public let text: String?

    /// Whether this section shows the reader something nobody measured.
    public var isInference: Bool { kind != .none }

    // MARK: - The vocabulary

    /// This section reports what was measured. Stated explicitly at the call
    /// site rather than defaulted, so choosing it is a decision somebody made.
    public static let none = SectionCaveat(kind: .none, text: nil)

    public static let replayedHistory = SectionCaveat(
        kind: .replayed,
        text: "Rebuilt from the readings as they stood on each day. Facts you "
            + "entered once — cholesterol, smoking — are applied as they stand "
            + "now, because the app has no history for them.")

    /// Reconstructed days need the floor; days the app itself scored do not.
    /// The old copy claimed sub-floor days flatly "aren't shown", and the
    /// user's export produced a counterexample the same week: a stored day the
    /// app genuinely told them about, kept in the line (as it should be — a
    /// stored point is the record of what was said), under a footnote denying
    /// it existed.
    public static let scoreFloor = SectionCaveat(
        kind: .partial,
        text: "Reconstructed days are only drawn once at least two signals were "
            + "recording — a score resting on one measurement isn't one. Days "
            + "the app scored for you at the time are kept as they were shown.")

    /// Weight change credited to whichever dose happened to be the current one.
    ///
    /// The text lives on `MedicationResponse` because the analysis and the
    /// disclaimer are the same claim, and three surfaces draw that analysis.
    /// Three hand-written versions of a caveat is three chances for one of them
    /// to be the soft one.
    public static let doseAttribution = SectionCaveat(
        kind: .estimated, text: MedicationResponse.caveat)

    /// Signals a scan looks at but does not weigh into the score.
    public static func unscored(signals: Int) -> SectionCaveat {
        SectionCaveat(
            kind: .partial,
            text: "\(signals) more \(plural(signals, "signal")) "
                + "\(signals == 1 ? "is" : "are") checked for anything unusual but "
                + "not scored — a scan reports outliers rather than averaging them in.")
    }

    /// The body-composition history, over however many weigh-ins are in view.
    public static func compositionWindow(weighIns: Int) -> SectionCaveat {
        SectionCaveat(
            kind: .estimated,
            text: "Your weight, split the same way as above, across \(weighIns) "
                + "\(plural(weighIns, "weigh-in")). The axis tops out at your "
                + "heaviest reading in this window rather than a round number "
                + "above it, so changing the timeframe rescales the picture. A "
                + "band thinning while the total falls is where the weight came off.")
    }

    /// Takes the date already formatted, because `Date.formatted(date:time:)`
    /// is one of the Foundation APIs that is Darwin-only — and InsightKit has
    /// been broken on Linux by exactly that before.
    public static func splitOnlyFrom(_ formattedDate: String) -> SectionCaveat {
        SectionCaveat(
            kind: .estimated,
            text: "Muscle and bone are only separated from \(formattedDate), when "
                + "your scale started reporting them. Before that the lean part is "
                + "drawn undivided rather than guessed at.")
    }

    /// The centile strip. `PeerStandingModel`'s own stated honesty constraint:
    /// the published sources give means and spreads, not full curves.
    public static let approximateNorms = SectionCaveat(
        kind: .approximate,
        text: "Centiles are normal approximations to published age and sex "
            + "summary statistics, not lookups into a real distribution. They "
            + "place you roughly, and none of them is a verdict.")

    /// Any forward projection. Deliberately says what would have to hold.
    public static let ifTodaysNumbersHold = SectionCaveat(
        kind: .projected,
        text: "Projected by running the same equations at future ages, on today's "
            + "numbers. It is what happens if nothing changes, not a forecast of "
            + "what will.")

    public static func fittedThrough(points: Int) -> SectionCaveat {
        SectionCaveat(
            kind: .fitted,
            text: "Fitted through \(points) \(plural(points, "day")) of overlap. A "
                + "short run of days can show a relationship that a longer one "
                + "does not, so this is a place to look rather than a finding.")
    }

    /// Energy's hourly curve. The model is explicit that it is a model — a test
    /// stops it ever claiming high confidence — so the section says so too.
    public static let modelledCurve = SectionCaveat(
        kind: .estimated,
        text: "Reconstructed hour by hour from your sleep, your heart rate and the "
            + "work you did. It is a model of the day rather than a reading taken "
            + "at each hour.")

    /// Sleep regularity: the points are measured, the centre and the band are not.
    public static func fittedCentre(nights: Int) -> SectionCaveat {
        SectionCaveat(
            kind: .fitted,
            text: "Each point is a measured night. The dashed centre and the shaded "
                + "band are fitted across these \(nights) \(plural(nights, "night")), "
                + "so both move as new nights arrive.")
    }

    /// The substance load series.
    public static let decayingLoad = SectionCaveat(
        kind: .estimated,
        text: "A running total that decays rather than a measurement — what you "
            + "logged, weighted by how long ago it was. It describes intake, not "
            + "your body's response to it.")

    /// Patterns and lags: associations found in one person's own window.
    public static let associationsNotCauses = SectionCaveat(
        kind: .fitted,
        text: "These are associations found in your own data over this window, not "
            + "causes, and not medical findings. A short run of days can show a "
            + "relationship that isn't there.")

    public static func periodContrast(days: Int) -> SectionCaveat {
        SectionCaveat(
            kind: .fitted,
            text: "Both windows are \(days) \(plural(days, "day")) long, so a signal "
                + "you record only occasionally is being compared on fewer readings "
                + "than one you record daily.")
    }

    /// For a section whose caveat is computed by a type that already tests its
    /// own phrasing — `VitalDeparturePanel.footnote` is the case this exists
    /// for. The kind is still stated here, so the section is still classified.
    public static func computed(_ kind: Kind, _ text: String) -> SectionCaveat {
        SectionCaveat(kind: kind, text: text)
    }

    /// Two caveats under one section, as one paragraph.
    ///
    /// The joined kind is the most inferential of the parts, on the `Kind`
    /// ordering below — a section that both replays *and* estimates should
    /// classify as the stronger claim, not the first one written.
    public static func joined(_ caveats: [SectionCaveat]) -> SectionCaveat {
        let texts = caveats.compactMap(\.text)
        guard !texts.isEmpty else { return .none }
        let kind = caveats.map(\.kind).max { $0.strength < $1.strength } ?? .none
        return SectionCaveat(kind: kind, text: texts.joined(separator: " "))
    }

    // MARK: -

    /// The plural bug this repo has already shipped once, in one place.
    /// "across 1 weigh-ins" was live in `InsightDetailView`.
    ///
    /// `plural:` is for the words where adding an s is wrong — "entry" is the
    /// one in use. Defaulted rather than required, because every other noun on
    /// these screens is regular and an explicit form for all of them would be
    /// noise around the one that matters.
    /// Public because the app target's section trailers count things too, and
    /// "1 signals" shipped from exactly the call sites that couldn't reach this.
    public static func plural(_ count: Int, _ singular: String,
                              plural: String? = nil) -> String {
        count == 1 ? singular : (plural ?? singular + "s")
    }
}
