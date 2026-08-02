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
    @State private var query = ""

    /// Identified by its title, not by a fresh `UUID()`.
    ///
    /// Searching rebuilds these groups on every keystroke, and a `UUID()`
    /// default meant every rebuilt group was a *different* row to `ForEach` —
    /// so the whole list tore down and re-created itself per character typed.
    /// The title is the group's identity and always was.
    private struct MetricGroup: Identifiable {
        var id: String { title }
        let title: String
        let metrics: [MetricType]
    }

    /// Fixed category order; only metrics that actually have samples are shown.
    ///
    /// **Generated from `MetricType.dataCategory`, not hand-written.** The old
    /// literal array had already dropped sleep latency and vascular age — real
    /// metrics with data, absent from this screen because adding a `MetricType`
    /// and listing it here were two steps. Now a new connector's metric appears
    /// automatically once it declares a category, which the compiler forces.
    private static let categories: [(String, [MetricType])] =
        MetricDataCategory.listed.map { ($0.rawValue, MetricType.metrics(in: $0)) }

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

    // MARK: - Search

    /// **Search is why this tab is usable at all now.** It lists every metric
    /// with data, every cuff reading, the substance log, the regimen, side
    /// effects *and* the whole unmodelled catalogue — which for this reader is
    /// several hundred rows — so "where is my resting heart rate" was a scroll.
    ///
    /// It matches the domain's own name as well as the row's, so typing
    /// "medication" narrows to that section rather than to nothing: the section
    /// headings are the vocabulary a reader has actually seen.
    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ candidates: String...) -> Bool {
        guard !trimmed.isEmpty else { return true }
        return candidates.contains {
            $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Groups narrowed to the query. A group whose *title* matches keeps all of
    /// its metrics — searching "sleep" wants the sleep section, not only the
    /// four metrics with "sleep" in their name.
    private var filteredGroups: [MetricGroup] {
        guard !trimmed.isEmpty else { return groups }
        return groups.compactMap { group in
            if matches(group.title, DataDomain.metrics.title) { return group }
            let hits = group.metrics.filter { matches($0.displayName) }
            return hits.isEmpty ? nil : MetricGroup(title: group.title, metrics: hits)
        }
    }

    private var filteredOtherGroups: [RawMetricGroup] {
        guard !trimmed.isEmpty else { return otherGroups }
        if matches(DataDomain.unmodelled.title, DataDomain.unmodelled.summary) {
            return otherGroups
        }
        // The raw identifier as well as the display name: "HKQuantityType…" is
        // what an export shows, and this screen is where those get looked up.
        return otherGroups.filter { matches($0.displayName, $0.id) }
    }

    private var filteredSideEffects: [SideEffectRecord] {
        let all = model.sideEffects
        if trimmed.isEmpty || matches(DataDomain.sideEffects.title) { return all }
        return all.filter { matches($0.name) }
    }

    /// Whether a domain has anything to show for the current query.
    ///
    /// Exhaustive, like `section(for:)` — a new `DataDomain` has to say how it
    /// answers a search, and "it doesn't" is a decision somebody makes rather
    /// than a row that quietly never appears.
    private func isVisible(_ domain: DataDomain) -> Bool {
        switch domain {
        case .metrics:
            return !filteredGroups.isEmpty
        case .bloodPressure:
            return !bloodPressure.isEmpty
                && matches(domain.title, "blood pressure", "systolic", "diastolic", "mmHg")
        case .substances:
            return !model.substanceEvents.isEmpty
                && (matches(domain.title, "cardiovascular load")
                    || model.substanceEvents.contains { matches($0.substance.displayName) })
        case .medication:
            guard let medication = model.activeMedication, !medication.doses.isEmpty else {
                return false
            }
            return matches(domain.title, "dose", "injection",
                           medication.brandName ?? "",
                           medication.compound?.displayName ?? "")
        case .sideEffects:
            return !filteredSideEffects.isEmpty
        case .derivedScores:
            return model.results.contains { $0.score != nil }
                && (matches(domain.title, "score", "estimate", "risk", "heart age")
                    || model.results.contains { matches($0.title) })
        case .unmodelled:
            return !filteredOtherGroups.isEmpty
        }
    }

    private var visibleDomains: [DataDomain] {
        DataDomain.allCases.filter { isVisible($0) }
    }

    /// The substance log's own row in the Data tab.
    ///
    /// Opens the read-only `SubstanceDataView`, not the *add* page. It used to
    /// open `SubstanceLogView` — the logging screen — so "view your data" and
    /// "add data" were the same tap, which is the inconsistency the convention
    /// (`DomainDataScaffold`) removes: every domain row opens its data page, and
    /// adding is a separate gesture.
    @ViewBuilder private var substanceSection: some View {
        if !model.substanceEvents.isEmpty {
            Section("Substances") {
                NavigationLink {
                    SubstanceDataView()
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
                // Computed once per body pass. Each `isVisible` call reaches
                // the store for the regimen, and asking twice — once for the
                // empty check and once for the loop — doubled that on every
                // keystroke.
                let visible = visibleDomains
                if groups.isEmpty && otherGroups.isEmpty && bloodPressure.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "waveform.path.ecg",
                        description: Text("Connect Apple Health or a device in Settings, then pull to refresh."))
                } else if visible.isEmpty {
                    // Only reachable with a query — every domain being empty
                    // without one is the branch above.
                    ContentUnavailableView.search(text: trimmed)
                } else {
                    List {
                        // **Exhaustive over `DataDomain`, and that is the
                        // point.** This screen is the app's answer to "what do
                        // you know about me", and it kept quietly failing to be
                        // complete because each section was hand-written and
                        // completeness relied on somebody remembering. A new
                        // kind of data now fails to compile here until it has a
                        // section. See `DataDomain`.
                        //
                        // Filtered by the search, but still walked in
                        // `DataDomain` order: search narrows this screen, it
                        // never reorders it, so a section stays where the
                        // reader last saw it.
                        ForEach(visible) { domain in
                            section(for: domain)
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .searchable(text: $query, prompt: "Search your data")
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
        case .derivedScores: derivedScoreSection
        case .unmodelled: otherDataSection
        }
    }

    /// What the app worked out, as data — each card's score and the clinical
    /// estimates behind it. The user's ask: *"I want any derived data being
    /// stored in the data tab, eg your ASCVD or SCORE2 etc scores."* They were
    /// visible only as a number on a card, with no list and no history here.
    @ViewBuilder private var derivedScoreSection: some View {
        let scored = model.results.filter { $0.score != nil }
        if !scored.isEmpty {
            Section {
                NavigationLink {
                    DerivedScoreDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Card scores & estimates")
                            Spacer()
                            Text("\(scored.count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text("Worked out by this app, not measured")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(DataDomain.derivedScores.title)
            } footer: {
                Text(DataDomain.derivedScores.summary)
            }
        }
    }

    @ViewBuilder private var metricSections: some View {
        ForEach(filteredGroups) { group in
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

    /// The medication regimen: how much is in you now, and how many doses back it.
    ///
    /// Opens `MedicationDataView` — the level curve and the dated dose list —
    /// rather than the Body Composition card it used to jump to. Landing the
    /// reader on a whole insight card when they tapped "Medication" in a data
    /// browser was the wrong altitude; the card is where the score lives, this
    /// is where the doses do.
    @ViewBuilder private var medicationSection: some View {
        if let medication = model.activeMedication, let compound = medication.compound,
           !medication.doses.isEmpty {
            Section {
                NavigationLink {
                    MedicationDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(medication.brandName ?? compound.displayName)
                            Spacer()
                            Text(String(format: "%.2f mg in your system",
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

    /// Side effects the reader recorded — imported from Shotsy or entered by
    /// hand.
    ///
    /// One tappable row into `SideEffectDataView`, like every other domain.
    /// It used to be a static inline list of up to six rows that opened nothing
    /// — no sub-page, no way to see the seventh, and a second one logged from
    /// the `+` menu could not even reach it. The row shows the newest and the
    /// count; the page holds the rest.
    @ViewBuilder private var sideEffectSection: some View {
        let effects = filteredSideEffects
        if !effects.isEmpty {
            Section {
                NavigationLink {
                    SideEffectDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        if let latest = effects.first {
                            HStack {
                                Text(latest.name)
                                Spacer()
                                Text("\(latest.severity)/10")
                                    .foregroundStyle(.secondary).monospacedDigit()
                                Text("· \(latest.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Text(effects.count == 1
                             ? "1 recorded"
                             : "\(effects.count) recorded")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(DataDomain.sideEffects.title)
            } footer: {
                Text(DataDomain.sideEffects.summary)
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
        if !filteredOtherGroups.isEmpty {
            Section {
                ForEach(filteredOtherGroups) { group in
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
