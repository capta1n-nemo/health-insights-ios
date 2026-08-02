import AppIntents
import Foundation
import InsightKit

/// Native Shortcuts actions, so the reader picks a metric from a menu instead of
/// hand-editing a URL.
///
/// **Why this exists on top of the URL transport.** `ShortcutIngest` is the
/// mechanism and it works, but the gesture it asks for is bad: open a text
/// field, paste `healthinsights://shortcut?date=YYYY-MM-DD&screenTimeMinutes=VALUE`,
/// then find `VALUE` and replace it with a variable from the action above. Every
/// part of that is a chance to get it wrong silently — which is why the ingest
/// reports `unknownKeys` at all.
///
/// An `AppIntent` removes the string. Shortcuts shows "Log health data" with a
/// metric picker and a number field, and wires the variable in the way it wires
/// every other action's. The URL entry point stays, because a shortcut someone
/// has already built must keep working, and because a URL is the only thing some
/// automations (a web hook, another app's "Open URL") can produce.
///
/// **Both doors lead to the same room.** The intent builds a URL with
/// `ShortcutIngest.url(for:on:)` and hands it to the very same
/// `AppModel.ingestShortcut` the URL scheme uses, so the plausibility guard, the
/// per-day upsert and the "last run" stamp are one implementation with one set
/// of tests, rather than two that agree until they don't.
@available(iOS 18.0, *)
struct LogHealthDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Log health data"
    static let description = IntentDescription(
        "Send a reading to Health Insights — screen time, a weight, anything the app tracks.",
        categoryName: "Data")

    /// Runs without bringing the app forward. The whole point is a scheduled
    /// automation that collects overnight; opening the app every morning to
    /// record a number would be worse than not having it.
    static let openAppWhenRun = false

    @Parameter(title: "Metric")
    var metric: MetricTypeEntity

    @Parameter(title: "Value")
    var value: Double

    /// Optional, and it means *today* when absent — the same default the URL
    /// transport takes, and the right one for an automation that runs each
    /// morning about the night before.
    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$value) as \(\.$metric) on \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let type = MetricType(rawValue: metric.id) else {
            throw $metric.needsValueError("Which reading is this?")
        }
        let day = date ?? Date()
        guard let url = ShortcutIngest.url(for: [type: value], on: day) else {
            throw $value.needsValueError("That value could not be recorded.")
        }
        // Deliberately the same call the URL scheme makes. See the type comment.
        guard let summary = AppModel.shared.ingestShortcut(url) else {
            throw $value.needsValueError("That value could not be recorded.")
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

/// The metric picker Shortcuts shows.
///
/// An `AppEntity` rather than an `AppEnum` because there are over a hundred
/// metrics and the list grows: an `AppEnum` bakes its cases into the app's
/// intent metadata and wants a display name per case written out, whereas a
/// queryable entity is generated from `MetricType.allCases` and a new metric
/// appears in Shortcuts the day it is added, with nothing here to update. That
/// is the same "a new connector populates everywhere by construction" rule the
/// rest of the app is built on.
@available(iOS 18.0, *)
struct MetricTypeEntity: AppEntity, Identifiable {
    /// The `MetricType` raw value — stable across releases, which matters
    /// because Shortcuts stores this in the reader's saved shortcut.
    let id: String
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Health metric")
    static let defaultQuery = MetricTypeQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ metric: MetricType) {
        self.id = metric.rawValue
        self.name = metric.displayName
    }
}

@available(iOS 18.0, *)
struct MetricTypeQuery: EntityStringQuery {
    private var all: [MetricTypeEntity] {
        MetricType.allCases.map(MetricTypeEntity.init).sorted { $0.name < $1.name }
    }

    func entities(for identifiers: [String]) async throws -> [MetricTypeEntity] {
        identifiers.compactMap { MetricType(rawValue: $0).map(MetricTypeEntity.init) }
    }

    /// What the reader typed in the picker's search field. Matched against the
    /// display name rather than the raw value, because the raw value is a
    /// camel-cased identifier nobody should have to know.
    func entities(matching string: String) async throws -> [MetricTypeEntity] {
        all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [MetricTypeEntity] { all }
}

/// The actions Shortcuts offers without the reader going looking, and the
/// phrases Siri accepts.
@available(iOS 18.0, *)
struct HealthInsightsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogHealthDataIntent(),
            phrases: [
                "Log health data in \(.applicationName)",
                "Add a reading to \(.applicationName)"
            ],
            shortTitle: "Log health data",
            systemImageName: "square.and.pencil")
    }
}
