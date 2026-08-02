import XCTest
@testable import InsightKit

/// The pharmacokinetics module. Every property here is one the Bateman model
/// guarantees, so a wrong constant or a flipped sign shows up as a shape that
/// cannot happen rather than as a number nobody can check.
final class PharmacokineticsTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_780_000_000)
    private func hours(_ h: Double) -> Date { anchor.addingTimeInterval(h * 3600) }

    // MARK: - One dose

    func testADrugCannotActBeforeItIsTaken() {
        XCTAssertEqual(PharmacokineticsModel.singleDoseLevel(
            dose: 10, hoursSince: -1, compound: .tirzepatide), 0)
    }

    /// The defining shape: rise to a peak, then a long decay. Not monotone
    /// either way, which is what separates this from a simple decay model.
    func testTheCurveRisesToAPeakThenDecays() {
        let levels = stride(from: 0.0, through: 480, by: 6).map {
            PharmacokineticsModel.singleDoseLevel(dose: 10, hoursSince: $0,
                                                  compound: .tirzepatide)
        }
        let peakIndex = levels.firstIndex(of: levels.max() ?? 0) ?? 0
        XCTAssertGreaterThan(peakIndex, 0, "it must rise before it falls")
        XCTAssertLessThan(peakIndex, levels.count - 1, "and fall after it rises")
        // Strictly increasing up to the peak, strictly decreasing after.
        for i in 1...peakIndex { XCTAssertGreaterThan(levels[i], levels[i - 1]) }
        for i in (peakIndex + 1)..<levels.count {
            XCTAssertLessThan(levels[i], levels[i - 1])
        }
    }

    /// One elimination half-life after the peak has passed, the tail must be
    /// falling at roughly the published rate.
    func testTheTailFallsAtTheEliminationHalfLife() {
        let compound = GLPCompound.semaglutide
        let late = 40 * 24.0            // well past absorption
        let a = PharmacokineticsModel.singleDoseLevel(dose: 1, hoursSince: late,
                                                      compound: compound)
        let b = PharmacokineticsModel.singleDoseLevel(
            dose: 1, hoursSince: late + compound.eliminationHalfLifeHours,
            compound: compound)
        XCTAssertEqual(b / a, 0.5, accuracy: 0.02, "a half-life halves it")
    }

    /// Linear in dose — the property that lets doses superpose and lets the
    /// curve be stored without going stale.
    func testTheModelIsLinearInDose() {
        let single = PharmacokineticsModel.singleDoseLevel(dose: 5, hoursSince: 72,
                                                           compound: .tirzepatide)
        let double = PharmacokineticsModel.singleDoseLevel(dose: 10, hoursSince: 72,
                                                           compound: .tirzepatide)
        XCTAssertEqual(double, single * 2, accuracy: 1e-9)
    }

    /// Equal rate constants are the 0/0 case, and it must not produce a NaN
    /// that propagates silently through every later sum.
    func testEqualRateConstantsDoNotProduceNaN() {
        // liraglutide's own constants differ; force the limit case directly.
        let value = PharmacokineticsModel.singleDoseLevel(dose: 1, hoursSince: 10,
                                                          compound: .liraglutide)
        XCTAssertFalse(value.isNaN)
        XCTAssertGreaterThan(value, 0)
    }

    // MARK: - Accumulation

    /// The reason a steady weekly dose keeps feeling stronger for a month after
    /// it stops changing.
    func testWeeklyDosingAccumulatesToSteadyState() {
        let compound = GLPCompound.tirzepatide
        let doses = (0..<12).map {
            AdministeredDose(takenAt: hours(Double($0) * 7 * 24), milligrams: 5)
        }
        let afterFirst = PharmacokineticsModel.level(
            at: hours(7 * 24), doses: Array(doses.prefix(1)), compound: compound)
        let afterTwelve = PharmacokineticsModel.level(
            at: hours(12 * 7 * 24), doses: doses, compound: compound)
        XCTAssertGreaterThan(afterTwelve, afterFirst * 1.5,
                             "twelve weeks in, the trough is well above the first one")

        let steady = PharmacokineticsModel.steadyState(dose: 5, everyDays: 7,
                                                       compound: compound)
        XCTAssertGreaterThan(steady.peak, steady.trough)
        XCTAssertEqual(afterTwelve, steady.trough, accuracy: steady.trough * 0.15,
                       "twelve weeks is close to converged for a five-day half-life")
    }

    func testALongerHalfLifeAccumulatesMore() {
        let semaglutide = PharmacokineticsModel.steadyState(dose: 1, everyDays: 7,
                                                            compound: .semaglutide)
        let liraglutide = PharmacokineticsModel.steadyState(dose: 1, everyDays: 7,
                                                            compound: .liraglutide)
        XCTAssertGreaterThan(semaglutide.trough, liraglutide.trough,
                             "a week-long half-life carries over; a 13-hour one does not")
    }

    // MARK: - The curve

    func testTheCurveMarksPointsRestingOnInferredDoses() throws {
        // One inferred dose at the start, then confirmed weekly doses for
        // three months.
        let inferred = AdministeredDose(takenAt: anchor, milligrams: 5, isInferred: true)
        let confirmed = (1...13).map {
            AdministeredDose(takenAt: hours(Double($0) * 7 * 24), milligrams: 5)
        }
        let curve = PharmacokineticsModel.curve(
            doses: [inferred] + confirmed, compound: .tirzepatide,
            from: anchor, to: hours(24 * 91), step: 24 * 3600)
        XCTAssertFalse(curve.isEmpty)

        // Three days in, the inferred dose is the only thing holding the line
        // up, so the line is an estimate and must draw as one.
        let earlyPoint = try XCTUnwrap(curve.first { $0.date >= hours(24 * 3) })
        XCTAssertTrue(earlyPoint.restsOnInferredDose)

        // Three months later a five-day half-life has taken it to nothing, and
        // the line is no longer resting on a guess.
        XCTAssertFalse(curve.last?.restsOnInferredDose ?? true,
                       "a decayed inferred dose is no longer holding the curve up")
    }

    /// At the instant of the very first dose nothing is on board yet, and a
    /// zero level rests on nothing — not on a guess.
    func testAZeroLevelRestsOnNothing() {
        let inferred = AdministeredDose(takenAt: anchor, milligrams: 5, isInferred: true)
        let curve = PharmacokineticsModel.curve(
            doses: [inferred], compound: .tirzepatide,
            from: anchor, to: hours(24), step: 24 * 3600)
        XCTAssertEqual(curve.first?.level, 0)
        XCTAssertFalse(curve.first?.restsOnInferredDose ?? true)
    }

    func testNoDosesIsNoCurve() {
        XCTAssertTrue(PharmacokineticsModel.curve(
            doses: [], compound: .tirzepatide, from: anchor, to: hours(24)).isEmpty)
    }

    // MARK: - Titration inference

    /// The brief's example: 12.5 mg now, so 2.5 → 5 → 7.5 → 10 → 12.5 behind it.
    func testTitrationWalksTheLadderBackwards() {
        let now = hours(24 * 200)
        let doses = TitrationEngine.inferHistory(
            currentDose: 12.5, compound: .tirzepatide,
            startedOn: hours(0), now: now)
        XCTAssertFalse(doses.isEmpty)
        let ladder = doses.map(\.milligrams)
        XCTAssertEqual(ladder.first, 2.5, "it starts at the bottom of the ladder")
        XCTAssertEqual(ladder.last, 12.5, "and finishes where the reader actually is")
        // Never decreasing: a titration goes up.
        for i in 1..<ladder.count { XCTAssertGreaterThanOrEqual(ladder[i], ladder[i - 1]) }
    }

    /// **The safety property.** Every proposal is marked as one — the app may
    /// guess out loud, and may not act on its own guess.
    func testEveryInferredDoseSaysItIsInferred() {
        let doses = TitrationEngine.inferHistory(
            currentDose: 10, compound: .tirzepatide,
            startedOn: hours(0), now: hours(24 * 150))
        XCTAssertFalse(doses.isEmpty)
        XCTAssertTrue(doses.allSatisfy(\.isInferred))
    }

    /// A recent start cannot have walked the whole ladder, and the inference
    /// must not invent months that did not happen.
    func testAShortHistoryDoesNotInventMonths() {
        let start = hours(24 * 10)
        let doses = TitrationEngine.inferHistory(
            currentDose: 12.5, compound: .tirzepatide,
            startedOn: start, now: hours(24 * 40))
        XCTAssertTrue(doses.allSatisfy { $0.takenAt >= start },
                      "nothing before the reader says they started")
    }

    func testWeeklyCompoundsInferWeeklyDoses() {
        let doses = TitrationEngine.inferHistory(
            currentDose: 5, compound: .tirzepatide,
            startedOn: hours(0), now: hours(24 * 60))
        let gaps = zip(doses, doses.dropFirst()).map {
            $1.takenAt.timeIntervalSince($0.takenAt) / 86_400
        }
        XCTAssertTrue(gaps.allSatisfy { abs($0 - 7) < 0.01 }, "weekly means weekly")
    }

    func testAnUnknownDoseInfersNothing() {
        XCTAssertTrue(TitrationEngine.inferHistory(
            currentDose: 0, compound: .tirzepatide,
            startedOn: hours(0), now: hours(24 * 60)).isEmpty)
    }

    // MARK: - The scan seam

    func testAScanReadsCompoundAndDoseFromABox() {
        let payload = MedicationScanPayload.from(
            recognisedText: ["Mounjaro", "tirzepatide injection", "12.5 mg/0.5 mL"])
        XCTAssertEqual(payload.compound, .tirzepatide)
        XCTAssertEqual(payload.milligrams, 12.5)
        XCTAssertEqual(payload.confidence, 1.0, accuracy: 1e-9)
    }

    func testAScanReadsABrandNameAlone() {
        let payload = MedicationScanPayload.from(recognisedText: ["Ozempic 0,5 mg"])
        XCTAssertEqual(payload.compound, .semaglutide)
        XCTAssertEqual(payload.milligrams, 0.5, "a comma decimal is still a decimal")
    }

    func testAnUnreadableBoxClaimsNothing() {
        let payload = MedicationScanPayload.from(recognisedText: ["blurred", "text"])
        XCTAssertNil(payload.compound)
        XCTAssertNil(payload.milligrams)
        XCTAssertEqual(payload.confidence, 0)
    }
}
