import Foundation

/// Which part of the launch refresh is running right now.
///
/// `AppModel.isSyncing` was always the gate, but it is one flag over two very
/// different waits — a provider round-trip over the network, and an on-device
/// FoundationModels pass — and those are exactly the two steps the launch copy
/// wants to tell apart. Ordered, because the narration clamps against it.
public enum LaunchPhase: Int, Comparable, CaseIterable, Sendable {
    /// Talking to Apple Health and the connected wearables. Network-bound, and
    /// the one that can genuinely take several seconds.
    case connecting
    /// Ingesting payloads, merging caches and running the insight engine. Local
    /// CPU — usually fast, occasionally not on a big history.
    case reading
    /// The on-device model writing the Today summary.
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
    /// wait. Chosen at the bottom of the 6–8 s the brief gave, because by then
    /// the script has run its length twice over and repeating it is what makes a
    /// slow launch feel stuck.
    public static let reassuranceAfter: TimeInterval = 7

    /// The reassurance lines hold nearly three times as long. They are there to
    /// say "still working", and saying it briskly says the opposite.
    ///
    /// They *do* still rotate: the brief ruled out "a slower rotation of the
    /// same ones", which is a rule about the sentences, not about movement. A
    /// twenty-second launch staring at one frozen line reads as a hang, which is
    /// the failure this whole screen exists to prevent.
    public static let reassuranceDwell: TimeInterval = 3.5

    /// The launch screen stays up at least this long once shown.
    ///
    /// A warm launch — everything cached, nothing to fetch — can finish in a
    /// couple of hundred milliseconds, and a splash that appears and dissolves
    /// inside a quarter of a second is a flicker. Worse than not showing one.
    public static let minimumOnScreen: TimeInterval = 0.9

    /// The splash comes down at this point whatever the phase says.
    ///
    /// A launch screen that never leaves is the worst thing this file can ship,
    /// and it only takes one refresh path that forgets to reach `.ready`. Today
    /// is safe to reveal at any moment — `AppModel` hydrates from cache in its
    /// initialiser, so the tabs hold real data before the sync starts.
    public static let hardCeiling: TimeInterval = 20

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
        Line(text: "Checking in with your health apps", phase: .connecting),
        Line(text: "Herding cats",                      phase: .connecting),
        Line(text: "Extracting the latest data",        phase: .connecting),

        Line(text: "Reading your last few weeks",       phase: .reading),
        Line(text: "Consulting the archives",           phase: .reading),
        Line(text: "Comparing today with your usual",   phase: .reading),

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

    public init() {}

    /// The line to show at `elapsed` seconds into the launch.
    ///
    /// Call it as often as you like — it is idempotent between moves, so a 10 Hz
    /// timer and a 60 Hz one produce the same sequence.
    public mutating func line(at elapsed: TimeInterval, phase: LaunchPhase) -> String {
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
    static func step(from index: Int, phase: LaunchPhase) -> Int {
        let window = window(for: phase)
        return min(max(index + 1, window.lowerBound), window.upperBound)
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
    /// Separate from the copy because it answers a different question, and
    /// because both of its floors are the kind that get dropped in a refactor:
    /// the minimum keeps a warm launch from flickering, the ceiling keeps a
    /// stalled refresh from trapping the user on a splash.
    public static func shouldDismiss(elapsed: TimeInterval, phase: LaunchPhase) -> Bool {
        guard elapsed >= minimumOnScreen else { return false }
        return phase == .ready || elapsed >= hardCeiling
    }
}
