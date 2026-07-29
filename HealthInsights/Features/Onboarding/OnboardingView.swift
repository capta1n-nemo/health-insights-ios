import SwiftUI
import InsightKit

/// A short, friendly first-run flow: welcome → connect Apple Health → optionally
/// connect devices → the two mandatory profile facts → done. The devices step is
/// fully skippable and everything is editable later in Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var page = 0
    @State private var setupProvider: OAuthIntegration?

    // Profile step. Optional so nothing is pre-filled with a fake value — the
    // user must confirm a real date of birth and sex (pre-filled from Apple
    // Health when available) before the risk models will run.
    @State private var dob: Date?
    @State private var sex: Int?

    private let lastPage = 3

    /// The last page can't be completed until both required facts are set.
    private var canFinish: Bool { dob != nil && sex != nil }

    var body: some View {
        VStack {
            TabView(selection: $page) {
                welcome.tag(0)
                connectHealth.tag(1)
                connectDevices.tag(2)
                profile.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page < lastPage ? "Continue" : "Get started") {
                if page < lastPage { withAnimation { page += 1 } } else { finish() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(page == lastPage && !canFinish)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $setupProvider) { provider in
            NavigationStack { ProviderSetupView(provider: provider) }
        }
    }

    private var welcome: some View {
        OnboardingPanel(icon: "heart.text.square.fill", title: "Welcome") {
            VStack(spacing: 12) {
                Text("Turn your Apple Health, Oura and Withings data into clear heart-health insights — powered by validated clinical models, running privately on your phone.")
                    .multilineTextAlignment(.center)
                Text("We'll only ever ask for the real readings the models genuinely need.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var appleHealth: (any HealthIntegration)? {
        model.registry.integration(withID: MetricSource.appleHealth.id)
    }

    private var appleHealthConnected: Bool {
        guard let apple = appleHealth, case .connected = model.status(for: apple) else { return false }
        return true
    }

    private var connectHealth: some View {
        OnboardingPanel(icon: "heart.fill", title: "Connect Apple Health") {
            VStack(spacing: 16) {
                Text("Grant read access so we can use your heart rate, HRV, cardio fitness and more. Your data stays on device.")
                    .multilineTextAlignment(.center)
                if appleHealthConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.good)
                        .font(.headline)
                } else {
                    Button("Connect Apple Health") {
                        Task {
                            guard let apple = appleHealth else { return }
                            await model.connect(apple)
                            // Reflect the granted state, then move the user along.
                            if case .connected = model.status(for: apple) {
                                prefillBasicsFromHealth()
                                if page == 1 { withAnimation { page = 2 } }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var connectDevices: some View {
        OnboardingPanel(icon: "sensor.tag.radiowaves.forward", title: "Connect your devices") {
            VStack(spacing: 14) {
                Text("Optional — you can do this now or any time in Settings. Tap a device for a simple, step-by-step guide.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ForEach(oauthProviders, id: \.id) { provider in
                    let connected: Bool = { if case .connected = model.status(for: provider) { return true }; return false }()
                    Button {
                        setupProvider = provider
                    } label: {
                        HStack {
                            Image(systemName: provider.iconSystemName)
                            Text(connected ? provider.displayName : "Set up \(provider.displayName)")
                            Spacer()
                            if connected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            } else {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
                Text("Prefer to skip? Just tap Continue.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var profile: some View {
        OnboardingPanel(icon: "person.text.rectangle", title: "A couple of basics") {
            VStack(alignment: .leading, spacing: 16) {
                Text(dob != nil || sex != nil
                     ? "We pre-filled these from Apple Health — please check they're right. Both are required by the risk models."
                     : "These two are required by the risk models. Please set them.")
                    .font(.footnote).foregroundStyle(.secondary)

                // Date of birth — no fake default; the user picks (or confirms
                // the value read from Health).
                if let dobBinding = Binding($dob) {
                    DatePicker("Date of birth", selection: dobBinding, in: ...Date(), displayedComponents: .date)
                } else {
                    Button {
                        dob = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
                    } label: {
                        HStack {
                            Text("Date of birth")
                            Spacer()
                            Text("Set").foregroundStyle(Theme.accent)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Biological sex").font(.subheadline)
                    Picker("Biological sex", selection: $sex) {
                        Text("Male").tag(Int?.some(0))
                        Text("Female").tag(Int?.some(1))
                    }.pickerStyle(.segmented)
                }

                if let weight = model.latest(.bodyMass) {
                    confirmationRow("Weight", String(format: "%.1f kg", weight))
                }
                if let height = model.latest(.height) {
                    confirmationRow("Height", String(format: "%.0f cm", height * 100))
                }

                if !canFinish {
                    Text("Set your date of birth and sex to continue.")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
            }
            .onAppear { prefillBasicsFromHealth() }
        }
    }

    private func confirmationRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.subheadline)
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good).font(.caption)
        }
    }

    /// Pre-fill date of birth and sex from Apple Health characteristics if we
    /// have them and the user hasn't already entered a value. Never overwrites
    /// a user choice; never invents data.
    private func prefillBasicsFromHealth() {
        let chars = model.healthService.biologicalCharacteristics()
        if dob == nil, let d = chars.dateOfBirth { dob = d }
        if sex == nil, let s = chars.sex { sex = (s == .male) ? 0 : 1 }
    }

    private var oauthProviders: [OAuthIntegration] {
        model.registry.integrations.compactMap { $0 as? OAuthIntegration }
    }

    private func finish() {
        guard let dob, let sex else { return }   // button is disabled until both set
        model.saveGrounding(kind: .dateOfBirth, value: dob.timeIntervalSince1970)
        model.saveGrounding(kind: .biologicalSex, value: Double(sex))
        // Australia is best matched by SCORE2's low-risk region; seed it so the
        // combined risk model is calibrated sensibly out of the box. Editable
        // later in Settings.
        if model.profile.value(.score2Region) == nil {
            model.saveGrounding(kind: .score2Region, value: 0) // 0 = low
        }
        model.hasCompletedOnboarding = true
        isPresented = false
        Task { await model.refresh() }
    }
}

/// Shared layout for an onboarding page.
struct OnboardingPanel<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text(title).font(.largeTitle.bold())
            content
                .padding(.horizontal, 32)
            Spacer(); Spacer()
        }
        .padding()
    }
}
