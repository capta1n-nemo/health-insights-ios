import SwiftUI
import Charts
import InsightKit

/// **The heartbeat stream, read inside the sleep window and shared by the two
/// sections that need it.**
///
/// One build, one memo key, two sections — "Overnight HRV" (backlog S10) and
/// "When you settled" (B3-20) ask different questions of the same pass over the
/// same readings, and doing it twice would be two walks of a 73,000-reading
/// series on every redraw of one screen.
///
/// ## Which HRV, and why it is a decision rather than a constant
///
/// **Apple reports SDNN and Oura reports rMSSD, and they are not the same
/// quantity.** They are computed from the same beat intervals by different
/// arithmetic, they sit at different levels, and pooling them into one series
/// would draw a step every time the reader changed which device they slept in.
/// So this picks whichever the reader has more of, keeps it to that one
/// instrument — the same rule `MetricDetailView.personalReading` follows — and
/// the section names it on screen so the number is never anonymous.
struct OvernightCardiacReading {
    let output: OvernightCardiac.Output
    /// Which heart-rate-variability quantity the curves and the nightly series
    /// are made of.
    let hrvMetric: MetricType

    /// The nights the sleep sections already agree on, plus what the heartbeat
    /// did inside each.
    ///
    /// The windows come from `NightSleepDetail.allNights`, under **the same memo
    /// key `sleepTypicalNightCard` already uses** — so on a card that has drawn
    /// "A typical night" this costs nothing at all, and on one that hasn't it
    /// pays for both.
    @MainActor static func build(_ model: AppModel) -> OvernightCardiacReading {
        let nights = model.memoized("nightSleepAllNights") {
            NightSleepDetail.allNights(raw: model.otherSamples, samples: model.samples)
        }
        let windows = nights.compactMap { night in
            night.window.map {
                OvernightCardiac.NightWindow(night: night.night, window: $0)
            }
        }
        let sdnn = model.samples.samples(of: .heartRateVariabilitySDNN).count
        let rmssd = model.samples.samples(of: .heartRateVariabilityRMSSD).count
        let metric: MetricType = sdnn >= rmssd ? .heartRateVariabilitySDNN
                                               : .heartRateVariabilityRMSSD
        return OvernightCardiacReading(
            output: OvernightCardiac.build(windows: windows, samples: model.samples,
                                           hrvMetric: metric),
            hrvMetric: metric)
    }
}

/// **"Overnight HRV"** — backlog S10, whose whole case is one sentence:
/// *"Sleep is the only card grading a night that reads nothing from the heartbeat
/// stream recorded during it."*
///
/// That was exactly true. Sleep's inputs were duration, onset, efficiency, the
/// stage minutes, latency, oxygen, respiratory rate, the breathing index and
/// three temperatures — and no heart measurement at all, while the phone held
/// tens of thousands of readings taken during the very nights being graded.
///
/// ## What it now reads, and what it still does not score
///
/// It reads, and charts, the heart-rate variability recorded **inside the sleep
/// window** — not the day's figure, not a wearable's own nightly average, but
/// the readings that fell between the moment a source said sleep started and the
/// moment it said it ended.
///
/// It does **not** feed the sleep score, and that is a decision with two reasons
/// rather than an omission:
///
/// - **HRV is already scored by five other cards** (Readiness, Heart Health,
///   Biological Age, Energy, Vital Signs). Scoring it a sixth time would count
///   one measurement of one night six ways, which is the double-counting this
///   app has had to unpick before.
/// - **Nothing published grades a person's own overnight HRV.** It moves with
///   age, alcohol, illness, room temperature and the last meal; there is a
///   population distribution and no threshold a night can be held to.
///
/// Both are said on screen, because "we looked at this and decided it counts for
/// nothing" is a completely different statement from "we forgot to weight it" —
/// and from the outside they look identical.
struct OvernightHRVSection: View {
    @Environment(AppModel.self) private var model
    let timeframe: Timeframe

    private var reading: OvernightCardiacReading {
        model.memoized("overnightCardiac") { OvernightCardiacReading.build(model) }
    }

    private var nightly: [OvernightCardiac.NightlyPoint] { reading.output.hrvNightly }

    private var trend: ScoreTrend? { OvernightCardiac.trend(nightly) }

    private var latest: OvernightCardiac.Night? {
        reading.output.nights.last { $0.hrv != nil }
    }

    var body: some View {
        InsightSection(
            title: "Overnight HRV",
            icon: "waveform.path.ecg",
            trailing: latest?.hrv.map {
                String(format: "%.0f ms median", $0.median)
            },
            caveat: .computed(.partial, caveatText),
            expansion: expansion
        ) {
            if nightly.count >= 2 {
                Text(headlineSentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                OvernightNightlyChart(points: nightly,
                                      unit: "ms",
                                      window: timeframe.chartWindow(spanning: span))
                lastNightRow
                if let waiting = reading.output.hrvCoverage?.sentence {
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

    private var span: TimeInterval? {
        guard let first = nightly.first?.night, let last = nightly.last?.night,
              first < last else { return nil }
        return last.timeIntervalSince(first)
    }

    private var expansion: SectionExpansion {
        guard nightly.count < 2 else { return .open }
        return .collapsed(preview: "Nothing recorded between lights-out and waking yet.")
    }

    private var metricName: String {
        reading.hrvMetric == .heartRateVariabilityRMSSD ? "rMSSD" : "SDNN"
    }

    private var headlineSentence: String {
        guard let trend else {
            return "Your heart-rate variability, taken only from the readings that fell "
                + "between falling asleep and waking, night by night."
        }
        guard trend.isMeaningful else {
            return "Steady across these nights — the line through them moves less than "
                + "the nights move around it, so there is no direction to name."
        }
        return String(format: "Drifting %@ by about %.1f ms a week over these nights, "
                      + "against a night-to-night scatter of %.1f ms. A direction, not "
                      + "a promise.",
                      trend.slopePerWeek > 0 ? "up" : "down",
                      abs(trend.slopePerWeek), trend.residualSD)
    }

    /// Last night's window, spelled out — how many readings it rests on, and what
    /// the heart rate did over the same stretch. Derived from the history rather
    /// than from the chart's visible window, so panning the chart cannot make it
    /// disappear (`add-chart` §9b).
    @ViewBuilder private var lastNightRow: some View {
        if let night = latest, let hrv = night.hrv {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%@: %.0f ms in the middle, %.0f–%.0f across the "
                            + "night, from %d readings.",
                            night.night.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                            hrv.median, hrv.lowest, hrv.highest, hrv.count))
                    .font(.caption).monospacedDigit()
                if let heart = night.heartRate {
                    Text(String(format: "Heart rate over the same stretch: %.0f bpm at "
                                + "its lowest, %.0f in the middle.",
                                heart.lowest, heart.median))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    private var notScoredSentence: String {
        "Charted, never scored. Your variability already counts toward Readiness, Heart "
        + "Health, Biological Age, Energy and Vital Signs, and adding it to your sleep "
        + "number as well would count one night's reading twice over. Nothing published "
        + "grades a person's own overnight variability anyway — it moves with age, "
        + "alcohol, illness and how warm the room was."
    }

    private var caveatText: String {
        "\(metricName), the quantity your densest source reports — Apple's watch reports "
        + "SDNN and Oura reports rMSSD, and the two are not interchangeable, so only one "
        + "of them is drawn here. A night is whatever your sleep source called sleep, so "
        + "a source that misses the first hour misses the readings in it too."
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(SectionPlaceholder.needsMore(
                subject: "Your overnight variability",
                have: nightly.count,
                need: 2,
                noun: "night with both a recorded sleep window and a variability reading inside it",
                plural: "nights with both a recorded sleep window and variability readings inside them").detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One nightly figure per night, against the middle it is measured from.
///
/// The same band-and-average shape as `SleepOnsetChart` and the fortnight strip,
/// at the reader's request — a dashed line at the usual level and a band one
/// standard deviation either side, both **re-fitted over whatever is on screen**
/// so scrolling to last spring draws last spring's usual rather than this
/// month's imposed on it.
///
/// Wraps `ScrollableMetricChart`, so pan, zoom, scrub, the substance shading and
/// the jump-to-nearest-data chevrons all arrive without a line here
/// (`add-chart` §1, §9a, §9b).
struct OvernightNightlyChart: View {
    let points: [OvernightCardiac.NightlyPoint]
    let unit: String
    let window: TimeInterval

    @State private var selection: Date?
    @State private var visibleRange: ClosedRange<Date>?

    private var tint: Color { Theme.insightTint(.sleep) }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.night, let last = points.last?.night,
              first <= last else { return nil }
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    private var fitted: (mean: Double, sd: Double)? {
        let visible = (visibleRange.map { r in points.filter { r.contains($0.night) } } ?? points)
            .map(\.value)
        guard visible.count >= 2, let mean = Baseline.mean(visible),
              let sd = Baseline.standardDeviation(visible) else { return nil }
        return (mean, sd)
    }

    private func point(at date: Date) -> OvernightCardiac.NightlyPoint? {
        guard let nearest = points.min(by: {
            abs($0.night.timeIntervalSince(date)) < abs($1.night.timeIntervalSince(date))
        }), abs(nearest.night.timeIntervalSince(date)) <= window / 10 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            caption
        }
    }

    /// Above the chart, never a mark annotation — on this SDK a `RuleMark` chain
    /// can resolve to `Chart3DContent`, which has none (`add-chart` §2). The
    /// blank line keeps the height constant so a scrub cannot move the page.
    @ViewBuilder private var readout: some View {
        if let selection, let hit = point(at: selection) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(String(format: "%.0f %@", hit.value, unit))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.night.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(.secondary)
                if let fitted, abs(hit.value - fitted.mean) >= 1 {
                    let delta = hit.value - fitted.mean
                    Text(String(format: "· %.0f %@ %@ than usual", abs(delta), unit,
                                delta > 0 ? "higher" : "lower"))
                        .foregroundStyle(.tertiary)
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
            height: 160,
            emptyMessage: "Nothing was recorded in the period on screen. Swipe sideways, tap the arrows on the edges to jump to your nearest nights, or pick a longer timeframe.",
            isEmpty: { range in !points.contains { range.contains($0.night) } },
            yDomain: { range in yDomain(range) },
            onVisibleRangeChange: { visibleRange = $0 }
        ) { range in
            marks(points.filter { range.contains($0.night) }, range: range)
        }
    }

    private func yDomain(_ range: ClosedRange<Date>) -> ClosedRange<Double>? {
        let visible = points.filter { range.contains($0.night) }.map(\.value)
        guard let low = visible.min(), let high = visible.max() else { return nil }
        let bandLow = fitted.map { $0.mean - $0.sd } ?? low
        let bandHigh = fitted.map { $0.mean + $0.sd } ?? high
        let lower = Swift.max(0, Swift.min(low, bandLow) * 0.9)
        let upper = Swift.max(high, bandHigh) * 1.1
        return lower < upper ? lower...upper : nil
    }

    @ChartContentBuilder
    private func marks(_ visible: [OvernightCardiac.NightlyPoint],
                       range: ClosedRange<Date>) -> some ChartContent {
        bandMark(range: range)
        averageMark
        ForEach(visible) { night in
            PointMark(x: .value("Night", night.night),
                      y: .value("Value", night.value))
                .foregroundStyle(tint.opacity(0.8))
                .symbolSize(30)
        }
    }

    @ChartContentBuilder
    private func bandMark(range: ClosedRange<Date>) -> some ChartContent {
        ForEach(fitted.map { [$0] } ?? [], id: \.mean) { fit in
            RectangleMark(xStart: .value("From", range.lowerBound),
                          xEnd: .value("To", range.upperBound),
                          yStart: .value("Low", Swift.max(0, fit.mean - fit.sd)),
                          yEnd: .value("High", fit.mean + fit.sd))
                .foregroundStyle(tint.opacity(0.10))
        }
    }

    /// Dashed, because a fitted average is not a night anybody had
    /// (`add-chart` §3).
    @ChartContentBuilder
    private var averageMark: some ChartContent {
        ForEach(fitted.map { [$0.mean] } ?? [], id: \.self) { mean in
            RuleMark(y: .value("Usual", mean))
                .foregroundStyle(tint.opacity(0.55))
                .lineStyle(Theme.projectedStroke)
        }
    }

    private var caption: some View {
        Text("Each point is one night. The dashed line is your usual level and the band is how far either side of it you typically land — both re-fit to whatever window you scroll to, so they describe the stretch you are looking at rather than this month.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
