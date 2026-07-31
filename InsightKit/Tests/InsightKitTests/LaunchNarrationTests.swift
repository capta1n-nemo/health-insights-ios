import XCTest
@testable import InsightKit

/// The launch copy has two failure modes and they pull in opposite directions:
/// paced by the phase alone it flashes three messages through a warm launch,
/// paced by the timer alone it announces work that has not started. Both are
/// invisible to a compiler and neither can be seen from the app target, which
/// has no test target — so they get pinned here.
final class LaunchNarrationTests: XCTestCase {

    /// Walk a launch at 20 Hz and record every line change with its timestamp.
    private func run(to end: TimeInterval,
                     step: TimeInterval = 0.05,
                     phase: @escaping (TimeInterval) -> LaunchPhase)
    -> [(at: TimeInterval, text: String)] {
        var narration = LaunchNarration()
        var changes: [(at: TimeInterval, text: String)] = []
        var last = ""
        var t: TimeInterval = 0
        while t <= end {
            let line = narration.line(at: t, phase: phase(t))
            if line != last {
                changes.append((t, line))
                last = line
            }
            t += step
        }
        return changes
    }

    // MARK: - The no-flash invariant

    /// The one the brief called out: a launch that finishes almost instantly
    /// must not strobe the whole script on its way out.
    func testNoLineIsReplacedBeforeItCanBeRead() {
        // Every shape of launch, including the pathological ones.
        let shapes: [(String, (TimeInterval) -> LaunchPhase)] = [
            ("instant", { _ in .summarising }),
            ("fast", { t in t < 0.2 ? .connecting : .summarising }),
            ("stepped", { t in t < 1.0 ? .connecting : (t < 2.0 ? .reading : .summarising) }),
            ("stalled", { _ in .connecting }),
            ("jumpy", { t in Int(t * 10) % 2 == 0 ? .connecting : .summarising })
        ]
        for (name, phase) in shapes {
            let changes = run(to: 12, phase: phase)
            for (a, b) in zip(changes, changes.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    b.at - a.at, LaunchNarration.dwell - 0.001,
                    "\(name): \"\(a.text)\" was replaced by \"\(b.text)\" after only \(b.at - a.at)s")
            }
        }
    }

    /// The concrete version of the same thing, stated the way the brief did.
    func testAFastLaunchDoesNotFlashThreeMessagesInHalfASecond() {
        let changes = run(to: 0.5, phase: { _ in .summarising })
        XCTAssertEqual(changes.count, 1, "Only the opening line should have been shown")
    }

    // MARK: - The phase clamps

    /// The opposite failure: narrating a step that has not begun. While the
    /// network is still out, nothing may claim to be generating insights.
    func testCopyNeverRunsAheadOfTheWork() {
        let connectingOnly = Set(
            LaunchNarration.script.filter { $0.phase == .connecting }.map(\.text))
        let shown = Set(run(to: LaunchNarration.reassuranceAfter - 0.1,
                            phase: { _ in .connecting }).map(\.text))
        XCTAssertFalse(shown.isEmpty)
        XCTAssertTrue(shown.isSubset(of: connectingOnly),
                      "Claimed \(shown.subtracting(connectingOnly)) while still connecting")
    }

    /// And the floor half of the same clamp: when the work has already raced
    /// ahead, the copy jumps to it rather than narrating a wait that is over.
    func testCopyIsPulledForwardWhenTheWorkOvertakesIt() {
        let changes = run(to: 2.0, phase: { _ in .summarising })
        XCTAssertEqual(changes.count, 2, "One opening line, one step")
        let summarising = LaunchNarration.script.filter { $0.phase == .summarising }.map(\.text)
        XCTAssertTrue(summarising.contains(changes[1].text),
                      "Second line was \"\(changes[1].text)\" — should have skipped to the real phase")
    }

    /// A phase that has been reached is not a phase that must be left. A slow
    /// network holds on its own last line rather than marching on.
    func testAStalledPhaseHoldsItsLastLine() {
        let changes = run(to: LaunchNarration.reassuranceAfter - 0.1, phase: { _ in .connecting })
        let connecting = LaunchNarration.script.filter { $0.phase == .connecting }
        XCTAssertEqual(changes.map(\.text), connecting.map(\.text),
                       "Should walk its own phase once and stop, not loop")
    }

    // MARK: - The long wait

    func testPastTheThresholdTheCopyChangesRegisterEntirely() {
        let scripted = Set(LaunchNarration.script.map(\.text))
        var narration = LaunchNarration()
        var t: TimeInterval = 0
        var line = ""
        while t <= 11 {
            line = narration.line(at: t, phase: .connecting)
            t += 0.05
        }
        XCTAssertFalse(scripted.contains(line),
                       "Still rotating the script at 11s — the brief wanted different sentences")
        XCTAssertTrue(LaunchNarration.reassurances.contains(line))
    }

    /// "A different sentence, not a slower rotation of the same ones" is a rule
    /// about the words. A twenty-second launch frozen on one line reads as the
    /// hang this screen exists to disprove, so they still move — just slowly.
    func testReassurancesRotateSlowlyRatherThanFreezing() {
        let changes = run(to: 20, phase: { _ in .connecting })
        let late = changes.filter { $0.at >= LaunchNarration.reassuranceAfter }
        XCTAssertGreaterThanOrEqual(late.count, 3, "The reassurance copy never moved")
        for (a, b) in zip(late, late.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.at - a.at, LaunchNarration.reassuranceDwell - 0.001)
        }
    }

    /// Once the wait has been acknowledged, dropping back into "Herding cats"
    /// would read as the launch having restarted.
    func testTheCopyNeverGoesBackToNarratingSteps() {
        let changes = run(to: 20, phase: { t in t < 9 ? .connecting : .reading })
        guard let firstLate = changes.firstIndex(where: {
            LaunchNarration.reassurances.contains($0.text)
        }) else { return XCTFail("Never reached the reassurance copy") }
        let after = changes[firstLate...].map(\.text)
        XCTAssertTrue(after.allSatisfy { LaunchNarration.reassurances.contains($0) },
                      "Went back to the script: \(after)")
    }

    // MARK: - Dismissal

    func testAWarmLaunchStillShowsTheScreenLongEnoughToNotFlicker() {
        XCTAssertFalse(LaunchNarration.shouldDismiss(elapsed: 0, hasContent: true))
        XCTAssertFalse(LaunchNarration.shouldDismiss(
            elapsed: LaunchNarration.minimumOnScreen - 0.01, hasContent: true))
        XCTAssertTrue(LaunchNarration.shouldDismiss(
            elapsed: LaunchNarration.minimumOnScreen, hasContent: true))
    }

    func testAStalledReadStillReleasesTheScreen() {
        XCTAssertFalse(LaunchNarration.shouldDismiss(
            elapsed: LaunchNarration.hardCeiling - 0.01, hasContent: false))
        XCTAssertTrue(LaunchNarration.shouldDismiss(
            elapsed: LaunchNarration.hardCeiling, hasContent: false),
            "A read that never completes would trap the user on the splash")
    }

    /// The regression this contract exists to prevent. The screen used to wait
    /// for the whole refresh — network sync, ingest and the on-device summary —
    /// which on a real history is about thirty seconds in front of an app that
    /// already had everything it needed to draw Today.
    func testTheScreenWaitsForContentAndNotForTheSyncToFinish() {
        // Cache read done at 1.2s; the network and the summariser are still going.
        XCTAssertTrue(LaunchNarration.shouldDismiss(elapsed: 1.2, hasContent: true),
                      "Today is drawable — the rest belongs behind it")
        // And it must not hang on for anything like the length of a real sync.
        XCTAssertLessThanOrEqual(LaunchNarration.hardCeiling, 8,
                                 "A ceiling this high stops being a safety net")
    }

    /// The reassurance state has to fit inside the screen's own lifetime.
    ///
    /// It did not, briefly: cutting the ceiling to match the new "wait for the
    /// cache read only" contract left the handover at 7 s and the release at
    /// 6 s, so the whole reassurance register was dead code that nothing would
    /// have caught. Two constants, no compiler relationship between them.
    func testTheReassuranceStateIsActuallyReachable() {
        XCTAssertLessThan(LaunchNarration.reassuranceAfter, LaunchNarration.hardCeiling,
                          "The screen releases before the reassurance copy could ever show")
        // And with room for at least one line to be read once it does.
        XCTAssertGreaterThanOrEqual(
            LaunchNarration.hardCeiling - LaunchNarration.reassuranceAfter, 1.0,
            "The reassurance line would flash and vanish")
        // Reached in practice, not just arithmetically.
        let late = run(to: LaunchNarration.hardCeiling, phase: { _ in .reading })
            .filter { LaunchNarration.reassurances.contains($0.text) }
        XCTAssertFalse(late.isEmpty, "A stalled read never reaches the reassurance copy")
    }

    // MARK: - Copy hygiene

    func testEverySentenceIsDistinctAndPresentable() {
        let all = LaunchNarration.script.map(\.text) + LaunchNarration.reassurances
        XCTAssertEqual(Set(all).count, all.count, "Duplicate line — the rotation would stutter")
        for text in all {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.hasSuffix("."), "\"\(text)\" — status lines don't take a full stop")
            XCTAssertLessThanOrEqual(text.count, 46, "\"\(text)\" will wrap on the narrowest device")
        }
    }

    /// The joke must never be the line a slow step parks on, which is what the
    /// last slot of each phase is.
    func testEveryPhaseHasCopyAndEndsOnSomethingFunctional() {
        for phase in LaunchPhase.allCases where phase != .ready {
            let lines = LaunchNarration.script.filter { $0.phase == phase }
            XCTAssertGreaterThanOrEqual(lines.count, 2, "\(phase) has nothing to say")
            let window = LaunchNarration.window(for: phase)
            XCTAssertEqual(LaunchNarration.script[window.upperBound].text, lines.last?.text)
        }
        // `.ready` borrows the final line rather than indexing past the end.
        let ready = LaunchNarration.window(for: .ready)
        XCTAssertEqual(ready.upperBound, LaunchNarration.script.count - 1)
    }
}
