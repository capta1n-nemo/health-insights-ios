import SwiftUI
import UniformTypeIdentifiers
import InsightKit

/// The sub-menu behind a card's single "Add or view your data" button: every
/// route the card offers, at full size — the guidance, the add affordances, and
/// the way into everything already given.
///
/// This is where the anatomy that used to sit on the card itself now lives.
/// Rendering every route at full size was right for one route and wrong for
/// four: Body Composition stacked four near-identical prominent buttons down
/// its card. The card now carries one status line per route and one button; the
/// hub carries the rest.
///
/// ## The anatomy, per route
///
/// 1. A header, and one figure saying where you are.
/// 2. The grounded / not-grounded summary — a seal, a sentence, and a bar while
///    there is something left to fill.
/// 3. One prominent button that adds.
/// 4. A link to the dated history, where one exists beyond the entry sheet —
///    blood pressure's readings screen, medication's dose and side-effect list.
///    See `ContributionSummary.detailLabel`.
///
/// Extensibility is the compiler's: `section(for:)` switches exhaustively over
/// `ContributionRoute`, so the next kind of data — a scan, a goal, whatever
/// comes — does not build until this screen says how it is added and where its
/// history is seen.
struct ViewAndAddHubView: View {
    let routes: [ContributionRoute]
    /// Carried so a missing fact can show the model's own reason for wanting
    /// it.
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var addingBloodPressure = false
    @State private var showingSubstanceLog = false
    @State private var showingGroundingDetail: GroundingKindList?
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var activeInput: InputKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                        Card { section(for: route) }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("View & add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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

    @ViewBuilder private func section(for route: ContributionRoute) -> some View {
        let status = ContributionRouteStatus(route: route, model: model,
                                             unmetRequirements: unmetRequirements)
        switch route {
        case .bloodPressureReadings: bloodPressureSection(status)
        case .substanceLog: substanceSection(status)
        case .groundingFacts(let kinds): factsSection(status, kinds: kinds)
        case .fileImport: fileImportSection(status)
        case .medication: medicationSection(status)
        case .bodyType: bodyTypeSection(status)
        }
    }

    // MARK: - The one anatomy

    /// Every route is this. The only per-route parts are the destination the
    /// button opens, the destination the link pushes, and any extra affordance
    /// a route carries (`extra:` — medication's side-effect button, the file
    /// importer's result line).
    private func sectionBody<Link: View, Extra: View>(
        _ status: ContributionRouteStatus,
        addAction: @escaping () -> Void,
        @ViewBuilder link: () -> Link,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(status)
            GroundedSummary(summary: status.summary)

            Button(action: addAction) {
                Label(status.summary.addLabel, systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            extra()
            link()
        }
    }

    private func sectionBody<Link: View>(
        _ status: ContributionRouteStatus,
        addAction: @escaping () -> Void,
        @ViewBuilder link: () -> Link
    ) -> some View {
        sectionBody(status, addAction: addAction, link: link, extra: { EmptyView() })
    }

    /// The same header everywhere: what this is, and one figure saying where
    /// you are.
    private func header(_ status: ContributionRouteStatus) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(status.title)
                .font(.headline)
            Spacer()
            Text(status.summary.figure)
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()
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

    /// The sheet takes a reading; the metric screen holds the dated history,
    /// the chart and the calibration detail.
    private func bloodPressureSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { addingBloodPressure = true }) {
            detailLink(status.summary) { MetricDetailView(subject: .bloodPressure) }
        }
    }

    // MARK: - Substance log

    /// `SubstanceLogView` is already both halves — the chips add, and the
    /// entries below can be re-timed or removed — so the button is the whole
    /// route and there is nothing for a link to reach past it.
    private func substanceSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { showingSubstanceLog = true }) {
            detailLink(status.summary) { EmptyView() }
        }
    }

    // MARK: - Medication

    /// Regimen, doses and side effects in one section: set up or log a dose
    /// with the button, record a side effect beside it, and the full dated
    /// history behind the link.
    private func medicationSection(_ status: ContributionRouteStatus) -> some View {
        let medication = model.activeMedication
        return sectionBody(
            status,
            addAction: { activeInput = medication == nil ? .medicationRegimen : .medicationDose },
            link: {
                detailLink(status.summary) { MedicationHistoryView() }
            },
            extra: {
                if medication != nil {
                    Button("Record a side effect") { activeInput = .sideEffect }
                        .font(.caption.weight(.medium))
                }
            })
    }

    // MARK: - Body type

    /// `BodyTypeSheet` is both halves too: it shows the estimate and the
    /// current choice, and changes it.
    private func bodyTypeSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { activeInput = .bodyType }) {
            detailLink(status.summary) { EmptyView() }
        }
    }

    // MARK: - Grounding facts

    /// `GroundingDetailView` is the view-and-edit list of every fact the card
    /// asks for.
    private func factsSection(_ status: ContributionRouteStatus,
                              kinds: [GroundingKind]) -> some View {
        sectionBody(status, addAction: { showingGroundingDetail = GroundingKindList(values: kinds) }) {
            detailLink(status.summary) { EmptyView() }
        }
    }

    // MARK: - File import

    /// Bringing a file in from another app — today a Shotsy backup. Bespoke
    /// below the button: the importer's result line has nowhere else to go.
    private func fileImportSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(
            status,
            addAction: { showingImporter = true },
            link: { EmptyView() },
            extra: {
                if let importMessage {
                    Text(importMessage)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            })
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
}

/// The dated medication record: every dose and every side effect, newest first.
///
/// This screen exists because "view all previous data" was true of every route
/// but this one — readings had the metric screen, substances their log, facts
/// their list, while doses could be seen only as aggregates in the
/// Weight-management tables. View-only: entries are made through the sheets,
/// and an imported dose is part of the record, not something to edit here.
struct MedicationHistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let medication = model.activeMedication, !medication.doses.isEmpty {
                Section {
                    ForEach(medication.doses.sorted { $0.takenAt > $1.takenAt }) { dose in
                        doseRow(dose)
                    }
                } header: {
                    Text("Doses")
                } footer: {
                    Text("An estimated dose is one the app worked out from your schedule and you haven't confirmed yet. It is drawn dashed everywhere it appears.")
                }
            }
            if !model.sideEffects.isEmpty {
                Section("Side effects") {
                    ForEach(model.sideEffects.sorted { $0.date > $1.date }) { effect in
                        sideEffectRow(effect)
                    }
                }
            }
        }
        .navigationTitle("Doses & side effects")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if (model.activeMedication?.doses.isEmpty ?? true) && model.sideEffects.isEmpty {
                ContentUnavailableView("Nothing logged yet", systemImage: "pills",
                                       description: Text("Doses and side effects you log or import appear here."))
            }
        }
    }

    private func doseRow(_ dose: DoseLogRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dose.takenAt.formatted(date: .abbreviated, time: .omitted))
                if let site = dose.injectionSite {
                    Text(site).font(.caption).foregroundStyle(.secondary)
                }
                if dose.isInferred && dose.confirmedAt == nil {
                    Text("Estimated — not yet confirmed")
                        .font(.caption2).foregroundStyle(Theme.warn)
                }
            }
            Spacer()
            Text("\(dose.milligrams.formatted()) mg")
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func sideEffectRow(_ effect: SideEffectRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.name)
                Text(effect.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(effect.severity)/10")
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(.secondary)
        }
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
