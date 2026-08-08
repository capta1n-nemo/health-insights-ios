# Write-back to Apple Health — scope of record (backlog Q12)

<!-- status: scoped — Q12 ready-to-build: the writable set is reader-entered values only, a modelled figure is never written back as measured. Unstarted **by the reader's own ruling** -->

**Status: scoped, not built. The reader ruled "Wanted, but not yet. Roadmap"
(2026-08-07).** This document exists so that when it is scheduled it is a
build, not a research project. Nothing here is an open question owed to the
reader — every decision below carries a recommended default a build session can
take without asking.

---

## 1. The one rule that shapes everything else

**A modelled figure must never be written to HealthKit as if measured.** Once a
number is in Apple Health it *is* the reader's permanent record: other apps
read it, clinicians are shown it, exports carry it, and nothing downstream can
tell a cuff reading from a regression. Writing a modelled value back would
launder modelled-as-measured into that record — the worst possible violation of
the app's honesty rule, because it happens outside the app where no caveat,
confidence badge or dashed line can travel with the number.

So the writable set is defined by provenance, not by type: **only values the
reader physically measured or deliberately reported, entered into this app by
hand.** Concretely, a sample qualifies only if its source is `MetricSource.manual`
(see `InsightKit/Sources/InsightKit/Models/HealthMetricSample.swift`). Excluded
by construction:

- `calculated` — the source that exists precisely so a modelled series can
  never be mistaken for a reading (`activeMedicationLevel`, the cuffless BP
  estimate, RFM/body-fat estimates, somatotype, sound-dose LEQs, every score).
- `document` / `shotsy` / `oura` / `withings` / any `appleHealthDevice(_)` —
  data that already has an upstream. Writing a Shotsy weigh-in to HealthKit
  would duplicate it the day Shotsy (or the scale) writes it too, and it is not
  ours to assert.
- `screenshot` / `shortcuts` — the device's own accounting, not a measurement
  this app took; and the Shortcuts route often *already* writes to HealthKit
  (the reader's basal-body-temperature Shortcut does exactly that).

One subtlety inside a single input: `BodyScan.CaptureMode`
(`InsightKit/Sources/InsightKit/Signals/BodyScan.swift`) distinguishes `.tape`
from `.lidarDepth` and `.cameraSegmentation`. A tape waist is measured; a
LiDAR or camera circumference is an ellipse fitted at a height station —
modelled, `confidence` capped at `.moderate` for that reason. **Only `.tape`
scans qualify for write-back.** Same sheet, same `BodyScan` type, different
provenance — the filter must be on `mode`, not on the input kind.

## 2. The writable set

Walking `InputKind` (`InsightKit/Sources/InsightKit/Presentation/InputKind.swift`)
case by case:

### v1 — writes cleanly, ship first

| Input | HealthKit target | Notes |
| --- | --- | --- |
| `cuffBloodPressure` | `HKCorrelation(.bloodPressure)` wrapping two `HKQuantitySample`s (`bloodPressureSystolic` / `bloodPressureDiastolic`, mmHg) | The canonical case: a real cuff, typed in. Written as a correlation so Health pairs the two numbers, exactly as it displays them. Share authorization is requested on the two *quantity* types — a correlation type itself cannot be authorized. |
| `bodyMeasurements`, **`.tape` mode only** | `waistCircumference`, cm | The single `BodyScan` field HealthKit models. Hips, chest, thigh, neck etc. have no HK type — they stay ours. LiDAR/camera scans never write (see §1). |

That is the honest v1: two targets. Small on purpose — the permission sheet
reads as two comprehensible lines, and every row in it is unimpeachably a
measurement.

### v2 candidates — writable in principle, each with a mapping caveat

| Input | HealthKit target | Caveat |
| --- | --- | --- |
| `sideEffect` | Symptom category types (`nausea`, `headache`, `fatigue`, `dizziness`, …) with `HKCategoryValueSeverity` | Reader-reported, so legitimate. But our free-text `name` must map onto Apple's fixed symptom list (unmapped names cannot be written), and our severity integer must map onto `HKCategoryValueSeverity`'s coarser scale. In HK the medication context is lost — a "side effect of dose N" becomes a bare symptom. Worth doing, second. |
| `labResultManual` — glucose only | `bloodGlucose` (writable quantity type) | A typed lab value is a measurement. But note §2.1: most of the lab panel has no writable HK type at all. |
| `substanceEvent` — alcohol only | `numberOfAlcoholicBeverages` | `SubstanceEvent.units` is deliberately "coarse and optional" (`Substance.swift`) — a count of drinks only when the reader supplied one and meant drinks. Caffeine looks tempting (`dietaryCaffeine`) but needs milligrams, which the app never collects; writing "2 units" as "2 mg" would be false data. Alcohol-with-units only, or skip. |

### Not writable, and why — recorded so nobody re-derives it

- **Lipids / HbA1c / the general lab store**: HealthKit has **no serum
  cholesterol, HDL, LDL, triglyceride or HbA1c quantity types**
  (`dietaryCholesterol` is intake, not serum — a trap). Labs exist in HK only
  as clinical (FHIR) records, which third-party apps cannot write, and whose
  entitlement (`com.apple.developer.healthkit.access`) is unavailable to a free
  team anyway (already noted in `Support/HealthInsights.entitlements`).
- **`ecgImport`**: `HKElectrocardiogram` is not third-party-writable, full stop.
- **`medicationRegimen` / `medicationDose`**: Apple Health's medication
  tracking has historically had no third-party write route, and GLP-1 doses
  must **never** be shoehorned into `insulinDelivery` — a GLP-1 is not insulin
  and that would be flatly wrong data in the permanent record. Re-check the
  current SDK when this is scheduled; if a dose-event write API exists by then,
  doses are reader-entered facts and qualify.
- **`screenTime`, `supplement`, `holiday`, `readerIdentity`,
  `eventConfirmation`, `illnessCorrection`, `bodyType`**: no HealthKit concept
  exists for any of them.
- **Weight**: not in the set because the app has no manual weight entry — every
  weigh-in arrives from Shotsy, a scale, or Apple Health itself (all "has an
  upstream", §1).
- **Every derived figure** — scores, baselines, readiness, sleep metrics,
  `activeMedicationLevel`, sound dose, illness probability: §1. Permanently.

## 3. The authorization surface

- **API**: the existing
  `store.requestAuthorization(toShare: [], read: readTypes)` call in
  `HealthKitService.requestAuthorization()`
  (`HealthInsights/Core/HealthData/HealthKitService.swift:363`) grows a
  non-empty `toShare` set. Same sheet machinery, one extra section.
- **How the ask reads**: the Health permission sheet gains a *"Allow Health
  Insights to Write"* section listing each share type as its own toggle —
  Blood Pressure (two rows, systolic and diastolic) and Waist Circumference in
  v1. The `NSHealthUpdateUsageDescription` string that explains the ask is
  **already in `Support/Info.plist:102`** and already says the right thing
  ("can save the readings you log, such as blood-pressure measurements, back
  to Apple Health").
- **When to ask**: not at onboarding. Write-back should be a Settings toggle —
  *"Save my entries to Apple Health"*, default **off** (the reader parked the
  feature; shipping it armed would overrule that). The share-authorization
  sheet is requested the moment the toggle is first flipped on, so the iOS ask
  arrives explaining an action the reader just chose rather than padding the
  onboarding sheet with write rows before anything has been logged.
- **Asymmetry worth building around**: unlike read status (which HK hides by
  design — see the long comment on `logReadOutcome`, same file), **share status
  is queryable**: `store.authorizationStatus(for:)` returns
  `.sharingAuthorized` / `.sharingDenied` per type. The write path can and
  should check before each save and degrade to a diagnostics line
  (`DiagnosticsLog`) instead of throwing at the reader. The Settings row can
  honestly display "writing blood pressure: off in Health" — a sentence the
  read side is never allowed.
- **Not an `InputKind`**: write-back takes nothing *from* the reader, so it is
  not a new input and adds no case to the enum, no `+`-menu row, no
  `ContributionRoute`. It is a standing configuration: one Settings toggle. The
  `verify.sh` sheet lint does not apply.

## 4. Entitlements and signing — the good news

**No entitlement change at all.** `com.apple.developer.healthkit` — already in
`Support/HealthInsights.entitlements`, already signed and deployed daily —
covers share as well as read. HealthKit is in the free-personal-team capability
set (it is what the app ships under today), so there is **no repeat of the App
Groups story** (`docs/deployment.md` §"share-sheet action extension": App
Groups is not free-team-signable, which is what parked `ShotsyImportAction`).
The clinical-records entitlement stays untouched for the reasons already
commented in the entitlements file.

Both Info.plist usage strings already exist (`Support/Info.plist:100–103`).
Net signing impact of this feature: **zero** — no new profile, no new
capability, no deploy risk beyond an ordinary push.

## 5. The dedup / round-trip loop, and how to break it

The app imports from HealthKit, so writing back creates a loop:

1. Reader types a cuff reading → stored in SwiftData, source `manual`.
2. Write-back saves it to HealthKit.
3. Next sync, `fetchQuantity` reads *everything* in the window — including our
   own write, which maps to
   `MetricSource.appleHealthDevice("Health Insights")`.
4. `deviceFamily` (`HealthMetricSample.swift:90`) resolves that echo to
   `"apple_health"` while the original is `"manual"` — **two different
   families**, so `MultiSource`'s per-family dedup keeps both. Every cuff
   reading double-counts in charts, means and baselines from the first sync
   after the first write.

Three mechanisms, all needed:

- **Own-source guard on read (the load-bearing one).** In each mapping closure
  in `HealthKitService` (`fetchQuantity`, `fetchRawQuantity`,
  `fetchRawCategory`, `fetchSleep`), skip samples whose
  `s.sourceRevision.source.bundleIdentifier` equals our own bundle identifier —
  one shared `nonisolated` helper, one `guard` per closure. Our SwiftData copy
  is canonical for our own entries; the HK copy exists for *other* apps and
  the reader's record, never for our read path. (There is no "not from source"
  HK predicate to push this into the query; an `NSCompoundPredicate` negation
  over `HKQuery.predicateForObjects(from:)` works, but the post-fetch guard is
  simpler and testable.)
- **Sync identifiers on write, so HealthKit itself never duplicates.** Every
  written object carries
  `HKMetadataKeySyncIdentifier: "healthinsights.<record-UUID>"` and
  `HKMetadataKeySyncVersion`, so a re-write (edit, retry, backfill re-run) is
  an idempotent replace inside HK rather than a second sample. Plus
  `HKMetadataKeyWasUserEntered: true` — which is exactly what these values are,
  and lets Health display them honestly.
- **Event-driven writes, never sweep-based mirroring.** Write at the moment an
  entry is saved (a hook where `DataStore` persists the record), and delete
  the HK object (predicate on the sync identifier) at the moment the reader
  deletes the entry in-app. **Never** run a "make HK match our store" sweep:
  a sweep resurrects samples the reader deliberately deleted in the Health app,
  which is their right — HK data is theirs there too. The asymmetry is
  intentional: delete in our app propagates to HK; delete in Health does not
  propagate back (our store holds the reader's entry as entered, and we never
  re-push it because nothing but the original save event writes).

One guard for the future: `percentageMetrics` scaling (0–1 fraction ↔ 0–100)
inverts on the write path. No v1/v2 writable metric is a percentage — a
comment at the write site should say so, so the first percentage candidate
pays the scaling once instead of shipping a hundredfold error into the
permanent record.

## 6. Build shape and cost

- `HealthKitWritebackService` (new file beside `HealthKitService` under
  `HealthInsights/Core/HealthData/`): the mapping tables, sync-identifier
  scheme, save/delete calls. The pure mapping (record → type identifier, unit,
  metadata) belongs in InsightKit where it is testable; the `HK*` calls stay in
  the app target behind `#if canImport(HealthKit)`, exactly as `HealthKitService`
  is structured.
- Own-source guard in `HealthKitService` (four closures, one helper).
- Settings toggle + share-authorization request on first enable.
- Hooks at the two v1 save/delete sites in `DataStore` / `AppModel`.
- **Backfill decision (recommended default: yes, once, on enable)** — when the
  toggle is first switched on, write the existing cuff readings and `.tape`
  waists (a bounded, small set for one reader), then event-driven thereafter.
  Guarded by the sync identifiers, a re-enable cannot duplicate.
- Verification: the simulator can exercise the write path end-to-end (its
  Health store accepts writes); confirm on device by reading the sample back
  in the Health app, source column showing this app. The own-source guard is
  the one behaviour a unit test cannot fully falsify — one device sync after
  one write is the check.

Estimate: one ordinary build session (`build` tier). No new entitlement, no
new input surface, two write targets, one read guard.
