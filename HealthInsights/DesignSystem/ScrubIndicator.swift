import SwiftUI
import Charts

/// The vertical line under the finger while scrubbing a chart.
///
/// Only the energy curve had one. Every other chart accepted a selection, moved
/// its readout, and left the reader guessing which point the numbers belonged to
/// — on a month of daily scores that is a guess across forty pixels.
///
/// A shared `ChartContent` rather than a line copied into each chart, for the
/// reason this app keeps rediscovering: the same four lines in seven files
/// becomes seven slightly different behaviours. It also keeps the construction
/// in one place, which matters more here than usual — a bare `RuleMark` chain
/// can resolve to `Chart3DContent` on this SDK and silently lose `.lineStyle`,
/// so the `ForEach`-over-one-element form below is deliberate and is the shape
/// the rest of the app has verified.
/// A namespace with one builder, **not** a type conforming to `ChartContent`.
///
/// The conforming-struct version is the obvious build and it broke the app
/// target's module emission — the failure surfaces as `EmitSwiftModule`, with no
/// line number, and nothing local can catch it because SwiftUI does not exist on
/// Linux. Every chart in this app instead composes marks through
/// `@ChartContentBuilder` members, so this matches that and stops being novel.
enum ScrubIndicator {

    /// The vertical line at `date`, or nothing when nothing is selected.
    ///
    /// `ForEach` over one element rather than a bare `RuleMark`: a bare chain
    /// can resolve to `Chart3DContent` on this SDK and silently drop
    /// `.lineStyle`. This is the construction the rest of the app has verified.
    @ChartContentBuilder
    static func at(_ date: Date?) -> some ChartContent {
        ForEach(date.map { [$0] } ?? [], id: \.self) { instant in
            RuleMark(x: .value("Selected", instant))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(Theme.referenceStroke)
        }
    }
}
