import Foundation
import BackgroundTasks
import InsightKit

/// **Waking the app up when nobody is holding it.**
///
/// ⚠️ This is the half the reader sequenced first, and the reason they did:
/// before this file existed there was no `BGTaskScheduler`, no `BackgroundTasks`
/// import and no `UIBackgroundModes` anywhere in the repo, so *anything* built
/// on top would have fired only while the app was on screen. Their words:
/// **"a symptom-radar alert that only fires when you happen to open the app is
/// not the feature that was asked for."** A radar flag at 3am has to be
/// computed while the phone is in a drawer, or the notification layer above it
/// is decoration.
///
/// ## What this changes about signing, stated plainly
///
/// ⚠️ **Nothing.** `deploy.yml` runs on the reader's own Mac and a failed deploy
/// is either a signing refusal or an unreachable phone; guessing between them
/// has cost a session before, so this is worth being exact about:
///
/// - `Support/Info.plist` gains `UIBackgroundModes` (`fetch`, `processing`) and
///   `BGTaskSchedulerPermittedIdentifiers`. **Neither is an entitlement.**
///   `Info.plist` background modes are not codesigned capabilities and are not
///   checked against a provisioning profile; a wrong value here fails at
///   *runtime* (`BGTaskScheduler` refuses to register the identifier) and never
///   at `codesign`.
/// - `Support/HealthInsights.entitlements` is **untouched**. It still declares
///   `com.apple.developer.healthkit` and nothing else.
///
/// ## The one thing deliberately not built, and why
///
/// **HealthKit background delivery** (`HKHealthStore.enableBackgroundDelivery`)
/// is the other, stronger meaning of "background delivery": iOS wakes the app
/// the moment a new sample lands rather than on a schedule it chooses. It needs
/// the `com.apple.developer.healthkit.background-delivery` entitlement — and an
/// entitlement a provisioning profile does not carry is exactly the kind of
/// change that fails at **signing**, on the reader's Mac, after the push. This
/// build is signed by a free personal team, whose capability set is limited and
/// which nothing in this session can query. Adding it blind would have risked a
/// red deploy whose cause is genuinely ambiguous from the outside.
///
/// So it is left for a session that can watch the deploy: it is a strict
/// improvement in latency, it is a one-line call plus one entitlement key, and
/// it is the right next step — but it is an entitlement change and must be
/// treated as one.
enum BackgroundRefresh {

    /// ⚠️ **Must match `BGTaskSchedulerPermittedIdentifiers` in
    /// `Support/Info.plist` exactly.** A mismatch is not a compile error and
    /// not a signing error: `BGTaskScheduler` throws `notPermitted` at
    /// registration, the app carries on working perfectly, and nothing ever
    /// runs in the background again. `BackgroundRefreshTests` asserts the two
    /// agree, because this is a string in two files and there is no compiler
    /// between them.
    static let taskIdentifier = "com.jasonsalway.healthinsights.refresh"

    /// The soonest iOS is asked to consider running it.
    ///
    /// A floor, not a schedule — the system decides, weighing battery, network
    /// and how often the app is actually opened, and it will frequently ignore
    /// this by hours. Two is chosen against what the pass can *find*: the radar
    /// re-evaluates once a day, wearables sync a few times a day, and asking
    /// more often would spend battery to re-derive answers that cannot have
    /// changed.
    static let earliestInterval: TimeInterval = 2 * 3600

    /// Ask for the next wake-up.
    ///
    /// Called at launch, on backgrounding, and — importantly — at the *start*
    /// of every background run. Rescheduling first is the standard shape and
    /// the reason is unforgiving: if the work throws, or the system expires the
    /// task mid-flight, a reschedule at the end never happens and the app
    /// silently never wakes again.
    /// `@MainActor` because `DiagnosticsLog` is, and every caller already is:
    /// the scene's `task`, its `onChange`, and `run()` below. Submitting a
    /// request is a cheap call into a system daemon, not work worth hopping
    /// off the main actor for.
    @MainActor
    static func schedule(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = now.addingTimeInterval(earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            DiagnosticsLog.shared.info(
                "Background", "Next background refresh requested",
                detail: "Not before \(request.earliestBeginDate.map(String.init(describing:)) ?? "—"). "
                    + "iOS decides the actual moment.")
        } catch {
            // The simulator has no background scheduling at all and throws
            // every time, so this is `info` rather than `fail`: a red line in
            // the diagnostics that appears on every simulator launch teaches
            // the reader to ignore red lines.
            DiagnosticsLog.shared.info(
                "Background", "Background refresh could not be scheduled",
                detail: "\(error.localizedDescription)\n"
                    + "Expected on the simulator, which does not run BGTaskScheduler. "
                    + "On device this means Background App Refresh is off for this app, "
                    + "or the identifier is missing from Info.plist.")
        }
    }

    /// One background pass: sync, recompute, then decide what is worth saying.
    ///
    /// ⚠️ **The reschedule comes first**, before any work that could fail. See
    /// `schedule(now:)`.
    ///
    /// The budget is the reason `force: true` is passed to `refresh`.
    /// `RefreshGate` exists to stop three pull-to-refresh gestures paying for
    /// three syncs; a wake-up hours later is not that gesture, and letting the
    /// gate swallow it would mean the background pass evaluated stale data and
    /// then congratulated itself for finding nothing.
    @MainActor
    static func run() async {
        schedule()
        let started = Date()
        DiagnosticsLog.shared.info("Background", "Background refresh started")
        await AppModel.shared.refresh(force: true)
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        DiagnosticsLog.shared.info("Background", "Background refresh finished in \(elapsed)s")
    }
}
