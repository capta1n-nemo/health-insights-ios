import SwiftUI
import InsightKit

/// **The week's headphone dose against WHO's allowance, day by day** — backlog
/// §B3 #22 / §B5 #33.
///
/// Two sections, because there are two subjects and one of them is a caveat:
/// what you took on through headphones (a running total against a published
/// budget) and what your watch heard around you (a reading, with its coverage
/// stated, that is never added to the first).
///
/// ⚠️ **Deliberately not a `Chart`.** Seven bars whose lengths are a share of
/// one budget need no pan, no scrub and no date axis — and a date axis is the
/// only thing the substance shading can land on, so a `Chart` here would buy the
/// `Chart3DContent` overload hazard and the stacked-gap hazard in exchange for
/// nothing. Same reasoning, and the same shape, as `effortIntensitySection`.
///
/// ⚠️ **The bar is the day's share of the *weekly* allowance, not of itself.**
/// Normalising each row to the loudest day would draw a quiet week and a
/// dangerous one identically, which is the mistake this section exists to
/// prevent: the whole finding is how much of a fixed budget went in one day.
struct SoundExposureSection: View {
    let output: SoundExposureModel.Output

    /// A day using more than this share of the *week's* allowance is the one
    /// worth looking at. A seventh is the flat rate — an even week — so a fifth
    /// is a day that ran ahead of the budget without being alarming about it.
    private static let notableDayShare = 0.2

    var body: some View {
        headphoneSection
        environmentSection
    }

    // MARK: - What you took on

    private var headphoneSection: some View {
        InsightSection(
            title: "What you took on",
            trailing: String(format: "%.0f%% of the week", output.allowanceUsed * 100),
            caveat: .computed(.partial,
                              "Your iPhone estimates the level it drove your headphones at; it cannot hear your ears. Audio through a laptop, a car or a speaker is not here and arrives as silence. The allowance is the World Health Organization's population exposure limit — 40 hours a week at 80 dB(A) — not a personal safety line."),
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 10) {
                budgetBar
                if output.days.isEmpty {
                    // The quiet week, said as a fact. It is a real reading —
                    // headphone exposure is written by the device doing the
                    // playing, so nothing recorded means nothing played — and
                    // an empty section here would read as a broken sensor.
                    Text("Nothing played through your headphones in the last \(SoundExposureModel.windowDays) days. Your iPhone has \(output.historyDays) days of headphone audio on record, so this is a quiet week rather than a gap in the data.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(output.days.reversed()) { day in
                        dayRow(day)
                    }
                    Divider()
                    Text(String(format: "%.1f hours of listening, carrying the same energy as %.0f hours at %.0f dB(A). Every 3 dB doubles how fast the allowance goes: an hour at 83 dB(A) costs what two hours at 80 do.",
                                output.listeningHours,
                                SoundExposureModel.allowanceHours,
                                output.equivalentLevelOver40Hours))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let loudest = output.loudestDay {
                        Text("At your loudest day's level the NIOSH occupational limit allows \(SoundExposureModel.permittedTimePhrase(atLevel: loudest.level)) — a different budget from the weekly one above, for an eight-hour working day, shown because it is the one that turns a percentage into a length of time.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The whole week against the whole allowance, in one bar.
    ///
    /// It runs past its own track when the week went over, rather than filling
    /// and stopping: a bar pinned at 100% draws a week at the limit and a week
    /// at four times it identically, and the second is the one somebody needs
    /// to see. Past the end it is clipped to twice the track and the figure
    /// beside it carries the real number.
    private var budgetBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let share = min(2, max(0, output.allowanceUsed))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Theme.color(forScore: output.score))
                        .frame(width: geometry.size.width * min(1, share))
                    // The overspend, drawn beyond the track's own end so a week
                    // over the allowance is visibly over rather than merely
                    // full.
                    if share > 1 {
                        Capsule()
                            .fill(Theme.color(forScore: output.score).opacity(0.45))
                            .frame(width: geometry.size.width * (share - 1))
                            .offset(x: geometry.size.width)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            Text(String(format: "%.1f of %.0f allowance-hours used",
                        output.allowanceHoursUsed, SoundExposureModel.allowanceHours))
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
        }
    }

    private func dayRow(_ day: SoundExposureModel.Day) -> some View {
        let share = day.allowanceHoursUsed / SoundExposureModel.allowanceHours
        return HStack(spacing: 8) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(share >= Self.notableDayShare
                              ? Theme.accent : Theme.accent.opacity(0.45))
                        .frame(width: geometry.size.width * min(1, share))
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            // Both halves of the dose, because either alone is misleading: the
            // level says how loud and the hours say how long, and the same
            // percentage can come from very different weeks.
            Text(String(format: "%.0f dB · %@", day.level,
                        day.hours >= 1
                            ? String(format: "%.1f h", day.hours)
                            : String(format: "%.0f m", day.hours * 60)))
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                .frame(width: 92, alignment: .trailing)
        }
    }

    // MARK: - What was around you

    /// ⚠️ **This section's caveat is its content.** The refusal this card
    /// reverses said environmental audio *"exists on 14 of the last 90 days and
    /// summing would invent the quiet hours"*, and that is still true — so the
    /// coverage sentence is not a footnote here, it is the reason the figure is
    /// shown at all rather than added to the one above.
    @ViewBuilder private var environmentSection: some View {
        if let environment = output.environment {
            InsightSection(
                title: "What was around you",
                trailing: String(format: "%.0f dB(A)", environment.latest.level),
                caveat: .computed(.partial,
                                  "Measured by your watch, and only while it was on your wrist and listening. It is never added to the headphone figure above."),
                expansion: .collapsed(
                    preview: String(format: "%.0f dB(A) on the last day your watch heard anything, over %d of the last %d days",
                                    environment.latest.level,
                                    environment.daysMeasured,
                                    SoundExposureModel.coverageDays))
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(environment.latest.date, format: .dateTime.day().month(.abbreviated))
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f dB(A) over %.1f hours",
                                    environment.latest.level, environment.latest.hours))
                            .font(.subheadline).monospacedDigit()
                    }
                    coverageBar(environment)
                    Text(SoundExposureModel.coveragePhrase(environment))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// How much of the last ninety days the watch heard — the figure that keeps
    /// this section honest, drawn rather than only stated.
    private func coverageBar(_ environment: SoundExposureModel.Environment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Theme.accent.opacity(0.5))
                        .frame(width: geometry.size.width * min(1, max(0, environment.coverage)))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            Text("\(environment.daysMeasured) of \(SoundExposureModel.coverageDays) days measured")
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
        }
    }
}
