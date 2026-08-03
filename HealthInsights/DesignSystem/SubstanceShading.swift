import SwiftUI
import Charts
import InsightKit

/// The stretch after a logged substance, shaded behind **every** chart in the
/// app.
///
/// **A standing design rule, set by the user on 2026-08-03**: *"make sure the
/// stimulant impact shading is on EVERY chart in the app, and this is a design
/// rule going forward."*
///
/// It used to be drawn only behind the metric-detail chart, and only for the
/// metrics `SubstanceResponseAnalyzer` compares — the reasoning being that a
/// shaded stretch behind, say, a weight chart would assert a relationship
/// nothing had looked for. That gate is gone, and the rule that replaces it is
/// narrower and more honest: **the shading says a substance was logged in this
/// stretch, and nothing else.** It is a fact about the reader's own timeline,
/// which is true on every chart; what it does *not* claim is that the metric
/// underneath responded. The caption says exactly that, everywhere it appears.
///
/// Rendering follows the rules the app already had: one merged span per
/// overlapping run (`SubstanceResponseAnalyzer.affectedWindows`), because three
/// coffees stacked as three translucent rectangles would encode *how many logs*
/// in a channel meant to say only *logged or not*; neutral grey rather than a
/// substance hue, because "a log sits here" is not a judgement; and clipped to
/// the plotted range, because an unclipped span widens the x domain.
enum SubstanceShading {

    /// Printed wherever the shading appears. A band with no caption is
    /// decoration — the same rule the reference ranges follow.
    static let caption = "Shaded: the hours after something you logged — a stimulant, alcohol or a medication dose. It marks when, not what it did."

    @ChartContentBuilder
    static func marks(_ windows: [SubstanceWindow],
                      in range: ClosedRange<Date>) -> some ChartContent {
        ForEach(windows.filter { $0.overlaps(range) }) { window in
            RectangleMark(
                xStart: .value("From", Swift.max(window.start, range.lowerBound)),
                xEnd: .value("To", Swift.min(window.end, range.upperBound)))
                // Below the reference bands' own opacity so the two can overlap
                // without either becoming unreadable.
                .foregroundStyle(Color.secondary.opacity(0.10))
        }
    }
}
