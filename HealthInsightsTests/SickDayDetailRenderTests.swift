import XCTest
import SwiftUI
import InsightKit
@testable import HealthInsights

/// **Does the per-day sick page actually draw — in every state it has?**
///
/// Backlog `B11-2`. `xcodebuild build` type-checks a `body` and never runs it,
/// so an index out of range on an empty signal list or a `Chart` given a
/// zero-height frame reaches the device intact. Two cards shipped *invisible* on
/// 2026-08-03 with green tests and green CI behind them; a page reachable only
/// from two taps inside a collapsed section is exactly the shape that happens
/// to.
///
/// The three states that matter are the three arms this page branches on, and
/// the first is the one that breaks: **nothing judged**. A day outside the
/// replay's span has no output, no signals, no derived rows and no reported
/// components — every list on the screen is empty at once, which is the state a
/// reader reaches by tapping any day before the app existed.
///
/// ⚠️ `ImageRenderer` does not run `.task`, so the summary section is always
/// evaluated on `SickDayReport.templateSummary` here rather than on the model's
/// phrasing. That is the right coverage: the template is the sentence that ships
/// wherever no on-device model exists, and it is the one a test can pin.
///
/// ⚠️ A smoke test is worth what a smoke test is worth: it proves the thing
/// draws, not that what it drew is right. `use-the-simulator` still applies.
@MainActor
final class SickDayDetailRenderTests: XCTestCase {

    private static let canvas = CGSize(width: 393, height: 4000)

    private func render(_ view: some View, _ what: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(content:
            view.frame(width: Self.canvas.width, height: Self.canvas.height)
        )
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage, "\(what) produced no image.", file: file, line: line)
    }

    private func page(_ model: AppModel, day: Date) -> some View {
        NavigationStack {
            SickDayDetailView(day: day, history: model.radarHistory)
        }
        .environment(model)
    }

    /// A fresh install: nothing judged, nothing recorded, no derived figures.
    /// Every collection on the page is empty simultaneously.
    func testTheDayPageRendersWithNothingJudged() {
        let model = TestAppModel.make()
        render(page(model, day: Date()), "Sick day (nothing judged)")
    }

    /// A day well outside anything the replay covers — the state a reader
    /// reaches by paging the calendar back past their own history.
    func testTheDayPageRendersForADayBeforeAnyData() {
        let model = TestAppModel.make()
        let old = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
        render(page(model, day: old), "Sick day (before any data)")
    }

    /// Seeded: signals, derived figures and a populated chart. The bar chart is
    /// the part with a computed height (`count * 26 + 30`), which is exactly the
    /// arithmetic that produces an invalid frame on an empty list.
    func testTheDayPageRendersOnSeededData() async {
        let model = await TestAppModel.seeded()
        render(page(model, day: Date()), "Sick day (seeded)")
    }

    /// The correction sheet, in both of its arms — the picker for "how bad?"
    /// only exists when the kind is not `.notIll`, and a `Picker` whose
    /// selection is absent from its options renders blank rather than failing,
    /// which is why the estimate's `.unknown` is seeded as `.notIll`.
    func testTheCorrectionSheetRenders() {
        let model = TestAppModel.make()
        let estimate = IllnessEstimate(
            assessment: IllnessAssessment(kind: .unknown, severity: nil),
            basis: ["You recorded nothing."],
            uncertainty: "A prompt, not a finding.",
            artifact: IllnessArtifact(physiologicalExcess: 0, accumulatedStatistic: 0,
                                      reportedExcess: 0, leaningSignals: 0,
                                      wasJudged: false))
        render(IllnessCorrectionSheet(day: Date(), estimate: estimate, existing: nil)
                .environment(model),
               "Illness correction (unanswered)")

        let answered = IllnessJudgement(day: Date(), estimate: estimate)
            .reviewed(correction: IllnessAssessment(kind: .respiratory, severity: .severe),
                      confirmed: false, at: Date())
        render(IllnessCorrectionSheet(day: Date(), estimate: estimate, existing: answered)
                .environment(model),
               "Illness correction (answered)")
    }

    /// The Data-tab page gained a second section (`B11-9`), including its
    /// below-the-floor footer — the arm that prints where a hit rate would be.
    func testTheSickDaysDataPageStillRenders() {
        let model = TestAppModel.make()
        render(NavigationStack { SickDaysDataView() }.environment(model),
               "Sick days data page")
    }
}
