# The backlog — everything open, in one place

_Written 2026-08-06. **This file is the exhaustive list.** `docs/progress.md` is
the historical roadmap and keeps its generated table; this is the flat,
current, nothing-omitted version, because the roadmap's own structure had
started hiding things — a nested item was invisible to the generator for weeks,
and six symptom-radar rows sat open after shipping._

**Rule for this file: nothing gets removed, only marked.** An item that turns out
to be impossible becomes a ❌ with a reason. An item that ships becomes ✅ with a
commit. Deleting a row is how a backlog starts lying.

---

## 0. Start here next session

⚠️ **2026-08-06, second message: the reader answered all 24 open questions and
reversed 11 of the 12 refusals in one go.** §A is now a specification rather than
a blocker, and §B5 is now a build list. **Read §A and §B5 before N1–N3 below** —
they were written when a dozen things were still "no".

**The build order the answers imply**, most-wanted first, by how hard the reader
pushed:

| | Item | Where |
|---|---|---|
| ~~1~~ | ✅ **Own-brand biological age** — shipped `972e2d7` | §B5 #29 |
| ~~2~~ | ✅ **Cuffless BP, ungated** — shipped `0ea9411` | §B5 #28 |
| ~~3~~ | ✅ **Mental health card** — shipped `867129e` | §B5 #27 |
| **1** ◐ | **The cycle tab** — ✅ **slice 1 shipped `a8be5ae`**: the fifth tab, a tappable calendar, the cycle you are in, and the range your cycles fall in. ⬜ **Still to come: the fertile window, the phase model, phase-aware baselines, and the Oura temperature channel.** Those need cycles to predict from, which slice 1 collects | §B5 #31, §A3 |
| ~~5~~ | ✅ **Score decomposition in the deep dive** — shipped `964c03e`, on `ScoreComparisonDetailView` | §B5 #38, S2 |
| 6 | Fitness sections: intensity (feeding the score), steps/distance/flights | §B5 #34–35 |
| 7 | Sound exposure (#33) · sleep apnoea (#30, ⚠️ **identifiers now requested — count the rows before building**) · ~~radar accuracy~~ ✅ `44fb94e` | §B5 #30, #33, #36 |
| 8 | Notifications · delete-everything · export gaps · calendar | Q10–Q13, I1 |
| 9 | Capture for the six zero-row domains | §B5 #37 |

**N1 — Stress, done properly. The reader's instruction, 2026-08-06:** *"I want to
rename it to stress, and research how Oura ring do this, because they track
stress, but lets do it better because we have more data."*

The rename shipped in `0dbc9b6` — "Sustained load" → **"Stress load"**, and the
balance web's spoke reads "Stress". That was the trivial half. The research is
the item.

⚠️ **Oura's own stress data is already in the raw catalogue and read by nothing.**
Measured in the reader's export:

| Field | Coverage |
| --- | --- |
| `oura.daily_stress.day_summary` | 142 days, 90 of the last 90 |
| `oura.daily_stress.stress_high` | same |
| `oura.daily_stress.recovery_high` | same |
| `oura.daily_resilience.level` | present |
| `oura.daily_resilience.contributors.stress` | present |
| `oura.daily_resilience.contributors.daytime_recovery` | present |
| `oura.daily_resilience.contributors.sleep_recovery` | present |

So the comparison is free: **this app's stress score can be graded against
Oura's own, day by day, on 90 of the last 90 days.** No competitor can do that
about itself.

What to establish before building:

1. **What Oura actually measures.** Their stress is a *daytime* signal — it reads
   the day, not the night. This app's Stress load reads four *nocturnal*
   channels over 28 days against 90. Those are different quantities, and the
   first question is whether the reader wants the daytime one, the sustained
   one, or both on one card.
2. **What we have that they do not.** Continuous daytime heart rate, the
   medication schedule and its modelled level, the substance log, cuff blood
   pressure, gait, and — once built — the calendar. Oura has none of that. The
   "do it better" claim has to name which of these carries the advantage rather
   than asserting more data is better.
3. ⚠️ **`daily_stress` is a vendor composite with an undisclosed formula.** It may
   be *shown* as a labelled second opinion; it must never be blended into this
   app's own score, on the same rule that governs `vascularAge` — relay, never
   merge.
4. **The overlap question, again.** Readiness answers *this morning*; the symptom
   radar answers *is something acute converging*; Stress load answers *has this
   lasted weeks*. A daytime stress signal is a fourth window and has to justify
   itself against all three, or it is a fourth rendering of one measurement.
5. **The naming lesson is part of the item.** The reader asked for a stress card,
   it shipped under a name they could not find, and they asked three more times.
   Whatever this becomes, it is findable by the word they think in.

**N2 — the calendar integration** (§D, I1), because it is the single thing that
unblocks two requested cards (travel drain, work impact) and feeds N1's point 2.

**N3 — a bespoke section on every card** (§C, S1), the reader's standing rule
from 2026-08-06, with the design docs updated so it is enforced rather than
remembered. Five cards have none today.

---

## A. Every open question — ✅ ALL 24 ANSWERED 2026-08-06

**The reader answered every one in a single message. Nothing in §A blocks work any
more; every row below is now a specification. Where the reader asked a question
back, my answer is recorded beside theirs — that exchange is the decision and
must not be re-opened.**

⚠️ **The framing that governs all of it, in the reader's own words:**

> *"I want to derive new insights from the data people already have. I am not
> just looking to copy — I want to be ground breaking and unique, we are going to
> do stuff that others will not do. I do not care about compliance at this point,
> it's my personal project for now."*

**So the compliance/clearance objection is retired as a reason to refuse a
feature.** It stays as a reason to *word* a feature carefully — the app still
never dresses modelled as measured (rule 3 in `architecture.md`), and it still
states its own error. What it no longer does is decline to compute something
because a regulator would want a trial first. This is one person's private
project. If that changes — distribution, an App Store listing, a second user —
**§B5's original reasons all come back**, which is why they are preserved below
rather than deleted.

### A1 — Decisions on things already built

| # | Question | ✅ Decision |
|---|---|---|
| Q1 | Substance card at 4 episodes: honest version or wait? | **Ship the honest version.** Per-episode deltas, the named alternative explanation beside each row, no score, and the sentence "nothing has happened the same way often enough to tell it from an ordinary run" |
| Q2 ✅ | BP card shows two ± and two cuff ages on one screen. **Shipped `0ea9411`** | Reader asked *"what do you mean?"* — fair, the row was written for someone looking at the screen. **What it means:** the card prints "±14, fitted to 23 readings" in one place and "the ±13 it is judged on" a few inches below, and "over a day old" beside "2 days ago", so it contradicts itself twice on one screen. **Decision (mine, stated so it is not re-asked): show one ± — the one the estimate is actually judged on — and one cuff age.** The other becomes a line in the detail sheet |
| Q3 ✅ | Fitness age: VO₂ 30 → a 68-year-old's fitness. Right? **Shipped `5330d92`** | **"Honestly doesn't seem right."** Confirmed. Below VO₂ ~36 the norm table is extrapolation off its lowest anchor (32 at 65). **Floor the extrapolation and widen the stated ±.** Moves `FitnessInsight` *and* `HeartHealthScore.vo2Score` |
| Q4 ✅ | Micronutrients: score now or wait? **Shipped `5330d92`** | **Estimate now, state the limitation, name the data that would sharpen it.** Wires `MicronutrientTargets`, which is currently dead code, and makes the Nutrition card's mandatory sex/DOB ask true instead of false |
| Q5 ✅ | Feedback gated so Nutrition/Metabolism cannot be rated. **Shipped `5330d92`** | **Ungate.** One line |

### A2 — Decisions on things not yet started

| # | Question | ✅ Decision |
|---|---|---|
| Q6 | Location: feed first, or both? | **"Just build the whole thing."** Feed and prompt together |
| Q7 | Bloods: manual entry or PDF/OCR? | Reader: *"both? What do you mean? We should be able to accept all of these."* **Decision: all input routes for a blood result — typed, PDF, photographed report, and the existing document scanner.** The question was a false choice and should not have been asked as one |
| Q8 | Supplements: worth the one-time capture? | Reader: *"Yes? From where?"* — **the reader enters them**, by label scan or by typing, because no wearable or health store carries a supplement stack. Then summed **ingredient by ingredient** against published upper limits, which is the part nobody ships. NIH DSLD (200,000+ labels, free API) supplies the ingredient lists |
| Q9 | Mental health: build the computes-nothing Mind section? | **No — build a real card.** *"I want a mental health card. Figure it out, creative licence + data science."* See §B5 #27, reversed |
| Q10 ◐ | Export gaps | **Tokens done (`964c03e`): `OAuthTokens` is no longer `Codable`, so a token cannot be a stored property of any `Encodable` type — a compile error rather than a convention.** The four missing fields are still to build. **Build them. Do not include tokens.** Connection state, suggestion dismissals, the feedback ledger and prediction outcomes are exported; credentials must be **structurally impossible** to serialise, not merely omitted |
| Q11 | Notifications — none exist anywhere | ⚠️ **Sequenced, 2026-08-06.** There is no `BGTaskScheduler`, no `BackgroundTasks` import and no `UIBackgroundModes` in the repo, so anything built today fires **only in the foreground** — a radar flag at 3am could not reach anyone. **Reader's decision: build the background delivery first, then notifications on top.** A symptom-radar alert that only fires when you happen to open the app is not the feature that was asked for. **Build them.** Named by the reader: **symptoms**, and **when a card changes majorly**. Plus *"any other major things you think we should notify on"* — creative authority granted, so: a flagged radar episode opening or closing, a grounding fact going stale (a cuff reading the BP estimate now needs), a body-scan cadence due, and a connector that has stopped syncing |
| Q12 | Write-back to Apple Health | **Wanted, but not yet. Roadmap.** Do not build this session |
| Q13 | Delete-everything path | **Yes** |
| Q14 | Does the app stop launching when the free-team profile expires? | Reader: **"No?"** — reported as not observed. ⚠️ Treated as *unconfirmed*, not as settled: a free-team profile is documented as 7 days, the app has never gone that long without a deploy, so nobody has actually tested the case. Left as a watch item, not as work |
| Q15 | Body scanner ARKit capture priority | **Yes** — build it |

### A3 — Cycle tracking: all four answered, so all ten items are unblocked

⚠️ **Q25, asked and answered 2026-08-06 — the fifth decision, and it was blocking
every line of code.** A scouting pass found the app is *structurally*
single-user: `ProviderCredentialStore` keys on `providerID` alone,
`IntegrationRecord.integrationID` is `@Attribute(.unique)` (one Oura account per
install), and `deploy.yml` reaches exactly one iPhone. The tab is for someone
else's body.

**Decision: she installs the app on her own phone, with her own Oura key.** The
cycle tab is therefore a *feature of a single-user app*, not a second-profile
concept — which is the cheapest of the three answers by a wide margin, keeps her
ring's temperature and HRV in scope (the whole reason this beats Flo), and means
nothing about the profile, the baselines or the cards has to change.

**What that rules out, and it must not be quietly re-opened:** no second
profile, no per-person baselines, no "whose data is this" on any sample. If a
future session finds itself adding a person dimension, that is a different
decision and needs asking again.

⚠️ **And it changes what the data claims mean.** Every zero-row and coverage
figure in this file — `MenstrualFlow` 0, `SexualActivity` 0,
`basalBodyTemperature` 136 — is measured against **the reader's** export.
Nothing here says anything about *her* ring. Do not write "already arriving"
about her record in a doc, a commit message, or on screen.

| # | Question | ✅ Decision |
|---|---|---|
| Q16 | Does the tab draw a fertile window at all? | **"YES! THAT'S THE WHOLE POINT."** The fertile window is the feature, not a stretch goal |
| Q17 | Surface the tirzepatide / oral-contraceptive labelling? | **Yes** |
| Q18 | Who is the tab for? | **The reader's wife.** *"She has an Oura ring, they want a huge amount of money every month for their feature. I want to build it instead since we have all the same data they do."* ⚠️ **This is the single most useful answer in the whole set** and it changes the design: the tab is for a specific person with a specific ring, the competitor is Oura's paid cycle insights (and Flo), and the win condition is *the same conclusions without the subscription* |
| Q19 | The privacy posture | Settled by Q20 |
| — | Zero rows in `MenstrualFlow` / `SexualActivity` | ⚠️ **Still true and still the hard part.** The tab ships with manual entry as a first-class path, and `basalBodyTemperature` (136 rows, 80 of the last 90) plus the ring's nocturnal temperature are what let a cycle be *confirmed* rather than guessed. **Note the data belongs to the wife's ring, not the reader's export** — coverage on her record is unmeasured |

### A4 — Crowd-sourced norms

| # | Question | ✅ Decision |
|---|---|---|
| Q20 | Opt-in per signal? | **"NO — opt-in for everything (by default) with ability to opt out."** So: **on by default, one global opt-out, no per-signal consent matrix.** ⚠️ This is a real change of posture — today nothing leaves the phone — and it is recorded here as the reader's explicit instruction for their own private build |
| Q21 | Contribute automatically once you consume, or separately? | Reader: *"What do you mean?????"* — the question was jargon. **What it meant:** if you use the crowd norms to see how you compare, does your own data automatically join the pool, or is joining a second, separate switch? **Answered by Q20: automatically, on by default, one opt-out covers both** |

### A5 — Small ones

| # | Question | ✅ Decision |
|---|---|---|
| Q22 | Does MyFitnessPal already write into Apple Health for you? | **Yes.** So the food-capture integration is a Settings row saying so, not a build. ⚠️ But `dietaryEnergy` is 0 rows in the last 90 on the export — so it writes when the reader logs, and the reader has not been logging |
| Q23 | Travel drain: calendar enough, or timezone metadata too? | **"EVERYTHING, AS MUCH AS POSSIBLE"** — calendar *and* HealthKit timezone metadata, **plus a manual travel tag the reader can add** |
| Q24 | "Stress card like Oura" — something other than Sustained Load? | **"NO"** — Sustained Load (now "Stress load") is what was meant. N1's research item stands; the card is not missing |

---

## B. Every card ever mentioned

### B1 — Built and shipped (14)

| # | Card | Tab | State for you |
|---|---|---|---|
| 1 | **Readiness** | Today | Scores |
| 2 | **Symptom radar** | Today | Scores. Rebuilt 2026-08-05: calibrated statistic + CUSUM memory |
| 3 | **Sleep** | Today | Scores |
| 4 | **Energy** | Today | Scores |
| 5 | **Heart Health** | Insights | Scores |
| 6 | **Fitness** | Insights | Scores |
| 7 | **Heart Attack & Stroke Risk** | Insights | Scores. Carries the age-comparison section |
| 8 | **Blood Pressure** | Insights | Scores. See Q2 |
| 9 | **Body Composition** | Insights | Scores |
| 10 | **Nutrition** | Insights | ⚠️ **Empty state — has never scored.** 0 logged food days in the last 90 |
| 11 | **Metabolism** | Insights | ⚠️ **Empty state — has never scored.** Same cause |
| 12 | **Sustained load** | Insights | Scores. **This is the stress card** — the name is why it is hard to find |
| 13 | **How you walked** | Insights | Scores. Gait, shipped 2026-08-05 |
| 14 | **Substance Impact** | Insights | Scores. See Q1 |
| 15 | **Biological age** | Insights | Scores. Shipped 2026-08-06. Its own bespoke section shows every marker's age, error and share |
| 16 | **Mental health** | Insights | Scores. Shipped 2026-08-06. ⚠️ Deliberately **off** the balance web — see §E D17 |

### B2 — You asked for them; they do not exist

| # | Card | Blocker |
|---|---|---|
| 15 ✅ | **Travel drain** | **Shipped.** ⚠️ Unverified with real data — The calendar integration now exists and `CalendarModel.timeZoneChanges` is the travel signal, tested. What remains: persist the events, then the card. ⚠️ Still true that **the app captures no HealthKit metadata**, so a calendar event's own time zone is the only handle on where a reading was taken |
| 16 ✅ | **Work impact** | **Shipped.** ⚠️ Unverified with real data — `CalendarModel.committedHours` and `busiestDay` are the input, tested. Needs the events persisted, then the card |
| 17 ◐ | **Cycle tracking — a whole fifth tab** | ✅ The tab exists and logs. Four decisions answered plus Q25. ⚠️ **Zero rows is still true of the reader's export and says nothing about hers** |
| 18 | **Stress Tracking "like Oura"** | Possibly already Sustained Load — see Q24 |

### B3 — Proposed by the competitive research, not built

| # | Card | Note |
|---|---|---|
| 19 | **"What I could see last night"** | Which instruments actually reported, and which cards are therefore abstaining. **The strongest single idea in the whole scan.** Today a green radar is ambiguous between *nothing stirring* and *the ring was on the charger*. Oura's `non_wear_time` (81 of your last 90 days) sits unread as the denominator |
| 20 | **"When you settled"** | Last night's overnight HR and HRV *curve* against your typical curve. Every product reports a summary; none draws the within-night shape. Probably a Sleep section |
| 21 | **"What the drug is doing"** | Every metric folded onto days-since-dose rather than the calendar, with the dose count on the figure. 14 tirzepatide doses, 9 side-effect records, 1,614 Withings weights |
| 22 | **"Sound you took on"** | Cumulative headphone dose against the WHO/NIOSH budget. 13,768 rows over 467 days. Must state the hours it could not see |
| 23 | **"Which instrument to believe"** | Where Watch, ring and scale disagree — show both, say which the app used and why. **You asked for this again tonight.** #27 is now fixed so it will not draw a gap it creates itself |
| 24 | **"Your bloods"** | Manual lipid + HbA1c entry. See Q7 |
| 25 | **"What is actually in your stack"** | Supplements summed ingredient by ingredient against upper limits. See Q8 |

### B4 — Built as a section rather than a card

| # | Thing | Where |
|---|---|---|
| 26 | **"How old does each thing think you are"** | Heart Attack & Stroke Risk card, bottom. Every age estimate, attributed, each with its own **derived** error |

### B5 — Previously refused. ⚠️ **ELEVEN OF TWELVE REVERSED BY THE READER, 2026-08-06.**

**The reader's ruling, verbatim:** *"There are other things that you've said no to
for stupid reasons like compliance or privacy — just do them."* And on #29
specifically: *"These sorts of things are the ENTIRE POINT OF THE APP."*

**Read this before re-refusing anything.** The original reasons are kept in the
right-hand column on purpose — not one of them was factually wrong, and each
still governs *how* the thing is worded. What they were wrong about was the
*conclusion*: they treated "a regulator would want a trial first" and "the data
is thin" as reasons not to compute, in an app whose stated purpose is to derive
insights nobody else will from data people already have. **Thin data is a reason
to print the error bar, not a reason to show nothing.** A permanent null is not
the safe option; it is the useless one.

**The one rule that survives all eleven reversals:** modelled is never dressed as
measured (`MetricSource.calculated`, its own family, weight 0, no reference
range), and every one of these states its own uncertainty. That is what makes
shipping them honest rather than reckless.

| # | Item | Original reason (kept — it still shapes the wording) | ✅ Ruling |
|---|---|---|---|
| 27 ✅ | **Mental health card** — shipped `867129e` | Nine adversarial attacks, all do-not-ship. MindfulSession 0 rows, StateOfMind 0, MoodChanges 0; the whole symptom log is one row. Every design produced a permanent null, and *"you seem fine"* arriving by arithmetic to someone having a bad month is the worst available failure | **BUILD IT.** *"I want a mental health card. Figure it out, creative licence + data science."* ⚠️ **The one attack that still stands is the failure mode, not the feature**: the card must never reassure. It reports what the body did, asks what the reader felt, and the arithmetic runs the reader's own answers against their own physiology |
| 28 ✅ | **Cuffless blood pressure** — shipped `0ea9411` | Whoop took an FDA warning letter; cuffless PPG has no finalised validation protocol. 51 real cuff readings are better | **BUILD IT.** Reader: *"Did we not already build the experimental BP estimate????"* — **yes, `BloodPressureEstimator` already does exactly this** (personal calibration, reports its own ±). The refusal was about *a second, cuff-free card*, and reads as a flat no. **What "do it" means here: stop hiding it behind the cuff, and give a daily estimate with its error** |
| 29 ✅ | **Own-brand biological age** — shipped `972e2d7` | You would get a worse black box with a smaller *n*. Relaying Oura's with its error attached is strictly more honest — that is #26 | **BUILD IT.** *"THESE SORTS OF THINGS ARE THE ENTIRE POINT OF THE APP. WHY WOULD YOU SAY NO."* Correct, and the refusal misread the brief. The answer to "a black box" is **not to build a black box**: every term visible, every weight visible, every one attributable |
| 30 | **Sleep-apnoea card** | Asserting or screening for apnoea is FDA-clearance territory. Trending the index inside Sleep is fine; a card whose *name* implies a condition is not | **BUILD IT** |
| 31 ◐ | **Cycle / fertility** — slice 1 shipped `a8be5ae` | Zero rows, contraceptive claims need clearance, unstated assumption about the reader | **BUILD IT — a whole new tab.** *"Basically do everything Flo does."* Assumption now stated (Q18: the reader's wife). Zero rows remains the real constraint |
| 32 | **Meal-to-outcome / TDEE / intake-driven anything** | `dietaryEnergy`: 30 days ever, **0 in the last 90**. The gate is ~80% of logged days; the reader is at 0% | ❌ **UPHELD — the only one.** Reader: *"I don't care, don't do it."* The single refusal both sides agree on |
| 33 | **Total sound exposure** | Environmental audio exists on 14 of the last 90 days — summing it with headphones would invent the quiet hours | **BUILD IT.** The honest form: headphone dose is the number, environmental is charted beside it with its coverage stated, and the two are never summed into one figure |
| 34 | **Physical-effort intensity** | 81,252 rows looks dense and is a trap: 13 of the last 90 days. A z-score over a series that exists one day in seven is not a z-score | **BUILD IT — as a Fitness section**, which is what the original note already recommended. ⚠️ **And the reader added a requirement the refusal never considered: the effort score feeds the overall Fitness score.** That is new work, not a relocation |
| 35 | **Steps / distance / flights** | Real, but Fitness sections rather than a card | **BUILD IT — as Fitness sections.** Reader agrees with the placement |
| 36 ✅ | **Radar accuracy scorecard** — shipped `44fb94e` | An honest sensitivity figure is 3–5 years away at one symptom tag. The false-alarm rate is printable today and belongs on the radar itself | **BUILD IT** |
| 37 | **Daylight/UV, spirometry, mindfulness, mood, oral health, falls** | All **zero rows**. Data-collection problems wearing a build's clothing | **BUILD THEM.** ⚠️ **The zero-row finding is unchanged and is the whole difficulty**: what gets built is the *capture* — a way to put the data in — because a reader cannot be shown a chart of nothing. Anything that only reads HealthKit here will render empty forever |
| 38 ✅ | **"Why is my score low"** — shipped `964c03e` as a section of the deep dive, not a card | Highest-value idea in the scan, and it must not be a card — an explanation one tap from the number is one nobody reads | ✅ **Reader agrees it is not a card, and placed it:** *"I want this to be part of the deep dive under the insight web."* More specific than §C's "under every score" — see S2 |

---

## B6 — The calendar brief (reader, 2026-08-06)

**A whole feature in one message, and it is bigger than the integration it
extends.** Recorded in full because it is the specification:

> *"When we import the calendar data, I want it to use AI to read the meetings
> and their content, and actually rank each calendar item on: was this work or
> personal? Was this actually a meeting, or just something like a reminder? Did
> it have a location (meaning I had to be somewhere), or did it include a remote
> meeting link? How long was the meeting? Was it a marathon workshop? Was it
> travel? … The sentiment of the meeting — is it a chill catchup or a formal
> meeting with a client?*
>
> *And to see this, I want a section in both cards that shows the list of items
> from your calendar, and the relevant details for each item, with an
> opportunity to correct them or confirm, which the model can learn from … These
> will then go into the overall score of the card.*
>
> *And uniquely, this will become a new data source, like Work Events, Personal
> Events, Travel Events."*

| # | Piece | State |
|---|---|---|
| C1 ✅ | **The six axes as a typed model** — `CalendarEventClassification`, with `Decider` per axis (fact / rules / model / reader) | Shipped |
| C2 ✅ | **The deterministic classifier** — `CalendarEventClassifier`, 23 tests. Answers duration, presence, travel, reminder-vs-meeting exactly; leaves work-vs-personal on an ambiguous title, and sentiment, for the model | Shipped |
| C3 ✅ | **`loadHours`** — an hour of formal client meeting in a room is not an hour of blocked focus time, and a reminder costs nothing. This is what a card's score reads | Shipped |
| C4 ✅ | **The learning loop's data shape** — `CalendarEventJudgement` keeps the guess and the reader's correction **apart**, so accuracy is measurable and re-classifying cannot overwrite the reader. `CalendarClassifierAccuracy` refuses a figure below 10 reviews | Shipped |
| C5 ✅ | **The buckets** — `CalendarEventBucket`: Work / Personal / Travel / Other, derived not stored, travel outranking the calendar it was booked in | Shipped |
| C6 ✅ | **The on-device model call.** `FoundationModelSummarizer` shows the pattern (`SystemLanguageModel.availability`, `LanguageModelSession`, graceful fallback). It may only move **context** and **formality** — `CalendarEventClassifier.refined` enforces that and is tested. ⚠️ Prompt must never leave the device | Shipped |
| C7 ✅ | **Persisting events and judgements.** Nothing survives a launch today. A `@Model` per event and per judgement, registered in `DataStore`'s schema (an unregistered `@Model` silently never persists) | Shipped |
| C8 ✅ | **The review section, in both cards** — the list with its details and confirm/correct controls | Shipped |
| C9 ✅ | **The buckets as `DataDomain` cases** — Work Events, Personal Events, Travel Events in the Data tab | Shipped |
| C10 ✅ | **Travel drain (#15) and work impact (#16) themselves** | Shipped |

✅ **All ten rows shipped 2026-08-06.** What remains is not in this table:
**nothing has been seen with real calendar data in it.** Every card and section
was verified in its *empty* state on the simulator, which is the state that
matters most (two cards shipped invisible on 2026-08-03) — but the populated
state, the classifier's accuracy on real titles, and whether the on-device model
is even available on the reader's phone are all unverified. ⚠️ **The reader's
own export has no calendar in it at all**, so this needs the phone.

## B7 — Calendar identity & holidays (reader, 2026-08-06, second brief)

**The reader's own words, recorded in full because they are the specification:**

> *"on the work and travel events, i need to be able to handle cases such as
> someone just putting an 'OOO' or 'out of office' block in my calendar,
> sometimes its mine, sometimes its not. Also this just made me realised.. I
> should be able to see holidays (e.g. my calendar blocks that are holidays).
> It should also be email aware, and user aware.. maybe I can input my name to
> give context to the events (e.g. did i organise the meeting, or did i just
> attend) and if it is something like a 'John smith on holiday - OOO' It can
> see if that is me, or someone else. I could also be asked input my emails,
> as input data, like my work email … and personal emails …, which will again
> give even more context to those meetings and travel. I should also be able
> to input holidays that are planned manually.. e.g. in the work impact, the
> travel impact, the stress, the mental health.. knowing you have, or have not
> been on a holiday is a very good data point (we should of course make sure
> it has a data tab, where I can track holidays). And one recommendation could
> be, if i'm stressed, my health is bad.. maybe I should be recommended to
> take some leave, take a long weekend.. and it could even look at my calendar
> and predict when is a good time since it knows my calendar!!"*

| # | Piece | State |
|---|---|---|
| H1 | **Identity inputs** — the reader's name, work email(s), personal email(s), as `InputKind`s (⚠️ load `add-data-or-input`: four surfaces, three checks). What they buy: organiser-vs-attendee on every event, and whose OOO a block is | ⬜ Not started |
| H2 | **OOO / out-of-office handling** — an "OOO" block is *someone's absence*, not a meeting. Whose it is decides everything: **mine** → a holiday/leave signal; **someone else's** → near-zero load, possibly *reduced* load (fewer meetings that week). Needs H1 to answer "mine?" — without identity, an OOO block must classify as ambiguous, never as work | ⬜ Not started |
| H3 | **Holiday detection from the calendar** — all-day/multi-day blocks reading as leave ("annual leave", "holiday", "vacation", "PTO", "OOO" when mine). A new classification outcome, not a new bucket bolted on: it feeds H5's ledger | ⬜ Not started |
| H4 | **Manual holiday input** — planned leave entered by hand, past and future. Its own `InputKind` + a **Holidays `DataDomain`** (reader: *"make sure it has a data tab, where I can track holidays"*) | ⬜ Not started |
| H5 | **One holiday ledger, two sources** — detected (H3) and entered (H4) merge into one dated record of leave, deduplicated, correctable. This is the data point the cards read | ⬜ Not started |
| H6 | **Cards read the ledger** — work impact, travel drain, stress load, mental health each get "you have / have not had leave recently" as an input. ⚠️ Each card that scores it needs its `modelVersion` bumped, per the fitness-v2 precedent | ⬜ Not started |
| H7 | **The leave recommendation** — "stressed + degraded health + no leave in N months → suggest a long weekend", and **predict a good window from the calendar** (quiet weeks, no marathon days, adjacent to weekends/public holidays). Goes through `Suggestions`/`SuggestionEngine`, ranked below grounding gaps like everything else | ⬜ Not started |

**Sequencing note:** H1 unblocks H2; H3+H4 unblock H5; H5 unblocks H6; H7
reads H5 and H6's inputs. H1–H4 are one session's work; H6 touches four scoring
models and their versions; H7 is small once H5 exists. ⚠️ **Identity data
(name, emails) is personal data in a public repo's docs — record the *shape*
(`work email`, `personal email`), never the reader's actual addresses, per
`docs/privacy-and-ip.md`.**

---

## C. Sections requested

| # | Section | Where | Note |
|---|---|---|---|
| S1 ✅ | **A bespoke section on EVERY card** — shipped `adca807`. `bespokeSection` is exhaustive now, so `default: EmptyView()` is gone and a new card cannot ship without a stated decision. Readiness is the one deliberate `EmptyView`, because its picture (the seventeen-vital strip) is drawn universally | All | ⚠️ **Five have none today: gait, sustainedLoad, nutrition, metabolism, readiness.** `InsightDetailView` has `default: EmptyView()` with a comment arguing *against* exhaustiveness — **your instruction reverses that.** Make the switch exhaustive so a new card cannot ship without one, and **update `docs/card-sections.md` and the `add-insight` skill** so it is enforced, not remembered. For gait it is the worst case: the speed = step length × cadence decomposition is the card's reason to exist and reaches you as one driver line |
| S2 ✅ | **Score decomposition** — shipped `964c03e`. — each signal, its value, its baseline, its deviation, its weight, and the counterfactual | ⚠️ **In the deep dive under the insight web** — the reader placed it there explicitly on 2026-08-06, in preference to "under every score" | Item #38 above. Oura's #1 unfixable complaint |
| S3 | **"Nights to flag" detail sheet** — slides up, slides back down | Symptom radar | 1.0 SD → 14 nights · 1.5 → 6 · 2.0 → 4 · 3.0 → 3 |
| S4 | **Flagged days over time** — when sickness was flagged and how it builds | Symptom radar | Your idea tonight |
| S5 | **"What changed while you slept"** | Sleep | Your request |
| S6 | **Recovery tracker** | Readiness | Your request |
| S7 | **SubstanceEpisodes explained** — the occasion is the unit of evidence; three drinks in one evening is one exposure, a fortnight later is another; substances never merge | Substance Impact | The logic exists and is tested; **nothing shows it to you** |
| S8 | **Device disagreement** — pick a signal, see the difference and why | Card or section — see #23 | |
| S9 | **Breathing disturbance, charted not scored** | Sleep | 107 days, only 10% redundant. Oura publishes no validated curve, so it must not be scored |
| S10 | **Overnight HRV** | Sleep | Sleep is the only card grading a night that reads nothing from the heartbeat stream recorded during it |
| S11 | **Sleep Regularity Index** replacing two crude estimators | Sleep | Beat duration head-to-head for mortality in UK Biobank (n=88,975). **Net weight change zero** |
| S12 | **Intensity distribution** | Fitness | Where PhysicalEffort legitimately belongs (#34) |
| S13 | **Trend the breathing-disturbance index** | Sleep | The describable half of #30 |

---

## D. Integrations

| # | Integration | State |
|---|---|---|
| I1 ◐ | **Calendar — sync one or many Apple calendars, and unsync, under Integrations like the others** | ✅ **Shipped `pending`**: `CalendarIntegration` in the registry, permission prompt, connect/disconnect, per-calendar selection persisted, and `CalendarEvent`/`CalendarModel` in InsightKit with committed hours, time-zone changes and busiest day — all testable on Linux. ⚠️ **Events are fetched but not yet STORED**: nothing persists them between launches and no card reads them. That is the remaining half, and it is what #15 and #16 need |
| I2 | Hume Band direct API | Flows in via Apple Health only |
| I3 | Ultrahuman | Nothing |
| I4 | Garmin | Nothing |
| I5 | Fitbit | Nothing |
| I6 | Arbitrary lab analytes via Foundation Models | Only known analytes parse today |
| I7 | ECG photo/PDF import with metadata | Nothing |
| I8 | Barcode scanner with on-device lookup (Open Food Facts / USDA) | Nothing. ⚠️ Photo-to-number is out: real-world portion estimation runs as low as 39% accurate. The flow must be photo → candidates → you confirm → portion |
| I9 | Camera + LiDAR guided body scan | Mesh renders; **no capture exists** |

---

## E. Defects and quality gaps

| # | Item | Note |
|---|---|---|
| D1 | **Five cards have no bespoke section** | S1 |
| D2 | **`MicronutrientTargets` is dead code with a user-visible cost** | Q4 |
| D3 | **Feedback gated on `primaryValue != nil`** | Q5 |
| D4 | **Six dead modules** | `MicronutrientTargets`, `PostureAssessment`, `MedicationScanner`, `BodyLimb`, `RingProvenance`, `BodyMeshConfiguration` |
| D5 | **The app target has ZERO tests** | 23,813 lines, ~41% of shipped Swift — every render site, every visibility gate, every hot path |
| D6 | **No accessibility work** | 23 modifiers total; charts, radar web and body mesh carry no VoiceOver description; no Dynamic Type |
| D7 | **English only** | All copy hard-coded in Swift literals; imperial units unchecked |
| D8 | **No widgets, Live Activities or watch target** | For a product whose central object is a daily number |
| D9 | **Cold-launch time against the real 320,913-row record is unmeasured** | Launch screen may be covering 1 second or 15 |
| D10 | **No unhappy path walked** | What you see when an Oura/Withings token expires mid-sync, or HealthKit is partially denied, is unknown |
| D11 | **The nine Data-domain detail pages have never been opened and checked** | Against the four promises `docs/data-conventions.md` makes |
| D12 | **Onboarding never checked** | Including whether the two now-mandatory grounding asks can be skipped |
| D13 | **The document/OCR path is unaudited** | The one input that turns a photograph into a health number |
| D14 | **Roadmap rows 33–38 are stale** | The symptom-radar rows all shipped |
| D15 | **`docs/card-sections.md` partially corrected 2026-08-06** | Two false "closed" claims reopened; the per-section tables still need a sweep |
| D20 | ⚠️ **A second vendor age is already arriving and nothing reads it: Withings "metabolic age"** (`withings.measure.227`, 153 rows over 110 distinct days, 2024-12-25 → 2026-07-29 — a *longer* history than Oura's vascular age). Raw-only: no `MetricType`, no promotion rule. ⚠️ **And the 227 → "Metabolic age" mapping is an inference** — `RawFieldPresentation` named it by matching the reader's own value range against plausible meanings, because Withings publishes no publictable. Printing "Withings says you are N" on that basis is a stronger claim than this app has ever made from an inference. **Decide before coding**: relay it labelled as an inference, or leave it raw | Found by the age scout, 2026-08-06 |
| D21 | **Fitness age and heart age still collapse multiple instruments.** Both read one source through `VitalReader.reading`; the reader's export has 4 VO₂max source ids and 4 systolic ones. The vascular row was fixed on 2026-08-06 but "all the sources" is only two-thirds true | Same scout |
| D22 | **No age series but heart and fitness.** `AgePoint` has exactly two optional age fields, so neither vascular age nor the app's own biological age can be drawn over time — the time chart and the comparison section disagree about how many ages exist | Same scout |
| D19 | ⚠️ **A hard-coded count inside reader-facing copy** — a section said "All four" on a card running on three signals, and mental health named all four behaviours including one it had no data for. The ledger's "hard-coded count going stale" row, except in a sentence, where it is worse: the sentence is a claim about what was looked at. Fixed in `adca807` with a test; **no lint exists for the next one** |
| D17 | ⚠️ **`walkingSpeed` reads 0 days in the last 90 in the simulator**, contradicting the 1,093-day figure measured against the raw export catalogue. The Gait card still scores 100, on its other two channels, with the speed channel silently absent | Next session's cheapest real find. Either `load-real-export.sh` does not promote the gait triad, or the promotion path drops it |
| D18 | **Five cards still have no bespoke section** — gait, sustainedLoad, nutrition, metabolism, readiness. Biological age shipped with one; mental health did not | S1 |
| D16 | **Score history is empty for five cards** | readiness, sleep, energy, substanceImpact, fitness — the 90-day replay landed after the last export |

---

## F. Device-gated — need the phone, not the simulator

Resting Heart Rate page cross-device defect · Body Composition after the hatch change · split-night proof from the next export · the ingestion pipeline · the cards on the phone · Phase 1 and Phase 2 sections · Heart Health on a young profile · Screen Time bar measurement · the share-sheet action extension (parked on signing)

---

## G. Standing rules you have set

**These are not tasks. They constrain every future task.**

0. ⚠️ **"Ground breaking and unique — do stuff that others will not do."**
   (2026-08-06) *"I do not care about compliance at this point, it's my personal
   project."* **Compliance, clearance and privacy-of-a-public-repo are no longer
   reasons to refuse a feature** — they are reasons to word it carefully and to
   print its error. Thin data means show the error bar, not show nothing. **A
   permanent null is not the safe option; it is the useless one.** If this app
   ever gets a second user, §B5's original reasons all come back.
1. **"Honest version, always."** (2026-08-05) — unchanged by rule 0, and the
   thing that keeps rule 0 from being recklessness: modelled is never dressed as
   measured, and every estimate states its own uncertainty.
2. **Every card shows, even with no data** — and an empty card asks for what it needs.
3. **Every chart carries the substance shading.**
4. **Everything a card charts carries a weight** — or says why it cannot.
5. **Every card gets a bespoke section** (2026-08-06) — creative authority granted.
6. **A fill's colour ramp follows the quantity's own axis** — the radial rule.
7. **Push to `main`. No pull requests.**
8. **Before writing "already arriving" about a data source, count its rows in the last 90 days.** (2026-08-05, learnt the hard way)
