import SwiftUI
import Charts
import InsightKit

/// The Data tab — the "everything" browser for people who want to dig.
///
/// Called Vitals until 2026-08-02, and renamed because it had stopped being
/// true: it holds the substance log, the medication regimen, side effects and
/// the raw imported catalogue as well as the vitals, and `DataDomain` exists
/// precisely so that list keeps growing. It also moved to third, at the user's
/// request — Today, Insights, Data, Settings reads as now, what it means, and
/// then everything underneath.
///
/// Lists every metric that has data, grouped, with its latest value and how many
/// sources report it; tapping opens the multi-source overlay in `MetricDetailView`.
struct DataTabView: View {
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
                                 .heartRateRecovery, .atrialFibrillationBurden,
                                 .vo2Max, .respiratoryRate, .oxygenSaturation,
                                 .peripheralPerfusionIndex]),
        ("Body", [.bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
                  .boneMass, .bodyWaterPercentage, .height, .bloodGlucose]),
        ("Sleep & recovery", [.sleepDurationHours, .sleepOnset, .sleepEfficiency,
                              .sleepDeepMinutes, .sleepRemMinutes, .bodyTemperature,
                              .skinTemperature, .skinTemperatureDeviation,
                              .dayStrain]),
        ("Activity & mobility", [.stepCount, .activeEnergyBurned, .exerciseMinutes,
                                 .walkingSteadiness, .walkingAsymmetry])
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

    /// The substance log's own row in Vitals.
    ///
    /// It was reachable only from the Today toolbar, which meant the one screen
    /// listing everything the app measures about you didn't mention it. Shows the
    /// current decayed load and the most recent entry, and opens the log.
    @ViewBuilder private var substanceSection: some View {
        if !model.substanceEvents.isEmpty {
            Section("Substances") {
                NavigationLink {
                    SubstanceLogView()
                } label: {
                    let load = SubstanceLoad.load(events: model.substanceEvents, at: Date())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Cardiovascular load")
                            Spacer()
                            Text("\(Int(load.rounded())) · \(SubstanceResponseAnalyzer.band(for: load))")
                                .foregroundStyle(.secondary)
                        }
                        if let latest = model.substanceEvents.first {
                            Text("Last logged: \(latest.substance.displayName.lowercased()), \(latest.timestamp.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty && otherGroups.isEmpty && bloodPressure.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "waveform.path.ecg",
                        description: Text("Connect Apple Health or a device in Settings, then pull to refresh."))
                } else {
                    List {
                        // **Exhaustive over `DataDomain`, and that is the
                        // point.** This screen is the app's answer to "what do
                        // you know about me", and it kept quietly failing to be
                        // complete because each section was hand-written and
                        // completeness relied on somebody remembering. A new
                        // kind of data now fails to compile here until it has a
                        // section. See `DataDomain`.
                        ForEach(DataDomain.allCases) { domain in
                            section(for: domain)
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .refreshable { await model.refresh() }
        }
    }

    /// One section per kind of data the app holds.
    ///
    /// A `switch` rather than a list of views: adding a `DataDomain` case
    /// without a section here is a compile error, which is the whole mechanism
    /// keeping this screen honest.
    @ViewBuilder private func section(for domain: DataDomain) -> some View {
        switch domain {
        case .metrics: metricSections
        case .bloodPressure: bloodPressureSection
        case .substances: substanceSection
        case .medication: medicationSection
        case .sideEffects: sideEffectSection
        case .unmodelled: otherDataSection
        }
    }

    @ViewBuilder private var metricSections: some View {
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
    }

    /// The medication regimen: what is on board now, and how many doses back it.
    @ViewBuilder private var medicationSection: some View {
        if let medication = model.activeMedication, let compound = medication.compound,
           !medication.doses.isEmpty {
            Section {
                NavigationLink {
                    InsightDetailView(insightID: .bodyComposition)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(medication.brandName ?? compound.displayName)
                            Spacer()
                            Text(String(format: "%.2f mg on board",
                                        PharmacokineticsModel.level(
                                            at: Date(),
                                            doses: medication.doses.map(\.administered),
                                            compound: compound)))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        if let latest = medication.doses.map(\.takenAt).max() {
                            Text("\(medication.doses.count) doses · last \(latest.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text(DataDomain.medication.title)
            }
        }
    }

    /// Side effects the reader recorded — imported from Shotsy today.
    @ViewBuilder private var sideEffectSection: some View {
        let effects = model.sideEffects
        if !effects.isEmpty {
            Section {
                ForEach(effects.prefix(6), id: \.persistentModelID) { effect in
                    HStack {
                        Text(effect.name)
                        Spacer()
                        Text("\(effect.severity)/10")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Text("· \(effect.date.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(DataDomain.sideEffects.title)
            } footer: {
                Text(effects.count > 6
                     ? "The 6 most recent of \(effects.count). \(DataDomain.sideEffects.summary)"
                     : DataDomain.sideEffects.summary)
            }
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
                        // "readings", spelt out — a bare "· 46" in the slot
                        // where every other row shows a relative time reads
                        // as a mystery number, not a count.
                        Text("· \(bloodPressure.count) readings").font(.caption2).foregroundStyle(.tertiary)
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
                                Text(latest.formattedValue)
                                    .foregroundStyle(.secondary).monospacedDigit()
                                    .lineLimit(1).truncationMode(.tail)
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

    /// The preview shows the single newest reading — not the average of each
    /// source's latest, which reads like a long-run figure when sources last
    /// reported at very different times. Anything not from today is dated, so a
    /// stale number can't be mistaken for a current one. Cumulative metrics
    /// show the newest day's total instead (see `VitalsSummary.displayValue`).
    ///
    /// `detailedString` renders the unit only when the value doesn't already
    /// carry it — appending `metric.unit` by hand here is what shipped
    /// "99% %" and "1h 19m min".
    @ViewBuilder private func row(for metric: MetricType) -> some View {
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

    /// One plottable reading. A named type rather than a tuple so Swift Charts'
    /// generics have something concrete and `Identifiable` to work with.
    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    /// Thinned for plotting — some imported identifiers carry tens of thousands
    /// of readings, and the extra marks are invisible at chart resolution.
    /// Numeric readings only: a text field has nothing to plot.
    private var charted: [Point] {
        let all = samples.compactMap { s in
            s.numericValue.map { Point(id: s.id, date: s.start, value: $0) }
        }
        let limit = 300
        guard all.count > limit else { return all }
        let stride = Double(all.count - 1) / Double(limit - 1)
        return (0..<limit).map { all[Int((Double($0) * stride).rounded())] }
    }

    /// For a categorical field (Oura's resilience level, a sleep stage), the
    /// useful summary is which states occurred and how often — a line chart of
    /// text is meaningless.
    private var stateCounts: [(state: String, count: Int)] {
        let texts = samples.compactMap { s -> String? in
            if case .text(let v) = s.value { return v }
            return nil
        }
        return Dictionary(grouping: texts, by: { $0 })
            .map { (state: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        List {
            Section {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                if charted.count > 1 {
                    // An explicit hue: without one Swift Charts supplies its
                    // own blue, which is off the validated palette every other
                    // chart in the app draws from.
                    Chart(charted) { point in
                        LineMark(x: .value("Time", point.date),
                                 y: .value(group.unit, point.value))
                            .foregroundStyle(Theme.paletteColour(slot: 0))
                            .interpolationMethod(.linear)
                        PointMark(x: .value("Time", point.date),
                                  y: .value(group.unit, point.value))
                            .foregroundStyle(Theme.paletteColour(slot: 0))
                            .symbolSize(20)
                    }
                    .frame(height: 160)
                }
            } header: {
                Text(group.displayName)
            } footer: {
                Text("Identifier: \(group.id)\nSources: \(group.sources.sorted().joined(separator: ", "))")
            }

            // Text fields get a state tally instead of a chart.
            if !stateCounts.isEmpty {
                Section("States") {
                    ForEach(stateCounts, id: \.state) { entry in
                        HStack {
                            Text(entry.state)
                            Spacer()
                            Text("\(entry.count)×")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }

            Section("Readings · \(samples.count)") {
                ForEach(samples) { s in
                    HStack {
                        Text(s.formattedValue)
                            .monospacedDigit()
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
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
}
