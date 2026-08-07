import SwiftUI
import InsightKit

/// **"Sleep and travel"** — the nights the reader crossed a zone, rendered in the
/// zone they are in now.
///
/// The reader, 2026-08-07: *"Sleep needs to be timezone and travel aware,
/// yesterday i was in the phillipines, today i am back in australia, i also
/// slept on the plane, all these things need to clearly report in MY current
/// timezone and all show correctly."* (Backlog `D56`.)
///
/// ## Why this section exists rather than a quiet fix inside the sleep card
///
/// The arithmetic landed first — `SleepTravel` in InsightKit, with the whole
/// argument for why a stored `.sleepOnset` is an instant in disguise and can
/// therefore be re-rendered in any zone without a migration. **Nothing called
/// it from a view**, which in this repo means it shipped nothing: the reader's
/// bedtimes still render from the stored number, baked at ingest in whatever
/// zone the phone was in that night.
///
/// Two things could have happened next, and the difference matters.
///
/// **The invisible fix** would re-render every `.sleepOnset` at read time and
/// change the fortnight chart, the strip, the consistency figure and the ideal
/// window all at once. That is the right end state and it is *not* what this is
/// — see the report accompanying this work for the precise change, because it
/// touches `AppModel` and two charts that assume bedtimes live within ±6 h of
/// midnight, which a well-travelled reader's no longer do.
///
/// **The visible one** is this: a section that shows the affected nights, both
/// clock readings side by side, and says which figure is which. It is worth
/// having even after the invisible fix lands, because a duration that disagrees
/// with the clock times beside it reads as a bug unless something says why.
///
/// ## The three answers this section is required to state out loud
///
/// 1. **Bedtimes here are in your current time zone.** The stored instant is
///    canonical; the rendering converts. That is the reader's own instruction.
/// 2. **A night's length is time actually asleep — elapsed, not what the clock
///    said.** `SleepNights` always summed segment durations and nobody had ever
///    written it down, which is worse than being wrong: a reader doing the
///    subtraction themselves gets a different answer and cannot tell which to
///    believe.
/// 3. **Daytime sleep is not in the night's total.** Four hours over the Timor
///    Sea at 14:00 is dropped by the night rule, correctly and silently. This
///    is the only place in the app that says so.
struct SleepTravelSection: View {
    @Environment(AppModel.self) private var model

    /// How far back to look for a journey. A season, because a card about
    /// travel with nothing on it is not the same as a card about travel whose
    /// last trip was in March, and 90 days is long enough to hold the second.
    private static let lookbackDays = 90

    /// Eight rows. A frequent traveller's ninety days can hold dozens of these,
    /// and a section that renders all of them stops being a section — it becomes
    /// a list nobody scrolls to the end of, on a card that already has ten.
    /// The count of what is not shown is printed rather than swallowed.
    private static let maximumRows = 8

    var body: some View {
        let nights = model.memoized("sleepTravelNights.\(Self.lookbackDays)") {
            travelNights()
        }
        InsightSection(
            title: "Sleep and travel",
            trailing: trailing(nights),
            caveat: .computed(.partial, Self.caveatText),
            expansion: nights.isEmpty
                ? .collapsed(preview: Self.emptyPreview)
                : .open
        ) {
            if nights.isEmpty {
                emptyBody
            } else {
                zoneStatement
                Divider()
                let shown = Array(nights.prefix(Self.maximumRows))
                ForEach(shown) { night in
                    nightRow(night)
                    if night.id != shown.last?.id { Divider() }
                }
                if nights.count > shown.count {
                    Text("\(nights.count - shown.count) older nights like these are "
                         + "not listed. Every one of them is in the Data tab.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - What counts as a night worth showing

    /// Nights in the window that either crossed a zone or hold sleep the night
    /// rule could not claim.
    ///
    /// An ordinary night at home is deliberately absent: every other section on
    /// this card already draws those, and repeating them here would bury the
    /// two the reader actually asked about.
    private func travelNights() -> [SleepTravel.Night] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays,
                                           to: Date()) ?? .distantPast
        // Deliberately **not** `Calendar(identifier:)` with a fixed zone: the
        // whole claim is that this renders in the reader's *current* calendar,
        // and hard-coding one here would be the defect wearing a different hat.
        return SleepTravel.nights(samples: model.samples,
                                  raw: model.otherSamples,
                                  calendar: .current)
            .filter { $0.day >= cutoff }
            .filter { night in
                night.crossedZones == true || (night.daytimeHours ?? 0) >= 0.5
            }
            .sorted { $0.day > $1.day }
    }

    /// The one figure: how many of the nights on the record crossed a zone.
    /// Never a count of *something else* when that is unavailable — an empty
    /// slot instead, per `InsightSection`'s rule.
    private func trailing(_ nights: [SleepTravel.Night]) -> String? {
        let crossed = nights.filter { $0.crossedZones == true }.count
        guard crossed > 0 else { return nil }
        return crossed == 1 ? "1 night moved" : "\(crossed) nights moved"
    }

    // MARK: - The statements

    @ViewBuilder private var zoneStatement: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shown in \(Self.currentZoneName)")
                .font(.subheadline.weight(.semibold))
            Text("Every clock time on this card is your current time zone, "
                 + "including nights you slept somewhere else. The moment is what "
                 + "was recorded; the clock face is worked out from where you are "
                 + "now.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A night's length is time actually asleep. It does not change "
                 + "when the clock does, which is why it can differ from the gap "
                 + "between the two clock times beside it.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `Australia/Sydney` → "Sydney time". Built by hand rather than with
    /// `TimeZone.localizedName`, which returns "Australian Eastern Standard
    /// Time" — accurate, and four words too long for a heading.
    private static var currentZoneName: String {
        let id = TimeZone.current.identifier
        guard let city = id.split(separator: "/").last else { return id }
        return city.replacingOccurrences(of: "_", with: " ") + " time"
    }

    // MARK: - One night

    @ViewBuilder private func nightRow(_ night: SleepTravel.Night) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(night.day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let elapsed = night.elapsedHours {
                    Text(String(format: "%.1f h asleep", elapsed))
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(Theme.metricColor(.sleepDurationHours))
                }
            }

            if let here = night.onsetHoursHere {
                clockLine(here: here, there: night.onsetHoursThere)
            }

            if let elapsed = night.elapsedHours, let wall = night.wallClockHours,
               abs(wall - elapsed) >= 0.25 {
                // Both numbers, both named. The gap between them *is* the
                // journey, and hiding either is how a reader ends up trusting
                // neither.
                Text(String(format: "The clock either side of it moved %.1f h — "
                            + "asleep %.1f h, clock-to-clock %.1f h.",
                            wall - elapsed, elapsed, wall))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = night.note {
                Text(note)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if night.crossedZones == nil {
                // ⚠️ **Unknown is not "stayed put".** Apple Health supplies no
                // UTC offset on this path, so an Apple-only night cannot say
                // whether anything moved. Saying nothing at all would let the
                // reader read the absence as a "no".
                Text("No source recorded a time zone for this night, so whether "
                     + "the clock moved is unknown rather than no.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bedtime here, and — when a source recorded a zone — bedtime there.
    @ViewBuilder private func clockLine(here: Double, there: Double?) -> some View {
        HStack(spacing: 10) {
            Label(SleepTravel.Night.clockText(here), systemImage: "bed.double")
                .font(.caption).monospacedDigit()
                .labelStyle(.titleAndIcon)
            if let there, abs(there - here) >= 0.25 {
                Text("· \(SleepTravel.Night.clockText(there)) where you were")
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Nothing to show

    @ViewBuilder private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No night in the last \(Self.lookbackDays) days both crossed a "
                 + "time zone and was recorded by something that noticed.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A time zone is only known when the source stamps one on the "
                 + "reading. Oura does; Apple Health does not. So a journey slept "
                 + "through on the watch alone will not appear here — that is a "
                 + "gap in what was recorded, not evidence you stayed put.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let emptyPreview =
        "No recorded night has crossed a time zone in the last 90 days"

    /// `.partial`, and the wording says which part. The clock conversion is
    /// exact; what is incomplete is *coverage* — only a source that stamps a UTC
    /// offset can say a night moved at all.
    private static let caveatText =
        "Clock times are converted from the moment each night was recorded, "
        + "which is exact. Whether a night crossed a time zone is only known for "
        + "sources that stamp one on the reading — Oura does, Apple Health does "
        + "not — so a night with no zone is unknown, never assumed. Daytime sleep "
        + "is reported here and is deliberately not part of any night's total."
}
