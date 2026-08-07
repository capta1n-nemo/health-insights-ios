import XCTest
import SwiftUI
import InsightKit
@testable import HealthInsights

/// **Does the deep dive under the insight web actually draw — in every state?**
///
/// Backlog P20. `CardRenderSmokeTests` covers the two card tabs and all eighteen
/// detail screens; nothing had ever evaluated `ScoreComparisonDetailView`, which
/// is one tap off the Insights hero and now carries three sections rather than
/// one. Same argument as that file's: `xcodebuild build` type-checks a `body`
/// and never runs it, so an index out of range on a short frame list or a
/// `Slider` given an empty range reaches the device intact.
///
/// The morph section is exercised **directly**, with timelines built by hand,
/// because `ImageRenderer` does not run `.task` — so rendering the screen alone
/// would only ever draw the section's "nothing yet" arm and would leave the
/// populated one, which is the whole feature, unevaluated.
///
/// ⚠️ A smoke test is worth what a smoke test is worth: it proves the thing
/// draws, not that what it drew is right. `use-the-simulator` still applies.
@MainActor
final class DeepDiveRenderTests: XCTestCase {

    private static let canvas = CGSize(width: 393, height: 3000)

    private func render(_ view: some View, _ what: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(content:
            view.frame(width: Self.canvas.width, height: Self.canvas.height)
        )
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage, "\(what) produced no image.", file: file, line: line)
    }

    // MARK: - The screen

    /// Empty is the half that breaks: a fresh install has nothing in any of the
    /// arrays this screen indexes, and it is the state a new reader is in.
    func testDeepDiveRendersOnAFreshInstall() {
        let model = TestAppModel.make()
        render(NavigationStack { ScoreComparisonDetailView() }.environment(model),
               "Deep dive (empty)")
    }

    // ⚠️ **The seeded whole-screen render is missing, and it is a live defect
    // rather than a test that was not written.**
    //
    // `render(NavigationStack { ScoreComparisonDetailView() })` on
    // `TestAppModel.seeded()` takes the host down with **"Test crashed with
    // signal kill"** — SIGKILL, so no crash report and no stack. It reproduces
    // on **unmodified `main`**, with this file's own section removed from the
    // screen and then with the whole screen reverted to `HEAD`, so it predates
    // backlog P20 and belongs to nothing in it.
    //
    // The likely mechanism, stated as the guess it is: this is the one screen
    // that asks `AppModel.scoreHistory(for:)` for **every** scored insight, and
    // `ImageRenderer` evaluates the body without the throttling a real scroll
    // gives it — so thirteen 90-day replays start against a 90-day synthetic
    // sample set inside a test host with no jetsam headroom. That would make it
    // an `ImageRenderer` limit rather than something the reader can hit on the
    // phone, and **that has not been shown either way**. Nobody should record
    // it as "fine on device" until someone has opened it on one.
    //
    // What *is* covered below: the screen on a fresh install, and the morph
    // section in every state it has, with its frames built directly — which is
    // where this file's own new code lives.

    // MARK: - The morph section, in each of its states

    private func timeline(_ granularity: WebTimeGranularity,
                          months: Int, cards: [InsightID]) -> BalanceWebTimeline {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        var histories: [InsightID: [ScorePoint]] = [:]
        for (offset, id) in cards.enumerated() {
            var points: [ScorePoint] = []
            for day in 0..<(months * 30) {
                let date = calendar.date(byAdding: .day, value: day, to: start)!
                points.append(ScorePoint(date: date,
                                         score: Double(40 + offset * 7 + day % 11),
                                         confidence: .moderate, contributorCount: 4))
            }
            histories[id] = points
        }
        return BalanceWebTimeline.build(histories: histories, granularity: granularity,
                                        calendar: calendar)
    }

    /// The populated case — a slider with several real steps behind it.
    func testMorphSectionRendersAPopulatedTimeline() {
        let built = timeline(.month, months: 6,
                             cards: [.readiness, .sleep, .fitness, .bodyComposition, .energy])
        XCTAssertTrue(built.isMorphable, "the fixture must actually be morphable")
        render(WebMorphSection(timeline: built, isReplaying: false,
                               granularity: .constant(.month)),
               "Morph section (populated)")
    }

    /// One step is not a morph, and the slider's range collapses to a point —
    /// which is the shape `Slider(in: 0...0)` traps on.
    func testMorphSectionRendersASingleStep() {
        let built = timeline(.quarter, months: 2, cards: [.readiness, .sleep, .fitness])
        XCTAssertEqual(built.frames.count, 1)
        render(WebMorphSection(timeline: built, isReplaying: false,
                               granularity: .constant(.quarter)),
               "Morph section (one step)")
    }

    /// Below the three-spoke floor: enough steps, not enough cards.
    func testMorphSectionRendersTooFewCards() {
        let built = timeline(.month, months: 4, cards: [.readiness, .sleep])
        XCTAssertFalse(built.isMorphable)
        render(WebMorphSection(timeline: built, isReplaying: false,
                               granularity: .constant(.month)),
               "Morph section (two cards)")
    }

    /// Nothing at all, and the same section while the replays are still running
    /// — two different sentences, and both have to draw.
    func testMorphSectionRendersItsEmptyStates() {
        render(WebMorphSection(timeline: .empty(.week), isReplaying: false,
                               granularity: .constant(.week)),
               "Morph section (nothing)")
        render(WebMorphSection(timeline: .empty(.week), isReplaying: true,
                               granularity: .constant(.week)),
               "Morph section (replaying)")
    }
}
