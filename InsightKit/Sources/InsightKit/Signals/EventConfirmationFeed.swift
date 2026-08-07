import Foundation

/// **The guess, the reader's answer, and the gap between them — kept apart.**
///
/// A copy of `CalendarEventJudgement`'s discipline, on purpose. The reader's
/// correction is stored separately from the app's guess and is never merged into
/// it, because merged they are indistinguishable the next time anything runs:
/// the app could never say how often it was right, and re-detection would
/// silently overwrite the reader.
///
/// Three layers, again for `CalendarEventJudgement`'s stated reason. Guess and
/// correction alone make a tally; `artifact` — the event as it stood when the
/// guess was made — is what turns a count into a training pair.
public struct FlaggedEventJudgement: Sendable, Equatable, Codable, Identifiable {

    public let eventID: String

    /// What the app offered, untouched by any answer. Optional because a
    /// detector with no candidates at all is a legitimate state, and recording
    /// "it had nothing to say" is different from recording a wrong guess.
    public let guess: EventCause?

    /// What the reader said, where they said anything.
    public let correction: EventCause?

    /// Their own words, kept beside `correction` rather than instead of it.
    ///
    /// ⚠️ **Stays on the phone.** See
    /// `HealthDataExport.exportKey(for: .flaggedEvents)` — free text about what
    /// somebody was doing during a flagged half-hour is the most sensitive
    /// string this app can hold, and unlike a holiday label it frequently
    /// describes other people.
    public let note: String?

    /// The event as it was when the guess was made.
    public let artifact: FlaggedEventArtifact?

    /// **The reader looked at it and agreed.** Different from an absent
    /// correction: "confirmed" is a label and "not yet looked at" is not, and
    /// treating them alike would inflate any accuracy figure.
    public let isConfirmed: Bool

    public let reviewedAt: Date?

    /// When the event was first seen to have changed after the reader had
    /// already answered — re-detection moving a window's edges. Surfaced, never
    /// resolved, exactly as `CalendarEventJudgement.changedAfterReviewAt` is:
    /// re-detection refreshes the snapshot, so the comparison that found the
    /// drift goes quiet a line later, and the reader's answer would then look
    /// current when it was about a window that no longer exists.
    public let changedAfterReviewAt: Date?

    public var id: String { eventID }

    /// What the rest of the app should use.
    public var effective: EventCause? { correction ?? guess }

    /// Whether the reader has said anything at all.
    public var isReviewed: Bool { isConfirmed || correction != nil }

    /// Whether the reader disagreed — the training signal.
    ///
    /// A correction that happens to match the guess is **not** a disagreement:
    /// the reader tapping the same option the app offered is a confirmation
    /// wearing a different hat, and counting it as a miss would understate the
    /// app by exactly the number of readers who prefer buttons to checkmarks.
    public var wasCorrected: Bool {
        guard let correction else { return false }
        return correction != guess
    }

    /// Whether the reader answered about a version of this event that no longer
    /// exists.
    public var needsRereview: Bool {
        changedAfterReviewAt != nil && isReviewed
    }

    public init(eventID: String, guess: EventCause?,
                correction: EventCause? = nil, note: String? = nil,
                artifact: FlaggedEventArtifact? = nil,
                isConfirmed: Bool = false, reviewedAt: Date? = nil,
                changedAfterReviewAt: Date? = nil) {
        self.eventID = eventID
        self.guess = guess
        self.correction = correction
        self.note = note
        self.artifact = artifact
        self.isConfirmed = isConfirmed
        self.reviewedAt = reviewedAt
        self.changedAfterReviewAt = changedAfterReviewAt
    }

    /// A fresh, unanswered judgement for an event nobody has looked at.
    public init(pending event: FlaggedEvent) {
        self.init(eventID: event.id, guess: event.guess,
                  artifact: FlaggedEventArtifact(event))
    }

    /// **Re-detection, as an invariant rather than a habit.**
    ///
    /// Running the detector again replaces the guess and the snapshot and leaves
    /// everything the reader said exactly where it is. The artifact moves *with*
    /// the guess, never with the correction: the pair (what was measured, what
    /// was concluded) has to stay self-consistent or the training example is a
    /// fiction.
    ///
    /// ⚠️ **`changedAfterReviewAt` survives**, and that is the point of storing
    /// it rather than deriving it — this call is what refreshes the snapshot, so
    /// the drift comparison stops reporting a line later.
    public func redetected(as event: FlaggedEvent) -> FlaggedEventJudgement {
        FlaggedEventJudgement(eventID: eventID, guess: event.guess,
                              correction: correction, note: note,
                              artifact: FlaggedEventArtifact(event),
                              isConfirmed: isConfirmed, reviewedAt: reviewedAt,
                              changedAfterReviewAt: changedAfterReviewAt)
    }

    /// Note that the event moved under a reader who had already answered.
    /// Idempotent and earliest-wins — the instant worth keeping is when their
    /// answer first went stale, not when a later pass happened to notice.
    public func markedChangedAfterReview(at date: Date) -> FlaggedEventJudgement {
        guard reviewedAt != nil, changedAfterReviewAt == nil else { return self }
        return FlaggedEventJudgement(eventID: eventID, guess: guess,
                                     correction: correction, note: note,
                                     artifact: artifact, isConfirmed: isConfirmed,
                                     reviewedAt: reviewedAt,
                                     changedAfterReviewAt: date)
    }

    /// The reader's answer, recorded against the guess already stored.
    ///
    /// ⚠️ **The snapshot is deliberately not refreshed here.** The app offered a
    /// guess about a particular window; re-reading it at answer time would
    /// attribute evidence to the guess that it may never have had.
    ///
    /// ⚠️ **It clears `changedAfterReviewAt`**, and only this does — the reader
    /// is looking at the event as it stands now.
    public func reviewed(correction: EventCause?, note: String? = nil,
                         confirmed: Bool, at date: Date) -> FlaggedEventJudgement {
        FlaggedEventJudgement(eventID: eventID, guess: guess,
                              correction: correction,
                              note: note?.isEmpty == true ? nil : note,
                              artifact: artifact, isConfirmed: confirmed,
                              reviewedAt: date, changedAfterReviewAt: nil)
    }
}

/// **How the app is doing at this, from the reader's own answers.**
///
/// The figure the loop exists to move, computable only because corrections are
/// kept apart from guesses.
public struct FlaggedEventAccuracy: Sendable, Equatable {

    /// Reviews below which no figure is offered. The same refusal
    /// `CalendarClassifierAccuracy` and `CycleSummary.lengthRange` make, and the
    /// reader singled the calendar's version out approvingly: *"It needs 10
    /// before that figure means anything."*
    public static let minimumReviewed = 10

    /// Answered events where a guess was on offer. The denominator.
    public let scored: Int
    /// Of those, the ones the reader agreed with.
    public let agreed: Int
    /// Answered events where the app had **no** guess to be right or wrong
    /// about. Reported separately rather than folded in: counting a silence as a
    /// miss would punish the detector for being honest, and counting it as a hit
    /// would be absurd.
    public let answeredWithoutAGuess: Int

    /// Nil until enough has been answered to mean anything.
    public var rate: Double? {
        scored >= Self.minimumReviewed ? Double(agreed) / Double(scored) : nil
    }

    /// What the feed shows where the figure would go. Nil once there is a rate.
    public var gate: CoverageGate? {
        CoverageGate.ifShort(need: Self.minimumReviewed, have: scored,
                             unit: "answered event",
                             unlocks: "the app can tell you how often its guesses are right")
    }

    public static func measure(_ judgements: [FlaggedEventJudgement]) -> FlaggedEventAccuracy {
        let reviewed = judgements.filter(\.isReviewed)
        let scorable = reviewed.filter { $0.guess != nil }
        return FlaggedEventAccuracy(
            scored: scorable.count,
            agreed: scorable.filter { !$0.wasCorrected }.count,
            answeredWithoutAGuess: reviewed.count - scorable.count)
    }

    public init(scored: Int, agreed: Int, answeredWithoutAGuess: Int) {
        self.scored = scored
        self.agreed = agreed
        self.answeredWithoutAGuess = answeredWithoutAGuess
    }

    /// The sentence the feed prints. Never a bare percentage: a rate over
    /// eleven answers is a different claim from one over four hundred, and the
    /// denominator travels with it.
    public var sentence: String {
        if let rate {
            return String(format: "The app's first guess has been right %.0f%% of the time, over %d answered events.",
                          rate * 100, scored)
        }
        return gate?.sentence ?? "Nothing answered yet."
    }
}

// MARK: - The feed

/// **What the reader sees: unanswered questions first, answered ones behind.**
///
/// Assembly only — it joins freshly detected events to the answers already
/// stored and decides what each one is now. Detection is
/// `FlaggedEventDetector`'s job and answering is the view's; this is the piece
/// that has to get the *joining* right, which is where a learning loop usually
/// breaks.
public struct EventConfirmationFeed: Sendable, Equatable {

    /// Flagged, unanswered, newest first. The queue.
    public let pending: [FlaggedEvent]
    /// Answered, newest first, paired with what the reader said.
    public let answered: [Answered]
    /// Answers that were given about a window which has since moved. Surfaced so
    /// the reader is told rather than overruled.
    public let needingRereview: [Answered]
    public let accuracy: FlaggedEventAccuracy
    /// What the feed is waiting for when it is empty — history depth, then
    /// permission, then simply nothing having happened.
    public let gate: CoverageGate?

    public struct Answered: Sendable, Equatable, Identifiable {
        public let event: FlaggedEvent
        public let judgement: FlaggedEventJudgement
        public var id: String { event.id }

        public init(event: FlaggedEvent, judgement: FlaggedEventJudgement) {
            self.event = event
            self.judgement = judgement
        }
    }

    public init(pending: [FlaggedEvent], answered: [Answered],
                needingRereview: [Answered], accuracy: FlaggedEventAccuracy,
                gate: CoverageGate?) {
        self.pending = pending
        self.answered = answered
        self.needingRereview = needingRereview
        self.accuracy = accuracy
        self.gate = gate
    }

    /// Join detected events to stored answers.
    ///
    /// ⚠️ **Answered events whose window is gone are kept.** An event that no
    /// longer detects — a threshold moved, a sample was deleted — still had a
    /// reader's answer attached, and dropping it would quietly shrink the
    /// accuracy denominator every time the detector changed. `heldJudgements`
    /// carries them, without an event to render, and they still count.
    public static func assemble(events: [FlaggedEvent],
                                judgements: [FlaggedEventJudgement],
                                historyGate: CoverageGate?,
                                now: Date = Date()) -> EventConfirmationFeed {
        var stored = Dictionary(judgements.map { ($0.eventID, $0) }) { a, _ in a }
        var pending: [FlaggedEvent] = []
        var answered: [Answered] = []
        var stale: [Answered] = []

        for event in events.sorted(by: { $0.start > $1.start }) {
            guard var judgement = stored[event.id] else {
                pending.append(event)
                continue
            }
            // Drift is checked against the *stored* snapshot, before
            // re-detection overwrites it — the one ordering that makes the
            // comparison possible at all.
            if judgement.artifact?.differs(from: event) == true {
                judgement = judgement.markedChangedAfterReview(at: now)
            }
            judgement = judgement.redetected(as: event)
            stored[event.id] = judgement

            if judgement.isReviewed {
                let row = Answered(event: event, judgement: judgement)
                if judgement.needsRereview { stale.append(row) } else { answered.append(row) }
            } else {
                pending.append(event)
            }
        }

        // Every stored answer counts toward accuracy, including ones whose event
        // has stopped being detected.
        let accuracy = FlaggedEventAccuracy.measure(Array(stored.values))
        return EventConfirmationFeed(
            pending: pending,
            answered: answered,
            needingRereview: stale,
            accuracy: accuracy,
            gate: historyGate)
    }

    /// What the feed says when there is nothing in it. **Never blank** — rule 7:
    /// an empty surface has to say what it is waiting for.
    public func emptyMessage(access: LocationAccess) -> String {
        if let gate, let sentence = gate.sentence {
            return sentence
        }
        var out = "Nothing unusual to ask about. The app is watching your heart rate against your own typical levels and will ask when something doesn't fit."
        if let permission = access.sentence { out += " " + permission }
        return out
    }
}

/// **When a coordinate is deleted, and why there is a deadline at all.**
///
/// `PlaceContext` allows a coordinate to exist for exactly one job — letting the
/// reader look at a map and remember what they were doing. A question nobody has
/// answered in a fortnight is a question that will not be answered, so the
/// coordinate has stopped doing the job and the justification for holding it has
/// expired.
///
/// ⚠️ **Time-based, not count-based.** An earlier draft kept the coordinate for
/// the newest N pending events, which sounds equivalent and is not: a reader who
/// stops opening the app would have kept twenty coordinates indefinitely, and
/// the person least likely to answer is exactly the person whose data should
/// decay fastest.
public enum FlaggedEventRetention {

    /// How long an unanswered event may keep its position.
    public static let coordinateLifetimeDays = 14

    /// How long an unanswered event stays in the feed at all before it is
    /// dropped. Longer than the coordinate's life on purpose: the *measurement*
    /// is ordinary health data with an ordinary lifetime, and only the position
    /// carries the risk that justifies the shorter clock.
    public static let questionLifetimeDays = 60

    /// Strip positions from anything past its deadline, and from anything the
    /// reader has already answered.
    ///
    /// Idempotent, and safe to run on every launch — which is how it is wired,
    /// because a retention rule that runs only when somebody remembers is not a
    /// retention rule.
    public static func sweep(events: [FlaggedEvent],
                             answeredIDs: Set<String>,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> [FlaggedEvent] {
        let expiry = calendar.date(byAdding: .day, value: -coordinateLifetimeDays, to: now)
            ?? .distantPast
        let floor = calendar.date(byAdding: .day, value: -questionLifetimeDays, to: now)
            ?? .distantPast
        return events
            .filter { $0.start >= floor }
            .map { event in
                if answeredIDs.contains(event.id) || event.start < expiry {
                    return event.forgettingCoordinate()
                }
                return event
            }
    }
}
