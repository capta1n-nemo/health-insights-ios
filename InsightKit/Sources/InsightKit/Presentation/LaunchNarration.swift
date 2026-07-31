import Foundation

/// Which part of the launch is running right now, in the order it happens.
///
/// `AppModel.isSyncing` was always the gate, but it is one flag over waits that
/// feel nothing alike — reading a large cache off disk, a provider round-trip
/// over the network, and an on-device FoundationModels pass. Ordered, because
/// the narration clamps against it.
///
/// The order matters and was wrong in the first version: it put `.connecting`
/// first, on the assumption that a launch starts by talking to the network. It
/// does not. It starts by reading the cache — which on a large history is the
/// single most expensive thing that happens — and only then syncs.
public enum LaunchPhase: Int, Comparable, CaseIterable, Sendable {
    /// Decoding the cached samples off disk and running the insight engine over
    /// them. Local CPU, and on a six-figure sample count the longest step here.
    /// **This is the only phase the launch screen waits for** — see
    /// `shouldDismiss`.
    case reading
    /// Talking to Apple Health and the connected wearables. Happens *behind*
    /// Today, not in front of it.
    case connecting
    /// The on-device model writing the Today summary. Also behind Today.
    case summarising
    /// Nothing left to wait for.
    case ready

    public static func < (a: LaunchPhase, b: LaunchPhase) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// The rotating status line under the launch screen's pulse.
///
/// Lives in InsightKit rather than in the view for the reason `OverlaySelection`
/// does: it is presentation logic that can be *wrong*, and the app target has no
/// test target. The two ways it can be wrong are opposites, and both are real:
///
/// - **Driven by phase alone**, a warm launch flashes three messages in half a
///   second and reads as a glitch.
/// - **Driven by the timer alone**, it cheerfully claims "Generating insights"
///   while the network request it depends on has not come back yet.
///
/// So neither drives it on its own: **the timer paces, the phase clamps.** One
/// line every `dwell` seconds, never a line whose phase the launch has not
/// reached, and — the invariant the tests actually pin — *nothing* replaces a
/// line before it has been on screen long enough to read, including a phase
/// jump and including the switch into the reassurance copy.
public struct LaunchNarration: Sendable {

    // MARK: - Timings

    /// How long each line holds. 1.25 s sits in the middle of the 1–1.5 s the
    /// brief asked for, and is comfortably above the ~0.4 s it takes to read six
    /// words.
    public static let dwell: TimeInterval = 1.25

    /// Past this, the copy stops narrating steps and starts acknowledging the
    /// wait, because by then the script has run its length and repeating it is
    /// what makes a slow launch feel stuck.
    ///
    /// The brief said 6–8 s, and this was 7 s while the screen also waited for
    /// the whole sync. Now that it waits only for the cache read and releases at
    /// `hardCeiling`, 7 s was past the end of the screen's own life — the
    /// reassurance state existed but could never be reached.
    /// `testTheReassuranceStateIsActuallyReachable` pins the relationship so the
    /// next person to move either number finds out immediately.
    public static let reassuranceAfter: TimeInterval = 4

    /// The reassurance lines hold far longer than the script's. They are there
    /// to say "still working", and saying it briskly says the opposite.
    ///
    /// They *do* still rotate: the brief ruled out "a slower rotation of the
    /// same ones", which is a rule about the sentences, not about movement. A
    /// twenty-second launch staring at one frozen line reads as a hang, which is
    /// the failure this whole screen exists to prevent.
    public static let reassuranceDwell: TimeInterval = 3

    /// The launch screen stays up at least this long once shown.
    ///
    /// A warm launch — everything cached, nothing to fetch — can finish in a
    /// couple of hundred milliseconds, and a splash that appears and dissolves
    /// inside a quarter of a second is a flicker. Worse than not showing one.
    public static let minimumOnScreen: TimeInterval = 0.9

    /// The splash comes down at this point whatever else is happening.
    ///
    /// A launch screen that never leaves is the worst thing this file can ship.
    /// Cut from 20 s to 8 s along with the fix below: once the screen only ever
    /// waits for the local cache read, twenty seconds is not a safety net, it is
    /// a licence to hang. Today is safe to reveal at any moment — an empty tab
    /// that fills in a second later beats a splash that will not leave.
    ///
    /// **The timer enforcing this must not run on the main actor.** The first
    /// version polled it from a `MainActor` loop, which is starved by exactly
    /// the main-thread work it exists to protect against — so the one launch
    /// that needed the ceiling was the one launch that could not fire it. See
    /// `LaunchScreen.narrate()`.
    public static let hardCeiling: TimeInterval = 8

    // MARK: - Copy

    public struct Line: Sendable, Equatable {
        public let text: String
        /// The phase during which this line is true. Never shown before it.
        public let phase: LaunchPhase
    }

    /// Three lines per phase, functional either side of a light one.
    ///
    /// The order is deliberate: the *last* line of a phase is the one that sits
    /// there while a slow step runs long, so it is never the joke. A launch
    /// stuck for four seconds on "Herding cats" is funny once and worrying
    /// after that.
    public static let script: [Line] = [
        Line(text: "Reading your last few weeks",       phase: .reading),
        Line(text: "Consulting the archives",           phase: .reading),
        Line(text: "Comparing today with your usual",   phase: .reading),

        Line(text: "Checking in with your health apps", phase: .connecting),
        Line(text: "Herding cats",                      phase: .connecting),
        Line(text: "Extracting the latest data",        phase: .connecting),

        Line(text: "Generating insights",               phase: .summarising),
        Line(text: "Choosing the right words",          phase: .summarising),
        Line(text: "Putting it into sentences",         phase: .summarising)
    ]

    /// Shown past `reassuranceAfter`. Different sentences, not the script again
    /// — they acknowledge the wait rather than narrate a step, because by then
    /// the step names have stopped being news.
    public static let reassurances: [String] = [
        "Still going — that's a lot of history to read",
        "Almost there, thanks for waiting",
        "Taking longer than usual. Nothing is lost"
    ]

    // MARK: - State

    private enum Cursor: Equatable {
        case script(Int)
        case reassurance(Int)
    }

    private var cursor: Cursor = .script(0)
    /// When the line now on screen went up. Everything holds off this.
    private var shownAt: TimeInterval = 0
    /// Whether a line has been chosen yet. The *first* one has no dwell to
    /// respect — nothing is on screen for it to cut short — so it goes straight
    /// to the phase the launch is actually in rather than always opening on the
    /// first line of the script and correcting a beat later.
    private var started = false

    public init() {}

    /// The line to show at `elapsed` seconds into the launch.
    ///
    /// Call it as often as you like — it is idempotent between moves, so a 10 Hz
    /// timer and a 60 Hz one produce the same sequence.
    public mutating func line(at elapsed: TimeInterval, phase: LaunchPhase) -> String {
        if !started {
            started = true
            cursor = .script(Self.window(for: phase).lowerBound)
            shownAt = elapsed
            return text(of: cursor)
        }

        let hold: TimeInterval
        if case .reassurance = cursor { hold = Self.reassuranceDwell } else { hold = Self.dwell }

        // The whole no-flash guarantee is this one guard. Nothing below it can
        // replace a line early: not a phase that jumped three steps, not the
        // handover into the reassurance copy.
        guard elapsed - shownAt >= hold else { return text(of: cursor) }

        let next = nextCursor(at: elapsed, phase: phase)
        if next != cursor {
            cursor = next
            shownAt = elapsed
        }
        return text(of: cursor)
    }

    private func nextCursor(at elapsed: TimeInterval, phase: LaunchPhase) -> Cursor {
        if elapsed >= Self.reassuranceAfter {
            // Reassurance is terminal within a launch — once the wait has been
            // acknowledged, going back to narrating steps would read as a restart.
            switch cursor {
            case .reassurance(let i): return .reassurance((i + 1) % Self.reassurances.count)
            case .script:             return .reassurance(0)
            }
        }
        guard case .script(let i) = cursor else { return cursor }
        return .script(Self.step(from: i, phase: phase))
    }

    /// One step forward, then pulled to the window the phase can honestly claim.
    ///
    /// The window is both a floor and a ceiling, and it needs to be both. The
    /// ceiling stops the copy running ahead of the work. The floor handles the
    /// opposite case — a launch so fast that the phase is already `.summarising`
    /// while the cursor is still on the first line — where advancing one step at
    /// a time would narrate a network wait that finished a second ago.
    /// Never backwards. A phase cannot un-happen in this app, but if one ever
    /// appeared to, holding the current line is the right answer — rewinding the
    /// copy would read as the launch having restarted.
    static func step(from index: Int, phase: LaunchPhase) -> Int {
        let window = window(for: phase)
        let target = min(max(index + 1, window.lowerBound), window.upperBound)
        return max(target, index)
    }

    static func window(for phase: LaunchPhase) -> ClosedRange<Int> {
        let last = script.count - 1
        // `.ready` has no copy of its own — the screen is on its way out.
        guard phase != .ready,
              let first = script.firstIndex(where: { $0.phase == phase }),
              let end = script.lastIndex(where: { $0.phase == phase })
        else { return last...last }
        return first...end
    }

    private func text(of cursor: Cursor) -> String {
        switch cursor {
        case .script(let i):      return Self.script[i].text
        case .reassurance(let i): return Self.reassurances[i]
        }
    }

    /// Whether the launch screen may come down yet.
    ///
    /// **`hasContent`, not "everything finished".** The first version waited for
    /// the whole refresh — network sync, payload ingest, insight pass and the
    /// on-device summary — before revealing Today. On a real phone with a real
    /// history that is around thirty seconds of staring at a splash, and it was
    /// a straight regression: before the launch screen existed, the tabs were on
    /// screen from the first frame and all of that work happened *behind* them,
    /// with a spinner on the Today card saying so.
    ///
    /// So the screen waits for one thing only: enough data to draw a real Today.
    /// Everything after that is a background refresh and belongs behind the app,
    /// exactly where it used to be.
    ///
    /// The floors either side both matter and both get dropped in a refactor:
    /// `minimumOnScreen` stops a warm launch flickering the splash in and out,
    /// `hardCeiling` stops a stalled read trapping the user.
    public static func shouldDismiss(elapsed: TimeInterval, hasContent: Bool) -> Bool {
        guard elapsed >= minimumOnScreen else { return false }
        return hasContent || elapsed >= hardCeiling
    }
}
