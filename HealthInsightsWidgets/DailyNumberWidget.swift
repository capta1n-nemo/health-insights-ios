// ⚠️ **THIS FILE COMPILES IN THE `HealthInsightsWidgets` TARGET, WHICH NOTHING
// EMBEDS OR SIGNS YET.** Read `docs/widgets.md` before switching it on.
//
// Backlog `D8`. Since 2026-08-08 the extension target exists in the project and
// builds via its own scheme (`xcodebuild -scheme HealthInsightsWidgets …
// CODE_SIGNING_ALLOWED=NO`), so this glue can no longer rot uncompiled. It is
// still deliberately OUT of the app's build graph: no target dependency, no
// embed phase, not in the `HealthInsights` scheme that ci.yml, verify.sh and
// deploy.yml all build. Embedding it turns a deploy *install* failure into a
// deploy *build* failure, and `main` is the only route to this reader's phone —
// the exact reasoning that parked `ShotsyImportAction` on 2026-08-02
// (`docs/deployment.md`). Two prerequisites, both outside this repo:
//
//   1. An Apple Developer Program membership. A widget can only read the app's
//      data through an App Group, and a free personal team cannot sign one.
//   2. An Xcode account on the deploy runner Mac, so `-allowProvisioningUpdates`
//      can mint a profile for a second bundle id ("No Accounts: Add a new
//      account in Accounts settings").
//
// **Everything with logic in it lives in a target that compiles.**
// `WidgetSnapshot` and `WidgetSnapshotStore` are in InsightKit with tests;
// `DailyNumberWidgetView` and `WidgetRenderSize` are in the app target and are
// rendered by Settings ▸ Home screen widget. What is left here is glue —
// WidgetKit's four required conformances and nothing else — so the amount of
// code that can rot while this is parked is as close to zero as the framework
// allows.

import SwiftUI
import WidgetKit
import InsightKit

/// The one widget. One card, one number, until there is a shipped one to learn
/// from.
struct DailyNumberWidget: Widget {
    static let kind = "DailyNumberWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DailyNumberProvider()) { entry in
            DailyNumberWidgetView(snapshot: entry.snapshot,
                                  size: WidgetRenderSize(entry.family),
                                  now: entry.date)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Your readiness score, with the words that qualify it.")
        // ⚠️ Home screen only. `.accessoryCircular` and `.accessoryRectangular`
        // render on a *locked* phone; see `WidgetRenderSize`.
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DailyNumberEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
}

struct DailyNumberProvider: TimelineProvider {

    /// The gallery placeholder. **Never a plausible-looking score** — a fake 74
    /// in the widget picker is a number this reader did not have, shown in the
    /// app's own voice.
    private func placeholderSnapshot(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(insight: .readiness, title: "Readiness",
                       content: .withheld(headline: "Open the app to set this up",
                                          reason: nil),
                       capturedAt: now, dataThrough: nil)
    }

    private func current(now: Date) -> WidgetSnapshot {
        WidgetSnapshotStore.resolve()?.read() ?? placeholderSnapshot(now: now)
    }

    func placeholder(in context: Context) -> DailyNumberEntry {
        DailyNumberEntry(date: Date(), snapshot: placeholderSnapshot(now: Date()),
                         family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyNumberEntry) -> Void) {
        let now = Date()
        completion(DailyNumberEntry(date: now, snapshot: current(now: now),
                                    family: context.family))
    }

    /// One entry now, and one at the next midnight.
    ///
    /// The second is not padding. Every figure this widget can show is a claim
    /// about *today*, and `WidgetSnapshot.stalenessSentence` changes its answer
    /// at the calendar-day boundary — so without a midnight entry a widget
    /// rendered at 11pm would still be presenting yesterday's number unlabelled
    /// at 9am. The app pushes fresher entries whenever it evaluates; this is the
    /// floor, for the phone that sat untouched overnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyNumberEntry>) -> Void) {
        let now = Date()
        let snapshot = current(now: now)
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let entries = [
            DailyNumberEntry(date: now, snapshot: snapshot, family: context.family),
            DailyNumberEntry(date: midnight, snapshot: snapshot, family: context.family)
        ]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

extension WidgetRenderSize {
    /// WidgetKit's families, mapped to the two this app draws. The one place
    /// WidgetKit's vocabulary is allowed to reach — see `DailyNumberWidgetView`.
    init(_ family: WidgetFamily) {
        self = family == .systemSmall ? .small : .medium
    }
}

// Named `…Bundle` rather than `HealthInsightsWidgets` because the module is
// already called that: a top-level type sharing its module's name makes every
// qualified lookup (`HealthInsightsWidgets.X`) resolve to the struct instead of
// the module, which surfaces as baffling "is not a member type" errors the day
// a second file needs one.
@main
struct HealthInsightsWidgetsBundle: WidgetBundle {
    var body: some Widget { DailyNumberWidget() }
}
