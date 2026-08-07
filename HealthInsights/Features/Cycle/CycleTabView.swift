import SwiftUI
import InsightKit

/// **The fifth tab.** Backlog #31, and the largest thing the reader asked for.
///
/// ## What this tab is
///
/// A working period tracker: a calendar you tap to log, the cycle you are in,
/// **the range your cycles actually fall in**, the phase you are probably in,
/// and the fertile window. It is the thing Flo charges for and Oura puts behind
/// a subscription, minus the subscription.
///
/// Slice 1 (`a8be5ae`) was the log and its arithmetic. Slice 2 is the model on
/// top: `CyclePhaseModel` and `PhaseAwareBaseline`. The order was not an
/// accident — a phase model needs cycles to predict from, and starting there is
/// how this repo has three times shipped a model with nothing under it.
///
/// ## The three design rules, all enforced below rather than remembered
///
/// 1. **A cycle length is a range, never a number.** `CycleSummary` has no
///    `averageLength` for the view to reach for.
/// 2. **A modelled phase is never asserted flatly.** Every line comes from
///    `CyclePhaseModel.phaseSentence`, which either names a logged fact or
///    hedges and shows its ±.
/// 3. ⚠️ **The not-contraception sentence is on the screen, permanently.**
///    `CyclePhaseModel.notContraceptionNotice`, in a caption that is always
///    rendered — not a disclosure, not a sheet, not an alert the reader
///    dismisses once. A fertile window presented as a way to avoid pregnancy is
///    a regulated medical claim and this app makes none.
///
/// ## Where the phase-aware shifts come from, and where they do not go
///
/// The shifts card reads `AppModel.cyclePhaseProfile` and renders **only
/// measured** shifts — a literature prior is never printed as the reader's own
/// number. And nothing here feeds the symptom radar: see the TODO on
/// `PhaseAwareBaseline`, which cannot be closed without redoing the radar's
/// calibration.
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
                    fertileWindowCard
                    phaseShiftsCard
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
                // The phase, immediately under the day number, because "day 21"
                // and "probably luteal, day 6 ±3" are the same fact said twice
                // and separating them across cards would invite the reader to
                // trust the precise-looking one.
                if let phase = model.currentCyclePhase {
                    Text(CyclePhaseModel.phaseSentence(phase))
                        .font(.headline)
                        .foregroundStyle(phase.isObserved ? Theme.accent : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // MARK: - The fertile window

    /// ⚠️ **Always rendered, in both states.** When the model can draw a window
    /// this shows it; when it cannot, it shows the model's own refusal sentence
    /// rather than an empty box or a hidden card — which is
    /// `docs/data-conventions.md`'s rule that an empty page must read as empty
    /// and not as broken.
    private var fertileWindowCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                Text("Fertile window").font(.headline)
                switch model.cycleForecast {
                case let .forecast(prediction):
                    Text(windowRange(prediction))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.cycleFertile)
                    Text(CyclePhaseModel.fertileWindowSentence(prediction, calendar: calendar))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case let .refused(reason):
                    Text(reason.sentence)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Rule 3. Small, permanent, and never behind a tap.
                Text(CyclePhaseModel.notContraceptionNotice)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func windowRange(_ prediction: CyclePrediction) -> String {
        let window = prediction.fertileWindow
        let opens = window.core.lowerBound.formatted(.dateTime.day().month(.abbreviated))
        let closes = window.core.upperBound.formatted(.dateTime.day().month(.abbreviated))
        return "\(opens) – \(closes)"
    }

    // MARK: - What this phase does to your body

    /// Only what was **measured on this reader**, and only when the shift is
    /// bigger than its own error bar.
    ///
    /// Two gates rather than one. `isMeasured` keeps the literature priors off
    /// the screen — a published +2 bpm rendered as "your resting heart rate
    /// runs +2" is the precise dishonesty `PhaseAwareBaseline` exists to
    /// prevent. The second gate drops a shift smaller than its ±, which is not
    /// a shift; it is the noise floor with a sign.
    @ViewBuilder private var phaseShiftsCard: some View {
        let phase = model.currentCyclePhase?.phase
        let shifts = (phase.map(measuredShifts) ?? [])
        if let phase, !shifts.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    Text("In your \(phase.title.lowercased()) phase").font(.headline)
                    ForEach(shifts, id: \.metric) { shift in
                        Text(shift.sentence)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Your own numbers, split by phase — which is why they are worth having. A normal luteal phase raises heart rate and lowers HRV in everybody, and knowing your own size for it is the difference between a pattern and a symptom.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func measuredShifts(_ phase: CyclePhase) -> [PhaseAwareBaseline.PhaseShift] {
        PhaseAwareBaseline.defaultMetrics.compactMap { metric in
            guard let shift = model.cyclePhaseProfile.expectedShift(metric: metric, phase: phase),
                  shift.isMeasured,
                  abs(shift.delta) > shift.uncertainty
            else { return nil }
            return shift
        }
    }

    // MARK: - The calendar

    private var calendarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                // Forward runs to the month holding the predicted period, and no
                // further.
                //
                // ⚠️ **It used to stop at the current month, and that would have
                // hidden the feature it now has.** A fertile window falling
                // after the 1st was simply unreachable. The reason for the old
                // limit — "a cycle log is a record of what happened, and
                // offering to log next Tuesday invites a guess into a dataset
                // every length is computed from" — is still right and is still
                // enforced, by `.disabled(isFuture)` on the cell itself. Seeing
                // a future day is not logging one.
                MonthStepper(month: $month, calendar: calendar,
                             canGoForward: canGoForward)
                // The grid, the weekday header and the reader's own first
                // weekday all live in `MonthGrid` now — shared with the symptom
                // radar's calendar rather than copied into it (§B11-1).
                MonthGrid(month: month, calendar: calendar) { day in
                    dayCell(day)
                }
                legend
            }
        }
    }

    /// The furthest month worth showing: the one holding the predicted period,
    /// so the whole fertile window is reachable however late in the month it
    /// falls. With no prediction there is nothing ahead to look at, so it is
    /// today — the behaviour this tab shipped with.
    private var forwardLimit: Date {
        model.cycleForecast.prediction?.nextPeriodStart ?? Date()
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: month),
              let limit = calendar.dateInterval(of: .month, for: forwardLimit)?.start
        else { return false }
        return next <= limit
    }

    @ViewBuilder private func dayCell(_ day: Date) -> some View {
        let logged = model.cycleDays.first { calendar.isDate($0.day, inSameDayAs: day) }
        let isFuture = day > calendar.startOfDay(for: Date())
        let fertile = fertileOpacity(day)
        Button {
            picking = day
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption)
                .foregroundStyle(logged != nil ? Color.white
                                 : (isFuture && fertile == nil ? Color.secondary.opacity(0.4)
                                    : .primary))
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
                    } else if let fertile {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.cycleFertile.opacity(fertile))
                    }
                }
                // Drawn over whatever fill won, so today is still findable on a
                // day that is both logged and inside a window.
                .overlay {
                    if calendar.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    /// How strongly to shade a day as fertile, or nil for a day outside the
    /// window entirely.
    ///
    /// ⚠️ **The fade *is* the uncertainty, not decoration.** Inside the six-day
    /// core the shading is flat; across the ± days either side it ramps down to
    /// nothing. A hard edge would draw an interval the model does not have, and
    /// the whole difference between this and every other tracker is that it
    /// declines to.
    private func fertileOpacity(_ day: Date) -> Double? {
        guard let window = model.cycleForecast.prediction?.fertileWindow else { return nil }
        let start = calendar.startOfDay(for: day)
        if window.core.contains(start) { return coreFertileOpacity }
        guard window.outer.contains(start), window.uncertaintyDays > 0 else { return nil }
        let distance = min(
            abs(calendar.dateComponents([.day], from: window.core.lowerBound,
                                        to: start).day ?? 0),
            abs(calendar.dateComponents([.day], from: window.core.upperBound,
                                        to: start).day ?? 0))
        // Linear from the core's edge out to the last day the ± reaches, never
        // quite to zero — a day inside the interval must still be visible.
        let falloff = 1 - Double(distance) / Double(window.uncertaintyDays + 1)
        return coreFertileOpacity * falloff
    }

    private let coreFertileOpacity = 0.45

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if model.cycleForecast.prediction != nil {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.cycleFertile.opacity(coreFertileOpacity))
                            .frame(width: 10, height: 10)
                        Text("Fertile window").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.cycleFertile.opacity(coreFertileOpacity * 0.35))
                            .frame(width: 10, height: 10)
                        Text("Could be either side").font(.caption2).foregroundStyle(.secondary)
                    }
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
            Text("Ovulation is worked out backwards from your next expected period, not forwards from your last one — the second half of a cycle is the steady one at about \(CyclePhaseModel.lutealLengthDays) days, and the first half is where cycles differ. That is why the ± here comes from how much *your* cycles vary rather than from a textbook.")
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }
}
