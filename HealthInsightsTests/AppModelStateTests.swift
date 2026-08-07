import XCTest
import InsightKit
@testable import HealthInsights

/// **`AppModel`'s state transitions — the ones with a rule written on them.**
///
/// `AppModel` is ~3,000 lines of the app target and every screen reads it. Its
/// doc comments record a dozen defects that were fixed by hand and left with no
/// test behind them: caches that must be dropped when their inputs change,
/// stored-and-observed properties that used to be computed off the store, a
/// launch flag that must be one-way, an import that must be idempotent. Each
/// test below names the rule it holds.
///
/// Everything runs against `DataStore(inMemory: true)`, so no test can see
/// another's writes or the simulator's real database.
@MainActor
final class AppModelStateTests: XCTestCase {

    // MARK: - The substance log

    /// Log, move, delete — and the observed array following each time.
    ///
    /// The rule under test is the one written on `substanceEvents`: it is a
    /// *stored* property refreshed by every mutator, not a computed read of the
    /// store. `data-conventions.md` calls the computed form "the observation
    /// trap": a view reading only a computed property establishes no dependency
    /// on any `@Observable` stored property, so it keeps showing stale counts
    /// until something unrelated redraws it.
    func testSubstanceLogRoundTrips() {
        let model = TestAppModel.make()
        XCTAssertTrue(model.substanceEvents.isEmpty)

        let when = Date(timeIntervalSince1970: 1_750_000_000)
        model.logSubstance(.caffeine, at: when, units: 1)
        XCTAssertEqual(model.substanceEvents.count, 1)
        guard let logged = model.substanceEvents.first else { return XCTFail("nothing logged") }
        XCTAssertEqual(logged.substance, .caffeine)

        let moved = when.addingTimeInterval(-3600)
        model.updateSubstanceEvent(id: logged.id, timestamp: moved)
        XCTAssertEqual(model.substanceEvents.first?.timestamp.timeIntervalSince1970 ?? .nan,
                       moved.timeIntervalSince1970, accuracy: 1,
                       "Moving an entry must be reflected in the observed array, not just the store.")

        model.deleteSubstanceEvent(id: logged.id)
        XCTAssertTrue(model.substanceEvents.isEmpty)
    }

    // MARK: - Suggestion dismissals

    /// Dismiss and restore, with the observed list following both ways.
    ///
    /// The "Improve your health" drawer is the reason the Insights tab gets
    /// opened, and a dismissal that does not survive into `suggestionDismissals`
    /// is a row that reappears on the next redraw.
    func testSuggestionDismissalIsStoredAndReversible() {
        let model = TestAppModel.make()
        XCTAssertTrue(model.suggestionDismissals.isEmpty)

        model.dismissSuggestion(id: "test-suggestion")
        XCTAssertEqual(model.suggestionDismissals.map(\.suggestionID), ["test-suggestion"])

        model.restoreSuggestion(id: "test-suggestion")
        XCTAssertTrue(model.suggestionDismissals.isEmpty,
                      "Restoring must clear the dismissal, or the row can never come back.")
    }

    // MARK: - The launch flag

    /// `isLaunching` is one-way, and it tracks onboarding at construction.
    ///
    /// The comment on it: *"Set once, here, and only ever cleared —
    /// `RootView.task` runs again when the app returns to the foreground, and a
    /// splash over a warm app would be a worse bug than the blank white screen
    /// this replaces."*
    ///
    /// ⚠️ `hasCompletedOnboarding` is `UserDefaults`, and the test host **is**
    /// the installed app — so its value here is whatever the simulator happens
    /// to hold, not something this test may assert. What is assertable without
    /// touching the reader's defaults is the relationship (`isLaunching`
    /// mirrors it at init) and the one-way rule.
    func testLaunchFlagMirrorsOnboardingAndOnlyEverClears() {
        let model = TestAppModel.make()
        XCTAssertEqual(model.isLaunching, model.hasCompletedOnboarding,
                       "The splash is raised for a returning reader and not for a first run.")
        model.finishLaunch()
        XCTAssertFalse(model.isLaunching)
        model.finishLaunch()
        XCTAssertFalse(model.isLaunching, "finishLaunch must be terminal, not a toggle.")
    }

    // MARK: - Screen time

    /// Screen-time precedence, through `AppModel` rather than through the pure
    /// rule InsightKit already tests.
    ///
    /// `ScreenTimePrecedence` is proved in InsightKit; what is unproved is that
    /// `AppModel.importScreenTime` → `DataStore.recordScreenTime` actually
    /// *applies* it, once, and reports honestly how many days it wrote. The
    /// return value is what an import sheet tells the reader, and the two rules
    /// below are the ones the reader can feel: **re-importing an old Week
    /// screenshot must not overwrite a day they later screenshotted precisely**,
    /// and **their own correction outranks the device's accounting.**
    func testScreenTimeImportAppliesPrecedenceOnce() {
        let model = TestAppModel.make()
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let recordedAt = Date(timeIntervalSince1970: 1_750_100_000)
        func stored() -> [ScreenTimeEntry] {
            model.screenTimeEntries().filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        }

        XCTAssertEqual(model.importScreenTime([
            ScreenTimeEntry(day: day, minutes: 123, provenance: .dayExact, recordedAt: recordedAt)
        ]), 1)
        XCTAssertEqual(stored().count, 1)

        // A Week screenshot imported afterwards. Newer, and still wrong to take.
        XCTAssertEqual(model.importScreenTime([
            ScreenTimeEntry(day: day, minutes: 999, provenance: .weekEstimate,
                            recordedAt: recordedAt.addingTimeInterval(3600))
        ]), 0, "A week-split estimate overwrote an exact day.")
        XCTAssertEqual(stored().first?.minutes, 123)

        // The reader correcting the app, after the fact.
        XCTAssertEqual(model.importScreenTime([
            ScreenTimeEntry(day: day, minutes: 200, provenance: .manual,
                            recordedAt: recordedAt.addingTimeInterval(7200))
        ]), 1, "A later manual correction must outrank the device's own accounting.")
        XCTAssertEqual(stored().count, 1, "A day must never end up stored twice.")
        XCTAssertEqual(stored().first?.minutes, 200)
    }

    // MARK: - Derived caches

    /// A new sample set drops every figure derived from the old one.
    ///
    /// `invalidateDerivedCaches()` is called from `samples.didSet` and lists
    /// nine caches, each one a screen's worth of derived numbers. The comment on
    /// the derived-series reset spells out the consequence of getting it wrong:
    /// figures "left describing data that no longer exists". `memoized` is the
    /// smallest observable proxy for the whole set — it is the render-time memo
    /// every detail screen goes through.
    func testSeedingNewDataDropsTheRenderMemo() async {
        let model = TestAppModel.make()
        var computations = 0
        let key = "cache-invalidation-probe"

        _ = model.memoized(key) { computations += 1; return 1 }
        _ = model.memoized(key) { computations += 1; return 1 }
        XCTAssertEqual(computations, 1, "The memo did not hold — every render would recompute.")

        model.seedSyntheticData(days: 30)
        await model.recomputeSettled()

        _ = model.memoized(key) { computations += 1; return 1 }
        XCTAssertEqual(computations, 2,
                       "A new sample set left a memoised figure describing data that no longer exists.")
    }

    /// Seeding produces samples, and the evaluation that follows produces cards.
    ///
    /// The wiring test the routing tests depend on: if this fails, their
    /// "nothing is dropped" assertions are passing over an empty set.
    func testSeedingProducesSamplesAndResults() async {
        let model = await TestAppModel.seeded(days: 60)
        XCTAssertFalse(model.samples.isEmpty, "Synthetic seeding produced no samples.")
        XCTAssertFalse(model.results.isEmpty, "A seeded model evaluated no cards.")
        XCTAssertTrue(model.results.contains { $0.primaryValue != nil },
                      "Not one card produced a number from a 60-day history.")
    }

    /// A metric's breakdown is served from the cache the second time.
    ///
    /// The comment on `breakdownCache`: building one "scans, de-duplicates and
    /// groups every sample of that metric", the Vitals list asks per row and the
    /// detail screens ask again on every redraw, and "recomputing was making
    /// large histories unusable". Equality of two consecutive answers is the
    /// most this can assert without reaching into private state — but a
    /// breakdown that changed between two reads of an unchanged sample set is a
    /// defect on its own.
    func testBreakdownIsStableAcrossReads() async {
        let model = await TestAppModel.seeded(days: 60)
        guard let metric = model.samples.first?.type else { return XCTFail("no samples") }
        XCTAssertEqual(model.breakdown(metric), model.breakdown(metric))
    }
}
