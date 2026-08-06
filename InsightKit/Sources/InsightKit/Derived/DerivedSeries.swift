import Foundation

/// **A figure this app worked out, kept as a series in its own right.**
///
/// The reader's instruction, 2026-08-06: *"for any insight we derive, it is
/// turned into a data source, so it can then in itself be used as a data source
/// for the same card.. or other cards.. and it has its own data source tracking
/// in the data tab. For example: there are lots of insights derived in the
/// 'What's driving this' sections, I want those converted to data sources, so
/// they can then be used in weightings and other parts of the app, and also
/// tracked/trended."*
///
/// ## What was wrong, stated precisely
///
/// `MetricContribution.metric` is a `MetricType`, so **only a measured series
/// can be weighted, charted, baselined, exported or shown in the Data tab.**
/// Everything the app computes — a fitness age, an observed TDEE, the radar's
/// accumulated statistic, this week's moderate-equivalent minutes, and the
/// per-component 0–100 behind every row of "What's driving this" — lived inside
/// a single evaluation and was discarded the moment the card was drawn. The app
/// was recomputing the same figures every launch and remembering none of them.
///
/// ## Why this is not a `MetricType`
///
/// `activeMedicationLevel` is the precedent for a modelled quantity being a
/// first-class metric, and it works — but each `MetricType` case feeds eight
/// exhaustive switches, and the component sub-scores alone are roughly ninety
/// series (card × metric). Ninety cases would be seven hundred switch arms, and
/// would flood every overlay, every Vitals scan and the metric picker with
/// quantities that are *about* the app rather than about the reader's body.
///
/// So derived series are their own vocabulary, deliberately kept out of
/// `MetricType`, with their own Data-tab home. What they gain instead is that
/// **they cost nothing to declare**: the component tier is harvested from
/// `MetricContribution`, which every scoring model already emits.
///
/// ## The three tiers
///
/// | Kind | Where it comes from | Roughly |
/// | --- | --- | --- |
/// | `.modelOutput` | a model naming it in `InsightResult.derivedOutputs` | 1–3 per card |
/// | `.componentScore` | `MetricContribution.componentScore` — free | one per weighted row |
/// | `.componentDeparture` | `MetricContribution.z` — free | one per judged row |
///
/// ⚠️ **Nothing here may be dressed as measured.** These are `.calculated` in
/// every sense the app already means it: no reference range, no peer norm, and
/// the Data tab files them under their own section rather than beside readings.
public struct DerivedSeriesID: Hashable, Sendable, Codable, RawRepresentable,
                               Comparable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Namespaced by the card that produces it, so two cards deriving "age" do
    /// not collide and a reader can see which card owns a figure.
    public init(_ insight: InsightID, _ key: String) {
        self.rawValue = "\(insight.rawValue).\(key)"
    }

    /// The producing card, read back off the id. `nil` for an id that did not
    /// come from this app's own namespacing — which should not happen, and
    /// returning nil rather than crashing is the honest handling of a stored
    /// id from an older build.
    public var producedBy: InsightID? {
        rawValue.split(separator: ".").first
            .flatMap { InsightID(rawValue: String($0)) }
    }
}

public enum DerivedSeriesKind: String, Sendable, Codable, CaseIterable {
    /// A figure the model names for itself — a fitness age, a weekly dose.
    case modelOutput
    /// One contributor's own 0–100, before its weight was applied.
    case componentScore
    /// One contributor's departure from the reader's own baseline, in SD,
    /// signed as the metric is measured rather than as "good" or "bad".
    case componentDeparture
}

/// What a derived series *is* — enough for a chart, a row and a legend without
/// re-deriving anything, which is the same contract `MetricContribution` holds
/// itself to.
public struct DerivedSeriesSpec: Sendable, Hashable, Identifiable {
    public let id: DerivedSeriesID
    public let displayName: String
    /// Empty where the value carries its own, exactly as `MetricType.unit` does.
    public let unit: String
    public let producedBy: InsightID
    public let kind: DerivedSeriesKind
    /// `nil` where neither direction is the good one — a departure is signed as
    /// measured, and a temperature deviation is best near zero.
    public let higherIsBetter: Bool?
    public let precision: Int

    public init(id: DerivedSeriesID, displayName: String, unit: String,
                producedBy: InsightID, kind: DerivedSeriesKind,
                higherIsBetter: Bool? = nil, precision: Int = 1) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
        self.producedBy = producedBy
        self.kind = kind
        self.higherIsBetter = higherIsBetter
        self.precision = precision
    }

    public func string(_ value: Double) -> String {
        let text = String(format: "%.\(precision)f", value)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }
}

/// One day's value of one derived series.
public struct DerivedPoint: Sendable, Hashable, Codable, Identifiable {
    public let series: DerivedSeriesID
    /// Start of the day this value belongs to, in the reader's calendar.
    public let day: Date
    public let value: Double

    public var id: String { "\(series.rawValue)@\(day.timeIntervalSince1970)" }

    public init(series: DerivedSeriesID, day: Date, value: Double) {
        self.series = series
        self.day = day
        self.value = value
    }
}

/// A figure a model names as worth keeping.
///
/// Declared on the result rather than registered in a central table, for the
/// reason `MetricContribution` is: *the scoring code emits it at the point the
/// figure is computed*, so a model that stops producing a figure stops
/// producing the series, with no second edit anywhere to forget.
public struct DerivedOutput: Sendable, Hashable {
    /// Stable and unique within the producing card. Changing one renames the
    /// series and orphans its history, so treat it like a `modelVersion`.
    public let key: String
    public let displayName: String
    public let unit: String
    public let value: Double
    public let higherIsBetter: Bool?
    public let precision: Int

    public init(key: String, displayName: String, unit: String = "",
                value: Double, higherIsBetter: Bool? = nil, precision: Int = 1) {
        self.key = key
        self.displayName = displayName
        self.unit = unit
        self.value = value
        self.higherIsBetter = higherIsBetter
        self.precision = precision
    }
}

/// Turns a finished `InsightResult` into the derived series it implies.
///
/// **The component tiers cost the models nothing**, which is the whole reason
/// the reader's "do the sub-scores too" is affordable: `componentScore` and `z`
/// have been on `MetricContribution` since the score-decomposition work, on
/// every model that fills them in, and this simply stops throwing them away.
public enum DerivedHarvest {

    /// Suffixes, in one place, because they are baked into stored ids.
    public static let scoreSuffix = "score"
    public static let departureSuffix = "departure"

    public static func componentScoreID(_ insight: InsightID, _ metric: MetricType) -> DerivedSeriesID {
        DerivedSeriesID(insight, "\(metric.rawValue).\(scoreSuffix)")
    }

    public static func componentDepartureID(_ insight: InsightID, _ metric: MetricType) -> DerivedSeriesID {
        DerivedSeriesID(insight, "\(metric.rawValue).\(departureSuffix)")
    }

    /// Every series this result carries, with its spec and today's value.
    ///
    /// ⚠️ **A contributor at weight 0 still yields its series.** The card
    /// charts it and narrates it without averaging it in, so its sub-score is a
    /// real statement about the reader that simply carries no share — and
    /// dropping it here would make the Data tab disagree with the card above it.
    public static func series(from result: InsightResult) -> [(DerivedSeriesSpec, Double)] {
        var out: [(DerivedSeriesSpec, Double)] = []

        for output in result.derivedOutputs {
            out.append((
                DerivedSeriesSpec(id: DerivedSeriesID(result.id, output.key),
                                  displayName: output.displayName,
                                  unit: output.unit,
                                  producedBy: result.id, kind: .modelOutput,
                                  higherIsBetter: output.higherIsBetter,
                                  precision: output.precision),
                output.value))
        }

        for contribution in result.contributors {
            let metric = contribution.metric
            if let score = contribution.componentScore {
                out.append((
                    DerivedSeriesSpec(id: componentScoreID(result.id, metric),
                                      displayName: "\(metric.displayName) — its own score",
                                      unit: "", producedBy: result.id,
                                      kind: .componentScore,
                                      // A component score is already oriented:
                                      // 100 is good whatever the metric does.
                                      higherIsBetter: true, precision: 0),
                    score))
            }
            if let z = contribution.z {
                out.append((
                    DerivedSeriesSpec(id: componentDepartureID(result.id, metric),
                                      displayName: "\(metric.displayName) — from your normal",
                                      unit: "SD", producedBy: result.id,
                                      kind: .componentDeparture,
                                      // Signed as the metric is measured, so
                                      // neither direction is "the good one"
                                      // without knowing which metric it is.
                                      higherIsBetter: nil, precision: 2),
                    z))
            }
        }
        return out
    }
}
