import SwiftUI
import InsightKit

// substance-shading: exempt — no time axis. The bars are one night's channels
// against their own spreads, not a series through time, so a shading band
// marking when something was logged would have nothing to sit against.

/// **"What changed while you slept"** — backlog S5, the reader's own request,
/// and the request is precise about what it is not.
///
/// Four sleep sections already describe the night: how long it was, what shape
/// it had, when the heart settled, how disturbed the breathing was. The reader
/// asked for the *comparison* — what actually moved — which nothing on the card
/// answered, because answering it means putting milliseconds, breaths, degrees
/// and percent side by side, and those only become comparable after each is
/// divided by its own night-to-night spread.
///
/// ## What it draws, and what it refuses to add up
///
/// One row per nocturnal channel: last night's figure, how far it sits from the
/// reader's own recent nights, and **how far that is in that channel's own
/// spread** — printed beside the spread, never on its own. A channel with fewer
/// than `OvernightChange.minimumReferenceNights` behind it is named as waiting
/// rather than judged.
///
/// ⚠️ **There is no total, and there must not be.** Several channels leaning
/// the same way is the symptom radar's claim, and the radar earns it: weights
/// by specificity, collapses signals that are one measurement twice, and grades
/// the result against a stated false-alarm budget. A sum of unweighted deltas
/// would make the same claim with none of that behind it. The headline says so
/// out loud the moment more than one channel moves.
///
/// ## Why every channel comes from `VitalReader.dailySeries`
///
/// One derivation route, deliberately. The alternative was to read the heart
/// rate and variability from inside the sleep window — which
/// `OvernightCardiac` already does for the two sections that are *about* the
/// within-night shape — and take the rest from the nightly series. That would
/// give the card two opinions about what a night is, and they would disagree on
/// exactly the nights that matter. Everything here is a once-a-night figure a
/// source already computed, read through the one type that de-duplicates a day
/// and never blends two instruments.
struct OvernightChangeSection: View {
    @Environment(AppModel.self) private var model

    /// The channels, in the order they are read.
    ///
    /// **Order is the subject's, not the data's**: the two the reader will look
    /// for first, then breathing, then warmth, then the composite. The thermal
    /// pair are both listed and both drawn where both exist — unlike the
    /// symptom radar, which collapses them to one vote, because this section is
    /// a list of what moved rather than a joint statistic, and hiding one
    /// thermometer's disagreement with the other would be hiding the most
    /// interesting thing on the row.
    private static let order: [MetricType] = [
        .restingHeartRate, .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
        .respiratoryRate, .oxygenSaturation,
        .skinTemperatureDeviation, .skinTemperature, .basalBodyTemperature,
        .breathingDisturbanceIndex
    ]

    private var output: OvernightChange.Output? {
        model.memoized("overnightChange") { build() }
    }

    /// One pass per channel, memoised on the card — `dailySeries` picks a single
    /// best-covering instrument per metric and never blends, which is the
    /// property that stops a channel stepping every time the reader changes
    /// which device they sleep in.
    private func build() -> OvernightChange.Output? {
        // The two HRV quantities are not interchangeable — Apple reports SDNN
        // and Oura rMSSD, computed from the same beats by different arithmetic
        // and sitting at different levels — so only the denser one is read.
        // The rule and the reason are `OvernightCardiacReading`'s.
        let sdnn = model.samples.samples(of: .heartRateVariabilitySDNN).count
        let rmssd = model.samples.samples(of: .heartRateVariabilityRMSSD).count
        let dropped: MetricType = sdnn >= rmssd ? .heartRateVariabilityRMSSD
                                                : .heartRateVariabilitySDNN
        let series = Self.order.filter { $0 != dropped }.compactMap { metric -> OvernightChange.Series? in
            let daily = VitalReader.dailySeries(metric, from: model.samples)
            guard !daily.isEmpty else { return nil }
            return OvernightChange.Series(
                metric: metric,
                nights: daily.map { .init(day: $0.date, value: $0.value) })
        }
        return OvernightChange.build(series)
    }

    var body: some View {
        InsightSection(
            title: "What changed while you slept",
            icon: "arrow.up.arrow.down",
            trailing: trailing,
            caveat: .computed(.partial, caveatText),
            expansion: expansion
        ) {
            if let output, !output.channels.isEmpty {
                Text(OvernightChange.headline(output))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                nightLine(output)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sorted(output)) { channel in
                        row(channel, night: output.night)
                    }
                }
                scaleCaption
                if let waiting = output.waitingSentence {
                    Text(waiting)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(notScoredSentence)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                emptyState
            }
        }
    }

    /// Moved channels first, hardest first, then the quiet ones in reading
    /// order. The reader's eye lands on what moved without the quiet channels
    /// being hidden — "nothing else moved" is only believable when the nothing
    /// is shown.
    private func sorted(_ output: OvernightChange.Output) -> [OvernightChange.Channel] {
        let moved = output.moved
        let movedSet = Set(moved.map(\.metric))
        return moved + output.channels.filter { !movedSet.contains($0.metric) }
    }

    /// **The one figure**: how many channels moved, out of how many were
    /// judgeable. One quantity in the slot, never a different one as a fallback
    /// (`InsightSection`'s rule).
    private var trailing: String? {
        guard let output, !output.channels.isEmpty else { return nil }
        return "\(output.moved.count) of \(output.channels.count) moved"
    }

    private var expansion: SectionExpansion {
        guard let output, !output.channels.isEmpty else {
            return .collapsed(preview: "Not enough nights behind your overnight readings yet.")
        }
        return .open
    }

    /// Which night this is, spelled out. **Derived from the data rather than
    /// from any visible window**, so nothing here can vanish when a chart
    /// elsewhere on the card is panned (`add-chart` §9b).
    private func nightLine(_ output: OvernightChange.Output) -> some View {
        Text("Night of \(output.night.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    // MARK: - One channel

    @ViewBuilder private func row(_ channel: OvernightChange.Channel,
                                  night: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(channel.metric.displayName)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text(OvernightChange.formatted(channel.value, in: channel))
                    .font(.caption.weight(.semibold)).monospacedDigit()
            }
            deviationBar(channel)
            Text(OvernightChange.sentence(for: channel))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Only where it differs from the night's own date — sources
            // disagree about which day a night is filed under, and a row
            // silently reporting a different day would be attributing a reading
            // to a night it was not taken on.
            if !Calendar.current.isDate(channel.day, inSameDayAs: night) {
                Text("Filed under \(channel.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) by your source.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// A signed bar on a fixed ±3-spread axis, with the ordinary range drawn
    /// behind it.
    ///
    /// **Plain shapes, not Swift Charts.** There is no time axis and nothing to
    /// scrub, and a one-value bar built from `RuleMark`s is exactly the shape
    /// that resolves to `Chart3DContent` on this SDK (`add-chart` §2). The axis
    /// is the same for every row, which is the entire point — that is what
    /// makes a millisecond comparable with a breath.
    private func deviationBar(_ channel: OvernightChange.Channel) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let centre = width / 2
            let unit = centre / CGFloat(Self.axisSpreads)
            let extent = min(CGFloat(abs(channel.z)), CGFloat(Self.axisSpreads)) * unit
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6)
                // The ordinary band — one spread either side, the range about
                // two thirds of nights land in.
                Capsule()
                    .fill(.quaternary)
                    .frame(width: unit * 2, height: 6)
                    .offset(x: centre - unit)
                Rectangle()
                    .fill(barTint(channel))
                    .frame(width: max(extent, 1.5), height: 6)
                    .clipShape(Capsule())
                    .offset(x: channel.z >= 0 ? centre : centre - extent)
                Rectangle().fill(.secondary).frame(width: 1, height: 10)
                    .offset(x: centre - 0.5)
            }
            .frame(height: 10)
        }
        .frame(height: 10)
    }

    /// How wide the axis is, in spreads. Three: past that a night is off the
    /// end of any ordinary scatter and the exact multiple is in the sentence
    /// anyway, so a longer axis would squash every row that matters.
    private static let axisSpreads = 3.0

    /// ⚠️ **Colour carries exactly one claim: the channel moved the way illness
    /// pushes it.** Length carries how far.
    ///
    /// The first version used `Theme.insightTint(.sleep)` for a move with no
    /// concerning direction and `Theme.warn` for one with — and on the
    /// simulator those two are both warm oranges a few points apart, so a
    /// falling temperature and a falling blood oxygen looked identical
    /// (`add-chart`: read the pixel before choosing a colour). Greys and one
    /// amber cannot collide, and the amber then means something.
    private func barTint(_ channel: OvernightChange.Channel) -> Color {
        guard !channel.isOrdinary else { return .secondary.opacity(0.35) }
        // A channel the health watch has no opinion about never turns amber:
        // this section has no basis for calling one of its directions bad, and
        // colouring it anyway would be a verdict rendered as decoration.
        let concerning = channel.risingIsConcerning.map { $0 == (channel.delta > 0) } ?? false
        return concerning ? Theme.warn : .secondary
    }

    private var scaleCaption: some View {
        Text("Every bar is on the same scale: how far the channel moved in its own night-to-night spreads, out to three either side. The pale block in the middle is one spread either way — the range about two thirds of your nights land in. That is what makes a millisecond comparable with a breath. Amber means the move was in the direction illness pushes that signal; grey means it moved the other way, or that nothing published says which way is worse.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notScoredSentence: String {
        "Nothing here is added up, and that is deliberate. Several channels leaning the same "
        + "way at once is the symptom radar's question — it weights each signal by how "
        + "specific it is, counts one measurement reported several ways only once, and "
        + "states how often it expects to be wrong. A total taken here would make the same "
        + "claim with none of that behind it."
    }

    private var caveatText: String {
        "Each channel is the one figure a night your densest source reports for it, held "
        + "against your own previous nights — never against anybody else's. Your sources "
        + "disagree about which day a night belongs to, so a reading filed a day either side "
        + "still counts as last night's and the row says when it was. And a spread is only "
        + "as honest as the nights behind it, which is why the count is printed every time."
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(SectionPlaceholder.needsMore(
                subject: "What changed overnight",
                have: output?.nightsBehind ?? 0,
                need: OvernightChange.minimumReferenceNights,
                noun: "night of overnight readings behind the one being judged",
                plural: "nights of overnight readings behind the one being judged").detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
