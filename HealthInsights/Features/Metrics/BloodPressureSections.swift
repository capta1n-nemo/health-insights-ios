import SwiftUI
import InsightKit

/// The consolidated blood-pressure screen: systolic and diastolic together,
/// calibration progress, and the full dated history merged from everywhere
/// (in-app, Apple Health, Withings).
///
/// Migrated out of the standalone `BloodPressureLogView` so blood pressure uses
/// the same chart plumbing as every other metric. **The grounding rules are
/// unchanged**: five readings to ground, only the last 30 days count, older
/// readings are listed but don't contribute.
struct BloodPressureSections: View {
    @Environment(AppModel.self) private var model
    @Binding var timeframe: Timeframe
    @State private var showingAdd = false
    @State private var showAllEarlier = false

    private var readings: [BloodPressureEstimator.Reading] { model.bloodPressureReadings }
    private var status: BloodPressureEstimator.CalibrationStatus { model.bloodPressureCalibration }

    private var split: (recent: [BloodPressureEstimator.Reading],
                        earlier: [BloodPressureEstimator.Reading]) {
        BloodPressureEstimator.split(readings)
    }


    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if !readings.isEmpty { chartCard }
            calibrationCard
            if readings.isEmpty { emptyCard } else { historyCard }
        }
        .sheet(isPresented: $showingAdd) {
            AddBloodPressureView { systolic, diastolic, date in
                model.logBloodPressure(systolic: systolic, diastolic: diastolic, at: date)
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                // The same component the Blood Pressure insight card draws, not
                // a second copy of it. This chart carries three separate
                // `Chart3DContent` workarounds; two copies would be two places
                // for one of them to be dropped.
                BloodPressureChart(readings: readings, timeframe: timeframe)
            }
        }
    }


    // MARK: Calibration

    private var calibrationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calibration").font(.headline)
                Button {
                    showingAdd = true
                } label: {
                    Label("Add a reading", systemImage: "plus.circle.fill")
                }
                CalibrationProgress(status: status)
                Text("Grounding uses only readings from the last 30 days. Log \(BloodPressureEstimator.initialCalibrationReadings) within 30 days to ground the estimate, then \(BloodPressureEstimator.maintenanceReadingsPerMonth) a month keeps it grounded. Readings already in Apple Health count automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var emptyCard: some View {
        Card {
            Text("No readings yet. Add one from a cuff, or log some in Apple Health — they'll show here automatically with their dates.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: History

    /// A lazy stack rather than a List, because this screen is a ScrollView of
    /// cards and a List cannot nest inside one. Older readings are paged so a
    /// long history doesn't build hundreds of rows at once.
    private var historyCard: some View {
        let parts = split
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                if !parts.recent.isEmpty {
                    Text("Last 30 days · \(parts.recent.count)").font(.headline)
                    LazyVStack(spacing: 8) {
                        ForEach(parts.recent) { readingRow($0) }
                    }
                }
                if !parts.earlier.isEmpty {
                    Divider()
                    Text("Earlier · \(parts.earlier.count)")
                        .font(.subheadline.weight(.semibold))
                    Text("Listed for reference — these no longer count towards grounding.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    LazyVStack(spacing: 8) {
                        ForEach(showAllEarlier ? parts.earlier : Array(parts.earlier.prefix(20))) {
                            readingRow($0)
                        }
                    }
                    if !showAllEarlier, parts.earlier.count > 20 {
                        Button("Show all \(parts.earlier.count)") { showAllEarlier = true }
                            .font(.footnote)
                    }
                }
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
