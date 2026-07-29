import SwiftUI
import InsightKit

/// A dated list of blood-pressure readings — the fix for the old single-value
/// input. It merges readings you log here with any blood pressure already in
/// **Apple Health** (or Withings), shows each with its date, source and
/// category, and lets you add as many as you like. The personalised estimate
/// needs at least `minimumCalibrationPoints` readings, surfaced as a progress hint.
struct BloodPressureLogView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false

    private struct Reading: Identifiable {
        let id = UUID()
        let date: Date
        let systolic: Double
        let diastolic: Double
        let source: String
    }

    /// Pair systolic + diastolic samples (from every source) by nearest time.
    private var readings: [Reading] {
        let systolic = model.series(.bloodPressureSystolic)
        let diastolic = model.series(.bloodPressureDiastolic)
        guard !systolic.isEmpty else { return [] }
        return systolic.compactMap { s -> Reading? in
            guard let d = diastolic.min(by: {
                abs($0.start.timeIntervalSince(s.start)) < abs($1.start.timeIntervalSince(s.start))
            }), abs(d.start.timeIntervalSince(s.start)) <= 2 * 3600 else { return nil }
            return Reading(date: s.start, systolic: s.value, diastolic: d.value,
                           source: s.source.displayName)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add a reading", systemImage: "plus.circle.fill")
                }
            } footer: {
                let n = readings.count
                if n < BloodPressureEstimator.minimumCalibrationPoints {
                    Text("Log \(BloodPressureEstimator.minimumCalibrationPoints - n) more reading\(BloodPressureEstimator.minimumCalibrationPoints - n == 1 ? "" : "s") to unlock the personalised estimate. Readings from Apple Health count too.")
                } else {
                    Text("You have enough readings for the personalised estimate. Keep logging to improve it.")
                }
            }

            if readings.isEmpty {
                Section {
                    Text("No readings yet. Add one from a cuff, or log some in Apple Health — they'll show here automatically.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section("Your readings") {
                    ForEach(readings) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(r.systolic.rounded()))/\(Int(r.diastolic.rounded())) mmHg")
                                    .font(.body.weight(.semibold))
                                Text(BloodPressureEstimator.category(systolic: r.systolic, diastolic: r.diastolic))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                Text(r.source).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Blood Pressure")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            AddBloodPressureView { systolic, diastolic, date in
                model.logBloodPressure(systolic: systolic, diastolic: diastolic, at: date)
            }
        }
    }
}

/// Entry sheet for a single dated reading. Plain numeric fields (no steppers) and
/// one clear Save action at the bottom.
private struct AddBloodPressureView: View {
    let onSave: (Double, Double, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var systolicText = ""
    @State private var diastolicText = ""
    @State private var date = Date()

    private var systolic: Double? {
        Double(systolicText.trimmingCharacters(in: .whitespaces))
    }
    private var diastolic: Double? {
        Double(diastolicText.trimmingCharacters(in: .whitespaces))
    }

    /// A reading is valid only when both numbers are present, in a plausible
    /// range, and systolic is above diastolic.
    private var isValid: Bool {
        guard let s = systolic, let d = diastolic else { return false }
        return (60...260).contains(s) && (30...200).contains(d) && s > d
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Systolic")
                        Spacer()
                        TextField("120", text: $systolicText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("mmHg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Diastolic")
                        Spacer()
                        TextField("80", text: $diastolicText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("mmHg").foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date())
                } footer: {
                    if let s = systolic, let d = diastolic, isValid {
                        Text("Category: \(BloodPressureEstimator.category(systolic: s, diastolic: d)). Use a real upper-arm cuff, seated and rested.")
                    } else {
                        Text("Enter the two numbers your cuff shows (the higher one is systolic). Use a real upper-arm cuff, seated and rested.")
                    }
                }

                Section {
                    Button {
                        if let s = systolic, let d = diastolic { onSave(s, d, date); dismiss() }
                    } label: {
                        Text("Save reading").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
            .navigationTitle("Add reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
