import SwiftUI
import InsightKit

/// **The fifth tab.** Backlog #31, and the largest thing the reader asked for.
///
/// ## What this slice is
///
/// A working period tracker: a calendar you tap to log, the cycle you are in,
/// and **the range your cycles actually fall in**. That is complete on its own —
/// it is the thing Flo charges for and Oura puts behind a subscription, minus
/// the subscription.
///
/// ## What it deliberately is not, yet
///
/// No fertile window, no phase model, no prediction. Those are the next slice
/// and they need what this one produces: cycles to predict from. The reader
/// asked for the fertile window in the strongest terms — *"YES! THAT'S THE WHOLE
/// POINT"* — and it is coming; starting there would have shipped a model with
/// nothing under it, which this repo has done three times and written down
/// twice.
///
/// ## The one design rule
///
/// **A cycle length is a range, never a number.** Every consumer tracker prints
/// "your cycle is 28 days" and every one of them is asserting a precision three
/// observations cannot support. `CycleSummary` has no `averageLength` for the
/// view to reach for, which is the version of this rule that survives a refactor.
struct CycleTabView: View {
    @Environment(AppModel.self) private var model
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var picking: Date?

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    summaryCard
                    calendarCard
                    historyCard
                    footnote
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Cycle")
        }
        .confirmationDialog("Log this day", isPresented: Binding(
            get: { picking != nil },
            set: { if !$0 { picking = nil } })
        ) {
            if let day = picking {
                ForEach(MenstrualFlowLevel.allCases) { level in
                    Button(level.title) {
                        model.setCycleDay(day, flow: level)
                        picking = nil
                    }
                }
                if model.cycleDays.contains(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                    Button("Remove", role: .destructive) {
                        model.clearCycleDay(day)
                        picking = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { picking = nil }
        } message: {
            Text(picking.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
        }
    }

    // MARK: - Where you are

    private var summaryCard: some View {
        let summary = model.cycleSummary
        return Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                Text(CycleModel.headline(summary))
                    .font(.largeTitle.weight(.semibold))
                if let current = summary.current {
                    Text("This one started \(current.start.formatted(date: .abbreviated, time: .omitted)), and ran \(current.periodLength(calendar: calendar)) day\(current.periodLength(calendar: calendar) == 1 ? "" : "s").")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(CycleModel.lengthSentence(summary))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The calendar

    private var calendarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                HStack {
                    Button {
                        month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
                    } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Spacer()
                    Button {
                        month = calendar.date(byAdding: .month, value: 1, to: month) ?? month
                    } label: { Image(systemName: "chevron.right") }
                    // Forward is stopped at the current month: a cycle log is a
                    // record of what happened, and offering to log next Tuesday
                    // invites a guess into a dataset every length is computed
                    // from.
                    .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
                }
                weekdayHeader
                monthGrid
                legend
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Weekday initials starting on the reader's own first weekday — Sunday in
    /// the US, Monday across most of Europe. Hard-coding Monday would put every
    /// logged day in the wrong column for half the world.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthGrid: some View {
        let days = monthDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2),
                                        count: 7), spacing: 4) {
            ForEach(days.indices, id: \.self) { index in
                if let day = days[index] {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    /// The month's days, padded with nils so the first lands under its weekday.
    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = (0..<count).map {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + days
    }

    @ViewBuilder private func dayCell(_ day: Date) -> some View {
        let logged = model.cycleDays.first { calendar.isDate($0.day, inSameDayAs: day) }
        let isFuture = day > calendar.startOfDay(for: Date())
        Button {
            picking = day
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption)
                .foregroundStyle(logged != nil ? Color.white
                                 : (isFuture ? Color.secondary.opacity(0.4) : .primary))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    if let logged {
                        // Opacity carries the flow level. Deliberately one hue
                        // with four strengths rather than four hues: the
                        // quantity has an order, and the app's own radial rule
                        // is that a fill's ramp follows its quantity's axis.
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.warn.opacity(0.35 + 0.65 * logged.flow.intensity))
                    } else if calendar.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(MenstrualFlowLevel.allCases) { level in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.warn.opacity(0.35 + 0.65 * level.intensity))
                        .frame(width: 10, height: 10)
                    Text(level.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - What has happened

    @ViewBuilder private var historyCard: some View {
        let summary = model.cycleSummary
        let completed = summary.cycles.filter { !$0.isInProgress }.reversed()
        if !completed.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    Text("Your cycles").font(.headline)
                    ForEach(Array(completed)) { cycle in
                        HStack {
                            Text(cycle.start.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                            Spacer()
                            Text("\(cycle.periodLength(calendar: calendar)) day period")
                                .font(.caption).foregroundStyle(.tertiary)
                            if let length = cycle.length(calendar: calendar) {
                                Text("\(length) days")
                                    .font(.subheadline.weight(.medium)).monospacedDigit()
                                    .frame(width: 62, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Days synced from Health appear here too. Tapping a day changes what is stored, so this stays your record rather than the app's guess at one.")
            Text("A fertile window and phase-aware baselines are next. They need cycles to work from, which is what this is collecting — and until there are enough, an app drawing one would be drawing an average of other people.")
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }
}
