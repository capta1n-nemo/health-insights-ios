import SwiftUI
import Charts
import InsightKit

/// The consolidated blood-pressure vital — Apple-Health-inspired: one screen with
/// a systolic + diastolic chart, calibration status, and the full dated list of
/// readings merged from everywhere (in-app, Apple Health, Withings). Grounding
/// uses only readings from the last 30 days.
struct BloodPressureLogView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var timeframe: Timeframe = .month

    private var readings: [BloodPressureEstimator.Reading] { model.bloodPressureReadings }
    private var status: BloodPressureEstimator.CalibrationStatus { model.bloodPressureCalibration }

    /// Split the history so recent readings (the ones grounding the estimate)
    /// are visible at a glance, while all history is still listed.
    private var recent: [BloodPressureEstimator.Reading] {
        readings.filter { Date().timeIntervalSince($0.date) <= BloodPressureEstimator.maintenanceWindow }
    }
    private var earlier: [BloodPressureEstimator.Reading] {
        readings.filter { Date().timeIntervalSince($0.date) > BloodPressureEstimator.maintenanceWindow }
    }
    private var chartReadings: [BloodPressureEstimator.Reading] {
        guard let start = timeframe.startDate() else { return readings }
        return readings.filter { $0.date >= start }
    }

    var body: some View {
        List {
            if !readings.isEmpty {
                Section {
                    Picker("Timeframe", selection: $timeframe) {
                        ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    bpChart
                }
            }

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
                Text("Grounding uses only readings from the last 30 days: log \(BloodPressureEstimator.initialCalibrationReadings) to ground the estimate, and because readings stop counting after 30 days you'll need to add fresh ones over time. Readings already in Apple Health count automatically.")
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

    @ViewBuilder private var bpChart: some View {
        let data = chartReadings
        if data.isEmpty {
            Text("No readings in \(timeframe.longLabel.lowercased()).")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Chart(data) { r in
                LineMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic),
                         series: .value("Reading", "Systolic"))
                    .foregroundStyle(Theme.sourceColor(0))
                PointMark(x: .value("Date", r.date), y: .value("mmHg", r.systolic))
                    .foregroundStyle(Theme.sourceColor(0)).symbolSize(20)
                LineMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic),
                         series: .value("Reading", "Diastolic"))
                    .foregroundStyle(Theme.sourceColor(1))
                PointMark(x: .value("Date", r.date), y: .value("mmHg", r.diastolic))
                    .foregroundStyle(Theme.sourceColor(1)).symbolSize(20)
            }
            .frame(height: 180)
            HStack(spacing: 16) {
                legendDot("Systolic", Theme.sourceColor(0))
                legendDot("Diastolic", Theme.sourceColor(1))
                Spacer()
            }
            .font(.caption)
        }
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
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

/// A compact "N of 5 in the last 30 days" progress row for BP grounding.
private struct CalibrationProgress: View {
    let status: BloodPressureEstimator.CalibrationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !status.isGrounded {
                ProgressView(value: Double(status.recentReadings),
                             total: Double(status.required))
                    .tint(Theme.accent)
            }
            HStack(spacing: 6) {
                Image(systemName: status.isGrounded ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(status.isGrounded ? Theme.good : Theme.accent)
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
