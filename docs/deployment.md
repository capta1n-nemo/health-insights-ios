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

### The App Group, and the one thing that could break signing

`ShotsyImportAction` (the share sheet's bottom row, added 2026-08-02) needs
`com.apple.security.application-groups` on **both** the app and the extension —
an extension has no other way to hand bytes to its containing app. The group is
`group.com.jasonsalway.healthinsights`, declared in
`SharedInbox.appGroupIdentifier` and repeated in the two entitlements files.

**App Groups are not available to free personal development teams.** If a
deploy starts failing at the signing step and names that capability, that is
the cause and the fix is to remove the extension, not to work around it:

1. Drop the `ShotsyImportAction` target from `project.yml` and
   `HealthInsights.xcodeproj/project.pbxproj` (all the `AAAA…AA2x` objects).
2. Remove `com.apple.security.application-groups` from
   `Support/HealthInsights.entitlements`.

Nothing else depends on it. The top-row share sheet — `CFBundleDocumentTypes`
plus `UTImportedTypeDeclarations` — imports files with no entitlement at all
and keeps working.

CI cannot tell you about this: `xcodebuild` runs there with
`CODE_SIGNING_ALLOWED=NO`, so a green CI and a red deploy is the expected shape
of this particular failure.

### Runner-keychain signing gotcha

If the Actions runner is installed as a background service (not run
interactively from Terminal), `codesign` can fail with
`errSecInternalComponent` because the runner process can't reach the login
keychain's private key. `deploy.yml` unlocks the keychain and adds `codesign`
to the signing key's partition list when a `KEYCHAIN_PASSWORD` repo secret is
set; without it, the workaround is running the runner interactively
(`sudo ./svc.sh stop` then `./run.sh` from Terminal while logged in).

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
