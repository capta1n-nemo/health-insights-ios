import SwiftUI
import InsightKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    // Bumped after connect/disconnect to re-read integration status.
    @State private var refreshToken = 0

    var body: some View {
        NavigationStack {
            List {
                integrationsSection
                inputSection
                intelligenceSection
                exportSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    private var integrationsSection: some View {
        Section {
            ForEach(model.registry.integrations, id: \.id) { integration in
                if let oauth = integration as? OAuthIntegration {
                    NavigationLink {
                        ProviderSetupView(provider: oauth)
                    } label: {
                        IntegrationSummaryRow(integration: integration, status: model.status(for: integration))
                    }
                // File-based: there is nothing to authorise, so it gets an
                // explainer rather than a Connect button — pressing Connect on
                // a source that only ever receives files would do nothing.
                } else if integration is ShotsyIntegration {
                    NavigationLink {
                        ShotsyIntegrationView()
                    } label: {
                        IntegrationSummaryRow(integration: integration,
                                              status: model.status(for: integration))
                    }
                // Same shape again: nothing to authorise, because the reader
                // "connects" this one by building an automation. The screen
                // walks them through it and reports when it last ran.
                } else if integration is ShortcutsIntegration {
                    NavigationLink {
                        ShortcutsIntegrationView()
                    } label: {
                        IntegrationSummaryRow(integration: integration,
                                              status: model.status(for: integration))
                    }
                } else {
                    IntegrationRow(integration: integration) { action in
                        Task {
                            switch action {
                            case .connect: await model.connect(integration)
                            case .disconnect: await model.disconnect(integration)
                            }
                            refreshToken += 1
                        }
                    }
                }
            }
        } header: {
            Text("Integrations")
        } footer: {
            Text("Apple Health works on-device. Tap Oura or Withings for a step-by-step guide. Shotsy has no API — you send it a file from Shotsy’s own share sheet, and tapping it explains how.")
        }
        .id(refreshToken)
    }

    /// One row, not a list.
    ///
    /// This was nine hand-listed grounding facts plus a separate row for the
    /// blood-test photo — a list that had to be edited by hand every time an
    /// input shipped, and wasn't. `weightGoal` landed the same morning the user
    /// pointed at it and appeared nowhere. It is now a sub-menu generated from
    /// `InputKind`, at the user's request: *"collapse this into a sub menu
    /// because it will get too long."*
    ///
    /// The renewal dots that used to be here moved with the facts — they live
    /// on the rows inside `GroundingDetailView`, which is where the facts now
    /// are. Two summaries stay: how many are set, and where you stand on each
    /// other input.
    private var inputSection: some View {
        Section {
            NavigationLink {
                AddDataView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Add or update data", systemImage: "plus.circle")
                    Text("\(groundingSetCount) of \(GroundingKind.directlyEntered.count) details set")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Every way to give the app something: your details, cuff readings, substances, medication and doses, side effects, a photographed blood test, and files shared from other apps.")
        }
    }

    private var groundingSetCount: Int {
        GroundingKind.directlyEntered.filter { model.profile.value($0) != nil }.count
    }


    /// The development feedback loop: hand back what the app has actually
    /// imported, so a decision about which signals deserve a card is made
    /// against the data rather than against a guess at what the parsers produce.
    private var exportSection: some View {
        Section {
            NavigationLink {
                DataExportView()
            } label: {
                Label("Export my data", systemImage: "square.and.arrow.up.on.square")
            }
        } footer: {
            Text("An inventory of every signal in your Data tab — including the imported fields no card reads yet — small enough to send in a message. Stays on this phone until you share it, and never includes account details.")
        }
    }

    private var intelligenceSection: some View {
        Section {
            HStack {
                Label("On-device summaries", systemImage: "sparkles")
                Spacer()
                Text(model.summarizer.isModelAvailable ? "Apple Intelligence" : "Template mode")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("When Apple Intelligence is available, your daily summary is written by the on-device foundation model. No health data leaves your phone.")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                TroubleshootingView()
            } label: {
                Label("Troubleshooting", systemImage: "stethoscope")
            }
            NavigationLink {
                DisclaimerView()
            } label: {
                Label("About & medical disclaimer", systemImage: "info.circle")
            }
            LabeledContent("Version", value: BuildInfo.summary)
            LabeledContent("Built", value: BuildInfo.formattedDate)
        } footer: {
            Text("Troubleshooting shows a live log of every sync, connection and imported value — handy if a device won't connect or a stat is missing. Version and build time tell you which deploy is on the phone.")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                TelemetryOutboxView()
            } label: {
                Label("Data & model improvement", systemImage: "lock.shield")
            }
        } footer: {
            Text("See exactly what would ever leave your phone to make the models better. Off by default; nothing is sent in this build.")
        }
    }

}

/// A single integration row with a connect / disconnect control and live status.
struct IntegrationRow: View {
    let integration: any HealthIntegration
    enum Action { case connect, disconnect }
    let onAction: (Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: integration.iconSystemName)
                .font(.title3).frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.displayName)
                Text(statusText).font(.caption).foregroundStyle(statusColor)
            }
            Spacer()
            control
        }
    }

    @ViewBuilder private var control: some View {
        switch integration.status {
        case .connected:
            Button("Disconnect", role: .destructive) { onAction(.disconnect) }
                .font(.caption).buttonStyle(.bordered)
        case .connecting:
            ProgressView()
        case .unavailable:
            Text("Unavailable").font(.caption).foregroundStyle(.secondary)
        default:
            Button("Connect") { onAction(.connect) }
                .font(.caption).buttonStyle(.borderedProminent)
        }
    }

    private var statusText: String {
        switch integration.status {
        case .notConnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected(let last):
            if let last { return "Synced \(last.formatted(.relative(presentation: .named)))" }
            return "Connected"
        case .unavailable(let reason): return reason
        case .error(let msg): return msg
        }
    }

    private var statusColor: Color {
        switch integration.status {
        case .connected: return Theme.good
        case .error: return Theme.bad
        default: return .secondary
        }
    }
}

/// Compact, non-interactive row for OAuth providers; tapping navigates to setup.
struct IntegrationSummaryRow: View {
    let integration: any HealthIntegration
    let status: IntegrationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: integration.iconSystemName)
                .font(.title3).frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.displayName)
                Text(statusText).font(.caption).foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if case .connected = status {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            } else if case .error = status {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
            }
        }
    }

    private var statusText: String {
        switch status {
        case .connected(let last):
            if let last { return "Connected · synced \(last.formatted(.relative(presentation: .named)))" }
            return "Connected"
        case .connecting: return "Connecting…"
        case .error(let msg): return "Couldn't connect: \(msg). Tap to try again."
        default: return "Tap to set up"
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return Theme.good
        case .error: return Theme.bad
        default: return .secondary
        }
    }
}

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How this app works")
                    .font(.title2.bold())
                Text("Heart-attack and stroke risk is computed with published, peer-reviewed clinical equations (SCORE2 and the ASCVD Pooled Cohort Equations). Heart-health scores come from your measured fitness signals compared with age-adjusted norms and your own baseline. Blood pressure is grounded in the readings you log from a real cuff; any on-device estimate is clearly marked as experimental.")
                Text("Not a medical device")
                    .font(.headline)
                Text("This app is for information and self-tracking only. It does not diagnose, treat, or prevent any disease, and it is not a substitute for professional medical advice. Always consult a qualified clinician about your health, and seek emergency care for any acute symptoms.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
