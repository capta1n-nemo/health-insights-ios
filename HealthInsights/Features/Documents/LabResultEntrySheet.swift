import SwiftUI
import InsightKit

/// **Type the numbers in.** Backlog `Q7`, and the route the reader named first:
/// *"both? What do you mean? We should be able to accept all of these."*
///
/// The floor is lipids and HbA1c, because those are the analytes a card already
/// scores. The ceiling is everything else a report prints, entered by naming the
/// analyte — which is `I6`'s promise met by hand rather than by a model, and it
/// works on every device including ones that cannot run one.
///
/// ⚠️ **A typed value carries no extraction uncertainty and must not be dressed
/// with any.** `LabResult.evidence` is nil for everything this sheet produces,
/// `confidence` is `.typed`, and the badge beside it says so. The reader read the
/// paper; the app did not.
struct LabResultEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The analytes that get their own row. The floor, in the order a lipid
    /// panel prints.
    private static let floorKeys = ["total_cholesterol", "hdl_cholesterol",
                                    "ldl_cholesterol", "triglycerides", "hba1c"]

    @State private var collectedAt = Date()
    @State private var values: [String: String] = [:]
    @State private var extras: [ExtraAnalyte] = []
    @State private var savedCount: Int?

    /// One analyte the catalogue may or may not know, named by the reader.
    private struct ExtraAnalyte: Identifiable {
        let id = UUID()
        var name = ""
        var value = ""
        var unit = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Blood taken", selection: $collectedAt,
                               in: ...Date(), displayedComponents: .date)
                } footer: {
                    // The date is the collection date, not today's, and saying
                    // so matters: a report read a fortnight after the draw is
                    // filed against the wrong two weeks of everything else.
                    Text("The date the blood was taken, not the date on the report. Everything is compared against the vitals around it.")
                }

                Section {
                    ForEach(Self.floorKeys, id: \.self) { key in
                        if let entry = LabAnalyteCatalog.entry(forKey: key) {
                            HStack {
                                Text(entry.displayName)
                                Spacer()
                                TextField("—", text: binding(for: key))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 90)
                                Text(entry.canonicalUnit)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("The usual ones")
                } footer: {
                    Text("Leave anything blank that your report does not print. Cholesterol and HDL also update your profile, which is what the heart-risk estimates read.")
                }

                Section {
                    ForEach($extras) { $extra in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Analyte, as your report names it", text: $extra.name)
                            HStack {
                                TextField("Value", text: $extra.value)
                                    .keyboardType(.decimalPad)
                                TextField("Unit", text: $extra.unit)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    Button {
                        extras.append(ExtraAnalyte())
                    } label: {
                        Label("Add another analyte", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Anything else on your report")
                } footer: {
                    // Honest about the limit of what typing an unknown analyte
                    // buys: it is stored and shown, and nothing scores it.
                    Text("Ferritin, TSH, vitamin D — whatever your report prints. If the app recognises the name it will convert the unit and keep the trend together; if it does not, it stores exactly what you type and says so. Nothing here is scored or interpreted.")
                }

                if let savedCount {
                    Section {
                        Label("Saved \(savedCount) value\(savedCount == 1 ? "" : "s").",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.good)
                    }
                }
            }
            .navigationTitle("Blood test results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(built().isEmpty)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    /// Everything the form currently describes, as results.
    ///
    /// Built rather than accumulated, so the Save button's enabled state and
    /// what Save actually writes can never disagree.
    private func built() -> [LabResult] {
        var results: [LabResult] = []
        for key in Self.floorKeys {
            guard let entry = LabAnalyteCatalog.entry(forKey: key),
                  let text = values[key], !text.isEmpty,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                  entry.plausible.contains(value) else { continue }
            results.append(LabResult(analyte: entry.analyte, value: value,
                                     unit: entry.canonicalUnit,
                                     collectedAt: collectedAt, collectedAtIsExact: true,
                                     source: .typed, evidence: nil,
                                     isConfirmedByReader: true))
        }
        for extra in extras {
            let name = extra.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  let value = Double(extra.value.replacingOccurrences(of: ",", with: "."))
            else { continue }
            let unit = extra.unit.trimmingCharacters(in: .whitespaces)
            // A name the catalogue knows joins the existing trend and converts;
            // one it does not is stored under the reader's own words with the
            // unit exactly as they typed it. Never converted on a guess.
            if let entry = LabAnalyteCatalog.match(label: name) {
                let converted = unit.isEmpty
                    ? value
                    : (LabAnalyteCatalog.convert(value, from: unit, for: entry) ?? value)
                let storedUnit = unit.isEmpty
                    ? entry.canonicalUnit
                    : (LabAnalyteCatalog.convert(value, from: unit, for: entry) != nil
                       ? entry.canonicalUnit : unit)
                results.append(LabResult(analyte: entry.analyte, value: converted,
                                         unit: storedUnit,
                                         collectedAt: collectedAt, collectedAtIsExact: true,
                                         source: .typed, evidence: nil,
                                         isConfirmedByReader: true))
            } else {
                results.append(LabResult(analyte: .unknown(label: name,
                                                           unit: unit.isEmpty ? nil : unit),
                                         value: value, unit: unit,
                                         collectedAt: collectedAt, collectedAtIsExact: true,
                                         source: .typed, evidence: nil,
                                         isConfirmedByReader: true))
            }
        }
        return results
    }

    private func save() {
        let results = built()
        guard !results.isEmpty else { return }
        model.saveLabResults(results)
        savedCount = results.count
        DiagnosticsLog.shared.ok("Import", "Typed \(results.count) lab value(s)")
        dismiss()
    }
}
