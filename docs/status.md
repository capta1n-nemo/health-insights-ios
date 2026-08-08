# Where we stand

**Generated 2026-08-09 at `d46a81f` by `./scripts/status.sh` — do not edit.**
Every number below is derived: features from `docs/backlog.md` (the one list),
research from each document's own status line. Nothing here is written twice,
so nothing here can disagree with its source.

## The short answer

- **211 delivered** · **14 partly delivered** · **63 not started** · **1 will not be built** (of 289 tracked items)
- Of the 77 still open: **39 can be picked up right now**, 38 are blocked.
- **You asked for 124 things in your own words. 103 are delivered; 21 are not.**
- Research: **23 documents** — 16 complete, 3 superseded, 2 partial, 1 stopped, 1 scoped.

---

## 1. What you asked for and have NOT got

These are the rows carrying an explicit `ask` marker — things you said, in your
own words, that are not finished. This is the list to read first.

| Item | What | Tier | Waiting on |
|---|---|---|---|
| `K1` | A correction to a past day cannot move the radar's headline or its hit rate | `hard` | — |
| `B19` | The Energy card has no calibration — five invented constants set its whole range | `ultra` | — |
| `B16-3` | Description (line 3): an AI summary of the whole card | `design` | decision |
| `B11-3` | Estimated sickness, which the reader can correct | `build` | needs:B11-2 |
| `B11-5` | The learning loop — and the reader is explicit about scale | `build` | needs:B11-3 |
| `B2-18` | Stress Tracking "like Oura" | `build` | needs:N1 |
| `L1` | Report grouping and specimen | `build` | — |
| `L2` | Labs as trendable series (`LabSeries`) | `build` | — |
| `L3` | The Face ID gate for infection and STI results | `build` | needs:K10 |
| `L4` | Batch import of many PDFs at once | `build` | needs:K12 |
| `L7` | The split chart: systolic over diastolic, each with its own bands | `build` | needs:L6 |
| `Q12` | Write-back to Apple Health | `build` | — |
| `B11-8` | Weightings | `hard` | — |
| `L5` | The grounding expansion — the "update cholesterol too" half | `hard` | — |
| `R60` | Seven research briefs commissioned 2026-08-07 evening — collect their outputs | `ultra` | — |
| `B2-17` | Cycle tracking — a whole fifth tab | `build` | decision |
| `B5-37` | Daylight/UV, spirometry, mindfulness, mood, oral health, falls | `build` | decision |
| `B11-7` | The fake-sick-day problem — the reader's own scientific objection, and the inversion | `ultra` | decision |
| `J11` | Two of the cycle brief's four streams never ran | `ultra` | — |
| `L6` | The blood-pressure engine, and the gate that stops it printing a number | `ultra` | — |
| `N1` | Stress, done properly | `ultra` | — |

## 2. Blocked, and by what

Nothing here is blocked on effort. Each group needs a different unlock.

### **Your phone** — only you can close it; a simulator cannot — 16

| Item | What | Tier | Waiting on |
|---|---|---|---|
| `D16` | Score history is empty for five cards | `mech` | phone |
| `C11` | Nothing has been seen with real calendar data in it | `build` | phone |
| `F1` | Resting Heart Rate page cross-device defect | `build` | phone |
| `B2-39` | Verify Travel drain and Work impact against real calendar data | `mech` | phone |
| `D9` | Cold-launch time against the real 320,913-row record is unmeasured | `mech` | phone |
| `F2` | Body Composition after the hatch change | `mech` | phone |
| `F3` | Split-night proof from the next export | `mech` | phone |
| `F4` | The ingestion pipeline | `mech` | phone |
| `F5` | The cards on the phone | `mech` | phone |
| `F6` | Phase 1 and Phase 2 sections | `mech` | phone |
| `F8` | Screen Time bar measurement | `mech` | phone |
| `J2` | MetricKit hang diagnostics have never been observed delivering | `mech` | phone |
| `F7` | Heart Health on a young profile | `hard` | phone |
| `F9` | The share-sheet action extension (parked on signing) | `build` | phone |
| `I8` | Barcode scanner with on-device lookup (Open Food Facts / USDA) | `build` | phone |
| `I9` | Camera + LiDAR guided body scan | `build` | phone |

### **Your call** — a question is waiting on you — 9

| Item | What | Tier | Waiting on |
|---|---|---|---|
| `K2` | A stated *severe* illness can never reach `.strongSigns` — the clause saying it can is dead | `hard` | decision |
| `B16-3` | Description (line 3): an AI summary of the whole card | `design` | decision |
| `D29` | The Data tab has grown very long | `design` | decision |
| `D40` | Heart Health's one derived figure is computed in the view, so it cannot be declared | `hard` | decision |
| `K7` | Tag and symptom promotion runs synchronously in `otherSamples.didSet` — deliberate, and the trade wants a ruling | `hard` | decision |
| `B2-17` | Cycle tracking — a whole fifth tab | `build` | decision |
| `B5-37` | Daylight/UV, spirometry, mindfulness, mood, oral health, falls | `build` | decision |
| `D42` | "How you compare" still has no norms for anything a card derives, and cannot | `hard` | decision |
| `B11-7` | The fake-sick-day problem — the reader's own scientific objection, and the inversion | `ultra` | decision |

### **Outside the repo** — a provider, an account, a device setting — 5

| Item | What | Tier | Waiting on |
|---|---|---|---|
| `AC2` | Three things the reader must do on their own devices before daylight or falls can record anything | `mech` | external |
| `I2` | Hume Band direct API | `build` | external |
| `I3` | Ultrahuman | `build` | external |
| `I4` | Garmin | `build` | external |
| `I5` | Fitbit | `build` | external |

### **Another row** — chained behind unfinished work — 8

| Item | What | Tier | Waiting on |
|---|---|---|---|
| `B11-3` | Estimated sickness, which the reader can correct | `build` | needs:B11-2 |
| `B11-5` | The learning loop — and the reader is explicit about scale | `build` | needs:B11-3 |
| `B2-18` | Stress Tracking "like Oura" | `build` | needs:N1 |
| `L3` | The Face ID gate for infection and STI results | `build` | needs:K10 |
| `L4` | Batch import of many PDFs at once | `build` | needs:K12 |
| `L7` | The split chart: systolic over diastolic, each with its own bands | `build` | needs:L6 |
| `J7` | `exertionHours` v2, inside Energy | `hard` | needs:J3 |
| `L8` | The two-tier learning loop, on device and offline | `hard` | needs:L6 |

## 3. Ready to pick up, batched by the model it needs

This is the batching you asked for: a session works one tier, on one model,
without stopping to ask. Waves run in your order — fundamentals, then quick
wins, then the complex work last.

### `mech` — run on **Opus 5 · medium** — 9 items

| Item | What | Tier | Wave |
|---|---|---|---|
| `K4` | A crash-shaped `Dictionary(uniqueKeysWithValues:)` over judgement ids, in three places | `mech` | w1 |
| `K9` | `pairedReadings` never marks a diastolic sample consumed | `mech` | w1 |
| `J1` | A time-zone change clears the caches but does not repaint | `mech` | w2 |
| `J9` | The widget scheme has no standing gate | `mech` | w2 |
| `K10` | `Support/Info.plist` has no `NSFaceIDUsageDescription` | `mech` | w2 |
| `K8` | Three catalogue gaps the reader's own corpus exposed | `mech` | w2 |
| `D7-a` | 1,583 app-target plain-String prose sites the catalog cannot see | `mech` | w4 |
| `D7-c` | `HealthInsightsWidgets` has no String Catalog | `mech` | w4 |
| `D7-d` | 251 interpolated strings with frozen word order | `mech` | w4 |

### `build` — run on **Opus 5 · high** — 16 items

| Item | What | Tier | Wave |
|---|---|---|---|
| `K11` | `captureBloodPressureOutcome` grades only in-app manual entry, and once per reading | `build` | w1 |
| `K12` | Re-importing a lab report duplicates every value | `build` | w1 |
| `K3` | Correcting a work event to "Sick day" makes the row vanish from the Work impact review | `build` | w1 |
| `K5` | `InstrumentCoverageSection` still walks every sample inside a view body | `build` | w1 |
| `K6` | `AppModel.latest(_:)` filters and sorts the whole record on every call, from view bodies | `build` | w1 |
| `J10` | Worktree agents collide on the one booted simulator | `build` | w2 |
| `D67` | Public holidays are not modelled, so H7's "adjacent to a public holiday" is unbuilt | `build` | w3 |
| `J3` | `AlertnessModel` belongs to the Sleep card, once, in InsightKit | `build` | w3 |
| `J5` | Oura's `daily_stress`/`daily_resilience` belong to Sustained load, not Energy | `build` | w3 |
| `L1` | Report grouping and specimen | `build` | w3 |
| `L2` | Labs as trendable series (`LabSeries`) | `build` | w3 |
| `L9` | Screen time is data-limited; the screenshots are not | `build` | w3 |
| `Q12` | Write-back to Apple Health | `build` | w3 |
| `D7` | English only | `build` | w4 |
| `D7-b` | InsightKit has no `defaultLocalization` and 3,276 prose strings | `build` | w4 |
| `D8` | No widgets, Live Activities or watch target | `build` | w4 |

### `hard` — run on **Opus 5 · xhigh/max** — 7 items

| Item | What | Tier | Wave |
|---|---|---|---|
| `J6` | Readiness has six weights and no source for any of them | `hard` | w1 |
| `J8` | The weight registry: seven surfaces read the nightly triad, uncounted | `hard` | w1 |
| `K1` | A correction to a past day cannot move the radar's headline or its hit rate | `hard` | w1 |
| `B11-8` | Weightings | `hard` | w3 |
| `J4` | `SubstancePrior` per class, replacing the flat 18-hour window | `hard` | w3 |
| `L10` | One lab-confirmed infection date: validate the radar, do not retrain it | `hard` | w3 |
| `L5` | The grounding expansion — the "update cholesterol too" half | `hard` | w3 |

### `ultra` — run on **Opus 5 + ultracode** — 7 items

| Item | What | Tier | Wave |
|---|---|---|---|
| `B19` | The Energy card has no calibration — five invented constants set its whole range | `ultra` | w1 |
| `R60` | Seven research briefs commissioned 2026-08-07 evening — collect their outputs | `ultra` | w3 |
| `J11` | Two of the cycle brief's four streams never ran | `ultra` | w4 |
| `L11` | The full constant sweep — the remainder after `J6`, `J8` and `B19` | `ultra` | w4 |
| `L6` | The blood-pressure engine, and the gate that stops it printing a number | `ultra` | w4 |
| `N1` | Stress, done properly | `ultra` | w4 |
| `R57` | Core ML personal anomaly detection once enough history exists | `ultra` | w4 |

## 4. Partly delivered — what is missing on each

A part-done row is the most dangerous kind, because the feature *exists* and
looks finished. The row's prose in `docs/backlog.md` says what is missing.

| Item | What | Tier | Waiting on |
|---|---|---|---|
| `F2` | Body Composition after the hatch change | `mech` | phone |
| `F3` | Split-night proof from the next export | `mech` | phone |
| `F6` | Phase 1 and Phase 2 sections | `mech` | phone |
| `F7` | Heart Health on a young profile | `hard` | phone |
| `F9` | The share-sheet action extension (parked on signing) | `build` | phone |
| `B11-8` | Weightings | `hard` | — |
| `D40` | Heart Health's one derived figure is computed in the view, so it cannot be declared | `hard` | decision |
| `R60` | Seven research briefs commissioned 2026-08-07 evening — collect their outputs | `ultra` | — |
| `B2-17` | Cycle tracking — a whole fifth tab | `build` | decision |
| `D7` | English only | `build` | — |
| `D8` | No widgets, Live Activities or watch target | `build` | — |
| `I9` | Camera + LiDAR guided body scan | `build` | phone |
| `D42` | "How you compare" still has no norms for anything a card derives, and cannot | `hard` | decision |
| `N1` | Stress, done properly | `ultra` | — |

## 5. Delivered

211 items. Listed by stream so a gap is visible against its
neighbours; the commit for each is in its row in `docs/backlog.md`.

- **calendar** (28) — `AC1` `B11-6` `B2-15` `B2-16` `B21` `C1` `C10` `C2` `C3` `C4` `C5` `C6` `C7` `C8` `C9` `D41` `H1` `H2` `H3` `H4` `H5` `H6` `H7` `I1` `N2` `R1` `R2` `R3`
- **pipeline** (22) — `D17` `D23` `D24` `D26` `D44` `D52` `D54` `D55` `D57` `D58` `D62` `D68` `D69` `J12` `K16` `K17` `K19` `P27` `P36` `P38` `P5` `Q11`
- **newcards** (21) — `B1-1` `B1-13` `B1-15` `B1-16` `B1-4` `B1-5` `B1-6` `B1-7` `B1-9` `B3-22` `B4-26` `B5-27` `B5-29` `B5-33` `B5-34` `B5-35` `B9-1` `D1` `D18` `D21` `S6`
- **rules** (18) — `AC3` `D14` `D15` `D19` `D30` `D31` `D32` `D38` `D47` `D48` `D51` `D65` `D66` `G-check-1` `G-check-2` `G-check-3` `N3` `P23`
- **sleep** (17) — `B1-3` `B18-1` `B18-3` `B18-4` `B18-5` `B18-6` `B18-7` `B18-8` `B3-20` `B5-30` `D56` `P22` `S10` `S11` `S13` `S5` `S9`
- **chrome** (14) — `B14` `B15-1` `B15-2` `B16-1` `B16-2` `B17` `D12` `D3` `D45` `D53` `D59` `D6` `K15` `S1`
- **transparency** (10) — `B3-19` `B3-23` `B5-38` `D25` `D46` `P24` `P33` `R5` `R6` `S2`
- **data** (9) — `AC4` `B11-9` `D11` `D27` `D28` `D43` `D49` `P31` `Q13`
- **export** (8) — `B20` `D35` `D39` `D50` `D60` `D61` `Q10` `R4`
- **testdebt** (7) — `D33` `D36` `D37` `D4` `D5` `D63` `D64`
- **nutrition** (6) — `B1-10` `B1-11` `D2` `Q8` `R25` `R26`
- **substances** (6) — `B1-14` `B3-21` `B3-25` `P16` `R24` `S7`
- **charts** (6) — `B13-1` `B13-2` `B13-3` `D22` `P20` `S12`
- **capture** (5) — `D13` `I7` `P32` `Q6` `R16`
- **labs** (5) — `B3-24` `I6` `K13` `K20` `Q7`
- **radar** (5) — `B1-2` `B5-36` `R33` `S3` `S4`
- **sickdays** (5) — `B11-1` `B11-2` `B11-4` `K18` `R28`
- **screentime** (4) — `B10-1` `B10-2` `B18-2` `B9-2`
- **tags** (4) — `B12-1` `B12-2` `B12-3` `K14`
- **bp** (3) — `B1-8` `B5-28` `P15`
- **devices** (3) — `D20` `D34` `S8`
- **bodyscan** (2) — `Q15` `R20`
- **stress** (1) — `B1-12`
- **cycle** (1) — `B5-31`
- **integrations** (1) — `D10`

## 6. Will not be built

Kept on the list with the reason, so it is never silently re-proposed.

| Item | What | Tier | Wave |
|---|---|---|---|
| `B5-32` | Meal-to-outcome / TDEE / intake-driven anything | `build` | w4 |

## 7. Research

Each document's state is declared inside it, so this table cannot go stale.
**`refuted` and `superseded` matter most: do not build from those.**

| Document | State | Lines | What it concluded |
|---|---|---|---|
| [`accessibility-research-2026-08-07.md`](accessibility-research-2026-08-07.md) | **complete** | 450 | 52 accessibility call sites measured; the radar can take the real VoiceOver chart rotor, BodyMeshView is a hard null, and the app has zero Dynamic Type armour |
| [`bp-engine-design-2026-08-09.md`](bp-engine-design-2026-08-09.md) | **complete** | 282 | design of record for L6–L8 and the Wave 3 retraining sweep L9–L11; the sitting and both dedupe defects shipped, the engine itself is designed and NOT built, and its acceptance gate fails on today's data by design |
| [`cuffless-bp-research-2026-08-08.md`](cuffless-bp-research-2026-08-08.md) | **complete** | 638 | predictive cuffless BP is a **no** on published evidence and on the reader's own cuff readings; the card-experience half carries buildable recommendations |
| [`cycle-failure-modes-research-2026-08-07.md`](cycle-failure-modes-research-2026-08-07.md) | **complete** | 162 | who wearable cycle inference fails for — pregnancy produces the same luteal shift, sustained, which is the finding that constrains the whole feature |
| [`energy-design-v2-2026-08-08.md`](energy-design-v2-2026-08-08.md) | **complete** | 751 | design of record for B19 — all eleven fatal v1 findings fixed and every carried-over number recomputed. Designed, NOT built; §3.2 blocks code until Ingre 2014 is transcribed |
| [`gap-hunt-research-2026-08-08.md`](gap-hunt-research-2026-08-08.md) | **complete** | 724 | twelve ranked findings no backlog row covered, each with measured counts and an honest feasibility |
| [`illness-detection-evidence-2026-08-07.md`](illness-detection-evidence-2026-08-07.md) | **complete** | 122 | 28 studies — more critical than the press coverage and, in two places, than this app's own design; constrains the symptom radar and §B11 |
| [`mental-health-research-2026-08-08.md`](mental-health-research-2026-08-08.md) | **complete** | 671 | sources, derivable data points and the psychiatric-medication ask, against a topic no prior run had covered |
| [`nutrition-bootstrap-research-2026-08-08.md`](nutrition-bootstrap-research-2026-08-08.md) | **complete** | 677 | what Nutrition and Metabolism can honestly show from data already held, inside §B5 #32's standing refusal |
| [`signal-audit-2026-08-08.md`](signal-audit-2026-08-08.md) | **complete** | 946 | every card against every signal — the app's most-looked-at number is its least-justified; produces no visible change, which is the point |
| [`sleep-debt-research-2026-08-07.md`](sleep-debt-research-2026-08-07.md) | **complete** | 261 | there is no defensible individual sleep-need estimator from free-living wearable data — an open problem, not a search gap; the honest section is deviation-from-your-own-typical |
| [`stress-design-v2-2026-08-08.md`](stress-design-v2-2026-08-08.md) | **complete** | 642 | design of record for N1 — accepts the reviews and rules the daytime half ships as a rendering with no daily figure. Designed, NOT built; five reader decisions (V1–V5) open |
| [`tag-mapping-research-2026-08-07.md`](tag-mapping-research-2026-08-07.md) | **complete** | 350 | buildable with NLEmbedding rather than Apple Intelligence — but measured at n=0 today, because OuraProvider never requests the tag scope |
| [`test-audit-2026-08-06.md`](test-audit-2026-08-06.md) | **complete** | 419 | all 139 InsightKit test files on seven axes — outdated pins, weak assertions, tautologies, timezone safety, flakiness, coverage holes, structure |
| [`test-results-design-2026-08-09.md`](test-results-design-2026-08-09.md) | **complete** | 212 | design of record for the test-results waves; the value type (K13) and the parser corpus fixes (K20) already shipped, the remaining five slices are designed and NOT built |
| [`uiux-research-2026-08-08.md`](uiux-research-2026-08-08.md) | **complete** | 1056 | UI/UX patterns this app should adopt, every count read out of the worktree |
| [`cycle-algorithms-research-2026-08-07.md`](cycle-algorithms-research-2026-08-07.md) | **partial** | 211 | one of four commissioned streams — algorithms and classic methods covered; device accuracy, competitor claims and the minimum-input question were never run |
| [`uiux-research-2026-08-06.md`](uiux-research-2026-08-06.md) | **partial** | 70 | stopped mid-run; superseded in substance by the 2026-08-08 run, kept for the parts that run did not revisit |
| [`energy-design-2026-08-07.md`](energy-design-2026-08-07.md) | **superseded** | 1132 | v1 — three hostile reviewers returned `needs-rework` (including a fabricated statistic). **Do not build from this.** Replaced by energy-design-v2-2026-08-08 |
| [`stress-design-2026-08-06.md`](stress-design-2026-08-06.md) | **superseded** | 573 | the original N1 design, superseded twice — by the 2026-08-07 revision and then by v2. **Do not build from this.** |
| [`stress-design-2026-08-07.md`](stress-design-2026-08-07.md) | **superseded** | 966 | v1 — returned `needs-rework` by all three reviewers (pseudo-replication disproved by its own text). **Do not build from this.** Replaced by stress-design-v2-2026-08-08 |
| [`writeback-scope-2026-08-08.md`](writeback-scope-2026-08-08.md) | **scoped** | 216 | Q12 ready-to-build: the writable set is reader-entered values only, a modelled figure is never written back as measured. Unstarted **by the reader's own ruling** |
| [`perf-audit-2026-08-06.md`](perf-audit-2026-08-06.md) | **stopped** | 268 | the agent was killed mid-run and left `PLACEHOLDER-NUMBERS` behind — rescued, incomplete, and **no number in it should be trusted without re-measuring** |

---

*Regenerate with `./scripts/status.sh`. `handover-check.sh` runs `--check` and
a session cannot close while this file disagrees with the backlog.*
