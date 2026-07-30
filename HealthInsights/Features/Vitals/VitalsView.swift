import SwiftUI
import Charts
import InsightKit

/// The Vitals tab — the "everything" data browser for people who want to dig.
/// Lists every metric that has data, grouped, with its latest value and how many
/// sources report it; tapping opens the multi-source overlay in `MetricDetailView`.
struct VitalsView: View {
    @Environment(AppModel.self) private var model

    private struct MetricGroup: Identifiable {
        let id = UUID()
        let title: String
        let metrics: [MetricType]
    }

    /// Fixed category order; only metrics that actually have samples are shown.
    private static let categories: [(String, [MetricType])] = [
        ("Heart & circulation", [.heartRate, .restingHeartRate, .walkingHeartRateAverage,
                                 .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
                                 .vo2Max, .respiratoryRate, .oxygenSaturation]),
        ("Body", [.bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
                  .boneMass, .bodyWaterPercentage, .height]),
        ("Sleep & recovery", [.sleepDurationHours, .bodyTemperature,
                              .skinTemperatureDeviation, .dayStrain]),
        ("Activity", [.stepCount, .activeEnergyBurned])
    ]

    private var groups: [MetricGroup] {
        // Keyed off the cached summaries rather than remapping every sample.
        let present = model.vitalsSummaries
        return Self.categories.compactMap { title, metrics in
            let available = metrics.filter { present[$0] != nil }
            return available.isEmpty ? nil : MetricGroup(title: title, metrics: available)
        }
    }

    private var otherGroups: [RawMetricGroup] { model.otherDataGroups }
    private var bloodPressure: [BloodPressureEstimator.Reading] { model.bloodPressureReadings }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty && otherGroups.isEmpty && bloodPressure.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "waveform.path.ecg",
                        description: Text("Connect Apple Health or a device in Settings, then pull to refresh."))
                } else {
                    List {
                        ForEach(groups) { group in
                            Section(group.title) {
                                ForEach(group.metrics, id: \.self) { metric in
                                    NavigationLink {
                                        MetricDetailView(metric: metric)
                                    } label: {
                                        row(for: metric)
                                    }
                                }
                            }
                        }
                        bloodPressureSection
                        otherDataSection
                    }
                }
            }
            .navigationTitle("Vitals")
            .refreshable { await model.refresh() }
        }
    }

    /// One consolidated Blood Pressure entry (systolic + diastolic together),
    /// Apple-Health style, opening the combined BP screen.
    @ViewBuilder private var bloodPressureSection: some View {
        if let latest = bloodPressure.first {
            Section {
                NavigationLink {
                    MetricDetailView(subject: .bloodPressure)
                } label: {
                    HStack {
                        Text("Blood Pressure")
                        Spacer()
                        Text("\(Int(latest.systolic.rounded()))/\(Int(latest.diastolic.rounded())) mmHg")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Text("· \(bloodPressure.count)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Blood pressure")
            }
        }
    }

    /// Everything imported that we don't yet model as a first-class vital, so it
    /// can be reviewed and later promoted into proper metrics/insights.
    @ViewBuilder private var otherDataSection: some View {
        if !otherGroups.isEmpty {
            Section {
                ForEach(otherGroups) { group in
                    NavigationLink {
                        OtherDataDetailView(group: group)
                    } label: {
                        HStack {
                            Text(group.displayName).lineLimit(1)
                            Spacer()
                            if let latest = group.latest {
                                Text(rawValue(latest))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            } header: {
                Text("Other data")
            } footer: {
                Text("Imported but not yet turned into insights — new HealthKit types and extra Oura/Withings fields. Tap any to review; tell me which to build into the app.")
            }
        }
    }

    private func rawValue(_ s: RawMetricSample) -> String {
        let v = abs(s.value) >= 100 ? String(format: "%.0f", s.value) : String(format: "%.1f", s.value)
        return s.unit.isEmpty ? v : "\(v) \(s.unit)"
    }

    /// The preview shows the single newest reading — not the average of each
    /// source's latest, which reads like a long-run figure when sources last
    /// reported at very different times. Anything not from today is dated, so a
    /// stale number can't be mistaken for a current one.
    @ViewBuilder private func row(for metric: MetricType) -> some View {
        let summary = model.vitalsSummaries[metric]
        HStack {
            Text(metric.displayName)
            Spacer()
            if let summary {
                Text("\(formatMetric(summary.latest.value, metric)) \(metric.unit)")
                    .foregroundStyle(.secondary).monospacedDigit()
                if let age = staleness(summary.latest.start) {
                    Text("· \(age)").font(.caption2).foregroundStyle(.tertiary)
                }
                if summary.sourceCount > 1 {
                    Text("· \(summary.sourceCount) sources")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// A short "how old is this" label, omitted entirely for today's readings.
    private func staleness(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return nil }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }
}

/// Read-only detail for one "other data" identifier: its readings over a chosen
/// timeframe, with a simple trend chart. This is the review surface for data the
/// app has imported but not yet modelled.
struct OtherDataDetailView: View {
    let group: RawMetricGroup
    @State private var timeframe: Timeframe = .month

    private var samples: [RawMetricSample] { group.samples.within(timeframe) }

    /// Thinned for plotting — some imported identifiers carry tens of thousands
    /// of readings, and the extra marks are invisible at chart resolution.
    private var charted: [RawMetricSample] {
        let limit = 300
        let all = samples
        guard all.count > limit else { return all }
        let stride = Double(all.count - 1) / Double(limit - 1)
        return (0..<limit).map { all[Int((Double($0) * stride).rounded())] }
    }

    var body: some View {
        List {
            Section {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                if samples.count > 1 {
                    Chart(charted) { s in
                        LineMark(x: .value("Time", s.start), y: .value(group.unit, s.value))
                            .interpolationMethod(.linear)
                        PointMark(x: .value("Time", s.start), y: .value(group.unit, s.value))
                            .symbolSize(20)
                    }
                    .frame(height: 160)
                }
            } header: {
                Text(group.displayName)
            } footer: {
                Text("Identifier: \(group.id)\nSources: \(group.sources.sorted().joined(separator: ", "))")
            }

            Section("Readings · \(samples.count)") {
                ForEach(samples) { s in
                    HStack {
                        Text(valueLabel(s)).monospacedDigit()
                        Spacer()
                        Text(s.start.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(group.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueLabel(_ s: RawMetricSample) -> String {
        let v = abs(s.value) >= 100 ? String(format: "%.0f", s.value) : String(format: "%.2f", s.value)
        return s.unit.isEmpty ? v : "\(v) \(s.unit)"
    }
}
