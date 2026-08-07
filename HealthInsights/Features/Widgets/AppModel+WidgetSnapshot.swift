import Foundation
import InsightKit

/// **Publishing the daily number for a home-screen widget.** Backlog `D8`.
///
/// One card, one file, written after every evaluation. Deliberately an
/// extension in its own file rather than a method on `AppModel`: the call site
/// in `applyRecomputed` is a single line, and everything this needs to decide
/// belongs next to the widget it feeds.
///
/// ⚠️ **This runs today, and today no widget can read it.** The App Group does
/// not exist (`WidgetSnapshotStore.isVisibleToWidgets` is `false` on every build
/// shipped so far), so the file lands in the app's own container instead. That
/// is not busywork: the in-app preview reads exactly this file, so the pipeline
/// the extension will use is the pipeline the reader can already see working,
/// rather than one that gets written for the first time on the day the
/// entitlement lands.
@MainActor
extension AppModel {

    /// Which card the widget shows.
    ///
    /// **Readiness, and it is not a close call.** It is the app's daily number:
    /// `InsightCadence.daily`, scored against the reader's own baseline, and the
    /// one figure whose whole value is being seen first thing without opening
    /// anything. Energy changes hour to hour (a widget refreshed on WidgetKit's
    /// schedule would routinely be wrong), and the trend cards answer questions
    /// nobody asks from a home screen.
    static let widgetInsight: InsightID = .readiness

    /// Write the snapshot, if it has changed.
    ///
    /// Called from `applyRecomputed`. Cheap — a few hundred bytes — but it is on
    /// the main actor at the end of every evaluation, and every evaluation is on
    /// a path the reader is watching, so an unchanged result writes nothing.
    func publishWidgetSnapshot(from evaluated: [InsightResult]) {
        guard let result = evaluated.first(where: { $0.id == Self.widgetInsight }) else { return }
        let dataThrough = freshestReading(behind: result)
        // ⚠️ Compared on what a reader would *see*, not on the whole value:
        // `capturedAt` moves on every evaluation, so full equality would never
        // match and this guard would never fire.
        let identity = WidgetPublishState.Identity(result: result, dataThrough: dataThrough)
        guard identity != WidgetPublishState.last else { return }
        WidgetPublishState.last = identity
        let snapshot = WidgetSnapshot.from(result, capturedAt: Date(), dataThrough: dataThrough)
        try? WidgetSnapshotStore.resolve()?.write(snapshot)
    }

    /// What the in-app preview shows: the snapshot as it was actually stored,
    /// not a fresh one built for the screen.
    ///
    /// The difference matters. A preview built in the view would render
    /// correctly while the store was broken, which makes it useless as evidence
    /// that a widget would show the same thing.
    func storedWidgetSnapshot() -> WidgetSnapshot? {
        WidgetSnapshotStore.resolve()?.read()
    }

    /// The freshest reading behind the card, from the metrics it named itself.
    ///
    /// ⚠️ **Never `Date()`.** The snapshot's staleness sentence is built from
    /// this, so passing "now" here would make every widget claim to be current
    /// — which is the exact dishonesty the field exists to prevent. `nil` when
    /// the card named no metric-backed contributor, which the snapshot renders
    /// as "No reading behind this yet" rather than as silence.
    private func freshestReading(behind result: InsightResult) -> Date? {
        let metrics = Set(result.contributors.map(\.metric))
        guard !metrics.isEmpty else { return nil }
        return samples.filter { metrics.contains($0.type) }.map(\.start).max()
    }
}

/// What was last written, so an evaluation that changed nothing writes nothing.
///
/// A file-scoped box rather than a stored property on `AppModel`: extensions
/// cannot add stored properties, and `AppModel` is a 3,000-line file that ten
/// concurrent worktrees are editing — a one-line call site there is a far
/// cheaper edit than a new field.
private enum WidgetPublishState {

    /// The parts of a snapshot a reader could tell apart.
    struct Identity: Equatable {
        let id: InsightID
        let headline: String
        let score: Double?
        let confidence: InsightConfidence
        let dataThrough: Date?

        init(result: InsightResult, dataThrough: Date?) {
            self.id = result.id
            self.headline = result.headline
            self.score = result.score
            self.confidence = result.confidence
            self.dataThrough = dataThrough
        }
    }

    @MainActor static var last: Identity?
}
