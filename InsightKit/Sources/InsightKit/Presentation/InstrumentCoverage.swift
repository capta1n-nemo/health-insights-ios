import Foundation

/// **What the app could actually see last night** — which instruments reported,
/// which were silent, and how unusual that is for each of them. Backlog B3-19.
///
/// ## The ambiguity this exists to remove
///
/// A quiet symptom radar means one of two completely different things: *nothing
/// stirred*, or *the ring was on the charger*. The app rendered both as the same
/// green. That is the worst possible failure for a card whose whole value is
/// that it stays quiet — because a reader who cannot tell the two apart learns
/// that the quiet means nothing, and then the one night it speaks means nothing
/// either.
///
/// Every card in this app already refuses to score on data it does not have.
/// What it never did was **say out loud what it had**. This is the denominator,
/// rendered.
///
/// ## What it is not
///
/// It is not a claim about *why* an instrument was silent. A ring can be on
/// charge, out of battery, unsynced, or simply not worn, and nothing on this
/// phone can tell those apart — so the copy says "reported nothing", which is
/// the only thing that is known. Oura's own `non_wear_time` would separate
/// not-worn from not-synced and is not yet ingested; see the backlog.
///
/// ## Why the coverage record is computed here rather than fetched
///
/// The denominator a reader wants — *"it has reported on 81 of the last 90
/// nights"* — is a property of the samples already on the phone, whichever
/// provider they came from. Deriving it from the sample set means it is right
/// for a Withings scale and an Apple Watch too, and it cannot disagree with the
/// charts, which read the same rows.
public struct InstrumentReport: Sendable, Equatable, Identifiable, Hashable {

    public var id: String { family }

    /// The de-duplicated device identity — see `MetricSource.deviceFamily`. A
    /// ring synced directly *and* mirrored through Apple Health is one
    /// instrument, and counting it twice would overstate coverage.
    public let family: String
    /// What to call it on screen.
    public let displayName: String

    /// Readings inside the night window.
    public let samplesInWindow: Int
    /// Which kinds of reading arrived, newest-first order not implied.
    public let metricsInWindow: [MetricType]
    /// The newest reading from this instrument at any time, so a silent night
    /// can be dated rather than merely noted.
    public let lastHeard: Date?

    /// Nights out of `nightsAssessed` on which this instrument reported
    /// anything at all. The reader's sense of whether tonight is unusual.
    public let nightsCovered: Int
    public let nightsAssessed: Int

    public init(family: String, displayName: String, samplesInWindow: Int,
                metricsInWindow: [MetricType], lastHeard: Date?,
                nightsCovered: Int, nightsAssessed: Int) {
        self.family = family
        self.displayName = displayName
        self.samplesInWindow = samplesInWindow
        self.metricsInWindow = metricsInWindow
        self.lastHeard = lastHeard
        self.nightsCovered = nightsCovered
        self.nightsAssessed = nightsAssessed
    }

    public var reported: Bool { samplesInWindow > 0 }

    /// Share of assessed nights covered, for a bar or a percentage.
    public var coverage: Double {
        guard nightsAssessed > 0 else { return 0 }
        return Double(nightsCovered) / Double(nightsAssessed)
    }

    /// "81 of the last 90 nights" — the denominator, spelled out.
    ///
    /// Derived, never written: the numbers come from the same pass that decided
    /// whether tonight counts, so the sentence cannot go stale against the
    /// figure beside it (backlog D19's rule).
    public var coverageSentence: String {
        "Reported on \(nightsCovered) of the last \(nightsAssessed) nights."
    }

    /// One line saying what this instrument did, with no inference about why.
    public var statusSentence: String {
        if reported {
            let kinds = metricsInWindow.count
            return "Reported \(samplesInWindow) "
                + SectionCaveat.plural(samplesInWindow, "reading")
                + " across \(kinds) " + SectionCaveat.plural(kinds, "kind") + "."
        }
        return "Reported nothing."
    }
}

/// The whole picture for one night.
public struct InstrumentCoverage: Sendable, Equatable {

    /// The night the report covers. Rendered, not assumed — a reader looking at
    /// this at 11pm is being told about the night that ended this morning.
    public let window: DateInterval
    /// Reporting instruments first, then silent ones, each block ordered by how
    /// much of the record they usually carry. The silent ones are the point, but
    /// leading with them would read as an error report on a normal night.
    public let instruments: [InstrumentReport]
    /// How many nights the coverage record looked back over.
    public let nightsAssessed: Int

    public init(window: DateInterval, instruments: [InstrumentReport],
                nightsAssessed: Int) {
        self.window = window
        self.instruments = instruments
        self.nightsAssessed = nightsAssessed
    }

    public var reporting: [InstrumentReport] { instruments.filter(\.reported) }
    public var silent: [InstrumentReport] { instruments.filter { !$0.reported } }

    /// Nothing known well enough to report on. A first-run state, and the one
    /// case where this whole section should not draw at all.
    public var isEmpty: Bool { instruments.isEmpty }

    /// The one-line answer, which is the only line some readers will read.
    ///
    /// Counts are derived from the arrays rather than written out, so the
    /// sentence can never name more instruments than were assessed.
    public var headline: String {
        guard !isEmpty else { return "Nothing has reported often enough to judge yet." }
        if silent.isEmpty {
            let n = reporting.count
            return "All \(n) " + SectionCaveat.plural(n, "instrument") + " reported."
        }
        if reporting.isEmpty {
            return "Nothing reported last night."
        }
        return "\(reporting.count) of \(instruments.count) instruments reported."
    }

    /// The caveat that stops a quiet night from reading as a clean bill.
    ///
    /// `nil` when everything reported, because a met requirement says nothing —
    /// the same rule `CoverageGate.sentence` follows, and for the same reason.
    public var caveat: String? {
        guard !silent.isEmpty, !isEmpty else { return nil }
        // Capped, because a night on which everything was quiet lists every
        // instrument the reader owns — measured at seven on a stale export, and
        // a paragraph of device names buries the sentence that matters. The
        // full list is a disclosure away.
        let list = ListPhrase.and(silent.map(\.displayName), limit: 3)
        return "\(list) reported nothing, so anything that depends on "
            + (silent.count == 1 ? "it" : "them")
            + " is not being scored rather than scoring clear."
    }
}

// MARK: - Building one

public extension InstrumentCoverage {

    /// How far back the coverage record looks. Ninety nights is a quarter — long
    /// enough that a fortnight's holiday does not dominate it, short enough that
    /// a ring bought last spring does not drag every figure down.
    static let defaultNightsAssessed = 90

    /// An instrument has to have been heard from on this many of the assessed
    /// nights before it is listed at all.
    ///
    /// Without a floor, one stray reading from a friend's scale becomes a
    /// permanent silent row accusing the reader of not using something they
    /// never owned. Three nights is the least that distinguishes an instrument
    /// from an accident.
    static let minimumNightsToBeKnown = 3

    /// Sources that are not instruments, whatever their origin says.
    ///
    /// `MetricSource.origin` catches typed values and documents, but a Shotsy
    /// backup and a Screen Time screenshot both classify as `directAPI` — they
    /// have their own source ids precisely so a per-source breakdown does not
    /// misdescribe how they arrived. Neither can be worn, so neither can be
    /// silent in the sense this card means.
    static let nonInstrumentSourceIDs: Set<String> = [
        MetricSource.calculated.id, MetricSource.shotsy.id,
        MetricSource.screenshot.id, MetricSource.document.id,
    ]

    /// Build the picture for the night that has just ended.
    ///
    /// ## The night window
    ///
    /// 18:00 the previous day to noon today, clipped at `now`. Wearables write
    /// a night's readings at wildly different times — a ring backfills at
    /// wake-up, a watch streams through the night, a scale reports at breakfast
    /// — and a window that stopped at midnight would call a ring silent every
    /// morning before it synced.
    ///
    /// ## Why night indices are arithmetic
    ///
    /// The coverage record needs to know which night each of up to a quarter of
    /// a million readings belongs to. Doing that with `Calendar` per sample is
    /// the shape of the render stalls this app has already paid for, so the
    /// index is `floor` division against the window's own start. The cost is
    /// that a daylight-saving change moves the boundary by an hour for one
    /// night — which can misfile a reading taken within an hour of 18:00, and
    /// cannot change whether an instrument was heard from at all unless it
    /// reported exactly once, in that hour, twice a year.
    static func night(samples: [HealthMetricSample], now: Date = Date(),
                      calendar: Calendar = .current,
                      nightsAssessed: Int = defaultNightsAssessed) -> InstrumentCoverage {
        let startOfToday = calendar.startOfDay(for: now)
        let nightStart = startOfToday.addingTimeInterval(-6 * 3_600)
        let nightEnd = Swift.min(now, startOfToday.addingTimeInterval(12 * 3_600))
        let window = DateInterval(start: nightStart,
                                  end: Swift.max(nightStart, nightEnd))

        var nightsSeen: [String: Set<Int>] = [:]
        var names: [String: String] = [:]
        var lastHeard: [String: Date] = [:]
        var windowCounts: [String: Int] = [:]
        var windowMetrics: [String: Set<MetricType>] = [:]

        for sample in samples {
            let source = sample.source
            // A figure this app worked out is not an instrument, and nothing the
            // reader handed over — a typed value, a PDF, a backup file, a
            // screenshot — can be "on the charger". Listing any of them would
            // turn a coverage report into a chore list, and the first build of
            // this card did exactly that: `shotsy` and `screenshot` sat in the
            // silent list on a simulator, accusing the reader of not importing a
            // file last night.
            guard !nonInstrumentSourceIDs.contains(source.id),
                  source.origin != .manual, source.origin != .document else { continue }

            let family = source.deviceFamily
            // The shortest display name wins, deterministically. One ring can
            // arrive as "Oura" and as "Oura via Apple Health", and last-write
            // ordering made the label depend on sample order.
            if let existing = names[family] {
                if source.displayName.count < existing.count { names[family] = source.displayName }
            } else {
                names[family] = source.displayName
            }
            if let seen = lastHeard[family] {
                if sample.start > seen { lastHeard[family] = sample.start }
            } else {
                lastHeard[family] = sample.start
            }

            let index = -Int(((sample.start.timeIntervalSince(nightStart)) / 86_400).rounded(.down))
            if index >= 0 && index < nightsAssessed {
                nightsSeen[family, default: []].insert(index)
            }
            if window.contains(sample.start) {
                windowCounts[family, default: 0] += 1
                windowMetrics[family, default: []].insert(sample.type)
            }
        }

        let reports = nightsSeen.compactMap { family, nights -> InstrumentReport? in
            guard nights.count >= minimumNightsToBeKnown else { return nil }
            return InstrumentReport(
                family: family,
                displayName: names[family] ?? family,
                samplesInWindow: windowCounts[family] ?? 0,
                metricsInWindow: (windowMetrics[family] ?? []).sorted { $0.rawValue < $1.rawValue },
                lastHeard: lastHeard[family],
                nightsCovered: nights.count,
                nightsAssessed: nightsAssessed)
        }

        let ordered = reports.sorted {
            if $0.reported != $1.reported { return $0.reported }
            if $0.nightsCovered != $1.nightsCovered { return $0.nightsCovered > $1.nightsCovered }
            return $0.displayName < $1.displayName
        }
        return InstrumentCoverage(window: window, instruments: ordered,
                                  nightsAssessed: nightsAssessed)
    }
}

/// Joining names into a sentence without a trailing comma or an "and" before a
/// single item. Small, but it is the difference between "Oura and Apple Watch
/// reported nothing" and "Oura, Apple Watch, reported nothing".
enum ListPhrase {

    /// `limit` caps how many are named before the rest become a count. The
    /// count is derived from the input, so the sentence cannot claim a size the
    /// list does not have — backlog D19's rule, one level down.
    static func and(_ items: [String], limit: Int? = nil) -> String {
        if let limit, items.count > limit, limit > 0 {
            let shown = items.prefix(limit).joined(separator: ", ")
            return "\(shown) and \(items.count - limit) more"
        }
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }
}
