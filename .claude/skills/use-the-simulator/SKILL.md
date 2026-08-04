---
name: use-the-simulator
description: See what the app actually looks like before claiming a UI change works. Use in any session running on the user's Mac when a change touches SwiftUI, a card's visibility, an empty state, navigation or a chart — and before reporting any of it as done.
---

# Using the iOS Simulator

**This works only in a session on the user's Mac.** A hosted session (Claude
Code on the web) is a Linux container with no Xcode, no `simctl` and no iOS SDK
— which is why CI is the only thing that compiles the app target there.
`scripts/simulator.sh` says so and exits rather than pretending.

## Why this exists, in one defect

On 2026-08-03 the **Nutrition and Metabolism cards shipped invisible**. Both
were in the build, registered in the engine, and filtered off the Insights tab
by `InsightResult.isWorthShowing` — they had no data, and a card with no number
and no unmet requirement is not shown. Every test passed, CI was green, the
deploy installed. The user opened the app, could not find two features they had
asked for, and told us.

**One `simulator.sh run` would have caught it in seconds**, because the
simulator's empty state is exactly the state that defect lived in.

## The loop

```bash
./scripts/simulator.sh doctor    # first time in a session: what's installed
./scripts/simulator.sh run       # build, boot, install, launch
./scripts/simulator.sh shot      # screenshot → build/simulator-shots/<sha>-<time>.png
```

Then **Read the PNG** — the Read tool renders images, so you can look at it
rather than guess. `./scripts/simulator.sh logs 5` prints the app's own log
lines from the last five minutes, which is where `DiagnosticsLog` writes.

`./scripts/simulator.sh reset --yes` erases the simulator's data and puts the
next launch back at onboarding. That is the only way to check the first-run
experience, and it is destructive, so it asks.

## What it can and cannot answer

**It can settle**, and these are real questions this project has got wrong:

- whether a card appears at all, and what it says when it has nothing;
- navigation, tab placement, the `+` menu and every input sheet;
- onboarding and the launch screen;
- layout, truncation, and whether a control is reachable.

**It cannot settle anything needing real data.** The Health app does not ship on
the simulator, so HealthKit returns nothing and every card renders empty. A
simulator screenshot proves nothing about a chart with data in it, a reference
band, a scrub read-out, the substance shading, the camera, LiDAR, or the ring
and the scale. **Those still need the phone**, and saying otherwise is the
"a comment describing behaviour is not evidence of it" trap one layer out.

## It does not replace the gate

Order, unchanged:

1. `./scripts/verify.sh --tests` — the gate, before every push. Still mandatory.
2. The simulator — *what the reader sees*. A different question, not a stronger
   version of the same one.
3. Push to `main`, `./scripts/ci-status.sh --wait`, then
   `./scripts/deploy-status.sh --wait`.

A Mac session can also run the app-target build directly
(`xcodebuild build -project HealthInsights.xcodeproj -scheme HealthInsights
-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`), which catches the
SwiftUI and HealthKit compile errors a hosted session can only learn from CI.
**Do that before pushing** — it is the one advantage a Mac session has over the
gate, and this session has shipped a red `main` for want of it.

## Reporting what you saw

Say what you looked at and what you could not. *"Nutrition and Metabolism both
appear on Insights with their empty copy — screenshot at build/simulator-shots/
bd4f049-141203.png. The charts are untested: the simulator has no health data."*

Never describe a screen you did not screenshot.
