import XCTest
import SwiftUI
import InsightKit
@testable import HealthInsights

/// **Does the model-accuracy screen draw — including the states nobody has data
/// for?** Backlog P24.
///
/// The states this screen spends most of its life in are the *empty* ones: a
/// fresh install has no graded prediction and never will have one for eighteen
/// of the twenty cards. Those paths are the feature, so they are the ones most
/// worth proving render — a screen whose "not enough yet" branch traps is a
/// screen that only ever works for the reader who least needs it.
///
/// Same instrument and the same caveat as `CardRenderSmokeTests`: `ImageRenderer`
/// evaluates the view tree without a window, so this catches a trap or a blank
/// where nothing else in this repo can. It says nothing about whether what it
/// drew is *right*; `use-the-simulator` still applies for that.
@MainActor
final class ModelAccuracyRenderTests: XCTestCase {

    private static let canvas = CGSize(width: 393, height: 3000)

    private func render(_ view: some View, _ what: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(content:
            view.frame(width: Self.canvas.width, height: Self.canvas.height))
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage, "\(what) produced no image.", file: file, line: line)
    }

    private func cohort() -> Cohort {
        Cohort(sex: "male", ageBand: "30-39", ethnicity: "white_or_other", region: "low")
    }

    private func report(pairCount: Int) -> CalibrationReport {
        let outcomes = (0..<pairCount).map { index in
            PredictionOutcome(
                insightID: .bloodPressure, metric: .bloodPressureSystolic,
                predicted: 124 + Double(index % 3), actual: 120 + Double(index % 5),
                modelVersion: InsightID.bloodPressure.modelVersion, cohort: cohort(),
                recordedAt: Date(timeIntervalSince1970: 1_767_225_600 + Double(index) * 4 * 86_400))
        }
        return ModelAccuracy.reports(from: outcomes)[0]
    }

    // MARK: The screen

    func testTheScreenRendersOnAFreshInstall() {
        let model = TestAppModel.make()
        render(NavigationStack { ModelAccuracyView() }.environment(model),
               "Model accuracy on a fresh install")
    }

    /// **The store-to-ledger path**, which is what the screen's `.task` actually
    /// does — a `PredictionOutcome` written by `logBloodPressure` has to come
    /// back out of SwiftData and land in the right group.
    ///
    /// ⚠️ **Not written as a render test on a seeded model**, deliberately.
    /// `TestAppModel.seeded()` kills the test host on this machine — so does the
    /// pre-existing `AppModelStateTests.testSeedingProducesSamplesAndResults`,
    /// run alone, which is how that was established as nothing to do with this
    /// screen. Seeding writes no `PredictionOutcome` anyway, so a seeded render
    /// would have drawn the same empty screen as the test above while importing
    /// somebody else's crash into this file.
    func testStoredOutcomesComeBackOutAndLandInTheMeasuredGroup() {
        let model = TestAppModel.make()
        for index in 0..<6 {
            model.dataStore.addPredictionOutcome(PredictionOutcome(
                insightID: .bloodPressure, metric: .bloodPressureSystolic,
                predicted: 126, actual: 121 + Double(index % 3),
                modelVersion: InsightID.bloodPressure.modelVersion, cohort: cohort(),
                recordedAt: Date(timeIntervalSince1970: 1_767_225_600 + Double(index) * 86_400)))
        }
        let entries = ModelAccuracy.ledger(outcomes: model.dataStore.loadPredictionOutcomes(),
                                           verdicts: [])
        let bp = entries.first { $0.insightID == .bloodPressure }
        XCTAssertEqual(bp?.evidence, .externalTruth)
        XCTAssertEqual(bp?.gradedPairs, 6)
        XCTAssertEqual(entries.first?.insightID, .bloodPressure, "Measured cards sort first.")
        // And the report it produces renders.
        guard let report = bp?.reports.first else { return XCTFail("no report") }
        render(NavigationStack {
            ModelAccuracyReportView(title: "Blood pressure", report: report)
        }.environment(model), "A report built from the real store")
    }

    // MARK: The report, at every count that changes what it may say

    /// One pair, five, eight and twelve — the counts either side of each
    /// threshold. A withheld figure has to draw its gate sentence, and a gate
    /// sentence that traps is worse than no screen at all.
    func testTheReportRendersAtEveryThresholdBoundary() {
        let model = TestAppModel.make()
        for n in [1, 4, 5, 7, 8, 9, 10, 12] {
            render(NavigationStack {
                ModelAccuracyReportView(title: "Blood pressure", report: report(pairCount: n))
            }.environment(model), "Calibration report at n = \(n)")
        }
    }

    /// The worked example is what a reader with nothing yet is shown, so it has
    /// to render on a model that has nothing.
    func testTheWorkedExampleRenders() {
        let model = TestAppModel.make()
        render(NavigationStack {
            ModelAccuracyReportView(title: "A worked example",
                                    report: ModelAccuracy.workedExample(),
                                    isWorkedExample: true)
        }.environment(model), "The worked example")
    }

    /// The chart alone, since it is the one part with a `Chart` in it and the
    /// one most able to trap on a degenerate domain — a single pair gives it a
    /// zero-width date span.
    func testTheChartRendersOnASinglePair() {
        let model = TestAppModel.make()
        render(PredictionVersusActualChart(report: report(pairCount: 1))
            .environment(model), "Prediction-versus-actual chart with one pair")
    }
}
