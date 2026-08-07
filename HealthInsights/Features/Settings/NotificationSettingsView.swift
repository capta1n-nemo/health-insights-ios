import SwiftUI
import UserNotifications
import InsightKit

/// What the app may interrupt the reader for.
///
/// ⚠️ **The permission prompt lives here and nowhere else.** iOS gives an app a
/// single chance to ask, and asking on first launch — before a single card has
/// been seen — is the cheapest way to earn a permanent no. This screen lists
/// every kind, in the app's own words, *before* the ask; the reader is deciding
/// with the list in front of them rather than from a one-line system alert.
///
/// The screen deliberately shows every kind even while permission is off, and
/// even while a kind is switched off. Same reasoning as the cards rule of
/// 2026-08-07 — nothing is hidden for want of a precondition; the empty state
/// says what it is waiting for.
struct NotificationSettingsView: View {

    @State private var centre = NotificationCentre.shared
    @State private var coordinator = NotificationCoordinator.shared

    private var isAuthorised: Bool {
        centre.authorization == .authorized || centre.authorization == .provisional
    }

    var body: some View {
        List {
            permissionSection
            kindsSection
            quietHoursSection
            capSection
            backgroundSection
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await centre.refreshAuthorization() }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            switch centre.authorization {
            case .notDetermined:
                Button("Allow notifications") {
                    Task { await centre.requestAuthorization() }
                }
            case .denied:
                Label("Turned off in iOS Settings", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
                Link("Open iOS Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            default:
                Label("Allowed", systemImage: "bell.badge")
                    .foregroundStyle(Theme.good)
            }
        } footer: {
            switch centre.authorization {
            case .notDetermined:
                Text("Nothing has been asked for yet. The list below is everything this app would ever send — read it first, then decide.")
            case .denied:
                // Honest about what the app cannot do about it: once denied,
                // only iOS Settings can reverse it.
                Text("iOS will not let the app ask again. The switches below still work and are remembered, but nothing can be delivered until notifications are turned back on for Health Insights in iOS Settings.")
            default:
                Text("Everything below is on top of that. Turning a kind off here stops it being sent without touching the permission.")
            }
        }
    }

    // MARK: - What gets sent

    private var kindsSection: some View {
        Section("What to send") {
            ForEach(HealthNotificationKind.allCases, id: \.self) { kind in
                Toggle(isOn: binding(kind)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.displayName)
                        Text(kind.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func binding(_ kind: HealthNotificationKind) -> Binding<Bool> {
        Binding(get: { coordinator.policy.enabledKinds.contains(kind) },
                set: { coordinator.setKind(kind, enabled: $0) })
    }

    // MARK: - Quiet hours

    private var quietHoursSection: some View {
        Section {
            Picker("From", selection: Binding(
                get: { coordinator.policy.quietHoursStart },
                set: { var p = coordinator.policy; p.quietHoursStart = $0; coordinator.setPolicy(p) })) {
                    ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
            Picker("Until", selection: Binding(
                get: { coordinator.policy.quietHoursEnd },
                set: { var p = coordinator.policy; p.quietHoursEnd = $0; coordinator.setPolicy(p) })) {
                    ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
                }
        } header: {
            Text("Quiet hours")
        } footer: {
            // The distinction that makes the background half worth having, said
            // to the reader rather than only in the code.
            Text("Nothing is sent between these hours — but nothing is thrown away either. A finding made at three in the morning is held and delivered when quiet hours end. Set both to the same hour for no quiet hours at all.")
        }
    }

    // MARK: - The cap

    private var capSection: some View {
        Section {
            Stepper(value: Binding(
                get: { coordinator.policy.dailyCap },
                set: { var p = coordinator.policy; p.dailyCap = $0; coordinator.setPolicy(p) }),
                    in: 0...10) {
                LabeledContent("Most in one day",
                               value: coordinator.policy.dailyCap == 0
                                   ? "None" : "\(coordinator.policy.dailyCap)")
            }
        } footer: {
            Text("A ceiling for the worst day rather than a target. The same finding is never sent twice, so reaching this means that many genuinely different things happened — and when it bites, what gets through is whatever is most about your body rather than whatever happened to be found first. Set it to none to stop everything without unticking each row.")
        }
    }

    // MARK: - The background half

    private var backgroundSection: some View {
        Section {
            LabeledContent("Checks for you", value: "About every \(Int(BackgroundRefresh.earliestInterval / 3600)) hours")
        } header: {
            Text("In the background")
        } footer: {
            // ⚠️ Honest about what the app does not control. iOS decides when —
            // and frequently decides "not yet" — and promising a schedule the
            // app cannot keep is exactly the kind of confident wrongness this
            // repo has been bitten by elsewhere.
            Text("The app asks iOS to wake it about this often so a change can be found while you are not looking. iOS decides the actual moment, weighing battery and how often you open the app, and it may be much longer. If Background App Refresh is off for Health Insights in iOS Settings, nothing is found until you next open it.")
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
