import SwiftUI
import Charts
import InsightKit

/// **Social battery's own pictures** — backlog B9-1.
///
/// The reader asked for *"several bespoke charts, to show very good insights
/// into people's 'social batteries'"*, and the card carries four, in the order
/// the three questions were asked in:
///
/// | Section | Question | Shape |
/// | --- | --- | --- |
/// | Where your time with people went | how much contact, and of which kind | a pannable stacked daily chart |
/// | What company does to you | did the body notice | a signed axis with a **95% interval on it** |
/// | Restores or drains you | which kind of contact does which | the same axis, one row per kind |
/// | Today | what is left | elapsed and ahead against a typical day, **and no percentage** |
///
/// ⚠️ **The interval is the point of the middle two, and it is why they are not
/// bar charts of a single number.** This card's most novel claim — *"company
/// restores this particular reader"* — is exactly the kind of claim that is
/// wrong at low n, and the only honest way to draw it is with the uncertainty
/// beside the estimate. A bar crossing zero is what *"we cannot tell yet"* looks
/// like, and a reader can see that in a picture faster than in a sentence.
///
/// ⚠️ **Its own file** — `InsightDetailView` is ~3,700 lines, and a section
/// written inline there is a merge conflict for the next agent. Same convention
/// as `BodyOverTimeSection`, `SleepApnoeaSection` and the rest.
struct SocialBatterySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let timeframe: Timeframe

    private var readiness: SocialBatteryModel.Readiness {
        model.memoized("socialBattery") {
            SocialBatteryModel.analyse(events: model.calendarEvents,
                                       judgements: model.calendarJudgements,
                                       samples: model.samples)
        }
    }

    var body: some View {
        switch readiness {
        case .ready(let out):
            contactSection(out)
            responseSection(out)
            restorationSection(out)
            todaySection(out)
        case .waiting(let gate):
            // ⚠️ Not an `EmptyView`, and not a single merged section either: a
            // card whose pictures disappear while it is counting is how two
            // sections shipped invisible on 2026-08-03. Each of the four says
            // what it is still waiting for.
            placeholder(title: "Where your time with people went",
                        message: gate.sentence ?? "Still gathering your calendar.")
            placeholder(title: "What company does to you",
                        message: "Nothing to compare yet. This needs enough days on both sides of your own median before it can say what company does to your resting heart rate, variability and sleep.")
            placeholder(title: "Does company restore you or drain you?",
                        message: "Not yet. This is the question this card exists for, and it is also the one most easily got wrong at low n — so it stays silent until the range around its answer stops containing zero.")
            placeholder(title: "Today", message: SocialBatteryModel.capacityRefusal)
        case .noCalendar:
            placeholder(title: "Where your time with people went",
                        message: "Connect your calendar in Settings ▸ Integrations and this will start reading how much of your time goes on other people. Nothing about your calendar leaves the phone, and the app never stores who was invited — only how many.")
        }
    }

    private func placeholder(title: LocalizedStringResource, message: String) -> some View {
        InsightSection(title: title, trailing: nil, caveat: .none,
                       expansion: .collapsed(preview: String(message.prefix(90)))) {
            Text(message)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 1. Where your time with people went

    private func contactSection(_ out: SocialBatteryModel.Output) -> some View {
        InsightSection(
            title: "Where your time with people went",
            icon: "person.2",
            trailing: String(format: "%.1f h on a typical day", out.typicalDayHours),
            caveat: .computed(.estimated,
                              "An hour is not an hour here: a formal meeting in a room counts for more than the same hour on a video call, and a block of time counts only when your calendar says somebody else was invited to it. Those weightings are the app's stated assumption, not a measurement."),
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: "Every day of the last %d, split by whether the company was yours to choose. The dashed line is your own median — the level the busy-versus-quiet split below is made at, inside weekdays and weekends separately.",
                            SocialBatteryModel.windowDays))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SocialContactChart(days: out.days,
                                   median: out.typicalDayHours,
                                   window: timeframe.chartWindow(spanning: span(out)))
                strataRows(out)
            }
        }
    }

    private func span(_ out: SocialBatteryModel.Output) -> TimeInterval? {
        guard let first = out.days.first?.day, let last = out.days.last?.day,
              first < last else { return nil }
        return last.timeIntervalSince(first)
    }

    /// How the split was actually made, block by block.
    ///
    /// ⚠️ **This is the card's legitimacy, drawn.** A pooled busy-versus-quiet
    /// split would put every weekend on the quiet side, so the finding would be
    /// about Saturday. Showing the two blocks separately is what lets a reader
    /// check that.
    @ViewBuilder private func strataRows(_ out: SocialBatteryModel.Output) -> some View {
        Divider()
        Text("How the comparison was blocked")
            .font(.caption.weight(.semibold))
        ForEach(SocialBatteryModel.Stratum.allCases) { stratum in
            let days = out.days.filter { $0.stratum == stratum }
            let used = out.strata.contains(stratum)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stratum.title)
                    .font(.caption)
                    .frame(width: 74, alignment: .leading)
                Text(used
                     ? "\(days.count) days, split at their own median"
                     : "\(days.count) days — left out entirely, too few or too alike to split. Folding them into the other block would put the confound back.")
                    .font(.caption2)
                    .foregroundStyle(used ? .secondary : .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 2. What company does to you

    private func responseSection(_ out: SocialBatteryModel.Output) -> some View {
        InsightSection(
            title: "What company does to you",
            icon: "waveform.path.ecg",
            trailing: String(format: "%.2f SD", out.overall.pooled),
            // The count is derived, never written out: this card runs on
            // whichever of its signals have coverage, and a sentence naming a
            // fixed number is the D19 defect ("All four" on a card running on
            // three).
            caveat: .computed(.fitted,
                              "Each signal is read on the night after the day, because company cannot change the sleep before it. The range shown is a 95% interval worked out as if the \(out.overall.channels.count) signals moved independently — they do not, so the true range is wider than the one drawn."),
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How far each signal moved between your busier days for company and your quieter ones, in standard deviations of your own spread. Right of the line is the unwelcome direction.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let scale = axisScale(out)
                ForEach(out.overall.channels) { channel in
                    SignedIntervalRow(
                        label: channel.metric.displayName,
                        estimate: channel.towardWorse,
                        halfWidth: nil,
                        extent: scale,
                        tint: Theme.metricColor(channel.metric),
                        detail: String(format: "%@ against %@",
                                       MetricValueFormatter.string(channel.onHeavyDays, channel.metric),
                                       MetricValueFormatter.string(channel.onLightDays, channel.metric)))
                }
                Divider()
                SignedIntervalRow(
                    label: "All of them, pooled",
                    estimate: out.overall.pooled,
                    halfWidth: out.overall.halfWidth,
                    extent: scale,
                    tint: Theme.insightTint(.socialBattery),
                    detail: out.overall.isDistinguishableFromZero
                        ? "the range stays clear of zero"
                        : "the range still contains zero")
                Text(SocialBatteryModel.restorationPhrase(out) + ".")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: "%d days on the busier side against %d on the quieter one.",
                            out.overall.highDays, out.overall.lowDays))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// One extent for every row on the card, so two rows drawn the same length
    /// mean the same thing. Never per-row, which would draw a 0.1 SD finding and
    /// a 2 SD one identically.
    private func axisScale(_ out: SocialBatteryModel.Output) -> Double {
        var extent = 1.0
        for channel in out.overall.channels { extent = max(extent, abs(channel.towardWorse)) }
        extent = max(extent, abs(out.overall.pooled) + out.overall.halfWidth)
        for finding in out.findings {
            guard let response = finding.response else { continue }
            extent = max(extent, abs(response.pooled) + response.halfWidth)
        }
        return extent * 1.1
    }

    // MARK: - 3. Does company restore you or drain you?

    private func restorationSection(_ out: SocialBatteryModel.Output) -> some View {
        InsightSection(
            title: "Does company restore you or drain you?",
            icon: "person.2.badge.gearshape",
            trailing: verdictWord(out),
            caveat: .computed(.fitted,
                              "Chosen and owed are proxies: nothing in a calendar says whether you wanted to be somewhere, so a personal event, or a casual one, stands in for contact you chose. Correct any event on the list below and this recomputes."),
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("The same nights, split a different way. If company drains you, both bars sit right of the line; if it restores you, they sit left. A bar that crosses the line is the honest answer that nothing can be said yet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let scale = axisScale(out)
                ForEach(out.findings) { finding in
                    if let response = finding.response {
                        SignedIntervalRow(
                            label: finding.kind.title,
                            estimate: response.pooled,
                            halfWidth: response.halfWidth,
                            extent: scale,
                            tint: Theme.paletteColour(slot: finding.kind == .chosen ? 3 : 5),
                            detail: verdictLabel(finding.verdict))
                    } else {
                        // ⚠️ Never dropped. A row missing says "we did not look",
                        // which is a completely different statement from "we
                        // looked and there is not enough of it yet".
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(finding.kind.title).font(.caption)
                                .frame(width: 120, alignment: .leading)
                            Text("not enough days yet")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                    }
                    Text(SocialBatteryModel.kindSentence(finding))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func verdictWord(_ out: SocialBatteryModel.Output) -> String {
        guard out.overall.isDistinguishableFromZero else { return "can't tell yet" }
        return out.overall.pooled < 0 ? "restores you" : "drains you"
    }

    private func verdictLabel(_ verdict: SocialBatteryModel.ContactVerdict) -> String {
        switch verdict {
        case .restores: return "restores you"
        case .drains: return "drains you"
        case .tooCloseToTell: return "can't tell yet"
        case .notEnoughDays: return "not enough days yet"
        }
    }

    // MARK: - 4. Today

    /// ⚠️ **No percentage, and the section says why in its own body rather than
    /// in a footnote.** The reader asked for capacity remaining; Energy's
    /// reservoir constants were chosen in this repo rather than measured, and a
    /// battery figure built on them would be the most reassuring thing on this
    /// card and the least true.
    private func todaySection(_ out: SocialBatteryModel.Output) -> some View {
        InsightSection(
            title: "Today",
            icon: "clock",
            trailing: out.today.map { String(format: "%.1f h", $0.totalHours) },
            caveat: .computed(.partial,
                              "Read straight off today's diary. An event that has not started yet is time you have not spent — nothing here predicts whether you will."),
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let today = out.today, today.totalHours > 0 {
                    todayBar(today, typical: out.typicalDayHours)
                }
                Text(SocialBatteryModel.todaySentence(out))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SocialBatteryModel.todayPrecedentSentence(out))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text(SocialBatteryModel.capacityRefusal)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Today's contact against a typical day of theirs.
    ///
    /// ⚠️ **No band ramp on this fill** (`add-chart` §7a). The length encodes
    /// *hours*, not a score, and a green-to-red gradient would grade a diary
    /// this card has explicitly declined to grade — so it takes the card's own
    /// hue at full strength.
    ///
    /// ⚠️ **The part still ahead is hatched rather than washed.** It is the same
    /// quantity in a state the app has not observed — nobody has spent it yet —
    /// and the app's word for that is *not measured*. A translucent version of
    /// the same hue would mix into a third colour that means nothing (§8) and
    /// would read as *less* company rather than as company that has not happened.
    private func todayBar(_ today: SocialBatteryModel.TodayLoad,
                          typical: Double) -> some View {
        let tint = Theme.insightTint(.socialBattery)
        let ahead = Theme.hatch(light: 0xB0455A, dark: 0xE8899A, colorScheme)
        let extent = max(typical, today.totalHours) * 1.15
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let scale = extent > 0 ? width / extent : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(tint)
                        .frame(width: max(0, today.elapsedHours * scale))
                    Capsule().fill(ahead)
                        .frame(width: max(0, today.aheadHours * scale))
                        .offset(x: today.elapsedHours * scale)
                    // The reader's own typical day, as a level nobody measured
                    // today — so it is drawn as a reference, not as data.
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 1)
                        .offset(x: min(width, typical * scale))
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack(spacing: 12) {
                swatch(tint, "behind you")
                swatch(ahead, "still ahead")
                Text(String(format: "| typical day %.1f h", typical))
                    .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
    }

    private func swatch(_ style: some ShapeStyle, _ label: String) -> some View {
        HStack(spacing: 4) {
            // Plain and opaque in the key — a key answers "which quantity is
            // this", and what it sits on top of is a fact about placement
            // (`add-chart` §8).
            RoundedRectangle(cornerRadius: 2).fill(style).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// One signed reading on a shared axis, **with its uncertainty where it has
/// one**.
///
/// Deliberately not a `Chart`: there is nothing to pan, nothing to scrub and no
/// date axis for the substance shading to land on, so a `Chart` here would buy
/// the `Chart3DContent` overload hazard in exchange for nothing. Same reasoning
/// and the same shape as `SoundExposureSection`'s bars.
private struct SignedIntervalRow: View {
    let label: String
    /// Positive is the unwelcome direction, on every row.
    let estimate: Double
    /// Half the 95% interval, or `nil` for a row that carries no interval.
    let halfWidth: Double?
    /// The value at each end of the axis. Shared across every row on the card.
    let extent: Double
    let tint: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.caption)
                Spacer(minLength: 8)
                Text(String(format: "%+.2f SD", estimate))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let mid = width / 2
                let scale = extent > 0 ? mid / extent : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.10))
                    // The interval, behind the estimate.
                    if let halfWidth {
                        let low = (estimate - halfWidth) * scale
                        let high = (estimate + halfWidth) * scale
                        Capsule()
                            .fill(tint.opacity(0.28))
                            .frame(width: max(2, high - low), height: 10)
                            .offset(x: mid + low)
                    }
                    // The estimate.
                    Circle()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                        .offset(x: mid + estimate * scale - 4.5)
                    // Zero — the thing a bar crossing it is saying something
                    // about, so it is drawn last and over everything.
                    Rectangle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 1)
                        .offset(x: mid)
                }
            }
            .frame(height: 16)
            HStack(spacing: 6) {
                Text("← better").font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Text("worse →").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// **Contact per day, stacked by whether it was yours to choose.**
///
/// Wraps `ScrollableMetricChart`, so pan, zoom, scrub, the substance shading and
/// the jump-to-nearest-data chevrons all arrive without a line here
/// (`add-chart` §1, §9a, §9b).
///
/// ⚠️ **Both series carry a value at every x**, zero where the day held none
/// (`add-chart` §7). `SocialBatteryModel.contactDays` returns a contiguous run
/// of days with explicit zeros for exactly this reason, so a stacked band cannot
/// open a wedge of background where one kind of contact happens to be absent.
private struct SocialContactChart: View {
    let days: [SocialBatteryModel.DayContact]
    /// The reader's own typical day — the level the split is made at.
    let median: Double
    let window: TimeInterval

    @State private var selection: Date?
    @State private var visibleRange: ClosedRange<Date>?

    /// Two fixed slots from the validated palette. Only these two series are
    /// ever on this chart, so a resolver would have nothing to resolve — but
    /// they are drawn from the same eight as every metric chart, so the card
    /// does not clash with the ones above it.
    private var chosenTint: Color { Theme.paletteColour(slot: 3) }
    private var obligatedTint: Color { Theme.paletteColour(slot: 5) }

    private var span: ClosedRange<Date>? {
        guard let first = days.first?.day, let last = days.last?.day,
              first <= last else { return nil }
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    private func day(at date: Date) -> SocialBatteryModel.DayContact? {
        guard let nearest = days.min(by: {
            abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
        }), abs(nearest.day.timeIntervalSince(date)) <= window / 10 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            legend
        }
    }

    /// Above the chart, never a mark annotation — on this SDK a `RuleMark` chain
    /// can resolve to `Chart3DContent`, which has none (`add-chart` §2). The
    /// blank line keeps the height constant so a scrub cannot move the page.
    @ViewBuilder private var readout: some View {
        if let selection, let hit = day(at: selection) {
            HStack(spacing: 8) {
                Text(hit.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f h", hit.hours))
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                if hit.sizedMeetings > 0 {
                    Text("· \(hit.people)+ people").foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: $selection,
            height: 170,
            emptyMessage: "Nothing was recorded in the period on screen. Swipe sideways, tap the arrows on the edges to jump to your nearest days, or pick a longer timeframe.",
            isEmpty: { range in !days.contains { range.contains($0.day) } },
            yDomain: { range in yDomain(range) },
            onVisibleRangeChange: { visibleRange = $0 }
        ) { range in
            marks(days.filter { range.contains($0.day) })
        }
    }

    /// The axis fits what is on screen and always starts at zero — a stacked
    /// share chart that does not is drawing a difference as a ratio.
    private func yDomain(_ range: ClosedRange<Date>) -> ClosedRange<Double>? {
        let visible = days.filter { range.contains($0.day) }.map(\.hours)
        let top = max(visible.max() ?? 0, median) * 1.15
        return top > 0 ? 0...top : nil
    }

    @ChartContentBuilder
    private func marks(_ visible: [SocialBatteryModel.DayContact]) -> some ChartContent {
        // ⚠️ `ForEach` rather than a bare `if`, and an explicit return type on
        // this builder: without both, a `RuleMark`/`BarMark` chain can resolve
        // to `Chart3DContent` on this SDK and silently drop `.foregroundStyle`
        // and `.lineStyle` (`add-chart` §2).
        ForEach(visible) { day in
            BarMark(x: .value("Day", day.day),
                    y: .value("Chosen", day.chosenHours))
                .foregroundStyle(chosenTint)
        }
        ForEach(visible) { day in
            BarMark(x: .value("Day", day.day),
                    y: .value("Owed", day.obligatedHours))
                .foregroundStyle(obligatedTint)
        }
        medianMark
    }

    /// A level derived from the reader's own days rather than measured on any of
    /// them, so it is dashed (`add-chart` §3).
    @ChartContentBuilder
    private var medianMark: some ChartContent {
        ForEach(median > 0 ? [median] : [], id: \.self) { level in
            RuleMark(y: .value("Typical day", level))
                .lineStyle(Theme.referenceStroke)
                .foregroundStyle(Color.secondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            key(chosenTint, SocialBatteryModel.ContactKind.chosen.title)
            key(obligatedTint, SocialBatteryModel.ContactKind.obligated.title)
            Text("- - typical day").font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private func key(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(colour).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
