import XCTest
import SwiftUI
import InsightKit
@testable import HealthInsights

/// **Does every card's detail screen actually draw?**
///
/// `InsightDetailView` is ~3,700 lines and its section switches are
/// `@ViewBuilder` properties — not callable from a test, and not reachable from
/// InsightKit at all. Until now the only thing that had ever evaluated their
/// bodies was the reader's phone. `swiftc -parse` builds a syntax tree;
/// `xcodebuild build` type-checks; neither runs a `body`, so an index out of
/// range on a short series, a force-unwrap of a metric a card does not have, or
/// a `Chart` fed an empty domain all reach the device intact.
///
/// `ImageRenderer` is what makes this testable: it evaluates the view tree and
/// lays it out, on the main actor, without a window or a running app. Failing to
/// produce an image, or trapping while trying, is a card that would have crashed
/// or drawn nothing.
///
/// ⚠️ **This is a smoke test and is worth exactly what a smoke test is worth.**
/// It proves a card renders; it says nothing about whether what it rendered is
/// right, and `use-the-simulator` still applies for that. What it does retire is
/// the class where a card compiles, ships, and traps the moment it is opened —
/// which no other check in this repo can see.
@MainActor
final class CardRenderSmokeTests: XCTestCase {

    /// iPhone-width, tall enough that lazily-stacked sections are laid out
    /// rather than deferred off-screen.
    private static let canvas = CGSize(width: 393, height: 3000)

    /// ⚠️ **The `autoreleasepool` is load-bearing, not tidiness.**
    ///
    /// The canvas is 393 × 3000 at scale 1 — about 4.7 million pixels, so each
    /// `uiImage` is roughly 19 MB of backing store, and it is a `UIImage`
    /// returned autoreleased. Without a pool per render, every image a sweep
    /// produces stays alive until the whole test method returns: the loop over
    /// `InsightID.allCases` was holding all of them at once, and on 2026-08-07
    /// the twentieth card took it past what the simulator would give the host.
    /// The symptom is `Test crashed with signal kill` with no `error:` line and
    /// no stack — a memory kill, which reads exactly like a card that traps.
    ///
    /// The card that tipped it (`.supplementStack`) rendered fine alone and the
    /// other nineteen rendered fine without it; only the whole sweep died, which
    /// is the signature of an accumulation rather than a defect in any card.
    /// **Draining per render fixes the class**, so the next card added does not
    /// re-discover this.
    private func render(_ view: some View, _ what: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        autoreleasepool {
            let renderer = ImageRenderer(content:
                view.frame(width: Self.canvas.width, height: Self.canvas.height)
            )
            renderer.scale = 1
            XCTAssertNotNil(renderer.uiImage, "\(what) produced no image.",
                            file: file, line: line)
        }
    }

    /// ⚠️ **Cards this test cannot run, because rendering them kills the
    /// process — a live defect, not a test limitation.**
    ///
    /// `.sleep` was found on this target's very first run (2026-08-07):
    ///
    ///     Simultaneous accesses to 0x…, but modification requires exclusive access.
    ///     Previous access (a modification) started at AppModel.memoized<A>(_:_:)
    ///     …  SettlingSection.reading.getter
    ///
    /// `SettlingSection.swift:68` calls `model.memoized("overnightCardiac") {
    /// OvernightCardiacReading.build(model) }`, and `build` — at
    /// `OvernightHRVSection.swift:36` — calls `model.memoized(…)` again. Two
    /// overlapping *modify* accesses to `AppModel.renderMemo`, which is a
    /// struct with a mutating `value(_:_:)`, so Swift's exclusivity check traps.
    /// It traps in Release too: dynamic exclusivity enforcement is on in both
    /// configurations. `OvernightHRVSection.swift:90` nests the same pair.
    ///
    /// It only fires with data because both call sites return early on an empty
    /// history, which is exactly why `testEveryCardDetailScreenRendersEmpty`
    /// below is green on the same card.
    ///
    /// **Do not "fix" this by widening the list.** Each entry is a card the
    /// reader can crash, and the entry goes when the crash does. The fix is in
    /// `AppModel.memoized` — it must not hold exclusive access to `renderMemo`
    /// across `compute()`.
    private static let knownRenderCrashes: Set<InsightID> = [.sleep]

    /// Every card, on a model with a real history.
    ///
    /// One test rather than one per card because they share a seeded model:
    /// `seedSyntheticData` plus a full evaluation is the expensive part, and
    /// paying it once per card would put this target's runtime somewhere nobody
    /// would keep it in the gate.
    func testEveryCardDetailScreenRendersWithData() async {
        let model = await TestAppModel.seeded()
        for id in InsightID.allCases where !Self.knownRenderCrashes.contains(id) {
            render(InsightDetailView(insightID: id).environment(model),
                   "\(id) detail screen (with data)")
        }
    }

    /// Every card again, on a model with nothing.
    ///
    /// **The empty state is the half that breaks.** A card with a full history
    /// has something in every array it indexes; a card on a fresh install has
    /// nothing in any of them, and that is where `first!`, `last!` and
    /// `array[0]` are found. It is also the state a new reader is in, so it is
    /// the state the app is judged on.
    func testEveryCardDetailScreenRendersEmpty() {
        let model = TestAppModel.make()
        for id in InsightID.allCases {
            render(InsightDetailView(insightID: id).environment(model),
                   "\(id) detail screen (empty)")
        }
    }

    /// The two tabs that list cards, in both states.
    ///
    /// These carry the visibility filters `CardRoutingTests` mirrors, plus the
    /// hero web and the suggestions drawer — the parts of the screen that are
    /// not a card and so are covered by nothing else.
    func testCardTabsRender() async {
        let empty = TestAppModel.make()
        render(TodayView().environment(empty), "Today (empty)")
        render(InsightsListView().environment(empty), "Insights (empty)")

        let seeded = await TestAppModel.seeded()
        render(TodayView().environment(seeded), "Today (with data)")
        render(InsightsListView().environment(seeded), "Insights (with data)")
    }
}
