import XCTest
@testable import InsightKit

/// The half of the share-sheet hand-off that does not need a container.
///
/// The container half only exists on a device with a provisioned App Group, so
/// the naming and ordering rules are the only part a test can hold — and they
/// are the part that decides whether two files shared in the same minute
/// collide, and whether the app drains them in the order they arrived.
final class SharedInboxTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_760_000_000)

    func testTheIdentifiersAreDeclaredOnce() {
        // Both of these appear in two entitlements files and two bundles. If
        // this test ever needs changing, four other places need changing too.
        XCTAssertEqual(SharedInbox.appGroupIdentifier,
                       "group.com.jasonsalway.healthinsights")
        XCTAssertEqual(SharedInbox.directoryName, "ShotsyInbox")
    }

    func testTheStagedNameKeepsTheOriginalAndItsExtension() {
        let name = SharedInbox.stagedFileName(original: "data_080226.shotsyjson",
                                              at: noon, salt: "ABCDEFGH-1234")
        XCTAssertTrue(name.hasSuffix("data_080226.shotsyjson"), name)
        XCTAssertTrue(name.hasPrefix("1760000000-ABCDEFGH-"), name)
    }

    /// Two files shared in the same second must not be the same file. The
    /// timestamp alone is one-second resolution, which a double-tap beats.
    func testTwoFilesInTheSameSecondDoNotCollide() {
        let first = SharedInbox.stagedFileName(original: "a.shotsyjson", at: noon)
        let second = SharedInbox.stagedFileName(original: "a.shotsyjson", at: noon)
        XCTAssertNotEqual(first, second)
    }

    func testHostileNamesBecomeSomethingAFilesystemAccepts() {
        let name = SharedInbox.sanitised("../../etc/passwd")
        XCTAssertFalse(name.contains("/"), name)
        // Not a dotfile: `ordered` skips those, so a leading dot would stage a
        // file the app then refused to see.
        XCTAssertFalse(name.hasPrefix("."), name)
        XCTAssertEqual(name, "etc-passwd")
        XCTAssertEqual(SharedInbox.sanitised("///"), "shared.shotsyjson")
        XCTAssertEqual(SharedInbox.sanitised("..."), "shared.shotsyjson")
        XCTAssertEqual(SharedInbox.sanitised(""), "shared.shotsyjson")
    }

    func testAVeryLongNameIsBounded() {
        let name = SharedInbox.sanitised(String(repeating: "x", count: 500))
        XCTAssertLessThanOrEqual(name.count, 80)
    }

    /// Oldest first, by the name's own timestamp — not lexicographic, which
    /// puts "9…" after "10…" and drains a backup out of order.
    func testPendingFilesDrainOldestFirst() {
        let names = ["1760000200-b-late.shotsyjson",
                     "999-a-ancient.shotsyjson",
                     "1760000100-c-early.shotsyjson"]
        XCTAssertEqual(SharedInbox.ordered(names), [
            "999-a-ancient.shotsyjson",
            "1760000100-c-early.shotsyjson",
            "1760000200-b-late.shotsyjson"
        ])
    }

    func testDotfilesAreNotTreatedAsSharedFiles() {
        XCTAssertEqual(SharedInbox.ordered([".DS_Store", "1-a.shotsyjson"]),
                       ["1-a.shotsyjson"])
    }
}
