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

    /// The row a "what changed" tap just jumped to, flashed briefly so the
    /// reader can see *which* one they landed on. See `jump(to:proxy:)`.
    @State private var highlighted: String?

    /// The flash fades and the scroll is animated — both are motion, and both
    /// are dropped when the reader has asked for less of it. The landing still
    /// happens; it just arrives rather than travels.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        let discovered = discoveredMetrics.subtracting(metricsShadowedByRawRow)
        return Self.categories.compactMap { category, metrics in
            // **Sighted counts, not just stored.** A metric the app has met is
            // listed in its home group whether or not it is holding a reading
            // right now; `row(for:)` says which of the two it is.
            //
            // In canonical order, mixed in with the rest rather than swept to
            // the bottom of the section: the reader is being sent here by a tap
            // on "New since you last looked", and a row that moves depending on
            // whether today's sync happened to carry a value is a row they have
            // to hunt for twice.
            let available = metrics.filter { present[$0] != nil || discovered.contains($0) }
            guard !available.isEmpty || !(extras[category] ?? []).isEmpty else { return nil }
            return MetricGroup(title: category.rawValue, metrics: available,
                               category: category)
        }
    }

    // MARK: - Discovered, with or without data

    /// **Every metric the app has ever *seen*, whether or not it holds one now.**
    ///
    /// The reader's rule, extended from cards to data — *"every card should
    /// show, even if it hasn't got data yet"* (2026-08-05) — restated for this
    /// screen on 2026-08-06: *"when a new data field is discovered, create a
    /// data section for it every time, even if we do not yet have data."*
    ///
    /// ⚠️ **Vitamin A is why.** It was promoted from a raw field to a
    /// `MetricType` on 2026-08-05, so on the next sync it arrived under a
    /// ledger key the app had never seen (`dietaryVitaminA` rather than
    /// `HKQuantityTypeIdentifierDietaryVitaminA`) and was announced under "New
    /// since you last looked". The reader's single vitamin A reading is then
    /// dropped by `MetricSanitizer` as implausible — it is far outside the
    /// metric's `plausibleRange` — so no sample survives into
    /// `vitalsSummaries`, and the old `present[$0] != nil` filter left the
    /// metric with **no row anywhere in the app**. Announced and then
    /// unfindable is worse than never mentioned.
    ///
    /// The ledger speaks three vocabularies (see `typeName(_:)`), so both the
    /// canonical raw value and the native HealthKit identifier are resolved —
    /// through `HealthKitService`'s own read table, which is the mapping
    /// ingestion uses, so this cannot disagree with it. A provider's dotted
    /// path is deliberately not resolved here: those are raw fields, they have
    /// rows of their own already, and promoting one to a canonical metric is a
    /// `PromotionRules` decision rather than a naming one.
    private var discoveredMetrics: Set<MetricType> {
        let native = HealthKitService.canonicalMetricByNativeIdentifier
        var out: Set<MetricType> = []
        for identifier in model.sightingLedger.sightings.keys {
            if let metric = MetricType(rawValue: identifier) ?? native[identifier] {
                out.insert(metric)
            }
        }
        return out
    }

    /// Metrics whose subject is **already on this screen as a raw field**, and
    /// which must therefore not also get a discovered row.
    ///
    /// A reader who has never had vitamin A promoted still has
    /// `HKQuantityTypeIdentifierDietaryVitaminA` in the catalogue, filed under
    /// Nutrition by `rawFieldsByCategory`. Adding a canonical "Vitamin A —
    /// discovered, nothing stored" row beside it would put two rows for one
    /// quantity in one section, and the quieter of the two would be lying: the
    /// app *is* holding a reading, in the row directly above.
    ///
    /// Computed over the whole catalogue rather than the filtered one, so a
    /// search cannot reveal the duplicate that an unsearched list hides.
    private var metricsShadowedByRawRow: Set<MetricType> {
        let native = HealthKitService.canonicalMetricByNativeIdentifier
        return Set(model.otherDataGroups.compactMap { native[$0.id] })
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
        // ⚠️ **A raw field filed into a canonical section was unsearchable.**
        // `metricSections` draws the raw extras *inside* their category's
        // section, so dropping a category because none of its **modelled**
        // metrics matched silently took the matching raw rows with it:
        // searching "Device model" said *No Results* while "Device model" and
        // "Device model ID" sat under Body measurements, because no
        // `MetricType` in `.body` is called that. Every raw field that has a
        // canonical home — nutrition, hearing, breathing, walking, body, sleep
        // detail, heart events — was reachable only by a query that happened to
        // name a modelled metric beside it.
        //
        // Seen in the simulator while finishing D27. The homeless groups never
        // had the fault, which is why the tab looked searchable: `stress` and
        // `readiness` both find their rows through `otherDataSection`, and it
        // draws its own sections.
        let extras = rawFieldsByCategory
        return groups.compactMap { group in
            if matches(group.title, DataDomain.metrics.title) { return group }
            let hits = group.metrics.filter { matches($0.displayName) }
            guard hits.isEmpty else {
                return MetricGroup(title: group.title, metrics: hits, category: group.category)
            }
            // No modelled metric matched — but keep the section if a raw field
            // filed under it did, with no metric rows.
            guard !(extras[group.category] ?? []).isEmpty else { return nil }
            return MetricGroup(title: group.title, metrics: [], category: group.category)
        }
    }

    private var filteredOtherGroups: [RawMetricGroup] {
        guard !trimmed.isEmpty else { return otherGroups }
        if matches(DataDomain.unmodelled.title, DataDomain.unmodelled.summary) {
            return otherGroups
        }
        // The raw identifier as well as the display name: "HKQuantityType…" is
        // what an export shows, and this screen is where those get looked up.
        //
        // ⚠️ **And the name actually on the row**, which was missing: searching
        // "Device model" returned *No Results* while a row reading "Device
        // model ID" sat in Body measurements, because the filter saw only the
        // provider's own `displayName` ("Modelid") and the path. Every raw row
        // has been titled by `RawFieldPresentation` since the flat list became
        // a catalogue, so a search that cannot see those titles cannot find
        // what the reader is looking at. Seen in the simulator while finishing
        // D27 — no test knew the two strings were meant to agree.
        //
        // The per-path title, not the collision-resolved one from
        // `fieldTitles`: that is computed *from* this list, and reading it here
        // would be circular. It differs only in how far a colliding name is
        // widened, and the leaf it starts from is in both.
        //
        // The group heading too, so "stress" finds the fields under "Stress &
        // resilience (Oura)" whatever each one happens to be called.
        return otherGroups.filter {
            matches($0.displayName, $0.id,
                    RawFieldPresentation.title(forPath: $0.id),
                    RawFieldGrouping.group(for: $0.id).title)
        }
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
        case .sickDays:
            // The words a reader types when they want the days they were ill.
            // "Sick" also finds the Symptoms section, which is right — they are
            // neighbouring answers to the same question.
            guard !model.sickDayLedger.periods.isEmpty else { return false }
            return matches(domain.title, "sick", "ill", "illness", "unwell",
                           "flu", "off sick")
                || model.sickDayLedger.periods.contains { matches($0.label ?? "") }
        case .bodyScans:
            guard !model.bodyScans.isEmpty else { return false }
            return matches(domain.title, "body", "measurement", "scan", "waist",
                           "hip", "chest", "tape")
        case .derivedScores:
            return model.results.contains { $0.score != nil }
                && (matches(domain.title, "score", "estimate", "risk", "heart age")
                    || model.results.contains { matches($0.title) })
        case .tags:
            // Searchable by the tag's **own words**, which is the point: a
            // reader looking for "kayaking" typed that word themselves and has
            // no reason to know the app files it under Tags, still less under
            // "Activity & mobility". The applicability name is searchable too,
            // so both routes in work.
            guard !model.tags.isEmpty else { return false }
            return matches(domain.title, "tag", "label", "note")
                || model.tags.contains { matches($0.name) }
                || model.tags.contains { matches($0.mapping.applicability.rawValue) }
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
                    // **The reader's ask, 2026-08-06:** *"when we discover a new
                    // field, if i click on it, scroll me down to it in the data
                    // section so i can see where it is"*. The proxy is the only
                    // way to do that, and it has to wrap the `List` itself.
                    ScrollViewReader { proxy in
                        List {
                            // Above the catalogue, because it answers a different
                            // question — "what changed" rather than "what have you
                            // got" — and because a reader who opens this tab after a
                            // new connector wants that first. Not a `DataDomain`:
                            // it is a view *of* the domains rather than one of them,
                            // and giving it a case would put it in the search
                            // vocabulary, where it makes no sense.
                            whatChangedSection(proxy)
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
                        // The flash decays on its own — a highlight that stayed
                        // would become a selection, which is a different claim
                        // about the row. Keyed on the id so a second jump
                        // cancels the first one's countdown rather than having
                        // it clear the new highlight early.
                        .task(id: highlighted) {
                            guard highlighted != nil else { return }
                            try? await Task.sleep(for: .seconds(1.6))
                            guard !Task.isCancelled else { return }
                            if reduceMotion {
                                highlighted = nil
                            } else {
                                withAnimation(.easeOut(duration: 0.9)) { highlighted = nil }
                            }
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
        // D49, spent: this opened nothing and now opens `CycleDataView`. The
        // Cycle tab still owns the calendar, the phase and every prediction —
        // this row is the Data tab's consistent way *in*, which is the thing
        // the convention is about.
        let summary = model.cycleSummary
        if !model.cycleDays.isEmpty {
            Section {
                NavigationLink {
                    CycleDataView()
                } label: {
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
                }
            } header: {
                Text(DataDomain.cycles.title)
            }
        }
    }

    /// The three categories the reader named, as three labelled groups under
    /// one heading — see `DataDomain.calendarEvents` for why it is one domain.
    @ViewBuilder private var calendarSection: some View {
        // D49, spent: this opened nothing and now opens `CalendarEventsDataView`.
        // The cards' review list is still where a judgement is *corrected* —
        // but it only covers work and travel, so a personal event was counted
        // here and visible nowhere. See the page's own note.
        let buckets = model.calendarBuckets
        if !model.calendarEvents.isEmpty {
            Section {
                NavigationLink {
                    CalendarEventsDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
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
                    }
                }
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

    /// **The days the reader was ill** — the merged `SickDayLedger` (§B11-4),
    /// one row into its data page. The reader's instruction: *"since this 'sick
    /// day' is now a new data source, it should of course now be stored in the
    /// data section too."*
    ///
    /// Its own section rather than a line inside Holidays, because a week of flu
    /// is not leave — see `DataDomain.sickDays`.
    @ViewBuilder private var sickDaysSection: some View {
        let ledger = model.sickDayLedger
        if let latest = ledger.periods.last {
            Section {
                NavigationLink {
                    SickDaysDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(latest.label ?? "From your calendar")
                            Spacer()
                            Text("\(ledger.periods.count) \(ledger.periods.count == 1 ? "spell" : "spells")")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(sickStanding(ledger))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text(DataDomain.sickDays.title)
            } footer: {
                Text(DataDomain.sickDays.summary)
            }
        }
    }

    /// One phrase for where the reader stands on illness. Three genuinely
    /// different answers, each with its own words — the same shape
    /// `holidayStanding` uses, and a ledger of only future-dated records must
    /// not read as "recently ill".
    private func sickStanding(_ ledger: SickDayLedger) -> String {
        switch ledger.daysSinceLastSickDay(asOf: Date()) {
        case 0: return "Marked ill today"
        case .some(let days): return "Last ill \(days) \(days == 1 ? "day" : "days") ago"
        case nil: return "Nothing recorded before today"
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
        case .sickDays: sickDaysSection
        case .cycles: cycleSection
        case .tags: tagsSection
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
                    // The scroll target for a "what changed" tap. Explicit
                    // rather than the `ForEach` identity, because the two lists
                    // above index by *ledger identifier* and only a stated id
                    // can be resolved from one — see `rowID(forSighted:)`.
                    .id(Self.rowID(metric: metric))
                    .listRowBackground(highlightBackground(Self.rowID(metric: metric)))
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
            HStack(alignment: .firstTextBaseline) {
                // ⚠️ **No `lineLimit(1)`.** It shipped one, and on the reader's
                // own record that truncated the names that needed reading most:
                // "Environmental Sound Reduct…", "Daily readiness temperature
                // de…" — a row whose *whole* subject is its name, with no way
                // to see the name. The canonical metric rows above wrap
                // ("Resting Heart Rate" is two lines on a 390pt screen), so
                // wrapping is this tab's own convention and this row was the
                // one place breaking it. `fixedSize` vertically is what makes a
                // `Text` in an `HStack` take the height it needs rather than
                // being squeezed back to one line.
                VStack(alignment: .leading, spacing: 2) {
                    Text(fieldName(field, titles: titles))
                        .fixedSize(horizontal: false, vertical: true)
                    // Not hidden — this tab is the app's answer to "what do you
                    // know about me" — but not dressed as a measurement either.
                    // Two of these are constant across every row the reader has.
                    // **Under the name, not beside it**: beside it, it competed
                    // with the name for the width that was already too narrow.
                    if RawFieldPresentation.isRecordingDetail(field.id) {
                        Text("how it was recorded")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if let value = fieldValue(field) {
                    // Two lines and wrapping, for the same reason: a decoded
                    // recording detail reads "Measured by the device", and
                    // truncating that back to "Measured by th…" would reinstate
                    // the defect at the other end of the row.
                    Text(value)
                        .foregroundStyle(.secondary).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Stated here rather than at the two call sites, so a raw field is the
        // same scroll target wherever it happens to be filed.
        .id(Self.rowID(rawField: field.id))
        .listRowBackground(highlightBackground(Self.rowID(rawField: field.id)))
    }

    /// The newest reading, in a unit a reader can read.
    private func fieldValue(_ group: RawMetricGroup) -> String? {
        // `latestReal`, not `latest`: a provider placeholder of exactly 0 is not
        // a reading, and this row printed one beside a min of 35.19.
        guard let latest = group.latestReal else { return nil }
        // What a value is allowed to claim is decided (and tested) in
        // InsightKit — `rowValue` decodes or silences recording-detail codes
        // and renders the Oura stress durations as time; `rowText` summarises
        // coded series and reads state words as words.
        guard let number = latest.numericValue else {
            return RawFieldPresentation.rowText(latest.formattedValue, identifier: group.id)
        }
        return RawFieldPresentation.rowValue(number, unit: latest.unit, identifier: group.id)
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

    // MARK: - Row identity, and jumping to one

    /// The id a metric's row carries, and the id a raw field's row carries.
    ///
    /// **They must not collide, which is why both are prefixed.** A metric's
    /// raw value and a provider's field path are both bare strings from the
    /// same ledger, and a single namespace would have one silently scroll to
    /// the other the first time the two ever agreed.
    private static func rowID(metric: MetricType) -> String { "metric:\(metric.rawValue)" }
    private static func rowID(rawField identifier: String) -> String { "raw:\(identifier)" }

    /// Every row id currently on screen.
    ///
    /// Built from the **unfiltered** lists: a jump clears the search first, so
    /// the question being asked is "will this row exist once I have", not "does
    /// it exist under the current query".
    private var renderedRowIDs: Set<String> {
        var ids = Set(groups.flatMap(\.metrics).map(Self.rowID(metric:)))
        ids.formUnion(model.otherDataGroups.map { Self.rowID(rawField: $0.id) })
        return ids
    }

    /// The row that represents a ledger identifier, or `nil` if none does.
    ///
    /// Resolved in the same three-way shape as `typeName(_:)` — canonical raw
    /// value, native HealthKit identifier, provider path — and canonical first,
    /// because a subject that has both a metric row and a raw row is the metric.
    ///
    /// ⚠️ **`nil` means do nothing at all.** Change A should make this
    /// unreachable for anything in "New since you last looked" — a sighted type
    /// now always has a row — but a ledger written by an older build can hold
    /// an identifier that no longer resolves to anything, and scrolling to
    /// *approximately* the right place would leave the reader believing a row
    /// they are looking at is the one they tapped.
    private func rowID(forSighted identifier: String, rendered: Set<String>) -> String? {
        if let metric = MetricType(rawValue: identifier)
            ?? HealthKitService.canonicalMetricByNativeIdentifier[identifier] {
            let id = Self.rowID(metric: metric)
            if rendered.contains(id) { return id }
        }
        let raw = Self.rowID(rawField: identifier)
        return rendered.contains(raw) ? raw : nil
    }

    /// Scroll the list to a row and flash it.
    ///
    /// The flash is the half that is easy to leave out and the half the reader
    /// actually asked for — *"scroll me down to it in the data section so i can
    /// see where it is"*. A scroll on its own lands them in a section of forty
    /// near-identical rows with no indication of which one moved them there.
    private func jump(to id: String, proxy: ScrollViewProxy) {
        // A live search filters rows out, and `scrollTo` on a row that is not
        // in the list does nothing. Unreachable today — the section this is
        // called from hides itself under a query — and kept because that is a
        // property of the *caller*, not of this function.
        if !trimmed.isEmpty { query = "" }
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
        // ⚠️ **The flash is set after the scroll, not with it, and that is a
        // fix rather than a flourish.** Measured on the simulator: a target
        // already on screen flashed correctly, and one forty rows down never
        // did. A `List` does not realise a row until it is nearly visible, so
        // setting the highlight in the same state update means the cell for the
        // destination is built *during* the scroll — and it arrives showing the
        // state as it was before the tap. Letting the scroll land first means
        // the row is on screen when the value changes, which is the case that
        // was already working.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            highlighted = id
        }
    }

    /// The flash itself: a wash of the accent over the ordinary row colour.
    ///
    /// **The system background is restated rather than left to `nil`.** The
    /// obvious form — `listRowBackground(highlighted == id ? colour : nil)` —
    /// swaps between "no view" and "a view", and there is nothing for SwiftUI
    /// to interpolate across that, so the decay would step rather than fade.
    /// One view whose *opacity* changes animates properly, and restating
    /// `secondarySystemGroupedBackground` underneath keeps an unhighlighted row
    /// looking exactly like the ones around it — checked on the simulator
    /// against the untouched sections above and below.
    private func highlightBackground(_ id: String) -> some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            Theme.accent.opacity(highlighted == id ? 0.28 : 0)
        }
    }

    /// One "what changed" row.
    ///
    /// A `Button` **only when there is somewhere to go** — the alternative is a
    /// row that looks tappable and does nothing, which is a worse answer than
    /// an obviously inert one. Both lists use this: they are visually identical
    /// rows about the same kind of thing, and making only one of them respond
    /// to a tap would read as a bug.
    @ViewBuilder private func changedRow(_ identifier: String, icon: String,
                                         rendered: Set<String>,
                                         proxy: ScrollViewProxy) -> some View {
        if let target = rowID(forSighted: identifier, rendered: rendered) {
            Button {
                jump(to: target, proxy: proxy)
            } label: {
                HStack {
                    Label(typeName(identifier), systemImage: icon)
                    Spacer()
                    // Says what the tap does before it is tapped. Down, because
                    // this section is pinned above the whole catalogue, so the
                    // row being pointed at is always below.
                    Image(systemName: "arrow.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            // Without this a `Button` in a `List` tints its whole label, and the
            // row stops looking like the rows either side of it.
            .buttonStyle(.plain)
        } else {
            Label(typeName(identifier), systemImage: icon)
        }
    }

    @ViewBuilder private func whatChangedSection(_ proxy: ScrollViewProxy) -> some View {
        // Search hides this: it answers "what changed", and a query is a
        // question about something else.
        if trimmed.isEmpty {
            // Once for the whole section rather than once per row: resolving a
            // target walks every group and every raw field, and this list can
            // hold dozens of rows the week a connector is added.
            let rendered = renderedRowIDs
            if !newlyArrived.isEmpty {
                Section {
                    ForEach(newlyArrived, id: \.self) { identifier in
                        changedRow(identifier, icon: "sparkles",
                                   rendered: rendered, proxy: proxy)
                    }
                } header: {
                    Text("New since you last looked")
                } footer: {
                    Text("Data types this app had never received before — a new connector, a new device, or one that only just started sending them. Tap one to jump to where it lives below. This is when the app first *saw* each one, not when the readings were taken, so a connector backfilling two years of history doesn't fill this list.")
                }
            }
            if !stoppedArriving.isEmpty {
                Section {
                    ForEach(stoppedArriving, id: \.self) { identifier in
                        changedRow(identifier, icon: "pause.circle",
                                   rendered: rendered, proxy: proxy)
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

    /// Tags, one row into `TagsDataView` (backlog B12-1).
    ///
    /// The row says how many distinct tags there are and how many of them the
    /// app has **not** placed — the second half deliberately, because "12 tags"
    /// alone would let a reader assume all twelve carry a meaning the app
    /// understands. The unplaced count is the honest headline for a feature
    /// whose whole job is classifying an open set.
    @ViewBuilder private var tagsSection: some View {
        let summaries = model.tags.distinctTags()
        if let newest = summaries.first {
            let unplaced = summaries.filter { $0.mapping.applicability == .unclassified }.count
            Section {
                NavigationLink {
                    TagsDataView()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(newest.name)
                            Spacer()
                            Text(newest.mapping.applicability.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("· \(newest.lastUsed.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(unplaced == 0
                             ? "\(summaries.count) tag\(summaries.count == 1 ? "" : "s"), all grouped"
                             : "\(summaries.count) tag\(summaries.count == 1 ? "" : "s") · \(unplaced) not yet grouped")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(DataDomain.tags.title)
            } footer: {
                Text(DataDomain.tags.summary)
            }
        }
    }

    @ViewBuilder private var otherDataSection: some View {
        // data-detail: exempt — PERMANENT, decided under D49 rather than
        // inherited from it. The other two exemptions D49 named were spent;
        // this one was examined and kept, and the reasoning is the point:
        //
        // 1. **Every row here already opens a page.** `rawFieldRow` is a
        //    `NavigationLink` into `OtherDataDetailView`, per identifier. There
        //    is no dead end for any actual datum — what has no single
        //    destination is the *section*, and only because it is not one kind
        //    of data. `unmodelled` is the residual: ~158 raw identifiers with
        //    nothing in common but that no card reads them yet.
        //
        // 2. **A page of everything answers nothing.** The other domains'
        //    detail pages exist to say "here is this one shape, listed, newest
        //    first". The equivalent here is a flat list of 158 unrelated
        //    fields — which is exactly the screen this section was rebuilt to
        //    stop being (eleven consecutive rows reading "Daily activity ·
        //    Contributors: Mee…"). Putting it one tap further away and calling
        //    it a detail page would undo that and satisfy a lint.
        //
        // 3. **This section is browsed in place, by search.** `filteredOtherGroups`
        //    matches the display name, the raw identifier, the rendered row
        //    title and the group heading, so the reader finds a field from the
        //    Data tab's own search field. A detail page would put a second
        //    search behind the first.
        //
        // The shape is different from every other domain, so the convention's
        // second rule genuinely does not apply — and saying so is a decision,
        // not a debt. If `unmodelled` ever narrows to one kind of thing, this
        // comment is wrong and the page should be built.
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
                // **Every group says what it holds** (`RawFieldGrouping.Group.
                // blurb`), which is standing rule 9 — every data entry carries a
                // "what this is" description — finally reaching the raw
                // catalogue. Before this the reader got thirteen bare headings
                // and one sentence at the very bottom about the lot; "Time
                // restored — 0m" under "Stress & resilience (Oura)" named its
                // subject and explained nothing.
                //
                // The catalogue-wide sentence still goes on the last section
                // only, so it reads as a statement about the whole list rather
                // than being repeated under each group.
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.group.blurb)
                    if section.id == sections.last?.id {
                        Text("Imported but not yet turned into insights — new HealthKit types and extra Oura/Withings fields. Tap any to review; tell me which to build into the app.")
                    }
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
            } else {
                // **Says what is true, in the slot where a value would be.**
                // Not "0", not "—": the app has met this measurement and is
                // holding none of it, and those are different states. The row
                // still opens `MetricDetailView`, which explains what the
                // metric is and carries its own empty state — so this is a
                // definition and an invitation rather than a dead end. See
                // `discoveredMetrics`.
                Text("Discovered · nothing stored")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        // Quieter than a row with a reading behind it, on the same reasoning
        // that dims the raw fields: both are real, and neither is the thing a
        // reader scanning this section is looking for first.
        .foregroundStyle(summary == nil ? .secondary : .primary)
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
    /// **For the substance shading, and only for it.** The reader's standing
    /// rule (2026-08-03) is that *every* chart carries it, and this page's
    /// chart went without for as long as it has existed — see the chart's own
    /// note for why no check caught that.
    @Environment(AppModel.self) private var model

    /// The same readable name the tab's row shows.
    ///
    /// It used to be `group.displayName` — the provider's own label — so a row
    /// reading "Time stressed" opened a page headed "Stress high", and one
    /// reading "Visceral fat index" opened "Measure 170". A reader tapping a
    /// name should land on that name.
    private var title: String {
        group.id.contains(".") ? RawFieldPresentation.title(forPath: group.id) : group.displayName
    }

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

    /// The span the chart actually draws, so the shading can be clipped to it.
    ///
    /// **From `charted`, not from the timeframe.** A shaded rectangle wider
    /// than the data widens the x domain and drags the line into a corner —
    /// which is why `SubstanceShading.marks` takes a range at all. Falls back
    /// to a zero-width range for the empty case, where nothing is drawn anyway.
    private var plotRange: ClosedRange<Date> {
        guard let first = charted.first?.date, let last = charted.last?.date,
              first <= last else {
            let now = Date()
            return now...now
        }
        return first...last
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

    /// **What this is**, and it is never empty.
    ///
    /// Standing rule 9 — every data entry carries a "what this is" description
    /// — was met for canonical metrics by `MetricExplainer` and missed entirely
    /// by the raw catalogue, which is where a reader most needs it: they did
    /// not choose these fields and mostly did not know they had them. Backlog
    /// D28 named the symptom on the reader's own screen — Oura's stress fields
    /// sitting "unsorted **and unexplained**".
    ///
    /// Two tiers, because the raw catalogue is an open set: the field's own
    /// sentence where the app has actually looked into it, and its group's
    /// blurb otherwise. Never a guess dressed as knowledge — the group blurb
    /// says what kind of thing the field is, which is true of every member by
    /// construction.
    private var explanation: String {
        RawFieldPresentation.explanation(forPath: group.id)
            ?? RawFieldGrouping.group(for: group.id).blurb
    }

    /// One reading, under the same rules the tab's rows follow.
    ///
    /// It was `sample.formattedValue` — the provider's number and the
    /// provider's unit string — so a page reached by tapping a row reading
    /// "58" listed "58 count", and one reading "2h 45m" listed "9900". **The
    /// unit-and-precision rules had reached the list and stopped at the page
    /// behind it**, which is the same split that let a named recording detail
    /// print its wire code: recognition in one place, rendering in another.
    ///
    /// The one difference from the row: where `rowValue` declines to print an
    /// undecoded code, this page still shows it. It is the review surface —
    /// the app's literal answer to "what do you know about me" — every row
    /// here carries a date and sits under a "Readings" heading, and the
    /// explanation above already says the field describes a reading rather
    /// than being one.
    private func readingText(_ sample: RawMetricSample) -> String {
        guard let number = sample.numericValue else {
            return RawFieldPresentation.rowText(sample.formattedValue, identifier: group.id)
        }
        return RawFieldPresentation.rowValue(number, unit: sample.unit, identifier: group.id)
            ?? RawFieldPresentation.formatted(number, unit: sample.unit)
    }

    var body: some View {
        List {
            Section {
                Text(explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("What this is")
            }

            Section {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                if charted.count > 1 {
                    // An explicit hue: without one Swift Charts supplies its
                    // own blue, which is off the validated palette every other
                    // chart in the app draws from. (Slot 0 *is* a blue — the
                    // validated one. Checked against the pixels, not assumed.)
                    Chart(charted) { point in
                        // ⚠️ **This chart carried no substance shading until
                        // D11 looked at it on the simulator**, and the reason
                        // no check said so is worth keeping: the shading lint
                        // greps for `Chart` followed by a **brace**, and this
                        // is the `Chart(data) { … }` paren form. Its sibling
                        // lint — no raw chart in a data page — already matched
                        // both. The one that mattered matched one. `verify.sh`
                        // now matches both, and this was the only file in the
                        // app the widening newly caught.
                        SubstanceShading.marks(model.allSubstanceWindows,
                                               in: plotRange)
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
                    // A band with no caption is decoration — the same rule the
                    // reference ranges follow.
                    Text(SubstanceShading.caption)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(title)
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
                        Text(readingText(s))
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
