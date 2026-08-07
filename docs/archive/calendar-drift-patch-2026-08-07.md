> ⚠️ **APPLIED, COMPILED AND TESTED — 2026-08-07 (backlog AC1). Do not apply it
> again.** Rescued verbatim from `/private/tmp` (the abandoned iCloud checkout's
> session scratchpad, which does not survive a reboot) and kept here only as the
> record of *why* the change is shaped this way. **The code is the authority
> now** — every doc comment below lives in the source. Three deliberate
> departures from the text, all noted at the end of this header:
>
> 1. §3 and §6c used `Dictionary(uniqueKeysWithValues:)`, which **traps** on a
>    duplicate id. `uniquingKeysWith: { first, _ in first }` instead, matching
>    `mergeCalendarEvents`. A crash in a pure comparison fed a caller-supplied
>    array is not worth the terseness.
> 2. §7 (`InsightDetailView.swift`) was applied **second, in a later wave** —
>    another agent owned that file when the other eight parts landed. It is in
>    now: the `needsRereview` row sits immediately above the three-state
>    `draft != nil` block in `calendarReviewRow`, and the `.onDisappear` is at
>    **body level**, after `.sheet(item: $groundingKind)` on the modifier chain
>    hanging off the `ScrollView` — *not* on `calendarReviewSection`, because the
>    stack inside is a `LazyVStack` and a section-level `.onDisappear` would fire
>    on every scroll. The anchor §7b called "the one anchor not read" is read and
>    the hazard was real.
> 3. Two tests added beyond the file in §8: a pre-upgrade snapshot with no
>    `start` cannot report a move, and the flag round-trips through JSON.

# Calendar re-judgement on drift — apply-ready patch (as written, before it was applied)

Written 2026-08-07 after the worktree became unreadable mid-session (EPERM on
every path under `com~apple~CloudDocs`; the Bash working-directory guard blocks
every shell call for the same reason — "unreadable ancestor directory").

Every edit below was designed against the file contents actually read this
session. Nothing has been applied and nothing has been compiled or tested.

---

## What already exists (verified by reading, this session)

- `CalendarEventArtifact` (`InsightKit/Sources/InsightKit/Models/CalendarEventArtifact.swift`)
  is the R3 snapshot and it is already captured **at classification time**:
  `DataStore.recordClassification(_:for:now:)` writes the guess and the snapshot
  together, and `recordReview` deliberately writes neither. So the "if the
  snapshot is absent, add it" half of the task is already done — R3 shipped in
  `ce9f76f`.
- `CalendarEventArtifact.differs(from:)` exists and its own doc comment says
  *"Nothing acts on this yet"*. That is what this change makes false.
- It compares title, location, attendeeCount, isAllDay, calendarName,
  hasVideoLink, durationHours. **It does not compare `start`** — the field is
  not on the artifact at all. That is the one genuine gap.
- `CalendarEventJudgement.reclassified(as:artifact:)` already states the C4
  invariant at value level (guess + artifact move, correction stays).
- `AppModel.syncCalendar()` classifies only events with no judgement.

---

## 1. `InsightKit/Sources/InsightKit/Models/CalendarEventArtifact.swift`

### 1a. Add `start`, after the `durationHours` property

```swift
    /// **When it was due to begin**, as the snapshot read it.
    ///
    /// Optional because rows written before this field existed have none, and a
    /// missing start is *unknown* rather than a claim — `differs(from:)` skips
    /// the comparison rather than reporting a change it cannot see. Same posture
    /// as `attendeeCount` and `organizerIsReader`.
    ///
    /// ⚠️ **Today a moved event usually arrives as a different event.**
    /// `CalendarIntegration.fetchEvents` folds the occurrence's start into the
    /// identifier (`"\(eventIdentifier)|\(startDate.timeIntervalSince1970)"`),
    /// so dragging a meeting mints a new `CalendarEvent.id` and the old
    /// judgement is left behind rather than found to have drifted. This field is
    /// therefore belt-and-braces — and it stops being belt-and-braces the moment
    /// that id scheme changes, which is exactly the kind of change that would
    /// otherwise make drift detection silently blind to the most obvious edit a
    /// reader can make.
    public let start: Date?
```

### 1b. Memberwise init — add a **defaulted** parameter

Defaulted, so `Sharing.swift:545` and `SharingTierTests.swift:28` keep compiling
untouched. Place it after `durationHours:`:

```swift
    public init(title: String, location: String?, attendeeCount: Int?,
                durationHours: Double, start: Date? = nil, isAllDay: Bool,
                calendarName: String, hasVideoLink: Bool,
                organizerIsReader: Bool?, capturedAt: Date) {
        ...
        self.start = start
        ...
    }
```

### 1c. `init(event:capturedAt:)` — pass `start: event.start`

### 1d. `differs(from:)` — compare start, and retire the "nothing acts on this" line

```swift
    /// Whether the event has drifted from the snapshot — the words, the place,
    /// the shape, the size or the slot changed after it was judged.
    ///
    /// **This is what re-judgement is triggered from** (backlog B8 R3 + C4). It
    /// is a pure struct comparison — no rules, no on-device model — which is
    /// what makes it cheap enough to run against every synced event, and it is
    /// deliberately the *only* thing that runs at sync time: what it finds is
    /// queued, and the classifier runs on a boundary. See
    /// `AppModel.flushCalendarReclassification()`.
    public func differs(from event: CalendarEvent) -> Bool {
        title != event.title
            || location != event.location
            || attendeeCount != event.attendeeCount
            || isAllDay != event.isAllDay
            || calendarName != event.calendarName
            || hasVideoLink != event.hasVideoLink
            || abs(durationHours - event.durationHours) > 0.001
            // A snapshot with no start recorded cannot say the event moved, so
            // it says nothing rather than guessing. One second of slack: these
            // round-trip through JSON and a Date is not a decimal.
            || (start.map { abs($0.timeIntervalSince(event.start)) > 1 } ?? false)
    }
```

---

## 2. `InsightKit/Sources/InsightKit/Models/CalendarEventClassification.swift`

All inside `CalendarEventJudgement`.

### 2a. New stored property (after `reviewedAt`)

```swift
    /// **When the event was first seen to have changed after the reader had
    /// already answered about it**, and nil while it has not.
    ///
    /// ⚠️ **The one thing a re-judgement is not allowed to resolve.** Re-running
    /// the classifier refreshes the guess *and* the snapshot — it has to, or the
    /// stored pair stops being a real training example — and the moment the
    /// snapshot moves, the comparison that found the drift stops reporting it.
    /// The reader's correction would then sit there looking current, when it was
    /// actually an answer about a version of the event that no longer exists.
    ///
    /// So the fact is recorded separately from the comparison and outlives it.
    /// Backlog C4 keeps the guess and the reader's answer apart so accuracy stays
    /// measurable; this keeps them apart in *time* as well — where the two may
    /// have come apart, the reader is told rather than overruled. Cleared only by
    /// the reader looking again (`reviewed(correction:confirmed:at:)`).
    public let changedAfterReviewAt: Date?
```

### 2b. New members

```swift
    /// Whether the reader answered about a version of this event that no longer
    /// exists. **Surfaced, never resolved** — see `changedAfterReviewAt`.
    ///
    /// Gated on there being an answer at all: an untouched guess cannot have
    /// gone stale, it can only be re-judged, which is exactly what happens to it.
    public var needsRereview: Bool {
        changedAfterReviewAt != nil && (isConfirmed || correction != nil)
    }

    /// Whether the event as it stands now differs from the one that was judged.
    ///
    /// False when there is no snapshot: a row written before B8 R3 has nothing to
    /// compare against, and "changed" would be an invention — the same refusal
    /// the artifact itself makes about a start it never recorded.
    public func hasDrifted(from event: CalendarEvent) -> Bool {
        artifact?.differs(from: event) ?? false
    }

    /// Note that the event moved under a reader who had already answered.
    ///
    /// Idempotent and **earliest-wins**: the instant worth keeping is when their
    /// answer first went stale, not the last time a sync happened to notice. A
    /// judgement nobody has reviewed is returned unchanged — there is no answer
    /// for the change to have invalidated.
    public func markedChangedAfterReview(at date: Date) -> CalendarEventJudgement {
        guard reviewedAt != nil, changedAfterReviewAt == nil else { return self }
        return CalendarEventJudgement(eventID: eventID,
                                      classification: classification,
                                      correction: correction,
                                      isConfirmed: isConfirmed,
                                      reviewedAt: reviewedAt,
                                      artifact: artifact,
                                      changedAfterReviewAt: date)
    }
```

### 2c. `init` — new defaulted parameter last

```swift
    public init(eventID: String, classification: CalendarEventClassification,
                correction: CalendarEventClassification? = nil,
                isConfirmed: Bool = false, reviewedAt: Date? = nil,
                artifact: CalendarEventArtifact? = nil,
                changedAfterReviewAt: Date? = nil) {
```

### 2d. `reclassified(as:artifact:)` — **carry the flag through**

Add `changedAfterReviewAt: changedAfterReviewAt` to the returned value, and to
the doc comment:

```swift
    /// ⚠️ **`changedAfterReviewAt` survives too**, and that is the point of it
    /// being stored rather than derived: this call is what refreshes the
    /// snapshot, so the drift comparison goes quiet a line later. If the flag
    /// moved with the snapshot, a re-judgement would silently decide that a
    /// correction made about the old event still describes the new one.
```

### 2e. `reviewed(correction:confirmed:at:)` — **clear the flag**

Pass `changedAfterReviewAt: nil`, and document:

```swift
    /// ⚠️ **It clears `changedAfterReviewAt`**, and only this does. The reader is
    /// looking at the event as it stands now, so whatever it did since they last
    /// answered has been answered for.
```

---

## 3. `InsightKit/Sources/InsightKit/Models/CalendarEventClassifier.swift`

New section, before `// MARK: - What the cards read`:

```swift
    // MARK: - Drift: the event changed after it was judged

    /// **Which of these events no longer match the snapshot they were judged
    /// against**, in the order they were given.
    ///
    /// A pure comparison — no rules, no model, one dictionary lookup per event —
    /// which is what makes it safe on every sync. Re-judging what it returns is a
    /// separate and deliberately debounced step; see
    /// `AppModel.flushCalendarReclassification()`.
    ///
    /// Two things it deliberately does not call drift:
    ///
    /// - **An event with no judgement.** That is unjudged, not changed, and the
    ///   sync path already classifies those.
    /// - **A judgement written before the artifact snapshot existed.** There is
    ///   nothing to compare, and treating "cannot tell" as "changed" would spend
    ///   the on-device model on every pre-B8 row at once, which is precisely the
    ///   *"do not completely slow down the app"* half of the reader's
    ///   instruction.
    public static func drifted(_ judgements: [CalendarEventJudgement],
                               events: [CalendarEvent]) -> [CalendarEvent] {
        let byID = Dictionary(uniqueKeysWithValues: judgements.map { ($0.eventID, $0) })
        return events.filter { byID[$0.id]?.hasDrifted(from: $0) == true }
    }
```

---

## 4. `HealthInsights/Core/Persistence/PersistenceModels.swift`

`CalendarJudgementRecord`, after `reviewedAt`:

```swift
    /// When the event first changed under an answer the reader had already
    /// given — see `CalendarEventJudgement.changedAfterReviewAt`. Optional and
    /// additive, so this is a lightweight SwiftData migration and needs no
    /// schema version, exactly like `artifactData` before it.
    var changedAfterReviewAt: Date?
```

Init gains `changedAfterReviewAt: Date? = nil` and assigns it; `judgement`
passes `changedAfterReviewAt: changedAfterReviewAt` through.

---

## 5. `HealthInsights/Core/Persistence/DataStore.swift`

### 5a. `recordClassification` — one comment, no behaviour change

Add to its doc block:

```swift
    /// ⚠️ **It does not touch `changedAfterReviewAt` either.** This call is what
    /// refreshes the snapshot, so it is the exact moment the drift comparison
    /// goes quiet — clearing the flag here would make a re-judgement decide, on
    /// the reader's behalf, that a correction about the old event still stands.
```

### 5b. `recordReview` — clear the flag

```swift
        record.reviewedAt = now
        // The reader has just looked at the event as it stands, so whatever it
        // did since they last answered has now been answered for.
        record.changedAfterReviewAt = nil
```

…and add to the doc block:

```swift
    /// It *does* clear `changedAfterReviewAt` — the "this changed since you
    /// reviewed it" flag — because this call is the reader answering again.
```

### 5c. New writer

```swift
    /// Note, against each of these events, that it changed after the reader had
    /// already answered about it.
    ///
    /// ⚠️ **A flag, not a resolution.** The correction is untouched here as
    /// everywhere; all this records is that the answer was given about a version
    /// of the event that no longer exists, so the review row can say so instead
    /// of the app quietly discarding their input. Rows the reader has never
    /// reviewed get nothing — there is no answer to have gone stale, and those
    /// are simply re-judged.
    ///
    /// Earliest-wins, so a nightly sync cannot keep resetting the instant to
    /// "just now" and make a fortnight-old drift look like it happened today.
    func markCalendarJudgementsChanged(_ eventIDs: [String], now: Date = Date()) {
        guard !eventIDs.isEmpty else { return }
        let wanted = Set(eventIDs)
        var touched = false
        for record in (try? context.fetch(FetchDescriptor<CalendarJudgementRecord>())) ?? []
        where wanted.contains(record.eventID) {
            guard record.reviewedAt != nil, record.changedAfterReviewAt == nil else { continue }
            record.changedAfterReviewAt = now
            touched = true
        }
        if touched { try? context.save() }
    }
```

---

## 6. `HealthInsights/Core/State/AppModel.swift`

### 6a. The queue, beside `calendarEvents` / `calendarJudgements`

```swift
    /// **Events that changed since the app judged them, waiting to be re-judged.**
    ///
    /// Ids rather than events, so a meeting renamed three times before the flush
    /// is judged once, against whatever it finally says.
    ///
    /// `@ObservationIgnored` on purpose: nothing on screen reads the queue — the
    /// review row reads `CalendarEventJudgement.needsRereview`, which is stored —
    /// and an observed set would redraw both calendar cards on every sync that
    /// found a renamed meeting.
    ///
    /// It does not survive a relaunch, and does not need to: re-judgement is what
    /// refreshes the snapshot, so anything not flushed is simply found again by
    /// the next sync's comparison.
    @ObservationIgnored private var calendarReclassificationQueue: Set<String> = []
```

### 6b. `syncCalendar()` — flush first, detect last

```swift
    func syncCalendar() async {
        // ⚠️ **The backstop, not the boundary.** The boundary is leaving the
        // card — see `flushCalendarReclassification()`. This is here so a reader
        // who never opens either calendar card does not accumulate stale guesses
        // for ever, and it is bounded by what actually moved rather than by the
        // size of the calendar: on the overwhelmingly common sync, where nothing
        // changed, it returns immediately having done nothing.
        await flushCalendarReclassification()

        guard let integration = registry.integration(withID: "calendar")
                as? CalendarIntegration,
              let fetched = try? integration.fetchEvents(identity: readerIdentity)
        else { return }
        dataStore.mergeCalendarEvents(fetched)

        let stored = dataStore.loadCalendarJudgements()
        let judged = Set(stored.map(\.eventID))
        for event in fetched where !judged.contains(event.id) {
            let base = CalendarEventClassifier.classify(event, identity: readerIdentity)
            let reading = await interpreter.interpret(event)
            let final = CalendarEventClassifier.refined(
                base, modelContext: reading?.context, modelFormality: reading?.formality)
            dataStore.recordClassification(final, for: event)
        }

        // MARK: what changed since it was judged (backlog B8 R3, C4)
        //
        // Detection only. A pure struct comparison against each stored snapshot,
        // costing a dictionary lookup per event — cheap enough to run every sync,
        // which is the whole reason judging and noticing were separated. What it
        // finds is queued and judged on a boundary, below.
        //
        // ⚠️ `stored` is read *before* the loop above deliberately: an event just
        // classified for the first time cannot have drifted from a snapshot taken
        // one line ago, and including it would re-judge every new event twice.
        let drifted = CalendarEventClassifier.drifted(stored, events: fetched)
        calendarReclassificationQueue.formUnion(drifted.map(\.id))
        // Where the reader has already answered and the event moved underneath
        // them, the row is flagged rather than silently re-decided. Their
        // correction is untouched either way — `recordClassification` cannot see
        // one — but an answer about words that no longer exist deserves saying so.
        dataStore.markCalendarJudgementsChanged(drifted.map(\.id))

        reloadCalendar()
        recompute()
    }
```

### 6c. The boundary

```swift
    /// **Re-judge everything that changed, on the way out of the card.**
    ///
    /// The reader's instruction, 2026-08-06: *"I want it to re-write the model,
    /// and re-calculate, maybe only do it once they leave the card, or just
    /// whatever is the most efficient way, that also will not completely slow
    /// down or break the app."*
    ///
    /// ## The boundary chosen, and why it is this one
    ///
    /// **Leaving the insight detail view** (`InsightDetailView.onDisappear`),
    /// with the next sync as a backstop. Noticing a change is free and happens on
    /// every sync; *judging* one is not — it is an on-device language-model call
    /// per event — and the two calendar cards are the only surface where the
    /// answer is visible. Doing the work as the reader walks out means it is
    /// already done when they walk back in, and it happens with nothing on screen
    /// waiting on it.
    ///
    /// The two alternatives were both worse, and both are named because both were
    /// nearly taken:
    ///
    /// - **Inside a view update.** It would run on every redraw, against a list
    ///   the reader is in the middle of reading, and relabel rows under their
    ///   thumb.
    /// - **On the sync tick.** It would land inside the "Syncing your devices"
    ///   pass the reader has already told us hangs their phone (2026-08-06), and
    ///   for a card they may not be looking at.
    ///
    /// Either trigger empties the queue, so **nothing happens when nothing
    /// moved** — which is what makes this a debounce rather than a schedule.
    ///
    /// ## ⚠️ The invariant
    ///
    /// This rewrites the **guess** and the **snapshot** and cannot reach the
    /// reader's correction: `DataStore.recordClassification` does not take one
    /// and has never had one in hand (backlog C4), and
    /// `CalendarEventJudgement.reclassified(as:artifact:)` states the same thing
    /// at value level, where it is tested. Where a correction exists and the
    /// event moved under it, `markCalendarJudgementsChanged` has already flagged
    /// the row, so the reader is told rather than overruled.
    func flushCalendarReclassification() async {
        guard !calendarReclassificationQueue.isEmpty else { return }
        // Taken and cleared up front, so a sync landing mid-flush queues into an
        // empty set rather than having its work dropped by the clear at the end.
        let pending = calendarReclassificationQueue
        calendarReclassificationQueue = []
        let byID = Dictionary(uniqueKeysWithValues:
            dataStore.loadCalendarEvents().map { ($0.id, $0) })
        var rejudged = 0
        for id in pending {
            guard let event = byID[id] else { continue }
            let base = CalendarEventClassifier.classify(event, identity: readerIdentity)
            let reading = await interpreter.interpret(event)
            let final = CalendarEventClassifier.refined(
                base, modelContext: reading?.context, modelFormality: reading?.formality)
            // Guess and snapshot together, so the stored pair stays each other's.
            dataStore.recordClassification(final, for: event)
            rejudged += 1
        }
        guard rejudged > 0 else { return }
        reloadCalendar()
        // Both calendar cards read `loadHours`, which a re-judged occasion or
        // formality moves. This is the existing path — the insight pass runs off
        // the main actor behind its generation guard (`dab5399`); nothing
        // synchronous is reintroduced here.
        recompute()
    }
```

---

## 7. `HealthInsights/Features/Insights/InsightDetailView.swift`

### 7a. The row — inside `calendarReviewRow`, immediately **above** the
`if draft != nil { … } else if judgement.isConfirmed … ` block

```swift
            // ⚠️ **Surfaced, never resolved** (backlog C4). A re-judgement
            // rewrites the app's guess and cannot touch the reader's answer — but
            // an answer given about a meeting that has since been renamed,
            // lengthened or moved may simply no longer be about the same thing.
            // Silently discarding it would destroy their input; silently keeping
            // it would present a stale answer as current. So the row says so and
            // leaves the decision where it belongs.
            if judgement.needsRereview {
                Label("This event changed after you reviewed it — check the labels still fit.",
                      systemImage: "exclamationmark.arrow.circlepath")
                    .font(.caption2).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
```

The existing `Change` / `That's right` controls are already present and already
clear the flag through `reviewCalendarEvent` → `DataStore.recordReview`.

### 7b. The boundary — ⚠️ **THE ONE ANCHOR NOT READ THIS SESSION**

`.onDisappear` must go on the **top level of `InsightDetailView.body`**, not on
`calendarReviewSection`. If the detail body is a `LazyVStack`, an `onDisappear`
on the section fires when the section scrolls out of view, which is a *view
update* and is exactly what the task forbids. Read `InsightDetailView.body`
(around lines 1–100 / 385+) and attach:

```swift
        // The debounce boundary the reader asked for: *"maybe only do it once
        // they leave the card"*. Detection is free and happens on sync; judging
        // costs an on-device model call, so it waits until nothing on screen
        // depends on it. Detached rather than awaited — the view is going away
        // and has nothing to wait for; the cards redraw when `recompute()`'s
        // observed results land.
        .onDisappear {
            Task { await model.flushCalendarReclassification() }
        }
```

---

## 8. New test file
`InsightKit/Tests/InsightKitTests/CalendarDriftTests.swift`

```swift
import XCTest
@testable import InsightKit

/// **An event that changed after it was judged** — backlog B8 R3 + C4.
///
/// The fourth test is the one that matters: a re-judgement must move the guess
/// and the snapshot and must not be able to reach the reader's answer.
final class CalendarDriftTests: XCTestCase {

    private let judgedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(id: String = "evt-1",
                       title: String = "Weekly planning",
                       location: String? = "Room 2",
                       hours: Double = 1,
                       startOffset: TimeInterval = 0,
                       calendarName: String = "Work",
                       attendees: Int? = 4,
                       allDay: Bool = false) -> CalendarEvent {
        let start = judgedAt.addingTimeInterval(startOffset)
        return CalendarEvent(id: id, start: start,
                             end: start.addingTimeInterval(hours * 3600),
                             isAllDay: allDay, timeZoneIdentifier: nil,
                             calendarName: calendarName, kind: .timed,
                             title: title, location: location,
                             hasVideoLink: false, organizerIsReader: true,
                             attendeeCount: attendees)
    }

    private func judgement(for event: CalendarEvent,
                           correction: CalendarEventClassification? = nil,
                           confirmed: Bool = false,
                           reviewed: Date? = nil,
                           snapshot: Bool = true) -> CalendarEventJudgement {
        CalendarEventJudgement(
            eventID: event.id,
            classification: CalendarEventClassifier.classify(event),
            correction: correction,
            isConfirmed: confirmed,
            reviewedAt: reviewed,
            artifact: snapshot ? CalendarEventArtifact(event: event, capturedAt: judgedAt) : nil)
    }

    // MARK: 1 — a changed event is detected

    func testARenamedEventIsDetected() {
        let original = event()
        let stored = judgement(for: original)
        let renamed = event(title: "Client review")
        XCTAssertTrue(stored.hasDrifted(from: renamed))
        XCTAssertEqual(CalendarEventClassifier.drifted([stored], events: [renamed]).map(\.id),
                       ["evt-1"])
    }

    func testALengthenedEventIsDetected() {
        let stored = judgement(for: event())
        XCTAssertTrue(stored.hasDrifted(from: event(hours: 3)))
    }

    func testAMovedEventIsDetected() {
        // The start is on the snapshot now, so a slot change is drift even when
        // nothing else about the event moved.
        let stored = judgement(for: event())
        XCTAssertTrue(stored.hasDrifted(from: event(startOffset: 3600)))
    }

    func testEveryAxisTheTaskNames() {
        let stored = judgement(for: event())
        XCTAssertTrue(stored.hasDrifted(from: event(title: "Other")))
        XCTAssertTrue(stored.hasDrifted(from: event(location: nil)))
        XCTAssertTrue(stored.hasDrifted(from: event(hours: 2)))
        XCTAssertTrue(stored.hasDrifted(from: event(startOffset: 900)))
        XCTAssertTrue(stored.hasDrifted(from: event(calendarName: "Family")))
        XCTAssertTrue(stored.hasDrifted(from: event(attendees: 9)))
        XCTAssertTrue(stored.hasDrifted(from: event(allDay: true)))
    }

    // MARK: 2 — an unchanged event is not re-judged

    func testAnUnchangedEventIsNotDrift() {
        let original = event()
        let stored = judgement(for: original)
        XCTAssertFalse(stored.hasDrifted(from: original))
        XCTAssertTrue(CalendarEventClassifier.drifted([stored], events: [original]).isEmpty)
    }

    func testAnUnjudgedEventIsNotDrift() {
        // Unjudged is not changed. The sync path classifies those separately and
        // counting them here would re-judge the whole calendar on first run.
        XCTAssertTrue(CalendarEventClassifier.drifted([], events: [event()]).isEmpty)
    }

    func testAJudgementWithNoSnapshotIsNeverDrift() {
        let stored = judgement(for: event(), snapshot: false)
        XCTAssertFalse(stored.hasDrifted(from: event(title: "Renamed")))
        XCTAssertTrue(CalendarEventClassifier.drifted([stored],
                                                      events: [event(title: "Renamed")]).isEmpty)
    }

    // MARK: 3 — re-judging moves the guess and the snapshot

    func testRejudgingMovesTheGuessAndTheSnapshot() throws {
        let original = event(title: "Weekly planning", calendarName: "Work")
        let stored = judgement(for: original)
        let changed = event(title: "Dentist", calendarName: "Personal")
        let fresh = CalendarEventClassifier.classify(changed)
        let after = stored.reclassified(
            as: fresh, artifact: CalendarEventArtifact(event: changed))

        XCTAssertEqual(after.classification.context, .personal)
        let snapshot = try XCTUnwrap(after.artifact)
        XCTAssertEqual(snapshot.title, "Dentist")
        XCTAssertEqual(snapshot.calendarName, "Personal")
        // And the drift is now settled — the pair is each other's again.
        XCTAssertFalse(after.hasDrifted(from: changed))
    }

    // MARK: 4 — ⚠️ the invariant: a correction survives a re-judge

    func testAReaderCorrectionSurvivesARejudge() {
        let original = event(title: "Weekly planning", calendarName: "Work")
        let readerSaid = CalendarEventClassification(
            context: .personal, occasion: .blockedTime, presence: .inPerson,
            formality: .casual, hours: 1,
            deciders: [CalendarEventClassification.contextKey: .reader,
                       CalendarEventClassification.occasionKey: .reader,
                       CalendarEventClassification.formalityKey: .reader])
        let stored = judgement(for: original, correction: readerSaid,
                               confirmed: true, reviewed: judgedAt)

        let changed = event(title: "Client review workshop", hours: 5)
        let after = stored
            .markedChangedAfterReview(at: judgedAt.addingTimeInterval(86_400))
            .reclassified(as: CalendarEventClassifier.classify(changed),
                          artifact: CalendarEventArtifact(event: changed))

        // The guess moved.
        XCTAssertEqual(after.classification.formality, .formal)
        // The reader's answer did not — on any axis.
        XCTAssertEqual(after.correction, readerSaid)
        XCTAssertEqual(after.effective, readerSaid)
        XCTAssertTrue(after.isConfirmed)
        XCTAssertEqual(after.reviewedAt, judgedAt)
        XCTAssertEqual(after.effective.decider(for: CalendarEventClassification.contextKey),
                       .reader)
    }

    func testTheChangedFlagOutlivesTheSnapshotRefresh() {
        // The reason the flag is stored rather than derived: re-judging is what
        // makes `hasDrifted` false again, so a derived flag would vanish exactly
        // when the reader most needs telling.
        let original = event()
        let stored = judgement(for: original,
                               correction: CalendarEventClassifier.classify(original),
                               confirmed: true, reviewed: judgedAt)
        let changed = event(title: "Renamed", hours: 4)
        let flagged = stored.markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        XCTAssertTrue(flagged.needsRereview)

        let after = flagged.reclassified(as: CalendarEventClassifier.classify(changed),
                                         artifact: CalendarEventArtifact(event: changed))
        XCTAssertFalse(after.hasDrifted(from: changed))
        XCTAssertTrue(after.needsRereview, "a re-judgement must not silence the flag")
    }

    func testAnUnreviewedJudgementIsNeverFlagged() {
        // Nothing has gone stale — there is no answer. It is simply re-judged.
        let stored = judgement(for: event())
        let flagged = stored.markedChangedAfterReview(at: judgedAt)
        XCTAssertNil(flagged.changedAfterReviewAt)
        XCTAssertFalse(flagged.needsRereview)
    }

    func testTheFlagIsEarliestWins() {
        let stored = judgement(for: event(), confirmed: true, reviewed: judgedAt)
        let first = stored.markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        let second = first.markedChangedAfterReview(at: judgedAt.addingTimeInterval(9_000))
        XCTAssertEqual(second.changedAfterReviewAt, judgedAt.addingTimeInterval(60))
    }

    func testReviewingAgainClearsTheFlag() {
        let stored = judgement(for: event(), confirmed: true, reviewed: judgedAt)
            .markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        XCTAssertTrue(stored.needsRereview)
        let answered = stored.reviewed(correction: nil, confirmed: true,
                                       at: judgedAt.addingTimeInterval(120))
        XCTAssertNil(answered.changedAfterReviewAt)
        XCTAssertFalse(answered.needsRereview)
    }
}
```

---

## 9. Afterwards

- `./scripts/gen-symbol-index.sh` (new type-free change, but `drifted` /
  `flushCalendarReclassification` are member declarations the index answers for).
- `./scripts/verify.sh --tests` — twice if the symbol index regenerates.
- Backlog: R3's row can gain a note that the snapshot is now *acted on*; the
  drift/re-judge loop is arguably a new row under B8 rather than a change to R3.
