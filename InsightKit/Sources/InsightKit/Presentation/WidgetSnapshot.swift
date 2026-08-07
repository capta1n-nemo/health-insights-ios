import Foundation

/// **What a home-screen widget is allowed to show, as a type.**
///
/// Backlog `D8`. A widget is the smallest surface this app has and the one the
/// reader sees most often — a glance, from across the room, with no tap and no
/// context. That combination makes it **the easiest place in the whole app to
/// dress modelled as measured**: there is no room for a caveat, so the caveat
/// gets dropped, and a 74 on a home screen looks exactly as solid as a
/// thermometer reading.
///
/// So the rule is not written in a comment for a future widget author to
/// remember. It is the shape of this type:
///
/// - A figure and its qualifier are **one value** (`Figure`), and the qualifier
///   is non-optional. There is no API here that hands out the number alone, so
///   a view cannot render a bare score by forgetting something.
/// - A card with no figure produces `.withheld`, carrying **the card's own
///   sentence** — the "Waiting for today's sync" / "Building baseline" copy the
///   model already wrote. The widget never invents its own empty-state wording
///   and never substitutes a dash, a zero or the last number it had.
/// - Nothing here is computed. Every string is copied from `InsightResult`,
///   which is the audited surface. A widget that re-derived a figure from
///   samples could disagree with the card it links to, and the reader would
///   have two different numbers for the same morning with no way to tell which
///   was wrong.
/// - `dataThrough` is the freshest reading actually behind the figure, and
///   `capturedAt` is when the app wrote this. **Both are needed**: WidgetKit
///   renders from a cached timeline entry at times of its own choosing, so a
///   widget can be on screen for hours after the app last ran. See
///   ``stalenessSentence(now:)`` — a widget showing yesterday's readiness with
///   no date on it is the specific dishonesty this field exists to stop.
///
/// ## What is deliberately *not* here
///
/// - **No trend arrow.** A direction with no stated comparison ("against what?
///   yesterday? your 7-day mean?") is the cheapest false precision available,
///   and the space to state it does not exist on a small widget.
/// - **No lock-screen or Live Activity variants**, for a privacy reason rather
///   than a technical one: accessory widgets render on a locked phone, which
///   shows this reader's health state to anyone who picks it up. That is a
///   decision for the reader to opt into, not a default. See `docs/widgets.md`.
/// - **No second card.** One card, one number, until there is a shipped widget
///   to learn from.
public struct WidgetSnapshot: Codable, Sendable, Equatable {

    /// Bumped whenever the stored shape changes.
    ///
    /// The app and the widget extension are two binaries that are **not**
    /// guaranteed to be the same build: iOS keeps running an old extension
    /// until it is next reloaded, and a reader can be mid-install. A decoded
    /// snapshot whose schema is not this one is discarded rather than
    /// best-effort mapped — a widget showing a field that meant something else
    /// two builds ago is exactly the failure this app cannot have.
    public static let schemaVersion = 1

    /// A number the reader may be shown, welded to the words that qualify it.
    public struct Figure: Codable, Sendable, Equatable {
        /// The card's own preformatted headline — "74", "Good", "5.2%".
        /// Copied, never re-formatted.
        public let headline: String
        /// The qualifier that must appear beside it. Never empty; see
        /// ``WidgetSnapshot/qualifier(for:)``.
        public let qualifier: String
        /// The 0–100 the card published, when it published one. Present for a
        /// dial or a bar; it is *inside* `Figure`, so reaching it means already
        /// holding `qualifier`.
        public let score: Double?
        /// One line of "what's driving this", where the card named a notable
        /// one. Never a second number.
        public let detail: String?

        public init(headline: String, qualifier: String,
                    score: Double? = nil, detail: String? = nil) {
            self.headline = headline
            // A qualifier is not optional. An empty one would be an optional
            // wearing a String's clothes, so it is repaired rather than
            // trusted — the one place this type can be wrong is a caller
            // passing "".
            self.qualifier = qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Estimated from your own readings" : qualifier
            self.score = score
            self.detail = detail
        }
    }

    /// Either a figure with its qualifier, or the card's own reason for having
    /// none. There is no third case, and in particular no "unknown".
    public enum Content: Codable, Sendable, Equatable {
        case figure(Figure)
        /// The card's own sentence — headline first, then the fuller line where
        /// one is short enough to be worth carrying.
        case withheld(headline: String, reason: String?)
    }

    public let schema: Int
    public let insight: InsightID
    /// The card's title, so the widget names what it is showing.
    public let title: String
    public let content: Content
    /// When the app wrote this snapshot.
    public let capturedAt: Date
    /// The freshest reading behind the figure, where the card named its inputs.
    /// `nil` when nothing measured is behind it — which is itself worth saying.
    public let dataThrough: Date?

    public init(insight: InsightID, title: String, content: Content,
                capturedAt: Date, dataThrough: Date?) {
        self.schema = Self.schemaVersion
        self.insight = insight
        self.title = title
        self.content = content
        self.capturedAt = capturedAt
        self.dataThrough = dataThrough
    }

    /// `true` when this snapshot was written by a build that agrees with this
    /// one about what the fields mean.
    public var isReadable: Bool { schema == Self.schemaVersion }
}

public extension WidgetSnapshot {

    /// Build one from a finished card. **The only supported route** — nothing
    /// else may construct the strings a widget shows.
    ///
    /// - Parameters:
    ///   - result: the card, exactly as the Insights tab has it.
    ///   - dataThrough: the freshest reading behind it. The caller resolves
    ///     this because `InsightResult` names its contributing metrics but not
    ///     their timestamps, and guessing "now" here would be the lie.
    static func from(_ result: InsightResult,
                     capturedAt: Date,
                     dataThrough: Date?) -> WidgetSnapshot {
        // A card with no primary figure is withholding one, and the reason is
        // already written in `headline` — "Waiting for today's sync",
        // "Building baseline", "Connect a wearable". The widget repeats it.
        //
        // ⚠️ `primaryValue` rather than `score`: several cards publish a score
        // for the dial and no headline number, and a couple do the reverse. The
        // question here is only "did this card put a figure in front of the
        // reader", and `primaryValue == nil` is how the app has always asked it
        // (see `InsightResult.isWorthShowing`'s history).
        guard result.primaryValue != nil || result.score != nil else {
            return WidgetSnapshot(
                insight: result.id, title: result.title,
                content: .withheld(headline: result.headline,
                                   reason: shortReason(from: result.explanation)),
                capturedAt: capturedAt, dataThrough: dataThrough)
        }
        let figure = Figure(headline: result.headline,
                            qualifier: qualifier(for: result),
                            score: result.score,
                            detail: notableDriver(in: result))
        return WidgetSnapshot(insight: result.id, title: result.title,
                              content: .figure(figure),
                              capturedAt: capturedAt, dataThrough: dataThrough)
    }

    /// The words that travel with the number, wherever it is shown.
    ///
    /// Same vocabulary as `ConfidenceBadge` on the cards — "Validated",
    /// "Estimate", "Needs data", "Experimental" — because a reader who has seen
    /// the badge in the app should not have to learn a second dialect on their
    /// home screen. Expanded into a phrase rather than a bare word: a pill has
    /// a card around it to give it context, and a widget has nothing.
    static func qualifier(for result: InsightResult) -> String {
        switch result.confidence {
        case .high: return "From your own readings"
        case .moderate: return "Estimate — some inputs missing"
        case .low: return "Rough — thin data behind it"
        case .experimental: return "Experimental — not a measurement"
        }
    }

    /// The one driver line worth a widget's second row, or none.
    ///
    /// Notable first, because that ordering is load-bearing on the Today card
    /// too. A card that draws no notable/routine distinction contributes
    /// nothing here rather than its first line: an unclassified list shown one
    /// item at a time is the "sixteen normals hide the one that isn't" failure
    /// `InsightDriver.isNotable` was added to stop.
    static func notableDriver(in result: InsightResult) -> String? {
        result.driverLines.first { $0.isNotable == true }?.text
    }

    /// A card's explanation, trimmed to something a widget can hold — or `nil`
    /// rather than a truncation.
    ///
    /// **Never an ellipsis.** A half-sentence about health data is worse than
    /// no sentence: the reader completes it themselves, and this app does not
    /// get to choose which half they keep.
    static func shortReason(from explanation: String, limit: Int = 90) -> String? {
        let firstSentence = explanation
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) + "." }
        guard let firstSentence, !firstSentence.isEmpty, firstSentence.count <= limit else {
            return nil
        }
        return firstSentence
    }
}

public extension WidgetSnapshot {

    /// How old the *data* is, in words, once that is worth saying — `nil` while
    /// it is current.
    ///
    /// ⚠️ **This is about `dataThrough`, not `capturedAt`.** The reader does not
    /// care when the app last ran; they care whether the number in front of
    /// them is about today. A widget rendered from a cached timeline entry at
    /// 6pm, built from a reading taken at 7am, is honest — that *is* this
    /// morning's readiness. The same widget still on screen tomorrow lunchtime
    /// is not, and this is the sentence that says so.
    ///
    /// The threshold is a calendar day rather than a rolling 24 hours because
    /// every card this can show is a claim about *today*: "yesterday" is the
    /// word that makes the staleness legible, and 23 hours can straddle it.
    func stalenessSentence(now: Date, calendar: Calendar = .current) -> String? {
        guard let dataThrough else { return "No reading behind this yet" }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: dataThrough),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return nil
        case 1: return "From yesterday"
        default: return "From \(days) days ago"
        }
    }

    /// Everything a view must render, resolved once, so two widget families
    /// cannot disagree about what the honest lines are.
    ///
    /// Order is deliberate: the qualifier is never below the fold of a small
    /// widget, and staleness outranks the driver line — if the number is not
    /// about today, *that* is the thing to say in the one spare row.
    func supportingLines(now: Date) -> [String] {
        var lines: [String] = []
        switch content {
        case .figure(let figure):
            lines.append(figure.qualifier)
            if let stale = stalenessSentence(now: now) { lines.append(stale) }
            else if let detail = figure.detail { lines.append(detail) }
        case .withheld(_, let reason):
            if let reason { lines.append(reason) }
        }
        return lines
    }
}
