import SwiftUI
import InsightKit

/// Which way a card's score has been going, beside the number.
///
/// ## What it deliberately isn't
///
/// It is not "vs yesterday". A survey of Oura, Whoop, Garmin, Apple Health,
/// Fitbit and Withings found that not one of them renders a day-over-day delta
/// on a daily score, and the reason is arithmetic rather than taste: day-to-day
/// variability in HRV runs at roughly 5% and is reported between 3% and 13%
/// depending on method, while a genuinely hard day moves it 10–20%. An arrow
/// driven by yesterday would be reporting noise most days, and an indicator that
/// is usually wrong gets ignored — which costs more than not having one.
///
/// `ScoreChangeReader` takes the comparison somewhere the signal survives:
/// today against the trailing week for daily cards, four weeks against the
/// quarter for trend cards. The chip just draws the answer.
///
/// ## Silence is a state
///
/// Nothing renders when the movement is inside the score's own usual spread.
/// Apple suppresses a trend outright when nothing has moved; Garmin and Fitbit
/// both render "inside your usual range" rather than a direction. A card seen
/// several times a day has to earn the right to point at something.
///
/// ## Colour is valence, not direction
///
/// Every score in this app is oriented so higher is better — that is what lets
/// `ScoreDial` colour them all on one scale — so up is green and down is amber,
/// and the arrow carries the direction. Where a metric's direction is not its
/// valence, the right thing is no colour at all; no score here is in that
/// position, and `Sleep Regularity` is scored (spread, not clock time)
/// specifically so it isn't.
struct ScoreChangeChip: View {
    let change: ScoreChange

    var body: some View {
        if let label = change.label {
            HStack(spacing: 2) {
                Image(systemName: change.direction == .up ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.bold))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var tint: Color {
        change.direction == .up ? Theme.good : Theme.warn
    }

    /// Spoken in full, because "+7" alone says nothing about what it is seven of
    /// or what it is seven above.
    private var accessibilityLabel: String {
        let direction = change.direction == .up ? "up" : "down"
        return "\(direction) \(Int(abs(change.delta).rounded())) points, \(change.comparison)"
    }
}
