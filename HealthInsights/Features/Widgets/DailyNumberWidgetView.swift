import SwiftUI
import InsightKit

/// **The home-screen widget's rendering — the whole of it.**
///
/// Backlog `D8`. This lives in the *app* target rather than in the extension,
/// and that is the load-bearing decision in this file.
///
/// ## Why it is here and not in `HealthInsightsWidgets/`
///
/// The widget extension target cannot be enabled on `main` today — it needs an
/// App Group to see the app's data and an Xcode account on the deploy runner to
/// sign a second bundle id, and neither exists (see `docs/widgets.md`). A view
/// that lived only in a disabled target would be code that never compiles, in a
/// repo whose gate is "does it compile and do the tests pass". Here it compiles
/// on every build, renders in the in-app preview, and the extension — when it
/// is switched on — imports it rather than reimplementing it.
///
/// ⚠️ **This file deliberately does not `import WidgetKit`.** The app target's
/// linked frameworks are an input to signing, and this repo has already lost a
/// day to a misread deploy failure; a change to the app's build inputs made in
/// passing, for a feature that cannot ship yet, is not a trade worth taking.
/// `WidgetFamily` is mapped to ``WidgetRenderSize`` by the extension, which is
/// the one place WidgetKit belongs.
///
/// ## What it may show
///
/// Nothing this file decides. Every string comes from ``WidgetSnapshot``, whose
/// type is the rule — a figure and its qualifier are one value, a card with no
/// figure yields its own sentence. This view's only job is to guarantee the
/// qualifier is **rendered**, never merely carried, at every size.

/// The two families this widget will offer. Named separately from WidgetKit's
/// `WidgetFamily` so nothing here depends on it.
///
/// ⚠️ **No `accessoryCircular` / `accessoryRectangular`.** Those render on a
/// *locked* phone, which puts this reader's health state in front of anyone who
/// picks it up. That is a decision for them to opt into, not a default — and a
/// circular accessory has room for a number and nothing else, which is the one
/// shape this snapshot type exists to refuse.
enum WidgetRenderSize {
    case small
    case medium

    /// How many supporting lines fit under the figure.
    ///
    /// **One is the floor, not zero.** The qualifier is the first supporting
    /// line, so a size that showed none would be showing a bare number — which
    /// is the whole defect. If a future size cannot fit a line, it does not get
    /// the figure either.
    var supportingLineLimit: Int {
        switch self {
        case .small: return 1
        case .medium: return 2
        }
    }
}

struct DailyNumberWidgetView: View {
    let snapshot: WidgetSnapshot
    let size: WidgetRenderSize
    /// Injected so the preview and the timeline entry both render against a
    /// stated instant rather than reaching for `Date()` inside a body.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 4)
            switch snapshot.content {
            case .figure(let figure): figureBody(figure)
            case .withheld(let headline, _): withheldBody(headline)
            }
            supporting
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.text.square")
                .font(.caption2)
            Text(snapshot.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
    }

    private func figureBody(_ figure: WidgetSnapshot.Figure) -> some View {
        Text(figure.headline)
            .font(size == .small ? .system(size: 40, weight: .semibold, design: .rounded)
                                 : .system(size: 46, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            // Coloured by the band the card itself would use, and only when the
            // card published a score. A headline with no 0–100 behind it
            // ("Good", "5.2%") is left in the primary colour: inventing a band
            // for it here would be this view deciding something the model
            // declined to.
            .foregroundStyle(figure.score.map { Theme.color(forScore: $0) } ?? .primary)
    }

    private func withheldBody(_ headline: String) -> some View {
        // Deliberately the same weight as a driver line, not the size of a
        // figure. "Waiting for today's sync" set in 40pt would read as an
        // announcement; it is an explanation.
        Text(headline)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(size == .small ? 2 : 3)
            .minimumScaleFactor(0.8)
    }

    /// The qualifier, and whatever else fits. **Never omitted for a figure** —
    /// `supportingLines` puts the qualifier first and the limit is at least one.
    private var supporting: some View {
        let lines = Array(snapshot.supportingLines(now: now)
            .prefix(size.supportingLineLimit))
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The widget drawn at its real proportions, for the in-app preview.
///
/// Sizes are the iPhone home-screen grid's, rounded — close enough that a line
/// which overflows here overflows on the phone, which is the only thing this
/// needs to be right about.
struct WidgetChrome<Content: View>: View {
    let size: WidgetRenderSize
    @ViewBuilder let content: Content

    private var dimensions: CGSize {
        switch size {
        case .small: return CGSize(width: 158, height: 158)
        case .medium: return CGSize(width: 338, height: 158)
        }
    }

    var body: some View {
        content
            .frame(width: dimensions.width, height: dimensions.height)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

#Preview("Scored") {
    let result = InsightResult(
        id: .readiness, title: "Readiness", primaryValue: 74, headline: "74",
        score: 74, confidence: .high,
        explanation: "Scored against your own baseline.",
        driverLines: [InsightDriver(text: "HRV is 12% below your normal", isNotable: true)],
        unmetRequirements: [])
    let snapshot = WidgetSnapshot.from(result, capturedAt: .now, dataThrough: .now)
    return HStack(spacing: 12) {
        WidgetChrome(size: .small) {
            DailyNumberWidgetView(snapshot: snapshot, size: .small, now: .now)
        }
        WidgetChrome(size: .medium) {
            DailyNumberWidgetView(snapshot: snapshot, size: .medium, now: .now)
        }
    }
}

#Preview("Withheld") {
    let result = InsightResult(
        id: .readiness, title: "Readiness", primaryValue: nil,
        headline: "Waiting for today's sync", score: nil, confidence: .low,
        explanation: "Readiness is about today, and nothing from today has arrived yet.",
        driverLines: [], unmetRequirements: [], isAwaitingTodaysData: true)
    let snapshot = WidgetSnapshot.from(result, capturedAt: .now, dataThrough: nil)
    return WidgetChrome(size: .small) {
        DailyNumberWidgetView(snapshot: snapshot, size: .small, now: .now)
    }
}
