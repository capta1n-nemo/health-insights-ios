import XCTest
@testable import InsightKit

/// The Data tab holds **158 distinct raw identifiers across 320,913 rows** on
/// the reader's own record, in one flat alphabetical list at the bottom of the
/// page. These pin the two things that make it navigable: a category derived
/// from the identifier, and a clock that can tell "new to me" from "backfilled".
final class DataTabSortingTests: XCTestCase {

    // MARK: - Grouping

    /// A sample of the reader's real identifiers, one per rule, so the rules
    /// are tested against what actually arrives rather than what is easy.
    private let realIdentifiers: [(String, RawFieldGrouping.Group)] = [
        ("HKQuantityTypeIdentifierDietaryCalcium", .nutrition),
        ("HKQuantityTypeIdentifierEnvironmentalAudioExposure", .hearing),
        ("HKCategoryTypeIdentifierAudioExposureEvent", .hearing),
        ("HKQuantityTypeIdentifierTimeInDaylight", .daylight),
        ("HKQuantityTypeIdentifierWalkingAsymmetryPercentage", .mobility),
        ("HKQuantityTypeIdentifierFlightsClimbed", .movement),
        ("HKQuantityTypeIdentifierBasalEnergyBurned", .movement),
        ("HKCategoryTypeIdentifierLowCardioFitnessEvent", .heartEvents),
        ("HKQuantityTypeIdentifierBasalBodyTemperature", .bodyMeasurements),
        ("HKQuantityTypeIdentifierWaterTemperature", .environment),
        ("oura.daily_activity.contributors.stay_active", .activityScore),
        ("oura.daily_cardiovascular_age.pulse_wave_velocity", .heartEvents),
        ("HKCategoryTypeIdentifierDizziness", .mind),
    ]

    func testEveryRuleLandsWhereItShould() {
        for (identifier, expected) in realIdentifiers {
            XCTAssertEqual(RawFieldGrouping.group(for: identifier), expected,
                           "\(identifier) landed in the wrong group")
        }
    }

    /// **The eleven Oura contributors were eleven top-level rows**, each
    /// rendering as "Daily activity · Contributors: …" and truncating before
    /// the word that told them apart. They are one score's workings.
    func testScoreComponentsAreRecognisedAsComponents() {
        XCTAssertTrue(RawFieldGrouping.isScoreComponent("oura.daily_activity.contributors.stay_active"))
        XCTAssertFalse(RawFieldGrouping.isScoreComponent("oura.daily_activity.steps"),
                       "a reading is not a component")
    }

    /// **The bucket measures the rules.** "Not yet sorted" is named for its own
    /// failure precisely so a long one gets fixed rather than tolerated, and
    /// this is the assertion that makes that automatic.
    func testTheUnsortedBucketStaysSmallOnRealIdentifiers() {
        let unsorted = realIdentifiers.filter {
            RawFieldGrouping.group(for: $0.0) == .unsorted
        }
        let share = Double(unsorted.count) / Double(realIdentifiers.count)
        XCTAssertLessThan(share, RawFieldGrouping.acceptableUnsortedShare,
                          "the prefix table has fallen behind: \(unsorted.map { $0.0 })")
    }

    func testUnsortedIsOrderedLastSoItIsVisibleRatherThanHidden() {
        XCTAssertEqual(RawFieldGrouping.Group.allCases.sorted().last, .unsorted)
    }

    // MARK: - The sighting ledger

    private let now = TestClock.now

    /// **The debut this feature must not have.** Every identifier a reader
    /// already holds would look brand new on the first launch after shipping —
    /// 158 "new data type" announcements for data they have had for years.
    func testSeededTypesAreNeverCalledNew() {
        var ledger = TypeSightingLedger()
        ledger.seed(["a", "b", "c"], at: now)
        XCTAssertTrue(ledger.newlyArrived(asOf: now).isEmpty)
        XCTAssertTrue(ledger.newlyArrived(asOf: now.addingTimeInterval(86_400)).isEmpty)
    }

    /// Seeding twice must not rewrite a genuine first sighting into a seeded
    /// one — a migration that runs again should be inert.
    func testSeedingIsIdempotentAndNeverOverwritesARealSighting() {
        var ledger = TypeSightingLedger()
        ledger.observe("real", at: now)
        ledger.seed(["real", "other"], at: now)
        XCTAssertEqual(ledger.newlyArrived(asOf: now), ["real"],
                       "seeding overwrote a genuine first sighting")
    }

    /// The backfill problem, stated directly: a type whose *data* is two years
    /// old is still new if the app only just met it.
    func testANewTypeIsNewEvenWhenItsDataIsOld() {
        var ledger = TypeSightingLedger()
        ledger.seed(["existing"], at: now.addingTimeInterval(-400 * 86_400))
        ledger.observe("justConnected", at: now)
        XCTAssertEqual(ledger.newlyArrived(asOf: now), ["justConnected"])
    }

    func testNewnessExpires() {
        var ledger = TypeSightingLedger()
        ledger.observe("x", at: now)
        let later = now.addingTimeInterval(TypeSightingLedger.newWithin + 86_400)
        XCTAssertTrue(ledger.newlyArrived(asOf: later).isEmpty)
    }

    /// ⚠️ **The qualifier is the whole feature.** Without it this says "your
    /// ring data is deprecated" the week the reader leaves the ring on charge.
    func testAQuietTypeIsOnlyStaleWhenItsSourceIsStillAlive() {
        var ledger = TypeSightingLedger()
        ledger.observe("oura.sleep.deep", at: now.addingTimeInterval(-90 * 86_400))
        ledger.observe("oura.sleep.rem", at: now)

        // Oura is clearly still delivering, so the quiet field is worth naming.
        XCTAssertEqual(ledger.stoppedArriving(asOf: now, activeSourcePrefixes: ["oura."]),
                       ["oura.sleep.deep"])

        // The ring has been off entirely — say nothing. That is a connection
        // problem and the connection screen owns it.
        XCTAssertTrue(ledger.stoppedArriving(asOf: now, activeSourcePrefixes: []).isEmpty)
    }

    func testARecentTypeIsNeverStale() {
        var ledger = TypeSightingLedger()
        ledger.observe("oura.sleep.deep", at: now.addingTimeInterval(-5 * 86_400))
        XCTAssertTrue(ledger.stoppedArriving(asOf: now, activeSourcePrefixes: ["oura."]).isEmpty)
    }

    /// The ledger persists, so it must survive a round trip.
    func testItRoundTrips() throws {
        var ledger = TypeSightingLedger()
        ledger.seed(["a"], at: now)
        ledger.observe("b", at: now)
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(TypeSightingLedger.self, from: data), ledger)
    }

    /// The caller of `stoppedArriving` needs a set of live sources, and getting
    /// it from anywhere else lets the two halves disagree about what "recently"
    /// means. Derived from the ledger, so they cannot.
    func testActivePrefixesComeFromTheLedgerItself() {
        var ledger = TypeSightingLedger()
        ledger.observe("oura.sleep.rem", at: now)
        ledger.observe("withings.weight", at: now.addingTimeInterval(-200 * 86_400))
        ledger.observe("HKQuantityTypeIdentifierStepCount", at: now)

        let live = ledger.activePrefixes(asOf: now)
        XCTAssertTrue(live.contains("oura."))
        XCTAssertTrue(live.contains("HKQuantityTypeIdentifier"),
                      "a HealthKit type has no dot and must not become its own prefix")
        XCTAssertFalse(live.contains("withings."),
                       "a source silent for 200 days was called alive")
    }

    /// ⚠️ **One quiet HealthKit type does not mean HealthKit went away.** The
    /// prefix has to be the type class, or every silent field would be its own
    /// living source and could never be reported as stale.
    func testAHealthKitTypeGroupsUnderItsClassAndNotUnderItself() {
        XCTAssertEqual(TypeSightingLedger.prefix(of: "HKQuantityTypeIdentifierStepCount"),
                       "HKQuantityTypeIdentifier")
        XCTAssertEqual(TypeSightingLedger.prefix(of: "oura.daily_sleep.score"), "oura.")
    }
}
