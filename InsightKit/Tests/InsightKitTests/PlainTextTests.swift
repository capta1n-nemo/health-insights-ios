import XCTest
@testable import InsightKit

final class PlainTextTests: XCTestCase {
    func testStripsBoldAndItalic() {
        XCTAssertEqual(PlainText.strip("Your **heart health** is *good* today."),
                       "Your heart health is good today.")
    }

    func testStripsUnderscoreEmphasisAndCode() {
        XCTAssertEqual(PlainText.strip("Readiness is __high__ and `HRV` is stable."),
                       "Readiness is high and HRV is stable.")
    }

    func testStripsHeadingsAndBullets() {
        let input = """
        ## Today
        - Sleep was solid
        - Resting heart rate is steady
        """
        let out = PlainText.strip(input)
        XCTAssertFalse(out.contains("#"))
        XCTAssertFalse(out.contains("- "))
        XCTAssertTrue(out.contains("Sleep was solid"))
        XCTAssertTrue(out.contains("Resting heart rate is steady"))
    }

    func testStripsLinksKeepingText() {
        XCTAssertEqual(PlainText.strip("See [your trends](app://trends) for more."),
                       "See your trends for more.")
    }

    func testLeavesPlainTextUnchanged() {
        let plain = "Here's your snapshot — heart health is good. Tap any card."
        XCTAssertEqual(PlainText.strip(plain), plain)
    }

    func testHandlesStrayDoubleAsterisks() {
        XCTAssertEqual(PlainText.strip("Great progress **"), "Great progress")
    }
}
