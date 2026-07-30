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
and fails loudly — rather than guessing — when:
- the pinned identifier isn't in the paired-devices list at all (phone was
  reset/replaced — update the identifier), or
- it's paired but its `tunnelState` isn't `connected` (phone locked, off
  Wi-Fi, on a VPN that routes it off the local subnet, or just asleep).

**A VPN on the phone is a common false alarm**: it changes the phone's
effective network path so the Mac's local peer-to-peer discovery can't reach
it, even though the phone shows as "connected to Wi-Fi." Disable VPN on the
phone before deploying.

## CI vs. deploy

- `ci.yml`: runs on every push — `cd InsightKit && swift test`, then
  `xcodebuild build ... CODE_SIGNING_ALLOWED=NO` (no signing, no device
  install — pure compile-and-test gate).
- `deploy.yml`: runs on push to `main` (or manual dispatch) — signs, builds,
  and installs to the pinned phone. This is the one that needs the phone
  reachable; CI does not.

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

## Verifying a deploy

`Settings ▸ About` in the app shows the build number and commit it was built
from (stamped into `Info.plist` by the deploy workflow), so after any deploy
you can confirm the phone actually picked up the expected commit rather than
trusting that the workflow merely *ran*.
