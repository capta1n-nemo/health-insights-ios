import SwiftUI
import InsightKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    // Bumped after connect/disconnect to re-read integration status.
    @State private var refreshToken = 0
    @State private var groundingKind: GroundingKind?

    var body: some View {
        NavigationStack {
            List {
                integrationsSection
                profileSection
                importSection
                intelligenceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(item: $groundingKind) { GroundingEntryView(kind: $0) }
        }
    }

    private var integrationsSection: some View {
        Section {
            ForEach(model.registry.integrations, id: \.id) { integration in
                if let oauth = integration as? OAuthIntegration {
                    NavigationLink {
                        ProviderSetupView(provider: oauth)
                    } label: {
                        IntegrationSummaryRow(integration: integration)
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
            Text("Apple Health works on-device. Tap Oura or Withings for a simple, step-by-step guide to connect them — everything stays on your phone.")
        }
        .id(refreshToken)
    }

    private var profileSection: some View {
        Section("Your details") {
            ForEach(profileKinds, id: \.self) { kind in
                Button {
                    groundingKind = kind
                } label: {
                    HStack {
                        Text(kind.displayName).foregroundStyle(.primary)
                        Spacer()
                        Text(valueLabel(kind)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var importSection: some View {
        Section {
            NavigationLink {
                ImportLabView()
            } label: {
                Label("Import blood test (photo)", systemImage: "doc.text.viewfinder")
            }
        } footer: {
            Text("Read on-device — take or choose a photo of a pathology report and confirm the values. Nothing is uploaded.")
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
                DisclaimerView()
            } label: {
                Label("About & medical disclaimer", systemImage: "info.circle")
            }
        }
    }

    private let profileKinds: [GroundingKind] = [
        .dateOfBirth, .biologicalSex, .totalCholesterol, .hdlCholesterol,
        .currentSmoker, .hasDiabetes, .onBPMedication, .score2Region, .cuffSystolic
    ]

    private func valueLabel(_ kind: GroundingKind) -> String {
        guard let v = model.profile.value(kind) else { return "Add" }
        switch kind {
        case .dateOfBirth:
            let age = model.profile.age() ?? 0
            return "\(Int(age)) yrs"
        case .biologicalSex: return v == 0 ? "Male" : "Female"
        case .currentSmoker, .hasDiabetes, .onBPMedication: return v >= 0.5 ? "Yes" : "No"
        case .score2Region: return model.profile.score2Region.displayName
        case .totalCholesterol, .hdlCholesterol: return String(format: "%.1f mmol/L", v)
        case .cuffSystolic:
            let d = model.profile.value(.cuffDiastolic) ?? 0
            return "\(Int(v))/\(Int(d))"
        default: return "\(Int(v))"
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
        }
    }

    private var statusText: String {
        switch integration.status {
        case .connected(let last):
            if let last { return "Connected · synced \(last.formatted(.relative(presentation: .named)))" }
            return "Connected"
        case .connecting: return "Connecting…"
        case .error(let msg): return msg
        default: return "Tap to set up"
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
