import SwiftUI
import InsightKit

/// **Weight management** — Body Composition's *second* bespoke section.
///
/// What is still in you, whether it is working, and — where the app filled a
/// history in — a plain request to confirm it.
///
/// ## What this grew into, and why
///
/// It began as one chart of milligrams on board. That answers a question about
/// the *drug* and none about the reader, and the user said so after seeing
/// Shotsy's own Results tab: *"I want the medication board graph to be in this
/// new Medication section, and for you to overlay weight, fat, relevant stats
/// onto it.. so I can see how well it's working."* So the section now carries,
/// in order:
///
/// 1. **Since you started** — the whole regimen in four numbers.
/// 2. **Medication in your system**, then **Is it working** — the level on its
///    own, then the level, weight and body fat standardised onto one axis
///    (`MedicationResponseChart`).
/// 3. **By dose** — total change and weekly rate for each rung of the ladder.
/// 4. **By injection site** — the same, where sites were recorded.
/// 5. **Side effects** — worst average first.
/// 6. The confirm-inferred-doses row, and logging.
///
/// Every figure comes from `MedicationResponse` in InsightKit, where it is
/// tested. **The attribution is by timing, not cause** — see
/// `SectionCaveat.doseAttribution`, which every table here carries rather than
/// each writing its own gentler version.
///
/// **"On board" is gone.** It was the pharmacology's own jargon and read as
/// nothing to anybody outside it. The user, 2026-08-02: *"renamed to something
/// more understandable, like 'medication in your blood' or something just
/// better."* It is **"in your system"** rather than "in your blood", because
/// the model is a whole-body compartment and not a plasma assay — saying blood
/// would claim a measurement nobody took.
///
/// **The confirm step is the module's safety posture made visible.**
/// `TitrationEngine` proposes a titration history from a current dose, because
/// asking somebody to re-enter six months of injections is how a feature goes
/// unused. What it must never do is let a guess become the reader's word
/// silently: the proposal is stored unconfirmed, drawn dashed, and sits behind
/// this row until they say yes.
struct MedicationSection: View {
    /// The card's timeframe, so every chart and table here obeys the picker
    /// like the rest of the screen. The first version drew a fixed ninety days
    /// whatever the picker said.
    let window: TimeInterval
    @Environment(AppModel.self) private var model
    @State private var showingStart = false
    @State private var showingLog = false

    private var days: Int { max(14, Int(window / 86_400)) }

    var body: some View {
        if let medication = model.activeMedication, let compound = medication.compound {
            let points = model.medicationCurve(days: days)
            let response = model.medicationResponse
            InsightSection(
                title: "Weight management",
                trailing: points.last.map {
                    String(format: "%.2f mg in your system", $0.level)
                },
                caveat: .none
            ) {
                overallSection(response, compound: compound)
                if !points.isEmpty {
                    Divider()
                    levelSection(points: points, compound: compound)
                    Divider()
                    responseSection
                }
                if response.byDose.count > 1 {
                    Divider()
                    doseTable(response.byDose)
                }
                if !response.bySite.isEmpty {
                    Divider()
                    siteTable(response.bySite)
                }
                if !model.sideEffectTally.isEmpty {
                    Divider()
                    sideEffectSection
                }
                if model.unconfirmedDoseCount > 0 {
                    confirmRow(count: model.unconfirmedDoseCount)
                }
                doseRow(compound: compound)
            }
        } else {
            InsightSection(title: "Weight management", trailing: nil, caveat: .none) {
                Text("If you're taking a GLP-1 medication, logging it lets the app draw how much is still in your system between doses and read your weight trend against it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set up medication") { showingStart = true }
                    .font(.caption.weight(.medium))
            }
            .sheet(isPresented: $showingStart) { MedicationSetupSheet() }
        }
    }

    // MARK: - Since you started

    /// The four figures Shotsy leads with. The level itself moved to its own
    /// sub-section below — it is a different quantity from "what has changed
    /// since you started", and it was sharing this heading's one figure slot.
    private func overallSection(_ response: MedicationResponse.Analysis,
                                compound: GLPCompound) -> some View {
        NestedInsightSection(
            title: "Since you started",
            trailing: nil,
            // Spelt out rather than `.none`: a bare `.none` in a position the
            // compiler could read as `Optional` is a well-worn way to get a
            // confusing diagnostic, and `SectionCaveat.none` is a real answer
            // here, not an absent one.
            caveat: response.overall == nil ? SectionCaveat.none : .doseAttribution
        ) {
            if let overall = response.overall {
                // A fixed-column grid rather than a wrapping stack: four figures
                // that must line up under each other when the words beneath
                // them are different lengths.
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        figure(String(format: "%+.2f kg", overall.totalChange), "Total change")
                        figure(String(format: "%+.1f%%", overall.percentChange), "Percent")
                    }
                    GridRow {
                        figure(String(format: "%+.2f kg", overall.perWeek), "Weekly average")
                        figure(String(format: "%.1f kg", overall.latestWeight), "Now")
                    }
                }
            } else {
                Text("Once there are weigh-ins either side of a dose, this will show what changed and how fast.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(compound.displayName), \(model.activeMedication?.doses.count ?? 0) doses logged.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .gridColumnAlignment(.leading)
    }

    // MARK: - Medication in your system

    /// The decay curve on its own, in real milligrams.
    ///
    /// Separate from "Is it working" because that chart standardises everything
    /// onto one axis to compare *shapes*, and the actual number — how much is in
    /// you right now, and how far it falls before the next dose — is the thing a
    /// reader on a weekly injectable actually asks. One question per chart.
    private func levelSection(points: [ActiveCompoundPoint],
                              compound: GLPCompound) -> some View {
        NestedInsightSection(
            title: "Medication in your system",
            trailing: points.last.map { String(format: "%.2f mg", $0.level) },
            caveat: .none
        ) {
            MedicationCurveChart(points: points, compound: compound, window: window)
        }
    }

    // MARK: - Is it working

    @ViewBuilder private var responseSection: some View {
        let series = model.medicationOverlay(days: days)
        NestedInsightSection(title: "Is it working", trailing: nil, caveat: .none) {
            if series.count < 2 {
                Text("Needs your weight recorded across at least a couple of days in this window to draw against the dose.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MedicationResponseChart(series: series, window: window)
            }
        }
    }

    // MARK: - The tables

    private func doseTable(_ rows: [MedicationResponse.Group]) -> some View {
        NestedInsightSection(title: "By dose", trailing: nil, caveat: .doseAttribution) {
            table(rows, first: "Dose")
        }
    }

    private func siteTable(_ rows: [MedicationResponse.Group]) -> some View {
        NestedInsightSection(title: "By injection site", trailing: nil,
                             caveat: .doseAttribution) {
            table(rows, first: "Site")
            Text("Sites are recorded, not compared: rotating them is about the skin, and any difference here is far more likely to be which weeks you happened to inject where.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One table shape for both breakdowns.
    ///
    /// A `Grid` so the numbers align down the columns whatever the labels do —
    /// four `HStack`s with `Spacer`s put every row's figures somewhere
    /// different, which is the thing that makes a table unreadable.
    private func table(_ rows: [MedicationResponse.Group], first: String) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text(first)
                Text("Jabs").gridColumnAlignment(.trailing)
                Text("Days").gridColumnAlignment(.trailing)
                Text("Change").gridColumnAlignment(.trailing)
                Text("Per week").gridColumnAlignment(.trailing)
            }
            .font(.caption2).foregroundStyle(.secondary)
            Divider()
            ForEach(rows) { row in
                GridRow {
                    Text(row.label).font(.caption).lineLimit(1)
                    Text("\(row.doseCount)").font(.caption).monospacedDigit()
                    Text("\(row.days)").font(.caption).monospacedDigit()
                    Text(row.totalChange == 0 ? "—"
                         : String(format: "%+.2f", row.totalChange))
                        .font(.caption.weight(.medium)).monospacedDigit()
                    Text(row.perWeek == 0 ? "—" : String(format: "%+.2f", row.perWeek))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Side effects

    private var sideEffectSection: some View {
        NestedInsightSection(title: "Side effects", trailing: nil, caveat: .none) {
            ForEach(model.sideEffectTally.prefix(5)) { tally in
                HStack(alignment: .firstTextBaseline) {
                    Text(tally.name).font(.caption)
                    Spacer(minLength: 8)
                    Text(String(format: "%.1f/10", tally.averageSeverity))
                        .font(.caption.weight(.medium)).monospacedDigit()
                    Text("· \(tally.occurrences)×")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text("Worst average first, not most frequent — three bad days matter more than eleven mild ones, and a list ordered by count buries the row worth reading.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Confirming and logging

    private func confirmRow(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("\(count) earlier \(count == 1 ? "dose" : "doses") worked out, not logged")
                .font(.caption.weight(.medium))
            Text("The app stepped your dose back through the standard schedule to fill in the months before you started logging. These are an estimate — the dashed part of the line above — until you say they're right.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("That's right") { model.confirmInferredDoses() }
                Button("Remove them", role: .destructive) { model.discardInferredDoses() }
            }
            .font(.caption.weight(.medium))
        }
    }

    private func doseRow(compound: GLPCompound) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Button("Log a dose") { showingLog = true }
                .font(.caption.weight(.medium))
        }
        .sheet(isPresented: $showingLog) { DoseEntrySheet(compound: compound) }
    }
}

/// Starting a regimen. Deliberately asks for the current dose and a start date
/// and nothing else — everything between them is what the titration engine is
/// for, and the reader confirms it afterwards rather than typing it.
struct MedicationSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var compound: GLPCompound = .tirzepatide
    @State private var dose: Double = 2.5
    @State private var startedOn = Date().addingTimeInterval(-90 * 86_400)

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    Picker("Compound", selection: $compound) {
                        ForEach(GLPCompound.allCases) { candidate in
                            Text(candidate.displayName).tag(candidate)
                        }
                    }
                    Text(compound.brandNames.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Where you are now") {
                    Picker("Current dose", selection: $dose) {
                        ForEach(compound.titrationLadder, id: \.self) { step in
                            Text(String(format: "%g mg", step)).tag(step)
                        }
                    }
                    DatePicker("Started", selection: $startedOn,
                               in: ...Date(), displayedComponents: .date)
                }
                Section {
                    Text("The app will suggest the doses you were probably on before today, stepping back through the standard schedule. You'll be asked to confirm or remove them — nothing is assumed. This is a record of what you tell it, not medical advice, and it will never suggest changing your dose.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.startMedication(compound: compound, brandName: nil,
                                              currentDose: dose, startedOn: startedOn)
                        dismiss()
                    }
                }
            }
            .onChange(of: compound) { _, new in
                if !new.titrationLadder.contains(dose) { dose = new.titrationLadder[0] }
            }
        }
    }
}

struct DoseEntrySheet: View {
    let compound: GLPCompound
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var dose: Double
    @State private var takenAt = Date()
    /// Empty means "not recorded", which stays a real answer — a site the
    /// reader did not note is not a site to guess at.
    @State private var site = ""

    init(compound: GLPCompound) {
        self.compound = compound
        _dose = State(initialValue: compound.titrationLadder.first ?? 2.5)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Dose", selection: $dose) {
                    ForEach(compound.titrationLadder, id: \.self) { step in
                        Text(String(format: "%g mg", step)).tag(step)
                    }
                }
                DatePicker("Taken", selection: $takenAt, in: ...Date())
                Section {
                    Picker("Site", selection: $site) {
                        Text("Not recorded").tag("")
                        ForEach(model.knownInjectionSites, id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("The sites offered are the ones already in your record, so a dose you log here groups with the ones imported from Shotsy rather than starting a second name for the same place.")
                }
            }
            .navigationTitle("Log a dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.logDose(dose, at: takenAt,
                                      site: site.isEmpty ? nil : site)
                        dismiss()
                    }
                }
            }
        }
    }
}
