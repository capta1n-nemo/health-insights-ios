import Foundation
import SwiftData
import XCTest
import InsightKit
@testable import HealthInsights

/// The delete-everything wipe (`Q13`), and the constraint that is the whole
/// point of it (`AC4`): **it must be derived from the `Schema`, never from a
/// hand-written list.**
///
/// The failure this guards against is not a crash and not a wrong number on a
/// screen. It is a `@Model` added six months from now, not added to the wipe,
/// and a reader who was told their health data was deleted while it sat on the
/// phone. Nothing about that is visible from the outside — which is exactly why
/// it needs a test rather than care.
@MainActor
final class DeleteEverythingTests: XCTestCase {

    /// The load-bearing one. If someone replaces the derived loop with a list of
    /// `try context.delete(model: …)` lines, the two arrays stop being the same
    /// array and this is what notices.
    ///
    /// It is deliberately *not* a count — "there are 19" would be a second place
    /// to update, which is the mistake being tested for. It asserts the
    /// **identity** of the two lists instead.
    func testTheWipeCoversExactlyTheSchemaItIsBuiltFrom() throws {
        let store = DataStore(inMemory: true)
        let schemaEntities = Set(store.container.schema.entities.map(\.name))
        let wiped = Set(DataStore.persistedModels.map { String(describing: $0) })

        XCTAssertEqual(wiped, schemaEntities,
                       "The wipe iterates `persistedModels`; the container is built from "
                       + "`Schema(persistedModels)`. If these differ, one of them has been "
                       + "restated rather than derived — and the missing side is health "
                       + "data that either never persists or never gets deleted.")
    }

    /// Every persisted type appears in the report, including the empty ones.
    ///
    /// Silence about a type is the shape of the defect: a wipe that only reports
    /// what it found cannot be distinguished from a wipe that never looked.
    func testEveryPersistedTypeIsAccountedForInTheReport() {
        let store = DataStore(inMemory: true)
        let report = store.deleteEverything()
        for model in DataStore.persistedModels {
            XCTAssertNotNil(report.rowsByType[String(describing: model)],
                            "\(model) is persisted but absent from the deletion report.")
        }
        XCTAssertEqual(report.typesCleared, DataStore.persistedModels.count)
        XCTAssertTrue(report.failures.isEmpty, "Wipe reported failures: \(report.failures)")
    }

    /// Records actually go, across several unrelated `@Model` types — including
    /// three of the four the backlog names as having landed *after* the
    /// delete-everything path was agreed.
    func testRecordsAcrossUnrelatedModelsAreActuallyDeleted() throws {
        let store = DataStore(inMemory: true)

        store.saveGrounding(kind: .totalCholesterol, value: 4.8)
        store.logSideEffect(name: "nausea", severity: 2, at: Date())
        store.setCycleDay(Date(), flow: .medium)
        store.logHoliday(firstDay: Date(), lastDay: Date(), label: "Manila")
        store.recordScore(.readiness, score: 0.7, confidence: .moderate, contributorCount: 3)

        let before = store.deleteEverything()
        XCTAssertGreaterThan(before.totalRows, 0, "Nothing was there to delete — the fixture "
                             + "is wrong and this test proves nothing.")

        XCTAssertTrue(store.loadSideEffects().isEmpty)
        XCTAssertTrue(store.loadCycleDays().isEmpty)
        XCTAssertTrue(store.loadHolidayEntries().isEmpty)
        XCTAssertTrue(store.scoreHistory(for: .readiness).isEmpty)

        // And it is idempotent: a second wipe finds nothing rather than throwing.
        let after = store.deleteEverything()
        XCTAssertEqual(after.totalRows, 0)
        XCTAssertTrue(after.failures.isEmpty)
    }

    /// The app around the store empties too. Without this, a reader who deleted
    /// everything keeps looking at all of it until they force-quit — the most
    /// visible possible way of not having deleted it.
    func testTheAppIsEmptiedAndNotJustTheDisk() async {
        let model = await TestAppModel.seeded(days: 30)
        XCTAssertFalse(model.samples.isEmpty, "Fixture produced no samples.")

        model.deleteEverything()

        XCTAssertTrue(model.samples.isEmpty)
        XCTAssertTrue(model.otherSamples.isEmpty)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.todaySummary.isEmpty)
    }

    /// An in-memory store must never sweep Application Support: the test bundle
    /// is hosted *in the installed app*, so that directory belongs to whoever is
    /// running the tests. This is the guard that stops a green test run deleting
    /// the reader's imported lab reports.
    func testAnInMemoryStoreTouchesNoFiles() {
        let report = DataStore(inMemory: true).deleteEverything()
        XCTAssertEqual(report.filesRemoved, 0)
    }

    /// The receipt is for the reader, so the type names are turned into words.
    func testTypeNamesAreRenderedForAReaderRatherThanACompiler() {
        XCTAssertEqual(DeleteEverythingView.readable("SideEffectRecord"), "Side effect")
        XCTAssertEqual(DeleteEverythingView.readable("CalendarJudgementRecord"),
                       "Calendar judgement")
        XCTAssertEqual(DeleteEverythingView.readable("HolidayEntry"), "Holiday")
        // A type that is only its suffix keeps its name rather than becoming "".
        XCTAssertEqual(DeleteEverythingView.readable("Record"), "Record")
    }
}
