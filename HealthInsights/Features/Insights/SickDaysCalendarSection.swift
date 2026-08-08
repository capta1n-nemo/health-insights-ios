import SwiftUI
import InsightKit

/// **Every day the radar judged, as a log or as a calendar** — backlog `B11-1`,
/// in the reader's own words: *"Two views, switchable: log and calendar."*
///
/// ## The ruling this section is built on, and why it is not obvious
///
/// Three different numbers could have coloured a day, and they disagree on
/// exactly the days the reader has already complained about:
///
/// | Number | What it is | Where it fails here |
/// | --- | --- | --- |
/// | `SymptomRadarModel.timeline` → `Output.score` | the day, judged alone | forgets a multi-day illness between mornings |
/// | `verdict()` | `max(today, accumulation)` — what the card said | paints a recovering day with Tuesday's memory |
/// | `DataStore.scoreHistory` | what was literally on screen | starts at install, so most of the year is blank |
///
/// The reader ruled on 2026-08-07, and the ruling is a design and not a
/// tiebreak: **colour each day by its own statistic, and draw the accumulated
/// episode as a band across the days it spanned.** A recovering morning is
/// therefore not painted red by something that happened four days ago — which
/// is the honest reading of *"why am I now back at 99% just 1 day later?"* — and
/// a week of illness still reads as one block rather than as a scatter of
/// unrelated bad days. Both facts are true and neither is allowed to hide the
/// other.
///
/// So the colour comes from `DayHistory.output.status` (the morning alone) and
/// the band comes from `SymptomRadarModel.flaggedSpans`, which groups by the
/// *verdict's* status — memory included. The difference between the two is
/// visible on the screen, labelled, and counted in the log.
///
/// ## Why the bands are the radar's own and not the app's score bands
///
/// `Theme.color(forScore:)` reads `ScoreBand` — 70 and 45 — which is the app's
/// general-purpose good/fair/poor. This card's own edges are **85 and 50**, and
/// they mean something specific: 85 is one null SD, 50 is a stated budget of
/// about two alarming mornings a year on a well body. Colouring by the generic
/// bands would give a calendar where a day the card called *quiet* was drawn
/// amber. The cells therefore read `Output.status` directly, which is the same
/// property the card's own headline reads.
///
/// The fourth colour splits `quiet` by whether **anything was leaning** — a
/// distinction the model already draws, not a threshold invented here. "Nothing
/// stirring at all" and "quiet, but one channel was off" are different days, and
/// on a calendar the second is the one worth being able to see coming.
///
/// ⚠️ **A coloured square is not a diagnosis, and a month of them is not a
/// medical history.** The caption says so and it is not optional: prospective
/// positive predictive value for this class of detector is 4–12%
/// (`docs/illness-detection-evidence-2026-08-07.md`).
///
/// ## What the reader said is on here too, and used not to be (2026-08-09)
///
/// From their own phone: *"when I correct a day to include illness on the
/// calendar… like I add severe sickness, the days still shows green on the
/// calendar and the AI doesn't seem to learn from it."* They were right, and the
/// defect was one line: `fill(for:)` read `DayHistory.output.status`, which
/// comes from `SymptomRadarModel.timeline(samples:days:endingAt:calendar:)` —
/// **a function whose only input is `samples`.** No sick day, of any severity,
/// from either source, could reach it. Green is what a quiet overnight reading
/// paints, and a quiet overnight reading is exactly what most real illness
/// produces.
///
/// The proof it was a defect and not the restraint above: tapping the square
/// opens `SickDayDetailView`, whose `SickDayReport.status` **does** fold in
/// `ReportedIllness`. The square and the page one tap behind it were computing
/// two different answers to one question, and the reader was looking at the one
/// that had never been told.
///
/// ⚠️ **This is not the rejected `verdict()` option in the table above.** That
/// one was rejected for smearing *Tuesday's accumulation* across a recovering
/// Friday, and the ruling it produced — "colour each day by its own statistic" —
/// is kept exactly: the accumulation is still the band and never the fill.
/// `ReportedIllness.evaluate` is same-day only by construction and says so at
/// length (*"'I was ill on Tuesday' is about Tuesday"*), so what the reader said
/// about a day **is** that day's own statistic. The fill is now
/// `verdict(today:accumulation: .none, reported:)` — the day alone, both of the
/// things known about it, and no memory.
///
/// ⚠️ **And the two are never blended into one meaning.** `add-chart`'s
/// hatch-never-blend rule: a stated illness and a measured departure are
/// different kinds of claim, so a day the reader spoke about carries its own
/// mark and its own legend row. A red square with the mark says *you told me*; a
/// red square without it says *your overnight numbers moved*. The section's own
/// thesis — both facts are true and neither may hide the other — is what that
/// mark is for.
struct SickDaysCalendarSection: View {
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .calendar
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selected: Date?

    private var calendar: Calendar { .current }

    enum Mode: String, CaseIterable, Identifiable {
        case calendar, log
        var id: String { rawValue }
        var title: String { self == .calendar ? "Calendar" : "Log" }
    }

    /// ⚠️ **Same memo key as `SickDaysSection`, deliberately.** Both want the
    /// same six months of replay off the same sample set, and
    /// `AppModel.memoized` is keyed by call site precisely so two readers of one
    /// computation pay for it once. The key clears with every other derived
    /// cache when the samples change, so a hit can never be stale.
    private var history: [SymptomRadarModel.DayHistory] {
        model.memoized("radarHistory") {
            SymptomRadarModel.history(over: SymptomRadarModel.timeline(
                samples: model.samples, days: SymptomRadarModel.historyDays,
                endingAt: Date(), calendar: .current))
        }
    }

    private var spans: [SymptomRadarModel.FlaggedSpan] {
        model.memoized("radarFlaggedSpans") {
            SymptomRadarModel.flaggedSpans(in: history, calendar: .current)
        }
    }

    /// **Every day the reader said something about, and what they said.**
    ///
    /// The same three records `SickDayReport.build` hands the day page — the
    /// merged `SickDayLedger`, the Health symptom tags and the medication
    /// tracker's own side-effect log — so a square and the page behind it cannot
    /// give different answers again.
    ///
    /// ⚠️ **Deliberately not `model.memoized`.** That cache is cleared by
    /// `invalidateDerivedCaches()`, which fires when `samples` change — and a
    /// correction changes no sample. Memoising here would leave the calendar
    /// showing the answer the reader had just disagreed with, which is a
    /// slower-burning version of the bug this whole plumbing exists to fix.
    ///
    /// Cheap without it: the day set is one pass over three short lists, and
    /// `ReportedIllness.evaluate` runs only for days actually in it — on a
    /// typical month, none.
    private var spokenDays: [Date: ReportedIllness.Output] {
        var days = model.sickDayLedger.sickDays(calendar: calendar)
        for event in model.symptoms where event.severity.isPresent {
            days.insert(calendar.startOfDay(for: event.date))
        }
        let effects = model.reportedSideEffects
        for effect in effects {
            days.insert(calendar.startOfDay(for: effect.date))
        }
        var out: [Date: ReportedIllness.Output] = [:]
        for day in days {
            let said = ReportedIllness.evaluate(day: day, symptoms: model.symptoms,
                                                sickDays: model.sickDayLedger,
                                                sideEffects: effects,
                                                calendar: calendar)
            if said.isSpeaking { out[day] = said }
        }
        return out
    }

    var body: some View {
        InsightSection(
            title: "Day by day",
            trailing: spans.isEmpty ? nil
                : "\(spans.count) spell\(spans.count == 1 ? "" : "s")",
            caveat: .computed(.replayed,
                              "Each day is judged the way this morning was — against "
                              + "the three weeks before it, ending four days before "
                              + "the window it judges. A square's colour is that day "
                              + "on its own — your overnight numbers and anything you "
                              + "recorded about that day, whichever says more; the bar "
                              + "under a run of days is the accumulation, which is what "
                              + "the card was actually saying. A dot marks a day you "
                              + "told the app something. Days nothing was worn are "
                              + "blank, not green."),
            // Closed on arrival. Six months of squares is a thing you go
            // looking for, and the preview says what is behind the door.
            expansion: .collapsed(preview: previewLine)
        ) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .calendar: calendarView
            case .log: logView
            }

            Text("A square is what the card said that morning, and nothing more. "
                 + "In the studies that ran detectors like this one forward against "
                 + "a real test, between 4 and 12 alerts in every 100 turned out to "
                 + "be infections — and about two-thirds of real infections never "
                 + "show up in these signals at all. Read a run of colour as "
                 + "something to look at, never as a record of when you were ill.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ⚠️ Unconditional, like the section itself — never gated on there being
    /// judged days. A section that appears and disappears as data arrives moves
    /// everything under the reader's finger.
    private var previewLine: String {
        let judged = history.filter { $0.output != nil }.count
        guard judged > 0 else { return "Nothing judged yet" }
        guard !spans.isEmpty else { return "\(judged) days judged, none flagged" }
        let flagged = spans.reduce(0) { $0 + $1.days.count }
        return "\(flagged) flagged days in \(spans.count) "
            + "spell\(spans.count == 1 ? "" : "s")"
    }

    // MARK: - Calendar

    @ViewBuilder private var calendarView: some View {
        // Computed once per pass and handed down, never per cell: `evaluate`
        // filters the whole tag list, and forty-two of those a render is the
        // shape of cost this file's own doc comment forbids elsewhere.
        let spoken = spokenDays
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            MonthStepper(month: $month, calendar: calendar,
                         canGoBack: canStep(-1), canGoForward: canStep(1))
            // 33 = the 28pt square, the 2pt gap and the 3pt band bar. A blank
            // leading slot that disagreed with a real cell by a point would
            // make the first week of a month a different height from the rest.
            MonthGrid(month: month, calendar: calendar, rowHeight: 33) { day in
                dayCell(day, said: spoken[calendar.startOfDay(for: day)] ?? .silent)
            }
            readout(spoken)
            calendarLegend
        }
    }

    /// Whether stepping a month lands anywhere the radar could have judged.
    ///
    /// Bounded by the replay's own span rather than by an arbitrary year: there
    /// is nothing behind the oldest judgeable day and nothing ahead of today,
    /// and a chevron that pages into six blank months teaches the reader that
    /// blank means broken.
    private func canStep(_ months: Int) -> Bool {
        guard let next = calendar.date(byAdding: .month, value: months, to: month),
              let target = calendar.dateInterval(of: .month, for: next)?.start,
              let oldest = history.first?.day,
              let floor = calendar.dateInterval(of: .month, for: oldest)?.start,
              let ceiling = calendar.dateInterval(of: .month, for: Date())?.start
        else { return false }
        return target >= floor && target <= ceiling
    }

    private func row(for day: Date) -> SymptomRadarModel.DayHistory? {
        history.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    @ViewBuilder private func dayCell(_ day: Date,
                                      said: ReportedIllness.Output) -> some View {
        let entry = row(for: day)
        let span = SymptomRadarModel.span(covering: day, in: spans, calendar: calendar)
        let isFuture = day > calendar.startOfDay(for: Date())
        Button {
            // Tapping the same day again clears it, so the readout is never
            // stuck showing a day the reader has stopped asking about.
            selected = (selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false)
                ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(entry?.output == nil && !said.isSpeaking
                                     ? Color.secondary.opacity(isFuture ? 0.35 : 0.7)
                                     : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if let fill = fill(for: entry, said: said) {
                            RoundedRectangle(cornerRadius: 8).fill(fill)
                        }
                    }
                    .overlay {
                        if calendar.isDateInToday(day) {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                        }
                        if let selected, calendar.isDate(selected, inSameDayAs: day) {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.accent, lineWidth: 1.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) { spokenMark(said) }
                bandBar(span, day: day)
            }
        }
        .buttonStyle(.plain)
        // ⚠️ **A day the reader spoke about is always tappable**, even where the
        // watch judged nothing. The old gate was `entry?.output == nil` alone,
        // so marking an unworn night as a sick day produced a blank square that
        // would not open — the reader's own record, stored, rendered nowhere and
        // unreachable.
        .disabled(entry?.output == nil && !said.isSpeaking)
        .accessibilityLabel(accessibilityLabel(day: day, entry: entry,
                                               span: span, said: said))
    }

    /// **The mark that says a human being said this, rather than a sensor.**
    ///
    /// Deliberately not a colour and not a fifth fill: `add-chart`'s
    /// hatch-never-blend rule is about exactly this case — one quantity drawn
    /// over another must stay separable, and a stated illness is a different
    /// kind of claim from a measured departure. So the grade goes into the fill
    /// (that is the scale `ReportedIllness.excess(for:)` is anchored to) and the
    /// *provenance* goes here, in the app's foreground colour, which reads
    /// against all four fills and against no fill at all.
    @ViewBuilder private func spokenMark(_ said: ReportedIllness.Output) -> some View {
        if said.isSpeaking {
            Circle()
                .fill(Color.primary)
                .frame(width: 6, height: 6)
                .padding(3)
        }
    }

    /// The accumulated episode, drawn under the days it spanned.
    ///
    /// Extended a point into the column gutter wherever the run continues, and
    /// inset where it genuinely stops, so the block reads as one bar across a
    /// week rather than as seven dashes. Grey rather than a band colour on
    /// purpose: `SickDaysSection`'s legend already means *accent = that morning,
    /// secondary = with memory*, and two sections of one card must not use one
    /// colour for two things.
    @ViewBuilder private func bandBar(_ span: SymptomRadarModel.FlaggedSpan?,
                                      day: Date) -> some View {
        if let span {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.75))
                .frame(height: 3)
                .padding(.leading, span.begins(on: day, calendar: calendar) ? 2 : -1)
                .padding(.trailing, span.ends(on: day, calendar: calendar) ? 2 : -1)
        } else {
            Color.clear.frame(height: 3)
        }
    }

    /// **The day's own statistic, and only ever the day's own — both halves of
    /// it.**
    ///
    /// `accumulation: .none` is the whole of the reader's §B11-1 ruling: memory
    /// is the band and never the fill, so a recovering Friday is not painted by
    /// Tuesday. `reported:` is the half that was missing until 2026-08-09, and
    /// it obeys the same rule for free — `ReportedIllness.evaluate` is same-day
    /// only by construction, so nothing here can smear a statement across a week
    /// either.
    ///
    /// Going through `SymptomRadarModel.verdict` rather than re-deriving is what
    /// keeps this square and the page it opens on one answer. With nothing
    /// reported it returns exactly what `Output.status` used to return — pinned
    /// by `SickDayCalendarColourTests.testAQuietDayIsUnchangedWhenNothingWasSaid`
    /// so a future edit to either set of gates cannot silently repaint six
    /// months of squares.
    ///
    /// Nil where the watch could not judge the day and the reader said nothing —
    /// an unworn night is missing evidence, and painting it green would be the
    /// app answering a question nobody measured. A day the reader *did* speak
    /// about still carries `spokenMark`, so their record is never invisible.
    private func fill(for entry: SymptomRadarModel.DayHistory?,
                      said: ReportedIllness.Output) -> Color? {
        guard let output = entry?.output else { return nil }
        let verdict = SymptomRadarModel.verdict(today: output, accumulation: .none,
                                                reported: said)
        switch verdict.status {
        case .quiet:
            // The fourth colour, and the only cut not already on the card: a
            // quiet morning with a channel leaning is drawn paler than a quiet
            // morning with nothing leaning at all. `leaning` is the model's own
            // property — no new threshold is invented here.
            return output.leaning.isEmpty
                ? Theme.good.opacity(0.55)
                : Theme.warn.opacity(0.35)
        case .someSigns: return Theme.warn.opacity(0.85)
        case .strongSigns: return Theme.bad.opacity(0.85)
        }
    }

    /// The tapped day, spelled out. **Fixed height in both states**, so
    /// selecting a day cannot shuffle the calendar under the finger that
    /// selected it — the same rule the charts follow (`add-chart` §9b).
    @ViewBuilder private func readout(_ spoken: [Date: ReportedIllness.Output]) -> some View {
        let said = selected.flatMap { spoken[calendar.startOfDay(for: $0)] } ?? .silent
        VStack(alignment: .leading, spacing: 3) {
            if let selected, let entry = row(for: selected), let output = entry.output {
                let span = SymptomRadarModel.span(covering: selected, in: spans,
                                                  calendar: calendar)
                let verdict = SymptomRadarModel.verdict(today: output,
                                                        accumulation: .none, reported: said)
                HStack(spacing: 6) {
                    Circle().fill(fill(for: entry, said: said) ?? .clear)
                        .frame(width: 8, height: 8)
                    Text(selected.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                    Text("\(Int(verdict.score.rounded()))")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                    Text(phrase(for: verdict.status))
                        .foregroundStyle(.secondary)
                    if span != nil, output.status == .quiet {
                        Text("· carried")
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    openDayLink(selected)
                }
                .font(.caption2)
            } else if let selected, said.isSpeaking {
                // A day nothing was worn and the reader spoke about. Not
                // "nothing judged that day" — that sentence, on a day they had
                // just marked as severe illness, is the app telling them their
                // own record does not exist.
                HStack(spacing: 6) {
                    Circle().fill(Color.primary).frame(width: 6, height: 6)
                    Text(selected.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                    Text("nothing measured")
                        .foregroundStyle(.tertiary)
                    Spacer()
                    openDayLink(selected)
                }
                .font(.caption2)
            } else {
                HStack {
                    Text(selected == nil ? "Tap a day" : "Nothing judged that day")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .font(.caption2)
            }
            // What the reader themselves said about the day, in their own
            // records' words — `ReportedIllness` writes these phrases and every
            // one of them reports what was recorded, never what it means.
            ForEach(said.components) { component in
                Text(component.detail)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// **B11-2's way in from the calendar.** A `NavigationLink` on the readout
    /// rather than on the square itself: the square's tap already means "select
    /// this day", and making it navigate as well would take the reader off the
    /// month every time they browsed it.
    private func openDayLink(_ day: Date) -> some View {
        NavigationLink {
            SickDayDetailView(day: day, history: history)
        } label: {
            Text("Open day")
                .font(.caption2.weight(.medium))
        }
    }

    private var calendarLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                swatch(Theme.good.opacity(0.55), "Nothing stirring")
                swatch(Theme.warn.opacity(0.35), "One channel off")
                Spacer()
            }
            HStack(spacing: 10) {
                swatch(Theme.warn.opacity(0.85), "Some signs")
                swatch(Theme.bad.opacity(0.85), "Strong signs")
                Spacer()
            }
            HStack(spacing: 10) {
                swatch(nil, "Not judged")
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary.opacity(0.75))
                        .frame(width: 14, height: 3)
                    Text("The card was still speaking")
                }
                Spacer()
            }
            HStack(spacing: 4) {
                Circle().fill(Color.primary).frame(width: 6, height: 6)
                    .frame(width: 11, height: 11)
                Text("You recorded something that day — a sick day, a symptom "
                     + "tag, or a side effect")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func swatch(_ colour: Color?, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(colour ?? Color.clear)
                .frame(width: 11, height: 11)
                .overlay {
                    if colour == nil {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    }
                }
            Text(label)
        }
    }

    // MARK: - Log

    /// **Every day the card was not quiet, newest first, grouped into the runs
    /// it read them as.** The same grouping the band draws, so the two views are
    /// two renderings of one fact rather than two computations that can drift.
    @ViewBuilder private var logView: some View {
        let spoken = spokenDays
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            if spans.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(history.contains { $0.output != nil }
                         ? "Nothing flagged in the last six months."
                         : "Nothing judged yet.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("That is not the same as six months of good health. It means "
                         + "no run of overnight readings sat far enough outside your own "
                         + "range for this card to say anything.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(spans.reversed()) { span in
                    spanBlock(span, spoken: spoken)
                }
            }
            recordedBlock
        }
    }

    /// **The days the reader recorded as illness, listed as their own record.**
    ///
    /// A separate block rather than rows folded into the spells above, and the
    /// reason is the same one that gives the calendar a separate mark:
    /// `flaggedSpans` groups by `DayHistory.isFlagged`, which is the
    /// *physiological* verdict, so a recorded sick day that the overnight
    /// numbers slept through is in no span and never will be. Inventing a span
    /// for it would put the reader's words inside a structure that means "your
    /// vitals departed", which is exactly the blend this section refuses.
    ///
    /// Without it the log said nothing at all about a correction the calendar
    /// beside it had just started drawing — the two halves of one section
    /// disagreeing, which is the shape of the bug being fixed.
    @ViewBuilder private var recordedBlock: some View {
        let window = replayWindow
        let periods = model.sickDayLedger.illness(in: window, calendar: calendar)
            .sorted { $0.firstDay > $1.firstDay }
        if !periods.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("What you recorded")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(periods.count) spell\(periods.count == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                ForEach(periods) { period in
                    NavigationLink {
                        SickDayDetailView(day: period.firstDay, history: history)
                    } label: {
                        recordedRow(period)
                    }
                    .buttonStyle(.plain)
                }
                Text("These are days you or your calendar said you were ill. Nothing "
                     + "here is a reading — a quiet card over one of them is the "
                     + "ordinary case, not a contradiction.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func recordedRow(_ period: SickDayLedger.Period) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.primary).frame(width: 6, height: 6)
            Text(rangeLabel(from: period.firstDay, to: period.lastDay))
                .font(.caption)
            Text(period.source == .entered ? "you said" : "your calendar")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Text(period.severity.map { $0 == .unstated ? "no grade" : $0.title.lowercased() }
                 ?? "no grade")
                .font(.caption2).foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this day in full")
    }

    /// The span the replay covers, so the recorded list matches the squares
    /// above it rather than reaching back past where the card can say anything.
    private var replayWindow: DateInterval {
        let end = calendar.date(byAdding: .day, value: 1,
                                to: calendar.startOfDay(for: Date()))
            ?? Date()
        let start = history.first?.day
            ?? calendar.date(byAdding: .day, value: -SymptomRadarModel.historyDays,
                             to: end) ?? end
        return DateInterval(start: min(start, end), end: end)
    }

    private func spanBlock(_ span: SymptomRadarModel.FlaggedSpan,
                           spoken: [Date: ReportedIllness.Output]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(rangeLabel(span))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(span.dayCount) day\(span.dayCount == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(span.days.reversed()) { entry in
                logRow(entry, in: span,
                       said: spoken[calendar.startOfDay(for: entry.day)] ?? .silent)
            }
            if span.carriedDays > 0 {
                Text("\(span.carriedDays) of these were quiet on their own numbers — "
                     + "the card kept speaking because the departure had been "
                     + "building, not because that morning was bad.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// **B11-2's way in from the log.** Every row navigates: unlike a calendar
    /// square, a log row has no other meaning for a tap, so the whole row is the
    /// target rather than a word at the end of it.
    private func logRow(_ entry: SymptomRadarModel.DayHistory,
                        in span: SymptomRadarModel.FlaggedSpan,
                        said: ReportedIllness.Output) -> some View {
        NavigationLink {
            SickDayDetailView(day: entry.day, history: history)
        } label: {
            logRowLabel(entry, in: span, said: said)
        }
        .buttonStyle(.plain)
    }

    private func logRowLabel(_ entry: SymptomRadarModel.DayHistory,
                             in span: SymptomRadarModel.FlaggedSpan,
                             said: ReportedIllness.Output) -> some View {
        let carried = entry.output?.status == .quiet
        return HStack(spacing: 6) {
            Circle().fill(fill(for: entry, said: said) ?? .clear)
                .frame(width: 7, height: 7)
            Text(entry.day.formatted(.dateTime.weekday(.abbreviated).day()
                                        .month(.abbreviated)))
                .font(.caption)
            if carried {
                Text("carried")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            // The same mark the square carries, for the same reason: a dot means
            // a person said something, and the dot must mean it in both views.
            if said.isSpeaking {
                Circle().fill(Color.primary).frame(width: 5, height: 5)
            }
            Spacer()
            // The day's own score, always — the number the colour came from.
            // Showing the verdict's here instead is how a log ends up
            // disagreeing with the calendar beside it.
            Text(entry.dailyScore.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(.secondary)
            // The row navigates, so it has to look like it does — a tappable
            // row with no affordance is a feature reachable only by accident.
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this day in full")
    }

    private func rangeLabel(_ span: SymptomRadarModel.FlaggedSpan) -> String {
        rangeLabel(from: span.start, to: span.end)
    }

    /// Shared with the recorded-spell rows, so a two-day flagged run and a
    /// two-day sick spell are written the same way in one list.
    private func rangeLabel(from start: Date, to end: Date) -> String {
        let first = start.formatted(.dateTime.day().month(.abbreviated))
        guard !calendar.isDate(start, inSameDayAs: end) else { return first }
        return "\(first) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    // MARK: - Words

    private func phrase(for status: SymptomRadarStatus) -> String {
        switch status {
        case .quiet: return "nothing stirring"
        case .someSigns: return "some signs"
        case .strongSigns: return "strong signs"
        }
    }

    private func accessibilityLabel(day: Date,
                                    entry: SymptomRadarModel.DayHistory?,
                                    span: SymptomRadarModel.FlaggedSpan?,
                                    said: ReportedIllness.Output) -> String {
        let date = day.formatted(date: .abbreviated, time: .omitted)
        // Said before judged, and said even where nothing was judged: the mark
        // on the square is the reader's own record, and a label that dropped it
        // would put VoiceOver back where the colour was before this fix.
        let spoken = said.components.map(\.detail)
        guard let output = entry?.output else {
            return ([date, "not judged"] + spoken).joined(separator: ", ")
        }
        let verdict = SymptomRadarModel.verdict(today: output, accumulation: .none,
                                                reported: said)
        var parts = ["\(date), \(phrase(for: verdict.status)), "
                     + "score \(Int(verdict.score.rounded()))"]
        parts += spoken
        if span != nil { parts.append("inside a flagged run") }
        return parts.joined(separator: ", ")
    }
}
