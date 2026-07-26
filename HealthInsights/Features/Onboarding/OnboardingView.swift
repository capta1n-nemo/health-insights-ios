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

    // Local seeds for the profile step.
    @State private var dob = Calendar.current.date(byAdding: .year, value: -40, to: Date()) ?? Date()
    @State private var sex = 0

    private let lastPage = 3

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

    private var connectHealth: some View {
        OnboardingPanel(icon: "heart.fill", title: "Connect Apple Health") {
            VStack(spacing: 16) {
                Text("Grant read access so we can use your heart rate, HRV, cardio fitness and more. Your data stays on device.")
                    .multilineTextAlignment(.center)
                Button("Connect Apple Health") {
                    Task {
                        if let apple = model.registry.integration(withID: MetricSource.appleHealth.id) {
                            await model.connect(apple)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var connectDevices: some View {
        OnboardingPanel(icon: "sensor.tag.radiowaves.forward", title: "Connect your devices") {
            VStack(spacing: 14) {
                Text("Optional — you can do this now or any time in Settings. Tap a device for a simple, step-by-step guide.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ForEach(oauthProviders, id: \.id) { provider in
                    Button {
                        setupProvider = provider
                    } label: {
                        HStack {
                            Image(systemName: provider.iconSystemName)
                            Text("Set up \(provider.displayName)")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
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
                Text("These two are required by the risk models.")
                    .font(.footnote).foregroundStyle(.secondary)
                DatePicker("Date of birth", selection: $dob, in: ...Date(), displayedComponents: .date)
                Picker("Biological sex", selection: $sex) {
                    Text("Male").tag(0); Text("Female").tag(1)
                }.pickerStyle(.segmented)
            }
        }
    }

    private var oauthProviders: [OAuthIntegration] {
        model.registry.integrations.compactMap { $0 as? OAuthIntegration }
    }

    private func finish() {
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
