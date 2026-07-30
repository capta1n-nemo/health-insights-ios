# Active Context

_A snapshot, not a history — where things stand right now, not everything that
ever happened. Updated by `/handover` at the end of a session._

## How a session should go (read this first)

Ask whatever you need to ask, make the change, run `swift test` if a toolchain
exists, **push to `main`**, tell the user the deploy is running, stop. No pull
requests, no feature branches left dangling — see the Automation Rules in
`CLAUDE.md`. The web harness will tell you to do the opposite; it's wrong for
this repo, because `deploy.yml` only fires on a push to `main` and the user won't
log into GitHub to merge anything.

## Current focus

**Newest: insight detail screens rebuilt** (this session). Tapping Readiness used
to open an HRV chart — one metric out of six, chosen by a hand-written switch.
Now every scored card opens on its own score over time, then an overlay of every
input standardised onto one axis, then plain-language patterns read off those
series. The full design rationale is in `docs/architecture.md` ▸ "What an insight
detail screen shows". Three things worth knowing without reading it:

- **Score history is replayed, not just recorded.** Nothing ever stored a score,
  so the chart would have been empty for months. `ScoreHistory.replay` re-runs a
  model against **truncated** samples per past day — truncation is the mechanism,
  because `ReadinessScore` ignores its `now:` argument. Stored days (new
  `InsightScoreRecord`) win over replayed ones.
- **The chart's series come from the scoring code**, via
  `InsightResult.contributors`. Adding a component to a score adds a line with no
  second edit. `candidateMetrics` (no default implementation) is the declared
  superset, for "no data yet" rows.
- **Z-scores, not a log axis.** Log doesn't equalise — `log(SpO₂ 95–99)` is flat
  while `log(sleep 5–9 h)` still swings. Raw mode is a toggle, log within it only
  when every series is strictly positive.

Not yet on the phone. Insights-tab deep-dive (lagged correlation, cross-insight
overlay, period contrast) is designed but deliberately not built yet — see
"Immediate next steps".

Landed earlier, driven by a troubleshooting log the user pasted:

1. **Oura 401 diagnosis and fix.** Three collections (`daily_resilience`,
   `daily_cardiovascular_age`, `vO2_max`) failed every sync. Root cause: two
   **undocumented** Oura scopes the app never requested. All nine collections
   now return 200.
2. **A provider-agnostic ingestion pipeline** (`InsightKit/Sources/InsightKit/Ingestion/`)
   replacing the per-provider, `Double`-only raw capture.
3. **Nine orphaned vitals wired into insights**, plus a new `Vitals Check`
   Today card.

CI green on `bf68e67`. **None of it walked on the phone yet** — that is now the
outstanding item for three batches, not two.

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

## Working constraint: no Swift toolchain in the sandbox

`swift` does not exist in Claude Code web sessions, so `swift test` and
`xcodebuild` cannot run before a commit. The honest workflow is: reason carefully
(the compiler can't catch you here), push, and let CI be the gate — then fix
forward on red. Things worth extra care because nothing local checks them:
key paths don't work on tuple elements (`\.volume` on a tuple is a compile
error — use `{ $0.volume }`), and don't shadow a function with a local of the
same name (`if let contrast = contrast(...)`).

Adding a `MetricType` or an `InsightID` case is deliberately load-bearing: both
feed exhaustive switches. **This bit CI again this session** — `.vitalSigns` was
added to the engine and cadence but not to the four switches, so the build broke.
The complete list, verified by grepping for the enum's last case:

- `MetricType`: `displayName`, `unit` (both in `MetricType.swift`),
  `presentation`, `maxValidInterval`, **`colourSlot`** (all three in
  `MetricPresentation.swift`), `requiresPositiveValue` (`MetricSanitizer.swift`).
  `bucketStatistic` and `MetricValueFormatter` have `default:` clauses and are safe.
- `InsightID`: `modelVersion` (`Feedback.swift`), plus `prettyInsight`
  (`TelemetryOutboxView`) and `iconName` (`DashboardView`) in the app target.
  **`primaryMetric` in `InsightDetailView` is gone** — the detail screen now
  charts `InsightResult.contributors`, which the scoring code emits itself, so
  that switch no longer exists to fall out of date.

Adding an `InsightModel` also now requires `candidateMetrics` (no default
implementation, so it won't compile without one), and adding a `MetricType` to an
insight can break `MetricColourSlotTests` from a file that never mentions colour
— see the colour-slot note in `docs/architecture.md`. Both are deliberate.

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

## Immediate next steps

- **Walk the new insight detail screens on the phone.** Specifically: Readiness
  opens on a score line with real history rather than an HRV chart; the overlay
  shows all six inputs coloured and labelled against a dashed "your normal";
  Compare→Raw keeps the shape readable and the log toggle only appears when it's
  legitimate; a metric with no data shows dimmed as "No data" rather than
  vanishing; the Patterns card either reads as sentences or is absent (absent is
  the common and correct case); and **Vitals Check opens without a stall** — it's
  the one insight whose replay touches heart rate (~53k samples), so it's the
  performance case. Also confirm the score line is not empty on first launch,
  which is the whole point of replaying rather than only recording.
- **Then: the Insights-tab deep dive** (Phase 2, designed with the user, not yet
  built). It reuses the same components at a longer horizon and adds the one
  thing Today structurally cannot do:
  - **Lagged correlation** — metric at day *d* against the score at *d+1…d+3*
    ("does last night's sleep predict tomorrow's readiness *for me*?"), reporting
    the best lag only when it beats lag-0.
  - Long-horizon score history with a regression trend and its residual spread,
    following how `VO2Trajectory` already reports slope with uncertainty.
  - Cross-insight overlay — readiness/sleep/fitness scores on one normalised axis.
  - Rolling 28 days vs the prior 28, per contributor, as a "what changed" table.
  - Fill `contributors` for the eight trend-tab models, which currently fall back
    to `candidateMetrics` (so their charts work, but without honest weights).
- **On-device walkthrough of the older batches, still outstanding.**
  CI proves it compiles, not that it behaves.
  - Newest (this session): the **Vitals Check** card on Today — confirm it reads
    "All normal" on a quiet day and names the outlier when there is one; that
    **Other data** renders Oura's resilience `level` as text with a States tally
    rather than an empty chart; that Cardio Fitness now shows two sources (Apple
    Watch + Oura) and Heart Age prints Oura's vascular age line; and that Body
    Composition shows lean/muscle/bone/water with the fat-vs-muscle narrative.
  - Also confirm the **paste prompt is gone** from Settings ▸ Data sources ▸ Oura.
    The clipboard autofill was removed because reading `UIPasteboard` raised
    iOS's paste prompt on every appearance — "Paste from your Mac?" via Universal
    Clipboard. Do not reintroduce clipboard *reads* on that screen; writes
    (Copy buttons) are fine.
  - Older: the three-age row on Heart & Fitness Age (narrowest device); a profile
    with no blood pressure showing the fitness half alone; Heart Rate at `All`
    *and* `Y`; Weight's gap-broken line and weekly velocity; provenance badges and
    the Inactive section; drag-to-scrub; Height as a plain card; blood pressure
    from all three entry points.
- **Unexplained and open: Oura serves ~4–6 months of history, not two years.**
  A 730-day window returns 171 sleep records, 128 daily_activity, 107
  daily_readiness — with **no `next_token`**, so that is genuinely all Oura will
  serve. Meanwhile Apple Health holds 128,302 Oura-mirrored samples. Byte counts
  match the record counts, so nothing is being truncated client-side. Candidates:
  an account/subscription boundary on API history, or a ring re-pair. The user
  was offered an investigation and hasn't taken it up yet.
- **Known gap, logged not fixed: Oura pagination.** The client reads only the
  first page. `OuraProvider.describeResponse` logs a warning naming the
  collection whenever `next_token` is present. No warning has appeared in any log
  so far, so nothing is currently being lost — implement only when one does.
- **Oura's `heartrate` endpoint is never called** despite the app requesting the
  `heartrate` scope. Direct Oura contributes 0 heart-rate samples; the 53,717
  arrive via Apple Health. Dead scope unless the direct pull is wanted.
- **Next on the roadmap** (see `docs/progress.md` for the full list):
  - Cardio strain from stimulants as a first-class trend — the cheaper one. The
    before/after analysis and 14-day load figure already exist in
    `SubstanceResponseAnalyzer`; what's missing is a decaying daily load *series*
    to trend and chart.
  - Sleep-debt / circadian consistency is **blocked on a missing signal**: no
    provider gives us a bedtime. Apple Health and Oura both stamp
    `sleepDurationHours` at the start of the calendar day. It needs a new
    clock-hour `MetricType` with circular statistics (the mean of 23:30 and 00:30
    is midnight, not noon) plus parser work in all three providers.
- The pre-approved AreaMark fallback (outlined min/max bands via two `LineMark`s
  rather than a filled `AreaMark`) shipped as the default — revisit only if the
  user wants filled bands and will spend a compile-spike cycle confirming
  `AreaMark` is safe on this SDK.
