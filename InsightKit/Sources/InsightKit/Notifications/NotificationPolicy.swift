import Foundation

/// The restraint, in one value.
///
/// Everything that decides *whether the reader is interrupted* lives here
/// rather than being spread across the triggers, so the answer to "why did I
/// get that?" is one struct and one ledger, and so the settings screen has
/// exactly one thing to write to.
///
/// **The defaults are the argument.** Three a day is a ceiling nobody should
/// reach — the triggers are already deduplicated by finding, so hitting three
/// means three genuinely different things happened — and it exists to bound the
/// worst day rather than to shape the ordinary one. Quiet hours are 22:00 to
/// 07:00 because the whole reason this work was sequenced background-first is
/// that *a radar flag at 3am reaches nobody*: the flag being computable at 3am
/// is the point, and it being **delivered** at 3am is not.
public struct NotificationPolicy: Codable, Sendable, Equatable {

    /// Kinds the reader has left on.
    public var enabledKinds: Set<HealthNotificationKind>
    /// Local hour at which quiet hours begin, 0…23.
    public var quietHoursStart: Int
    /// Local hour at which they end, 0…23. May be less than `start` — the
    /// interesting case wraps midnight, and every other spelling of this has
    /// got that wrong.
    public var quietHoursEnd: Int
    /// Most notifications in one local day. Zero disables delivery entirely
    /// without the reader having to untick seven rows.
    public var dailyCap: Int

    public static let defaultDailyCap = 3
    public static let defaultQuietHoursStart = 22
    public static let defaultQuietHoursEnd = 7

    public init(enabledKinds: Set<HealthNotificationKind>,
                quietHoursStart: Int = defaultQuietHoursStart,
                quietHoursEnd: Int = defaultQuietHoursEnd,
                dailyCap: Int = defaultDailyCap) {
        self.enabledKinds = enabledKinds
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.dailyCap = dailyCap
    }

    /// What a reader who has never opened the settings screen gets.
    public static var standard: NotificationPolicy {
        NotificationPolicy(
            enabledKinds: Set(HealthNotificationKind.allCases.filter(\.isOnByDefault)))
    }

    /// Nothing at all — what an unauthorised or opted-out reader is evaluated
    /// against, so the trigger pass still runs and still records nothing.
    public static var silent: NotificationPolicy {
        NotificationPolicy(enabledKinds: [], dailyCap: 0)
    }

    public func allows(_ kind: HealthNotificationKind) -> Bool {
        dailyCap > 0 && enabledKinds.contains(kind)
    }

    public func enabling(_ kind: HealthNotificationKind, _ on: Bool) -> NotificationPolicy {
        var copy = self
        if on { copy.enabledKinds.insert(kind) } else { copy.enabledKinds.remove(kind) }
        return copy
    }

    /// Whether `date` falls inside the quiet window.
    ///
    /// The wrap-around case is the normal one — 22:00 to 07:00 is two intervals
    /// on a clock face and one interval in the reader's head — so it is written
    /// as the general form rather than as a special case bolted on. Equal start
    /// and end means *no* quiet hours, not twenty-four of them: a reader who
    /// drags both ends to the same hour has expressed "don't hold anything
    /// back", and the opposite reading would silence the app forever.
    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        let start = ((quietHoursStart % 24) + 24) % 24
        let end = ((quietHoursEnd % 24) + 24) % 24
        guard start != end else { return false }
        let hour = calendar.component(.hour, from: date)
        return start < end ? (hour >= start && hour < end)
                           : (hour >= start || hour < end)
    }

    /// The next instant delivery is permitted, at or after `date`.
    ///
    /// Used to *hold* rather than to drop: a finding made at 03:00 is still
    /// true at 07:00, and the alternative — dropping it — is how a symptom flag
    /// computed overnight would reach nobody, which is the exact failure this
    /// whole row exists to fix.
    public func nextAllowedMoment(onOrAfter date: Date,
                                  calendar: Calendar = .current) -> Date {
        guard isQuiet(at: date, calendar: calendar) else { return date }
        let end = ((quietHoursEnd % 24) + 24) % 24
        // The next occurrence of the end hour, exactly on the hour.
        if let next = calendar.nextDate(after: date,
                                        matching: DateComponents(hour: end, minute: 0),
                                        matchingPolicy: .nextTime) {
            return next
        }
        // A calendar that cannot answer is not a reason to lose the finding.
        return date.addingTimeInterval(3600)
    }
}
