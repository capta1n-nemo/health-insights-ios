import SwiftUI

/// **One month, laid out as a calendar.** The grid, the weekday header and the
/// leading blanks — and nothing about what a day *means*.
///
/// ## Why this is shared rather than copied
///
/// This was `private` to `CycleTabView` (`weekdayHeader`, `orderedWeekdaySymbols`,
/// `monthGrid`, `monthDays`) until §B11-1 needed a second month calendar for the
/// symptom radar. Copying it would have duplicated one thing in particular that
/// is easy to get wrong and invisible when you do:
///
/// ⚠️ **The first column is the reader's own first weekday**, not Monday and not
/// Sunday. `Calendar.firstWeekday` is Sunday in the US, Monday across most of
/// Europe, Saturday in much of the Middle East — and the leading blank count
/// must be computed against the same number the header was ordered by. Hard-code
/// either and every day in the month sits in the wrong column for half the
/// world, silently, on a screen that still looks like a calendar.
///
/// ## What it deliberately does not do
///
/// **It does not size or shape a day cell.** Callers pass whatever view a day
/// is — `CycleTabView`'s is a `Button` whose own label carries the frame, so its
/// whole cell stays tappable — and this only supplies the blank slots that pad
/// the first week, at `rowHeight`. Imposing a frame from out here would shrink a
/// plain-styled button's hit region to its text, which is a defect nobody sees
/// in a screenshot.
struct MonthGrid<Cell: View>: View {
    /// Any date inside the month to draw.
    let month: Date
    var calendar: Calendar = .current
    /// The height a blank leading slot reserves, so an incomplete first week
    /// does not collapse. Match it to whatever height the cells set themselves.
    var rowHeight: CGFloat = 34
    var columnSpacing: CGFloat = 2
    var rowSpacing: CGFloat = 4
    /// The gap between the weekday header and the grid.
    var headerSpacing: CGFloat = Theme.sectionSpacing
    @ViewBuilder let cell: (Date) -> Cell

    var body: some View {
        VStack(spacing: headerSpacing) {
            weekdayHeader
            grid
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: columnSpacing) {
            ForEach(Array(Self.orderedWeekdaySymbols(calendar).enumerated()),
                    id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = Self.days(in: month, calendar: calendar)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: columnSpacing),
                           count: 7),
            spacing: rowSpacing
        ) {
            ForEach(days.indices, id: \.self) { index in
                if let day = days[index] {
                    cell(day)
                } else {
                    Color.clear.frame(height: rowHeight)
                }
            }
        }
    }

    /// Weekday initials starting on the reader's own first weekday.
    ///
    /// ⚠️ Iterated by *offset* rather than by value: `veryShortStandaloneWeekdaySymbols`
    /// repeats itself in several locales (Spanish has two "M"s, German two "S"s),
    /// and `id: \.self` on the string would collapse them into one column.
    static func orderedWeekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let first = min(max(calendar.firstWeekday - 1, 0), 6)
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, padded with nils so the first lands under its weekday.
    static func days(in month: Date, calendar: Calendar) -> [Date?] {
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
}

/// **The month name, with a chevron either side.** Extracted alongside
/// `MonthGrid` and kept separate from it, because what counts as *too far* is
/// the caller's question and never the grid's: the cycle tab stops forward at
/// the month holding the predicted period, and the symptom radar stops at the
/// month holding the oldest day it can judge.
struct MonthStepper: View {
    @Binding var month: Date
    var calendar: Calendar = .current
    var canGoBack: Bool = true
    var canGoForward: Bool = true

    var body: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
                .disabled(!canGoBack)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                // The month name is what changed, so it is what a screen reader
                // should land on.
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
                .disabled(!canGoForward)
        }
    }

    private func step(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }
}
