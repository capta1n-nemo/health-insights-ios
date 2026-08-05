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

## A. Every open question

**These are the only things blocking work. Nothing else needs an answer.**

### A1 — Decisions on things already built

| # | Question | What changes |
|---|---|---|
| Q1 | **Substance card at 4 episodes.** Ship the honest version — per-episode deltas, the alternative explanation on each row, no score, "nothing has happened the same way often enough to tell it from an ordinary run" — or wait for more exposures? | Independent review refuted the confirmation design on your own record: heart rate's apparent effect falls from 0.91 to **0.03** once same-day steps are in the model; the permutation null is ~2× anti-conservative; and the finding set flips on the day boundary (3 confirmations at UTC+8, 0 at UTC−5) |
| Q2 | **Blood Pressure card shows two ± and two cuff ages on one screen** ("±14, fitted to 23 readings" beside "the ±13 it is judged on"; "over a day old" beside "2 days ago"). Show one ± and say which, or say the fit has moved since that reading was graded? | Both are defensible alone; together they read as a contradiction. I'd pick the first |
| Q3 | **Fitness-age anchor.** Does your VO₂max of 30 reading as a **68-year-old's fitness** seem right? | The norm table's lowest anchor is VO₂ 32 at age 65; below ~36 it is extrapolation. It is shared with `HeartHealthScore.vo2Score`, so a floor moves **two cards** and also moves the fitness age's stated ±9 |
| Q4 | **Micronutrients.** Score the eleven now, or leave until the supplement work? | ⚠️ **The Nutrition card currently makes sex and date-of-birth MANDATORY**, with the stated reason "without it none of them can be scored" — and then scores none of them. `MicronutrientTargets` is built, tested, and called by nothing. **That rationale is untrue today.** Either wire it or drop the mandatory ask |
| Q5 | **Feedback control** is gated on `primaryValue != nil`, so Nutrition and Metabolism in their empty states **cannot be rated** — the cards most likely to be wrong are the ones you cannot tell are wrong. Ungate? | One line |

### A2 — Decisions on things not yet started

| # | Question | What changes |
|---|---|---|
| Q6 | **Location permission / event-confirmation feed (#32).** You approved the permission in principle. Build the feed first then the prompt, or both together? | I declined to build a privacy prompt for a feature that didn't exist. It still doesn't |
| Q7 | **Bloods.** Manual entry, or PDF/OCR import? | The risk card computes SCORE2/ASCVD **assuming** your cholesterol right now, and you cannot see what it assumed. Neither total nor HDL exists in the 45 canonical metrics or the 158 raw identifiers |
| Q8 | **Supplements.** Worth a one-time capture form against published upper limits? | NIH's label database has 200,000+ products behind a free API. Every food tracker treats a supplement as a food with a calorie count, which is backwards |
| Q9 | **Mental health.** Build the computes-nothing Mind section in the Data tab? | Full research says do not build a card — see §E. The section holds what you write, shows it back, computes nothing |
| Q10 | **Export gaps (#40).** Build them? | Missing: connector connection state, suggestion dismissals, the feedback ledger, prediction outcomes. ⚠️ **"Connector configuration" includes OAuth tokens and this repo is public** — status and last-sync are safe; credentials must be *structurally impossible* to serialise, not merely omitted today |
| Q11 | **Notifications.** There are **none, anywhere** — zero `UserNotifications` imports. Intended? | A symptom radar whose whole thesis is noticing illness early can only speak when you open the app |
| Q12 | **Write-back to Apple Health.** Nothing is written back — `requestAuthorization(toShare: [])`. Intended? | Every cuff reading, weight, symptom and substance you type stays inside this app, invisible to Health and every other app |
| Q13 | **Delete-everything path.** None exists. Want one? | Settings has "Rebuild" and "Disconnect" only. Also unresolved: what happens to Keychain-stored provider credentials on uninstall |
| Q14 | **Signing lifetime.** Does the app stop launching when the free-team provisioning profile expires? | Nobody has checked. If yes, a deploy is needed on a *schedule*, not on a change |
| Q15 | **Body scanner priority.** ARKit capture is the largest single unbuilt piece. Where does it sit? | The mesh renders; **no capture exists anywhere in the repo** |

### A3 — Cycle tracking: four decisions gate all ten items

⚠️ **Row 48 says explicitly: settle the privacy posture first.** That is why nothing started.

| # | Question |
|---|---|
| Q16 | **Does the tab draw a fertile window at all?** (#45) — anything contraceptive needs FDA clearance; Natural Cycles is the only cleared app of its kind, and this app is explicitly not a medical device |
| Q17 | **Surface the tirzepatide / oral-contraceptive labelling?** (#46) |
| Q18 | **Who is the tab for?** (#47) — it rests on an assumption about the reader nobody has stated |
| Q19 | **The privacy posture** (#48) — this repo is public and holds one person's health data |

⚠️ **And a harder problem than the four:** `MenstrualFlow` has **zero rows**. `SexualActivity` has **zero rows**. Measured against your export. Phase 1 would be an empty log awaiting manual entry, and Phase 2 (prediction) needs cycles to predict from. The one real asset in the domain is `basalBodyTemperature` — 136 rows, 80 of the last 90, written by your Shortcut and read by nothing — and its best use is **an independent temperature channel for the symptom radar**, because it survives a night the ring was on charge, which is exactly when the radar goes blind.

### A4 — Crowd-sourced norms: two decisions

| # | Question |
|---|---|
| Q20 | **Opt-in per signal** (#55) — nothing leaves the phone today and that must stay true until you choose otherwise |
| Q21 | **Does a user contribute automatically once they consume, or is contributing a separate choice?** (#59) |

### A5 — Small ones

| # | Question |
|---|---|
| Q22 | **Does MyFitnessPal already write into Apple Health for you?** (#49) — check before building any food capture |
| Q23 | **Travel drain**: is the calendar integration enough, or do you also want HealthKit timezone metadata captured? (The app captures **no** metadata today) |
| Q24 | **"Create Stress Tracking card like Oura"** — Sustained Load shipped. Do you mean something different: Oura's own `daily_stress` (142 days, 90 of the last 90) as a labelled second opinion? |

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

### B2 — You asked for them; they do not exist

| # | Card | Blocker |
|---|---|---|
| 15 | **Travel drain** | No event source. **The app captures no HealthKit metadata at all**, so there is no timezone on any sample. The original plan assumed this was free; it is not |
| 16 | **Work impact** | Needs a calendar. **Your new instruction to build a calendar integration unblocks this and #15** |
| 17 | **Cycle tracking — a whole fifth tab, 10 items** | Four decisions (Q16–Q19) plus zero rows. See §A3 |
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

### B5 — Deliberately refused, with reasons

**These are not backlog. They are decisions. Re-proposing one needs a new argument.**

| # | Refused | Why |
|---|---|---|
| 27 | **Mental health card** | Nine adversarial attacks, all do-not-ship on all three designs. MindfulSession 0 rows, StateOfMind 0, MoodChanges 0; your whole symptom log is one row. Every design produced a permanent null, and "you seem fine" arriving by arithmetic to someone having a bad month is the worst available failure. **Recommended instead: a Mind section that computes nothing** (Q9) |
| 28 | **Cuffless blood pressure** | Whoop took an FDA warning letter; clinicians say cuffless PPG has no finalised validation protocol. You have 51 real cuff readings, which is better |
| 29 | **Own-brand biological age** | You would get a worse black box with a smaller *n*. Relaying Oura's *with its error attached* is strictly more honest — that is #26 |
| 30 | **Sleep-apnoea / breathing-disturbance card** | Asserting or screening for apnoea is FDA-clearance territory. **Trending the index inside Sleep and saying what it is derived from is fine**; a card whose name implies a condition is not |
| 31 | **Cycle/fertility as a card** | Zero rows, contraceptive claims need clearance, and it rests on an unstated assumption. The tab (#17) is a separate question |
| 32 | **Meal-to-outcome / TDEE / intake-driven anything** | `dietaryEnergy`: 30 days ever, **0 in the last 90**. The gate is ~80% of logged days; you are at 0% |
| 33 | **Total sound-exposure card** | Environmental audio exists on 14 of your last 90 days — summing it with headphones would invent the quiet hours |
| 34 | **Physical-effort intensity card** | 81,252 rows looks dense and is a trap: only 13 of the last 90 days. A z-score over a series that exists one day in seven is not a z-score. Belongs as a Fitness section |
| 35 | **Steps / distance / flights card** | Real, but Fitness sections rather than a card |
| 36 | **Symptom-radar accuracy scorecard as a card** | An honest sensitivity figure is 3–5 years away at one symptom tag. **The false-alarm rate is printable today** and belongs on the radar itself |
| 37 | **Daylight/UV, spirometry, mindfulness, mood, oral-health, falls cards** | All **zero rows**. Data-collection problems wearing a build's clothing |
| 38 | **"Why is my score low" as a card** | The single highest-value idea in the scan, and it **must not be a card** — an explanation one tap from the number is one nobody reads. It belongs as a section under *every* score. See §C |

---

## C. Sections requested

| # | Section | Where | Note |
|---|---|---|---|
| S1 | **A bespoke section on EVERY card** — creative authority granted | All | ⚠️ **Five have none today: gait, sustainedLoad, nutrition, metabolism, readiness.** `InsightDetailView` has `default: EmptyView()` with a comment arguing *against* exhaustiveness — **your instruction reverses that.** Make the switch exhaustive so a new card cannot ship without one, and **update `docs/card-sections.md` and the `add-insight` skill** so it is enforced, not remembered. For gait it is the worst case: the speed = step length × cadence decomposition is the card's reason to exist and reaches you as one driver line |
| S2 | **Score decomposition** — each signal, its value, its baseline, its deviation, its weight, and the counterfactual | Under every score, Readiness first | Item #38 above. Oura's #1 unfixable complaint |
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
| I1 | **Calendar — sync one or many Apple calendars, and unsync, under Integrations like the others** | ⚠️ **NEW, your instruction. Nothing exists — zero `EventKit` imports.** Unblocks #15 and #16 |
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
| D16 | **Score history is empty for five cards** | readiness, sleep, energy, substanceImpact, fitness — the 90-day replay landed after the last export |

---

## F. Device-gated — need the phone, not the simulator

Resting Heart Rate page cross-device defect · Body Composition after the hatch change · split-night proof from the next export · the ingestion pipeline · the cards on the phone · Phase 1 and Phase 2 sections · Heart Health on a young profile · Screen Time bar measurement · the share-sheet action extension (parked on signing)

---

## G. Standing rules you have set

**These are not tasks. They constrain every future task.**

1. **"Honest version, always."** (2026-08-05)
2. **Every card shows, even with no data** — and an empty card asks for what it needs.
3. **Every chart carries the substance shading.**
4. **Everything a card charts carries a weight** — or says why it cannot.
5. **Every card gets a bespoke section** (2026-08-06) — creative authority granted.
6. **A fill's colour ramp follows the quantity's own axis** — the radial rule.
7. **Push to `main`. No pull requests.**
8. **Before writing "already arriving" about a data source, count its rows in the last 90 days.** (2026-08-05, learnt the hard way)
