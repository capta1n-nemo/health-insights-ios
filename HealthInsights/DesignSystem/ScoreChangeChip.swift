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
/// ## Steady is a state the chip shows, not one it hides
///
/// It used to render nothing when the movement was inside the score's own usual
/// spread. That read as broken: on a screen of daily cards, only the one card
/// that happened to move showed a badge and the rest showed nothing, and the
/// reader could not tell "no change" from "not measured". The chip now draws all
/// three directions — up, down, and a neutral **steady** — so silence means only
/// one thing: not enough history to judge, which is when `ScoreChange` is `nil`
/// and there is no chip at all.
///
/// Apple, Garmin and Fitbit all render "inside your usual range" rather than an
/// arrow when nothing has moved; this is that, kept next to the number.
///
/// ## Colour is valence, not direction
///
/// Every score in this app is oriented so higher is better — that is what lets
/// `ScoreDial` colour them all on one scale — so up is green, down is amber, and
/// steady is neutral. The arrow carries the direction; steady has no arrow, an
/// equals sign, and no valence colour, because "unchanged" is neither good news
/// nor bad.
struct ScoreChangeChip: View {
    let change: ScoreChange

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
            Text(change.chipLabel)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch change.direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .steady: return "equal"
        }
    }

    private var tint: Color {
        switch change.direction {
        case .up: return Theme.good
        case .down: return Theme.warn
        case .steady: return .secondary
        }
    }

    /// Spoken in full, because "+7" alone says nothing about what it is seven of
    /// or what it is seven above.
    private var accessibilityLabel: String {
        switch change.direction {
        case .up: return "up \(Int(abs(change.delta).rounded())) points, \(change.comparison)"
        case .down: return "down \(Int(abs(change.delta).rounded())) points, \(change.comparison)"
        case .steady: return "no change, \(change.comparison)"
        }
    }
}
