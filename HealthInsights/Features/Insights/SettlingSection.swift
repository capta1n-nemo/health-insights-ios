import SwiftUI
import Charts
import InsightKit

/// **"When you settled"** — backlog B3-20, and the one thing the competitive
/// scan found nobody drawing.
///
/// Every wearable reports a nightly *summary*: an average overnight heart rate,
/// an average HRV. None of them draws the **shape inside the night**. A night
/// that reached its floor forty minutes after lights-out and a night that took
/// three hours produce the same average and are not the same night — the second
/// is the one where the wine, the late meal or the argument is still being
/// worked through — and only the shape tells them apart.
///
/// So this section draws last night's curve, binned from the moment sleep
/// started, against the reader's own usual curve over their recent nights.
///
/// ## The three decisions worth knowing about
///
/// **The x axis is hours since sleep started, not clock time.** Two nights that
/// began at 22:40 and 00:30 are the same shape an hour and fifty minutes apart,
/// and a clock axis would smear the band across that offset until it described
/// nothing. It also means this chart has no date axis, which is both its
/// substance-shading exemption and the reason it cannot strand a reader in an
/// empty window (`add-chart` §9a and §9b).
///
/// **The band excludes the night being drawn.** `OvernightCardiac.Output
/// .typicalHeartRate(excluding:)` fits over the nights *before* it, so last night
/// is held against something other than itself. On a short history, including it
/// would pull the band far enough to hide exactly the unusual night worth
/// noticing.
///
/// **"Settled" is defined, and the definition is on screen.** It is the first
/// bin at or below a tenth of the way back up from the night's floor to where it
/// opened — not the minimum itself, which is one bin and wanders with a single
/// noisy reading. A night whose rate never came down has no settling time at
/// all, and says so rather than reporting "settled immediately".
///
/// Nothing here is scored, for the reasons `OvernightHRVSection` sets out.
///
// substance-shading: exempt — the x axis is hours since you fell asleep, not a
// date, so a window in which something was logged has nowhere to land.
struct SettlingSection: View {
    @Environment(AppModel.self) private var model

    /// Which quantity the curve draws. A view control, not an input — nothing
    /// here is given to the app.
    private enum Quantity: String, CaseIterable, Identifiable {
        case heartRate, hrv
        var id: String { rawValue }
        var label: String {
            switch self {
            case .heartRate: return "Heart rate"
            case .hrv: return "Variability"
            }
        }
        var unit: String {
            switch self {
            case .heartRate: return "bpm"
            case .hrv: return "ms"
            }
        }
    }

    @State private var quantity: Quantity = .heartRate

    private var reading: OvernightCardiacReading {
        model.memoized("overnightCardiac") { OvernightCardiacReading.build(model) }
    }

    /// The most recent night with a heartbeat curve in it — not simply the most
    /// recent night, which may be one the ring spent on charge.
    private var night: OvernightCardiac.Night? {
        reading.output.nights.last { !$0.heartRateCurve.isEmpty || !$0.hrvCurve.isEmpty }
    }

    private var curve: [OvernightCardiac.CurvePoint] {
        guard let night else { return [] }
        return quantity == .heartRate ? night.heartRateCurve : night.hrvCurve
    }

    private var band: [OvernightCardiac.Band] {
        guard let night else { return [] }
        return quantity == .heartRate
            ? reading.output.typicalHeartRate(excluding: night.night)
            : reading.output.typicalHRV(excluding: night.night)
    }

    private var tint: Color { Theme.insightTint(.sleep) }

    var body: some View {
        InsightSection(
            title: "When you settled",
            icon: "moon.zzz",
            trailing: settledLabel,
            caveat: .computed(.partial, caveatText),
            expansion: expansion
        ) {
            if curve.count >= 3 {
                Text(headline)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                picker
                chart
                legend
                if let waiting = reading.output.typicalCoverage(before: night?.night ?? Date())?
                    .sentence {
                    Text(waiting)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Settled means the first point at or below a tenth of the way back up from the night's floor to where it started. A night that never came down has no settling point, and this says so rather than calling it instant.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                emptyState
            }
        }
    }

    private var expansion: SectionExpansion {
        guard curve.count < 3 else { return .open }
        return .collapsed(preview: "No heartbeat recorded through a night yet.")
    }

    private var picker: some View {
        Picker("What to draw", selection: $quantity) {
            ForEach(Quantity.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Which overnight signal to draw")
    }

    // MARK: - What it says in words

    private var settledLabel: String? {
        guard let hours = night?.settledAfterHours else { return nil }
        return String(format: "settled after %@", Self.duration(hours))
    }

    private var headline: String {
        guard let night else { return "" }
        let dated = night.night.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        guard let settled = night.settledAfterHours else {
            return "\(dated): your heart rate did not come down over this night, so there "
                + "is no settling point to mark. The curve is still drawn — a night that "
                + "stays level is a finding, not a gap."
        }
        guard let usual = reading.output.typicalSettlingHours(excluding: night.night) else {
            return "\(dated): you reached your night's floor about \(Self.duration(settled)) "
                + "after falling asleep. There aren't enough earlier nights yet to say "
                + "whether that is quick for you."
        }
        let delta = settled - usual
        guard abs(delta) >= 0.25 else {
            return "\(dated): you reached your night's floor about \(Self.duration(settled)) "
                + "after falling asleep — about your usual \(Self.duration(usual))."
        }
        return "\(dated): you reached your night's floor about \(Self.duration(settled)) "
            + "after falling asleep, against a usual \(Self.duration(usual)) — "
            + "\(Self.duration(abs(delta))) \(delta > 0 ? "slower" : "quicker") than "
            + "your recent nights."
    }

    static func duration(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        if minutes < 90 { return "\(minutes) min" }
        return String(format: "%.1f h", hours)
    }

    // MARK: - The chart

    private var chart: some View {
        Chart {
            typicalBand
            typicalMedian
            settledRule
            lastNight
        }
        .chartLegend(.hidden)
        .chartXAxisLabel("Hours after you fell asleep")
        .chartYAxisLabel(quantity.unit)
        .chartYScale(domain: yDomain)
        .frame(height: 190)
    }

    /// The visible spread of both the night and the band, with a little headroom
    /// — never a round number above it (`add-chart` §10).
    private var yDomain: ClosedRange<Double> {
        var values = curve.map(\.value)
        values += band.map(\.low)
        values += band.map(\.high)
        guard let low = values.min(), let high = values.max(), low < high else {
            return 0...1
        }
        let pad = (high - low) * 0.1
        return (low - pad)...(high + pad)
    }

    /// Your usual night, as a band between the quartiles.
    ///
    /// `AreaMark(x:yStart:yEnd:)` takes no `stacking:` — an absolute band between
    /// two heights is inherently unstacked, which is what lets last night's line
    /// sit over it honestly rather than displacing it (`add-chart` §7).
    @ChartContentBuilder private var typicalBand: some ChartContent {
        ForEach(band) { point in
            AreaMark(x: .value("Hours", point.hours),
                     yStart: .value("Lower quartile", point.low),
                     yEnd: .value("Upper quartile", point.high))
                .foregroundStyle(tint.opacity(0.12))
                .interpolationMethod(.linear)
        }
    }

    /// The middle of your usual night. Dashed, because a fitted middle is not a
    /// night anybody had (`add-chart` §3).
    @ChartContentBuilder private var typicalMedian: some ChartContent {
        ForEach(band) { point in
            LineMark(x: .value("Hours", point.hours),
                     y: .value("Usual", point.median),
                     series: .value("Series", "usual"))
                .foregroundStyle(tint.opacity(0.6))
                .lineStyle(Theme.projectedStroke)
                .interpolationMethod(.linear)
        }
    }

    /// Last night itself. Solid, because every point of it was measured.
    @ChartContentBuilder private var lastNight: some ChartContent {
        ForEach(curve) { point in
            LineMark(x: .value("Hours", point.hours),
                     y: .value(quantity.unit, point.value),
                     series: .value("Series", "last night"))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
        }
    }

    /// Where the settling point fell. Only on the heart-rate curve, because that
    /// is the curve it was measured from — drawing it over the variability curve
    /// would attach a heart-rate finding to a different quantity.
    @ChartContentBuilder private var settledRule: some ChartContent {
        ForEach(settledMark, id: \.self) { hours in
            RuleMark(x: .value("Settled", hours))
                .foregroundStyle(Theme.accent.opacity(0.5))
                .lineStyle(Theme.projectedStroke)
        }
    }

    private var settledMark: [Double] {
        guard quantity == .heartRate, let hours = night?.settledAfterHours else { return [] }
        return [hours]
    }

    private var legend: some View {
        HStack(spacing: 14) {
            key(colour: tint, dashed: false, label: "Last night")
            if !band.isEmpty {
                key(colour: tint.opacity(0.6), dashed: true,
                    label: "Your usual, \(band.map(\.nights).max() ?? 0) nights")
            }
            if !settledMark.isEmpty {
                key(colour: Theme.accent.opacity(0.6), dashed: true, label: "Settled")
            }
            Spacer(minLength: 0)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    /// A key draws its quantity plain and opaque; the dash carries the same
    /// meaning it does on the chart — not measured (`add-chart` §3, §8).
    private func key(colour: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(colour)
                .frame(width: dashed ? 6 : 14, height: 2)
                .frame(width: 14, alignment: .leading)
            Text(label)
        }
    }

    private var caveatText: String {
        "Both lines are twenty-minute medians, not readings — a bin with one high "
        + "roll-over reading in it would otherwise draw a spike nobody experienced. "
        + "The band is the middle half of your recent nights, fitted without the night "
        + "drawn over it, and it stops where too few nights ran that long."
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(SectionPlaceholder.needsInput(
                subject: "The shape of a night",
                what: "a heart rate recorded while you were asleep, and a sleep source "
                    + "saying when that was",
                remedy: "wear a watch or ring to bed, and connect it under Settings").detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
