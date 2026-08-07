import Foundation

/// Turns a pile of true findings into the small number of them worth
/// interrupting somebody for.
///
/// Pure and value-in/value-out, like every model in this package: the same
/// candidates, policy, ledger and clock always produce the same decision, which
/// is what lets the restraint be tested rather than believed. The app layer
/// does nothing but hand this its inputs and post what comes back.
///
/// ⚠️ **A held notification is not a dropped one.** During quiet hours the
/// decision carries a `deliverAt` in the future, and the caller schedules
/// rather than posts. Dropping instead would mean a flag raised at 03:00 —
/// precisely the case the background work was sequenced first for — reaching
/// nobody, which is the failure being fixed and not a form of restraint.
public enum NotificationScheduler {

    /// Why a candidate did not go out. Kept rather than discarded because
    /// "nothing was sent and I do not know why" is the state this app's
    /// diagnostics exist to prevent.
    public enum Suppression: String, Sendable, Equatable {
        /// The reader has this kind switched off, or the cap is zero.
        case disabled
        /// The same finding has already been delivered.
        case alreadySent
        /// Another of this kind went out inside its minimum interval.
        case tooSoonForKind
        /// The day's cap was already spent on higher-ranked findings.
        case dailyCapReached
    }

    public struct Held: Sendable, Equatable {
        public let notification: HealthNotification
        public let reason: Suppression
    }

    public struct Scheduled: Sendable, Equatable {
        public let notification: HealthNotification
        /// When it should reach the reader. `now` outside quiet hours, the end
        /// of the quiet window inside them.
        public let deliverAt: Date
    }

    public struct Decision: Sendable, Equatable {
        public let scheduled: [Scheduled]
        public let suppressed: [Held]

        public var isEmpty: Bool { scheduled.isEmpty }
    }

    /// Decide, and report what was left behind.
    ///
    /// The order of the gates is deliberate and each one is cheaper and more
    /// definite than the next: **off** beats **already said**, which beats
    /// **said too recently**, which beats **too many today**. Only the last is
    /// competitive — it depends on what else is in the batch — so it runs last,
    /// over a list already sorted by `kind.rank`. That is what makes the cap
    /// spend itself on the symptom flag rather than on the body-scan reminder
    /// that happened to be generated first.
    ///
    /// ⚠️ **The cap counts what has *already* been delivered today too**, from
    /// the ledger, not just what is in this batch. A background pass every two
    /// hours would otherwise get a fresh allowance of three each time it woke.
    public static func decide(candidates: [HealthNotification],
                              policy: NotificationPolicy,
                              ledger: NotificationLedger,
                              now: Date,
                              calendar: Calendar = .current) -> Decision {
        var scheduled: [Scheduled] = []
        var suppressed: [Held] = []

        let deliverAt = policy.nextAllowedMoment(onOrAfter: now, calendar: calendar)
        // The cap is spent against the day the reader will actually hear it —
        // a finding held overnight lands tomorrow and should be counted there.
        var spent = ledger.count(onDayOf: deliverAt, calendar: calendar)
        // A kind's cooldown has to see the decisions made earlier in this same
        // batch, or two candidates of one kind both pass a check that only
        // consulted the stored past.
        var lastOfKind: [HealthNotificationKind: Date] = [:]

        for candidate in candidates.sorted(by: { $0.kind.rank < $1.kind.rank }) {
            guard policy.allows(candidate.kind) else {
                suppressed.append(Held(notification: candidate, reason: .disabled))
                continue
            }
            guard !ledger.hasDelivered(candidate) else {
                suppressed.append(Held(notification: candidate, reason: .alreadySent))
                continue
            }
            let previous = [ledger.lastDelivery(of: candidate.kind), lastOfKind[candidate.kind]]
                .compactMap { $0 }
                .max()
            if let previous,
               deliverAt.timeIntervalSince(previous) < candidate.kind.minimumInterval {
                suppressed.append(Held(notification: candidate, reason: .tooSoonForKind))
                continue
            }
            guard spent < policy.dailyCap else {
                suppressed.append(Held(notification: candidate, reason: .dailyCapReached))
                continue
            }
            scheduled.append(Scheduled(notification: candidate, deliverAt: deliverAt))
            spent += 1
            lastOfKind[candidate.kind] = deliverAt
        }

        return Decision(scheduled: scheduled, suppressed: suppressed)
    }
}
