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
/// (`docs/illness-detection-evidence-2026-08-07.md`). This section deliberately
/// does not draw the reader's recorded sick days over the top — same restraint,
/// same reason, as `SickDaysSection`.
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

    var body: some View {
        InsightSection(
            title: "Day by day",
            trailing: spans.isEmpty ? nil
                : "\(spans.count) spell\(spans.count == 1 ? "" : "s")",
            caveat: .computed(.replayed,
                              "Each day is judged the way this morning was — against "
                              + "the three weeks before it, ending four days before "
                              + "the window it judges. A square's colour is that day "
                              + "on its own; the bar under a run of days is the "
                              + "accumulation, which is what the card was actually "
                              + "saying. Days nothing was worn are blank, not green."),
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
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            MonthStepper(month: $month, calendar: calendar,
                         canGoBack: canStep(-1), canGoForward: canStep(1))
            // 33 = the 28pt square, the 2pt gap and the 3pt band bar. A blank
            // leading slot that disagreed with a real cell by a point would
            // make the first week of a month a different height from the rest.
            MonthGrid(month: month, calendar: calendar, rowHeight: 33) { day in
                dayCell(day)
            }
            readout
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

    @ViewBuilder private func dayCell(_ day: Date) -> some View {
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
                    .foregroundStyle(entry?.output == nil
                                     ? Color.secondary.opacity(isFuture ? 0.35 : 0.7)
                                     : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if let fill = fill(for: entry) {
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
                bandBar(span, day: day)
            }
        }
        .buttonStyle(.plain)
        .disabled(entry?.output == nil)
        .accessibilityLabel(accessibilityLabel(day: day, entry: entry, span: span))
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

    /// **The day's own statistic, and only ever the day's own.**
    ///
    /// Nil where the watch could not judge the day — an unworn night is missing
    /// evidence, and painting it green would be the app answering a question
    /// nobody measured.
    private func fill(for entry: SymptomRadarModel.DayHistory?) -> Color? {
        guard let output = entry?.output else { return nil }
        switch output.status {
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
    @ViewBuilder private var readout: some View {
        if let selected, let entry = row(for: selected), let output = entry.output {
            let span = SymptomRadarModel.span(covering: selected, in: spans,
                                              calendar: calendar)
            HStack(spacing: 6) {
                Circle().fill(fill(for: entry) ?? .clear).frame(width: 8, height: 8)
                Text(selected.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                Text("\(Int(output.score.rounded()))")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(phrase(for: output.status))
                    .foregroundStyle(.secondary)
                if span != nil, output.status == .quiet {
                    Text("· carried")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
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
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                ForEach(spans.reversed()) { span in
                    spanBlock(span)
                }
            }
        }
    }

    private func spanBlock(_ span: SymptomRadarModel.FlaggedSpan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(rangeLabel(span))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(span.dayCount) day\(span.dayCount == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(span.days.reversed()) { entry in
                logRow(entry, in: span)
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

    private func logRow(_ entry: SymptomRadarModel.DayHistory,
                        in span: SymptomRadarModel.FlaggedSpan) -> some View {
        let carried = entry.output?.status == .quiet
        return HStack(spacing: 6) {
            Circle().fill(fill(for: entry) ?? .clear).frame(width: 7, height: 7)
            Text(entry.day.formatted(.dateTime.weekday(.abbreviated).day()
                                        .month(.abbreviated)))
                .font(.caption)
            if carried {
                Text("carried")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            // The day's own score, always — the number the colour came from.
            // Showing the verdict's here instead is how a log ends up
            // disagreeing with the calendar beside it.
            Text(entry.dailyScore.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func rangeLabel(_ span: SymptomRadarModel.FlaggedSpan) -> String {
        let start = span.start.formatted(.dateTime.day().month(.abbreviated))
        guard !calendar.isDate(span.start, inSameDayAs: span.end) else { return start }
        return "\(start) – \(span.end.formatted(.dateTime.day().month(.abbreviated)))"
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
                                    span: SymptomRadarModel.FlaggedSpan?) -> String {
        let date = day.formatted(date: .abbreviated, time: .omitted)
        guard let output = entry?.output else { return "\(date), not judged" }
        var parts = ["\(date), \(phrase(for: output.status)), "
                     + "score \(Int(output.score.rounded()))"]
        if span != nil { parts.append("inside a flagged run") }
        return parts.joined(separator: ", ")
    }
}
