import Foundation

/// **The safeguards for letting anything read anything.**
///
/// The reader's decision, 2026-08-06: derived series may feed scores with full
/// flexibility — any card may read any series, including its own — *"but lets
/// do some research to make it safe, avoid drift and avoid loops. Maybe we need
/// some safeguards, tests, and some reporting built in from day zero."*
///
/// The research, in short: a feedback loop is not dangerous because it is a
/// loop; it is dangerous when it is **undefined** (a value depending on itself
/// on the same day, so the answer depends on evaluation order) or when its
/// **gain exceeds one** (each pass around the loop amplifies the last, so the
/// score drifts away from the data that feeds it). Control theory has one
/// answer for the first — insert a delay — and one for the second — measure the
/// loop gain and require it below unity. Both are implemented here, one
/// structurally and one as an audit.
///
/// ## Safeguard 1 — every edge is lagged, by construction
///
/// **A consumer reads the store as it stood *yesterday*** — `upTo(day:)`
/// excludes the evaluation day and everything after. This is structural, not a
/// convention: the engine hands models a snapshot that cannot contain today,
/// so a same-day self-read is impossible to write rather than forbidden in
/// prose. Every cycle therefore has lag ≥ 1 day and a defined evaluation
/// order, whatever the graph looks like. (It also kills a subtler bug: two
/// cards reading each other same-day would give different answers depending on
/// which evaluated first.)
///
/// ## Safeguard 2 — every edge is declared
///
/// A model states what it reads in `derivedInputs`, and the snapshot it is
/// handed is **filtered to that declaration** — an undeclared read comes back
/// empty rather than working silently. The declaration is what makes the graph
/// below computable at all, which is what makes loops *visible*.
///
/// ## Safeguard 3 — the loop gain is measured, not assumed
///
/// `DerivedFeedbackAudit` runs the whole system to a fixed point: replay with
/// no derived inputs (order 0), then replay again letting models read order 0's
/// store (order 1), and again (order 2). If the system is contractive — loop
/// gain below one — successive orders converge and the audit reports the
/// residual shrinking. If a loop amplifies, order 2 diverges further from
/// order 1 than order 1 did from order 0, and the audit names the series doing
/// it. **This is the drift report the reader asked for, and it runs in a test
/// from day zero**, so a diverging loop fails CI before it ships.
public enum DerivedDependencies {

    /// One declared read: `consumer` reads `series`, which `producer` writes.
    public struct Edge: Sendable, Hashable {
        public let consumer: InsightID
        public let series: DerivedSeriesID
        public let producer: InsightID

        public init(consumer: InsightID, series: DerivedSeriesID, producer: InsightID) {
            self.consumer = consumer
            self.series = series
            self.producer = producer
        }
    }

    /// A cycle of cards, each reading a series the next produces. Reported,
    /// never forbidden: every edge carries a day's lag by construction, so a
    /// cycle is a defined difference equation — but it is also the shape that
    /// can drift, so every one must be visible and audited.
    public struct Cycle: Sendable, Hashable {
        /// The cards, in reading order, starting from the lexicographically
        /// smallest so the same cycle always reports identically.
        public let cards: [InsightID]

        public var description: String {
            (cards + [cards[0]]).map(\.rawValue).joined(separator: " → ")
        }
    }

    public static func edges(of models: [any InsightModel]) -> [Edge] {
        models.flatMap { model in
            model.derivedInputs.compactMap { series in
                series.producedBy.map {
                    Edge(consumer: model.id, series: series, producer: $0)
                }
            }
        }
    }

    /// A declared input whose id names no registered producer — a typo, or a
    /// card that has been removed. Not a cycle, but the same family of silent
    /// wrongness: the read would simply always be empty.
    public static func unproducedInputs(of models: [any InsightModel]) -> [DerivedSeriesID] {
        let registered = Set(models.map(\.id))
        return models.flatMap(\.derivedInputs)
            .filter { id in id.producedBy.map { !registered.contains($0) } ?? true }
            .sorted()
    }

    /// Every simple cycle in the card graph, self-loops included.
    public static func cycles(in models: [any InsightModel]) -> [Cycle] {
        let graph = Dictionary(grouping: edges(of: models), by: \.consumer)
            .mapValues { Set($0.map(\.producer)) }

        var found: Set<[InsightID]> = []
        var stack: [InsightID] = []
        var onStack: Set<InsightID> = []

        func walk(_ node: InsightID) {
            if let at = stack.firstIndex(of: node) {
                let cycle = Array(stack[at...])
                // Rotate to the smallest member so one cycle has one spelling.
                if let pivot = cycle.enumerated().min(by: { $0.element.rawValue < $1.element.rawValue })?.offset {
                    found.insert(Array(cycle[pivot...] + cycle[..<pivot]))
                }
                return
            }
            guard !onStack.contains(node) else { return }
            stack.append(node)
            onStack.insert(node)
            for next in (graph[node] ?? []).sorted(by: { $0.rawValue < $1.rawValue }) {
                walk(next)
            }
            stack.removeLast()
            onStack.remove(node)
        }

        for node in graph.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            walk(node)
        }
        return found.map(Cycle.init(cards:))
            .sorted { $0.description < $1.description }
    }

    /// The standing report: every edge, every cycle, every unproduced input.
    ///
    /// Human-readable on purpose — this is what a session (or the reader) looks
    /// at to see what feeds what, and it is regenerated from the models rather
    /// than maintained by hand, so it cannot go stale.
    public static func report(models: [any InsightModel]) -> String {
        let edgeList = edges(of: models)
        let cycleList = cycles(in: models)
        let orphans = unproducedInputs(of: models)

        var lines = ["Derived-series dependency report"]
        if edgeList.isEmpty {
            lines.append("No card reads a derived series yet.")
        }
        for edge in edgeList.sorted(by: { $0.series < $1.series }) {
            lines.append("\(edge.consumer.rawValue) ← \(edge.series.rawValue) (produced by \(edge.producer.rawValue), lagged 1 day by construction)")
        }
        for cycle in cycleList {
            lines.append("⚠️ feedback loop: \(cycle.description) — defined (every edge lagged), audited by DerivedFeedbackAudit")
        }
        for orphan in orphans {
            lines.append("✗ declared input with no registered producer: \(orphan.rawValue)")
        }
        return lines.joined(separator: "\n")
    }
}

/// **The drift audit: run the system to a fixed point and watch whether it
/// settles.**
///
/// Order 0 replays every model with no derived inputs. Order n+1 replays
/// letting every model read order n's store (still lagged a day, exactly as at
/// runtime). If every loop's gain is below one the orders converge — the
/// residual between successive orders shrinks — and in the common case of a
/// card reading only *other* cards' outputs with no cycle at all, order 1 is
/// already exact and the residual is zero.
///
/// A residual that **grows** between successive orders is a loop amplifying
/// its own output: the score has begun to feed on itself faster than the data
/// can correct it. That is the drift the reader asked to be protected from,
/// and `DerivedSafetyTests` fails on it for every registered model, so it is
/// caught the day it is wired rather than the month it has drifted.
public enum DerivedFeedbackAudit {

    public struct SeriesDrift: Sendable {
        public let series: DerivedSeriesID
        /// Mean |order 1 − order 0| across shared days.
        public let firstResidual: Double
        /// Mean |order 2 − order 1| across shared days.
        public let secondResidual: Double
        /// A loop is contractive where the second pass moved less than the
        /// first. Equality is allowed for zero: an acyclic read is exact after
        /// one pass and both residuals are 0.
        public var isContractive: Bool { secondResidual <= firstResidual || secondResidual < 1e-9 }
    }

    public struct Report: Sendable {
        public let drifts: [SeriesDrift]
        public var diverging: [SeriesDrift] { drifts.filter { !$0.isContractive } }
        public var isStable: Bool { diverging.isEmpty }
    }

    /// `evaluate` must produce a fresh store for the given input store — at
    /// runtime that is a backfill with models bound to `input`; in tests it can
    /// be anything. Three passes, compared pairwise.
    public static func audit(
        evaluate: (_ input: DerivedSeriesStore) -> DerivedSeriesStore
    ) -> Report {
        let order0 = evaluate(DerivedSeriesStore())
        let order1 = evaluate(order0)
        let order2 = evaluate(order1)

        var drifts: [SeriesDrift] = []
        for id in Set(order1.seriesIDs).union(order2.seriesIDs).sorted() {
            let first = residual(order0.series(id), order1.series(id))
            let second = residual(order1.series(id), order2.series(id))
            // A series identical across all three orders is not in any loop —
            // reporting it would bury the ones that are.
            guard first > 1e-9 || second > 1e-9 else { continue }
            drifts.append(SeriesDrift(series: id, firstResidual: first,
                                      secondResidual: second))
        }
        return Report(drifts: drifts)
    }

    /// Mean absolute difference across the days both runs produced.
    static func residual(_ a: [DerivedPoint], _ b: [DerivedPoint]) -> Double {
        let byDay = Dictionary(a.map { ($0.day, $0.value) }, uniquingKeysWith: { x, _ in x })
        let shared = b.compactMap { point in
            byDay[point.day].map { abs(point.value - $0) }
        }
        guard !shared.isEmpty else { return 0 }
        return shared.reduce(0, +) / Double(shared.count)
    }
}
