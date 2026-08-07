import Foundation

/// What has already been said, so nothing is said twice.
///
/// ⚠️ **This is the piece a background-delivered app cannot do without.** The
/// trigger pass is pure and stateless — it re-derives every finding from the
/// data each time it runs — so with the app foregrounded once a day that is
/// harmless, and with `BGTaskScheduler` waking it every couple of hours it
/// would send the same flag a dozen times before lunch. The ledger is what
/// makes a *stateless* trigger pass safe to run on a *stateful* schedule.
///
/// Keyed by `HealthNotification.id`, which is the kind plus the fingerprint of
/// the finding — never a timestamp, never a UUID. That is the whole contract:
/// two evaluations of the same underlying fact must produce the same id.
public struct NotificationLedger: Codable, Sendable, Equatable {

    public struct Delivery: Codable, Sendable, Equatable {
        public let id: String
        public let kind: HealthNotificationKind
        public let at: Date

        public init(id: String, kind: HealthNotificationKind, at: Date) {
            self.id = id
            self.kind = kind
            self.at = at
        }
    }

    /// Newest last.
    public private(set) var deliveries: [Delivery]

    /// How long a delivery is remembered.
    ///
    /// Longer than any kind's `minimumInterval`, so the cooldowns are never
    /// silently shortened by pruning, and long enough that a seasonal finding
    /// — a lipid panel lapsing, a scan interval — cannot repeat inside one
    /// window. It is a few hundred bytes; there is no reason to be clever.
    public static let retention: TimeInterval = 120 * 86_400

    public init(deliveries: [Delivery] = []) {
        self.deliveries = deliveries
    }

    public func hasDelivered(_ id: String) -> Bool {
        deliveries.contains { $0.id == id }
    }

    public func hasDelivered(_ notification: HealthNotification) -> Bool {
        hasDelivered(notification.id)
    }

    public func lastDelivery(of kind: HealthNotificationKind) -> Date? {
        deliveries.last { $0.kind == kind }?.at
    }

    /// How many landed on the same local day as `date`.
    public func count(onDayOf date: Date, calendar: Calendar = .current) -> Int {
        deliveries.filter { calendar.isDate($0.at, inSameDayAs: date) }.count
    }

    public mutating func record(_ notification: HealthNotification, at date: Date) {
        deliveries.append(Delivery(id: notification.id, kind: notification.kind, at: date))
    }

    /// Drop anything older than `retention` before `now`.
    public mutating func pruned(asOf now: Date) {
        let floor = now.addingTimeInterval(-Self.retention)
        deliveries.removeAll { $0.at < floor }
    }
}
