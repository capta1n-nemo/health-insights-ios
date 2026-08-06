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
    /// The `+`, same one Today and Insights carry. This is the screen that says
    /// what the app knows about you, so it is the likeliest place to notice
    /// something missing — and it had no way to add it.
    @State private var activeInput: InputKind?

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
        /// Carried rather than reconstructed from `title`. A round trip through
        /// the raw value works today and is a silent bug the day a title gains
        /// a word — and this group is what raw fields are filed against.
        let category: MetricDataCategory
    }

    /// Fixed category order; only metrics that actually have samples are shown.
    ///
    /// **Generated from `MetricType.dataCategory`, not hand-written.** The old
    /// literal array had already dropped sleep latency and vascular age — real
    /// metrics with data, absent from this screen because adding a `MetricType`
    /// and listing it here were two steps. Now a new connector's metric appears
    /// automatically once it declares a category, which the compiler forces.
    private static let categories: [(MetricDataCategory, [MetricType])] =
        MetricDataCategory.listed.map { ($0, MetricType.metrics(in: $0)) }

    /// ⚠️ **A category with only raw fields still gets a section.** Filing raw
    /// fields into canonical sections would otherwise make them disappear
    /// wherever the reader happens to have no modelled metric of that kind —
    /// which is exactly the state the newest connectors arrive in, and exactly
    /// the failure this whole change exists to fix.
    private var groups: [MetricGroup] {
        // Keyed off the cached summaries rather than remapping every sample.
        let present = model.vitalsSummaries
        let extras = rawFieldsByCategory
        return Self.categories.compactMap { category, metrics in
            let available = metrics.filter { present[$0] != nil }
            guard !available.isEmpty || !(extras[category] ?? []).isEmpty else { return nil }
            return MetricGroup(title: category.rawValue, metrics: available,
                               category: category)
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
            return hits.isEmpty ? nil : MetricGroup(title: group.title, metrics: hits,
                                                    category: group.category)
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
        case .symptoms:
            // Searchable by the symptom's own name as well as the heading, so
            // "headache" finds it without the reader knowing the app calls this
            // section Symptoms.
            guard !model.symptoms.isEmpty else { return false }
            return matches(domain.title, "symptom", "unwell", "sick")
        case .cycles:
            // The words a reader actually types. "Cycles" is what the app calls
            // it and is the least likely of the five to be searched for.
            guard !model.cycleDays.isEmpty else { return false }
            return matches(domain.title, "period", "cycle", "menstrual", "bleeding")
        case .calendarEvents:
            guard !model.calendarEvents.isEmpty else { return false }
            return matches(domain.title, "calendar", "meeting", "work", "travel",
                           "event", "personal")
                || model.symptoms.contains { matches($0.type.title) }
        case .holidays:
            // The words a reader reaches for, plus any label they typed — the
            // one part of the ledger in their own vocabulary.
            guard !model.holidayLedger.periods.isEmpty else { return false }
            return matches(domain.title, "holiday", "leave", "vacation",
                           "time off", "pto", "break")
                || model.holidayLedger.periods.contains { matches($0.label ?? "") }
        case .bodyScans:
            guard !model.bodyScans.isEmpty else { return false }
            return matches(domain.title, "body", "measurement", "scan", "waist",
                           "hip", "chest", "tape")
        case .derivedScores:
            return model.results.contains { $0.score != nil }
                && (matches(domain.title, "score", "estimate", "risk", "heart age")
                    || model.results.contains { matches($0.title) })
        case .unmodelled:
            return !filteredOtherGroups.isEmpty
        case .generatedInsights:
            // Searchable by the section's own words and by any series' display
            // name, so "fitness age" finds it without the reader knowing the
            // app files that under Generated insights.
            guard model.derivedSeries.pointCount > 0 else { return false }
            return matches(domain.title, "generated", "derived", "computed",
                           "insight", "trend")
                || model.derivedSeries.seriesIDs.contains {
                    model.derivedSeries.spec($0).map { matches($0.displayName) } ?? false
                }
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
                        // Above the catalogue, because it answers a different
                        // question — "what changed" rather than "what have you
                        // got" — and because a reader who opens this tab after a
                        // new connector wants that first. Not a `DataDomain`:
                        // it is a view *of* the domains rather than one of them,
                        // and giving it a case would put it in the search
                        // vocabulary, where it makes no sense.
                        whatChangedSection
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
            .addInputToolbar($activeInput)
        }
    }

    /// One section per kind of data the app holds.
    ///
    /// A `switch` rather than a list of views: adding a `DataDomain` case
    /// without a section here is a compile error, which is the whole mechanism
    /// keeping this screen honest.
    /// The cycle log, as data rather than as a calendar.
    ///
    /// The tab draws it to be tapped; this draws it to be *read*, which is the
    /// Data tab's whole job — every kind of data the app holds, listed, newest
    /// first, with nothing derived.
    @ViewBuilder private var cycleSection: some View {
        let summary = model.cycleSummary
        if !model.cycleDays.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    if let latest = model.cycleDays.last {
                        HStack {
                            Text(latest.day.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(latest.flow.title).foregroundStyle(.secondary)
                        }
                    }
                    // The range, never a single length — the rule `CycleLog`
                    // is built around, restated wherever cycles are shown.
                    Text(summary.lengthRange.map {
                        "\(model.cycleDays.count) days logged · cycles \($0.lowerBound)–\($0.upperBound) days"
                    } ?? "\(model.cycleDays.count) day\(model.cycleDays.count == 1 ? "" : "s") logged")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(DataDomain.cycles.title)
            }
        }
    }

    /// The three categories the reader named, as three labelled groups under
    /// one heading — see `DataDomain.calendarEvents` for why it is one domain.
    @ViewBuilder private var calendarSection: some View {
        let buckets = model.calendarBuckets
        if !model.calendarEvents.isEmpty {
            Section {
                ForEach(CalendarEventBucket.allCases) { bucket in
                    if let events = buckets[bucket], !events.isEmpty {
                        HStack {
                            Text(bucket.title)
                            Spacer()
                            Text("\(events.count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                let reviewed = model.calendarAccuracy
                Text(reviewed.rate.map {
                    String(format: "%d events · you have reviewed %d, and it was right %.0f%% of the time",
                           model.calendarEvents.count, reviewed.reviewed, $0 * 100)
                } ?? "\(model.calendarEvents.count) events · \(reviewed.reviewed) reviewed so far")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(DataDomain.calendarEvents.title)
            }
        }
    }

    /// The reader's leave — the merged holiday ledger (B7 H5), one row into
    /// its data page. The reader's instruction: *"make sure it has a data tab,
    /// where I can track holidays."*
    @ViewBuilder private var holidaysSection: some View {
        let ledger = model.holidayLedger
        if let latest = ledger.periods.last {
            Section {
                NavigationLink {
                    HolidaysDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(latest.label ?? (latest.source == .detected
                                                  ? "From your calendar" : "Leave"))
                            Spacer()
                            Text("\(ledger.periods.count) \(ledger.periods.count == 1 ? "period" : "periods")")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(holidayStanding(ledger))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(DataDomain.holidays.title)
            } footer: {
                Text(DataDomain.holidays.summary)
            }
        }
    }

    /// One phrase for where the reader stands on leave. The three states are
    /// genuinely different answers and each earns its own words — a ledger of
    /// only *booked* leave must not read as recent recovery.
    private func holidayStanding(_ ledger: HolidayLedger) -> String {
        switch ledger.daysSinceLastLeave(asOf: Date()) {
        case 0: return "On leave now"
        case .some(let days): return "Last leave ended \(days) \(days == 1 ? "day" : "days") ago"
        case nil: return "None taken yet — only booked ahead"
        }
    }

    @ViewBuilder private func section(for domain: DataDomain) -> some View {
        switch domain {
        case .metrics: metricSections
        case .bloodPressure: bloodPressureSection
        case .substances: substanceSection
        case .medication: medicationSection
        case .sideEffects: sideEffectSection
        case .symptoms: symptomSection
        case .bodyScans: bodyScanSection
        case .derivedScores: derivedScoreSection
        case .calendarEvents: calendarSection
        case .holidays: holidaysSection
        case .cycles: cycleSection
        case .unmodelled: otherDataSection
        case .generatedInsights: generatedInsightsSection
        }
    }

    /// One row, opening the sub-page — the reader's own shape for it, 2026-08-06:
    /// *"maybe we can put them all into a sub menu, so it doesn't blow out that
    /// page… Maybe in a 'Generated Insights' sub menu at the bottom."* The
    /// component tier alone is dozens of series, so the row carries a count and
    /// the page carries the list.
    @ViewBuilder private var generatedInsightsSection: some View {
        if model.derivedSeries.pointCount > 0 {
            Section {
                NavigationLink {
                    GeneratedInsightsDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Derived figures, day by day")
                            Spacer()
                            Text("\(model.derivedSeries.seriesIDs.count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text("Computed by this app, never measured")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(DataDomain.generatedInsights.title)
            } footer: {
                Text(DataDomain.generatedInsights.summary)
            }
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

    /// The modelled metrics, **plus the raw fields that measure the same
    /// subject** — so there is one "Nutrition" and one home for a VO₂max
    /// whoever sent it. See `rawFieldsByCategory` for what the reader reported.
    ///
    /// The raw ones come last within the section and are visibly quieter: they
    /// are fields the app holds but does not yet model, and the modelled metric
    /// is the one a reader should reach for first.
    @ViewBuilder private var metricSections: some View {
        let extras = rawFieldsByCategory
        let titles = fieldTitles
        ForEach(filteredGroups) { group in
            Section(group.title) {
                ForEach(group.metrics, id: \.self) { metric in
                    NavigationLink {
                        MetricDetailView(metric: metric)
                    } label: {
                        row(for: metric)
                    }
                }
                ForEach(extras[group.category] ?? []) { field in
                    rawFieldRow(field, titles: titles)
                        .foregroundStyle(.secondary)
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
    /// Body measurements, as a shape rather than a series.
    ///
    /// The seven promoted sites also chart under Measurements — that is not a
    /// duplicate. This row is about the *scan*: when, how, under what
    /// conditions, and whether it can still be re-derived. None of that fits a
    /// metric row, which is why `DataDomain.bodyScans` exists at all.
    @ViewBuilder private var bodyScanSection: some View {
        if let latest = model.bodyScans.first {
            Section {
                NavigationLink {
                    BodyScanDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(latest.mode.displayName)
                            Spacer()
                            Text("\(latest.measurements.sites.count) sites")
                                .foregroundStyle(.secondary).monospacedDigit()
                            Text("· \(latest.capturedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(model.bodyScans.count == 1
                             ? "1 measurement session"
                             : "\(model.bodyScans.count) measurement sessions")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(DataDomain.bodyScans.title)
            } footer: {
                Text(DataDomain.bodyScans.summary)
            }
        }
    }

    /// Symptoms the reader has tagged, promoted out of the raw catalogue.
    ///
    /// Counts only what they actually *had*: `notPresent` is a recorded absence
    /// — the reader saying "I checked and I did not have this" — and showing it
    /// as an occurrence would invert the one thing it means.
    @ViewBuilder private var symptomSection: some View {
        let present = model.symptoms.filter { $0.severity.isPresent }
        if !present.isEmpty {
            Section {
                NavigationLink {
                    SymptomDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        if let latest = present.first {
                            HStack {
                                Text(latest.type.title)
                                Spacer()
                                Text(latest.severity.title)
                                    .foregroundStyle(.secondary)
                                Text("· \(latest.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Text(present.count == 1 ? "1 recorded" : "\(present.count) recorded")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(DataDomain.symptoms.title)
            }
        }
    }

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
    ///
    /// **This was one flat alphabetical list of 158 identifiers** on the
    /// reader's own record, each rendered from its full dotted path, and eleven
    /// consecutive rows read "Daily activity · Contributors: Mee…" — every
    /// visible character shared, the distinguishing word truncated away. Three
    /// changes, all of them decided in InsightKit where they are tested:
    /// `RawFieldGrouping` puts each field in a titled section,
    /// `RawFieldPresentation.title(forPath:)` leads with the leaf, and
    /// `converted` fixes the units that read as nonsense ("32.26 count").
    /// A section of the catalogue. A named type rather than a tuple because
    /// `ForEach(_:id:)` needs a key path and **a key path into a tuple element
    /// does not compile** — `verify.sh` bans `\.0` for exactly this, and caught
    /// this line the first time it was written.
    private struct FieldSection: Identifiable {
        let group: RawFieldGrouping.Group
        let fields: [RawMetricGroup]
        var id: String { group.rawValue }
    }

    /// Titles resolved **across the whole catalogue at once**, because
    /// uniqueness is a property of a list and not of an identifier — see
    /// `RawFieldPresentation.titles(for:)`. Computed once per render rather than
    /// per row: it is O(paths) and this list is several hundred long.
    private var fieldTitles: [String: String] {
        let dotted = filteredOtherGroups.map(\.id).filter { $0.contains(".") }
        return RawFieldPresentation.titles(for: dotted)
    }

    private func fieldName(_ group: RawMetricGroup, titles: [String: String]) -> String {
        // HealthKit identifiers have no dotted path, and their own display name
        // is already the readable form.
        titles[group.id] ?? group.displayName
    }

    /// Raw fields that belong **inside** a canonical metric section, keyed by it.
    ///
    /// ⚠️ **The reader reported two "Nutrition" headings** within an hour of the
    /// grouped catalogue shipping, and *"a VO₂ Max data point from Oura at the
    /// very bottom of the page"* away from the canonical one. Two taxonomies —
    /// `MetricDataCategory` for modelled metrics and `RawFieldGrouping` for raw
    /// ones — each drawing their own sections. A section heading is a statement
    /// about a subject, so two headings with one name is a bug whatever sits
    /// under them. `RawFieldGrouping.Group.canonicalCategory` decides; this just
    /// files them.
    private var rawFieldsByCategory: [MetricDataCategory: [RawMetricGroup]] {
        let titles = fieldTitles
        var out: [MetricDataCategory: [RawMetricGroup]] = [:]
        for field in filteredOtherGroups {
            guard let category = RawFieldGrouping.group(for: field.id).canonicalCategory
            else { continue }
            out[category, default: []].append(field)
        }
        return out.mapValues { $0.sorted { fieldName($0, titles: titles) < fieldName($1, titles: titles) } }
    }

    /// The groups with no canonical home, which keep sections of their own.
    private var fieldSections: [FieldSection] {
        let titles = fieldTitles
        let homeless = filteredOtherGroups.filter {
            RawFieldGrouping.group(for: $0.id).canonicalCategory == nil
        }
        return Dictionary(grouping: homeless) { RawFieldGrouping.group(for: $0.id) }
            .sorted { $0.key < $1.key }
            .map { FieldSection(group: $0.key,
                                fields: $0.value.sorted {
                                    fieldName($0, titles: titles) < fieldName($1, titles: titles)
                                }) }
    }

    /// One raw field's row, shared by both places it can appear.
    @ViewBuilder private func rawFieldRow(_ field: RawMetricGroup,
                                          titles: [String: String]) -> some View {
        NavigationLink {
            OtherDataDetailView(group: field)
        } label: {
            HStack {
                Text(fieldName(field, titles: titles)).lineLimit(1)
                // Not hidden — this tab is the app's answer to "what do you know
                // about me" — but not dressed as a measurement either. Two of
                // these are constant across every row the reader has.
                if RawFieldPresentation.isRecordingDetail(field.id) {
                    Text("how it was recorded")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if let value = fieldValue(field) {
                    Text(value)
                        .foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }

    /// The newest reading, in a unit a reader can read.
    private func fieldValue(_ group: RawMetricGroup) -> String? {
        // `latestReal`, not `latest`: a provider placeholder of exactly 0 is not
        // a reading, and this row printed one beside a min of 35.19.
        guard let latest = group.latestReal else { return nil }
        guard let number = latest.numericValue else {
            // A long coded string — Oura's per-30-second hypnogram, say — is not
            // a value and printing 400 characters of it truncated tells nobody
            // anything.
            let text = latest.formattedValue
            return RawFieldPresentation.isCodedSeries(text)
                ? RawFieldPresentation.codedSeriesSummary(text) : text
        }
        return RawFieldPresentation.formatted(number, unit: latest.unit)
    }

    // MARK: - What changed

    /// **The reader's own idea**, 2026-08-05: *"remember that idea of how we can
    /// point out new data points synced, and point out now deprecated data?"*
    ///
    /// Two lists, and the second one is the harder promise. See
    /// `TypeSightingLedger` for why neither can be derived from the samples.
    private var newlyArrived: [String] {
        model.sightingLedger.newlyArrived(asOf: Date())
    }

    /// ⚠️ **Only where the source is demonstrably still alive.** Without that
    /// qualifier this announces "your ring data is deprecated" the week the ring
    /// spent on charge — wrong, and alarming in a health app.
    private var stoppedArriving: [String] {
        let now = Date()
        return model.sightingLedger.stoppedArriving(
            asOf: now, activeSourcePrefixes: model.sightingLedger.activePrefixes(asOf: now))
    }

    /// A readable name for a ledger identifier, which may be a canonical metric
    /// or a raw field.
    private func typeName(_ identifier: String) -> String {
        if let metric = MetricType(rawValue: identifier) { return metric.displayName }
        if identifier.contains(".") { return RawFieldPresentation.title(forPath: identifier) }
        return model.otherDataGroups.first { $0.id == identifier }?.displayName ?? identifier
    }

    @ViewBuilder private var whatChangedSection: some View {
        // Search hides this: it answers "what changed", and a query is a
        // question about something else.
        if trimmed.isEmpty {
            if !newlyArrived.isEmpty {
                Section {
                    ForEach(newlyArrived, id: \.self) { identifier in
                        Label(typeName(identifier), systemImage: "sparkles")
                    }
                } header: {
                    Text("New since you last looked")
                } footer: {
                    Text("Data types this app had never received before — a new connector, a new device, or one that only just started sending them. This is when the app first *saw* each one, not when the readings were taken, so a connector backfilling two years of history doesn't fill this list.")
                }
            }
            if !stoppedArriving.isEmpty {
                Section {
                    ForEach(stoppedArriving, id: \.self) { identifier in
                        Label(typeName(identifier), systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("No longer arriving")
                } footer: {
                    Text("Nothing new for two months, while the same source kept sending everything else — so this is the field going quiet rather than the device being off. Your data is untouched; it just isn't being added to.")
                }
            }
        }
    }

    @ViewBuilder private var otherDataSection: some View {
        let sections = fieldSections
        let titles = fieldTitles
        ForEach(sections) { section in
            Section {
                ForEach(section.fields) { field in
                    rawFieldRow(field, titles: titles)
                }
            } header: {
                Text(section.group.title)
            } footer: {
                // The footer goes on the last section only, so it reads as a
                // statement about the whole catalogue rather than being repeated
                // thirteen times.
                if section.id == sections.last?.id {
                    Text("Imported but not yet turned into insights — new HealthKit types and extra Oura/Withings fields. Tap any to review; tell me which to build into the app.")
                }
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

    // `realSamples`: a provider placeholder of exactly zero is not a reading,
    // and this page charted 35 of them in the reader's basal body temperature
    // as a series plunging to 0 °C. See `RawMetricGroup.placeholderZeros`.
    private var samples: [RawMetricSample] { group.realSamples.within(timeframe) }

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
                // **The placeholder count sits here, outside the chart's own
                // `count > 1` gate.** On a series that is mostly placeholders
                // filtering can drop the chart entirely, and a chart that
                // vanishes with no explanation is worse than the wrong chart
                // it replaced.
                let dropped = group.placeholderZeros.count
                Text("Identifier: \(group.id)\nSources: \(group.sources.sorted().joined(separator: ", "))"
                     + (dropped > 0
                        ? "\n\(dropped) reading\(dropped == 1 ? "" : "s") arrived as exactly 0 and are not shown — this source writes a zero where it means 'nothing recorded'."
                        : ""))
            }

            // A reading this series' own history says cannot be right. Judged
            // against the whole group rather than the visible timeframe: the
            // question "is this number wrong" is about the series, and a
            // fortnight's window can contain the slip and none of the ordinary
            // days it should be compared with.
            if let suspicion = group.suspicionNote {
                Section {
                    Label(suspicion, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Worth a look")
                }
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
                let suspect = group.suspectValues
                ForEach(samples) { s in
                    HStack {
                        Text(s.formattedValue)
                            .monospacedDigit()
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        // Marked on the row as well as summarised above, so the
                        // reader can see *which* one without comparing numbers
                        // by eye down a long list.
                        if suspect.contains(s.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.warn)
                                .accessibilityLabel("Far outside the rest of this series")
                        }
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
