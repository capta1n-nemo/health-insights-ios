# Widgets — what one may show, and why there isn't one yet

Backlog `D8`: *"No widgets, Live Activities or watch target — for a product
whose central object is a daily number."* Written 2026-08-07.

Two halves, and they are independent. **The honesty rules are decided and
built.** **The extension is parked on signing**, for reasons that are outside
this repo.

---

## 1. What a widget is allowed to show

A widget is the smallest surface this app has and the one seen most often: a
glance, from across the room, with no tap and no context. That combination makes
it **the easiest place in the app to dress modelled as measured** — there is no
room for a caveat, so the caveat gets dropped, and a 74 on a home screen looks
exactly as solid as a thermometer reading.

So the rules below are not a convention for a future author to remember. Each
one is either the shape of a type or a test.

| Rule | How it is held |
| --- | --- |
| **A number never appears without the words that qualify it.** | `WidgetSnapshot.Figure` welds `headline` and `qualifier` into one value, and `qualifier` is non-optional (an empty one is repaired in `init`). There is no API that hands out the number alone. `WidgetRenderSize.supportingLineLimit` is ≥ 1 at every size, and a size that cannot fit a line does not get the figure either. |
| **A card with no figure yields the card's own sentence** — never a dash, a zero, or the last number it had. | `WidgetSnapshot.Content` has exactly two cases. `from(_:capturedAt:dataThrough:)` returns `.withheld` whenever the card published neither `primaryValue` nor `score`, carrying the model's own copy ("Waiting for today's sync", "Building baseline", "Connect a wearable"). `testNoCardInventsAFigureOnAFreshInstall` runs every registered model against no data at all. |
| **Nothing is recomputed for the widget.** | Every string is copied from `InsightResult`. A widget that re-derived a figure could disagree with the card it opens, and the reader would have two numbers for one morning with no way to tell which was wrong. |
| **It says when the reading is old.** | WidgetKit renders from a cached timeline entry at times of its own choosing, so a widget can be on screen hours after the app last ran. `stalenessSentence(now:)` is built from `dataThrough` — the freshest reading actually behind the figure — and is `nil` only while it is *today's*. `AppModel+WidgetSnapshot.freshestReading(behind:)` resolves it from the card's own named contributors; passing `Date()` there would make every widget claim to be current, which is the specific dishonesty the field exists to stop. |
| **Staleness outranks the driver line** for the one spare row. | `supportingLines(now:)`, and `testStalenessOutranksTheDriverLine`. If the number is not about today, that is the thing to say. |
| **Only a *notable* driver earns the second row.** | `notableDriver(in:)` takes `isNotable == true` and nothing else. A card that draws no notable/routine distinction contributes none — showing one item of an unclassified list is the "sixteen normals hide the one that isn't" failure, one row wide. |
| **No trend arrow.** | Not built. A direction with no stated comparison ("against what — yesterday? your 7-day mean?") is the cheapest false precision available, and there is no room to state it. |
| **No truncation.** | `shortReason(from:)` returns `nil` rather than an ellipsis. A half-sentence about health data is worse than no sentence: the reader finishes it themselves, and this app does not get to choose which half they keep. |
| **No lock screen, no Live Activities.** | `.supportedFamilies([.systemSmall, .systemMedium])`. `accessoryCircular`/`accessoryRectangular` render on a **locked** phone, putting this reader's health state in front of anyone who picks it up — an opt-in, not a default. A circular accessory also has room for a number and nothing else, which is the one shape these rules refuse. |
| **The gallery placeholder is not a plausible score.** | `DailyNumberProvider.placeholderSnapshot` withholds. A fake 74 in the widget picker is a number this reader did not have, shown in the app's own voice. |

### Which card

**Readiness**, and it is not close. It is `InsightCadence.daily`, scored against
the reader's own baseline, and the one figure whose whole value is being seen
first thing without opening anything. Energy changes hour to hour and a widget
refreshed on WidgetKit's schedule would routinely be wrong about it; the trend
cards answer questions nobody asks from a home screen. One card until there is a
shipped widget to learn from — `AppModel.widgetInsight`.

---

## 2. Why it is not on the phone

**A widget extension cannot be enabled on `main` today.** Two prerequisites,
both outside this repo, both already documented for `ShotsyImportAction` in
`docs/deployment.md` — the deploy Mac's own words:

```
No profiles for 'com.jasonsalway.healthinsights.ShotsyImportAction' were found
Provisioning profile "iOS Team Provisioning Profile: com.jasonsalway.healthinsights"
  doesn't include the App Groups capability
No Accounts: Add a new account in Accounts settings
```

1. **An Apple Developer Program membership.** A widget runs in its own sandbox.
   The only channel between it and the containing app is an **App Group**, and
   App Groups are not among the capabilities a free personal team can sign.
   There is no version of a data-carrying widget that avoids the entitlement —
   the same finding the share-sheet extension reached, for the same reason.
2. **An Xcode account on the deploy runner Mac.** A widget is a second app
   bundle with its own identifier, and `-allowProvisioningUpdates` cannot mint a
   profile for it while the runner has no account.

**Why parked rather than built and left red:** enabling the target turns a
deploy *install* failure into a deploy *build* failure. An install failure means
the phone missed one update; a build failure means `main` stops reaching the
phone at all and every later push inherits it. `main` is the only route to this
device.

### What was changed that could affect signing

Stated plainly, because this repo has already spent a day on a misread deploy
failure:

**2026-08-07 (honesty rules, snapshot, in-app preview):**

- **Nothing.** No target was added to `HealthInsights.xcodeproj`. No entitlement
  was added or changed — `Support/HealthInsights.entitlements` still contains
  only `com.apple.developer.healthkit`. No new framework is linked by the app
  target: `DailyNumberWidgetView` deliberately does **not** `import WidgetKit`,
  and maps `WidgetFamily` to its own `WidgetRenderSize` in the parked extension
  instead.
- The only edits to shipping code are three Swift files under
  `HealthInsights/Features/Widgets/`, two under `InsightKit/…/Presentation/`, one
  line in `AppModel.applyRecomputed`, and one section in `SettingsView`.

**2026-08-08 (the extension target itself):**

- The `HealthInsightsWidgets` app-extension target now exists in
  `HealthInsights.xcodeproj` (hand-edited; ids `AAAA…AA21`–`AA2E`) — but
  **nothing the deploy signs changed**, verified by building
  `-scheme HealthInsights` before pushing: the new target is **not** a
  dependency of the app target, there is **no embed phase**, and it is in no
  scheme that `ci.yml`, `verify.sh` or `deploy.yml` builds. `deploy.yml` signs
  the same one bundle, with the same
  `Support/HealthInsights.entitlements` (still HealthKit only), as before.
- `Support/HealthInsightsWidgets.entitlements` (App Group) and
  `Support/HealthInsightsWidgets-Info.plist` (the `NSExtension` dict) are new
  files **referenced only by the widget target's build settings** — nothing
  reads them until something builds or signs that target.
- The extension compiles on demand via its own build-only scheme:
  `xcodebuild build -project HealthInsights.xcodeproj -scheme
  HealthInsightsWidgets -destination 'generic/platform=iOS'
  CODE_SIGNING_ALLOWED=NO` — so the glue in `HealthInsightsWidgets/` can no
  longer rot uncompiled (it built first try after one fix: the `@main` bundle
  type was renamed `HealthInsightsWidgetsBundle`, since it shared its name with
  the module). Neither CI nor `verify.sh` builds this scheme yet; until one of
  them does, it compiles only when someone runs the line above.

### What ships today instead

- The app writes `widget-snapshot.json` after every evaluation
  (`AppModel.publishWidgetSnapshot`) — into the App Group container when one
  exists, and into its own container when it does not.
  `WidgetSnapshotStore.resolve()` decides; `isVisibleToWidgets` says which
  happened.
- **Settings ▸ Home screen widget** renders the small and medium widget *from
  that stored file* — not rebuilt for the screen, so a defect in the writing
  half shows there as a blank card rather than as a surprise on the day the
  extension is switched on. The same screen names both blockers in the reader's
  words and lists what a widget is allowed to say.

⚠️ **`UserDefaults(suiteName:)` was deliberately not used.** It is the one API
here that *silently succeeds* without the entitlement: it returns a live object,
accepts every write, and hands the extension nothing — a failure mode that looks
like working software. A file in a directory fails visibly, and is the same code
path on Linux, so the round trip is covered by `swift test`.

---

## 3. Switching it on, when the prerequisites exist

Since 2026-08-08 the target, its entitlements and its Info.plist all exist and
the extension compiles (see above) — what remains is exactly the app-side
wiring that would today break signing:

1. Sign in to Xcode on the deploy runner Mac (Settings ▸ Accounts) as the user
   the Actions runner runs as.
2. With a paid team, add the App Group `group.com.jasonsalway.healthinsights` to
   `Support/HealthInsights.entitlements` (the widget-side
   `Support/HealthInsightsWidgets.entitlements` already carries it — its header
   comment explains why the app side was left out).
3. Embed the extension — **by hand in the `.xcodeproj`; `xcodegen generate` is
   destructive** (see `project.yml`'s header). On the app target
   (`AAAA0000000000000000AA06`): a `PBXTargetDependency` +
   `PBXContainerItemProxy` on `HealthInsightsWidgets`
   (`AAAA0000000000000000AA23`), and a new `PBXCopyFilesBuildPhase` ("Embed
   Foundation Extensions", `dstSubfolderSpec = 13`) carrying
   `HealthInsightsWidgets.appex` with `RemoveHeadersOnCopy`. Mirror the same
   two lines in `project.yml` (the `- target: HealthInsightsWidgets /
   embed: true` dependency) so spec and project keep saying the same thing.
4. `./scripts/verify.sh --tests`, then push and watch
   `./scripts/deploy-status.sh --wait` — and on a red,
   `./scripts/deploy-status.sh --errors`, which distinguishes a signing refusal
   from an unreachable phone. **If it goes red, revert step 3 immediately**
   rather than debugging on `main`.
5. Once it deploys, add `import WidgetKit` and
   `WidgetCenter.shared.reloadTimelines(ofKind: DailyNumberWidget.kind)` to
   `AppModel.publishWidgetSnapshot`. It is left out today because a reload call
   with no installed widget is a no-op that would link WidgetKit into the app
   for nothing.
6. Give the extension a standing gate: add the `HealthInsightsWidgets` scheme
   build (signing off) to `verify.sh`'s Darwin block and/or `ci.yml`, so a
   regression in the glue is caught before the day someone ships it.

## Not attempted, and why

- **A watch target.** Same signing wall, a larger one — a watch app is a second
  product with its own provisioning — and it needs a data story of its own
  (HealthKit on the watch, not this snapshot). Nothing here is a step towards it.
- **Live Activities.** They need something that *starts and ends* — a workout, a
  dose window. A daily score has neither, so an activity would sit there for
  twenty-four hours saying the same thing, which is a widget with more
  ceremony.
