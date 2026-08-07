# Watch capture setup — daylight, UV, falls

**Setup instructions for the reader.** Every claim is sourced; anything Apple
does not state is marked ⚠️ unconfirmed rather than asserted.
Backlog §B5 #37. Every claim below is sourced; anything Apple does not state is
marked ⚠️ **unconfirmed** rather than asserted.

## Time in Daylight — turn this on, it is the best of the three

The Apple Watch ambient light sensor estimates it automatically. iOS 17+ /
watchOS 10+. Cumulative time units.

⚠️ **There is a prerequisite nobody guesses**, and it is why this can read zero
on a worn watch:

> **Settings ▸ Privacy & Security ▸ Location Services ▸ System Services ▸
> Motion Calibration & Distance** — must be **on**.

Confirm it is recording: **Health app ▸ Search ▸ Other Data ▸ Time in
Daylight**. (Apple's current pages say **Search**; older ones say **Browse** —
same bottom-right tab, renamed around iOS 26.)

Opt-out lives at Watch ▸ Settings ▸ Privacy & Security ▸ Health ▸ Time in
Daylight, or iPhone ▸ Watch app ▸ My Watch ▸ Privacy.

⚠️ **Unconfirmed: which Watch models.** Apple publishes no model list. The
widely-repeated "SE 2nd gen, Series 6 and later" claim traces to no Apple
source. Apple's own page carries no model restriction — unlike Fall Detection's,
which is titled with one — so any watch on watchOS 10+ probably records it.
**Do not print a model list as fact.**

⚠️ **Unconfirmed: iPhone alone.** Every Apple description attributes it to the
Watch's ambient light sensor. Safe wording: an Apple Watch is required for
automatic recording.

## UV Exposure — leave it raw, nothing writes it

Type exists since iOS 9 and its value is a **UV index** (0–12, dimensionless
count), not a dose. But:

- No Apple Watch has ever had a UV sensor.
- Apple's dev doc carries no Apple-source note, unlike `numberOfTimesFallen`.
- UV appears nowhere in Apple's list of data its devices collect.

⚠️ This is a **documented absence, not a documented denial** — Apple never says
"we don't write this". Honest wording: *no Apple device writes UV Exposure; it
comes only from third-party apps, accessories, or by hand.*

**Recommendation: do not promote it to a `MetricType`.** A metric that can never
fill is a chart nobody asked for.

## Falls — two corrections to what we assumed

**1. Under 55 is not "off".** watchOS 8.1+ turns on **Fall Detection only during
workouts** automatically for ages 18–55. At 55+ it is fully on automatically.

To make it always-on: **Watch ▸ Settings ▸ SOS ▸ Fall Detection ▸ "Always on"**
(or iPhone ▸ Watch app ▸ My Watch ▸ Emergency SOS). The two options are named
exactly *"Always on"* and *"Only on during workouts"*.

Models: **Apple Watch SE and Series 4 and later** (includes Ultra).

⚠️ Apple's current Fall Detection page contains a sentence about *"Apple Watch
Ultra 3, or other models paired with iPhone 14 or later"* — that belongs to
**Emergency SOS via satellite** on the same page, **not** Fall Detection. Do not
repeat it as a requirement.

**2. ⚠️ The important one: a dismissed fall is never logged.**
`numberOfTimesFallen` is written only when the person **confirmed** the fall or
the system **escalated to emergency services**. Reply "I didn't fall" and
nothing is recorded.

**So a zero is not evidence of no falls**, and any card built on this must say
so. There is a Core Motion API that sees *all* fall events including dismissed
ones, but it needs an entitlement requested from Apple
(developer.apple.com/contact/request/fall-detection-api).

**Health app path: Search ▸ Other Data ▸ Number of Times Fallen** — **not**
Mobility. That was our wrong prior.

### Fall-adjacent, and worth knowing

`appleWalkingSteadinessEvent` is the only fall-**risk** category type — four
values (`initialLow`, `initialVeryLow`, `repeatLow`, `repeatVeryLow`). It fires
on gait scores, **never on an actual fall**; keep them distinct.
**Read-only — this app can never write it.**

`appleWalkingSteadiness` (0.0–1.0) records automatically on **iPhone 8+**, needs
the phone carried near the waist, needs **height set in Health** for accuracy,
and writes roughly **every 7 days**. Not recorded in Wheelchair mode. Lives
under **Mobility**. Also read-only.

## Granting this app read access

**Health app ▸ profile picture (upper right) ▸ Privacy ▸ Apps ▸ [this app]** —
toggle each data type. Or **Settings ▸ Health ▸ Data Access & Devices**.

Access is **per-type and per-direction** (read and write are separate grants).

⚠️ **A denied read is indistinguishable from no data** — HealthKit hides
read-denial deliberately, so the app can never detect a refused type. That is
precisely why this document has to exist: when something reads zero, the reader
needs a checklist, because the app cannot tell them.

When the app requests a *new* type, iOS re-prompts — and the sheet lists **all**
requested permissions, not just the new one, so it looks like a repeat ask.

## Sources

Apple developer docs for `timeInDaylight`, `uvExposure`, `numberOfTimesFallen`,
`appleWalkingSteadiness`, `appleWalkingSteadinessEvent`,
`requestAuthorization(toShare:read:)`; Apple Watch User Guide (Time in Daylight,
Manage Fall Detection); support.apple.com/en-us/108896 and /108779; Apple
Platform Security (protecting access to health data); Apple Newsroom June 2023.
