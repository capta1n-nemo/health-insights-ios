import SwiftUI
import UniformTypeIdentifiers
import InsightKit

/// "View & add" — one section, one anatomy, on every card that takes something
/// from the user.
///
/// Before this there were three unrelated experiences: a one-fact sheet behind
/// "Add these for a better estimate", a blood-pressure chart and add-button
/// hidden behind a link to a different screen, and a substance log reachable
/// only from a toolbar button on a tab that never mentions it. Body composition
/// had no route at all.
///
/// What each card offers comes from its model's `contributions`
/// (`ContributionRoute` in InsightKit), which is derived from the requirements
/// the model already declares — so this view never decides *what* a card takes,
/// only how it looks.
///
/// ## The anatomy, and what it stopped being
///
/// The doc comment here used to claim the anatomy was fixed whatever the route.
/// It was not. Blood pressure had a grounded summary and the other two did not;
/// the grounding-facts route had no add button at all, so its rows were the only
/// way in; the "all readings" link appeared only once there were more than
/// three; and all three routes **previewed their own contents** on the card —
/// three readings, three events, and every fact with its value.
///
/// It is now, everywhere:
///
/// 1. A header, and one figure saying where you are.
/// 2. The grounded / not-grounded summary — a seal, a sentence, and a bar while
///    there is something left to fill.
/// 3. One prominent button into the sub-menu that holds adding *and* what has
///    been added.
/// 4. A link to the fuller screen, where one exists beyond that sub-menu. Only
///    blood pressure has one; see `ContributionSummary.detailLabel`.
///
/// **No previews.** A card is for where you stand; the sub-menu is for what you
/// gave. Listing the last three readings on the card duplicated the first rows
/// of the screen the button opens, and the fact values did the same for the
/// grounding list. The state — how many, how recent, whether that is enough — is
/// the part that belongs out here, and `ContributionSummary` computes it in
/// InsightKit where it is tested.
struct ViewAndAddSection: View {
    let routes: [ContributionRoute]
    /// Carried so a missing fact can show the model's own reason for wanting it,
    /// which is the sentence that used to live on "Add these for a better
    /// estimate".
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model
    @State private var addingBloodPressure = false
    @State private var showingSubstanceLog = false
    @State private var showingGroundingDetail: GroundingKindList?
    @State private var showingImporter = false
    @State private var importMessage: String?
    /// The two routes added on 2026-08-02, after the user found three inputs on
    /// the Body Composition card that this section did not mention.
    @State private var activeInput: InputKind?

    var body: some View {
        if !routes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                        if index > 0 { Divider() }
                        section(for: route)
                    }
                }
            }
            .sheet(isPresented: $addingBloodPressure) {
                AddBloodPressureView { systolic, diastolic, date in
                    model.logBloodPressure(systolic: systolic, diastolic: diastolic, at: date)
                }
            }
            .sheet(isPresented: $showingSubstanceLog) { SubstanceLogView() }
            .sheet(item: $showingGroundingDetail) { kinds in
                GroundingDetailView(kinds: kinds.values,
                                    unmetRequirements: unmetRequirements)
            }
            // The same sheets the master list and the `+` menu open. One switch
            // for the whole app — see `View.inputSheet(_:)`.
            .inputSheet($activeInput)
        }
    }

    /// Bringing a file in from another app — today a Shotsy backup.
    ///
    /// On the card rather than only in Settings because that is what this
    /// section is *for*: it answers "what does this card want from me", and an
    /// input the reader can only find by going looking is one they will not
    /// find. The same will be true of scans and photos.
    @ViewBuilder private var fileImportRoute: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Import from another app", systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.medium))
            Text("Shotsy holds your injections, weight and body composition. Export its JSON and share it here — or pick a file you've already saved.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let lastImport = ShotsyIntegration.lastImportDate {
                Text("Last file received \(lastImport.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Button("Choose a file") { showingImporter = true }
                .font(.caption.weight(.medium))
            if let importMessage {
                Text(importMessage)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: ShotsyIntegrationView.acceptedTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { importMessage = await model.importSharedFile(at: url) }
            case .failure(let error):
                importMessage = "Couldn't open that file: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder private func section(for route: ContributionRoute) -> some View {
        switch route {
        case .bloodPressureReadings: bloodPressureRoute
        case .substanceLog: substanceRoute
        case .groundingFacts(let kinds): factsRoute(kinds)
        case .fileImport: fileImportRoute
        case .medication: medicationRoute
        case .bodyType: bodyTypeRoute
        }
    }

    // MARK: - The one anatomy

    /// Every route is this. The only per-route parts are the destination the
    /// button opens and the destination the link pushes.
    private func routeBody<Link: View>(
        title: String,
        summary: ContributionSummary,
        add: @escaping () -> Void,
        @ViewBuilder link: () -> Link
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title, status: summary.figure)
            GroundedSummary(summary: summary)

            Button(action: add) {
                Label(summary.addLabel, systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            link()
        }
    }

    /// The same header everywhere: what this is, and one figure saying where you
    /// are. The figure is the thing that makes the section worth looking at when
    /// there is nothing to add.
    private func header(_ title: String, status: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: "plus.circle")
                .font(.headline)
            Spacer()
            if let status {
                Text(status)
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func detailLink<Destination: View>(
        _ summary: ContributionSummary,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        Group {
            if let label = summary.detailLabel {
                NavigationLink(destination: destination()) {
                    HStack(spacing: 4) {
                        Text(label).font(.caption.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Blood pressure

    /// The one route with somewhere further to go: the sheet takes a reading,
    /// the metric screen holds the dated history, the chart and the calibration
    /// detail. The link used to appear only past three readings, so the screen
    /// was unreachable from here exactly while a user was learning the feature.
    private var bloodPressureRoute: some View {
        let summary = ContributionSummary.bloodPressure(model.bloodPressureCalibration)
        return routeBody(
            title: "View & add readings",
            summary: summary,
            add: { addingBloodPressure = true },
            link: {
                detailLink(summary) { MetricDetailView(subject: .bloodPressure) }
            })
    }

    // MARK: - Substance log

    /// `SubstanceLogView` is already both halves — the chips add, and the
    /// entries below can be re-timed or removed — so the button is the whole
    /// route and there is nothing for a link to reach past it.
    private var substanceRoute: some View {
        let summary = ContributionSummary.substances(logged: model.substanceEvents.count)
        return routeBody(
            title: "View & add entries",
            summary: summary,
            add: { showingSubstanceLog = true },
            link: { detailLink(summary) { EmptyView() } })
    }

    // MARK: - Medication

    /// Regimen, doses and side effects behind one button.
    ///
    /// **This route is the fix for the reported bug.** Logging a dose was a
    /// button inside the Weight-management chart and nowhere else, so the one
    /// section that is supposed to answer "what does this card want from me"
    /// did not mention it. The in-context button stays — it is the right place
    /// to log a dose while you are looking at the curve — but it is no longer
    /// the *only* place.
    private var medicationRoute: some View {
        let medication = model.activeMedication
        let summary = ContributionSummary.medication(
            hasRegimen: medication != nil,
            doses: medication?.doses.count ?? 0,
            sideEffects: model.sideEffects.count)
        return routeBody(
            title: "View & add medication",
            summary: summary,
            add: { activeInput = medication == nil ? .medicationRegimen : .medicationDose },
            link: { detailLink(summary) { EmptyView() } })
    }

    // MARK: - Body type

    /// The build override, which lived inside the somatotype chart and was
    /// named nowhere else. Same story as the dose button above.
    private var bodyTypeRoute: some View {
        let summary = ContributionSummary.bodyType(
            estimated: model.estimatedBuildName, override: model.buildOverrideName)
        return routeBody(
            title: "View & add your build",
            summary: summary,
            add: { activeInput = .bodyType },
            link: { detailLink(summary) { EmptyView() } })
    }

    // MARK: - Grounding facts

    /// The route that had no button. Its rows were the only way to reach a
    /// value, which meant the "add" half of "View & add" was a thing you had to
    /// already know was there.
    private func factsRoute(_ kinds: [GroundingKind]) -> some View {
        let unmetKinds = Set(unmetRequirements.map(\.kind))
        let setCount = kinds.filter { !unmetKinds.contains($0) }.count
        let summary = ContributionSummary.facts(set: setCount, of: kinds.count)
        return routeBody(
            title: "View & add details",
            summary: summary,
            add: { showingGroundingDetail = GroundingKindList(values: kinds) },
            link: { detailLink(summary) { EmptyView() } })
    }
}

/// The green seal, the sentence, and a bar while there is something left to
/// fill. Modelled on `CalibrationProgress`, which was the one route that had
/// this and is now what all three look like.
struct GroundedSummary: View {
    let summary: ContributionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = summary.progress {
                ProgressView(value: progress).tint(Theme.accent)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: summary.isGrounded ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(summary.isGrounded ? Theme.good : Theme.accent)
                Text(summary.guidance)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// `sheet(item:)` needs an `Identifiable`, and `[GroundingKind]` is not one.
///
/// A wrapper rather than a retroactive conformance on `Array`: conforming a
/// standard-library type to a protocol it does not own is a change every other
/// file in the target inherits, for one sheet's benefit.
struct GroundingKindList: Identifiable {
    let values: [GroundingKind]
    var id: String { values.map(\.rawValue).joined(separator: "|") }
}
