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

    // Profile step. Optional so the reader must confirm a real date of birth
    // and sex before the risk models will run.
    @State private var dob: Date?
    @State private var sex: Int?

    /// Whether each value actually came from Apple Health — **one flag per
    /// fact**, because Health can supply one and not the other.
    ///
    /// **Not derivable from `dob != nil`, which is what this screen used to
    /// ask.** Tapping *Set* below fills the date with today minus thirty years
    /// so the `DatePicker` has something to bind to — so the moment the reader
    /// set it themselves, the copy told them Apple Health had provided it.
    /// Found in the simulator on 2026-08-04 with the Health connection
    /// declined: there was no Health data on the device at all and the screen
    /// still claimed a Health pre-fill.
    ///
    /// That is this app's own cardinal rule broken one layer above the models —
    /// a fabricated value presented as a measured one — and it is worse here
    /// than on a card, because a reader told the date came from Health has been
    /// given a reason *not* to check it, and age drives every cardiovascular
    /// risk score the app computes.
    ///
    /// The 2026-08-04 fix used a single `Bool` for both facts, which left the
    /// mixed case still wrong: Health commonly holds a sex and no birthdate, so
    /// one flag was set, the reader tapped *Set* for the date, and the screen
    /// said *"We pre-filled these from Apple Health"* over a placeholder. Found
    /// 2026-08-07 (backlog D12) — the same defect, one case narrower.
    @State private var dobFromHealth = false
    @State private var sexFromHealth = false

    /// Whether the date on screen is still the *Set* button's seed rather than
    /// the reader's own.
    ///
    /// This is what stops the mandatory ask being skippable. Before it, two
    /// taps — *Set*, then a sex — completed onboarding, and "today minus thirty
    /// years" was written to `GroundingKind.dateOfBirth` as an ordinary fact,
    /// indistinguishable from a confirmed one, to be used by every
    /// cardiovascular model the app runs. A mandatory fact that can be
    /// satisfied without being answered is not mandatory.
    @State private var dobIsPlaceholder = false

    private let lastPage = 3

    /// The last page can't be completed until both required facts are set —
    /// and a placeholder is not a set date.
    private var canFinish: Bool { dob != nil && !dobIsPlaceholder && sex != nil }

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
                Text("Turn your Apple Health, Oura and Withings data into clear heart-health insights — powered by validated clinical models, all of which run on your phone.")
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
                // ⚠️ Was "Your data stays on device." (B8 R6). A blanket
                // promise on the second screen of onboarding is the single
                // most-relied-on sentence in the app, and it stopped being
                // unconditional when two-tier sharing shipped on by default.
                // It now says what is true — your readings are not sent —
                // and points at the screen that states the exception, rather
                // than making a claim the reader would have to discover was
                // narrower than it sounded.
                Text("Grant read access so we can use your heart rate, HRV, cardio fitness and more. Your readings are stored on this phone and are never uploaded. What can be shared to improve the models is listed in Settings ▸ Data & model improvement, and nothing is sent in this build.")
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
                Text(basicsPrompt)
                    .font(.footnote).foregroundStyle(.secondary)

                // Date of birth. Tapping *Set* seeds the picker with a round
                // thirty years so there is something to bind to — that is a
                // starting point, never a reading, and `basicsPrompt` says so
                // rather than crediting Apple Health for it.
                if let dobBinding = Binding($dob) {
                    DatePicker("Date of birth", selection: dobBinding, in: ...Date(), displayedComponents: .date)
                        // Fires only on a change the reader made: the seeding
                        // assignment happens *before* this view exists, so the
                        // first call is always a real adjustment.
                        .onChange(of: dob) { _, _ in dobIsPlaceholder = false }
                } else {
                    Button {
                        dob = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
                        dobIsPlaceholder = true
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

                if let outstanding = outstandingPrompt {
                    Text(outstanding)
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

    /// What the profile step says above the two fields.
    ///
    /// **Built per fact, not per screen.** Health can supply a sex and no
    /// birthdate (or the reverse), so any single sentence covering "these"
    /// credits Health for something it never provided — which is the exact
    /// defect this screen has now been fixed for twice. Each fact says where
    /// its own value came from, and a placeholder is called a placeholder.
    private var basicsPrompt: String {
        var parts: [String] = []
        var toSet: [String] = []

        if dobFromHealth {
            parts.append("Your date of birth came from Apple Health — please check it's right.")
        } else if dobIsPlaceholder {
            parts.append("The date below is a placeholder, not a reading — move it to your own date of birth.")
        } else if dob == nil {
            toSet.append("date of birth")
        }

        if sexFromHealth {
            parts.append("Your sex came from Apple Health — please check it's right.")
        } else if sex == nil {
            toSet.append("biological sex")
        }

        // One sentence for whatever is still blank, rather than one apiece —
        // "Please set your date of birth. Please set your biological sex."
        // is what building it per fact reads like on a fresh install.
        if !toSet.isEmpty {
            parts.append("Please set your \(toSet.joined(separator: " and ")).")
        }

        parts.append("Both are required by the risk models.")
        return parts.joined(separator: " ")
    }

    /// What is still outstanding, named — shown in the accent colour beside the
    /// disabled button so "Get started" being dead is never a mystery.
    private var outstandingPrompt: String? {
        var missing: [String] = []
        if dob == nil {
            missing.append("set your date of birth")
        } else if dobIsPlaceholder {
            missing.append("move the date of birth off the placeholder")
        }
        if sex == nil { missing.append("choose your biological sex") }
        guard !missing.isEmpty else { return nil }
        return "To continue, \(missing.joined(separator: " and "))."
    }

    /// Pre-fill date of birth and sex from Apple Health characteristics if we
    /// have them and the user hasn't already entered a value. Never overwrites
    /// a user choice; never invents data.
    ///
    /// Records *that* it pre-filled, which is the part the copy above needs and
    /// could not previously ask for.
    private func prefillBasicsFromHealth() {
        let chars = model.healthService.biologicalCharacteristics()
        if dob == nil, let d = chars.dateOfBirth {
            dob = d
            dobFromHealth = true
            // A Health birthdate is a real one, so it is not a placeholder even
            // though it arrived without the reader touching the picker.
            dobIsPlaceholder = false
        }
        if sex == nil, let s = chars.sex {
            sex = (s == .male) ? 0 : 1
            sexFromHealth = true
        }
    }

    private var oauthProviders: [OAuthIntegration] {
        model.registry.integrations.compactMap { $0 as? OAuthIntegration }
    }

    private func finish() {
        // The button is disabled until both are set and the date is the
        // reader's own — checked again here so a future caller cannot write a
        // placeholder birthdate into the grounding facts by accident.
        guard let dob, let sex, !dobIsPlaceholder else { return }
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
        Task { await model.refresh(force: true) }
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
