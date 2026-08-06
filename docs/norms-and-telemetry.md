# Why this app collects what it collects — the norm-building tenet

**This is a core tenet, set by the reader on 2026-08-06, and it governs design
decisions across the whole app. Read it before deciding not to collect
something.**

> *"for things that have no research, we are going to do the research and find
> the 'norms' ourselves. This is why we are building the app to record the stuff
> we are asking for. When we roll this app out to people, and lots of people
> start inputting their data, we will start collecting metrics on things like…
> meeting hours for a 28 year old male, we will now start to know what is
> normal, and what is not, or stress… So make sure that is a core tenet
> remembered, we are building this app so we can collect this telemetry, and
> start building these norms. If we haven't already, we need to build this into
> the export mechanism, all the data points so when we combine it all at a
> server-level later, we can build these baselines and norms and global
> trends."*

## What this changes about how decisions get made

The app has repeatedly refused to draw a band, a percentile or a "how you
compare" row because **no published norm exists** — for meeting hours, for a
pooled mental-health channel, for effort intensity, for a vendor's stress
composite. Every one of those refusals was correct **and every one is
temporary**. The absence of a norm is not a permanent property of the
quantity; it is a statement about what has been measured so far, and this app
is being built to measure it.

So the standing question changes from *"is there a published norm for this?"*
to **"is this quantity recorded in a form that could become a norm?"**

⚠️ **What does NOT change: the app still never dresses modelled as measured, and
still never shows a norm it does not have.** Collecting toward a future norm is
not permission to invent a present one. A card with no norm says so today and
gets a real one later — it does not get a plausible-looking one now.

## The design tension nobody should rediscover

**The telemetry that already exists is the wrong shape for this**, and that is
not a defect — it was built for a different job.

`InsightKit/Sources/InsightKit/Feedback/Feedback.swift` carries
`TelemetryEvent`, whose own doc comment says: *"There are no raw measurements
and no identifiers here by construction: only a coarse cohort, the model
version, a differentially-private rounded error (or a rating), and a coarse
week bucket."*

That is **accuracy telemetry**: it answers *"is model v2 better than v1 for
40-49 year old men?"* using a DP-noised **error percentage**. It cannot answer
*"what is a normal week of meeting hours for a 28-year-old man?"*, because
building a norm needs the **distribution of values**, and this event type
carries no values by design.

**So norm telemetry is a second, differently-shaped thing** — not an extension
of the first. Do not try to widen `TelemetryEvent`; it will end up doing
neither job honestly.

| | Accuracy telemetry (exists) | Norm telemetry (needed) |
| --- | --- | --- |
| Answers | is the model right | what is typical |
| Carries | signed error %, rating | the value itself, coarsened |
| Cohort | strata for comparison | strata for *the norm itself* |
| Privacy | DP noise on the error | needs its own analysis — see below |

## The rule for the export

**Every quantity the app holds or derives must reach the export**, because the
export is the only route from a phone to a server-side pool. A quantity that is
recomputable on-device is *not* therefore excludable: recomputability is a
property of the device that has the raw data, and the pool will not have it.

⚠️ **This reverses a call made earlier the same day.** Derived series were
excluded from the export on the reasoning that they are replayed from `samples`
so exporting them would be exporting a cache — see `exportKey(for:
.generatedInsights)`. That reasoning is sound for a *personal* export (restore,
inspect, hand back to a session) and **wrong for norm building**, where the
derived figures are exactly the ones with no published norm and therefore the
ones most worth pooling.

The two purposes want different files, and conflating them is how one of them
gets quietly broken:

- **Personal export** — everything, faithful, for the reader and for a session
  debugging with them. Already exists; `HealthDataExport`.
- **Norm contribution** — coarsened, cohort-stratified, no free text, no
  identifiers, opt-in. Does not exist yet.

## What must never go in the norm pool

These are not open questions; they follow from rules the app already holds.

1. **No free text, ever.** Calendar event titles and locations are the most
   identifying strings this app holds, which is why `exportKey(for:
   .calendarEvents)` deliberately emits nothing. Their *derived* quantities
   (meeting hours, formality, presence) carry no title and are exactly what the
   norm wants — so the calendar contributes without its text ever leaving.
2. **No credentials, no tokens.** The reader's own condition on the export.
3. **No raw dated series.** A per-day timeline is re-identifying even without a
   name; a pooled distribution is not. Contribute summaries, not histories.
4. **Nothing at all without opt-in.** Settings ▸ Data & model improvement
   already exists, is off by default, and states that nothing is sent in this
   build. That promise holds until the reader changes it.

## Open, and needing a decision before anything is sent

- **What statistic per person per period?** A median plus quantiles over a week
  is far more privacy-preserving than daily values and is sufficient to build a
  norm. Probably the right default.
- **The minimum cohort size before a norm is published back.** A "norm" from
  four people is worse than no norm — it is a plausible-looking number with no
  basis, which is the failure this app exists to avoid.
- **How a returned norm is labelled.** A norm built from this app's own users is
  not a published clinical reference and must never be drawn as one. It needs
  its own visual and verbal treatment, and its own sample size on the row —
  `AgeComparison`'s rule already applies: *the error figure is the most useful
  thing on the row.*
- **The DP budget for values**, which is a different analysis from the DP budget
  for errors and cannot be inherited from it.

## Where this is enforced

`docs/backlog.md` §G standing rules, and the `add-metric-type` /
`add-data-or-input` skills: a new quantity has to say how it reaches the export,
not merely how it reaches the Data tab.
