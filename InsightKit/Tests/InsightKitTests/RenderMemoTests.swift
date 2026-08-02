import XCTest
@testable import InsightKit

/// The one behaviour that matters: a transient `nil` must not become a sticky
/// one. Shaped like the 2026-08-02 screenshots — "What you're made of" claiming
/// no scale existed while six scale signals rendered above it, because the
/// section's `nil` had been cached during a window the data was briefly absent.
final class RenderMemoTests: XCTestCase {

    func testCachesANonNilResult() {
        var memo = RenderMemo()
        var runs = 0
        _ = memo.value("k") { runs += 1; return 42 }
        let hit = memo.value("k") { runs += 1; return 99 }
        XCTAssertEqual(hit, 42)
        XCTAssertEqual(runs, 1, "a non-nil result is computed once")
    }

    func testNeverCachesNil_soASectionHealsWhenItsDataArrives() {
        var memo = RenderMemo()
        var backing: Int? = nil
        let first = memo.value("split") { backing }
        XCTAssertNil(first)
        backing = 7 // the data lands (a sync completes, hydration finishes)
        let second = memo.value("split") { backing }
        XCTAssertEqual(second, 7,
                       "a nil computed during a transient window must not outlive it")
        backing = nil
        let third = memo.value("split") { backing }
        XCTAssertEqual(third, 7, "…and the non-nil result is the one that sticks")
    }

    func testRemoveAllClearsHits() {
        var memo = RenderMemo()
        _ = memo.value("k") { 1 }
        memo.removeAll(keepingCapacity: true)
        let recomputed = memo.value("k") { 2 }
        XCTAssertEqual(recomputed, 2)
    }

    func testDistinctKeysDoNotCollide() {
        var memo = RenderMemo()
        _ = memo.value("a") { 1 }
        let b = memo.value("b") { 2 }
        XCTAssertEqual(b, 2)
    }
}
