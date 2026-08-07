import SwiftUI
import InsightKit

/// **"Jetlag"** on the Travel card — how much, how it landed, and when a real
/// recovery figure becomes possible.
///
/// The reader, 2026-08-07: *"One thing I want on the travel card: A way to
/// calculate jetlag, and how that impacts you, and how long it takes to recover
/// from it."* (Backlog `B21`.)
///
/// ## The three questions, answered at three different strengths — and labelled
///
/// **How much** is arithmetic on a signed offset and is solid: two zones east is
/// two zones east. **How long** is a published population rate, and the section
/// says the words "published" and "not a measurement of you" where it prints
/// it. **How it landed** is the reader's own body, and with a couple of trips on
/// the record it is a *record of what happened*, never a finding.
///
/// That third label is the one worth defending. A card that turns a single
/// flight into a finding is precisely what this repo refused the substance card
/// for, and `TravelDrainModel.minimumTrips = 2` exists for the same reason. So
/// the per-channel rows carry no score, no colour-coded verdict and no arrow —
/// they are numbers with their denominator printed beside them.
///
/// ## Why there is no recovery curve here
///
/// Because it cannot be drawn honestly yet, and the section says how many trips
/// it would take instead of drawing one anyway. `JetlagModel.tripsNeeded`
/// derives that from a power calculation with its effect size stated — eight
/// trips for a large effect, thirty-two for a realistic one — rather than from a
/// number somebody picked. **A curve through two trips is a drawing.**
struct JetlagSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let readiness = model.memoized("jetlag") {
            JetlagModel.analyse(events: model.calendarEvents,
                                spans: SleepTravel.spans(raw: model.otherSamples),
                                samples: model.samples)
        }
        InsightSection(
            title: "Jetlag",
            trailing: trailing(readiness),
            caveat: .computed(.approximate, Self.caveatText),
            expansion: expansion(readiness)
        ) {
            switch readiness {
            case .ready(let out):
                dose(out)
                Divider()
                responses(out)
                Divider()
                recovery(out)
            case .doseOnly(let out):
                dose(out)
                Divider()
                Text("One time-zone change on the record. The size of it above is "
                     + "arithmetic and is true of one trip; what it did to you is "
                     + "a comparison, and a comparison needs something to compare "
                     + "against. That arrives with your next journey.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                recovery(out)
            case .waiting(let gate):
                CoverageGateNotice(gate: gate)
            case .noEvidence:
                noEvidenceBody
            }
        }
    }

    private func trailing(_ readiness: JetlagModel.Readiness) -> String? {
        let latest: JetlagModel.Crossing?
        switch readiness {
        case .ready(let out), .doseOnly(let out): latest = out.latest
        case .waiting, .noEvidence: latest = nil
        }
        guard let latest else { return nil }
        return String(format: "%.0f h %@", abs(latest.shiftHours),
                      latest.isEastward ? "east" : "west")
    }

    private func expansion(_ readiness: JetlagModel.Readiness) -> SectionExpansion {
        switch readiness {
        case .ready, .doseOnly: return .open
        case .waiting(let gate):
            return .collapsed(preview: gate.sentence ?? "Waiting on more days")
        case .noEvidence:
            return .collapsed(preview: "Nothing on record shows you changed time zone")
        }
    }

    // MARK: - How much

    @ViewBuilder private func dose(_ out: JetlagModel.Output) -> some View {
        if let latest = out.latest {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f h %@", abs(latest.shiftHours),
                                latest.isEastward ? "east" : "west"))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(latest.day, format: .dateTime.day().month(.abbreviated))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                if let from = latest.from, let to = latest.to {
                    Text("\(place(from)) → \(place(to))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(Self.adjustmentHeadline(latest))
                    .font(.subheadline.weight(.semibold))
                Text(expectedDaysSentence(latest))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // ⚠️ Evidence, always stated. A measured crossing and an
                // inferred one are not the same claim and must not look alike.
                Text(evidenceSentence(latest))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(JetlagModel.directionRationale)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                if out.crossings.count > 1 {
                    Text("\(out.crossings.count) time-zone changes found in your record.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Half-days are kept: two zones west is two days and two zones east is
    /// three, but one zone east is a day and a half and rounding it to "1 day"
    /// would erase the very asymmetry this section is about.
    private static func daysText(_ days: Double) -> String {
        let halves = (days * 2).rounded() / 2
        if halves <= 1 { return "about a day" }
        let text = halves == halves.rounded()
            ? String(format: "%.0f", halves) : String(format: "%.1f", halves)
        return "about \(text) days"
    }

    private static func adjustmentHeadline(_ crossing: JetlagModel.Crossing) -> String {
        let text = daysText(crossing.adjustmentDays)
        return text.prefix(1).uppercased() + text.dropFirst() + " to adjust, on published rates."
    }

    /// The days figure spelled out, kept separate from the headline so the
    /// headline never has to carry a caveat inside itself.
    private func expectedDaysSentence(_ crossing: JetlagModel.Crossing) -> String {
        let zones = String(format: "%.0f", abs(crossing.shiftHours))
        return "Published rates put \(zones) "
            + "zones \(crossing.isEastward ? "eastward" : "westward") at "
            + "\(Self.daysText(crossing.adjustmentDays)) — a population average "
            + "over many travellers, not a measurement of you."
    }

    private func evidenceSentence(_ crossing: JetlagModel.Crossing) -> String {
        switch crossing.evidence {
        case .measured:
            return crossing.possiblyDaylightSaving
                ? "Measured: the two ends of that night carried different UTC "
                    + "offsets. A one-hour move can also be a daylight-saving "
                    + "change rather than a journey, and the offset alone cannot "
                    + "tell them apart."
                : "Measured: the two ends of that night carried different UTC "
                    + "offsets, so the clock genuinely moved. No inference "
                    + "involved."
        case .calendar:
            return "Inferred from the time zone on your calendar events. Setting "
                + "one event in another zone by hand looks identical, so this is "
                + "weaker than a recorded offset."
        }
    }

    /// `Asia/Manila` → "Manila".
    private func place(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - How it landed

    @ViewBuilder private func responses(_ out: JetlagModel.Output) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What your body did afterwards")
                .font(.subheadline.weight(.semibold))
            Text("Each signal's average over the days inside a change's expected "
                 + "adjustment window, against every other day. A record of what "
                 + "happened, not a finding — \(out.crossings.count) trips "
                 + "is far too few to attribute it, so nothing here is scored.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(out.responses) { response in
                HStack(alignment: .firstTextBaseline) {
                    Text(response.metric.displayName)
                        .font(.caption)
                    Spacer()
                    Text(MetricValueFormatter.string(response.afterCrossing, response.metric))
                        .font(.caption).monospacedDigit()
                    Text("vs")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(MetricValueFormatter.string(response.ordinary, response.metric))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                // The denominator, printed. A delta over three days is not the
                // same claim as one over thirty and must not look like it.
                Text("over \(response.daysCounted) "
                     + (response.daysCounted == 1 ? "day" : "days") + " inside a window")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - How long to recover

    @ViewBuilder private func recovery(_ out: JetlagModel.Output) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How long you take to recover")
                .font(.subheadline.weight(.semibold))
            Text("Not yet, and here is the number rather than a promise. "
                 + "Recovery is the day your signals come back to normal, which "
                 + "means one estimate per day after a trip — and each trip "
                 + "contributes exactly one observation to each of those days. "
                 + "So the number of trips is the sample size.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("You have \(out.crossings.count). It would take about "
                 + "\(out.tripsForLargeEffect) for a large effect, and roughly "
                 + "\(out.tripsForModerateEffect) for the more realistic size "
                 + "this app actually sees across its signals.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Until then the estimate above is the textbook's, and it says so.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Nothing knows you moved

    @ViewBuilder private var noEvidenceBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing on record shows a time-zone change.")
                .font(.subheadline).foregroundStyle(.secondary)
            // Structural, not a collection size: there are exactly two ways a
            // zone change can be established here (`Crossing.Evidence`), and the
            // sentence names both. A third changes the enum and this line
            // together, which is a compile-time visit rather than a silent drift.
            // count-in-copy: exempt — structural; mirrors Crossing.Evidence
            Text("Two things can know you moved: a calendar event stamped with "
                 + "another zone, or a night whose two ends carried different UTC "
                 + "offsets — which today means Oura. Neither has one. That is a "
                 + "gap in what was recorded, not a claim that you stayed home.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `.approximate`, because the headline figure is a published rate rather
    /// than a lookup into this reader's data — which is the definition of that
    /// kind, and the honest label for it.
    private static let caveatText =
        "How long a change takes to adjust to is a published population figure — "
        + "about a day per time zone westward and one and a half eastward — not "
        + "something measured on you. The direction of that asymmetry follows "
        + "from the body clock running slightly longer than 24 hours; the size is "
        + "from the literature. Sources: "
        + "Czeisler et al., Science 1999; Waterhouse et al., Lancet 2007; "
        + "Eastman & Burgess, Sleep Medicine Clinics 2009."
}
