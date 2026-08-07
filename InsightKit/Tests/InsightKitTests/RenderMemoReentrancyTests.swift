import XCTest
@testable import InsightKit

/// **The `SIGABRT` of backlog `D58`, reproduced in eight lines.**
///
/// Two crash reports on 2026-08-07, an hour and forty minutes apart and from
/// different builds, carried the same stack: `swift_beginAccess →
/// swift::fatalError → abort`, immediately above `AppModel.memoized`. No
/// exception type, no subtype, no `asi` payload — an exclusivity trap leaves
/// nothing else behind, which is why the row spent a day looking like an
/// unexplained abort of ambiguous provenance.
///
/// The cause is structural rather than incidental. `RenderMemo.value` is
/// `mutating`, so calling it **on a stored property** holds an exclusive access
/// to that property for the whole of the caller's closure — and the app's real
/// call graph nests memoisation two deep (`SettlingSection` memoises
/// `"overnightCardiac"`; `OvernightCardiacReading.build` memoises
/// `"nightSleepAllNights"`). Every render of that section aborted the process.
///
/// ## ⚠️ What this test can and cannot do
///
/// It pins the **fix**: `cached` + `store`, with nothing held across the
/// compute, survives re-entry and returns the right answers. It deliberately
/// does **not** attempt to exercise the crashing shape — an exclusivity
/// violation is a process abort, not a catchable error, so a test that
/// reproduced it would take the whole suite with it. The crashing shape is
/// recorded in the doc comments on `RenderMemo.value` and `AppModel.memoized`
/// instead, where the next caller will actually read it.
final class RenderMemoReentrancyTests: XCTestCase {

    /// The app's shape: a memo held in a stored property of a reference type,
    /// exactly as `AppModel` holds it.
    private final class Host {
        var memo = RenderMemo()
        private(set) var computeCount: [String: Int] = [:]

        /// `AppModel.memoized`, character for character in structure.
        func memoized<T>(_ key: String, _ compute: () -> T) -> T {
            if let hit: T = memo.cached(key) { return hit }
            computeCount[key, default: 0] += 1
            let value = compute()
            memo.store(key, value)
            return value
        }
    }

    func testANestedMemoisationDoesNotTrapAndBothLayersCache() {
        let host = Host()

        func outer() -> Int {
            host.memoized("outer") { host.memoized("inner") { 7 } * 2 }
        }

        XCTAssertEqual(outer(), 14, "the nested compute must run and its result reach the outer one")
        XCTAssertEqual(outer(), 14, "and the second ask must agree with the first")
        XCTAssertEqual(host.computeCount["outer"], 1, "the outer value was cached")
        XCTAssertEqual(host.computeCount["inner"], 1, "the inner value was cached by the nested call")
    }

    /// Three deep, because the app's graph is not guaranteed to stop at two and
    /// the old shape trapped at the *second* access whatever came after it.
    func testThreeLevelsOfNestingSurvive() {
        let host = Host()
        let result = host.memoized("a") {
            host.memoized("b") { host.memoized("c") { 3 } + 10 } + 100
        }
        XCTAssertEqual(result, 113)
        XCTAssertEqual(host.memoized("c") { 999 }, 3, "the innermost value is in the cache, not recomputed")
    }

    /// The nil rule has to survive being moved out of `value` and into `store`,
    /// because a cached `nil` is the defect `RenderMemo`'s own doc comment opens
    /// with — "What you're made of" claiming the reader had no scale while the
    /// scale's data was on screen two sections up.
    func testANilResultIsStillNeverCachedOnTheReentrantPath() {
        let host = Host()
        var answer: Int? = nil
        func read() -> Int? { host.memoized("maybe") { answer } }

        XCTAssertNil(read())
        XCTAssertEqual(host.computeCount["maybe"], 1)
        XCTAssertNil(read())
        XCTAssertEqual(host.computeCount["maybe"], 2, "a nil must recompute rather than stick")

        answer = 42
        XCTAssertEqual(read(), 42, "and the moment there is an answer it is seen")
        XCTAssertEqual(read(), 42)
        XCTAssertEqual(host.computeCount["maybe"], 3, "the non-nil answer is cached")
    }

    /// `cached` must keep the unwrap-before-cast rule that `value` documents:
    /// `storage[key] as? T` succeeds as `.some(.none)` for a missing key when
    /// `T` is itself optional, which made every optional compute "hit" on its
    /// first ask and never run.
    func testAMissingKeyIsAMissRatherThanACachedNilForAnOptionalType() {
        let memo = RenderMemo()
        // `== nil` rather than `XCTAssertNil`, which takes `Any?` and so
        // flattens the double optional this test is entirely about.
        let hit: Int?? = memo.cached("never stored")
        XCTAssertTrue(hit == nil, "a missing key must be a miss, even when the value type is optional")
    }
}
