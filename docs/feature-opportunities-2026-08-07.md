# Feature opportunities — what people wish health apps did (2026-08-07)

_Research doc, no code. Commissioned by the reader: "Research other opportunities
for new high value features that people wish health apps had." Written against
`docs/backlog.md` (124 open rows checked), `docs/data-opportunities.md`,
`docs/planned-modules.md` and the code (`MetricType.swift`, insight usage greps),
so nothing below duplicates an existing row. Where a proposal touches an existing
row, the row ID is named._

**The three strongest opportunities, and why they fit this app specifically.**
First, a **precedent engine** — when something deviates, retrieve the reader's
own past episodes that looked like this and show what followed, with the n and
the spread. It is the honest answer to the single most common complaint about
this product category ("it tells me my score dropped, not what that has ever
meant"), it needs no advice, no population model and no new data — only the
320,913-row record the app already holds. Second, an **illness recovery arc** —
after the symptom radar flags an episode, chart each channel's return to
baseline against the reader's own previous episodes; published evidence (Radin
2021) says physiological recovery outlasts symptoms by days to weeks, every
vendor scores *today* and none scores *the arc*, and "day 5 of a course that has
previously taken 9–11 days" is a statement of record, not advice. Third,
**n-of-1 experiment scaffolding** — the academic self-experimentation frameworks
(Karkar 2016) that no consumer product ships, with the app's signature move
being the honesty step nobody else would print: *before* the experiment starts,
state what three weeks of the reader's own variance can and cannot detect. All
three convert "we never advise" from a limitation into the differentiator: they
answer "so what?" with the reader's own evidence instead of a platitude.

---

## 0. How this research was done, honestly

This session's web-search budget was exhausted before the research began
(200/200 calls used elsewhere in the session), and direct fetches of Reddit and
journal pages were blocked. So:

- **Complaint themes in §1 are characterised from the published abandonment /
  personal-informatics literature** (checkable citations in §7) **plus general
  knowledge of the r/ouraring / r/whoop / r/QuantifiedSelf discourse genres,
  labelled as judgement.** No fresh mine of threads or App Store reviews was
  performed, and no user is quoted.
- Every named study is one I am confident exists and is checkable by author,
  year and journal in §7. Nothing is quoted verbatim from any of them.
- Product-feature claims about Oura, Whoop, Bearable, Visible, Exist.io are from
  general knowledge current to early 2026 and are marked (judgement) where a
  vendor may have shipped something since.

A future session with search budget could harden §1 with a real review mine;
the ranked list in §6 does not depend on it.

---

## 1. What people actually complain wearable/health apps lack

The published record first, because it is checkable:

- **Roughly a third of activity-tracker owners stop using the device within six
  months** (Ledger & McCaffrey, Endeavour Partners 2014). The follow-up
  ethnographic work found abandonment is mostly not hardware failure but
  *meaning* failure — the data stopped saying anything the person could use
  (Clawson et al. 2015; Lazar et al. 2015; Epstein et al. 2015).
- **Even committed self-trackers fail at insight, not collection.** Choe et
  al. (2014) catalogued quantified-selfers' own named pitfalls: tracking too
  many things, failing to track the triggers/context alongside the outcomes,
  and lacking the rigour to conclude anything. Ten years later the mainstream
  products still collect on the left of that gap.
- **Sleep-staging trust is a real, evidenced grievance**: consumer devices'
  epoch-by-epoch stage agreement against polysomnography is moderate at best
  (de Zambotti et al. 2019 for Oura), while the apps present stages with
  unqualified confidence. This app's stated-error identity is the direct
  answer.

The recurring discourse genres, characterised as judgement (no fresh mine, no
invented quotes — see §0):

1. **"It tells me the score dropped, not what to do / what it means."** The
   dominant genre. Generic coping copy ("consider an early night") reads as
   filler; users ask for *their own* history: has this happened before, what
   followed, how long did it last.
2. **"The score contradicts how I feel"** — and there is no way to tell the
   app so, or the way exists and visibly changes nothing. (This app's feedback
   ledger + correction loops are ahead here; §B8 is the moat.)
3. **Subscription resentment** — Oura's move to subscription and Whoop's
   subscription-only hardware are perennial flashpoints. A no-subscription app
   that does more with the same ring data attacks this directly (it is the
   stated win condition of the cycle tab, Q18).
4. **Data ownership and export** — "my data is in their cloud and I can't get
   it out at full resolution."
5. **Accuracy contradictions between devices** with no adjudication — already
   this repo's B3-23 / S8, ruled 2026-08-07, so not proposed again.
6. **Illness features that stop at detection** — flags you're getting sick,
   silent on recovery (see §3.1).
7. **Life-blindness** — the products know the body but not the life: a
   readiness dip during a house move, a newborn, or bereavement is narrated as
   if it were a training problem. Only a calendar-holding app can fix this
   (§4).

---

## 2. The "so what" gap — non-advice forms of actionability

The app never advises. The research question was: what *other* forms of
actionability exist? Four, in increasing order of build cost — the first two
are the new opportunities, the last two the app already does:

1. **Precedent retrieval** — "the last 4 times this configuration appeared,
   here is what followed." Case-based reasoning over the reader's own record.
   No consumer product ships this as a first-class surface (judgement); Whoop's
   monthly journal-impact reports and Exist.io / Bearable correlation tables
   are the nearest relatives, and all three aggregate rather than retrieve —
   they answer "what correlates on average," never "what happened the times it
   looked like *this*." Ranked #1 in §6.
2. **Experiment scaffolding** — structured n-of-1 trials: pick one lever,
   alternate or washout properly, state up front what is detectable at the
   reader's own variance, report the answer with its uncertainty. The academic
   record is rich — Karkar et al. 2016 (framework), Karkar et al. 2017
   (TummyTrials, food triggers), Daskalova et al. 2016 (SleepCoacher, sleep
   recommendations as self-experiments) — and the consumer record is
   essentially empty (judgement). A plausible reason nobody ships it: an
   honest experiment can conclude the vendor's product changes nothing, which
   is a retention risk for them and a credibility win for an app whose brand
   is honesty. Ranked #3 in §6.
3. **Attribution** — "why is the number what it is." Shipped: score
   decomposition (B5-38, `964c03e`), weights on every card, "what goes into
   this."
4. **Acquisition prompts** — "what data would sharpen this." Shipped: the
   improvement section and `InsightKit`'s grounding-fact asks.

Precedent retrieval deserves one more design note, because it is the one most
at risk of quiet dishonesty: **the surface must show the n, the spread, and the
non-events.** "3 of the 5 previous times, nothing followed" is a legitimate and
common answer, and printing it is what separates precedent from superstition.
The illness-detection evidence doc already establishes the base-rate discipline
(`docs/illness-detection-evidence-2026-08-07.md`); this feature inherits it.

---

## 3. Evidence-backed features almost nobody ships

Each with its evidence, its fit, and its collision check against the backlog.

### 3.1 Illness recovery pacing — the arc after the flag

- **Evidence.** Radin et al. 2021 (JAMA Network Open, Fitbit COVID cohort)
  found resting heart rate and activity took days-to-weeks longer than
  symptoms to return to baseline, with a long tail of multi-week outliers.
  Sports-medicine guidance has formalised graded return after infection for
  decades — the "neck check" heuristic (Eichner 1993) and the graduated
  return-to-play protocols published for COVID (Elliott et al. 2020, BJSM).
- **The gap.** Every vendor scores *today's* recovery; none renders the
  *episode* — where you are on the return arc, against your own previous
  arcs. Visible (the long-covid/ME-CFS pacing app) is the only product built
  around pacing at all, and it serves chronic illness, not the acute
  "cold-to-normal" case everyone has.
- **Fit here.** The radar already detects episode onset with CUSUM memory and
  the ruled sick-days design (§B11) gives episodes start/end structure. The
  arc is the natural third act: per-channel days-to-baseline, this episode
  drawn over the reader's previous ones. Non-advice framing is native: "RHR
  still +6 bpm over baseline; your previous three episodes took 9–11 days" is
  record, not prescription. Extends `S6` (Recovery tracker — one line, scope
  unset) rather than duplicating it; `S6` should absorb this as its brief.

### 3.2 Alcohol decision support, the night OF

- **Evidence.** Alcohol suppresses cardiovascular autonomic regulation during
  the first hours of sleep dose-dependently — demonstrated at scale in a
  real-world Finnish cohort (Pietilä et al. 2018, JMIR). The effect is large,
  same-night, and highly per-person in magnitude — ideal n-of-1 material.
- **The gap.** Whoop surfaces alcohol impact in *monthly* journal
  retrospectives; Oura tags decorate charts after the fact. Nothing answers at
  the moment that matters: the evening itself. A night-of surface — open the
  substance log to record a drink and see *your own* last-n episodes' next
  mornings, by dose band — is historical mirroring, not advice, and no vendor
  ships it (judgement: plausibly because a drinking-moment surface reads as
  either judging or condoning; a mirror does neither).
- **Fit here.** The substance log and `SubstanceResponseAnalyzer` exist; the
  substance card ships the honest per-episode framing (Q1). **Data honesty:
  n=4 episodes as of 2026-08-06 (Q1)** — the surface must print the n and it
  will be thin for months; that is exactly the Q1 sentence pattern. HealthKit's
  `numberOfAlcoholicBeverages` type is currently unread (verified: no
  `MetricType` maps it) and would let other apps' drink logs feed the same
  mirror.

### 3.3 Medication timing patterns vs chronotype

- **Evidence — and the evidence story is the feature.** The Hygia trial
  (Hermida et al. 2020) claimed enormous benefits for evening antihypertensive
  dosing; the much cleaner TIME study (Mackenzie et al. 2022, Lancet) found no
  outcome difference morning vs evening. A field where the headline finding
  *flipped* is precisely where an honest app relays patterns and refuses to
  advise timing.
- **Fit, with a caveat found in this repo's own data.** The only medication in
  the panel today is tirzepatide — **weekly** doses (14 recorded, B3-21), so
  time-of-day analysis has nothing to chew on yet. This becomes real when the
  medication panel (`R24`, open) admits daily medications. Park behind R24;
  rank low accordingly.

### 3.4 Heat, cold, and the environment the body was in

- **Evidence.** Ambient night-time heat measurably degrades sleep at
  population scale (Obradovich et al. 2017, Science Advances). Particulate
  exposure acutely lowers HRV (Gold et al. 2000, Circulation). Regular sauna
  use associates with lower cardiovascular mortality in the Kuopio cohort
  (Laukkanen et al. 2015, JAMA Internal Medicine). Pollen seasons measurably
  disturb sleep and daytime symptoms in allergic cohorts (well-replicated;
  specific-study citation deliberately omitted rather than risked).
- **The gap.** Weather apps show the exposure and health apps show the
  response; nothing joins them per person. "Your sleep efficiency on nights
  over 24°C" or "your radar's respiratory channel against the pollen calendar"
  is a WorkImpactModel-shaped exposure×response question the app already knows
  how to ask — pointed at the sky instead of the calendar.
- **Fit here.** Gated on `Q6` (location feed — ruled "build the whole thing").
  Once location exists, Apple's WeatherKit (free at this scale with the
  developer account, includes AQI and pollen in supported regions) supplies
  exposure without a new BYO key. Skin/core temperature channels are already
  modelled (three `MetricType`s, verified). Altitude falls out of the same
  layer for free and feeds the Travel card (`B21` jetlag row stays separate).
  **This is the single highest-leverage extension of Q6** and nothing in the
  124 open rows claims it.

### 3.5 Perimenopause — the underserved half of the cycle work

- **Evidence.** Perimenopause staging is formally defined in large part by
  *cycle-length variability* (persistent ≥7-day differences — STRAW+10,
  Harlow et al. 2012), which a cycle log computes directly. Vasomotor symptoms
  affect a large majority of women in transition and are strongly nocturnal —
  which is where a ring's temperature and sleep channels already look.
- **The gap.** The femtech market clusters on fertility; perimenopause support
  is thin and what exists is subscription-gated (judgement; Oura has been
  moving toward cycle/perimenopause insights — exact shipped state unverified
  from this session).
- **Fit here.** The cycle tab, phase model, temperature channels and
  phase-aware baselines are **built** (§B5 #31); this is a mode, not a new
  tab: variability staging against STRAW+10 bands, nocturnal
  temperature-excursion counts, sleep-fragmentation trend — stated as record.
  Serves the wife's install (Q18/Q25 single-user ruling: *her* phone, her
  data). ⚠️ Her record's coverage is unmeasured (§A3 warning) — count before
  claiming anything arrives.

### 3.6 Parked: meal-response patterns and fueling windows

The evidence is real — postprandial responses vary enormously between people
on identical meals (Berry et al. 2020, Nature Medicine / PREDICT) — and
`bloodGlucose` is already a `MetricType`. But **both collide with the one
refusal the reader upheld** (B5-32: *"Meal-to-outcome / TDEE / intake-driven
anything"* — "I don't care, don't do it", 0 logged food days in the last 90).
Recorded here so the evidence isn't re-derived; **not proposed, and §6 excludes
them.** If the reader ever reverses B5-32, this section is the starting point.

### 3.7 Noted, not ranked

- **Snoring / partner disturbance** — real want, adjacent to the shipped
  breathing-disturbance work (S9/B18-1); needs all-night microphone capture
  with battery, storage and consent costs. Revisit if the apnoea section
  creates appetite.
- **Blood-oxygen altitude adjustment** — subsumed by §3.4's environment layer.
- **Keyboard/typing dynamics** — genuine literature (typing dynamics as an
  early motor-decline signal, Giancardo et al. 2016) but **iOS provides no
  global keystroke API**; infeasible without becoming a custom keyboard.
  Recorded so it is not re-researched.
- **Photo-library metadata as a life log** — technically feasible with
  permission (density, places, faces as life-rhythm signals) but squarely on
  the wrong side of §4's comfort line for inference without a correction
  surface; only worth revisiting as an explicit, reader-driven import.

---

## 4. Life-event awareness — what only a calendar-holding app can see

The app already classifies events on six axes, detects holidays, and learns
from corrections (§B6–B8, H-series). The next tier is *events that reshape the
whole record*:

| Life event | Detectable shape | Honesty grade |
|---|---|---|
| Deadline crunch | `committedHours` spike sustained over days — the Work card already holds the number; the *episode* (named span with an arc) is new | Honest — it is the reader's own calendar |
| New job / role change | Calendar-identity shift: new organiser domains, new meeting population (B7 adjacency) | Honest if surfaced as a question, creepy if asserted |
| Moving house | Location regime change once Q6 lands | Honest as a question |
| Newborn | Sleep fragmentation signature + overnight-wake pattern | Honest as a question; never inferred from calendar *content* |
| Bereavement | Calendar-shape anomaly (cancellations, funeral-shaped entries) | **Do not infer.** Ask nothing; accept only a reader-entered chapter |

**Where the comfort line is.** The privacy literature's usable rule is
contextual integrity (Nissenbaum 2004): an inference is acceptable when it
stays within the norms of the context the data came from, and violations are
what people call "creepy." The practical translation for this app, consistent
with its own correction-loop design language: **infer silently, surface as a
question, let the reader confirm or correct, and never let an unconfirmed
inference change what the app says.** Bereavement is the case that stays
manual forever — an app guessing at grief from calendar text is the canonical
creepy overreach, and the cost of being wrong is unbounded.

**The build this implies — "Life chapters."** A reader-confirmed `LifeEvent`
record (moved house, started job, had a baby, lost someone — plus free-form),
seeded by calendar/location hints for the benign rows only. Two payoffs:

1. **Baselines stop lying across regime changes.** Every baseline in the app
   currently assumes one continuous life. A confirmed chapter boundary is a
   principled place to segment or reweight the reference window — the same
   class of correction the phase-aware baselines make for the cycle (§A3),
   generalised. This is a statistical feature wearing a diary's clothing.
2. **Precedent retrieval (§2.1) gains its most powerful filter** — "similar
   episodes, *same chapter of life*."

Nothing in the backlog proposes it; closest rows are the calendar-identity
brief (B7) and D56's travel-aware sleep, both of which it composes with.

---

## 5. Data people have that nothing reads

Generalising the walkingSpeed find (`data-opportunities.md` #7). Checked
against `MetricType.swift` and insight-usage greps on 2026-08-07 — claims of
"unread" below are verified against this repo, not assumed:

**Already read here — do not re-propose.** AFib burden (vitals scan), heart
rate recovery (Heart Health + Fitness), walking steadiness/asymmetry/speed
(gait card), environmental + headphone sound dose, breathing-disturbance index
(`MetricType` exists; scoring is S9/S13's open work), skin/core temperature,
peripheral perfusion, screen time, modelled medication level. The mainstream
apps ignore most of these; this app is already ahead of its own §5.

**Held by HealthKit, unmodelled here, with an honest basis available:**

| Signal | Basis | Note |
|---|---|---|
| `stairAscentSpeed` / `stairDescentSpeed` | Functional-capacity literature; stair performance is a validated frailty/capacity marker | Natural extra spokes for the gait card; small build |
| `sixMinuteWalkTestDistance` | The 6MWT is a genuinely clinical measure with published reference equations | Apple estimates it passively; nobody consumer-facing surfaces it |
| Sleep-apnoea notification events (iOS 18) | Apple's own FDA-cleared detection | Corroborating witness for the BDI section — a second instrument, B3-23-style |
| `numberOfAlcoholicBeverages` | Direct | Feeds §3.2's mirror from other apps' logs |
| Irregular-rhythm / low-cardio-fitness notification events | Apple-cleared events | Belong in the vitals scan's evidence list, not as scores |
| Running dynamics (power, ground contact, vertical oscillation), cycling power/FTP | Training-load literature | Only worth it if the reader runs/cycles — count first; likely zero rows |
| `environmentalSoundReduction` (AirPods ANC) | Completes the sound-dose picture: measured attenuation | Small add to the shipped dose models |

**Explicitly not applicable or infeasible** (recorded so the next scan skips
them): wheelchair metrics (single-user app, Q25 ruling — not this user);
keyboard dynamics (no API, §3.7); photo metadata (comfort line, §3.7);
`bloodAlcoholContent` (no consumer source writes it in practice).

---

## 6. The top 10 for THIS app — ranked, with reasons

Ranking is judgement; the criteria are: evidence quality, whether the data is
already held (counted, not assumed), n-of-1 feasibility at this record's actual
coverage, distinctiveness (why competitors don't), and fit with the honesty
identity. Backlog collisions checked per row.

| # | Feature | Evidence rests on | Data needed — held? | n-of-1 feasibility | Why competitors don't |
|---|---|---|---|---|---|
| 1 | **Precedent engine** — "this has happened before; here is what followed, n and spread, including the times nothing followed" | Case-based reasoning; the abandonment literature's insight-gap finding (§1) | Full metric + score history. **Held**: 320,913-row record (D9); caveat: `scoreHistory` only since install, empty for five cards (D16) | High — it *is* n-of-1; degrades honestly to "no precedent yet" | Population products aggregate; retrieval needs full local history and the nerve to print "usually nothing followed" |
| 2 | **Illness recovery arc** — per-channel return-to-baseline after a radar episode, drawn over the reader's previous arcs | Radin 2021; Elliott 2020 (BJSM); Eichner 1993 | Radar episodes (built, CUSUM), RHR/HRV/temp/RR channels (held). Episode count on the real record unmeasured — count on the phone first | High once ≥2 episodes exist; first episode renders honestly as "no prior arc" | Business model scores *days*, not *episodes*; return-to-exercise smells like medical advice — mirroring your own past arcs doesn't |
| 3 | **N-of-1 experiment scaffolding** — one lever, proper washout, detectability stated before starting | Karkar 2016/2017; Daskalova 2016 | Whatever the lever touches — all held for non-dietary levers (bedtime, screen time, walking, caffeine timing via substance log). ⚠️ Dietary levers collide with B5-32 — excluded | The whole feature is n-of-1; the honest power statement is the differentiator | An honest experiment can conclude "no effect" — retention poison for advice-selling vendors, brand-perfect here |
| 4 | **Night-of substance mirror** (alcohol first) | Pietilä 2018; the app's own per-episode deltas (Q1 design) | Substance log **held but thin — n=4 episodes (Q1, 2026-08-06)**; `numberOfAlcoholicBeverages` unread (verified) | Grows with every episode; surface prints its n from day one | A drinking-moment surface reads as judging or condoning; a mirror of your own mornings is neither — and needs episode-level local history |
| 5 | **Environment layer** — heat, cold, AQI, pollen, altitude × the reader's own sleep/HRV/radar channels | Obradovich 2017; Gold 2000; Laukkanen 2015 | **Not held — gated on Q6 (location, ruled: build)** + WeatherKit; response channels all held | Exposure×response, the WorkImpactModel shape, per person | Weather apps hold exposure, health apps hold response; nobody joins them per person |
| 6 | **Social jetlag vs the real calendar** — midsleep on committed days vs free days, from actual events, not an assumed Mon–Fri | Roenneberg 2006/2012 | Sleep midpoint (held), workday identification (held — `CalendarEventRecord` persisted, verified) | Direct computation, no model | **No vendor has the calendar.** Unique-data play; feeds B18-8's ideal-timeframe section rather than duplicating it |
| 7 | **Life chapters** — confirmed life events as first-class records; baselines segment at chapter boundaries | Nissenbaum 2004 for the comfort line; the app's own phase-aware-baseline precedent (§A3) | Calendar (held), correction loop (built, B8); location hints once Q6 lands | The payoff *is* per-person statistical hygiene | No calendar, no correction loop, and the creepy-line risk without both |
| 8 | **Perimenopause mode** on the cycle tab | Harlow 2012 (STRAW+10); vasomotor/sleep literature | Cycle log + temperature channels **built**; the wife's record's coverage **unmeasured — count before claiming (§A3)** | Variability staging is arithmetic on the existing log | Femtech clusters on fertility; what exists is subscription-gated (judgement) |
| 9 | **Unread-signal small adds** — stair speeds + 6MWT into gait, apnoea/irregular-rhythm events as corroborating witnesses, ANC into sound dose, alcoholic-beverages type into the substance log | Per-row in §5 | Held by HealthKit; per-signal coverage on this record uncounted — count each before building | Trivial — they extend shipped cards | Long-tail signals, low ROI at population scale; high ROI when one person's record is the product |
| 10 | **Medication timing patterns** — dose-time × outcome mirror, advice refused on principle | TIME 2022 vs Hygia 2020 — the flip is the reason to mirror, never advise | Dose times held **but current panel is weekly tirzepatide only (14 doses)** — inert until R24 admits daily meds | Good once daily meds exist | Regulatory caution; and most vendors would have shipped the Hygia advice and been wrong |

**Sequencing note (judgement).** #1 and #2 share machinery — an episode
similarity/retrieval layer over the existing record — and #2's sick-days
substrate (§B11) is already specified and reader-requested, so the natural
order is 2 → 1 → 3. #5 waits on Q6 regardless of merit. #6 is the cheapest
genuinely novel item in the table and could ship inside a week's session.

**Explicitly not proposed, with reasons:** meal-response/fueling (upheld
refusal B5-32, §3.6); anything already in the 124 open rows — stress (N1),
sound-exposure card (B5-33), device disagreement (B3-23/S8), instrument
coverage (B3-19), within-night curves (B3-20/S10), days-since-dose folding
(B3-21), supplements (Q8), bloods (Q7/B3-24), jetlag (B21), sleep debt/ideal
timeframe/regularity (B18-7/B18-8/S11), social battery (B9-1), screen time
(B9-2), tags (B12), notifications (Q11), body scan (Q15/I9), crowd norms
(A4/`norms-and-telemetry.md`), daylight/UV/spirometry/mood/oral/falls capture
(B5-37), basal-temperature radar channel (R33), personal relationship mining
for nutrition (R26 — the precedent engine generalises it and should absorb it
if built).

---

## 7. Sources

Checkable by author/year/venue; none fetched this session (§0), all cited from
knowledge and stated only to the precision I am confident of.

- Ledger D, McCaffrey D. *Inside Wearables.* Endeavour Partners, 2014.
- Clawson J, et al. *No longer wearing: investigating the abandonment of
  personal health-tracking technologies on Craigslist.* UbiComp 2015.
- Lazar A, et al. *Why we use and abandon smart devices.* UbiComp 2015.
- Epstein DA, et al. *A lived informatics model of personal informatics.*
  UbiComp 2015.
- Choe EK, et al. *Understanding quantified-selfers' practices in collecting
  and exploring personal data.* CHI 2014.
- de Zambotti M, et al. Oura ring validation against polysomnography.
  Chronobiology International, 2019.
- Karkar R, et al. *A framework for self-experimentation in personalized
  health.* JAMIA 2016.
- Karkar R, et al. *TummyTrials: a feasibility study of using
  self-experimentation to detect individualized food triggers.* CHI 2017.
- Daskalova N, et al. *SleepCoacher: a personalized automated
  self-experimentation system for sleep recommendations.* UIST 2016.
- Radin JM, et al. Prolonged physiological and behavioral changes associated
  with COVID-19 infection. JAMA Network Open, 2021.
- Elliott N, et al. Graduated return to play guidance following COVID-19
  infection. British Journal of Sports Medicine, 2020.
- Eichner ER. Infection, immunity, and exercise. The Physician and
  Sportsmedicine, 1993 (the "neck check").
- Pietilä J, et al. Acute effect of alcohol intake on cardiovascular autonomic
  regulation during the first hours of sleep. JMIR (Mental Health), 2018.
- Mackenzie IS, et al. The TIME study — evening vs morning antihypertensive
  dosing. The Lancet, 2022. (Contrast: Hermida RC, et al., Hygia, European
  Heart Journal 2020, whose findings TIME did not reproduce.)
- Obradovich N, et al. Nighttime temperature and human sleep loss in a
  changing climate. Science Advances, 2017.
- Gold DR, et al. Ambient pollution and heart rate variability. Circulation,
  2000.
- Laukkanen T, et al. Sauna bathing and cardiovascular/all-cause mortality.
  JAMA Internal Medicine, 2015.
- Roenneberg T, et al. Social jetlag: misalignment of biological and social
  time. Chronobiology International, 2006; and social jetlag and obesity,
  Current Biology, 2012.
- Harlow SD, et al. STRAW+10: Stages of Reproductive Aging Workshop + 10.
  2012 (multi-journal executive summary).
- Berry SE, et al. Human postprandial responses to food (PREDICT). Nature
  Medicine, 2020. *(Evidence recorded; feature parked under B5-32.)*
- Giancardo L, et al. Computer keyboard interaction as an indicator of early
  Parkinson's disease. Scientific Reports, 2016. *(Infeasible on iOS; recorded
  to prevent re-research.)*
- Nissenbaum H. Privacy as contextual integrity. Washington Law Review, 2004.
- Cole CR, et al. Heart-rate recovery immediately after exercise as a
  predictor of mortality. NEJM, 1999. *(Basis for HRR — already consumed by
  Heart Health and Fitness; listed because §5 verified it needs no new work.)*
- Products referenced as design precedents (judgement, feature states as of
  early 2026): Whoop journal impact reports; Oura tags and cycle insights;
  Exist.io and Bearable (correlation surfaces); Visible (pacing for long
  covid/ME-CFS); SnoreLab (snoring capture).
