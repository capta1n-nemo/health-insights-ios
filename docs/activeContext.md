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

## Lesson from this session: suspect your own precheck first

Four deploy runs "failed to find the phone." The cause was not the phone. The
install step's guard demanded `connectionProperties.tunnelState == "connected"`
and refused anything else — but a paired, perfectly installable iPhone commonly
reports `available (paired)`, and `devicectl` opens the tunnel on demand. The
guard was rejecting a working device.

What went wrong in the diagnosis is the part worth remembering: each failure
came with a plausible user-side explanation (phone locked, VPN on, off Wi-Fi,
Xcode not signed in), and each one was accepted instead of questioning the check
doing the rejecting. The user settled it by running `xcrun devicectl list
devices` themselves and pasting output showing the phone as `available
(paired)`. Fixed in `122d2c6`; run 36 installed successfully on the same phone,
same network, no VPN change.

Rule: when a self-written guard reports an environmental failure repeatedly,
verify the guard's premise against the raw tool output before asking the user to
change anything about their environment.

## Known gotcha: memory files may not auto-load

`CLAUDE.md` and `.claude/commands/handover.md` live in **this repo's** root
(`health-insights-ios`). If a session's working directory is a *different*
repo (e.g. `ripp3r`, with this one attached alongside), Claude Code may not
discover either — `/handover` comes back "Unknown command" and `CLAUDE.md`
isn't auto-read. Slash commands are also registered at session start, so a
newly-created one never works in the session that created it.

To get the intended behaviour, start the session with `health-insights-ios` as
the working directory. If that isn't possible, run the handover steps manually
(they're just: update this file + `progress.md`, then commit) and paste the
contents of `CLAUDE.md` at the start of a new chat.

## Immediate next steps

- **Deploy is working again** — run 36 (`122d2c6`) installed successfully to
  the pinned iPhone 16 Pro. See the guard-bug note below for why the preceding
  runs failed; it was not the phone.
- **On-device verification of the nine-part UI pass is still outstanding.** CI
  proves it compiles, not that it behaves. Walk: Heart Rate at `All` *and* `Y`
  (the squish bug was never `.all`-only), Weight's gap-broken line and weekly
  velocity, a multi-source metric's provenance badges and Inactive section,
  drag-to-scrub updating the breakdown, Height as a plain card, and blood
  pressure from all three entry points with the grounding count unchanged.
- The pre-approved AreaMark fallback (outlined min/max bands via two `LineMark`s
  rather than a filled `AreaMark`) shipped as the default — revisit only if the
  user wants filled bands and is willing to spend a compile-spike cycle
  confirming `AreaMark` is safe on this SDK.
