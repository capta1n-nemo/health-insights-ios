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
///
/// Viewing what has already been given is not per-route here: it is the single
/// "View all this card's data" link at the top, which opens `CardDataView`. A
/// card with four routes had four view links scattered down it, which is exactly
/// the fragmentation the consolidated screen removes.
///
/// Extensibility is the compiler's: `section(for:)` switches exhaustively over
/// `ContributionRoute`, so the next kind of data — a scan, a goal, whatever
/// comes — does not build until this screen says how it is added and where its
/// history is seen.
struct ViewAndAddHubView: View {
    let cardTitle: String
    /// The signals this card reads, for the consolidated data screen.
    let metrics: [MetricType]
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
                    // Viewing is consolidated into one screen; the sections
                    // below are for adding. See `CardDataView`.
                    Card {
                        NavigationLink {
                            CardDataView(cardTitle: cardTitle, metrics: metrics,
                                         routes: routes, unmetRequirements: unmetRequirements)
                        } label: {
                            HStack {
                                Label("View all this card's data", systemImage: "list.bullet.rectangle")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
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
        case .screenTime: screenTimeSection(status)
        }
    }

    // MARK: - The one anatomy

    /// Every route is this now: a header, the grounded summary, one add button,
    /// and an optional bespoke `extra` (medication's side-effect button, the
    /// file importer's result line). The per-route *view* links are gone —
    /// viewing is the one consolidated screen at the top of this hub, so a route
    /// here is purely "add", which is the job the card can't consolidate.
    private func sectionBody<Extra: View>(
        _ status: ContributionRouteStatus,
        addAction: @escaping () -> Void,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
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
        }
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

    // MARK: - Blood pressure

    private func bloodPressureSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { addingBloodPressure = true })
    }

    // MARK: - Substance log

    private func substanceSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { showingSubstanceLog = true })
    }

    // MARK: - Medication

    /// Set up or log a dose with the button, record a side effect beside it.
    /// The dated history lives on the consolidated data screen.
    private func medicationSection(_ status: ContributionRouteStatus) -> some View {
        let medication = model.activeMedication
        return sectionBody(
            status,
            addAction: { activeInput = medication == nil ? .medicationRegimen : .medicationDose },
            extra: {
                if medication != nil {
                    Button("Record a side effect") { activeInput = .sideEffect }
                        .font(.caption.weight(.medium))
                }
            })
    }

    // MARK: - Body type

    private func bodyTypeSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { activeInput = .bodyType })
    }

    // MARK: - Screen time

    /// `ScreenTimeEntrySheet` is the whole route — Apple gives an app no way to
    /// read the figure, so there is nothing to link to but the entry.
    private func screenTimeSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(status, addAction: { activeInput = .screenTime })
    }

    // MARK: - Grounding facts

    private func factsSection(_ status: ContributionRouteStatus,
                              kinds: [GroundingKind]) -> some View {
        sectionBody(status, addAction: { showingGroundingDetail = GroundingKindList(values: kinds) })
    }

    // MARK: - File import

    /// Bringing a file in from another app — today a Shotsy backup. Bespoke
    /// below the button: the importer's result line has nowhere else to go.
    private func fileImportSection(_ status: ContributionRouteStatus) -> some View {
        sectionBody(
            status,
            addAction: { showingImporter = true },
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

/// `sheet(item:)` needs an `Identifiable`, and `[GroundingKind]` is not one.
///
/// A wrapper rather than a retroactive conformance on `Array`: conforming a
/// standard-library type to a protocol it does not own is a change every other
/// file in the target inherits, for one sheet's benefit.
struct GroundingKindList: Identifiable {
    let values: [GroundingKind]
    var id: String { values.map(\.rawValue).joined(separator: "|") }
}
