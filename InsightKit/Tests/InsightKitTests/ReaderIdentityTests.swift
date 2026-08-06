import XCTest
@testable import InsightKit

/// Who the reader is, to their calendar — B7 H1.
///
/// ⚠️ **Every name and address in this file is invented**, per
/// `docs/privacy-and-ip.md`: this repo is public, and an identity fixture is
/// the one string that would identify the reader outright.
final class ReaderIdentityTests: XCTestCase {

    private let identity = ReaderIdentity(
        name: "Alex Reader",
        workEmails: ["a.reader@example.com"],
        personalEmails: ["alex@example.org"])

    // MARK: - Emails

    /// The shape this is actually called with: EventKit hands over an
    /// organiser as a `mailto:` URL, in whatever case the server used.
    func testOrganizerMatchingSurvivesMailtoCaseAndWhitespace() {
        XCTAssertTrue(identity.matches(organizer: "a.reader@example.com"))
        XCTAssertTrue(identity.matches(organizer: "mailto:A.Reader@Example.com"))
        XCTAssertTrue(identity.matches(organizer: "  alex@example.org "))
        XCTAssertFalse(identity.matches(organizer: "someone.else@example.com"))
        XCTAssertFalse(identity.matches(organizer: nil))
        XCTAssertFalse(identity.matches(organizer: ""))
    }

    /// Work and personal both answer "is this me" — the split exists for the
    /// *kind* of context an address gives, not for matching.
    func testWorkAndPersonalEmailsBothCount() {
        XCTAssertEqual(identity.allEmails,
                       ["a.reader@example.com", "alex@example.org"])
    }

    // MARK: - The name in a title

    /// The brief's own example, shape for shape: *"'John smith on holiday -
    /// OOO' It can see if that is me, or someone else."*
    func testTheNameIsFoundInAnOOOTitleWhicheverWayRoundItIsWritten() {
        XCTAssertTrue(identity.isMe("Alex Reader on holiday - OOO"))
        XCTAssertTrue(identity.isMe("Reader, Alex — OOO"))
        XCTAssertTrue(identity.isMe("ALEX READER annual leave"))
    }

    /// Whole words only: a name found *inside* another word is not the reader,
    /// and "Ann" inside "Annual" is exactly how a colleague's marker would
    /// become the reader's holiday.
    func testTheNameMatchesOnWordBoundariesOnly() {
        let ann = ReaderIdentity(name: "Ann")
        XCTAssertFalse(ann.isMe("Annual leave"))
        XCTAssertTrue(ann.isMe("Ann OOO"))

        XCTAssertFalse(identity.isMe("Alexander Readers offsite"),
                       "substrings of both names, words of neither")
        XCTAssertFalse(identity.isMe("Sam Poll OOO"))
    }

    /// Every word of the name must appear — a shared first name alone is not
    /// the reader.
    func testASharedFirstNameAloneIsNotAMatchForATwoWordName() {
        XCTAssertFalse(identity.isMe("Alex T OOO"),
                       "another Alex's absence claimed as the reader's")
    }

    // MARK: - Configured or not

    /// An unconfigured identity must read as *no* identity: the classifier's
    /// ambiguous-absence rule keys off this, and a blank name that counted as
    /// configured would silently turn every unnamed OOO into "not mine".
    func testBlankIdentityIsNotConfigured() {
        XCTAssertFalse(ReaderIdentity().isConfigured)
        XCTAssertFalse(ReaderIdentity(name: "   ").isConfigured)
        XCTAssertFalse(ReaderIdentity(workEmails: ["  "]).isConfigured,
                       "a whitespace email is not an identity")
        XCTAssertTrue(ReaderIdentity(name: "Alex").isConfigured)
        XCTAssertTrue(ReaderIdentity(workEmails: ["a.reader@example.com"]).isConfigured)
        XCTAssertFalse(ReaderIdentity(name: "   ").isMe("anything at all"))
    }

    /// It round-trips as JSON, because that is how the app stores it.
    func testIdentityRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(ReaderIdentity.self, from: data)
        XCTAssertEqual(decoded, identity)
    }
}
