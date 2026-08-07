import Foundation
import UserNotifications
import InsightKit

/// The only thing in this app that talks to `UNUserNotificationCenter`.
///
/// Everything about *whether* to interrupt somebody lives in InsightKit, where
/// it is pure and tested on Linux (`NotificationTriggers`,
/// `NotificationScheduler`). This type knows nothing about health: it asks for
/// permission, posts what it is handed, and reports what the system says back.
/// The split is what lets the restraint be a test rather than a claim.
@MainActor
@Observable
final class NotificationCentre: NSObject {

    static let shared = NotificationCentre()

    /// What iOS currently says. `notDetermined` until `refreshAuthorization()`
    /// has run once — deliberately not assumed, because a reader who denied
    /// permission six months ago and a reader who has never been asked need
    /// completely different words on the settings screen.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// `true` once the delegate is installed. Set-once, so a scene that
    /// re-runs its `task` cannot stack delegates.
    private var isConfigured = false

    private var centre: UNUserNotificationCenter { .current() }

    /// Install the foreground delegate. Idempotent.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        centre.delegate = self
    }

    func refreshAuthorization() async {
        authorization = await centre.notificationSettings().authorizationStatus
    }

    /// Ask, once. Returns what the reader chose.
    ///
    /// ⚠️ **Never called on launch.** A permission prompt on first open is the
    /// cheapest way to get a permanent no, and iOS gives an app exactly one
    /// chance to ask. It is asked for from the settings screen, next to the
    /// list of what would actually be sent — which is the only place the reader
    /// has enough information to answer.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        DiagnosticsLog.shared.info("Notifications",
                                   granted ? "Permission granted" : "Permission not granted")
        return granted
    }

    /// Post everything the scheduler decided to send.
    ///
    /// ⚠️ **A held notification is scheduled, not dropped.** `deliverAt` is in
    /// the future whenever the finding was made during quiet hours, and that is
    /// the entire reason the background work was sequenced ahead of this: a
    /// radar flag computed at 3am has to *survive* to breakfast. A time-interval
    /// trigger is what carries it there, and iOS delivers it whether or not the
    /// app is running when the moment arrives.
    func post(_ scheduled: [NotificationScheduler.Scheduled], now: Date = Date()) async {
        for item in scheduled {
            let content = UNMutableNotificationContent()
            content.title = item.notification.title
            content.body = item.notification.body
            content.threadIdentifier = item.notification.kind.threadIdentifier
            content.sound = .default
            content.userInfo = [
                Self.kindKey: item.notification.kind.rawValue,
                Self.insightKey: item.notification.insight?.rawValue ?? ""
            ]

            let delay = item.deliverAt.timeIntervalSince(now)
            // A `UNTimeIntervalNotificationTrigger` rejects a non-positive
            // interval, and `nil` means "as soon as this is added" — which is
            // what an already-due notification wants anyway.
            let trigger: UNNotificationTrigger? = delay > 1
                ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                : nil

            do {
                try await centre.add(UNNotificationRequest(
                    identifier: item.notification.id, content: content, trigger: trigger))
                DiagnosticsLog.shared.ok(
                    "Notifications",
                    delay > 1 ? "Held until quiet hours end: \(item.notification.kind.rawValue)"
                              : "Sent: \(item.notification.kind.rawValue)",
                    detail: item.notification.title)
            } catch {
                DiagnosticsLog.shared.fail("Notifications",
                                           "Could not post \(item.notification.kind.rawValue)",
                                           detail: error.localizedDescription)
            }
        }
    }

    static let kindKey = "healthNotificationKind"
    static let insightKey = "healthNotificationInsight"
}

extension NotificationCentre: UNUserNotificationCenterDelegate {

    /// Shown even with the app open.
    ///
    /// The reader could be three tabs away from the card that changed, and a
    /// finding that is worth a banner on the lock screen is worth one in the
    /// app. The alternative — suppressing in the foreground — is also how "my
    /// notifications don't work" gets reported by somebody who was testing it
    /// with the app open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
