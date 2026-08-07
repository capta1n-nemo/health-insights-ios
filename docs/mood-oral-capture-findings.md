# Mood + oral health capture — the reading, salvaged (2026-08-07)

**Findings from an agent that lost filesystem access before writing code.**
The reading is the expensive half; a retry starts here rather than at zero.
An agent did the full codebase reading for backlog §B5 #37's mood and
oral-health capture, then lost filesystem access before writing a line of code.
Its worktree is clean — no partial edits, no `COMMIT_MESSAGE.txt`. This is the
expensive half, preserved so a retry starts here rather than at zero.

## Can HealthKit supply either without the reader typing?

**Oral health — yes, already, and nothing reads it.**
`HKCategoryTypeIdentifierToothbrushingEvent` is *already* in
`HealthKitService.otherCategoryIdentifiers` (`HealthKitService.swift:270`),
already inside `readTypes`, already ingested into the raw catalogue. **Zero rows
means nothing has ever written one** — Apple Watch writes handwashing, not
brushing; only a smart toothbrush does. So the correct shape is a **promotion,
not a new read**: mirror `SymptomPromotion` (`Models/Symptom.swift:229`) with an
`OralCarePromotion` over `[RawMetricSample]` — pure InsightKit, testable on
Linux. Duration comes free from `RawMetricSample.start`/`.end`.

**Mood — no, not today.** `HKStateOfMind` is neither a quantity nor a category
type, so it cannot arrive through the raw lane at all. It needs
`HKObjectType.stateOfMindType()` and its own `HKSampleQuery`, and is requested
nowhere. ⚠️ **Deployment target is iOS 18.0** (`project.yml`) and `HKStateOfMind`
is iOS 18.0+, **not 17** as commonly stated — so no availability guard is
needed. `RawFieldGrouping.swift:122` already maps a `"HKStateOfMind"` string to
`.mind`, but nothing produces it: a dangling mapping, not a read path.

## Both are `DataDomain`s, not `MetricType`s

A mood entry is a date plus a signed valence **plus** a kind
(momentary/daily), labels and associations — a metric row cannot hold the last
three, and they are the part a reader would actually look at. Oral care is a
dated event with a duration and a kind. Both are *shapes* under the
`DataDomain` header rule.

Consequences: **no `chartStyleIndex` is taken** (so the collision hazard that
has bitten three times today does not apply here at all) and **no
`MetricExplainer` arm is needed**. The every-data-entry-has-a-description rule
is met by an explainer section on each domain page, sourced from constants in
InsightKit so the wording stays testable.

## ⚠️ The `cardRequirement` problem — and why the obvious answer does not compile

`.offeredAndPrompted` implies `mustBeOfferedOnACard == true`, and
`InputKindTests.testEveryInputACardTakesIsOfferedByThatCardsViewAndAdd` then
requires a shipped model's `contributions` to offer it. **No card reads mood or
oral care**, and the Mental Health card is deliberately behaviour-only —
`MentalHealthModel` exists *because* the mood surfaces were empty. Putting mood
on it would claim a sensitivity the model does not have, which is the exact
objection already recorded against `.holiday`.

Two honest options:

- **(a) `.settingsOnly(reason)` for both**, following the holiday precedent —
  but no nudge ever, which is how a capture stays at zero rows and the backlog
  row silently re-opens.
- **(b) A fourth `CardRequirement` case, `promptedOnly(String)`** — no card, but
  still a dismissible "Improve your health" row. **This is what the reader's
  rule actually says**: the fourth clause about never-used inputs is textually
  independent of the "on a card" antecedent. One file's blast radius
  (`InputKind.swift`'s two derived switches), and it retires the conflation
  that already forced the wrong-shaped answer for holidays.

The agent had settled on **(b)**, and the reasoning looks right.

## ⚠️ One unavoidable file conflict

`HealthDataExport.exportKey(for:)` is exhaustive over `DataDomain`, so **a new
domain cannot compile without editing `HealthDataExport.swift`** — plus a field,
an `init` parameter, a `CodingKeys` case and an `encode` line, then
`DataExportView.buildFullExport()` (which `verify.sh` checks passes every label)
and `HealthDataExportTests.fullyPopulated()`. There is no way to add a
`DataDomain` and stay out of that file. Whoever retries must take it or
serialise against any agent that has it.

## Already mapped, so unblocked

`DataTabView`'s two exhaustive switches (`isVisible` :199, `section(for:)`
:476) · the `DomainDataScaffold` shape and its `verify.sh` lint · the
`…Sheet`-must-be-in-`AddDataView` lint · `AppModel.reloadLoggedData()` (:231)
and `usedInputs` (:532) · `DataStore`'s schema array (:13–22, where an
unregistered `@Model` silently never persists) · `HolidayLedger`/`HolidayEntry`
as the closest template for both new domains.
