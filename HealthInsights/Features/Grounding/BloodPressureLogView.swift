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

    private var readings: [BloodPressureEstimator.Reading] { model.bloodPressureReadings }
    private var status: BloodPressureEstimator.CalibrationStatus { model.bloodPressureCalibration }

    /// Split the history so recent readings (the ones keeping the estimate
    /// grounded) are visible at a glance, while all history is still listed.
    private var recent: [BloodPressureEstimator.Reading] {
        readings.filter { Date().timeIntervalSince($0.date) <= BloodPressureEstimator.maintenanceWindow }
    }
    private var earlier: [BloodPressureEstimator.Reading] {
        readings.filter { Date().timeIntervalSince($0.date) > BloodPressureEstimator.maintenanceWindow }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add a reading", systemImage: "plus.circle.fill")
                }
                CalibrationProgress(status: status)
            } header: {
                Text("Calibration")
            } footer: {
                Text("It takes \(BloodPressureEstimator.initialCalibrationReadings) cuff readings to calibrate the estimate, then about \(BloodPressureEstimator.maintenanceReadingsPerMonth) a month to keep it grounded. Readings already in Apple Health count automatically.")
            }

            if readings.isEmpty {
                Section {
                    Text("No readings yet. Add one from a cuff, or log some in Apple Health — they'll show here automatically with their dates.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                if !recent.isEmpty {
                    Section {
                        ForEach(recent) { readingRow($0) }
                    } header: {
                        Text("Last 30 days · \(recent.count)")
                    }
                }
                if !earlier.isEmpty {
                    Section {
                        ForEach(earlier) { readingRow($0) }
                    } header: {
                        Text("Earlier · \(earlier.count)")
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

    private func readingRow(_ r: BloodPressureEstimator.Reading) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(r.systolic.rounded()))/\(Int(r.diastolic.rounded())) mmHg")
                    .font(.body.weight(.semibold))
                Text(r.category)
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

/// A compact "N of 5" (or "grounded this month") progress row for BP calibration.
private struct CalibrationProgress: View {
    let status: BloodPressureEstimator.CalibrationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !status.initialComplete {
                ProgressView(value: Double(status.totalReadings),
                             total: Double(BloodPressureEstimator.initialCalibrationReadings))
                    .tint(Theme.accent)
            }
            HStack(spacing: 6) {
                Image(systemName: status.isFresh ? "checkmark.seal.fill"
                      : (status.initialComplete ? "clock.badge.exclamationmark" : "target"))
                    .foregroundStyle(status.isFresh ? Theme.good : Theme.accent)
                Text(status.guidance)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
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
