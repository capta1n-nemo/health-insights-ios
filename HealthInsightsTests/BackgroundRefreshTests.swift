import Foundation
import XCTest
import InsightKit
@testable import HealthInsights

/// The background half of backlog `Q11`, and specifically the parts of it that
/// no test in InsightKit can reach: a string that has to match a bundle
/// resource, and a declaration that has to be present in a plist.
///
/// ⚠️ **Every failure this file catches is silent at runtime.** A background
/// task identifier that is not in `BGTaskSchedulerPermittedIdentifiers` throws
/// at registration, the app carries on working perfectly, and nothing is ever
/// evaluated in the background again — which is exactly the state the repo was
/// already in before this row, and exactly the state that would be
/// indistinguishable from it afterwards. That is worth a test even though it is
/// only comparing two strings.
///
/// Mac-only, like everything in this target — see `AppTargetTestSupport.swift`.
final class BackgroundRefreshTests: XCTestCase {

    private var info: [String: Any] {
        Bundle(for: BackgroundRefreshTests.self).infoDictionary ?? [:]
    }

    /// The host app's own bundle, not the test bundle's.
    private var appInfo: [String: Any] {
        // `TEST_HOST` puts the tests inside the app, so the app bundle is the
        // one that owns the executable under test.
        Bundle(for: AppModel.self).infoDictionary ?? [:]
    }

    func testTheTaskIdentifierIsPermittedByInfoPlist() throws {
        let permitted = try XCTUnwrap(
            appInfo["BGTaskSchedulerPermittedIdentifiers"] as? [String],
            "Support/Info.plist declares no BGTaskSchedulerPermittedIdentifiers, "
                + "so BGTaskScheduler will refuse to register anything and the app "
                + "will only ever evaluate while it is on screen.")
        XCTAssertTrue(permitted.contains(BackgroundRefresh.taskIdentifier),
                      "BackgroundRefresh.taskIdentifier (\(BackgroundRefresh.taskIdentifier)) "
                        + "is not in \(permitted). These are one string in two files with no "
                        + "compiler between them.")
    }

    func testTheFetchBackgroundModeIsDeclared() throws {
        let modes = try XCTUnwrap(appInfo["UIBackgroundModes"] as? [String],
                                  "Without UIBackgroundModes, a BGAppRefreshTask never runs.")
        XCTAssertTrue(modes.contains("fetch"))
    }

    /// ⚠️ **The signing claim, asserted rather than asserted-in-prose.**
    ///
    /// `deploy.yml` runs on the reader's own Mac and a red deploy is either a
    /// signing refusal or an unreachable phone. Guessing between the two has
    /// cost a session before, so the statement "this work cannot make a deploy
    /// fail at signing" is worth holding down: the entitlements file must carry
    /// nothing but the HealthKit key it already had. If a later session adds
    /// HealthKit background delivery — which is the natural next step and is
    /// argued for in `BackgroundRefresh` — this test fails, and the failure is
    /// the reminder that an entitlement change has to be watched through a
    /// deploy rather than pushed and assumed.
    func testTheEntitlementsFileGainedNothing() throws {
        let url = try XCTUnwrap(
            Bundle(for: AppModel.self).url(forResource: "HealthInsights", withExtension: "entitlements")
                ?? entitlementsInSource(),
            "Could not find HealthInsights.entitlements to check.")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(Set(plist.keys), ["com.apple.developer.healthkit"],
                       "The background-delivery work must not add an entitlement. "
                        + "Anything beyond the HealthKit key has to be provisioned, and an "
                        + "unprovisioned entitlement fails at codesign on the reader's Mac.")
    }

    /// The entitlements file is not copied into the built bundle, so in a
    /// simulator run it has to be read from the source tree.
    private func entitlementsInSource() -> URL? {
        // `#filePath` is this file, in the checkout that built the bundle.
        var url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // HealthInsightsTests
            .deletingLastPathComponent()      // repo root
        url.appendPathComponent("Support/HealthInsights.entitlements")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A floor rather than a schedule, and it must stay a floor a reasonable
    /// system would ever honour. iOS ignores anything shorter than about
    /// fifteen minutes outright.
    func testTheEarliestIntervalIsSomethingIOSWouldHonour() {
        XCTAssertGreaterThanOrEqual(BackgroundRefresh.earliestInterval, 15 * 60)
    }

    /// The settings screen prints this as whole hours. A value that does not
    /// divide would render "about every 0 hours".
    func testTheIntervalRendersAsWholeHours() {
        XCTAssertGreaterThanOrEqual(Int(BackgroundRefresh.earliestInterval / 3600), 1)
    }
}

/// The wiring between `AppModel` and the pure notification machinery.
///
/// The decisions themselves are tested in InsightKit, where they run on Linux
/// and in CI. What is left here is what only the app target can answer: that a
/// stored policy survives a round trip, and that a source the app cannot pull
/// from is never accused of having stopped.
@MainActor
final class NotificationCoordinatorTests: XCTestCase {

    /// Push-only sources cannot stall, and the notification pass must not say
    /// they have. Held here because `syncsOnItsOwn` is a property of the app's
    /// integration protocol, which InsightKit cannot see.
    func testPushOnlySourcesDoNotClaimToSyncOnTheirOwn() {
        XCTAssertFalse(ShotsyIntegration().syncsOnItsOwn)
        XCTAssertFalse(ShortcutsIntegration().syncsOnItsOwn)
    }

    /// A source the app genuinely polls keeps the default, so a stall in it is
    /// reported.
    func testPullingSourcesAreWatched() {
        XCTAssertTrue(AppleHealthProvider(service: HealthKitService()).syncsOnItsOwn)
    }
}
