# Deployment

## Self-hosted Mac runner

CI and deploy both run on a self-hosted macOS GitHub Actions runner (the
user's own Mac), registered as `runs-on: self-hosted` in
`.github/workflows/ci.yml` and `.github/workflows/deploy.yml`. No macOS cloud
runners are used.

Two one-time setup requirements on that Mac, both independent of anything in
this repo:
- Xcode signed in with the developer's Apple ID once (Signing & Capabilities
  → Automatically manage signing), so a development certificate exists in the
  login keychain for `xcodebuild` to use.
- The target iPhone paired over Wi-Fi (Xcode ▸ Window ▸ Devices and
  Simulators ▸ "Connect via network"), so `devicectl` can reach it without a
  cable.

### Re-running a deploy: use `--fresh`

The verdict ref is keyed on the sha alone, so a **re-run of a commit that
already has a verdict** — which is every retry that doesn't involve a new push —
leaves the old ref in place. `./scripts/deploy-status.sh --wait` finds it
immediately and reports a failure that has not happened yet. `--fresh`
baselines whatever is recorded and waits for it to *change*.

Found on 2026-08-02 by believing the stale answer for a round.

### The share-sheet action extension is parked, and this is why

`ShotsyImportAction` was built and reverted on 2026-08-02 (`aaf185c`, reverted
in the commit after `74c4b44`). It is a clean revert — `git cherry-pick aaf185c`
brings the whole thing back — and it is parked on **signing**, not on code. CI
was green for it, because CI builds with `CODE_SIGNING_ALLOWED=NO`.

The deploy Mac, verbatim:

```
No profiles for 'com.jasonsalway.healthinsights.ShotsyImportAction' were found
Provisioning profile "iOS Team Provisioning Profile: com.jasonsalway.healthinsights"
  doesn't include the App Groups capability
No Accounts: Add a new account in Accounts settings
```

Two prerequisites, in order:

1. **An Xcode account on the runner Mac.** The "No Accounts" line is why
   `-allowProvisioningUpdates` could not mint a profile for the new bundle id.
   The runner is a background service; Xcode ▸ Settings ▸ Accounts has to be
   signed in as the user the runner runs as.
2. **An Apple Developer Program membership.** App Groups is not among the
   capabilities a free personal team can sign, and an extension has **no other
   way** to hand a file to its containing app — it runs in its own sandbox, and
   84 KB of JSON does not fit in a URL. There is no version of this feature that
   avoids the entitlement.

**Why it was reverted rather than left on `main`:** it turned a deploy *install*
failure into a deploy *build* failure. An install failure means the phone missed
one update; a build failure means `main` stops reaching the phone at all, and
every later push inherits it. A red `main` is the one state this repo cannot sit
in, because `main` is the only route to the device.

Nothing else depends on the group. The top-row share sheet
(`CFBundleDocumentTypes` + `UTImportedTypeDeclarations`) imports files with no
entitlement at all and was never touched.

### Runner-keychain signing gotcha

If the Actions runner is installed as a background service (not run
interactively from Terminal), `codesign` can fail with
`errSecInternalComponent` because the runner process can't reach the login
keychain's private key. `deploy.yml` unlocks the keychain and adds `codesign`
to the signing key's partition list when a `KEYCHAIN_PASSWORD` repo secret is
set; without it, the workaround is running the runner interactively
(`sudo ./svc.sh stop` then `./run.sh` from Terminal while logged in).

## When a push does not reach the phone: run the doctor

```bash
./scripts/runner-doctor.sh          # ON THE MAC, not in a sandbox
```

**Read the refs before blaming the phone.** `deploy.yml` is `runs-on:
self-hosted`, so a push to `main` only installs if the runner on the Mac claims
the job. The distinction that matters:

| What you see | What it means |
| --- | --- |
| `refs/deploy/passed/<sha>` | Installed. This is the only thing that means installed. |
| `refs/deploy/failed/<sha>` | The job **ran** and failed — build, signing or device. Use `deploy-status.sh --errors`. |
| **No ref at all** | The job **never ran**. That is the runner, not the phone. |

On 2026-08-03 four commits sat unclaimed for hours while the phone was both
hotspotting the Mac *and* plugged in by cable. Neither was the problem, and
hours went into the network because "no verdict" was read as "cannot reach the
device". It is not — it is "nothing tried".

Two things worth knowing while travelling:

- **A hotspot is fine for the runner.** It makes an *outbound* long poll to
  GitHub, so nothing needs to reach the Mac from outside. A captive portal is
  the one exception.
- **A hotspot is fine for the phone too** — the phone *is* the network, so the
  Mac is on its subnet by construction. `devicectl` reporting the device as
  `disconnected` or `unavailable` is not a fault; it brings the tunnel up on
  demand during install.

## Wi-Fi deploy to the pinned iPhone

`deploy.yml`'s install step targets **one specific device by identifier**,
never auto-detected. Several phones can be paired to the same Mac (old
devices, test devices), and picking "whichever one is connected" risks
installing to the wrong phone silently. The identifier is set via the
`IPHONE_DEVICE_ID` env var (hardcoded default in the workflow, overridable via
a repo secret of the same name).

Before installing, the workflow checks `devicectl list devices --json-output`
and fails loudly — rather than guessing — only when the pinned identifier isn't
in the paired-devices list at all (phone was reset or replaced, so the
identifier needs updating). A `tunnelState` of `unavailable` logs a warning and
the install is attempted anyway.

**Do not tighten that check back to `tunnelState == "connected"`.** An earlier
version did, and it broke deploys for several runs: a paired iPhone routinely
reports `available (paired)` or `disconnected` while being entirely reachable —
`devicectl` brings the tunnel up on demand as part of the install. The strict
guard rejected working devices and sent us chasing phantom Wi-Fi and VPN
problems on a phone that was fine. `devicectl`'s own exit status is the source
of truth for reachability; the precheck exists only to catch an unpaired or
replaced device.

If an install genuinely does fail to reach the phone, the usual causes are a
locked phone, a VPN routing it off the Mac's local subnet, or the phone being
on a different network. But confirm the failure came from `devicectl` itself
before acting on any of those.

## The simulator, and which session can actually use it (2026-08-03)

The user installed the Claude Code app on their Mac. **That changes what can be
verified without the phone — but only for a session running there.**

**A hosted session cannot use it.** The web/remote container is Linux
(`uname -sm` → `Linux x86_64`), with no Xcode, no `xcrun`, no `simctl` and no
iOS SDK. That is also why CI is the only compiler for the app target here. A
session in the Mac app has the whole toolchain and can build, boot a simulator,
drive the app and take screenshots.

**So the split is now three ways, not two:**

| Where | What it can settle |
| --- | --- |
| This container (Linux) | InsightKit's maths and text, every lint, the full test suite. Nothing visual |
| CI (`macos-15`) | that the app target compiles. Nothing visual |
| **A session on the user's Mac** | **layout, navigation, empty states, every input sheet, onboarding, the launch screen, tab placement** — anything that does not need real health data |
| The phone (`deploy.yml`) | anything reading real data, the camera, LiDAR, the ring and the scale |

**What the simulator cannot answer, and it is the important half.** The Health
app does not ship on the simulator, so HealthKit returns nothing: every card
renders its *empty* state. That is genuinely useful — the empty states are real
work and have shipped wrong before — but a simulator screenshot proves nothing
about a chart with data in it, a reference band, a scrub read-out, or the
substance shading. Those still need the phone.

**Worth checking in a simulator before the next deploy** (all app-target work
landed 2026-08-03, none of it device-verified): the `+` menu on Insights and
Data and whether a toolbar item or a floating button is right; Settings ▸ Body
scans; the two new cards' layout in their empty states; and the blood-test
import screen now that the scanner button leads.

## CI vs. deploy

- `ci.yml`: runs on every push — `cd InsightKit && swift test`, then
  `xcodebuild build ... CODE_SIGNING_ALLOWED=NO` (no signing, no device
  install — pure compile-and-test gate).
- `deploy.yml`: runs on push to `main` (or manual dispatch) — signs, builds,
  and installs to the pinned phone. This is the one that needs the phone
  reachable; CI does not.

### `main` is the deploy trigger — so don't stop short of it

`deploy.yml` is `on: push: branches: [main]`. Nothing else installs anything.
A feature branch, however green, produces a CI run and no phone install; a pull
request left open produces exactly the same nothing. The intended shape of a
session is: **ask questions first, make the change, push to `main`, tell the user
the deploy is running.** See the no-pull-requests rule in `CLAUDE.md`, which
deliberately overrides the web harness's default branch-and-PR workflow.

One consequence worth knowing: because the trigger is any push to `main`, a
docs-only commit also builds and installs. That's cheap (incremental builds
reuse DerivedData, see below) and harmless, not something to work around.

## Incremental builds

The `xcodebuild` invocation in `deploy.yml` passes `-derivedDataPath build`,
pointing DerivedData at a repo-relative path that persists between runs on the
runner (each run checks out fresh sources into the same workspace, but doesn't
wipe `build/`). The build step invokes `xcodebuild ... build` (no `clean`), so
an unchanged or lightly-changed target reuses prior compilation output instead
of rebuilding from scratch — the difference between a multi-minute full build
and roughly 15–30 seconds for a small change. Force a clean build manually
(`rm -rf build` on the runner, or add `clean` back to that one invocation) if
DerivedData is ever suspected stale — mismatched incremental state is a classic
source of "works after a clean build" confusion.

## Agent sandbox setup (optional, but free)

Every Claude Code session gets a fresh container, so the Swift toolchain never
survives. Three layers cover this, weakest to strongest:

1. `CLAUDE.md` tells the session to run `./scripts/bootstrap-swift.sh` first.
   Depends on the instruction being read and followed.
2. **`./scripts/verify.sh --tests` installs the toolchain itself** if `swift` is
   missing. This is the one that actually holds — the gate self-heals, so a
   session that never read `CLAUDE.md` still ends up running the tests. Verified
   by deleting `/opt/swift` and re-running.
3. **The environment setup script** — best of all, because it costs no session
   time at all. If you paste this into the environment's setup script (Claude
   Code web → environment settings), Swift is already present at session start:

```bash
cd /home/user/health-insights-ios 2>/dev/null || cd "$(ls -d /home/user/*/ | head -1)"
./scripts/bootstrap-swift.sh || true
```

`|| true` because a failed toolchain download must never block the session —
CI is still the backstop. The script exits immediately when Swift is already
present, so it is safe to leave in place forever.

The download is ~780 MB and takes about two minutes. Doing it in setup moves
that off the session clock entirely.

## Verifying a deploy

`Settings ▸ About` in the app shows the build number and commit it was built
from (stamped into `Info.plist` by the deploy workflow), so after any deploy
you can confirm the phone actually picked up the expected commit rather than
trusting that the workflow merely *ran*.
