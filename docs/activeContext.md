# Active Context

_A snapshot, not a history — where things stand right now, not everything that
ever happened. Updated by `/handover` at the end of a session._

## Current focus — session 32 (2026-08-09), 9 commits

⚠️ **Read these five first.**

1. **What is on the phone: `d46a81f`, and it is the first Release build.**
   `deploy.yml` had been shipping `-configuration Debug` — the reader's phone was
   running unoptimised Swift, about **3.5× slower on this code** (849 ms vs
   239 ms for the main-actor half of `recompute()` on their own 379,693 samples)
   — while they spent a day reporting hangs. Verified **running**, not merely
   installed, by `./scripts/device-smoke.sh`.
2. ⚠️ **A build shipped that died on launch for every existing install, and
   three separate checks said it was fine.** `LabResultRecord.shapeRaw` went in
   as a non-optional `@Model` column with no default; this repo has no
   `SchemaMigrationPlan`. **The rule it cost: a new stored property on a shipped
   `@Model` is either optional or defaulted. There is no third option here.**
   Now a lint (`scripts/check-swiftdata-schema.sh`, wired into `verify.sh`) plus
   `scripts/device-smoke.sh`, because **"installed" is not "runs"** and
   `deploy-status.sh` can only ever tell you the first.
3. **`D61` is delivered.** The reader supplied a fresh export —
   `schemaVersion 7`, build `0.1.0 (434) · ae10d84` — carrying every
   model-improvement key that was missing. **This was the highest-value blocked
   row on the list and it is now the input to `L6`–`L11`.**
4. **The reader approved a large plan and none of it is built.** It is carried in
   as `docs/test-results-design-2026-08-09.md` and
   `docs/bp-engine-design-2026-08-09.md`, and sliced into rows `L1`–`L11`. ⚠️
   The plan itself lived **outside the repo**; nothing outside the repo survives
   a session.
5. **The open count went 55 → 77 and that is the session working.** Twenty
   findings became rows (`K1`–`K12`, `L1`–`L11`), eight shipped rows were added
   for the record (`K13`–`K20`), and `D61` closed.

```bash
./scripts/backlog.sh --next    # the next batch, and the model it needs
./scripts/backlog.sh --asks    # what the reader asked for and has NOT got
./scripts/status.sh            # regenerate the reader-facing breakdown
```

### What shipped tonight, and what found it

| | Found by |
| --- | --- |
| **`LabValue`** — a result is quantitative / censored / qualitative / not-measured; two results in five in the reader's corpus are not numbers (`K13`, `b7c18b0`) | The reader's own pathology PDFs |
| **`MomentConcept`** — one vocabulary for "a thing that happens to a person"; the Oura tag "Sex" failed to link to "Sexual activity" **four independent ways** (`K14`, `7e5e325`) | **The reader**, from outside: *"I couldn't link it as sexual activity"* |
| **The consistency sweep** — `DataDomainBand`, `InputTopic`, a badge counting only genuinely unanswered items, and a side-effect picker that **proposed three words the app could not read back** (`K15`, `189a5e1`) | **The reader**: *"Do a sweep, I want consistency all over the app"* |
| **The launch crash**, plus a lint and a device smoke test (`K16`, `96b0367`/`2c5f365`/`21dde0c`) | **The reader**, in minutes, on their phone |
| **The hangs** — launch block **13.32 s → 5.25 s**, main-actor hold **849 ms → 113 ms**; the detector itself had never once fired (`K17`, `dbbbd83`) | **The reader**: *"it hangs when I add data, opening cards hangs, the load screen hangs"* |
| **The sick day that stayed green** — three causes, one symptom (`K18`, `dbbbd83`) | **The reader**, then agents on the arithmetic |
| **Release to the phone**, and the install path that broke with it (`K19`, `3a56655`/`d46a81f`) | An agent, while measuring the hangs |
| **The parser vs. a real Australian corpus** — four live misreads, five date sources on a page (`K20`, `d46a81f`) | An agent, pointed at the reader's documents |

### ⚠️ The three lessons worth carrying, because each is a class

- **An instrument that has never fired is not evidence of health.** The hang
  detector reported *detection latency* rather than duration, so every hang
  logged 0.25–0.38 s whatever its size and the 1 s threshold **had never once
  fired** — which is why the 2026-08-06 fix looked like it had worked. Measured
  at the stall's end, the same launch event logs 13.22 s. It also self-oscillated
  at 4 Hz against an idle app, overwriting the reader's whole diagnostics export
  every four minutes. `D69` proved the Thread Performance Checker fires on a
  deliberate fault; nothing had done that for this.
- **A cache emptied by the tap before the one you are timing.**
  `refreshMedicationLevelSamples()` reassigned all 379,693 samples on every
  recompute — its guard asked "was a derivation present", always true for a
  reader on a regimen — so `samples.didSet` wiped every breakdown, render memo,
  score history and derived series. **The caches that make a card open instantly
  were destroyed by the previous interaction.** That is the whole "opening cards
  hangs" mechanism.
- **An edge is not inside the band it opens.** `ReportedIllness.excess` anchored
  a stated illness exactly *on* `someSignsExcess`, which scores exactly 85, and
  every gate reads `>= 85` as quiet — so an ungraded sick day was arithmetically
  "nothing stirring" while the file's own table said "some signs". ⚠️ **The
  identical shape is still live one band up** and is now `K2`: a stated *severe*
  illness scores exactly 50, the `score >= 50` branch takes it first, and the
  clause written to let a severe report reach `.strongSigns` on its own is
  **dead code that its own comment argues for at length.**

### Next session, in order

**Do not work from a list here. Run `./scripts/backlog.sh --next`.**

1. ⚠️ **`K2` needs the reader, and it is the first thing to ask.** A stated
   severe illness can never reach the card's loudest state. `SickDayReportTests`
   pins the current behaviour, so **it is a decision, not a fix** — and the two
   ways out say different things to a person. Their own objection in `B11-7` is
   about *not* over-trusting stated sick days, so do not guess which way they
   want it.
2. **`K1` — the sick-day correction loop's input half.** A correction to a
   **past** day still cannot move the radar's headline or its hit rate:
   `ReportedIllness.evaluate` reads `day: today` only and `SymptomRadarModel.ledger`
   takes no sick days at all. `B11-8`'s real remainder, and `B11-3`/`B11-5` are
   built on it.
3. **The `w1` mechanical batch, all ungated** — `K4` (a `uniqueKeysWithValues`
   that traps on duplicate judgement ids, in **three** files), `K9`
   (`pairedReadings` gives the second of two simultaneous systolics the wrong
   diastolic), then `K3`/`K5`/`K6`/`K11`/`K12` at `build`.
4. **`L1`–`L5`, the test-results waves.** Land `K10`
   (`NSFaceIDUsageDescription`, absent — the first `evaluatePolicy` call crashes
   the app) and `K12` (re-import duplicates every value, 19× worse under batch)
   **before** the features gated on them.
5. **`L6`, and read the constraint before designing anything.** 20 sittings,
   pooled within-sitting SD 9.6 mmHg, **28% of the variance is the cuff** — total
   headroom for every factor combined is about **2–5 mmHg**, and the acceptance
   gate **fails on today's data by design**, so the card prints no number. ⚠️
   The largest accuracy win available is not in the modelling at all: three
   readings per sitting moves irreducible error 7.7 → 4.4 mmHg, more than every
   factor combined.
6. **Still true from last session:** 16 rows are `gate:phone` and iPhone
   Mirroring was declined on 2026-08-08; `J6`/`J8`/`B19` remain the most valuable
   ungated calibration work, and `L11` is deliberately only the remainder after
   them.

---

## Sessions 30–31 (2026-08-07/08), 169 commits

⚠️ **Read these five first.**

1. **There is ONE open-item list: `docs/backlog.md`, read by
   `./scripts/backlog.sh`.** `progress.md` keeps the shipped history; this file
   keeps the current state. Neither records open work. If you find yourself
   starting a second list, that is the mistake this session existed to stop.
2. **`docs/status.md` answers "where do we stand" and is GENERATED.** Run
   `./scripts/status.sh`; never edit the file. It is the reader-facing view of the
   same rows plus a research table each document populates itself.
3. **`R60` is the unblocker, and it is now mostly delivered.** Seven briefs; the
   two `w4` designs (`B19` Energy, `N1` Stress) both have **v2 documents that fix
   every fatal finding of their refuted v1s** and are waiting only on the
   reader's decisions. ⚠️ **Do not read the v1 designs** — `energy-design-2026-08-07`
   and both `stress-design-2026-08-0{6,7}` are marked `superseded` and were
   returned `needs-rework`.
4. **`D63` — the Mac gate is flaky under concurrent agent load**, and it made me
   diagnose an outage wrong twice. Read that row before trusting a red gate.
5. ⚠️ **A merge reverted a shipped outage fix and only a lint caught it.** See
   below; it is the most transferable thing here.

```bash
./scripts/backlog.sh --asks    # what the reader asked for and has NOT got
./scripts/backlog.sh --next    # the next batch, and the model it needs
./scripts/status.sh            # regenerate the reader-facing breakdown
```

**258 rows, 55 open** _(a snapshot taken 2026-08-08 — 289/77 as of 2026-08-09;
never quote a count from this file, run the script)_ — **23 ungated**, and the
other 32 wait on the phone (16),
a decision (7), another row (5) or something outside the repo (4). Ordered `w0`
blockers → `w1` shipped-but-wrong → `w2` quick wins → `w3` builds → `w4` complex.
Every row carries a **tier** naming the model it needs — `mech` (Opus 5 ·
medium), `build` (high), `hard` (xhigh/max), `ultra` (+ ultracode), `design`
(Fable 5). **Say the model out loud when the tier changes.**

### What this session was

The list was consolidated from three to one, and then **~120 rows were closed**
by eight waves of worktree agents. The reader reported five live defects from
their own phone while it ran, and all five are fixed and installed.

⚠️ **The open count went UP at the end (40 → 55) and that is the session working,
not failing.** Fifteen rows were *added* in the final handover from things the
agents found while doing something else — the four `D7-*` localisation
remainders, `J1`–`J11`. A wave that closes rows and reports no new ones has
either done nothing interesting or lost what it learnt.

### The two structural things added at the end

- **`docs/status.md` is generated** (`scripts/status.sh`). The reader asked for a
  status breakdown; the first answer was hand-written, 534 lines, stale within a
  day, and a **fourth list**. Now the feature half derives from `backlog.md` and
  the research half from each document's own `<!-- status: … -->` line, so a
  research report cannot sit on disk without a verdict — 15 of 19 did, which made
  "researched" and "concluded" indistinguishable, with two *refuted* designs among
  them.
- **A tracked transcript or export now fails the gate.** `last_session.md`/`.rtf`
  — 357 KB of RTF session transcript — sat at the repo root untracked and
  **unignored** while this session ran `git add -A` three times. This repo is
  public and holds one person's health data. `.gitignore` covers the shape;
  `verify.sh` content-sniffs the *index*, because a filename is a guess about what
  is inside a file.

### ⚠️ The four defects worth carrying, because each is a class

- **`D62` — the sync never finished.** `performRefresh` **awaited**
  `refreshTagApplicability()` before its completion marker; that walks up to 12
  tags serially, each a fresh `LanguageModelSession`. The reader lost every
  card. **The class: an on-device model call must never be awaited on the path
  that tells the app its data is ready.** Linted.
- **`D59` — a correct fix made a card vanish.** Travel drain was fixed to stop
  saying "Connect your calendar" to a reader who had; the fix set
  `invitesInput: false`, every term of `isWorthShowing` went false, and the card
  disappeared. **The reader then ruled: no card is ever hidden for want of
  data.** `isWorthShowing` is unconditionally `true` now, and the obligation
  moved to the empty state.
- **`D60` — the export carried no score history at all.** It called
  `AppModel.scoreHistory(for:)`, a **lazy view cache** returning `[]` until a
  chart is drawn. **So there were no prediction-versus-actual pairs and the app
  could not learn from itself.** Linted.
- **`D58` — a Swift exclusivity trap aborted the app** on every render of a
  section shipped the same afternoon. `RenderMemo.value` was `mutating`, so it
  held exclusive access across the caller's closure, and one memo nested inside
  another.

### ⚠️ The merge lesson, and it is the biggest one

Eleven branches all added `DataDomain` cases, `InputKind` cases, export keys and
`Schema` entries. An automatic keep-both resolution **spliced them into code
that read plausibly and did not parse** — two `case` lists welded together, the
`Schema` array closed twice, two `syncWarning` defaults.

**And all eleven predated `D62`'s fix, so the merge reverted it.** `verify.sh`
caught it. Without that lint the push would have re-shipped the reader's outage
**with 2,669 green tests behind it**, because no test can see that defect.

**Carry this:** after a multi-branch merge, `grep -rl '^<<<<<<<'` over the whole
tree — not over the file list `git` reported before resolution, which is what I
did and it missed four files. And where a merged array carries a rule
(`DataStore`'s *"a `@Model` not listed here silently never persists"*),
**enumerate the set from source and check it** rather than trusting the merge.

### Next session, in order

**Do not work from a list here. Run `./scripts/backlog.sh --next` and read
`docs/status.md`.**

⚠️ **32 of the 55 open rows are gated on something a session cannot supply.**
Twenty-three are ungated, and most of those are the `J*` findings written at the
very end — real work, none of it reader-blocked. But the *highest-value* items
are all waiting on the reader, so:

1. **Ask for four things in the first message, before writing any code.** Each
   unblocks more than it costs, and each has been waiting a full session:
   - **A fresh export** (`D61`). Theirs is `schemaVersion 4`; every
     model-improvement key landed at 5 and 6 the same day, so the correction and
     grounding data they explicitly asked to learn from **is in no file yet**. This
     is the single highest-value unlock on the list.
   - **The `N1` Stress rulings, V1–V5** (`docs/stress-design-v2-2026-08-08.md`
     §12) — chiefly the central verdict that the daytime half ships as a
     *rendering* with no daily figure. `B2-18` is chained behind it.
   - **The `B19` Energy design** — v2 is build-ready except §3.2, which needs
     Ingre 2014 transcribed before any code (v1 fabricated that constant).
   - **`B16-3`** (an AI card description) and **`B11-7`** (the fake-sick-day
     inversion) — both `gate:decision`, both blocking chains.
2. **The 16 `gate:phone` rows.** ⚠️ **iPhone Mirroring access was requested on
   2026-08-08 and the reader declined it**, so these did not move. Either ask again
   at the start or plan the session without them — do not attempt them silently.
3. **`J3`, `J6`, `J8` — the weight problem, which is now three rows.**
   `signal-audit` found the most-looked-at numbers are the least-justified;
   Readiness has six weights with no source (`J6`), seven surfaces spend the same
   nightly triad uncounted (`J8`), and three of them want one `AlertnessModel`
   that nobody owns (`J3`). This is the most valuable ungated work left.
4. **`D63`** — make the flaky gate say it is a resource problem. Until it does,
   a red gate trains a session to push through a real one.
5. **The `◐` rows** — `D7` (localisation: extraction done, translation not
   started, remainder counted in `D7-a`…`D7-d`), `D8` (widget target compiles;
   blocked on a paid Apple team that can sign App Groups), `I9`/`Q15` residue.

---

## Session 29 (2026-08-06/07), 64 commits

**The reader used the app on their own phone all day and reported defects from
it.** That is new, and it is the most valuable input this project has had: five
of the things fixed below were invisible to tests, to CI and to the simulator.

### ⚠️ Read these three first

1. **The repo moved out of iCloud Drive** — see the section below. Canonical
   checkout is `~/health-insights-ios`.
2. **`docs/illness-detection-evidence-2026-08-07.md`** — 28 studies. It
   vindicates the symptom radar's caution *and* constrains the sick-days
   feature the reader specced (§B11). **Read it before building any illness
   signal.** Prospective PPV is 4–12%; the one RCT's physiological arm returned
   zero confirmed infections; two-thirds of genuine infections produce no clear
   signal at all.
3. **`docs/backlog.md` §B9–§B19** — the reader's 2026-08-07 brief, eleven
   sections, none built.

### What shipped, and what found it

| | Found by |
| --- | --- |
| **The sync hang** — `recompute()` ran the full 18-model pass on the `@MainActor`, measured at **2.36 s over 380k samples**, from **33 call sites**. Now detached behind a generation guard | The reader, on their phone: *"it hangs the UI/UX and the app becomes unresponsive"* |
| **Work impact scores the calendar** — exposure × response, four quadrants, `work-impact-v2`. The calendar gap now carries **21% of the score** | The reader: *"where is that in the weighting section?"* |
| **The review loop** — every axis editable, nothing commits until Save, `Change` un-confirms | The reader, then **verified on their phone before and after** |
| **Every derived figure is a data source** — all 18 cards swept, `.derived(DerivedSeriesID)` carries identity, exports, trends | The reader's instruction |
| **A description on every data entry** — `MetricExplainer` is non-optional now, so a new metric cannot compile without one | The reader |
| **`CoverageGate`** — a withheld figure says what it is waiting for | The reader: *"so users know why things are - or are not showing"* |
| Fitness sections (#34/#35), breathing disturbance (#30), sound exposure (#33), cycle slice 2, B7 identity + holidays, two-tier sharing | Backlog |

### ⚠️ The environment failed twice, and both are worth knowing

**iCloud revoked read access to the whole tree, mid-session.** `EPERM`
everywhere, to the main process and to five separately-spawned agents on their
first call, while `/private/tmp` and `~/HealthSeed` stayed readable and
disabling the sandbox changed nothing. **An iCloud resync does not fix it** —
it is TCC. An hour of work was stranded and `CoverageGate` was rewritten from
scratch into a clone. That clone is now the repo.

**Roughly ten agents died on API stalls or the filesystem loss.** Three had
written real work that had to be hand-rescued from their worktrees; one lost
everything. **The pattern that survived: an agent that only needs the web.** The
two best deliverables of the day — the illness evidence and the watch-capture
research — came from agents with no filesystem dependency at all.

### Next session, in order

**Do not work from a list written here. Run `./scripts/backlog.sh --next`.**
It orders by wave and batches by the model tier each item needs. What follows is
context for the first two batches, not a substitute for the command.

1. **`w0` blockers, all `mech`** — 14 ready. Three are costing work right now:
   `D31` (`.claude/settings.json` allows the hook's `cd` prefix only for the
   Linux path, so the Mac and worktree prefixes prompt), `D32` (concurrent
   worktree agents collide on shared scratchpad filenames — two agents have
   already lost commits), and `AC3`/`D38` (prune this file; it is 4,222 lines
   and read in full at every session start, and the protocol has now instructed
   this **three** times).
2. **⚠️ `AC1` is on a clock.** The calendar-drift patch — 706 lines with tests —
   **is not lost**, contrary to what this section used to say. It survives in
   the *abandoned* iCloud checkout's session scratchpad, and `/private/tmp` does
   not survive a reboot. **Copy it into the repo before anything else touches
   it.** Its anchor is confirmed real: `InsightDetailView.swift:423–429` is a
   `LazyVStack`, so the `.onDisappear` must attach at body level or it fires on
   scroll. It is designed but **never compiled or tested**.
3. **`w1` — things already on the phone that are currently wrong.** The
   screen-time OCR pair (`B10-1` date attribution, `B10-2` a regression, so
   bisect before rewriting), `B13-1` the collapsing chart header, `F1` the
   resting-heart-rate cross-device defect.
4. **`w2` quick wins are genuinely quick.** `B16-2` is one line
   (`Energy.swift:538` is the only interpolated-number headline in InsightKit);
   `B14` is two sites; `B15-1`/`B15-2` are the two states of a chip whose other
   halves already ship.
5. **`AC2` needs the reader, not a build** — three settings on their own devices
   before daylight or falls can record anything, and every day it is not done is
   a day of history that cannot be backfilled.
6. **`B11`'s inversion is constrained, not blocked** — compute and store, never
   surface as a judgement about honesty. `docs/illness-detection-evidence-2026-08-07.md`
   says why.

### ⚠️ Docs debt, now overdue — and now on the list

`activeContext.md` is 4,222 lines across 29 sessions and is read at every session
start. The handover protocol has instructed archiving superseded sections since
2026-08-06 and **it has not been done three times running**. Sessions 24–27
should move to `docs/archive/activeContext-history.md`.

⚠️ **The lesson is the repeat, not the debt.** An instruction that has been
ignored three times is not made to hold by writing it a fourth time — that is
this repo's own rule, and it is why `unbuilt-asks.sh` became a command and why
`backlog.sh` hard-errors instead of warning. This is now `AC3`/`D38` on the one
list, at `w0`, so it surfaces in `--next` rather than in a paragraph.

## ⚠️ The repo moved out of iCloud Drive — 2026-08-07

**Canonical checkout is `~/health-insights-ios`.** The old path under
`~/Library/Mobile Documents/com~apple~CloudDocs/HealthAppLocal/` is abandoned,
still on disk, and **not** kept in step — do not pull it, push from it, or read
its docs.

The trigger was the third iCloud failure and the only unsurvivable one: **a
live session lost read access to the entire tree mid-flight.** `EPERM` on every
path, to the main process and to five separately-spawned agents on their first
call, while `/private/tmp` and `~/HealthSeed` stayed readable and disabling the
sandbox changed nothing — macOS TCC, not sync state, and an iCloud resync does
not fix it. An hour of work was stranded; `CoverageGate` had to be rewritten
from scratch into a fresh clone.

The two earlier failures are recorded below (codesigning refusing iCloud's
extended attributes; 766 MB of build output syncing because `.gitignore` means
nothing to iCloud). **The general shape worth carrying: a working copy whose
access can be revoked by the OS, mid-session, without warning, is not a working
copy.** Cloud sync is for files a human edits, not for a tree a build reads
thousands of times.

Almost nothing in the repo needed changing — the workdir hook already used
`$CLAUDE_PROJECT_DIR`, and `verify.sh`/`simulator.sh` already wrote derived
data to `~/Library/Caches/health-insights/`. Only three tracked files even
mentioned the old path, all in prose.

## Read `docs/backlog.md` first (added 2026-08-06)

Every open question, every card ever mentioned, every requested section,
integration and quality gap is on **one flat list** there. It exists because
this file and `progress.md` between them had begun losing things: the roadmap
generator could not see a nested item, six symptom-radar rows sat open after
shipping, and the reader had to ask three separate times for work that was on
no list they could find. **Nothing is ever deleted from the backlog, only
marked.**

## Three things this session's own work got wrong, found by auditing it

Recorded because each is a *class*, and none of 1,626 tests could fail on any.

1. **A comment claimed the opposite of its code.** The CUSUM's status branch
   said the accumulated path could escalate without two leaning signals. It
   cannot — memory's excess caps at exactly `strongSignsExcess`, `ScoreCurve`
   returns an anchor exactly at its input, that anchor is (3.3, 50), so
   `score >= 50` always wins first. The code was the intended design; the
   comment overclaimed. **A comment describing behaviour is still not evidence
   of it.**
2. **A guard that skips is a guard that hides.** `ScoreAttributionTests` took
   `ContributorsFixture`'s 20-day default while every other caller passed 130,
   and each sweep opens `guard result.score != nil else { continue }`. Sustained
   Load (118 days) and Gait (393) were skipped by all three sweeps from the day
   they shipped, in silence. The default is 130 now and
   `testEveryRegisteredModelScoresOnTheFixture` asserts the set being examined
   is the set that exists.
3. **The handover gate had a blind spot in itself.** `roadmap-table.sh` matched
   `- [ ] ` at column 0, so one nested open item was invisible to the table, to
   `--check`, and therefore to the gate meant to stop a session closing on a
   stale roadmap.

## Six things established on 2026-08-05 (afternoon), in priority order

**1. `docs/progress.md` was wrong about six data domains, and the correction is
the important part.** It listed eight unbuilt domains as "arriving" and "a
promotion plus a reader, not new plumbing". Measured against the reader's own
export — 158 raw identifiers, 320,913 rows — **daylight, UV, spirometry, inhaler
use, mindful minutes, mood, menstrual flow, sexual activity, falls and
toothbrushing have zero rows. Not thin: absent.** "Arriving" had been inferred
from the read request in `HealthKitService` and never checked against a row
count. **The general rule, now written beside that list: before writing "already
arriving" about a data source, count its rows in the last 90 days.**

**2. The densest signal in the record was in the raw pile, unread, for a year.**
`walkingSpeed`, `walkingStepLength`, `walkingDoubleSupportPercentage` — 1,093
days each, 91 of the last 90, 366 of the last 365, from the iPhone alone. Now
`GaitInsight`, which decomposes a speed change into step length versus cadence
(speed = length × cadence exactly, so the shares are an identity and not a fit).
**Worth generalising: the raw catalogue is where the next card comes from, and
the way to find it is to count coverage per identifier, not to read names.**

**3. The radar's score was wrong in both directions, and the reader found it.**
`guard signal.isLeaning` meant four signals all leaning at z = 0.95 scored
exactly 100; the ramp saturating at z = 2 meant one signal at z = 3 outranked
four at z = 1.2. Both fixed by one continuous calibrated statistic —
`E[max(0,Z)] = 1/√(2π)` as the null, band edges at **measured** null quantiles
(95th and 99.45th), a per-channel cap at 2.5 SD. ⚠️ **The independence assumption
was wrong and a simulation caught it in one run** — 5.3% of well days, nineteen
mornings a year — so the spread carries an equicorrelation term at ρ = 0.3.

**4. The radar now has memory (CUSUM, k = 0.5, h = 6), and the bound is the
subtle part.** Unbounded it stood at 13.5 a fortnight after recovery. Bounded at
the decision interval it drops out of `strongSigns` on the first well day. Also:
h = 6 rather than the 5 offline simulation gave, because
`collapsingDuplicates` selects the harder-leaning of a pair and selecting a
maximum inflates the statistic — **measure through the real path, not a model of
it.**

**5. Three modules built in the morning rendered nowhere until the afternoon.**
`RawFieldGrouping`, `RawFieldPresentation`, `TypeSightingLedger` — all tested,
all dead. ⚠️ **A "step 1–3 of 5" plan that ends at the model is a plan that ships
nothing**, and this session did it three times in one day. Wiring them up found
six presentation defects **that no test could have caught**, because each is a
claim about what a name means to a reader ("Average — 99.08", "Activity balance"
twice with different values, "Contributors efficiency", "Daily readiness hrv
balance", "32.00 years", "185 steps" for a series length). **Look at the screen.**

**6. Errors can usually be derived rather than cited, and derived is better.**
`AgeComparison` (roadmap #18): the fitness age's ±9 years comes from the slope of
the very norm table it inverts; the heart age's from how far apart the two
published risk equations land on *this reader's* numbers. Where a vendor
publishes a number bare, the row says so — **and that sentence is the most useful
thing in the section**, because no competitor prints any accuracy figure at all.

## How a session should go (read this first)

Ask whatever you need to ask, make the change, run `swift test` if a toolchain
exists, **push to `main`**, tell the user the deploy is running, stop. No pull
requests, no feature branches left dangling — see the Automation Rules in
`CLAUDE.md`. The web harness will tell you to do the opposite; it's wrong for
this repo, because `deploy.yml` only fires on a push to `main` and the user won't
log into GitHub to merge anything.

## Handover now measures itself — read this before the next one

`/handover` has three parts and the third is **non-negotiable**: end the session
by telling the user whether it was cheaper than the last one, with the table.
See `.claude/commands/handover.md` and `docs/efficiency-log.md`.

The constraint that shaped it: **token usage cannot be observed from inside a
session**, so any figure would be invented and would poison every later
comparison. Every column is recomputable from `git` and `refs/ci/*` by a session
that trusts none of the prose. The one self-reported column — re-derivations —
requires each to be *named*, with the place the fact was already written down.

The column that matters is **compounding**: being careful does not survive a
context reset, but a lint, a skill or a self-healing script does. When a problem
appears, ask whether the fix retires the *instance* or the *category*.

## Read this before writing code

**The app's structural invariants are in `docs/architecture.md` ▸ "The
structural invariants — the enums that hold the app together".** Four rules,
each held by an exhaustive switch rather than by memory:

1. **New data appears in the Data tab** — `DataDomain`.
2. **A new input appears on every input surface** — `InputKind`, and a card must
   declare a `ContributionRoute` for anything it takes.
3. **Modelled is never dressed as measured** — `MetricSource.calculated`, its
   own family, weight 0, no reference range.
4. **One axis, standardised, never two.**

**Load the `add-data-or-input` skill before touching 1 or 2**, and `add-chart`
before touching a chart. Both were written from shipped defects.

## ⚠️ The gate lied, and it had been lying. Fixed 2026-08-02.

**`./scripts/verify.sh --tests` — the command CLAUDE.md mandates before every
push — exited 0 on a tree that plain `./scripts/verify.sh` exited 1 on.** The
mandated mode was the *weaker* of the two. It let a `\.0` tuple key path reach
`main`, red CI, on a commit whose gate had printed `Clean.`

The mechanism: the test block's runner-artifact recovery set `fail=0` to undo a
false failure it had just diagnosed (`swift test --parallel` intermittently
exits non-zero with every test passing). But `fail` is shared with **every lint
above it**, so any lint failure was erased whenever the serial re-run passed.
The lint had fired, correctly, and was wiped a second later.

**The general shape, worth more than the instance: a recovery may only undo the
thing it diagnosed.** A recovery that clears a flag it does not own silently
forgives everything else that set it. The test run now has its own `testfail`,
and `verify.sh` **checks itself** for a stray `fail=0` — the needle assembled
from two string pieces so the check's own source cannot match it, which is the
only way a self-check can be made honest rather than made to pass.

Two smaller things landed with it:

- **`ban` now skips comment lines.** This repo's house style is that every fix
  records the shape it replaced in a doc comment, so ban patterns are quoted, by
  design, in the files that no longer commit the sin. Documenting a fix tripped
  the lint that motivated it, twice in one session, and the only way out was to
  describe the mistake less clearly. A comment cannot be a compile error.
- **CI's `lint` job runs plain `verify.sh`**, which is why CI caught what the
  local gate missed. That is a good property — keep it.

## Sessions 24–28 — archived 2026-08-07

**Moved to [`docs/archive/activeContext-history.md`](archive/activeContext-history.md), not deleted.**
3,430 lines of session-24-to-28 narrative sat under a second, stale
`## Current focus` heading, plus a superseded "Immediate next steps" section
whose own text said the question it asked no longer needed asking.

⚠️ **The instruction to do this was issued by the handover protocol three times
and ignored three times** — which is why it is `AC3`/`D38` on the backlog rather
than a paragraph in a protocol. This file is read *in full* at every session
start, so every superseded narrative left in it is a tax on every future
session.

The conclusions worth carrying forward were already lifted out of that block
into the standing sections above and into `docs/backlog.md`'s rows. If you need
the reasoning behind a decision from that period, the archive has it whole —
and `docs/progress.md` carries the shipped record with what found each thing.

## Two regressions I shipped, and what they cost

Both were caught by the user's screenshots, not by CI, and both have the same
root cause: **the rule lived in the view layer where no test could reach it.**

1. **Two identical reds.** "Draw only the anomalous ones" is not by itself a
   small number — thirteen vitals with nine departing is an ordinary week, so the
   ninth line wrapped onto a hue already in use.
2. **Steady signals drawn as notable**, contradicting the legend one line below.

Fixed by moving the rule into `InsightKit/Sources/InsightKit/Presentation/OverlaySelection.swift`
and testing it against the screenshot's own shape. **Rule worth keeping: if a
piece of logic decides whether two things can look alike, or whether a number is
right, it belongs in InsightKit.** The app target has no test target — anything
that lives there is verified only by eye.

## The Oura scope answer (don't re-derive this)

Oura returns **401, not 403, for a missing scope** — it reserves 403 for a
lapsed subscription — and names the scope in the RFC7807 `detail` of the body.
Neither its published scope table nor its OpenAPI spec (v1.37, eight scopes)
documents which endpoint needs which. Learned from its own error text:

| Collection | Scope |
| --- | --- |
| `daily_resilience` | `stress` |
| `daily_cardiovascular_age` | `heart_health` |
| `vO2_max` | `heart_health` |

Also: Oura's developer console moved to `developer.ouraring.com/applications`
(the OAuth authorize/token endpoints did **not** move). And Oura does **not**
reliably return `scope` on the OAuth callback, despite documenting that it does.

## Recent architectural choices worth knowing

- **One quantity drawn over another is a hatch, never a blend.** This is the
  standing approach — `Theme.hatch(light:dark:_:)`, worked example in
  `BodyCompositionTrendChart`. A translucent fill *mixes*, and the mix is a third
  colour that means nothing and is frequently nowhere near either parent: blue
  over red is purple at every ratio, because it is colour arithmetic rather than
  a tuning problem. A hatch keeps both colours because every pixel is one of
  them. Two corollaries earned the hard way: **draw the host band whole and paint
  over it** — carving the overlaid share out as its own slice removes the host's
  colour from that stretch, so nothing reads as underneath and no hue can fix it —
  and **the overlaid quantity contributes no mass to the stack**, so it wants an
  `AreaMark(x:yStart:yEnd:)` between two cumulative heights, with the span
  computed in InsightKit where it is testable.
- **When a colour looks wrong, measure the composited pixel before choosing
  another one.** Five rounds went into the water colour by eye; the measurement
  (rgb 126, 88, 121 — red and blue near-equal, green suppressed) named the cause
  in one step. Generalised: when a visual fix keeps landing in the same wrong
  place, check whether the mechanism can produce the target at all before picking
  another value for it.

- **Choose a representation instead of propagating a special case.** `.sleepOnset`
  could have been a clock hour with circular statistics, and then `Baseline`,
  every regression and every chart would have had to know which metric they were
  holding. Moving the branch cut to midday made the linear machinery correct by
  construction. When one value type would make everything downstream an
  exception, look for the encoding that makes it not one.
- **"No provider gives us X" is a claim about the parsers.** Circadian consistency
  sat blocked for sessions on a signal that was in every payload and was being
  discarded at ingest. Before recording something as blocked on a missing signal,
  open the payload.
- **Merge overlapping spans before shading them.** Three logs in a morning drawn
  as three translucent rectangles compound into a darker band, which encodes *how
  many* in a channel meant to say only *whether*. Same class of error as two
  identical reds: an encoding that carries information nobody intended.
- **A generic lint beats a maintained list of lints.** The exhaustive-switch check
  named each switch individually and therefore only caught the ones somebody had
  remembered. Swift's own rule — a `default:`-free switch names every case — is
  enough to check the class rather than the instances.
- **Don't ask for a permission you don't use.** Oura's `heartrate` scope was
  requested for months and never called. Removing it costs a comment naming the
  three steps to reinstate.

- **A shared reader beats a shared convention.** Every insight "knew" it should
  read a daily, de-duplicated, windowed value; every insight wrote its own and
  got it wrong differently. `VitalReader` is the convention made a type. When you
  find the same four-line pattern in five files with five bugs, extract it —
  don't document it.
- **Freshness is reported, not enforced.** `VitalReading.isFresh` is a fact; what
  it *means* is the insight's call. Readiness drops a stale component (it's a
  claim about today); Heart Health keeps one (VO₂max updates every few weeks by
  design). A single global staleness rule would have been wrong for one of them.
- **Presentation logic that can be wrong belongs in InsightKit.** The app target
  has no test target. `OverlaySelection` and `MetricPalette` decide whether two
  lines can look alike — that is a correctness question, not a styling one, and
  both regressions this session came from having it in the view.
- **A tri-state flag beats a Bool when "we didn't check" is a real state.**
  `InsightDriver.isNotable: Bool?` — `nil` means the insight doesn't draw the
  distinction, which must not render as "everything is fine".
- **Two copies of a clinical threshold need a test binding them.** The
  blood-pressure bands exist in `Category.of` (classify) and `systolicRange`
  (shade). `PressureBandTests` sweeps every value from 80 to 210 and asserts each
  lands inside the band its own classifier assigned it.
- **Encoding that is technically safe can still be practically wrong.** The
  (hue, dash) pair was collision-free by construction and validated with a
  colour-blindness tool. It still failed, because dash carries a *meaning* to
  readers — "estimated / missing" — that no separation metric measures. Check
  what an encoding says, not just whether it's distinguishable.
- **Providers fetch bytes; the pipeline decides what they mean.** `SyncedData`
  now carries `payloads: [IngestPayload]` alongside samples. A provider's typed
  parser contributes only the handful of fields it has *unit and semantic*
  knowledge about; everything else in the document is the pipeline's job. That
  inversion is why a field Oura added this morning reaches the vitals layer with
  no code change.
- **`RawValue` is `number | text | flag`,** encoded as a bare JSON scalar. The
  bare-scalar choice is load-bearing: caches written when `RawMetricSample.value`
  was a `Double` decode straight into `.number(...)`, so the migration is free.
  There is a test pinning this — don't "tidy" it into a tagged object.
- **Numeric arrays summarise, they don't explode.** Oura's 5-minute night series
  (`heart_rate.items`, ~200/night) becomes count/min/max/mean/first/last.
  Expanding literally would add ~40k samples per sync for data Apple Health
  already mirrors. `FlattenPolicy.arrayStrategy = .expand` is the per-field
  switch if a series ever earns it. Chosen deliberately with the user.
- **Promotion is data, never inference.** `PromotionRuleSet` maps
  path/leaf/suffix → `MetricType` with unit conversion. A field that merely
  *looks* like a known vital (alias match, no rule) is catalogued and logged as
  a **proposal**. This is what stops a provider renaming a field from silently
  rewiring an insight. Also chosen deliberately with the user.
- **Empty ≠ unknown.** `OAuthTokens.grantedScopes` stores `nil`, never `[]`, and
  **nothing may withhold a request on the strength of it.** A build that skipped
  collections whose scope looked absent read "provider didn't say" as "granted
  nothing" and suppressed the very sync that would have proven the fix worked.
  The provider's own 401 is the only authority.
- **A scope 401 is never retried.** `ProviderAPIError.missingScope` recognises
  Oura's phrasing; a fresh token carries the same grant, so retrying only spends
  a single-use refresh token and logs each failure twice. Refreshes are coalesced
  through one in-flight `Task` and disabled for the rest of a sync after a
  failure, because Oura's refresh tokens are single-use — nine endpoints each
  refreshing on their own 401 would revoke the grant outright.
- **Vascular age is a second opinion, not an input.** Oura's estimate became its
  own `MetricType.vascularAge` rather than being merged into `HeartAgeInsight`'s
  own calculation. Two models built on different inputs disagreeing is
  information; averaging them away is not. VO₂max went the *other* way — Oura's
  joins the existing `.vo2Max` metric as another source, matching how heart rate
  and weight already work.
- **Ages, not just percentages.** `HeartAgeModel` inverts SCORE2/ASCVD over age
  against an optimal-risk-factor reference person (the published Framingham
  vascular-age method). No new equation — the shipped ones read backwards. Each
  engine is inverted **only inside its own validated band** (SCORE2 40–69, ASCVD
  40–79) and returns `isCapped`, which the UI voices as "79 or older" rather than
  printing an extrapolated number. `FitnessAgeModel` does the same trick on the
  VO₂max norm table `HeartHealthScore` already scores against, so the two can't
  disagree about "average for your age".
- **Lifetime risk was deliberately not faked.** The roadmap asked for lifetime
  framing. Nothing here is validated past 79 and compounding decades of 10-year
  risk would invent a number, so `HeartAgeModel.projection` runs the same
  equations at future ages they *are* validated for, labelled "if today's numbers
  hold". If a real lifetime figure is wanted it needs a different published model
  (JBS3 has one) — that's new work, not a tweak.
- **A trajectory is judged against ageing, not zero.** `VO2Trajectory` compares
  the least-squares VO₂max slope to the norm line's own slope at that age, so
  holding level scores *above* mid-dial. `netPerYear` is that comparison;
  `fitnessYearsGained` is the trajectory's effect on fitness age alone. Keep them
  separate — adding them double-counts.
- **`MetricSubject`** (not raw `MetricType`) is what a detail screen addresses,
  because blood pressure is inherently a systolic/diastolic pair.
  `MetricDetailView` keeps `init(metric:)` for backward compatibility; prefer
  `init(subject:)` when the subject might be blood pressure.
- **`ScrollableMetricChart`** owns all pan/zoom/scrub/axis-scale logic for every
  chart in the app. `MultiSourceChart` and the blood-pressure chart both wrap it.
  Any new chart type should too, rather than growing its own copy.
- **Swift Charts `Chart3DContent` overload-resolution hazard**: on the current
  SDK, a `RuleMark`/`AreaMark`/`BarMark` chain built without an explicit
  `some ChartContent` return type can silently resolve to 3D chart content and
  lose modifiers like `.lineStyle`/`.annotation`. Always give mark-building
  helpers an explicit `-> some ChartContent`. This caused two CI failures in one
  session — a known trap, not a one-off.
- **Never start a continuation line with `...`** in Swift — it parses as a
  standalone prefix `PartialRangeThrough`, not a continuation of the range above.

## The sandbox has a Swift toolchain now — use it

This section used to say the opposite, and that was the single most expensive
false belief in the repo: it meant every logic error was found by pushing and
waiting ~90 s for CI.

`InsightKit` was always meant to be platform-free, but two Darwin-only
Foundation APIs had crept in (`Measurement.formatted` and `CFBooleanGetTypeID`)
and CI runs on macOS, so nothing caught them. Both are behind
`#if canImport(Darwin)`. **The full suite passes on Swift 6.0.3 / Ubuntu 24.04** — `swift test` prints the count, so it is not repeated here to rot.

```bash
./scripts/verify.sh --tests     # installs the toolchain if absent, then runs
```

The container is rebuilt per session so the toolchain never survives, but the
gate **self-heals**: `verify.sh --tests` bootstraps Swift itself rather than
telling you to. Nothing depends on this document being read. Better still, put
`./scripts/bootstrap-swift.sh || true` in the environment's setup script and it
costs no session time at all — see `docs/deployment.md`.

`xcodebuild` is still macOS-only, so the **app target** is compiled only by CI.
Local green means InsightKit is green: the clinical maths, scoring, baselines
and parsers — which is where the bugs have actually been.

Still worth care, because nothing local checks them: key paths don't work on
tuple elements (`\.volume` on a tuple is a compile error — use `{ $0.volume }`),
and don't shadow a function with a local of the same name. `scripts/verify.sh`
checks the first of those.

Adding a `MetricType` or an `InsightID` case is deliberately load-bearing: both
feed exhaustive switches. **This bit CI again this session** — `.vitalSigns` was
added to the engine and cadence but not to the four switches, so the build broke.
The complete list, verified by grepping for the enum's last case:

- `MetricType` — **eight** switches: `displayName`, `unit` (both in
  `MetricType.swift`),
  **`family`**, **`chartStyleIndex`**, `presentation`, `maxValidInterval` (all
  four in `MetricPresentation.swift`), **`referenceRange`** (also
  `MetricPresentation.swift` — usually `nil`, and the case must say *why*;
  `.sleepOnset` is the worked example), `requiresPositiveValue`
  (`Signals/MetricSanitizer.swift`). `bucketStatistic`, `inSentence` and
  `MetricValueFormatter` are safe — the first has a `default:`, the second is
  derived from `displayName`.
  `colourSlot` and `sharesMeasurementBasis` are **derived**, not switches, so
  they no longer need touching. `chartStyleIndex` must stay contiguous from zero
  (`testStyleIndicesAreContiguousFromZero` pins it) so the metrics most likely to
  share a chart keep first claim on the eight hues.
- `InsightID`: **five switches, not three** — this list was itself stale and is
  now verified. `cadence` (`Insight.swift`), `modelVersion` (`Feedback.swift`),
  `prettyInsight` (`TelemetryOutboxView`), `iconName` (`DashboardView`),
  `colourSlot` (`Presentation/InsightPalette.swift` — *not* `insightTint` in
  `Theme.swift`, which now resolves through it). **Four of the five are
  exhaustive and break the build**: `modelVersion`, `prettyInsight`, `iconName`,
  `colourSlot`. Only `cadence` carries a `default:`, and it fails *silently* by
  putting the card on the wrong tab. Plus registration in `InsightEngine`, which
  breaks nothing and simply makes the card never appear.
  **Use the `add-insight` skill rather than this summary.**
  **`primaryMetric` in `InsightDetailView` is gone** — the detail screen now
  charts `InsightResult.contributors`, which the scoring code emits itself, so
  that switch no longer exists to fall out of date.

Adding an `InsightModel` also requires `candidateMetrics` (no default
implementation, so it won't compile without one). `MetricColourSlotTests` no
longer depends on what co-occurs — it asserts that *any* set up to the palette
size resolves to distinct hues, so adding a metric to an insight can't break it
from a file that never mentions colour. That was deliberate: the previous version
encoded a belief about co-occurrence, and the belief shipped wrong.

Do this grep *before* pushing, because CI is the only thing that will tell you.

## Lesson worth keeping: suspect your own precheck first

Four deploy runs "failed to find the phone." The cause was not the phone. The
install step's guard demanded `connectionProperties.tunnelState == "connected"` —
but a paired, perfectly installable iPhone commonly reports `available (paired)`,
and `devicectl` opens the tunnel on demand. The guard was rejecting a working
device. Each failure came with a plausible user-side explanation (phone locked,
VPN, off Wi-Fi, Xcode not signed in) and each was accepted instead of questioning
the check doing the rejecting. Fixed in `122d2c6`.

Rule: when a self-written guard reports an environmental failure repeatedly,
verify the guard's premise against raw tool output before asking the user to
change anything about their environment.

## Known gotcha: memory files may not auto-load

`CLAUDE.md` and `.claude/commands/handover.md` live in **this repo's** root. If a
session's working directory is a *different* repo with this one attached
alongside, Claude Code may not discover either — `/handover` comes back "Unknown
command" and `CLAUDE.md` isn't auto-read. Slash commands are registered at session
start, so a newly-created one never works in the session that created it. Start
sessions with `health-insights-ios` as the working directory; otherwise run the
handover steps by hand and paste `CLAUDE.md` into the new chat.

## Lesson worth keeping: don't let a guess pre-empt the authority

The scope skip described above cost the user a deploy cycle and a round of
pointless account-fiddling (revoking an Oura authorisation that was already
correct). The app *inferred* that a permission was missing and acted on the
inference by not making the call — which destroyed the evidence that would have
shown the inference was wrong.

Rule: when a remote system is the authority on whether something is permitted,
ask it. A local prediction may inform a warning; it must never replace the
request. This is the same failure shape as the `tunnelState` guard below.

