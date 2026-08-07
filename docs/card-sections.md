# Card sections — what each screen actually renders

_Audit of record. Re-derived 2026-07-31 after the consolidation from seventeen
insight cards to nine, again 2026-08-01 after the section order changed, and
**swept against the code 2026-08-07** (backlog D15 + D48) after nine more cards
had shipped without the hand-written tables moving. Every cell was read out of
the code._

Written because the app had three families of card-based screen and no record of
which sections each shows. The first pass found eight inconsistencies; five were
closed in Phase 1. Then the count itself turned out to be the real problem —
seventeen cards with three built on VO₂max, three on sleep duration and three
scanning the same baselines — and they were merged to nine.

**Phase 2 is done** as of 2026-08-01 (`dc5fae6`), bar Body Composition's
"view & add" scan entry, which the user deferred to its own session — see
"Still open" ▸ 10.

---

## 1. Insight detail screens

One file renders **all eighteen**:
`HealthInsights/Features/Insights/InsightDetailView.swift`. Its `body` is a fixed
sequence. Nothing is per-insight except the gates.

### The order, and why

_Set by the user on 2026-08-01, and this is the rationale as they gave it. The
list is a reading order: **the number → why → how it moved → what changed → the
card's own subject → what it is made of → how it compares → the deep dives → the
appendices.**_

| # | Section | Why here |
|---|---|---|
| 1 | **the score** | The very first thing: your overall number for this card, at a glance. |
| 2 | What's driving this | Why you are seeing that score. The fastest insight on the screen. |
| 3 | Score over time | How it is trending. |
| 4 | What changed | Deltas, before any of the machinery behind them. |
| 5 | *the bespoke section* | The card's own picture of its own subject. |
| 6 | *the second bespoke section* | Two cards have one. **Body Composition**: *what your body is made of* and *what you are doing about it* were sharing a slot, and the medication half had grown five sub-sections inside somebody else's heading (the user's call, 2026-08-02). **Cardiovascular Risk**, added 2026-08-05: *how old does each thing think you are* — every age estimate the app and its connectors produce, each attributed and each carrying its own error. It is a genuinely different question from *what is your risk*, which is why it earns the slot rather than becoming a thirteenth card. |
| 7 | What goes into this | Which sources feed the score. |
| 8 | How this is weighted | The deep dive on those weightings, for the reader who wants the science. |
| 9 | Which instrument to believe | *Whose* reading each of those was. Added 2026-08-07 (backlog B3-23 / S8, the reader's ask and not the first time they made it): where Watch, ring and scale disagree, both numbers, which one the app used and why. It sits **after** 7 and 8 rather than between them, because "the overview of what feeds the score, then the arithmetic" is an argument the user made and splitting the pair would break it. |
| 10 | How you compare | You against everyone else. |
| 11 | How far from your normal | You against you. |
| 12 | Patterns worth a look | What the app noticed across the inputs. |
| 13 | What comes first | What runs ahead of the score. |
| 14 | Full history | An appendix — one link per input. |
| 15 | View & add | What the card asks *of* you. |
| 16 | Was this accurate? | The other thing asked of you. |

**Two things are not sections and are not in that list.** The *disclaimer* is
chrome and is always last. The *timeframe picker* has no position at all: it is
**pinned above the tab bar** and on screen the whole time.

That pinning is the third placement it has had, and the first two failed the
same way. It began *inside* "Score over time" while also driving four other
sections, so a card with too few replayable days lost the control for sections
that still used it. Moved out and gated on `usesTimeframe`, it was then hidden
on cards where nothing read it — including the one case where widening the
window is the *remedy*, a card with no series, which left `SectionPlaceholder`
telling the reader to widen a timeframe that was not on screen. **Both bugs were
the control being somewhere the reader wasn't.** Five sections read it, spread
from position 3 to position 11 of fourteen; there is no point in a fourteen-
section scroll that is near all five.

It is a `safeAreaInset(edge: .bottom)` rather than an `overlay`: an overlay would
sit on top of the last section and permanently hide the bottom of the
disclaimer, while an inset shortens the scrollable area by the bar's own height
so everything can still be scrolled clear of it. The inset also stacks above the
tab bar's own safe area with no hard-coded guess at its height.

**7 before 8 is deliberate**: the overview of what feeds the score, then the
arithmetic. **10 before 11** for the same shape — the outside comparison, then
the personal one.

**9 is after that pair and not inside it** (2026-08-07). "Which instrument to
believe" qualifies both 7 and 8 — it says *whose reading* each input was — so
the tempting placement is between them, next to the list of inputs it is about.
It is not there, because 7-then-8 is a single argument the user made and a
section wedged into the middle of it breaks the sentence. Provenance is the
third thing said about the inputs, not an interruption of the first two.

**Body Composition's first bespoke slot now nests three things (2026-08-03).**
In order: **"Your body over time"** (the body model — a silhouette drawn from the
reader's own girths, a scrubber that morphs between measurements and runs on
into the weight trend's projection), then **"What you're made of"** (the
composition split), then **"Your build"** (the somatotype).

Nested rather than taking a seventh top-level slot, deliberately: all three are
readings *of one body*, and the ordering block below is generated from
`InsightDetailView.body` — a new slot moves four hand-written tables with it.
`card-map.sh --check` agrees with the nested arrangement.

The body model's own gate: it needs a height and a weight, and renders from
**estimated** girths where nothing has been measured, because a body model that
appears only after a scan cannot be what persuades somebody to take one. Its
caveat always says which girths were estimated. The projected half is refused
outright when `CompositionVelocity.isMoving` is false — a steady weight draws
nothing past today rather than a confident future out of a flat line.

**Position 6 is new, 2026-08-02, and it is one card's.** Body Composition's
bespoke slot had grown to hold two genuinely different questions — *what your
body is made of* and *what you are doing about it* — and the second had five
sub-sections filed under a heading that said nothing about them. The user:
*"I want to actually put the medication on its own section, called weight
management. Meaning body comp will have two bespoke sections."* Every other
card renders `EmptyView` there, which costs no spacing.

### The generated map

Regenerated by `./scripts/card-map.sh`, which reads `InsightDetailView.body`.
`--check` fails when this table and the code disagree, and `handover-check.sh`
runs it — so a session that adds or moves a section cannot close without this
file having been brought along.

<!-- CARD-MAP:BEGIN — generated by scripts/card-map.sh, do not edit -->

| # | Renders | Section title |
|---|---|---|
| 1 | `headerCard` | (the score itself — dial, headline, confidence, explanation) |
| 2 | `driversCard` | What's driving this |
| 3 | `scoreHistoryCard` | Score over time |
| 4 | `periodContrastCard` | What changed |
| 5 | `bespokeSection` | *(one `switch`, per card — see the matrix)* |
| 6 | `secondaryBespokeSection` | *(untitled)* |
| 7 | `contributorsCard` | What goes into this |
| 8 | `weightedContributionCard` | How this is weighted |
| 9 | `InstrumentAgreementSection` | Which instrument to believe |
| 10 | `peerStandingSection` | How you compare |
| 11 | `vitalDepartureSection` | How far from your normal |
| 12 | `patternsCard` | Patterns worth a look |
| 13 | `laggedCard` | What comes first |
| 14 | `contributorLinksCard` | Full history |
| 15 | `ViewAndAddSection` | View & add |
| 16 | `feedbackCard` | Was this accurate? |
| — | `disclaimerCard` | *(chrome, not a section)* |
| — | `timeframeBar` | *(screen control, pinned above the tab bar)* |

<!-- CARD-MAP:END -->

**The generated block is the order only.** Everything else in this file — the
matrix, the feature audit, the gaps — is written by hand and a new section
changes all three. That is the point of the check failing rather than
self-healing: it is a prompt to re-read, not a formatter.

### The gates

Ordering lives in the generated map above. This is the other half: what each
section needs before it draws content rather than a `SectionPlaceholder`.

| # | Key | Section | Gate |
|---|---|---|---|
| — | *picker* | the timeframe control, pinned above the tab bar | **always** |
| 1 | `Hdr` | the score — dial, **title and headline beside it**, trend chip, confidence badge, subheadline, explanation | always |
| 2 | `Drv` | "What's driving this" | **always** |
| 3 | `ScrHx` | "Score over time" | **always** |
| 4 | `Chg` | "What changed" — period contrast | **always** |
| 5 | *bespoke* | the card's own picture of its own subject | one exhaustive `switch`, all **eighteen** ids, no `default:` — Readiness's arm is a deliberate `EmptyView()` |
| 6 | *bespoke 2* | "Weight management" · "How old does each thing think you are" · "How hard you worked" + "How much you moved" | Body Composition, Biological age and Fitness; `EmptyView` on the other fifteen |
| 7 | `Goes` | "What goes into this" — overlay, scale picker, legend | **always** |
| 8 | `Wgt` | "How this is weighted" — arrives **closed** | **always** |
| 9 | `Inst` | "Which instrument to believe" — every device's own reading, which one the app used, and why. Arrives **closed** | **always** — it draws its own empty state ("one instrument each, so nothing to choose between"), which is the *good* answer on most cards and must not read as a gap |
| 10 | `Cmp` | "How you compare" — the card's inputs against published norms | **always** |
| 11 | `Nrm` | "How far from your normal" — against your own baseline | **always** |
| 12 | `Patt` | "Patterns worth a look" — arrives **closed** | **always** |
| 13 | `1st` | "What comes first" — lag, arrives **closed** | **always** |
| 14 | `Hist` | "Full history" — one link per input | contributors non-empty — but `candidateMetrics` is never empty (`ContributorsTests`), so in practice always |
| 15 | `V&A` | "View & add" | the model's `contributions` is non-empty — twelve of eighteen cards |
| 16 | `Fbk` | "Was this accurate?" / "Is this right about you?" | **always**, since 2026-08-06 (`5330d92`). `primaryValue == nil` now only changes the wording |
| — | `Disc` | disclaimer | always |

**Every gate above that says "always" was `◐` at the start of 2026-08-01.** The
reordering is cosmetic beside that change: a section that renders on every card
whatever it found is what makes the order *mean* anything, because a fixed
sequence with holes in it is not a sequence the reader can learn.

### Every section closes; only some arrive closed

Sections 2–11 are all `InsightSection`, and **every `InsightSection` has a
chevron**. The two that do not — `V&A` and `Fbk` — are plain `Card`s and were
excluded by the user by name, which is also why nothing had to be opted out: the
capability comes from the container, and those two were never in it.

*Collapsed* and *collapsible* were the same thing until 2026-08-01, and the bug
that exposed the difference is worth keeping. "Score over time" was collapsible
only while it was **empty**, because the view passed `.collapsed` for the
placeholder and `.always` for the chart — so the reader could close the section
that had nothing in it, and then lost the chevron the moment the replay landed
and it had something. `SectionExpansion` is now a struct whose `startsExpanded`
says only what the section does before anyone touches it.

Which arrive closed: `Wgt`, `Inst`, `Patt`, `1st` always, plus **any section
with nothing to show**, which shows its `SectionPlaceholder` headline as the
preview line. `Inst` joined that group on 2026-08-07 for the group's own reason
— it is a transparency deep dive rather than a headline — and its preview
carries the finding out onto the closed header, so a reader who never opens it
has still been told that two of their devices disagree and by how much. Everything else arrives open. A section that arrives open has no preview:
`trailing` is already the one number worth opening it for, and somebody who
closed a section themselves does not need telling what they closed.

**The reader's choice is a `Bool?`, not a `Bool`.** `startsExpanded` is derived
from data that lands *after* the first render, so a plain flag would either
freeze a section at whichever state it was born in, or reopen one the reader had
deliberately closed each time new data arrived. Three states, because there are
three: closed by the reader, opened by the reader, and not yet asked.

### The matrix

**Key** — `●` always renders · `◐` renders once the data clears a floor ·
`○` cannot ever render.

⚠️ **Swept against the code 2026-08-07 (backlog D15/D48).** It had **fifteen**
rows against `InsightID.allCases`' **eighteen** — Symptom radar, Work impact and
Travel drain had never been added — and three columns were describing the app of
2026-08-01: `Fbk` was `◐` everywhere after being ungated (`5330d92`, "Q5 feedback
ungated"), `V&A` was `○` on two cards that have one, and Readiness's bespoke cell
described a section its `case` renders `EmptyView` for. **Rows come from
`InsightID.allCases` and nothing generates them**, which is why they go stale
silently; count the enum before trusting the table.

| Insight | Tab | `Hdr` | `Drv` | `ScrHx` | `Chg` | bespoke | bespoke 2 | `Goes` | `Wgt` | `Inst` | `Cmp` | `Nrm` | `Patt` | `1st` | `Hist` | `V&A` | `Fbk` | `Disc` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Readiness | Today | ● | ● | ● | ● | ○ — `case .readiness: EmptyView()`; the scan *is* `Nrm`, kept at all seventeen rows here | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ● | ● |
| Sleep | Today | ● | ● | ● | ● | ◐ **five top-level sections**: "Last night in stages" + "A typical night" + "Your fortnight" + "How fast you fall asleep" + "Breathing during sleep" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Energy | Today | ● | ● | ● | ● | ◐ "Today" curve | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ● | ● |
| Symptom radar | Today | ● | ● | ● | ● | ◐ "The radar" **+ its own scorecard** | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● `.symptomLog` | ● | ● |
| Substance Impact | Insights | ● | ● | ● | ● | ◐ "Cardiovascular load" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Heart Health | Insights | ● | ● | ● | ● | ◐ "How your heart responds" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Fitness | Insights | ● | ● | ● | ● | ◐ "Fitness age over time" **+ "Where this is heading"** | ● "How hard you worked" + "How much you moved" | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Heart Attack & Stroke Risk | Insights | ● | ● | ● | ● | ◐ "Heart age over time" **+ "If today's numbers hold"** | ○ — the age comparison moved to Biological age 2026-08-06 | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Blood Pressure | Insights | ● | ● | ● | ● | ◐ "Your readings" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Body Composition | Insights | ● | ● | ● | ● | ◐ "What you're made of" + "How that has changed" + "Your build" | ● "Weight management" (6 nested) | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Nutrition | Insights | ● | ● | ● | ● | ◐ "Vitamins and minerals" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Metabolism | Insights | ● | ● | ● | ● | ◐ "What you burn against what you should" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Stress load | Insights | ● | ● | ● | ● | ◐ "Where the load is sitting" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ● | ● |
| How you walked | Insights | ● | ● | ● | ● | ◐ "Which half moved" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ● | ● |
| Biological age | Insights | ● | ● | ● | ● | ◐ "What each marker says" | ● "Your ages over time" **+ "How old does each thing think you are"** | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| Mental health | Insights | ● | ● | ● | ● | ◐ "What moved, and which way" | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ | ● | ● |
| Work impact | Insights | ● | ● | ● | ● | ◐ "Your work events" — the calendar review list | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ● `.readerIdentity` | ● | ● |
| Travel drain | Insights | ● | ● | ● | ● | ◐ "Your travel events" — the same list, `.travel` only | ○ | ● | ● | ● | ● | ● | ● | ● | ● | ○ — deliberate: the model reads time-zone changes and no classifications | ● | ● |

**The bespoke slot is one slot, and there is now a second one.** Five cards
draw more than one thing *inside* the first slot (Body Composition, Fitness,
Heart Attack & Stroke Risk, Symptom radar, and — since 2026-08-02 — Sleep, which
draws four), separated by a `Divider()` and wrapped in `NestedInsightSection` —
the pattern Body Composition established.

**Biological age's second slot carries two sections since 2026-08-07** —
"Your ages over time" above "How old does each thing think you are" (backlog
D22). The order is the reader's question order: *is mine moving* comes before
*what does everything else say today*. Before this the card had no history at
all, which was the wrong half to be missing on a model whose own documentation
says the absolute number is soft to about ±10 years and the direction it moves
is what survives. Note the chart there draws **two** series — the app's own
biological age and the vendor's vascular age — and is the only caller of
`AgeHistoryChart` that draws more than one; see `AgeHistoryChart.banded` for
why only the leading one gets a filled band.

That stopped being enough for Body Composition on 2026-08-02. **"Weight
management" is a second top-level bespoke section**, at the user's request, and
it needed no new placement rule: it is a fixed position 6 for every card, and
`EmptyView` on the fifteen that have nothing to put there. The thing Phase 1
bought — one placement rule, not one per card — survives, because the rule is
still positional and not per-insight. **Three cards fill it now**, not one:
Body Composition's "Weight management", Biological age's "How old does each
thing think you are" (moved off the risk card 2026-08-06), and Fitness, which is
the one card putting *two* sections in the second slot — "How hard you worked"
and "How much you moved".

**Sleep's second picture is "Last night in stages"** (`NightSleepChart`,
backed by `NightSleepDetail` in InsightKit): one lane per source, stage bands
decoded from Oura's five-minute phase strings, a single stageless block for a
source that reports only its window, and the gaps left visible. Built at the
user's request off the night of 2026-07-29 — 4.3 h from Oura, 8.5 h from Apple
Health — where the disagreement *was* the finding: a morning re-sleep one
source typed as a nap. The same session changed the parser convention to
match: a nap-typed Oura record that **begins before noon** joins the night's
totals (`OuraResponseParser.isMorningReSleep`), afternoon and evening naps and
untimed rest records stay excluded, and a re-sleep still never provides the
night's bedtime or latency.

**Sleep's other four sections**, all top-level since 2026-08-07 (backlog B18-3,
B18-4, B18-5 and P22) and each its own `@ViewBuilder` member:

- **"A typical night"** (5p, `SleepStageAverageChart` over
  `SleepStageAverages`) — per-stage averages across sources, **obeying the page
  timeframe**, which is backlog P22's third and final part. It exists because
  the timeframe control drove five sections and drove nothing on the card's own
  subject: the stage picture was one fixed night, so *"has my deep sleep been
  getting worse?"* could not be asked. One bar per source, never pooled, and
  each source averaged over **the nights it recorded** rather than the nights in
  the window — the other denominator draws a ring worn nine nights in thirty as
  somebody sleeping two hours a night.
- **"Your fortnight"** (5f) — the bedtime strip.
- **"How fast you fall asleep"** (5n) — nightly latency, its drift, and the four
  things the app can see that move it.
- **"Breathing during sleep"** (5o): Oura's nightly breathing-disturbance index
  promoted from the raw catalogue (backlog #30/S9), drawn with the shared
  `MultiSourceChart` against the reader's own recent range and reported by the
  model as a weight-0 contribution — trended, never scored, and its caveat says
  outright that it is not an apnoea test. **Backlog B18-1 wants this contained
  by a dedicated sleep-apnoea indicator section**, which does not exist yet;
  when it is built, this is the section it wraps.

Keeping each in its own member is not tidiness. `card-map.sh` reads titles from
a 4,000-character window per member and **fails open** past it (activeContext
finding 3), and `sleepNightCard` was at 3,124 characters while holding all five
— one added paragraph from silently dropping a title from the generated map.
Split, the largest of them is well under half the window.

It was five until 2026-08-01. Heart Health and Readiness had their centile strip
and their departure panel nested under "How this is weighted", which was their
bespoke section — and when that section went universal *and closed by default*,
those two strips would have arrived hidden inside a collapsed generic section.
**A card's own picture of its own subject must not be something you have to open
a shared section to find**, so both were promoted into the bespoke slot itself.

**Every card renders the same sections, in the same order, always.** Two
deliberate exceptions remain, each about the *card* rather than about the data:

- **`V&A` reaches twelve of the eighteen.** The six without it — Readiness,
  Energy, Stress load, How you walked, Mental health, Travel drain — ask the user
  for nothing and are built entirely from sensed data. "Add a reading" on a card
  that takes none is a control that can never do anything.
  **It is derived, not switched:** `InsightModel.contributions` defaults to
  `requirements.isEmpty ? [] : [.groundingFacts(…)]`, and six models override it
  because a dated log is not a profile fact — Sleep (`.screenTime`), Substance
  Impact (`.substanceLog`), Blood Pressure (`.bloodPressureReadings`), Symptom
  radar (`.symptomLog`), Work impact (`.readerIdentity`) and Body Composition.
  *(This bullet said "reaches six … Readiness, Sleep, Energy" until 2026-08-07,
  which was the count from before the derivation landed and before nine more
  cards existed.)*
- **The bespoke slot is per-card by construction** — it is the card's own
  picture of its own subject, so there is nothing generic to draw in its place.
  Its `switch` is exhaustive over all eighteen ids with no `default:`
  (`adca807`), and five cards draw more than one thing in it under a `Divider()`.
  **Sleep left the nesting pattern entirely on 2026-08-07** and returns five
  top-level sections.
  **Readiness's arm is `EmptyView()` on purpose** and the comment on it says so:
  its subject *is* the seventeen-vital scan, which `Nrm` already draws unnarrowed
  for this one card, and a second copy would be the same strip twice.
- ~~**`Fbk` needs a number to rate.**~~ **Gone 2026-08-06** (`5330d92`, backlog
  Q5). `feedbackCard` is now rendered unconditionally and the `primaryValue ==
  nil` branch only rewords the question — "Is this right about you?" / "Yes" /
  "No" instead of "Was this accurate?" / "Accurate" / "Not accurate". A card with
  no number still has a claim worth agreeing or disagreeing with, which is what
  the old gate had missed.

### Why the rest are `●` with nothing to show

They were all `◐` until 2026-08-01, and the floors are high: two scored days for
`ScrHx`, fourteen paired days for `Patt` and `1st`, seven days in each of two
windows for `Chg`. Measured rather than assumed — a replay over a realistic
five-signal dataset gives **four of the nine cards zero score-history points**
(measured 2026-08-01, when there were nine; the ratio has not been re-measured
against eighteen) —
so "Score over time" was absent more often than present, and its absence read as
the chart having been taken away.

**A section that vanishes is an absence the reader cannot read.** "Score over
time" missing means the 90-day replay hasn't finished, *or* no day has had two
of this card's signals recording at once, *or* exactly one has. Only somebody
holding the source could tell those apart — and the first fixes itself in a
second while the third is one day away.

`SectionPlaceholder` (InsightKit, tested) works out which applies, from the same
floors the section's own producer gates on — `ScoreHistory.minimumContributors`,
`PatternFinder.defaultMinimumPairs`, `PeriodContrast.minimumDaysPerPeriod` — and
quotes the actual shortfall, so "not enough data yet" can never appear under a
card holding two years of it. An empty section arrives **collapsed** with the
reason as its preview; `Patt` and `1st` arrive collapsed either way, previewing
their strongest finding. See `SectionExpansion`.

**"How this is weighted" says how, on every card.** _Rewritten 2026-08-01; this
paragraph previously argued the opposite and was wrong on three cards out of
four._ It used to read: only Heart Health, Readiness, Sleep and Energy blend
components in fixed proportions, so the other five said **"Not a weighted
average"**. That conflated *nobody chose these proportions* with *there are no
proportions*, and the two are not the same claim:

- **Body Composition** and **Fitness** each rest on **one** measurement scored
  against a published range — body fat (or BMI in fallback) and VO₂max. One
  signal has 100% of the number, so "no signal has a percentage share of it"
  described a card that does not exist. *(They were `ScoreWeighting.singleMeasure`
  for the length of one commit. Both are `weightedAverage` now — the second half
  of the same day gave their supporting signals real shares, so the primary
  measurement no longer has all of it. See the section below.)*
- **Substance Impact** divides **exactly**, and since 2026-08-02 it does so by
  inspection: the combiner is
  `0.45·worst + 0.55·mean(severities) + exposure`, which is *linear* in the
  severities, so each input's share is its own points over the total.
  `SubstanceResponseAnalyzer.penaltyShares`. *(It was
  `worst + 0.35·√(Σ rest²)` — exact too, but by Euler's theorem, and a card
  whose whole job is to be believed should prefer arithmetic a sceptical
  reader can check.)*
- **Heart Attack & Stroke Risk** runs published equations, which is a reason the
  shares are not proportions anyone chose — not a reason they cannot be
  reported. `RiskAttribution` holds one factor at its optimal value and re-runs
  the same equation; the drop is that factor's contribution. That is the
  vascular-age method the app already ships, it is what the card's own *"that
  gap is the modifiable part"* line already describes, and it **reuses
  `HeartAgeModel.riskPercent` unchanged** so no coefficient is written down
  twice.

Only **Blood Pressure's cuff route** is genuinely unweighted — and even there
*"this is your own cuff reading from the last 24 hours, taken at face value"*
says more than a negation. `ScoreWeighting.measurement`.

**The basis is stated by the model, not inferred from the weights.** A card
whose contributors all came back at zero used to be indistinguishable from one
that had decided there was nothing to divide. `InsightResult.weighting` is that
statement, it defaults to `.unstated` so a new insight is silent rather than
claiming a basis nobody chose for it, and
`ScoreAttributionTests.testEveryScoringCardStatesHowItsNumberIsFormed` stops a
card going back to having a number and no account of it.

### Everything charted carries a share — the weight-0 rule, reversed

_Set by the user 2026-08-01, **after** seeing the version above ship:_ **"Everything
that is in 'what goes into this' should go into the overall score. That's the
whole point of that section, and the weighting should just be a list of things
that all have a weight, even if some are very low."**

This reverses a rule argued at length in three files. The argument was that an
invented weight inside a number the user is asked to trust is worse than none —
and it is sound *against inventing one*. It never justified what it was actually
producing: a section headed "What goes into this" listing seven signals on
Fitness of which one went into anything, and eleven on Readiness of which none
did.

**Nothing is invented.** The app has always known how to judge a signal it has
no published scale for — direction-aware departure from the reader's own normal
— and has done it for seventeen vitals since `VitalSignsCheck` was written.
`SupportingSignal.score` is the identical mapping `ReadinessScore` weights every
one of its components with, extended with the case where neither direction is
the good one. Weaker evidence earns a **smaller** weight, not a zero one.

`SupportingSignal.collectiveShare` is 20%, in one place, and it is the whole of
the judgement: enough that a signal visibly moves the number, small enough that
the card's primary measurement still decides what the card says. On Fitness the
primary pool keeps 80% against six supporting signals at about 3% each, and no
combination of them turns "Excellent" into "Needs work". *(Since 2026-08-01
that pool is VO₂max at 0.80 and the week's exercise dose at 0.20 — the dose is
primary, not supporting, because `ActivityDoseModel` scores it against WHO
2020's published band rather than against the reader's own baseline.)*

`ScoreBlend.blend` is the shared arithmetic — renormalise each group, multiply,
sum — because adding a second group of terms to five cards separately is five
places for the weights to stop summing to one, which is the claim the section
makes on screen. A metric in both groups keeps its primary term, so a signal
weighed on a published scale is never weighed again against its own baseline.

**A card with nothing supporting is unchanged.** The 20% is only carved out when
there is something to put in it, so a reader with no wearable sees the number
they saw yesterday.

### The three exceptions, and what they have in common

Every remaining unweighted row **says why on the row itself**, and
`ScoreAttributionTests.testAnUnweightedRowAlwaysSaysWhy` enforces it across
every card. It found three bare zeroes on the risk card while being written.

| Card | Row | Why it has no share |
|---|---|---|
| Heart Attack & Stroke Risk | VO₂max, vascular age | SCORE2 and ASCVD have **no term** for fitness; a provider's vascular age is a second opinion reported beside ours rather than folded in |
| Blood Pressure (cuff routes) | resting HR, HRV | they feed the estimator, and the estimator is not what the dial is reading |
| Substance Impact | a signal that moved the welcome way | it took nothing off |
| Heart Attack & Stroke Risk | a factor at or better than optimal | it is carrying none of your risk — which is good news, and "carrying none" and "not looked at" are opposite statements |

The first two are the same shape: **the signal feeds a different number on this
card.** That is a real category and not a dodge — a weight for either would be
claiming an input the published equations do not have.

**Height left the card rather than earning a weight.** It is a static attribute
— the app already gives it a plain value card with no chart — so it is neither a
series to draw nor a thing that can change between two readings. It enters
through BMI and is named in the drivers. The only honest label for its bar would
be "this cannot change".

**Age and sex are marked with a lock.** They carry the risk card's largest share
and are the one row nobody can act on; ranked silently beside cholesterol the
section reads as a list of things to work on with the biggest bar on the one
that cannot move. `ScoreFactor.isModifiable`.

The collapsed preview for a card that *does* weight names the heaviest signal,
and `[MetricContribution].weightingPreview` refuses the superlative on a tie:
`byInfluence` breaks ties by name, so on six equal Readiness components the
first is not "the most", and saying so would be false.

**The `isComputing` arm is the one that earns its keep.** `AppModel.scoreHistory`
returns `[]` on first ask and replays off the main actor, so a card opened cold
is genuinely empty for a second or two. "No scored days yet" there would be a
false statement that corrects itself only after the reader has read it;
`AppModel.scoreHistoryIsPending(for:)` is what stops it being said.

That the bespoke line above once said "reaches six" while item 7 under "Still
open" in this same file said all nine had one is worth keeping in view: **a file
disagreeing with itself, written in one session and half-updated in it** — the
polarity handover step 11 exists to catch, and the one that keeps getting
skipped, because a claim that something is *missing* is exactly what the work
invalidates.

### Every figure a card works out is a data source — the 2026-08-06 rule

_The reader, on seeing the derived-series substrate ship without the cards using
it:_ **"the metrics we are deriving from each card, are still not being turned
into their own individual data sources, and used, especially in weightings. …
The work impact card… 'What's changed' and 'what goes into this' will only still
just show Resting Heart Rate, HRV and sleep duration…. the entire point of this
card is to take into consideration work impact, where is that on these
sections? Where is that in the weighting section? Where is that in how you
compare?"** And then: **"Do this for EVERY card, and make it a rule for every
card going forward."**

**The rule, beside the weight-0 rule above and of the same kind:** a card must
declare, for every non-metric quantity it computes, either a derived series or —
in a comment at the site — the reason it is a pass-through.

`ScoreFactor.Source.derived` carries a `DerivedSeriesID` from 2026-08-06 (it
carried no payload before, which is why a derived row could never link
anywhere). The three verdicts, the two borderline calls and the mechanics live
in the `add-insight` skill, §5a. What belongs *here*, because it is about the
sections:

- **Both sections show them.** A derived factor reaches "What goes into this"
  through `auxiliaryInputs` and "How this is weighted" through `weightedFactors`
  / `unweightedFactors` — no per-card wiring, the same route a grounding fact
  takes.
- **Most of them carry weight 0, and the zero is arithmetic.** A pooled
  departure, a combined biological age, an observed TDEE: each is a function of
  the rows below it, so a share would count the same evidence twice. They render
  under *charted, not scored*, and each row states why — the same rule the table
  above enforces, extended to figures a card **produces** rather than reads. The
  group's heading changed to admit both kinds.
- **Three rows carry a real share**, because their coefficients really are terms
  in the sum: Sleep's debt (12%) and night-length consistency (8%), and
  Substance Impact's decaying load. The first two used to be folded invisibly
  into the sleep-duration row's weight — a decision that was right about the
  *chart* (three quantities from one series draw one line) and had quietly
  become wrong about the *weighting section*.
- **Every derived row is tappable** through to its page under Data ▸ Generated
  insights, where a figure the app is not yet computing falls back to a plain
  row rather than linking to an empty page.
- **"How you compare" now says what it could not compare.** There is no
  published distribution of meeting hours, or of a pooled mental-health
  departure, by age and sex — and there is no honest way to invent one. The
  section lists those figures under *"Nothing to compare these against"*, on
  both the populated and the placeholder branch, because the card most likely to
  have no norms at all is exactly the one whose main input was being skipped in
  silence.

`DerivedFactorIdentityTests` enforces the mechanical half: no `.derived` factor
may name a series its own result does not produce. There is deliberately no test
demanding every card have one — Readiness and Heart Health honestly have none,
and such a test would be satisfied by inventing a figure.

### Per-insight facts behind the matrix

| Insight | `cadence` | Grounding | `contributions` | Absorbed |
|---|---|---|---|---|
| Readiness | daily | 0 | — | Vitals Check, Health Watch |
| Sleep | daily | 0 | — | Sleep Quality, Sleep Debt, Sleep Regularity |
| Energy | daily | 0 | — | — |
| Substance Impact | trend | 0 | `.substanceLog` (override) | — |
| Heart Health | trend | 2 | `.groundingFacts` | Where You Stand (centiles), Resting HR |
| Fitness | trend | 2 | `.groundingFacts` | Cardio Fitness, Fitness Trajectory, fitness age |
| Heart Attack & Stroke Risk | trend | 10 | `.groundingFacts` | heart age |
| Blood Pressure | trend | 2 | `.bloodPressureReadings` (override) | — |
| Body Composition | trend | 2 | `.groundingFacts` | — |
| Nutrition | trend | 1 (sex, optional) | `.groundingFacts` | — |
| Metabolism | trend | 2 (both optional, fallback equation only) | `.groundingFacts` | — |

### How each card's number divides

_Read out of the models 2026-08-01. `ScoreWeighting` is the model's own
statement; the shares are what "How this is weighted" draws._

| Insight | `weighting` | Primary (80%) | Supporting (20%, shared) |
|---|---|---|---|
| Readiness | `weightedAverage` | six fixed weights, renormalised over what had data | the further vitals the scan covers, scored by the scan's own `normality` |
| Sleep | `weightedAverage` | ten terms summing to 1 (latency joined 2026-08-01, funded from duration and consistency) — one `Weight` table read by the score and `contributors` both | — none; every input is already weighted |
| Energy | `weightedAverage` | **`EnergyModel.Output.terms`**, each term's magnitude over the total | resting HR; heart rate when the day is too thin to count exertion |
| Substance Impact | `worstOffender` | `penaltyShares` — exact and linear (see above). **The dial is measured impact, never disapproval of use** (user ruling, 2026-08-02 — see "Harm reduction" below): one signal is bounded at `worstResponseShare` 0.45 of the deduction, breadth carries the other 0.55 as a mean over everything measured, thin pools are discounted by `severity`, and exposure alone is capped at 25 once ≥3 signals are measured (55 when nothing is). The comparison is **contemporaneous** — both sides from the last 90 days (`comparisonWindowDays`) — after a six-year cuff history posed as the clean baseline for a fortnight of logs | — the pool already covers every signal |
| Heart Health | `weightedAverage` | four fixed weights, renormalised | heart-rate recovery |
| Fitness | `weightedAverage` | VO₂max (level 0.55 + trajectory 0.25, both halves off one series) and the week's activity dose (0.20) — from **`EffortIntensityModel`** where the watch recorded enough effort, otherwise `ActivityDoseModel`. One term, two inputs, never both: they answer the same WHO question and only one carries the intensity | strain, HR recovery, walking HR, resting HR, steps, active energy, distance, flights — plus whichever of exercise minutes / physical effort did *not* win the dose term |
| Heart Attack & Stroke Risk | `equation` | **`RiskAttribution`** — hold one factor at optimal, re-run | — the equations take no other input |
| Blood Pressure | route-dependent — see below | | |
| Body Composition | `weightedAverage` | **a level, a rate and a quality** (2026-08-02): body fat vs the Gallagher band **0.45**, rate of change vs the goal's band **0.30**, lean share of that change **0.25** — see "Velocity" below | lean, bone, water — *not* muscle mass, which is lean counted twice and is charted at weight 0 with its reason on the row |

### Velocity: what Body Composition's number is for

_Set by the user 2026-08-02, and built the same day._ The card scored a
**level** and nothing else, so a reader twelve kilograms down over three months
scored exactly the same as one who had never moved. For anyone actually
changing — which is most people who open it — the rate and the quality of the
change *are* the subject.

| Term | Weight | Basis |
|---|---|---|
| Body fat vs the age/sex healthy range | **0.45** | Gallagher et al. (2000) |
| Rate of change vs the goal's band | **0.30** | 0.5–1.0 %/week published loss guidance |
| Lean share of that change | **0.25** | lean is 20–30% of loss under good conditions |

**0.45 is the user's own figure**, and it lands where the established scoring
systems land: InBody's score moves on lean mass and fat mass roughly
*symmetrically* against height-and-sex norms rather than treating fat as
dominant. Here the other 0.55 expresses the same "lean matters as much as fat"
judgement as *change* rather than as level.

**The goal is a grounding fact, never inferred.** `GroundingKind.weightGoal`
(lose / maintain / gain). Inferring it from the trend makes the score circular —
a card that decides you must be trying to lose *because* you are losing can only
congratulate you. **With no goal set, the rate is scored for safety alone**:
anything inside ±1 %/week is unremarkable in either direction, and only a very
fast change costs. That is the whole of what is defensible without knowing the
intention, since −0.8 %/week is either excellent progress or an unexplained
wasting and no sensor can tell them apart.

Three shapes of wrong rate, deliberately not equally wrong
(`CompositionVelocityModel.rateScore`): short of the ideal in the right
direction is the most forgiving curve, past the ideal tightens (fast loss is
what costs lean tissue), and the opposite direction entirely is tighter again.

**The co-linearity fix rides along.** A BIA scale measures weight and impedance
and *derives* the rest — lean = weight × (1 − fat%), muscle a fixed fraction of
lean — so weighting lean, muscle and weight as three signals counted two
measurements three times and called it breadth. One lean-tissue term stands for
the tissue; weight's information now lives in the velocity, where it belongs.
Muscle mass stays **charted at weight 0 with its reason on the row**, because a
declared metric reported nowhere charts on no section of its own card, and
`ContributorsTests` catches it the moment it happens.

### Harm reduction: what Substance Impact's number is for

_Set by the user on 2026-08-02, on seeing their own card read 0:_ **"Just
because I had stimulants doesn't mean it should be 0. This is harm reduction —
it's about letting people know an honest impact of drug usage, not just 'drugs
are bad'. Measure the impact to me and tell me when I'm overdoing it. No big
impact? Your score will be quite high. If you've had heaps and there is now a
big impact to all your metrics, then yes, lower score. I want almost every
vital to go into this, so it can actually see the real impact drugs have to me
as an individual, not just general doctor guidance that would draconianly say
'you've had something, now you're at 0%'."**

Three faults produced that 0, and each has its own fix:

1. **One signal could annihilate the dial.** A single response at two standard
   deviations took the full 100 off, so the user's systolic row zeroed a card
   whose seven other signals were untouched. `worstResponseShare` (0.45) now
   bounds what any single row can do; `breadthShare` (0.55) spreads the rest
   over the **mean** severity of everything measured. Reaching zero requires a
   body responding across the board — which is what the user asked for, and
   what a broad response actually means.
2. **A three-reading pool counted like a three-hundred-reading one.** Their
   systolic comparison was 3 readings after use against 5 clean. `severity`
   now subtracts one standard error (`√(1/n₁+1/n₂)`, in SDs) from the observed
   effect size and discounts by the thinner pool against `fullEvidencePairs`
   (5). The row is still shown, still named, still headlined if it is the
   largest thing on the card — it simply cannot take its full toll until the
   readings back it, and the driver line says so in words.
3. **Only eleven vitals were watched.** Now nearly every one that can move
   inside the after-use window: heart rate, walking heart rate, both blood
   pressures, sleep architecture (efficiency, deep, REM, latency), core
   temperature, next-day capacity (steps, active energy, exercise minutes,
   strain), perfusion, glucose and gait. **Widening is safe by construction** —
   a quiet signal lowers the breadth mean, so adding vitals can only raise the
   score unless they actually moved (`testWatchingMoreQuietSignalsNeverLowersTheScore`).

Still excluded, and why: body composition, VO₂max, vascular age and height
cannot move within 18 hours, so a difference across that window measures the
passage of time rather than a response; **sleep onset** is when you chose to go
to bed, which is a decision rather than something the substance did to you.

Exposure keeps a seat — *"tell me when I'm overdoing it"* — but never the whole
bench: `exposureCeilingUnmeasured` (55) means a heavy fortnight with no
biometrics at all reads 45 rather than 0, because a log with no readings is
evidence of **use** and none of **harm**.

**Blood Pressure has three routes, and which one is live is what the section says:**

| Dial route | `weighting` | Shares |
|---|---|---|
| a cuff reading from the last 24 h | `singleMeasure` (ACC/AHA bands) | systolic and diastolic, by how far each has travelled along **its own** axis |
| past a day: the experimental estimate | `fit` | the cuff pair carries the level (80%), today's resting HR and HRV carry the nudge (20%) |
| no wearable to estimate from | `singleMeasure` (ACC/AHA bands, averaged) | the same two-number split, over the average |

**Why not a leave-one-out for the cuff pair.** It was the obvious choice — it is
what the risk card uses — and it has the wrong shape here: it measures the
*deficit* against 120/80, so a reader at 112/72 has no deficit to divide and
both rows come back at zero on the best reading they have ever taken.
`readingShares` uses distance along each number's own scale instead (90→180 and
60→120), which is always positive and still says which of the two is carrying
more.

**Energy's weights were three constants.** 0.6 / 0.25 / 0.15, written in the
card, appearing nowhere in `EnergyModel` — under a heading promising "the share
each signal has of the score". They also left the drain half's second term
unrepresented: time above resting is a full peer of active energy in the model
and reaches the reader as a driver line, and **heart rate charted on no card in
the app** despite being the signal behind it.

**Sleep's are still restated by hand** and the file says so at the point it does
it: every weight in `contributors` must equal its coefficient in the score
expression twenty lines above. They drifted apart once already. This is the
remaining instance of the pattern `EnergyModel.Output.terms` closed.

**The maths of every merged card was kept**, as components with their own tests:
`VO2Trajectory`, `FitnessAgeModel`, `HeartAgeAnalyser`, `SleepDebtModel`,
`CircadianConsistencyModel`, `VitalSignsCheck`, `HealthWatchModel`,
`PeerStandingModel`. Only the wrappers and their `InsightID`s went.

### Feature audit — what each section actually carries

_Read out of the code 2026-08-01, because "we made improvements and they only got
into some cards" is a claim nobody could check against the matrix above: it says
*which* sections render, never what each one does._

⚠️ **Re-read out of the code 2026-08-07 (backlog D15), and it had drifted three
ways.** The `#` column was a numbering of its own that had never matched the
generated map — two schemes for the same fifteen slots in one file — so it now
uses the map's positions and the bespoke sections are a separate table. The `On`
column still said `all 9` and still listed "How you compare" as Heart Health's
and "How far from your normal" as Readiness's, which was the world before those
two went universal on 2026-08-01. And the eleven bespoke sections added since
2026-08-06 were missing entirely, which matters because **six of them have no
empty state at all** — see the note under the second table.

Key — `●` yes · `○` no · `—` not applicable. `#` is the position in the generated
map above.

| # | Section | On | Arrives | Empty state | Figure | Caveat | Chart |
|---|---|---|---|---|---|---|---|
| 2 | Score over time | all 9 | open (closed when empty) | ● 3 reasons | trend/week | `scoreFloor` | `ScoreHistoryChart` |
| 3 | What's driving this | all 9 | open (closed when empty) | ● 2 reasons | `n` signals | `.none` | — |
| 4 | How this is weighted | all 9 | **closed** | ● 5 reasons | `n` weighted | `unscored` | — |
| 5a | Your readings | BP | open (closed when empty) | ● | category | `.none` | `BloodPressureChart` |
| 5b | Heart/Fitness age over time | CVR, Fit | open (closed when empty) | ● | years/year | `replayedHistory` | `AgeHistoryChart` |
| 5c | If today's numbers hold | CVR | open (closed when empty) | ● | out to age | `ifTodaysNumbersHold` | `RiskProjectionBar` |
| 5d | Where this is heading | Fit | open (closed when empty) | ● | in a year | `ifTodaysNumbersHold` | `FitnessProjectionChart` |
| 5e | Today | Energy | open (closed when empty) | ● | spent of charge | `modelledCurve` | `EnergyCurveChart` |
| 5f | Your fortnight | Sleep | open (closed when empty) | ● | social jetlag | `fittedCentre` | `SleepOnsetStripChart` |
| 5l | Last night in stages | Sleep | open (closed when empty) | ● | h asleep | `.none` | `NightSleepChart` |
| 5p | **A typical night** | Sleep | open (closed when empty) | ● `needsInput` — says "widen the timeframe" first | `n` nights · the timeframe | `estimated` — a mean; sources never pooled | `SleepStageAverageChart` |
| 5n | How fast you fall asleep | Sleep | open (closed when empty) | ● | min typical | `associationsNotCauses` | `SleepOnsetChart` |
| 5o | Breathing during sleep | Sleep | open (closed when empty) | ● `needsInput` | latest index | `estimated` — trended, never scored, not an apnoea test | `MultiSourceChart` |
| 5g | Cardiovascular load | Subst | open (closed when empty) | ● | trend/week | `decayingLoad` | `SubstanceLoadChart` |
| 5h | How you compare | HH | open (closed when empty) | ● | centile | `approximateNorms` | `PeerStandingStrip` |
| 5i | How far from your normal | Readi | open (closed when empty) | ● | `n` checked | computed | `VitalDepartureStrip` |
| 5j | What you're made of | BodyC | open (closed when empty) | ● | total kg | `.none` | stacked bar |
| 5k | How that has changed | BodyC | open (closed when empty) | ● | kg delta | `compositionWindow` | `BodyCompositionTrendChart` |
| 5m | Your build | BodyC | open (closed when empty) | ● | dominant type | `computed` | three-bar rating |
| 6b | **How hard you worked** | Fit | open (absent when no effort data) | ● the gate, as a fact | min moderate+ | `partial` | — (seven wear-scaled bars) |
| 6c | **How much you moved** | Fit | open (absent when nothing recorded) | ● | week's steps | `partial` | — (three totals) |
| 6a | **Weight management** | BodyC | open (closed when empty) | ● | mg in your system | `.none` | — (the section) |
| 6a·1 | Since you started | BodyC | nested in 6a | ● | — | `doseAttribution` | — (four figures) |
| 6a·2 | Medication in your system | BodyC | nested in 6a | ● | mg | `.none` | `MedicationCurveChart` |
| 6a·3 | Is it working | BodyC | nested in 6a | ● | — | `.none` | `MedicationResponseChart` |
| 6a·4 | By dose | BodyC | nested in 6a, ≥2 steps | ● | — | `doseAttribution` | — (grid) |
| 6a·5 | By injection site | BodyC | nested in 6a, if recorded | ● | — | `doseAttribution` | — (grid) |
| 6a·6 | Side effects | BodyC | nested in 6a, if any | ● | — | `.none` | — (worst avg first) |
| 6 | Patterns worth a look | all 9 | **closed** | ● 4 reasons | `n` found | `associationsNotCauses` | — |
| 7 | What comes first | all 9 | **closed** | ● 4 reasons | `n` leading | `fittedThrough` | — |
| 8 | What goes into this | all 9 | open (closed when empty) | ● 2 reasons | `n` of `m` | `.none` | `MetricOverlayChart` |
| 9 | What changed | all 9 | open (closed when empty) | ● 2 reasons | `n` signals | `periodContrast` | — |
| 10 | Full history | all 9 | open | ○ | `n` signals | `.none` | — |
| 11 | View & add | 6 | open, **not closable** | ○ | per route | own | — |
| 12 | Was this accurate? | ◐ | open, **not closable** | ○ | — | — | — |

**The generic slots**, every one of them on all eighteen cards (no count in this
line on purpose — it was "fifteen" and went stale the day a section was added;
the generated map above is the authority for how many there are):

| # | Section | Arrives | Empty state | Figure | Caveat | Chart |
|---|---|---|---|---|---|---|
| 1 | the score itself | — (not an `InsightSection`) | — | dial or headline | — | — |
| 2 | What's driving this | open (closed when empty) | ● 2 reasons | `n` notes | `.none` | — |
| 3 | Score over time | open (closed when empty) | ● 3 reasons | trend/week | `scoreFloor` | `ScoreHistoryChart` |
| 4 | What changed | open (closed when empty) | ● 2 reasons | `n` signals / "No shift" | `periodContrast(days:)` | — |
| 5 | *bespoke* | see the second table | | | | |
| 6 | *bespoke 2* | see the second table | | | | |
| 7 | What goes into this | open (closed when empty) | ● 2 reasons | `n` of `m` | `.none` | `MetricOverlayChart` |
| 8 | How this is weighted | **closed** | ● 5 reasons | `n` weighted / "None" | `unscored(signals:)` | — |
| 9 | Which instrument to believe | **closed** | ● 2 reasons (nothing reporting / one instrument each) | `n` signals with more than one | `computed(.partial, …)` naming the window, and refusing calibration | — (rows, not a chart) |
| 10 | How you compare | open (closed when empty) | ● `needsInput` (no DOB/sex) or `notComputable` | `n`th centile overall | `approximateNorms` | `PeerStandingStrip` |
| 11 | How far from your normal | open (closed when empty) | ● `notComputable` | `n` checked | `computed(.partial, …)` from the panel's own footnote | `VitalDepartureStrip` |
| 12 | Patterns worth a look | **closed** | ● 4 reasons | `n` found / "None yet" | `associationsNotCauses` (`.none` when empty) | — |
| 13 | What comes first | **closed** | ● 4 reasons | `n` leading / "None yet" | `fittedThrough(points:)` (`.none` when empty) | — |
| 14 | Full history | open | ○ — the whole section is absent with no metrics and no aux inputs | `n` signals | `.none` | — |
| 15 | View & add | open, **not closable** | ○ | per route | own | — |
| 16 | Was this accurate? | open, **not closable** | ○ | — | — | — |

**The bespoke sections** — slot 5 unless marked `6`:

| Card | Section | Arrives | Empty state | Figure | Caveat | Chart |
|---|---|---|---|---|---|---|
| BP | Your readings | open (closed when empty) | ● | category | `.none` | `BloodPressureChart` |
| CVR, Fit | Heart/Fitness age over time | open (closed when empty) | ● | years/year | `replayedHistory` | `AgeHistoryChart` |
| CVR | If today's numbers hold | open (closed when empty) | ● | out to age | `ifTodaysNumbersHold` | `RiskProjectionBar` |
| Fit | Where this is heading | open (closed when empty) | ● | in a year | `ifTodaysNumbersHold` | `FitnessProjectionChart` |
| Energy | Today | open (closed when empty) | ● | spent of charge | `modelledCurve` | `EnergyCurveChart` |
| Sleep | Last night in stages | open (closed when empty) | ● | h asleep | `.none` | `NightSleepChart` |
| Sleep | Your fortnight | nested in the night card | ● | social jetlag | `fittedCentre` | `SleepOnsetStripChart` |
| Sleep | How fast you fall asleep | nested in the night card | ● | min typical | `associationsNotCauses` | `SleepOnsetChart` |
| Sleep | Breathing during sleep | nested in the night card | ● `needsInput` | latest index | `estimated` — trended, never scored, not an apnoea test | `MultiSourceChart` |
| Subst | Cardiovascular load | open (closed when empty) | ● | trend/week | `decayingLoad` | `SubstanceLoadChart` |
| HH | How your heart responds | closed behind its preview either way | ● `needsInput` (a recorded workout, and the remedy says so — nothing under "View & add" can record one) | −`n` bpm in a minute | `approximate` (Cole et al., NEJM 1999) | — (recovery + autonomic rows) |
| BodyC | What you're made of | open (closed when empty) | ● | total kg | `.none` | stacked bar |
| BodyC | How that has changed | open (closed when empty) | ● | kg delta | `compositionWindow` | `BodyCompositionTrendChart` |
| BodyC | Your build | open (closed when empty) | ● | dominant type | `computed` | three-bar rating |
| Readi | — | — | — | — | — | — (`EmptyView()`; the scan is drawn by slot 10) |
| Radar | The radar | open | ● `needsMore` | — | `computed(.partial, …)` | `SymptomRadarWebCard` (hand-drawn polar `Path`) |
| Radar | …its scorecard | nested, **absent** until `flagRate` and `coverage` both exist | ○ | flag days, coverage | prose, not a `SectionCaveat` | — |
| Gait | Which half moved | closed behind its preview | ◐ **only the "too small to apportion" arm**; nothing at all when `GaitModel.evaluate` returns `nil` | ±`n`% speed | `approximate` | — (one share bar) |
| Mental | What moved, and which way | closed behind its preview | ○ — **the section vanishes** when `evaluate` returns `nil` | `n` of `m` moved | `approximate` | — (signed departure strip) |
| Stress | Where the load is sitting | closed behind its preview | ○ — **vanishes** | `n` of `m` leaning | `approximate` | — (the same signed strip) |
| Nutr | Vitamins and minerals | closed behind its preview | ○ — **vanishes** | `n` of `m` from your log | `estimated`/`partial`, from `MicronutrientEstimate.caveat` | — (per-nutrient bars) |
| Metab | What you burn against what you should | closed behind its preview | ○ — **vanishes** when there is no predicted TDEE | `n`% speed | `fitted` | — (two bars) |
| BioAge | What each marker says | closed behind its preview; **open** when there are no markers, because the preview is then `""` | ○ — **vanishes** | ±`n` years | `approximate` | — (per-marker age strip) |
| Work | Your work events | closed behind its preview | ○ — **vanishes** with no events | `n`% right so far | `computed(.estimated, …)` | — (review rows) |
| Travel | Your travel events | closed behind its preview | ○ — **vanishes** with no events | `n`% right so far | `computed(.estimated, …)` | — (review rows) |
| Fit `6` | **How hard you worked** | open (absent when no effort data) | ● the gate, as a fact | min moderate+ | `partial` | — (seven wear-scaled bars) |
| Fit `6` | **How much you moved** | open (absent when nothing recorded) | ● | week's steps | `partial` | — (three totals) |
| BodyC `6` | **Weight management** | open (closed when empty) | ● | mg in your system | `.none` | — (the section) |
| BodyC `6` | ⤷ Since you started | nested | ● | — | `doseAttribution` | — (four figures) |
| BodyC `6` | ⤷ Medication in your system | nested | ● | mg | `.none` | `MedicationCurveChart` |
| BodyC `6` | ⤷ Is it working | nested | ● | — | `.none` | `MedicationResponseChart` |
| BodyC `6` | ⤷ By dose | nested, ≥2 steps | ● | — | `doseAttribution` | — (grid) |
| BodyC `6` | ⤷ By injection site | nested, if recorded | ● | — | `doseAttribution` | — (grid) |
| BodyC `6` | ⤷ Side effects | nested, if any | ● | — | `.none` | — (worst avg first) |
| BioAge `6` | How old does each thing think you are | nested, needs ≥2 estimates | ○ — **vanishes** below two | `n` years apart | `.none` | — (`ageEstimateStrip`, hand-drawn) |

⚠️ **"Every section on every card has an empty state" stopped being true on
2026-08-06, and this is the regression to fix.** It was made true on 2026-08-01,
and the reasoning behind it still stands verbatim: "Your fortnight" gone could
mean no sleep data at all or fewer than `CircadianConsistencyModel.minimumNights`
nights — a provider problem and a patience problem, indistinguishable from the
outside. But **eight of the eleven bespoke sections added since** — mental
health, stress load, nutrition, metabolism, both of biological age's, and the two
calendar review lists — are written as `if let out { InsightSection(…) }` with no
`else`, so the card's own picture of its own subject simply disappears and the
reader is left with the generic sections and no explanation. **"The radar" is the
only one that took the `emptySection(…)` path.** Gait took it halfway, covering
"the change is too small to apportion" but not "the model returned nothing"; the
radar's own scorecard is nested inside a section that does have one, so its
absence at least leaves something behind.

Nothing enforces this. `verify.sh` has no check for it, and the pattern compiles
because a `@ViewBuilder` with a bare `if` is legal — it is exactly the shape the
2026-08-01 pass was written to remove.

Three builders cover them, and the split between the first two is the point:
`needsMore(subject:have:need:noun:)` for a countable floor, which always quotes
*both* numbers and ends "as more arrive"; `needsInput(subject:what:remedy:)` for
the gaps only the reader can close — a cuff reading, a date of birth, a scale
that reports body fat — which never promises it will fill in on its own; and
`notComputable(subject:because:)` where the reason is about the model rather
than a count. A test pins that the two instructions never appear in each other's
copy. **`remedy:` (2026-08-02) is where the reader actually closes the gap** —
the default points at this card's own "View & add", which is right only for a
grounding fact the card collects; the scale, the workout, and DOB/sex on a
card without that section each say where they really live, because a pointer
at a section that says "All set" (or isn't on the screen) is worse than none.

Two placeholders stopped lying on 2026-08-02. "How far from your normal" says
when a card's signals are outside the scan's coverage entirely (Body
Composition — nothing in `VitalSignsCheck.coveredMetrics` is a scale reading,
so that card's panel can never fill and must not claim "not enough history…
arrives on its own"). "How you compare" distinguishes missing DOB/sex from
having nothing to compare, so a transient empty state can never borrow the
missing-details copy.

### Two ways of placing a signal, on every card

`Cmp` and `Nrm` answer the same question against two different references —
**other people**, and **your own past** — and both were one card's bespoke
section until 2026-08-01. Neither is a heart question; both are questions any
card's inputs can be asked, which is why they are universal now.

- **`Cmp` "How you compare"** takes the card's own metrics rather than a fixed
  list. **Five signals now carry a published age/sex norm**: resting heart rate,
  rMSSD, VO₂max, body-fat percentage, and — added 2026-08-02 — **lean mass via
  the fat-free mass index**. `PeerStandingModel.norm(for:age:sex:)` returns `nil`
  for everything else and the section *names* those signals rather than dropping
  them, because two rows out of nine implies the other seven were checked and
  found unremarkable.
  - **FFMI (Kyle et al. 2003, n=5 635, BIA)** places lean mass ÷ height², not raw
    kilograms — a tall person carries more of everything, so raw lean kg cannot
    be compared across people. It needs a height (unnormed without one) and the
    row labels itself in kg/m². The reference is BIA-measured, matching the
    reader's scale, which is the point.
  - **The section now has three buckets, not two.** Blood pressure used to sit
    under "no published norm", which reads as the app not knowing what a healthy
    reading is — the miscategorisation the user found. It is **assessed by
    clinical category** (ACC/AHA stages), a stronger statement than a centile,
    and has its own labelled group (`Output.assessedByCategory`) pointing at the
    Blood Pressure card. A **modelled** quantity (`activeMedicationLevel`) is
    dropped from the comparison entirely — there is no population for "your drug
    in your system", and listing it as "no norm yet" would imply one is coming.
  - **Deliberately still not normed, and why** (researched 2026-08-02): **SDNN**
    — Apple computes it over ~60 s while the only published reference (Nunan
    2010) is 5-minute, a window mismatch that biases the typical user below the
    50th centile; **sleep duration** — real age/sex data exists (Lee 2026) but
    it is U-shaped, and the monotonic `Norm` would reward oversleeping; **weight
    / BMI** — non-monotonic and obesity-skewed; **bone mass / body water** —
    BIA-specific with no population age/sex summary. Crowd-sourced comparison for
    these is scoped in `docs/progress.md` ▸ "Crowd-sourced norms".
- **`Nrm` "How far from your normal"** is narrowed to the card's metrics, except
  on Readiness, whose subject *is* the whole seventeen-vital scan.

**Heart Health lost its bespoke section to this** — "How you compare" was it —
and gained `heartResponseCard`, which exists because of what the promotion
exposed: everything else this app says about the heart is calibrated on middle
age. SCORE2 is validated 40–69 and ASCVD 40–79, so the risk card and heart age
say *nothing* to a 25-year-old. Heart rate recovery is the one cardiac marker
whose published threshold is a fixed count of beats rather than a curve through
age — 12 bpm or fewer in the first minute marked roughly double six-year
mortality across 2 428 adults (Cole et al., NEJM 1999) — so it reads the same at
25 and 65. Beside it sit resting rate and rMSSD as a pair, because they come off
one beat-to-beat stream and only agreement between them is evidence.

⚠️ **One row owed to the table below (left for its owner, 2026-08-07).**
`SleepStageAverageChart` is new and belongs in the chart audit as:
`○` wraps the wrapper · `○` pan/zoom · `○` scrub · **`●` honours the card's
timeframe** — it is the only chart on the sleep card that does, which was the
whole of backlog P22. It does not wrap `ScrollableMetricChart` because its x
axis is *hours per night*, not time, and it is `substance-shading: exempt` for
the same reason — the second honest exemption after `FitnessProjectionChart`,
so the sentence below saying that chart is "the one exemption" now needs a
second name.

### Feature audit — what each chart supports

**Substance shading is universal as of 2026-08-03** and so is not a column:
`ScrollableMetricChart` draws it for everything wrapping it, `EnergyCurveChart`
and `NightSleepChart` call `SubstanceShading` themselves, and
`FitnessProjectionChart` and `SymptomRadarWebCard` carry the written exemption —
one has months-ahead on its x axis, the other has no axis at all, so a window
that happened yesterday has nowhere to land. `verify.sh` fails on any new raw
`Chart {}` that does none of the three. See the `add-chart` skill ▸ 9a.

⚠️ **Recounted 2026-08-07 (backlog D48). The table listed eleven
`ScrollableMetricChart` wrappers; there are thirteen** — `SleepOnsetChart` and
`DerivedSeriesChart` had never been added — **and one raw `Chart` in the app was
missing from the census entirely.** Sizing a "sweep every chart" pass off the old
table under-counted the charts §B13 applies to by two, which is exactly how such
a sweep ships having missed some.

The census, as verified against the source:

- **13 wrap `ScrollableMetricChart`** — the thirteen `●` rows below.
- **4 build a raw `Chart` of their own**: `ScrollableMetricChart` itself,
  `EnergyCurveChart` and `NightSleepChart` (both call `SubstanceShading`), and
  `FitnessProjectionChart` (exempt, in writing).
- **1 more raw chart the lint cannot see** — the inline
  `Chart(charted) { point in … }` at `DataTabView.swift:1202`, the raw-identifier
  data page's own line-and-point plot. It wraps nothing, calls nothing and
  carries no exemption. `verify.sh`'s census greps for `Chart[ ]*\{`, so the
  `Chart(data) { … }` initialiser form is invisible to it and the file passes.
  **This is a lint gap, not a decision** — see §4 ▸ Still open.
- **5 draw a figure by hand, deliberately not with Swift Charts**:
  `PeerStandingStrip`, `VitalDepartureStrip`, `RiskProjectionBar`,
  `ScoreBalanceWeb` and `SymptomRadarWebCard`, plus `ageEstimateStrip` and
  `biologicalAgeRow` inside `InsightDetailView`. None has a time axis; the polar
  two sidestep the `Chart3DContent` overload hazard as well.

| Chart | Wraps `Scrollable­MetricChart` | Pan / zoom | Scrub line | Honours the card's timeframe |
|---|---|---|---|---|
| `ScoreHistoryChart` | ● | ● | ● shared | ● `window(spanning:)` |
| `MetricOverlayChart` | ● | ● | ● shared | ● |
| `BloodPressureChart` | ● | ● | ● shared | ● takes `timeframe` |
| `MultiSourceChart` (metric detail + Sleep's breathing section) | ● | ● | ● shared | ● |
| `ScoreComparisonChart` (Insights list) | ● | ● | ● shared | — no picker on that screen |
| `AgeHistoryChart` | ● | ● | ● shared | ● **fixed 2026-08-01** |
| `SubstanceLoadChart` | ● | ● | ● shared | ● **fixed 2026-08-01** |
| `BodyCompositionTrendChart` | ● **2026-08-01** | ● | ● shared | ● |
| `SleepOnsetStripChart` | ● **2026-08-01** | ● | ● shared | ● re-fits per window |
| `SleepOnsetChart` (Sleep ▸ "How fast you fall asleep") | ● **missing from this table until 2026-08-07** | ● | ● shared, or the card's binding | ● takes `window`, and re-fits its band per visible window |
| `MedicationCurveChart` | ● **2026-08-02** | ● | ● shared | ● takes `window` |
| `MedicationResponseChart` | ● **2026-08-02** | ● | ● shared | ● takes `window` |
| `DerivedSeriesChart` (Data ▸ Generated insights) | ● **missing from this table until 2026-08-07** | ● | ● own `selection` | — a data page, no timeframe picker: fixed 90-day default |
| `EnergyCurveChart` | ○ calls `SubstanceShading` itself | ○ | ● shared **2026-08-01** | — within a single day |
| `NightSleepChart` | ○ calls `SubstanceShading` itself | ○ | ● shared | — within a single night |
| `FitnessProjectionChart` | ○ **exempt, in writing** | ○ | ● **2026-08-01**, numeric axis | — twelve months ahead |
| inline `Chart` at `DataTabView.swift:1202` | ○ ⚠️ **no shading, no exemption, invisible to the lint** | ○ | ○ | ● takes the page's own `timeframe` |
| `PeerStandingStrip` | — hand-drawn | — | — | — position, not time |
| `VitalDepartureStrip` | — hand-drawn | — | — | — position, not time |
| `RiskProjectionBar` | — hand-drawn | — | — | — a projection, not a series |
| `ScoreBalanceWeb` (Insights list) | — hand-drawn `Path` | — | — | — polar, no axis |
| `SymptomRadarWebCard` | — hand-drawn `Path`, **exempt in writing** | — | — | — polar, no axis |
| `ageEstimateStrip`, `biologicalAgeRow` (in `InsightDetailView`) | — hand-drawn | — | — | — the axis is *age*, not time |

### "Weight management" is a section of its own, and the level is a metric

**Two changes on 2026-08-02, both the user's.** The medication moved out of
"What you're made of" into its own top-level bespoke section — *"I want to
actually put the medication on its own section, called weight management.
Meaning body comp will have two bespoke sections"* — and **"on board" is gone**
from every surface. It was the pharmacology's own jargon; the reader asked for
*"medication in your blood or something just better"*. It is **"in your
system"**, not "in your blood", because the model is a whole-body compartment
and not a plasma assay — saying blood would claim a measurement nobody took.

**`MetricType.activeMedicationLevel` is the app's only modelled metric.** The
same request: *"I also want that data point to go into the 'what goes into
this' chart."* That chart, the baseline machinery and the whole contributor
pipeline speak `MetricType` and `HealthMetricSample`, so nothing else could
carry the level onto it. `PharmacokineticsModel.dailySamples` emits one point a
day, `AppModel.refreshMedicationLevelSamples` folds them into `samples` on every
recompute (idempotently — the previous derivation is stripped first), and it
lands as a contributor via `BodyCompositionInsight.trackedNotScored`.

Three things keep it from being read as a measurement:

- **`MetricSource.calculated`** on every sample, so the overlay legend, the
  per-source breakdown and the export all say *"Worked out by this app"*.
- **Its own `MetricFamily.pharmacology`.** `.body` would have put it in weight's
  family, and same-family pairs are suppressed as tautologies — hiding the one
  relationship the metric exists to show.
- **Weight 0, not 2%.** The user offered it a small weight so it would appear
  on the chart. The chart draws `contributors` rather than weights, so weight 0
  gets it there anyway — and a weight would assert that more or less of a
  prescribed drug is *better*, which is meaningless and is the opposite of what
  this app says about medication everywhere else. What the drug is doing is
  already scored: that is `rateWeight`, the speed the weight is moving at.

It is deliberately **not** in the Data tab's metric categories. It already has a
home there under `DataDomain.medication`, and listing it beside measured vitals
would be the one place the distinction blurs.

### The medication section is now six sections

`MedicationSection` began as one chart of milligrams on board. That answers a
question about the *drug* and none about the reader — the user, after showing
Shotsy's Results tab: *"I want the medication board graph to be in this new
Medication section, and for you to overlay weight, fat, relevant stats onto it..
so I can see how well it's working."*

`MedicationResponse` (InsightKit, 16 tests) is the engine. It attributes the
weight record to the dose history: each dose owns the stretch until the next
one, and the weigh-ins nearest each boundary — within ten days, symmetric —
give that stretch its change. From that come the ladder table, the site table,
and the overall four figures.

Three things about it are deliberate and worth not undoing:

- **Attribution by timing is not cause**, and `SectionCaveat.doseAttribution`
  says so on every table that draws it. Early loss on a GLP-1 is faster at any
  dose, so the first rungs of a ladder always flatter themselves.
- **A dose step with no weigh-ins keeps its days and its count but gets no
  rate.** Dropping it would shorten the denominator and inflate the per-week
  figure for that step — a made-up number where a dash belongs.
- **The overlay is standardised, not dual-axed.** `MedicationResponseChart`
  puts milligrams, kilograms and percent on one axis as z-scores against each
  series' own window mean. Two y-axes is how any two lines can be slid until
  they agree; `MetricOverlayChart` already refused to do it and this follows.
  The scrub read-out carries the real numbers, so nothing is hidden.
  `ResponsePoint` exists rather than reusing `NormalizedPoint` for one field:
  `isInferred`, so a curve resting on doses `TitrationEngine` worked out stays
  **dashed** after normalisation instead of becoming a solid guess.

Injection sites are recorded and shown, with a note that they are not a
comparison — rotating sites is about the skin, and any difference in the table
is far more likely to be which weeks the reader happened to inject where. The
dose sheet offers the sites **already in the record**, so a hand-logged dose
groups with imported ones instead of starting a second name for the same place.

**Seven of twelve charts pan** — the five that don't never wrapped the shared
component. Three of those (`EnergyCurveChart`, `FitnessProjectionChart`,
`NightSleepChart`) are correctly exempt: hours within today, twelve months
ahead, and one night — none has history to scroll back through.

**Two charts pan but ignore the picker above them.** `AgeHistoryChart` and
`SubstanceLoadChart` both declare `var window: TimeInterval = <default>` and
neither call site passes one, so setting the card to "Week" leaves the heart-age
chart on a year and the substance chart on ninety days. This is the specific
shape of "the graphs conform to the date range, but only some of them", and it
is **a one-line fix at each call site** — the parameter already exists.

### Signals the merge newly wired in

`dayStrain` reached **no insight at all**; `heartRateRecovery` and
`walkingHeartRateAverage` reached only the vitals scanner, never a score. All
three are now on Fitness. ~~They contribute at **weight 0** — real signals worth
charting, but no validated 0–100 curve exists for them here, and an invented
weight inside a score the user is asked to trust is worse than none.~~
**Superseded 2026-08-01**: all three carry a share now, judged against the
reader's own baseline rather than a curve nobody has published — see
"Everything charted carries a share" above. Struck through rather than deleted
because the argument is still correct about *inventing* a weight, and a future
session reading only the replacement would not know what it is a replacement
for.

The absolute temperatures (`skinTemperature`, `bodyTemperature`) joined Sleep
for the same reason: the card read the *deviation* and nothing read the absolute,
which on a device reporting only the absolute was the whole signal.

### Declared and never read — the gap nothing was checking

_Found 2026-08-01, four instances, all by hand._ Two directions exist and only
one was tested. `ContributorsTests.testReportedContributorsAreAlwaysDeclaredInputs`
catches a card charting a metric it never declared. Nothing caught the commoner
direction: **a card declaring a metric and then never reporting it.**

The consequence is invisible rather than wrong, which is why it survived.
`ChartedContributions.resolve` substitutes the declared list only when a card
reports *nothing* — so on a card that reports anything at all, a
declared-but-unreported input charts nowhere, links nowhere under "Full history",
and appears in no legend. The paragraph above claiming the absolute temperatures
"joined Sleep" is the shape of it: they were declared and read by nothing.

| Card | Declared, unread | Where it *was* visible |
|---|---|---|
| Heart Attack & Stroke Risk | VO₂max, vascular age — **not even declared** | its own "Heart age over time" chart, and a driver line |
| Heart Health | heart-rate recovery — **not even declared** | the whole of its own bespoke section |
| Energy | heart rate, resting heart rate | a driver line, "5.2 h with your heart rate above resting" |
| Sleep | skin temperature, body temperature | nowhere — the term silently took its neutral 75 |

`testEveryDeclaredInputWithDataIsActuallyRead` now closes the class. The
exception it has to allow is *alternatives* — rMSSD or SDNN, a deviation or an
absolute — and that is `MetricType.interchangeableGroups`, two rows of data
rather than a per-model exception list, which only ever catches the models
somebody remembered to leave out of it.

---

## 2. Metric detail screens

`MetricDetailView` switches on `subject.presentation` into three structurally
different bodies. Unchanged by the consolidation.

| Section | `cumulativeTrend` | `fluctuatingRange` | `cumulativeTotal` | `discreteBivariate` | `staticAttribute` |
|---|---|---|---|---|---|
| summary card | Change over this period | Range over this period | Daily totals | ○ | current value |
| timeframe picker | ✅ | ✅ | ✅ | ✅ | ○ |
| chart | `MultiSourceChart` | ✅ | ✅ | `BloodPressureChart` (shared) | ○ |
| per-source breakdown / averages | ✅ | ✅ | ✅ | ○ | ○ |
| reference range + provenance | ✅ | ✅ | ✅ | in the chart's legend | ○ |
| substance-window shading | ✅ | ✅ | ✅ | ○ | ○ |
| log-scale toggle | ○ by presentation | ✅ | ✅ | ○ | ○ |
| calibration · history · add | ○ | ○ | ○ | ✅ | Earlier entries |

---

## 3. List, tab and settings surfaces

| Surface | Cards, in order | Which insights it lists |
|---|---|---|
| **Today** | summary · suggestion · Last night · Vitals glance · 4 daily tiles | `cadence == .daily && isWorthShowing` |

**`isWorthShowing` grew a third arm on 2026-08-02**:
`InsightResult.isAwaitingTodaysData`. Readiness and Energy score *today*, so a
morning before the wearable syncs left them with no `primaryValue` — and both
cards vanished from Today while their empty copy told a user with months of
nights to "record a night". With ≥7 recorded days and a reading no older than 3
days they now stay listed as "Waiting for today's sync" / "Waiting for last
night"; a fresh install (or a wearable abandoned longer than that) keeps the
old copy and stays hidden, so the placeholder-card rule survives. The
Last-night tile joined the same truth: a stale night is titled "Yesterday's
night" with a sync hint, not "Last night".
| **Insights** | "Improve your health" · subtitle · score comparison · 5 trend tiles | `cadence == .trend && isWorthShowing` |
| **Data** (3rd tab) | search bar, then `DataDomain.allCases` in case order: 4 metric groups · Blood pressure · Substances · Medication · Side effects · Other data | rows, not cards |
| **Settings ▸ Add or update data** | `InputGroup.allCases` → `InputKind` rows: About you · Log as it happens · Bring data in | the master input list |
| **Settings ▸ Export my data** | inventory (Markdown) · full export (JSON) · browse the unmodelled | the development feedback loop |

**Tab order and the rename, 2026-08-02.** Today · Insights · **Data** · Settings.
Vitals was second and is now third and called Data, at the user's request. Both
halves were overdue: the order reads as *now → what it means → everything
underneath*, and the tab had stopped holding only vitals — it carries the
substance log, the medication regimen, side effects and the raw imported
catalogue, and `DataDomain` exists so that list keeps growing. `VitalsView` is
`DataTabView`, in `Features/Data/`.

**Data is now generated from an enum, and that is the point.** The tab is the
app's answer to *"what does this thing actually know about me"*, and that claim
only holds if it is complete — which it kept not being, because each section was
hand-written and completeness depended on somebody remembering. The substance
log was reachable only from a toolbar button for weeks; medication doses and
imported side effects were written to the store and listed nowhere. The user's
rule, 2026-08-02: **"whenever we add new data, it must have an entry in that
tab."**

So `DataTabView.body` is `ForEach(DataDomain.allCases)` into an **exhaustive**
`switch`, and `DataDomain` (InsightKit, `Presentation/DataDomain.swift`) carries
the section's title and summary. A new kind of data is a compile error in the
app target until it has a section. Same mechanism as `MetricType`'s eight
switches and `ContributionRoute` — and the reason it is an enum rather than a
list of section builders is that the app target has no test target, so the
compiler is the only thing that can hold a rule there.

`DataDomain` is deliberately **not** `MetricType`. A metric is one measured
series; a domain is a *shape* of data — a dated log, a set of paired readings, a
regimen with a decay curve — and most of these are not series at all, which is
exactly why they kept falling out of a screen built around series. Composition
scans, when they land, add a case and the build tells you where to put it.

**Search narrows it, and never reorders it.** `DataTabView` is `.searchable`,
and `isVisible(_ domain:)` is a second **exhaustive** switch over `DataDomain`
— so a new kind of data has to say how it answers a search, rather than
quietly never appearing in one. The query matches a row's name *and* its
domain's title, because the section headings are the vocabulary a reader has
actually seen: typing "medication" narrows to that section rather than to
nothing. `MetricGroup` is identified by its title now; it defaulted to
`UUID()`, which made every keystroke rebuild the whole list as new rows.

**The input side got the same treatment: `InputKind`.** `DataDomain` guarantees
every kind of data can be *seen*; `InputKind` (InsightKit,
`Presentation/InputKind.swift`) guarantees every kind can be *given*. The app
had four input surfaces — Settings' "Your details", the Today `+` menu, a card's
"View & add", and a Settings row for the blood-test photo — each a hand-written
list, so each went stale separately. Settings offered nine facts while the app
accepted fourteen kinds of input; `weightGoal` shipped and appeared in none of
them. The user: *"make sure it gets updated every time a new input is in the
app, also collapse this into a sub menu because it will get too long."*

- `InputKind.allCases` × `InputGroup` generates `AddDataView`, the sub-menu
  Settings now pushes to instead of listing facts inline.
- The Today `+` menu is `AddInputMenu`, from the same enum.
- `View.inputSheet(_:)` holds **one** exhaustive switch saying what each input
  opens, so a new input works on every surface at once.
- `ContributionRoute.inputKind` is exhaustive, so a card route cannot exist
  without a master-list entry.
- `GroundingKind.isEnteredDirectly` replaced Settings' array of nine. The one
  `false` is diastolic, which arrives with systolic.
- Side effects became enterable by hand (`SideEffectEntrySheet`) — they could
  previously only arrive inside a Shotsy backup.

**And the rule that binds all four surfaces, 2026-08-02.** The user found the
gap the enum had not closed: *"there are things on the body comp page that are
not in the add and view.. body type, log a dose, import from file"* — inputs
offered by a button inside a chart and declared nowhere. `InputKind` guaranteed
every *declared* input reached every surface; nothing guaranteed a card
declared what it offered.

`InputKind.cardRequirement` is that guarantee, exhaustive, with three answers:

| | Meaning |
|---|---|
| `.offeredAndPrompted` | On a card's "View & add", **and** prompted for while never used |
| `.offeredOnly` | On a card's "View & add", never nagged for |
| `.settingsOnly(reason)` | Reachable from Settings alone, for a stated reason |

Three checks hold it, and each catches a different half:

1. **`InputKindTests`** — every `mustBeOfferedOnACard` kind appears in some
   shipped model's `contributions`, and no `settingsOnly` kind does. This is
   the check the user asked for.
2. **`verify.sh`** — any `…Sheet` view under `Features/` must be named in
   `AddDataView.swift`. The test above only binds inputs somebody *declared*;
   this catches the ones nobody did, which is what actually happened.
3. **`SuggestionEngine.unusedInputs`** — a `promptsWhenNeverUsed` kind that has
   never been used becomes a dismissible "Improve your health" row, which is
   what puts it on Today. Ranked *below* a grounding fact costing a card its
   score (strength 0.15): "a feature you haven't tried" must never outrank
   "this card cannot produce a number without it".

`ContributionRoute` gained `.medication` (regimen, doses and side effects —
one conversation, one button) and `.bodyType`, and its mapping to `InputKind`
became **plural** so a route standing for three inputs cannot leave two of them
undeclared.

**And the section collapsed to one button, 2026-08-02 (evening).** Rendering
every route at full size was right for one route and wrong for four: Body
Composition stacked four blocks with four identical prominent buttons down its
card. The user, from a screenshot: *"It should just be one add button, and this
should show you the ability to add new data and view all previous data and
inputs."* The split is now:

- **The card** (`ViewAndAddSection`) carries one status line per route — seal,
  name, figure — and **one** button, so a new kind of data costs the card a
  line, not a block.
- **The button opens `ViewAndAddHubView`**, a sheet holding the full anatomy
  per route: guidance, the add affordances, and the way into what has already
  been given. Its `section(for:)` is the exhaustive switch over
  `ContributionRoute` now; `ContributionRouteStatus` is the one place a route's
  name and `ContributionSummary` are resolved, read by card rows and hub
  sections alike so the two can never disagree.
- **Every route can show its history.** Medication was the gap — doses were
  visible only as aggregates in the Weight-management tables — and gained
  `MedicationHistoryView` (every dose and side effect, newest first, estimated
  doses labelled). `.fileImport` gained a summary factory so it renders through
  the same anatomy as everything else.

**Then viewing itself consolidated, 2026-08-02 (evening, round 2).** The user:
*"we can have multiple data sources… figure out how it views data in a
consolidated way"* — and chose **one data screen per card**. The hub's per-route
*view* links (metric screen, dose history, facts list, each separate) collapsed
into a single "View all this card's data" link at the top of the hub, opening
`CardDataView` — the card-scoped twin of the Data tab: the signals the card
reads (same rows as `DataTabView`, latest value + source count), then its logs
and inputs (BP readings, substances, doses & side effects, imports, build,
details), each opening the full record. A route in the hub is now purely *add*;
viewing is the one consolidated screen. `CardDataView.routeSection(_:)` is
exhaustive over `ContributionRoute`, the same discipline `DataTabView` enforces
app-wide.

**Today lost "Improve your insights" on 2026-08-01.** `GroundingPromptBanner`
listed the same grounding gaps that `SuggestionEngine.unlocks` already emits as
`.unlockAnInsight` — reaching the reader twice, through the dismissible
`suggestionCard` on Today and the full "Improve your health" list on Insights.
Two surfaces for one set of facts, and only the suggestion could be dismissed,
so waving a prompt away on Today left the same prompt on Today.

The one thing the banner said that the suggestions did not — that a fact was
**stale** rather than absent — moved into `unlocks` rather than going with it.
`unmetRequirements` is "not satisfied", which covers both, and "add your
cholesterol" to someone who added it last year reads as the app having lost it.
`AppModel.outstandingGrounding` went too; the engine's own remains.

---

## 4. The gaps

### Closed

1. The timeframe picker is a screen-level control, not trapped inside "Score
   over time" — which it outlived by three sections.
2. "What comes first" / "What changed" lost their cadence gate.
3. One placement rule for the bespoke slot, above "Score over time".
4. Both tabs share one listing rule, `InsightResult.isWorthShowing`.
5. One "View & add" section on every card that takes input, and blood pressure's
   chart on the card that talks about it.
6. **Seventeen cards became nine.** The overlap *was* the inconsistency.

### Still open

0. ⚠️ **Eight bespoke sections vanish instead of saying why** — found by the
   D15 doc-truth sweep, 2026-08-07. Mental health, Stress load, Nutrition,
   Metabolism, both of Biological age's, and the two calendar review lists are
   `if let out { InsightSection(…) }` with no `else`, so the card's own picture
   of its own subject is simply absent when its model returns `nil`. Gait covers
   one of its two empty arms. This is the exact regression the 2026-08-01 pass
   closed, reintroduced by every card built after it, and it is undefended:
   **nothing in `verify.sh` checks that a bespoke section has an `emptySection`
   path**, and the shape compiles because a bare `if` in a `@ViewBuilder` is
   legal. The fix has two halves — the eight `else` arms, and a lint that makes a
   ninth impossible. See the per-section feature audit above for which arm each
   one is missing.
0b. ⚠️ **One raw chart is outside the substance-shading lint's reach** — found
   by D48 the same day. `verify.sh` finds raw charts with
   `grep -rlE '(^|[^A-Za-z0-9_])Chart[ ]*\{'`, which matches the `Chart { … }`
   trailing-closure form and **not** `Chart(data) { … }`. The inline plot at
   `DataTabView.swift:1202` uses the second form, wraps nothing, calls
   `SubstanceShading` nowhere and carries no exemption — so the reader's
   raw-identifier data pages draw the one chart in the app with no shading on it,
   and the gate says nothing. Widening the pattern to `Chart[ ]*[({]` is the
   whole fix on the lint side; the chart itself then needs a wrapper or a written
   exemption.
7. ~~**Three cards have no bespoke section**~~ — ~~**closed.** All nine now have
   one.~~ ⚠️ **REOPENED 2026-08-06 by audit: five of fourteen fall through to
   `default: EmptyView()`** — gait, sustainedLoad, nutrition, metabolism and
   readiness. **Update, same day: sixteen cards now, and six without one** —
   biological age shipped *with* its section (`biologicalAgeMarkersCard`, the
   one that makes the card not a black box), and mental health shipped without.
   **CLOSED, properly this time, 2026-08-06: `bespokeSection` is now exhaustive
   over `InsightID`.** `default: EmptyView()` is gone, so a new card cannot ship
   without a stated decision about its own picture. Five sections were written
   in one pass — gait's `speed = step length × cadence` split, mental health's
   and Stress load's signed departure strips (one shared implementation, because
   two renderings of one encoding is how the chart gap-bridge defect happened),
   Nutrition's vitamins-and-minerals table, and Metabolism's observed-against-
   predicted bars. **Readiness is the one `EmptyView()` and it is a decision
   rather than a gap**: its subject *is* the seventeen-vital scan, and
   `vitalDepartureSection` — which was Readiness's bespoke slot before it was
   promoted to universal — still draws all seventeen rows for this card. A
   second one would render the same strip twice. The earlier audit listed
   Readiness as sectionless, which was true of the switch and false of the
   screen: the cost of reading a `default:` instead of the card. The claim was true of nine cards and stopped being true the moment
   the tenth shipped, which is the failure mode a "closed" tick invites. For
   **gait** it is not cosmetic: that card's whole reason to exist is the
   `speed = step length × cadence` decomposition, and with no section it reaches
   the reader as one driver line inside a generic card. The rest of this item
   still records what was true then: Heart Health and Readiness share `weightedContributionCard` ("How this
   is weighted"), drawn from `InsightResult.contributors`' renormalised weight —
   no new type and no model change, exactly as Phase 2 predicted. Body
   Composition got "What you're made of", backed by `BodyCompositionSplit` in
   InsightKit (12 tests). ~~**The bespoke switch keeps its `default:`** even
   though all nine cases are now named: making it exhaustive would add a sixth
   build-breaking switch over `InsightID`, which `activeContext.md` singles out
   as the most expensive way to add a feature here.~~ **Reversed 2026-08-06 and
   the reversal was right** — the `default:` is what let five cards ship with no
   picture at all, and a build break is cheaper than a silently sectionless card.
8. ~~**Caveat footnotes and header trailing stats are ad-hoc.**~~ **Closed
   2026-08-01** (`dc5fae6`). Every section now goes through `InsightSection`
   (or `NestedInsightSection`), which carries the title, at most one figure and
   the caveat, at one spacing and one footnote colour.

   **The rule is enforced by the compiler, not by a convention.** `caveat` has
   no default value, so a section cannot be written without stating one and
   `.none` is a visible choice. The previous convention was followed by four
   sections out of twelve, and the one it was skipped on — "What comes first",
   a correlation at a lag fitted through however many days two series overlap
   on — was the most inferential claim on the screen.

   The words are `SectionCaveat`, in InsightKit, with tests. Two defects fell
   out of moving them there: the body-composition caption opened *"Height is
   your weight"*, and it pluralised "across 1 weigh-ins".

   The trailing slot now carries **one quantity**. It used to show a kilogram
   delta *or* a count of weigh-ins in the same position on the same card.
9. **Two presentation flags no view consults** —
   `MetricPresentation.allowsTimeframeSelection` and `.showsChart` are read only
   by `PresentationTests`.

16. ~~**"How this is weighted" said "Not a weighted average" on four cards.**~~
   **Closed 2026-08-01.** It was true on one of them. See "How this is
   weighted says how, on every card" above for the three it was wrong on, the
   method used for each, and the second group the section now draws.

17. ~~**Four cards declared or drew a metric that reached "What goes into this"
   on no card.**~~ **Closed 2026-08-01**, with the invariant that catches the
   next one — see "Declared and never read" above.

19. ~~**Four cards said "Not a weighted average"; three had computable
   shares.**~~ **Closed 2026-08-01**, and then closed *again* the same day at
   the user's direction — the first pass computed the missing shares and kept
   the weight-0 signals as a named second group, and the user's answer on
   seeing it was that everything charted should carry a weight. Both steps are
   above.

   **The lesson is about the shape of the original rule, not about the
   numbers.** "An invented weight is worse than none" is a true statement that
   was doing work it could not support: it argued against *inventing*, and it
   was being used to justify *not attributing*. The two are different, and the
   gap between them shipped as a section listing seven inputs of which one went
   into anything. Same shape as *"that technique has a fatal flaw" is not "this
   is impossible"*, already in `activeContext.md`.

18. ~~**Sleep's contributor weights are still a hand-written restatement of its
   score expression.**~~ **Closed 2026-08-01.** The nine coefficients moved
   into `SleepInsight.Weight`, one table both the score expression and the
   contributors read — including the two derived lines (`durationLine` folds
   consistency and debt into duration's line; `stageLine` halves the
   restorative term across deep and REM), which were the numbers most likely
   to drift because neither appeared verbatim in the score.
   `testContributorWeightsMatchTheWeightsTheScoreApplies` still pins that the
   chart's weights sum to 1. Sleep's score is one expression rather than a
   separable model, so it got a shared table rather than Energy's
   `Output.terms` — same category of fix (the duplicate is impossible, not
   merely tested), smaller mechanism.
10. **Body Composition's "view & add" scan entry** — a further
   `ContributionRoute`. Deferred by the user on 2026-08-01 to its own session.
   The capture it points at is the camera + LiDAR body scan, which is
   deliberately a roadmap note and is ARKit, so it cannot be exercised from a
   sandbox at all. Adding the case touches `ContributionRoute`,
   `ContributionRouteStatus`, the exhaustive switch in
   `ViewAndAddHubView.section(for:)`, an override on
   `BodyCompositionInsight` (which already returns four routes), and the skip
   list in
   `ContributionRouteTests.testGroundingFactsAreDerivedFromTheModelsOwnRequirements`.

11. ~~**The legend under "What goes into this" stated one fact out of three.**~~
   **Closed 2026-08-01.** Each row printed whichever of *direction*, *is that
   direction good* and *weighting* an `if` reached first: the weight where there
   was one, the trend otherwise, and the good-or-bad verdict only where the
   model had declared a direction. So which of the three was missing varied row
   to row, with nothing on screen to say which. All three now render on every
   row, of every legend, on every card — `LegendCaption`, in InsightKit.

   The interesting part is what fell out of it. `weight: 0` and
   `higherIsBetter: nil` are real *findings* in some rows — `dayStrain` is
   deliberately unscored, a temperature deviation deliberately has no good
   direction — and pure *absences* in others, because
   `InsightDetailView.resolvedContributions` substitutes an insight's declared
   inputs when it reports none, and the stand-ins carry exactly those values.
   Rendered naively, every row of such a card announces itself as "tracked, not
   scored · neither direction is better", two claims no model made. **Substance
   Impact before its first logged event is the live case**, found by a test
   written for something else. `ChartedContributions` carries the distinction
   now; `ContributorsTests` pins that Substance Impact is the only insight that
   reaches it.


12. ~~**No bespoke section has an empty state.**~~ **Closed 2026-08-01.** All
   eleven vanished when their data didn't clear a floor — exactly the behaviour the nine generic sections were
   moved away from on 2026-08-01, for a reason that applies here unchanged: an
   absence cannot be read. "Your fortnight" missing means no sleep data *or*
   fewer than `CircadianConsistencyModel.minimumNights` nights; "How you compare"
   missing means no date of birth *or* nothing comparable recorded. Each needs
   its own `SectionPlaceholder` reason, derived from its own floor.

13. ~~**Two charts pan but ignore their card's timeframe.**~~ **Closed 2026-08-01.** `AgeHistoryChart`
   (fixed 365 days, on Fitness and Heart Attack & Stroke Risk) and
   `SubstanceLoadChart` (fixed 90 days, on Substance Impact) both take a
   `window:` parameter that no call site passes. One line each.

14. ~~**Two time-series charts cannot be panned.**~~ **Closed 2026-08-01.**
   `BodyCompositionTrendChart` now wraps the shared component. The bedtime strip
   needed `CircadianConsistencyModel` split first — reading the nights is the
   expensive half, fitting a centre to them is arithmetic — so the strip re-fits
   over whatever comes into view and every number it draws describes the nights
   it is drawn against. Original text: `BodyCompositionTrendChart` and
   `SleepOnsetStripChart` draw their own `Chart` rather than wrapping
   `ScrollableMetricChart`, so the only way to see further back is the timeframe
   picker — and `SleepOnsetStripChart` does not read that either, so on that one
   there is no way at all. `EnergyCurveChart` and `FitnessProjectionChart` are
   correctly exempt: one is a single day, the other is a forecast.

15. ~~**`EnergyCurveChart.selectionMark` is a byte-for-byte copy of
   `ScrubIndicator.at`** — same colour, same stroke, same deliberate
   `ForEach`-over-one construction that avoids the `Chart3DContent` overload
   hazard. It predates the shared type (whose own doc comment says "only the
   energy curve had one") and was never migrated. Identical today; the shared
   type exists precisely because the same four lines in several files becomes
   several slightly different behaviours.~~ **Closed 2026-08-01**, along with
   the last chart that had no scrub at all: `FitnessProjectionChart` plots
   months-ahead rather than dates, so `ScrubIndicator` gained a `Double`
   overload and the read-out interpolates along the line the marks draw.

---

## How to keep this current

- **Columns** come from `InsightDetailView.body`.
- **Rows** come from `InsightID.allCases` — **eighteen** as of 2026-08-07. This
  line has now been wrong twice, saying nine and then fourteen while the enum had
  moved on, so do not read the number: count it.

  ```bash
  awk '/^public enum InsightID/,/^}/' \
      InsightKit/Sources/InsightKit/Insights/Insight.swift | grep -c '^    case '
  ```

  See the `add-insight` skill for the switches a new id feeds.
- **Cell values** come from each model's `InsightResult` plus its `requirements`
  and `contributions`.
- **`V&A` is derived, not switched** — `InsightModel.contributions` defaults to
  `requirements.isEmpty ? [] : [.groundingFacts(…)]`, so a card gains that
  section by declaring a requirement, with no edit here or anywhere else. That is
  the good design *and* the reason this table goes stale without anyone touching
  it.

⚠️ **Only the ordering block is generated.** `card-map.sh --check` compares it
with `InsightDetailView.body` and `handover-check.sh` runs that — but it says
nothing about the matrix, the gate table, the two feature audits or the gaps,
all of which are hand-written and all of which had drifted by 2026-08-07. A green
`--check` is not evidence that this file is true.

`docs/activeContext.md` is the authority on *why*; `docs/progress.md` is the
history of how it got that way.
