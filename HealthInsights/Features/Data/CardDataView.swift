import SwiftUI
import InsightKit

/// Everything one card draws on, in one place.
///
/// ## Why this exists
///
/// The "View & add" hub gives every route its own add button, and each route
/// used to carry its own *view* link too — the metric screen, the substance
/// log, the dose history, the facts list, each a separate destination. That was
/// fine when a card read one thing. It doesn't: Body Composition reads weight,
/// body fat, lean mass and a modelled medication level, and takes doses, side
/// effects, a build and an import — and "view my data" fragmenting into eight
/// links is the opposite of an answer. The user's call: *"we can have multiple
/// data sources… figure out how it views data in a consolidated way"*, and the
/// direction chosen was **one data screen per card**.
///
/// So this is the card-scoped twin of the Data tab. The metric rows are the same
/// rows `DataTabView` draws — latest value, staleness, how many sources report
/// it — narrowed to the signals this card reads; below them sit the card's own
/// logs and inputs, each opening the full record. Viewing is consolidated here;
/// adding stays per-route in the hub, because logging a dose and reviewing the
/// dose history are different jobs.
struct CardDataView: View {
    let cardTitle: String
    /// The signals this card reads, in the card's own order.
    let metrics: [MetricType]
    let routes: [ContributionRoute]
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model

    /// Only the metrics that actually have readings — a card lists the signals
    /// it *would* read, and the ones with nothing recorded belong in "View &
    /// add" as a gap, not here as an empty row.
    private var presentMetrics: [MetricType] {
        var seen: Set<MetricType> = []
        return metrics.filter { seen.insert($0).inserted && model.vitalsSummaries[$0] != nil }
    }

    var body: some View {
        List {
            if !presentMetrics.isEmpty {
                Section {
                    ForEach(presentMetrics, id: \.self) { metric in
                        NavigationLink {
                            MetricDetailView(metric: metric)
                        } label: {
                            metricRow(metric)
                        }
                    }
                } header: {
                    Text("Signals this card reads")
                } footer: {
                    Text("The measurements that feed this card's score. Tap any to see every source and its history.")
                }
            }

            // The card's own logs and inputs, in `ContributionRoute` order so
            // the screen reads the same as the hub beside it. Each route knows
            // whether it has anything to show.
            ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                routeSection(route)
            }
        }
        .navigationTitle("All \(cardTitle) data")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Metric rows (the Data-tab row, card-scoped)

    @ViewBuilder private func metricRow(_ metric: MetricType) -> some View {
        let summary = model.vitalsSummaries[metric]
        HStack {
            Text(metric.displayName)
            Spacer()
            if let summary {
                Text(MetricValueFormatter.detailedString(summary.displayValue, metric))
                    .foregroundStyle(.secondary).monospacedDigit()
                if let age = staleness(summary.displayDate) {
                    Text("· \(age)").font(.caption2).foregroundStyle(.tertiary)
                }
                if summary.sourceCount > 1 {
                    Text("· \(summary.sourceCount) sources")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func staleness(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return nil }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    // MARK: - Route sections

    /// One section per route that has data. Exhaustive over `ContributionRoute`,
    /// so a new kind of data cannot be added without saying how it is viewed
    /// here — the same discipline `DataTabView.section(for:)` enforces app-wide.
    @ViewBuilder private func routeSection(_ route: ContributionRoute) -> some View {
        switch route {
        case .bloodPressureReadings: bloodPressureSection
        case .substanceLog: substanceSection
        case .medication: medicationSection
        case .fileImport: importSection
        case .bodyMeasurements: bodyMeasurementsSection
        case .bodyType: bodyTypeSection
        case .screenTime: screenTimeSection
        case .symptomLog: symptomSection
        case .groundingFacts(let kinds): factsSection(kinds)
        }
    }

    @ViewBuilder private var bloodPressureSection: some View {
        if let latest = model.bloodPressureReadings.first {
            Section("Blood pressure") {
                NavigationLink {
                    MetricDetailView(subject: .bloodPressure)
                } label: {
                    HStack {
                        Text("Readings")
                        Spacer()
                        Text("\(Int(latest.systolic.rounded()))/\(Int(latest.diastolic.rounded())) mmHg")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Text("· \(model.bloodPressureReadings.count) \(SectionCaveat.plural(model.bloodPressureReadings.count, "reading"))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var substanceSection: some View {
        if !model.substanceEvents.isEmpty {
            Section("Substances") {
                NavigationLink {
                    SubstanceLogView()
                } label: {
                    let load = SubstanceLoad.load(events: model.substanceEvents, at: Date())
                    HStack {
                        Text("Log")
                        Spacer()
                        Text("\(Int(load.rounded())) · \(SubstanceResponseAnalyzer.band(for: load))")
                            .foregroundStyle(.secondary)
                        Text("· \(model.substanceEvents.count) \(SectionCaveat.plural(model.substanceEvents.count, "entry", plural: "entries"))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Doses and side effects are separate domains — separate rows into their
    /// own data pages — so this card slice reads the same as the Data tab does,
    /// rather than inventing a combined destination that exists nowhere else.
    @ViewBuilder private var medicationSection: some View {
        let doses = model.activeMedication?.doses.count ?? 0
        let effects = model.sideEffects.count
        if doses > 0 {
            Section("Medication") {
                NavigationLink {
                    MedicationDataView()
                } label: {
                    HStack {
                        Text("Doses")
                        Spacer()
                        Text("\(doses) \(SectionCaveat.plural(doses, "dose"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if effects > 0 {
            Section("Side effects") {
                NavigationLink {
                    SideEffectDataView()
                } label: {
                    HStack {
                        Text("Recorded")
                        Spacer()
                        Text("\(effects) side \(SectionCaveat.plural(effects, "effect"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var importSection: some View {
        if let last = ShotsyIntegration.lastImportDate {
            Section("Imports") {
                NavigationLink {
                    NavigationStack { ShotsyIntegrationView() }
                } label: {
                    HStack {
                        Text("From another app")
                        Spacer()
                        Text(last.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The card-scoped view of what has been measured.
    ///
    /// Sites rather than a scan count: "5 measurements" answers what the reader
    /// wants to know, and "2 scans" does not. A disputed site is called out
    /// here rather than resolved silently — two sources disagreeing beyond the
    /// noise is information, and `BodyMeasurementReconciliation` deliberately
    /// keeps the loser rather than hiding it.
    @ViewBuilder private var bodyMeasurementsSection: some View {
        let measurements = model.reconciledMeasurements()
        if !measurements.values.isEmpty {
            Section("Body measurements") {
                ForEach(measurements.sites, id: \.self) { site in
                    if let value = measurements.mean(site) {
                        HStack {
                            Text(site.displayName)
                            Spacer()
                            Text(String(format: "%.1f cm", value))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                ForEach(model.measurementDisputes(), id: \.chosen.site) { dispute in
                    if let note = dispute.note {
                        Text(note)
                            .font(.caption).foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private var bodyTypeSection: some View {
        if let build = model.buildOverrideName ?? model.estimatedBuildName {
            Section("Build") {
                HStack {
                    Text(model.buildOverrideName != nil ? "Your build" : "Estimated build")
                    Spacer()
                    Text(build).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var screenTimeSection: some View {
        let days = model.screenTimeDaysRecorded
        if days > 0 {
            Section("Screen time") {
                NavigationLink {
                    MetricDetailView(metric: .screenTimeMinutes)
                } label: {
                    HStack {
                        Text("Days recorded")
                        Spacer()
                        Text("\(days)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The reader's symptom tags, opening the same page the Data tab presents —
    /// one data page per domain, never a parallel one. Counts only what was
    /// actually *had*: a recorded absence is a real answer, not an occurrence.
    @ViewBuilder private var symptomSection: some View {
        let present = model.symptoms.filter { $0.severity.isPresent }
        if !present.isEmpty {
            Section("Symptoms") {
                NavigationLink {
                    SymptomDataView()
                } label: {
                    HStack {
                        Text("Tagged")
                        Spacer()
                        Text("\(present.count) \(SectionCaveat.plural(present.count, "entry", plural: "entries"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func factsSection(_ kinds: [GroundingKind]) -> some View {
        let unmet = Set(unmetRequirements.map(\.kind))
        let set = kinds.filter { !unmet.contains($0) }.count
        if !kinds.isEmpty {
            Section("Your details") {
                NavigationLink {
                    GroundingDetailView(kinds: kinds, unmetRequirements: unmetRequirements)
                } label: {
                    HStack {
                        Text("Details you've given")
                        Spacer()
                        Text("\(set) of \(kinds.count) set")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
