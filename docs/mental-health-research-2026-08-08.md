# Mental health, psychiatric medication and drug interactions — the evidence

_Research for backlog `R60`, brief commissioned 2026-08-07, written 2026-08-08.
**The topic was uncovered**: the agent originally commissioned for it returned
nothing, so nothing here builds on prior work in this repo besides
`MentalHealthModel` itself._

**The reader's brief, verbatim:** *"Research the mental health card, and how we
can improve it, what sources we can input, and what new data points we can
derive, and nested derivations using all the data we have. Even investigate how
we can get people to share with us anti mental health drugs they are on, so we
can then put that into weightings, and investigate how other things could impact
the effectiveness... E.g. if you are on lexapro, but have MDMA.. you could have a
very bad few days after because of the mood drop."*

---

## The verdict, in six sentences

The four behaviours `MentalHealthModel` already reads are the right four —
reduced daytime activity, disrupted rest–activity rhythm and reduced HRV are the
best-replicated correlates of low mood there are, and every one of them is a
**population association with a small effect size**, not a per-person detector.
Psychiatric medication moves three of those four channels **directly and
pharmacologically**, which means a card that watches HRV while somebody starts
an SSRI is watching the drug, not the illness — and the card currently has no way
to know a drug was started, so it will silently attribute the drug's effect to
the person. Capturing psychiatric medication is therefore **defensive first and
analytic second**: the first thing it buys is a confound named on a row, not a
new finding. The interaction the reader named is real and well-documented in the
right direction — SSRIs *blunt* MDMA rather than amplifying it — and the
genuinely dangerous class is **MAOIs**, which have killed people in combination
with MDMA and must be handled as a static published warning that never passes
through any scoring path. The post-MDMA mood dip is real at group level and
**substantially confounded by sleep**, which is exactly the confound this app is
best placed to see and worst placed to disentangle. And on this reader's own
record almost nothing here can be *discovered* — the substance log holds **a
handful of occasions, far below every episode gate this app already enforces**
(`SubstanceEpisodes.minimumEpisodesToDescribe = 3` is the smallest of them), so
every interaction finding starts life as a published prior shown against their
record, and must say so in the sentence. Per `docs/privacy-and-ip.md`, the
precise counts and dates stay out of this public document — the *shape* is what
the design needs, and the shape is "priors only".

---

## §1 — What wearable signals actually track mental state

### 1.1 The three findings that survive

| Signal | Finding | Effect size | n | Source |
| --- | --- | --- | --- | --- |
| **Daytime activity** | Lower in depression, case–control | SMD **−0.76** (95% CI −1.05 to −0.47) | 412 patients, 19 papers from 16 studies | Burton et al. 2013, *J Affect Disord* — "Activity monitoring in patients with depression: a systematic review" |
| **Daytime activity, during treatment** | Rises as treatment proceeds | SMD **+0.53** (0.20 to 0.87); night-time activity **−0.36** (−0.65 to −0.06) | same review, longitudinal arm | Burton et al. 2013 |
| **Rest–activity rhythm amplitude** | Lower amplitude ↔ mood disorder | per one-quintile drop: MDD OR **1.06** (1.04–1.08); bipolar **1.11** (1.03–1.20); mood instability **1.02** (1.01–1.04) | **91,105** accelerometer-wearing adults | Lyall et al. 2018, *Lancet Psychiatry* 5(6):507–514 |
| **HRV, unmedicated depression** | Lower than controls | RMSSD Hedges' g **−0.462** (−0.612 to −0.312); HF **−0.318** (−0.388 to −0.247); SDNN **−0.266** | 2,250 patients / 1,982 controls, 21 studies | Koch et al. 2019, *Psychol Med* 49(12) |
| **HRV, including medicated samples** | Lower, and **antidepressant treatment does not resolve it** | HF g **−0.293**; time-domain g **−0.301** | 673 depressed / 407 controls, 18 articles | Kemp et al. 2010, *Biol Psychiatry* 67(11):1067–1074 |

That is the whole honest evidential base for this card, and the app already reads
all four channels it implies (`MentalHealthModel.channels`,
`InsightKit/Sources/InsightKit/Insights/MentalHealthModel.swift:117`).

### 1.2 ⚠️ Read those effect sizes as what they are

**Lyall's odds ratio is 1.06.** Ninety-one thousand people, an unambiguous
direction, a confidence interval nowhere near 1 — and a *six percent* change in
odds per quintile of circadian amplitude. That is a real population signal and it
is nearly useless as a per-person indicator. The same is true of Koch's
RMSSD g of −0.46: a medium effect at group level means the distributions overlap
heavily, and it was measured **between people**, not within one person across a
fortnight. Nothing in this table licenses the sentence "your HRV is down, so your
mood is down."

`MentalHealthModel` already declines to make that sentence, and the reason it is
right to is arithmetic, not modesty.

### 1.3 ⚠️ The replication problem, stated bluntly

Digital phenotyping — the field that promises mood inference from passive phone
and wearable data — has a serious and openly acknowledged reproducibility
problem.

- A systematic review of digital phenotyping for depression prediction
  ("From smartphone data to clinically relevant predictions", *Neuroscience &
  Biobehavioral Reviews*, 2024) included **14 studies covering 3,249
  participants**, found only *moderate* model performance, and named the
  recurring methodological failures: missing data, no harmonised feature set,
  and — the important one — **a lack of external test sets**. Author list not
  verified in this pass; cited by title, journal and year.
- The specific feature family most often reported — GPS-derived location entropy
  and time-at-home — is repeatedly described in that literature as having
  replication and generalisability problems, with calls for replication in
  larger and more heterogeneous samples before the associations are relied on.
- Prediction of *affect* specifically is harder to replicate than prediction of
  aggregate symptom scores, and population-level daily-mood prediction from
  phone use is limited by the sheer size of between-person variation in phone
  habits.

**This repo has already been here.** `docs/illness-detection-evidence-2026-08-07.md`
found the same shape in a neighbouring literature: impressive retrospective
AUCs, then prospective positive predictive values of 4–12%. Assume the same
discount applies to any mood-detection claim, because the study designs are the
same designs.

**What follows for us, concretely:** a mental-health feature in this app must be
built out of the *replicated* effects (activity down, rhythm disrupted, HRV
down) reported as departures from the reader's own baseline, with alternatives
named — which is precisely the existing design. Any "we predicted your mood"
capability is out of reach and should be recorded as refused, not deferred.

### 1.4 Sources we could input, and what each is actually worth

| Source | Status in this app | Honest verdict |
| --- | --- | --- |
| Step count, exercise minutes, sleep onset, HRV | **Arriving densely** — the card runs on the reader's record today | The evidence base above. Keep. |
| `HKStateOfMind` (iOS 18 mood logging) | **Zero rows.** Needs its own `HKSampleQuery`; a `"HKStateOfMind"` string mapping exists at `RawFieldGrouping.swift:122` but nothing produces it (`docs/mood-oral-capture-findings.md`) | The only *direct* measurement of the thing. Worth capturing precisely because everything else is a proxy — but it is an input to be offered, never a source to claim we have. |
| Mindful minutes / `MindfulSession` | **Zero rows** (`docs/backlog.md:690`) | Nothing to read. |
| Screen time | 26 days, hand-entered, gated by `CoverageGate` (`ScreenTimeSleepLink.swift`) | Evening screen use is a plausible channel and there is nowhere near enough of it. The existing coverage gate is the correct posture. |
| Calendar density / work load | `CalendarEvent`, `CalendarEventClassifier` present | The strongest **alternative explanation** source we have: a brutal fortnight at work moves all four channels. Better used to *defend* the card than to feed it. |
| Sleep regularity index | `SleepRegularityIndex.swift` exists | Directly the Lyall construct. The best unexploited fit in the codebase. |
| Location entropy / time-at-home | ⚠️ **Deliberately impossible here.** `PlaceContext.swift` stores no timeline by design, citing de Montjoye et al., *Sci Rep* 3:1376 (2013) — four points re-identify a person | Do not propose it. The privacy design is more valuable than the feature, and the feature's literature is the least replicable part of the field. |
| Typing dynamics, voice prosody | Not available to third-party iOS apps | No path. Record as refused for platform reasons, not for evidence reasons. |
| Vendor mood/stress composites (Oura, WHOOP) | — | **Relay only, never blend** (standing rule). Their formulas are undisclosed. |

---

## §2 — Psychiatric medication and the signals this app reads

### 2.1 What each class measurably does to HR, HRV and sleep

| Class | Heart rate | HRV | Sleep / activity | Evidence |
| --- | --- | --- | --- | --- |
| **TCAs** (amitriptyline, imipramine) | **Up**, markedly | **Down**, largest effect of any class | Sedating; earlier sleep onset common | Licht et al. 2010, *Biol Psychiatry* 68(9):861–868 — NESDA, **n=2,114**, baseline and 2-year follow-up; new TCA users showed increased heart rate *and* decreased respiratory sinus arrhythmia vs continuous non-users |
| **SNRIs** (venlafaxine, duloxetine) | **Up** | **Down**, intermediate | Activating; insomnia common early | Licht et al. 2010, same cohort |
| **SSRIs** (escitalopram/Lexapro, sertraline, fluoxetine…) | **Not raised** | **Down** — smaller than TCA/SNRI but present | REM suppression, increased awakenings; insomnia or somnolence both common in the first weeks | Licht et al. 2010; Kemp et al. 2010 (antidepressant treatment did **not** resolve the HRV reduction across 18 studies) |
| **Antipsychotics** | Up (clozapine, olanzapine) | **Down** — clozapine largest; olanzapine and aripiprazole significant; **ziprasidone and risperidone showed no such fall** | Strongly sedating; weight gain over months | Huang, Wei & Qin, *Int J Psychiatry Med* 2025 (epub 2024), retrospective, **n=164** schizophrenia patients, SDNN/RMSSD/PNN50 at weeks 2 and 4 |
| **Prescribed stimulants** (methylphenidate, lisdexamfetamine) | **Up ~4–6 bpm** at rest | Expected down; not separately quantified in the sources read | Delayed sleep onset, reduced total sleep | "Meta-analysis of increased heart rate and blood pressure associated with CNS stimulant treatment of ADHD in adults", *Eur Neuropsychopharmacol* 2013 — resting HR **+5.7 bpm**; a separate ADHD review reports **+4.37 bpm** for methylphenidate vs placebo. Author lists not verified in this pass |
| **Benzodiazepines, lithium** | — | — | — | ⚠️ **I found no adequate quantitative source for either in this pass.** Do not print a figure for them. |

### 2.2 ⚠️ Direction of travel is *not* settled for SSRIs, and this matters

Two literatures point opposite ways and both are real:

- **Licht 2010** (n=2,114, observational, 2 years): starting an SSRI is followed
  by *reduced* vagal tone; stopping reverses it. Framed by its authors as an
  unfavourable drug effect.
- **Treatment-response studies** at 8 weeks and 6 months report HRV
  *improving* alongside symptom remission — i.e. the illness suppresses HRV
  (Koch's unmedicated g of −0.46 is the disease effect) and recovery restores it,
  partly against the drug's own direction.

**These are not reconcilable from the outside**, and the net direction in any one
person over any one fortnight is unknown. That is the single most important
sentence in this document for the wording rules in §4: **an HRV change after a
medication change has at least two published explanations pointing opposite
ways, so the app cannot read it as evidence about anything.**

### 2.3 Onset, washout, and what a card would actually SEE

**⚠️ No published day-by-day curve exists for HRV after starting an SSRI.** This
is a finding, not a gap in my search. The evidence is at 2-week, 4-week, 8-week,
6-month and 2-year resolution; nothing in what I read supports a daily
trajectory, an expected magnitude for one person, or a time-to-detect. Any curve
this app drew would be invented. Contrast `Pharmacokinetics.swift`, where the
GLP-1 curve rests on published absorption and elimination half-lives — **there
is no equivalent for a psychiatric drug's effect on a wearable signal.** The
plasma-level pharmacokinetics of escitalopram are published; the mapping from
plasma level to RMSSD is not.

What *can* be said, and what a card watching HRV/sleep would plausibly see:

| Event | Pharmacological timescale | What the four channels might show | Confidence |
| --- | --- | --- | --- |
| **Starting an SSRI** | Steady state in ~1–2 weeks; clinical effect conventionally 2–6 weeks | Sleep disruption in the first weeks is the most likely visible thing; HRV drift over months, direction contested (§2.2) | **Low.** Direction contested, magnitude unpublished |
| **Missing a dose** | Escitalopram half-life ~27–32 h — one missed dose is a modest dip | ⚠️ **Almost certainly nothing visible.** Do not build a "missed dose" detector | Effectively zero |
| **Stopping** | Discontinuation symptoms — dizziness, headache, nausea, **insomnia**, irritability | Insomnia and irritability are the ones that could touch sleep onset and HRV | Moderate for *some* people; see below |
| **Stopping, short half-life agents** | Paroxetine and venlafaxine are the classic offenders | Same, sooner and harder | Moderate |

**Discontinuation, quantified honestly:** Henssler et al. 2024, *Lancet
Psychiatry* 11(7):526–535 — systematic review and meta-analysis, **79 studies,
21,002 patients** (16,532 discontinuing an antidepressant, 4,470 placebo). About
**31%** report at least one symptom, but so do people discontinuing placebo; the
incidence **attributable** to the drug is about **15%**, roughly one in six or
seven. Severe symptoms in about **3%** (one in 35). Imipramine, paroxetine and
(des)venlafaxine carried higher risk of severe symptoms.

So: five in six people who stop will not show anything a card could see, and the
one who does will show it in signals (insomnia, irritability) with a hundred
other causes. **A card must not offer to detect discontinuation.** The figure is
still worth holding, because it belongs in the safety copy at §4.4.

### 2.4 What capturing medication actually buys us

Not a new score. Three defensive things, in order of value:

1. **A named confound on the HRV channel.** `MentalHealthModel.channels`
   (`:117`) currently gives HRV the alternative *"This falls for illness,
   alcohol, heat and hard training — it is the least specific signal here."*
   Every class in §2.1 belongs in that sentence. **This is the cheapest
   defensible change in this entire document**: one string, no new data, and it
   closes a case where the card would otherwise report a drug's pharmacology as
   the reader's fortnight.
2. **A reason to withhold.** A card that knows a medication changed in the
   window has grounds to *say less*, which no amount of extra data provides.
3. **A marker on a chart** — under the `SubstanceShading` rule, which already
   exists and already says the right thing: it marks *when something was logged,
   never what it did*.

---

## §3 — The interaction the reader named, and its class

### 3.1 SSRI × MDMA: real, well-documented, and **the opposite direction to the folk model**

The anchor source is **Sarparast et al. 2022, *Psychopharmacology* (Berl)
239(6):1945–1976** — "Drug-drug interactions between psychiatric medications and
MDMA or psilocybin: a systematic review". **40 publications: 26 RCTs, 3
epidemiologic studies, 11 case reports**; the RCTs covered over 200 healthy
adults, 24 of them MDMA studies.

| Combination | What happens | Figures |
| --- | --- | --- |
| **SSRI + MDMA** (citalopram, fluoxetine, paroxetine) | MDMA's subjective effects **substantially blunted**; physiological effects barely touched. ⚠️ **MDMA plasma concentrations *rise*** (CYP2D6 inhibition) — more drug in the blood, less effect from it | subjective **−30% to −80%**; physiological **−6% to −14%** |
| **SNRI + MDMA** (duloxetine) | Broad attenuation of both | subjective ~−55% to −84%; HR/BP ~−57% to −64% |
| **Bupropion + MDMA** | ⚠️ **Opposite.** *Prolongs* and heightens the positive mood effects, while raising heart rate and circulating catecholamines | — |
| **Haloperidol + MDMA** | Shifts the experience toward dysphoria and anxiety | — |
| **MAOIs, lithium + MDMA** | **No RCTs exist.** Evidence is epidemiologic and case reports | see §3.2 |

The mechanism is clean and worth stating in the code comments: MDMA works by
**reversing** the serotonin transporter to dump serotonin out; an SSRI **occupies
and inhibits** that same transporter, so there is nothing for MDMA to reverse.
The single most instructive experiment is **Hysek et al. 2012, *PLoS ONE*
7(5):e36476** — double-blind, randomised, placebo-controlled, four-session
crossover, **n=16**: duloxetine blunted the response *despite raising plasma
MDMA levels*. Blockade is pharmacodynamic, not pharmacokinetic. Earlier and
consistent: **Liechti, Baumann, Gamma & Vollenweider 2000, *Neuropsychopharmacology*
22(5):513–521, n=16** (citalopram 40 mg IV attenuated MDMA's psychological
effects) and **Liechti & Vollenweider 2000, *J Psychopharmacol* 14(3):269–274,
n=16** (cardiovascular and vegetative effects attenuated).

⚠️ **Two caveats that must travel with those numbers.** First, the controlled
evidence is **acute intravenous or single-dose pretreatment in samples of about
sixteen people** — it is not somebody on a stable daily 10 mg of escitalopram for
eight months, and the chronic-dosing evidence is survey and self-report level.
Second, the blunting creates its own hazard: **the predictable human response to
"it isn't working" is redosing**, and Hysek shows plasma levels are already
elevated. That is the practically dangerous consequence of this interaction, and
it is a harm-reduction fact, not a mood forecast.

⚠️ **The reader's own framing needs correcting in the copy, gently.** "You're on
Lexapro but took MDMA, so expect a very bad few days" is a reasonable inference
that the literature does not support in that direction — an SSRI on board makes
the acute experience *smaller*, and the serotonin-release-then-depletion story
that drives the comedown is exactly what the SSRI is interfering with. There is
no published study of the comedown *specifically in chronic SSRI users*. **"No
published curve exists for this" is the answer**, and this app's job is to say so
rather than pick the intuitive direction.

### 3.2 ⚠️⚠️ MAOI × MDMA — safety-critical, and it never becomes lifestyle copy

**This is the combination that kills people.**

**Vuori et al. 2003, *Addiction* 98(3):365–368** — **four deaths** following
ingestion of MDMA together with **moclobemide** (a reversible MAO-A inhibitor).
The probable cause of death in each case was **serotonin syndrome** from the
interaction. None of the four had been prescribed moclobemide; each appears to
have taken it deliberately **to enhance the MDMA**, which is the exact belief
this warning has to defeat.

The pharmacology is the mirror image of §3.1: an SSRI blocks the transporter and
*reduces* the serotonin surge; an MAOI blocks the enzyme that *clears* serotonin,
so the surge has nowhere to go. Sarparast's review is explicit that
SSRIs/SNRIs/TCAs are **unlikely** to push serotonin to life-threatening
toxicity — precisely because transporter inhibition negates MDMA's mechanism —
which makes MAOIs the isolated, categorical exception rather than one point on a
gradient.

Classical MAOIs: phenelzine, tranylcypromine, isocarboxazid, selegiline
(including transdermal). Reversible: moclobemide. Also relevant and frequently
missed: **linezolid** (an antibiotic with MAOI activity) and **methylene blue**.

**Design rules, non-negotiable:**

- This is **a static, published, pre-emptive warning shown at capture time** —
  when a reader records an MAOI, or records MDMA while an MAOI is on the
  regimen. It is **not** an insight, **not** derived from any measurement, and
  **never** the output of a scoring path.
- It never enters a weighting, never contributes to a score, never becomes a
  "driver row", and never softens into a caveat sentence at the bottom of a
  card.
- It **cannot be dismissed into silence** by the card-dismissal machinery.
- The copy names serotonin syndrome and says to seek medical help. It does not
  say "may affect your recovery" or any other lifestyle register.
- ⚠️ It must not be gated behind data sufficiency. Everything else in this
  document waits for n; this waits for nothing.

The review also cites an FDA adverse-event-reporting analysis with elevated
mortality-report odds for bupropion (**OR 2.82**) and sertraline (**OR 2.36**)
co-reported with MDMA. ⚠️ **Second-hand: I did not read the primary FAERS
analysis, and a disproportionality signal in spontaneous reports is not an
incidence.** Do not put those two numbers in front of a reader.

### 3.3 The post-MDMA mood dip — real, and mostly not what people think

| Study | Design | n | Finding |
| --- | --- | --- | --- |
| **Curran & Travill 1997**, *Addiction* 92(7):821–831 | Users assessed day 1, day 2, day 5 | ⚠️ n not verified in this pass | Elevated mood day 1, significantly **low mood day 5**, some scoring in the clinically depressed range. The origin of "Suicide Tuesday" |
| **Blankers et al. 2025**, *Drug Alcohol Depend* 276:112881 | Daily EMA, **35 days**, European nightlife cohort | **244** (UK 120, NL 124), aged 18–34 | Significant drop in mental well-being over the **three days** following use: **B = −0.14, SE = 0.04, p < .001**. Persisted after adjusting for other substances, depression, anxiety and sleep quality. Cocaine co-use and poor sleep made it worse |
| **Medina-Kirchner & Lukas 2026**, *Drug Alcohol Depend Rep* 19:100422 | Within-subject daily diary: one use weekend vs one non-use weekend, each followed by Mon–Thu | **17** | Monday mood ~**1.4 points lower** on a 0–10 scale; Weekend × Day interaction **F(3,48) = 3.41, p = 0.037**; Monday **t(16) = 2.36, p = 0.031**. ⚠️ **Adjusting for hours spent in bed attenuated the effect to non-significance (β = −0.82, p = 0.17)** |
| **Sessa et al. 2022**, *J Psychopharmacol* | Clinical MDMA in an alcohol-use-disorder trial | **14** | **No** affect drop in the week after dosing. Published letter criticised the claim as unjustified by n=14 |

**Read those four rows together and the honest summary is:**

1. The dip is **real at group level** and now has modern daily-diary support with
   an effect size (Blankers, n=244).
2. It is **small**. B = −0.14 on a standardised well-being measure is not "a very
   bad few days" for the average person; it is a detectable group shift.
3. **Sleep may be most of it.** The one study that adjusted for time in bed
   watched the effect vanish (Medina-Kirchner, n=17 — small, but that is the
   *direction* of the confound, and this app measures sleep).
4. **Context matters enormously.** Clinical administration, with sleep and
   without a nightclub, produced no dip at all in the one small trial that
   looked.

⚠️ **This is where this app is uniquely placed and uniquely at risk.** It holds
the sleep data that Medina-Kirchner used to dissolve the effect. It could
legitimately show *"you slept four hours less across that weekend"* — an
observation. It must not show *"your comedown was worse because of your
medication"* — a claim resting on a study that does not exist.

### 3.4 Generalising: the other interactions worth holding

| Interaction | What the evidence says | Confidence | What we may say |
| --- | --- | --- | --- |
| **Alcohol × HRV** (with or without medication) | Acute alcohol suppresses nocturnal vagal HRV, dose-dependently. Pietilä et al. 2018, *JMIR Ment Health* 5(1):e23 — **n=4,098** Finnish employees, beat-to-beat R-R over the first 3 h of sleep, **within-subject** comparison of drinking vs non-drinking nights. ⚠️ Magnitudes not extracted in this pass — do not print one | **High** for direction; the design is the closest published analogue to what this app does | The HRV channel's existing alternative already names alcohol. Keep it, and cite this study for it |
| **Alcohol × antidepressants** | Additive sedation and impairment is pharmacologically expected. ⚠️ **I found no wearable-signal study of the combination.** No effect size exists to print | **None for anything measurable** | Nothing quantitative. A capture-time note at most |
| **Cannabis × HRV** | ⚠️ **Contradictory.** A lab THC-before-bed study (Gonzalez et al. 2026, *J Sleep Res*) reports markedly reduced HRV; an older study of young men (PubMed 20191442) reports *higher* resting RMSSD in users (56.2 ms vs 48.6 ms in controls); WHOOP's own blog reports ~1 bpm higher resting HR and ~2.8 ms lower HRV the next day | **Low. Direction not settled** | Say the direction is not settled. ⚠️ The WHOOP figure is a **vendor composite with an undisclosed method** — relayable as a labelled second opinion, never blended into anything |
| **Prescribed stimulants × the card's channels** | +4–6 bpm resting HR (§2.1); delayed sleep onset | Moderate | This directly moves `sleepOnset`, one of the four channels. It is a confound, not a finding |
| **St John's Wort** | Potent **CYP3A4 inducer** — Markowitz et al. 2003, *JAMA* 290(11):1500–1504, open-label crossover, **n=12**, 14 days of 300 mg t.i.d., measured against alprazolam and dextromethorphan probes. Halves the exposure of many co-administered drugs; combined with an SSRI it is also a serotonergic load | **High** for the enzyme induction | ⚠️ It is sold as a supplement, so it can arrive through `SupplementStack` while the reader does not think of it as a drug. **This is the most likely silent interaction in the whole document** and belongs in the supplement capture path, not the medication one |
| **Bupropion × MDMA** | Enhances rather than blunts (§3.1) | Moderate — from the review | The one antidepressant where "it will feel weaker" is wrong |

---

## §4 — ⚠️ The wording problem. This is the hard part.

### 4.1 The two failures, named

The card's founding rule is **it never reassures** — "you seem fine" arriving by
arithmetic to somebody having a bad month is the worst available failure
(`docs/backlog.md:686`, `MentalHealthModel` header).

Introducing medication creates the **mirror failure, which is worse because it is
lethal in one direction**:

> **A person reads "your medication may not be working", stops taking it, and
> comes off an antidepressant abruptly on the say-so of a step counter.**

Henssler's numbers make the harm concrete rather than theoretical: about one in
six who discontinue get symptoms attributable to the drug, one in 35 severe, and
that is with a *planned* taper. An unplanned stop prompted by a phone is
strictly worse. There is no version of this card that is allowed to make that
sentence, in any register, however hedged.

### 4.2 Where exactly the line falls

The reader's own example draws it well. Consider four sentences of increasing
sin:

| # | Sentence | Verdict |
| --- | --- | --- |
| 1 | *"Your heart-rate variability has been lower than your season since the 12th."* | ✅ **Observation.** A statement about a number and a date. Already the card's house style |
| 2 | *"Your heart-rate variability has been lower since the 12th. You recorded a medication change on the 11th."* | ⚠️ **The line.** Both halves are true and the juxtaposition does the arguing. This is the sentence to be most careful about — see 4.3 |
| 3 | *"Your HRV fell after you started escitalopram — SSRIs are known to reduce HRV."* | ❌ **Causal claim** about a contested direction (§2.2), stated as settled |
| 4 | *"Your HRV has not recovered, which may mean the medication isn't working."* | ❌❌ **Catastrophic.** An efficacy claim. Never, under any gate, at any n |

### 4.3 The rule that resolves row 2 — and it already exists in this codebase

**`SubstanceShading` marks when something was logged, never what it did.** The
same rule, applied to medication, resolves the whole problem:

> **A medication is a marker on a chart and a date in a list. It is never the
> subject of a sentence whose predicate is a change in a signal.**

The chart may show a vertical marker on the 11th. The reader can see the marker
and see the line and draw their own conclusion — which is their business, their
body and their prescriber's conversation. The app does not write the sentence
that joins them. That is not a dodge: it is exactly the distinction between
showing a record and making a claim, and it is the same distinction the app
already enforces everywhere else it draws substance shading.

### 4.4 Concrete copy rules

**Forbidden outright, at any n:**

- Any sentence containing a medication name and a signal change in the same
  clause.
- The words *working*, *effective*, *helping*, *response* applied to a
  medication.
- Any suggestion, however framed, to change a dose, skip, stop, taper, or "see
  if things improve without it". This app is a health diary; that is
  prescribing.
- Any implication that the card can tell whether a treatment is right.
- ⚠️ Any push notification on this subject whatsoever. A phone that buzzes about
  your psychiatric medication while you are at work is a category of harm this
  app should not enter.

**Required, whenever medication appears anywhere near this card:**

- A fixed, non-dismissible line to the effect of: *this cannot tell you whether a
  medication is working, and stopping suddenly has its own effects — that is a
  conversation with whoever prescribed it.*
- The existing two closing rows stay
  (`MentalHealthModel.evaluate`, the *"has no idea how you feel"* and *"does not
  diagnose anything"* drivers).
- The HRV channel's `alternative` string extended to name medication (§2.4).

**Permitted:**

- The date. Always the date. *"Since the 12th"* is the most information this
  feature is allowed to add, and it is genuinely useful.
- Withholding, out loud, with the reason. `CoverageGate` already exists for
  exactly this — say *how many more* rather than going quiet.
- The published prior, labelled as somebody else's finding about other people,
  never as a measurement of the reader (§6.2).

### 4.5 The escalation exception

Everything in 4.4 is about *efficacy* and *mood*. §3.2's MAOI warning is a
different object entirely: a safety fact, published, static, shown pre-emptively
at capture, in plain clinical language. Softening it into this section's register
would be its own failure. **Two vocabularies, one file, and the boundary between
them is whether the sentence could contribute to somebody stopping a
prescription (never) or to somebody not dying (always).**

---

## §5 — Capture: what exists, and what psychiatric medication would need

### 5.1 ⚠️ The existing Medication machinery is GLP-1-shaped end to end

This is the finding that governs the build, and it is not obvious from the
outside because everything is called "Medication".

| Thing | Where | Why psychiatric drugs do not fit |
| --- | --- | --- |
| `GLPCompound` | `InsightKit/Sources/InsightKit/Signals/Pharmacokinetics.swift:10` | A **closed enum of three GLP-1 agonists** carrying elimination and absorption half-lives, a dosing interval, and a manufacturer's titration ladder |
| `MedicationRecord` | `HealthInsights/Core/Persistence/PersistenceModels.swift:529` | `compound: GLPCompound?` — a record whose compound is not one of three is *unrepresentable* |
| `DoseLogRecord` | `PersistenceModels.swift:561` | Carries `injectionSite`. A tablet has no injection site |
| `MedicationResponse`, `MedicationDoseResponse` | `Signals/` | Attribute **weight** and **intake vs expenditure** change to dose rungs. Neither question applies |
| `MedicationCurveChart`, `MedicationSection` | app target | Draw the Bateman curve for a weekly injection |
| `activeMedicationLevel` | `MetricType.swift:247` | Comment says it plainly: *"mg of GLP-1 still active — modelled"* |

`GLPCompound` appears **27 times across 7 files**. Verified against the reader's
own export: the `medication` key is a single object with a `compound`, a
`brandName` and an array of dated injections with sites.

**So "extend the existing Medication machinery" is the wrong instruction.** The
options are:

- **(a) A parallel `Prescription` type** — free-text or coded name, class, dose,
  schedule, start date, optional stop date. No pharmacokinetic model, no curve,
  no response analysis. Reuses `DataDomain.medication` for display and
  `InputKind.medicationRegimen`'s sheet pattern, and shares nothing with
  `GLPCompound`. **This is the honest shape**, because the thing that makes the
  GLP-1 machinery valuable — a published curve — does not exist here (§2.3).
- **(b) Generalise `GLPCompound` into a protocol.** Tempting, and wrong: it would
  put psychiatric drugs on a code path whose entire purpose is to model an
  active level the literature does not support for them. The abstraction would
  invite exactly the invented curve §2.3 forbids.

**What is already reusable and should be reused:**

- `SideEffectRecord` — free-text `name`, `severity`, `date` in the export, and
  domain-generic. Psychiatric side effects fit unchanged.
- `SubstanceEventRecord` (`PersistenceModels.swift:166`) and
  `SubstanceClass` — `.mdma`, `.stimulant`, `.alcohol`, `.cannabis` all exist
  already, so the *substance* half of every interaction in §3 is already
  capturable.
- `DataDomain.medication` / `.sideEffects` / `.substances`
  (`Presentation/DataDomain.swift`) — the display contract holds.
- `InputKind.medicationRegimen` / `.medicationDose` / `.sideEffect` /
  `.substanceEvent` (`Presentation/InputKind.swift`) — the input surfaces
  already exist, and the `add-data-or-input` skill governs any change.
- `SupplementStack` — ⚠️ **and St John's Wort will arrive here, not through
  medication** (§3.4).

### 5.2 How to get someone to tell you, and what the answer is worth

The reader asked specifically how to get people to share psychiatric medication.
Three things from the literature and one from this codebase.

**What the adherence literature says about self-report:**

- Self-reported adherence **systematically overestimates** actual adherence when
  compared against electronic pill-bottle monitoring, with **high specificity and
  low sensitivity** — i.e. someone who reports missing doses really did, but many
  who report perfect adherence did not.
- In antidepressants specifically, one study of an underserved community (n=38)
  found self-report and electronic monitoring in only *fair-to-slight* agreement
  at baseline, 6 and 12 weeks; another found **35–36% poor adherence by pharmacy
  refill records versus 18–24% by self-report** at 6 and 12 months.

**⚠️ The consequence for weighting, stated plainly:** a self-reported psychiatric
regimen tells you *what was prescribed*, and only weakly *what was taken*. Any
model that treats "on escitalopram 10 mg" as a fact about the reader's
bloodstream is wrong at a known and substantial rate. **This is a second,
independent reason not to build an active-level curve** (the first being §2.3's
absence of a published dose–signal relationship).

**What would actually get it captured:**

1. **Ask for the class, not the molecule, as the required field.** "An
   antidepressant" is enough for every defensive use in §2.4 and is a far lower
   disclosure bar than typing *Lexapro* into a phone. Molecule optional.
2. **Say what it is for, at the point of asking, in one sentence.** The honest
   pitch is not "so we can score you better" — it is *"so this app stops blaming
   you for something your medication did"*. That is true, it is the actual
   primary benefit (§2.4), and it is the only pitch that survives the wording
   rules.
3. **Promise the ceiling out loud**: it will never comment on whether the
   medication is working. A reader deciding whether to disclose a psychiatric
   diagnosis to an app is asking exactly that question.
4. **Lean on the local-only guarantee**, which this app can actually make.
   ⚠️ **But note `docs/privacy-and-ip.md`: this repository is public.** A
   psychiatric medication list is the most sensitive category this app has ever
   held. Nothing about it — not a class, not a count, not a date — goes in a
   commit message, a doc, or a test fixture. The rule stands: **the shape of a
   finding, never the reading.**

---

## §6 — Nested derivations, and the n at which each becomes honest

### 6.1 What the reader's record can actually support

Counted from `~/HealthSeed/exports/health-insights-export-new.json` (export of
2026-08-07), rather than assumed:

- **The four card channels arrive densely.** The card evaluates on the reader's
  record today; step count, sleep onset, exercise minutes and HRV are all
  present at daily resolution across the season.
- **The substance log is at single-digit occasions** — below every episode
  gate the app enforces, so nothing per-substance is discoverable from it yet.
  ⚠️ Per `docs/privacy-and-ip.md` (*the shape of a finding, never the reading*),
  the counts, classes, and recency stay out of this public document. The first
  draft printed them; a provenance check caught it before the push, and this
  wording is the redaction.
- **MDMA does not appear in the log at all.** The interaction the reader named
  has **n = 0** in their own record — a zero-row finding, which this repo's
  convention treats as shape.
- **Mood surfaces remain at zero rows** (`docs/backlog.md:690`).
- **The medication record is the GLP-1 one.** No psychiatric drug is recorded,
  so every medication finding in this document currently has **n = 0** as well.

Against the existing gates: `SubstanceEpisodes.minimumEpisodesToDescribe = 3`
(`SubstanceEpisodes.swift:91`) and
`SubstanceResponseAnalyzer.comparisonWindowDays = 90` (`:31`). Roughly five
occasions clears the floor for the *aggregate* substance analysis and clears
nothing at all per-class-per-interaction.

### 6.2 ⚠️ So most of this ships as published priors, not as discovered effects

**Say this plainly in the copy, because it is the difference between honest and
not.** With n = 0 MDMA episodes and n = 0 psychiatric prescriptions, an
interaction section on this reader's phone can contain exactly one kind of
sentence:

> *"In a diary study of 244 people, well-being dipped for about three days after
> MDMA use — an average, not a forecast, and half of it may have been the sleep.
> You have not recorded anything here."*

That is a **relay of somebody else's finding, labelled as such**, in the same
family as the vendor-composite rule: it may be shown, it may not be blended into
a score, and it may never be phrased as a measurement of the reader. The moment
it acquires a number derived from their record without clearing the gate below,
it becomes a lie with a decimal point.

### 6.3 The derivation ladder, with its gates

Ordered by what is buildable now. `n` is **the reader's own episodes or days**,
not the literature's.

| # | Derivation | Inputs | Gate to become honest | Status today |
| --- | --- | --- | --- | --- |
| **D1** | **Medication named as a confound on the HRV channel** | one string | **n = 0.** Correct at any n — it is a caveat, not a finding | ✅ Build now. Cheapest defensible change in this document |
| **D2** | **Regimen capture: class, optional molecule, start/stop dates** | new `Prescription` type (§5.1a) | n = 0 | ✅ Build. Value is defensive |
| **D3** | **MAOI × MDMA pre-emptive warning** | D2 + `SubstanceClass.mdma` | **No gate. Never gated** | ✅ Build with D2, same commit |
| **D4** | **Medication markers on existing charts** | D2 + `SubstanceShading` pattern | 1 event | ✅ Build. Marks when, never what it did |
| **D5** | **Sleep-adjusted post-substance window** — how the days after an occasion looked, *with sleep debt shown alongside* | `SubstanceEpisodes` + `SleepDebt` + the four channels | **≥3 occasions of that class** (existing floor), and the sleep row is **mandatory**, per Medina-Kirchner | ◐ Partly reachable for the classes already logged. ⚠️ Must never present the mood delta without the sleep delta beside it |
| **D6** | **Pooled departure vs medication epoch** — `MentalHealthInsight.pooledKey` before/after a start date | D2 + existing derived series | ⚠️ **Refuse.** This is the row-4 sentence of §4.2 wearing arithmetic. No n makes it safe | ❌ **Record as refused** |
| **D7** | **Per-person SSRI × MDMA interaction** | D2 + MDMA episodes | Needs episodes both on and off the drug. ⚠️ **Realistically unreachable for one person, ever** | ❌ Published prior only (§6.2) |
| **D8** | **Sleep regularity index as a fifth channel** | `SleepRegularityIndex.swift`, already built | Same 7-of-14-days floor as the other channels (`MentalHealthModel.minimumDays`, `:63`) | ◐ **The best genuine improvement available.** It is the Lyall construct measured properly, and unlike the existing `sleepOnset` channel it captures *irregularity* rather than lateness |
| **D9** | **Calendar density as a named alternative** | `CalendarEventClassifier` | 1 fortnight | ◐ Turns "a busy fortnight" from a generic caveat into a specific one the app can actually check |
| **D10** | **`HKStateOfMind` capture** | new query (`docs/mood-oral-capture-findings.md`) | n = 0 | ◐ ⚠️ Capture it, but note that card's founding objection: putting mood on the mental health card claims a sensitivity the behaviour-only model does not have |

### 6.4 The one weighting change worth making

The reader asked to put medication "into weightings". The defensible version is
not a new term in the weighted mean — it is **shrinking a channel's weight when
its confound is known to be active**:

> When a medication known to move a channel started or stopped inside the
> fortnight, that channel's weight drops toward zero and the card says so on the
> row: *"heart-rate variability — not counted this fortnight, because a
> medication change sits inside the window."*

That fits the existing machinery exactly. `MentalHealthModel` already emits
zero-weight `MetricContribution` rows for channels it could not read
(`evaluate`, the `!present.contains` loop), and already refuses to run below two
channels (`:208`). Naming a channel and declining to count it is a move the card
already knows how to make.

⚠️ **Note the honest cost**: with four channels and a two-channel floor, dropping
HRV plus one other silences the card entirely. That is the correct outcome —
silence with a stated reason beats a score built on a drug's pharmacology — and
it is another argument for D8's fifth channel.

---

## What I could not establish

Recorded so the next session does not re-spend the budget:

- **No published day-by-day curve** of HRV, sleep or activity after starting,
  stopping or missing a psychiatric medication. The literature is at 2-week to
  2-year resolution (§2.3).
- **No study of the MDMA comedown in chronic SSRI users specifically** — the
  reader's exact question. The controlled interaction work is acute pretreatment
  in n≈16 lab samples (§3.1).
- **No wearable-signal study of alcohol × antidepressants.**
- **No adequate quantitative source for benzodiazepines or lithium** on HR/HRV in
  this pass.
- **Curran & Travill 1997's n** — the abstract is paywalled; the finding is
  well-attested, the sample size is not verified here.
- **Pietilä 2018's effect magnitudes** — design and n=4,098 verified, numbers not
  extracted.
- **The FAERS mortality ORs** quoted in Sarparast 2022 — second-hand, primary
  analysis not read (§3.2).
- Author lists for the two stimulant meta-analyses and the digital-phenotyping
  systematic review — cited by title, journal and year only.

---

## Sources

- Blankers M, van Beek R, Spronk D, den Hollander W, Andree R, Freeman TP, Grabski M, Curran HV, Waldron J, van Laar MW. *Three-day blues after ecstasy/MDMA use: Evidence from a longitudinal and daily analysis in the European nightlife scene.* Drug and Alcohol Dependence 2025;276:112881. — https://pubmed.ncbi.nlm.nih.gov/40992011/
- Burton C, et al. *Activity monitoring in patients with depression: a systematic review.* J Affect Disord 2013. — https://pubmed.ncbi.nlm.nih.gov/22868056/
- Curran HV, Travill RA. *Mood and cognitive effects of ±3,4-methylenedioxymethamphetamine (MDMA, 'ecstasy'): week-end 'high' followed by mid-week low.* Addiction 1997;92(7):821–831. — https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1360-0443.1997.tb02951.x
- de Montjoye Y-A, et al. *Unique in the Crowd: The privacy bounds of human mobility.* Scientific Reports 2013;3:1376. (cited in `PlaceContext.swift`)
- Henssler J, Schmidt Y, et al. *Incidence of antidepressant discontinuation symptoms: a systematic review and meta-analysis.* Lancet Psychiatry 2024;11(7):526–535. — https://pubmed.ncbi.nlm.nih.gov/38851198/
- Huang L, Wei C, Qin Q. *Effects of six antipsychotic drug treatment regimens on short-term heart rate variability in patients with schizophrenia.* Int J Psychiatry Med 2025 (epub 2024). — https://pubmed.ncbi.nlm.nih.gov/39455903/
- Hysek CM, Simmler LD, Nicola VG, Vischer N, Donzelli M, et al. *Duloxetine inhibits effects of MDMA ("ecstasy") in vitro and in humans in a randomized placebo-controlled laboratory study.* PLoS ONE 2012;7(5):e36476. — https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0036476
- Kemp AH, Quintana DS, et al. *Impact of Depression and Antidepressant Treatment on Heart Rate Variability: A Review and Meta-Analysis.* Biological Psychiatry 2010;67(11):1067–1074. — https://www.sciencedirect.com/science/article/abs/pii/S0006322309014498
- Koch C, Wilhelm M, Salzmann S, Rief W, Euteneuer F. *A meta-analysis of heart rate variability in major depression.* Psychological Medicine 2019;49(12). — https://www.cambridge.org/core/journals/psychological-medicine/article/metaanalysis-of-heart-rate-variability-in-major-depression/F93BB157D9E258B0C64A1EC7F3652A28
- Licht CMM, de Geus EJC, van Dyck R, Penninx BWJH. *Longitudinal evidence for unfavorable effects of antidepressants on heart rate variability.* Biological Psychiatry 2010;68(9):861–868. — https://pubmed.ncbi.nlm.nih.gov/20843507/
- Liechti ME, Baumann C, Gamma A, Vollenweider FX. *Acute psychological effects of MDMA ("Ecstasy") are attenuated by the serotonin uptake inhibitor citalopram.* Neuropsychopharmacology 2000;22(5):513–521. — https://www.nature.com/articles/1395472
- Liechti ME, Vollenweider FX. *The serotonin uptake inhibitor citalopram reduces acute cardiovascular and vegetative effects of MDMA ('Ecstasy') in healthy volunteers.* J Psychopharmacol 2000;14(3):269–274. — https://pubmed.ncbi.nlm.nih.gov/11106307/
- Lyall LM, et al. *Association of disrupted circadian rhythmicity with mood disorders, subjective wellbeing, and cognitive function: a cross-sectional study of 91,105 participants from the UK Biobank.* Lancet Psychiatry 2018;5(6):507–514. — https://www.thelancet.com/journals/lanpsy/article/PIIS2215-0366(18)30139-1/abstract
- Markowitz JS, Donovan JL, et al. *Effect of St John's wort on drug metabolism by induction of cytochrome P450 3A4 enzyme.* JAMA 2003;290(11):1500–1504. — https://pubmed.ncbi.nlm.nih.gov/13129991/
- Medina-Kirchner C, Lukas SE. *Monday mood decline after weekend ecstasy use: A retrospective analysis of daily diary reports.* Drug and Alcohol Dependence Reports 2026;19:100422. — https://pmc.ncbi.nlm.nih.gov/articles/PMC12993375/
- *Meta-analysis of increased heart rate and blood pressure associated with CNS stimulant treatment of ADHD in adults.* Eur Neuropsychopharmacol 2013. (authors unverified) — https://pubmed.ncbi.nlm.nih.gov/22796229/
- Pietilä J, et al. *Acute Effect of Alcohol Intake on Cardiovascular Autonomic Regulation During the First Hours of Sleep in a Large Real-World Sample of Finnish Employees: Observational Study.* JMIR Mental Health 2018;5(1):e23. — https://mental.jmir.org/2018/1/e23/
- Sarparast A, Thomas K, Malcolm B, Stauffer CS. *Drug-drug interactions between psychiatric medications and MDMA or psilocybin: a systematic review.* Psychopharmacology (Berl) 2022;239(6):1945–1976. — https://pmc.ncbi.nlm.nih.gov/articles/PMC9177763/
- Sessa B, Aday JS, O'Brien S, Curran HV, Measham F, Higbed L, Nutt DJ. *Debunking the myth of 'Blue Mondays': No evidence of affect drop after taking clinical MDMA.* J Psychopharmacol 2022. — https://pubmed.ncbi.nlm.nih.gov/34894842/ (and the critical reply, https://pubmed.ncbi.nlm.nih.gov/35924889/)
- *From smartphone data to clinically relevant predictions: A systematic review of digital phenotyping methods in depression.* Neuroscience & Biobehavioral Reviews 2024. (authors unverified) — https://www.sciencedirect.com/science/article/pii/S0149763424000095
- Vuori E, Henry JA, Ojanperä I, Nieminen R, Savolainen T, Wahlsten P, Jäntti M. *Death following ingestion of MDMA (ecstasy) and moclobemide.* Addiction 2003;98(3):365–368. — https://onlinelibrary.wiley.com/doi/abs/10.1046/j.1360-0443.2003.00292.x
- Gonzalez, et al. *Delta-9-Tetrahydrocannabinol (THC) Before Bedtime: Feasibility and Mechanistic Pilot Study on Sleep and Cardiac Autonomic Activity.* Journal of Sleep Research 2026. — https://pubmed.ncbi.nlm.nih.gov/41692699/
- *The effects of cannabis on heart rate variability and well-being in young men.* 2010. — https://pubmed.ncbi.nlm.nih.gov/20191442/
- WHOOP. *Marijuana and Sleep: Effects on HRV and Heart Rate.* ⚠️ Vendor blog, undisclosed method — relay only. — https://www.whoop.com/us/en/thelocker/impact-of-marijuana-sleep-resting-heart-rate-hrv/
