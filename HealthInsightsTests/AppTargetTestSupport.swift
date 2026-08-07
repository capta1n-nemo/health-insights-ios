import Foundation
import XCTest
import InsightKit
@testable import HealthInsights

// MARK: - Why this target exists, and where it can run
//
// **The app target had zero tests until 2026-08-07.** 28,573 lines — roughly
// 39% of the shipped Swift, and the 39% that holds every render site, every
// card-visibility gate and every state transition — were checked only by
// `swiftc -parse`, an `xcodebuild build`, and the reader opening the app.
// InsightKit's suite is large and green and cannot see any of it: it is a
// platform-free package that knows nothing about `AppModel`, the tabs, or
// SwiftUI.
//
// ⚠️ **This target is Mac-only, forever, and that is not a gap to be closed.**
// A unit-test bundle hosted in an iOS app needs the iOS SDK to compile and an
// iOS simulator to run. The hosted Linux sessions this repo is often driven
// from have neither, and `ci.yml` runs on GitHub's runners, which have neither
// either. So:
//
//   * `verify.sh --tests` runs it **only on Darwin**, beside the InsightKit
//     run, and says out loud when it is skipping it.
//   * **CI does not gate it.** Nobody should wonder why: there is no iOS SDK
//     on the runner to gate it with. The Mac gate is the gate.
//   * The scheme's BuildAction still lists only the app, so `xcodebuild build`
//     — what CI and `deploy.yml` run — does not compile this target at all.
//     A broken test file cannot stop a deploy reaching the phone.
//
// The corollary matters more than the caveat: **anything that can be proved in
// InsightKit belongs in InsightKit**, where Linux, CI and every session can run
// it. What belongs here is only what genuinely needs the app target — the view
// layer, `AppModel`, and the gates between them.

/// A fully wired `AppModel` that touches no real device and no real disk.
///
/// `DataStore(inMemory: true)` is the load-bearing part: the shipped
/// `AppModel.makeDefault()` opens the on-disk SwiftData store and registers six
/// live integrations, so two tests in a row would see each other's writes and a
/// test run would edit the simulator's real database.
///
/// The registry is deliberately empty rather than stubbed. Nothing under test
/// here syncs, and an empty registry is the honest description of "no provider
/// is connected" — which is also the state a fresh install is in, and the state
/// the visibility tests below care most about.
@MainActor
enum TestAppModel {
    static func make() -> AppModel {
        AppModel(dataStore: DataStore(inMemory: true),
                 healthService: HealthKitService(),
                 registry: IntegrationRegistry(integrations: []),
                 summarizer: FoundationModelSummarizer())
    }

    /// A model with a plausible history, evaluated and settled.
    ///
    /// `recomputeSettled()` rather than a sleep or an expectation:
    /// `recompute()` detaches the eighteen-model pass off the main actor
    /// (2026-08-06, the "syncing hangs the UI" report), so `results` is empty
    /// for a beat after `seedSyntheticData` returns. A test that read it
    /// straight away would be testing the race, and would pass or fail by
    /// machine load.
    static func seeded(days: Int = 90) async -> AppModel {
        let model = make()
        model.seedSyntheticData(days: days)
        await model.recomputeSettled()
        return model
    }

    /// What the app's own engine makes of a fresh install: no samples, no
    /// events, an empty profile.
    ///
    /// ⚠️ **Deliberately not `AppModel.hydrate()`.** Hydration reads the app
    /// container's on-disk sample cache, and the test host *is* the installed
    /// app — so on a simulator somebody has been using, the "fresh install"
    /// test would quietly run against the reader's data and pass for the wrong
    /// reason. Evaluating the engine directly is the same call `recompute()`
    /// makes, with inputs this file controls.
    static func freshInstallResults() -> [InsightResult] {
        let model = make()
        return model.engine.evaluateAll(samples: [], events: [], profile: model.profile)
    }
}
