import SwiftUI
import InsightKit

/// Body Composition's medication picture: what is on board, what was logged,
/// and — where the app filled a history in — a plain request to confirm it.
///
/// **The confirm step is the module's safety posture made visible.**
/// `TitrationEngine` proposes a titration history from a current dose, because
/// asking somebody to re-enter six months of injections is how a feature goes
/// unused. What it must never do is let a guess become the reader's word
/// silently: the proposal is stored unconfirmed, drawn dashed, and sits behind
/// this row until they say yes.
struct MedicationSection: View {
    @Environment(AppModel.self) private var model
    @State private var showingStart = false
    @State private var showingLog = false

    var body: some View {
        if let medication = model.activeMedication, let compound = medication.compound {
            let points = model.medicationCurve()
            NestedInsightSection(
                title: "Medication on board",
                trailing: points.last.map { String(format: "%.2f mg", $0.level) },
                caveat: .none
            ) {
                if points.isEmpty {
                    Text("No doses logged yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    MedicationCurveChart(points: points, compound: compound)
                }
                if model.unconfirmedDoseCount > 0 {
                    confirmRow(count: model.unconfirmedDoseCount)
                }
                doseRow(compound: compound)
            }
        } else {
            NestedInsightSection(title: "Medication on board", trailing: nil,
                                 caveat: .none) {
                Text("If you're taking a GLP-1 medication, logging it lets the app draw how much is still active between doses and read your weight trend against it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set up medication") { showingStart = true }
                    .font(.caption.weight(.medium))
            }
            .sheet(isPresented: $showingStart) { MedicationSetupSheet() }
        }
    }

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
            }
            .navigationTitle("Log a dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.logDose(dose, at: takenAt)
                        dismiss()
                    }
                }
            }
        }
    }
}
