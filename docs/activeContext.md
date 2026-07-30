# Active Context

_Updated by `/handover` at the end of a session. This file is a snapshot, not a
history — it describes where things stand right now, not everything that ever
happened._

## Current focus

Just landed: a nine-part UI/UX pass on the Vitals/Insights experience (provider
setup UX, chart correctness — the All/Y "squish" bug, source provenance
badges, gap-aware chart lines, real bucketing, active/inactive source
handling, timeframe/scrub-aware source breakdowns, per-category metric
layouts, and a full blood-pressure screen migration into the new
`MetricViewStrategy` system). Shipped as two pushes (model layer, then UI) per
`InsightKit`'s no-toolchain-in-sandbox constraint — everything is verified via
CI, never locally.

Also just landed: this memory/automation scaffold itself (`CLAUDE.md`,
`.claude/settings.json`, `/handover`, the four `docs/*.md` files, and
dropping `clean` from the deploy build step for faster incremental deploys).

## Recent architectural choices worth knowing

- **`MetricSubject`** (not raw `MetricType`) is now what a detail screen
  addresses, because blood pressure is inherently a systolic/diastolic pair.
  `MetricDetailView` keeps `init(metric:)` for backward compatibility, so
  existing call sites are untouched; new code should prefer
  `init(subject:)` when the subject might be blood pressure.
- **`ScrollableMetricChart`** now owns all pan/zoom/scrub/axis-scale logic for
  every chart in the app. `MultiSourceChart` and the blood-pressure chart both
  wrap it rather than each re-implementing scrolling. Any future chart type
  should do the same rather than growing its own copy.
- **Swift Charts `Chart3DContent` overload-resolution hazard**: on the current
  SDK, a `RuleMark`/`AreaMark`/`BarMark` chain built without an explicit
  `some ChartContent` return type can silently resolve to 3D chart content and
  lose modifiers like `.lineStyle`/`.annotation`. Always give mark-building
  helper functions an explicit `-> some ChartContent` return type. This has
  caused two separate CI failures this session — treat it as a known trap, not
  a one-off bug.
- **Never start a continuation line with `...`** in Swift — it parses as a
  standalone prefix `PartialRangeThrough`, not a continuation of the range
  expression above it. Also caused a CI failure this session.

## Immediate next steps

- Confirm the just-triggered deploy actually installs (device connectivity
  has been flaky this session — VPN and Wi-Fi/lock-state issues, unrelated to
  the app).
- On-device verification of the nine-part UI pass is still outstanding (CI only
  proves it compiles): Heart Rate at `All` and `Y`, a multi-source metric's
  active/inactive badges, drag-to-scrub, the Height static-attribute card, and
  all three blood-pressure entry points.
- The pre-approved AreaMark fallback (outlined min/max bands via two `LineMark`s
  rather than a filled `AreaMark`) shipped as the default — revisit only if the
  user wants filled bands and is willing to spend a compile-spike cycle
  confirming `AreaMark` is safe on this SDK.
