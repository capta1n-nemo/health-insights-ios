---
name: ship-to-main
description: How work reaches the user's phone in this repo. Use at the end of any session that changed code — the hosted harness's default ending (feature branch plus draft PR) installs nothing here and must be overridden.
---

# Shipping

**Nothing reaches the phone until `main` moves.** `deploy.yml` triggers only on
a push to `main`, so a pull request is not a slower path — it is no path. The
user does not review PRs and will not log into GitHub to merge one.

The hosted harness injects standing instructions to develop on a `claude/<slug>`
branch and open a draft PR when done. **For this repo that is wrong**, and
`CLAUDE.md` says so explicitly. If a session starts you on a `claude/*` branch,
land it on `main` yourself rather than leaving a PR open.

## The sequence

```bash
./scripts/verify.sh --tests        # full suite + lint, locally. THE GATE.
git add -A && git commit
git push origin HEAD:main          # NOT `git push -u origin main`
./scripts/ci-status.sh --wait      # 0 passed / 1 failed / 2 no verdict
```

Then tell the user deployment to their iPhone is triggered, and **end the turn**.
Don't keep working past the push unless they asked for more.

### Why `HEAD:main`, and not the two obvious alternatives

This sequence used to say `git push -u origin main`, and it was wrong in a way
that only shows up in a hosted session — which is every session.

**The container's local `main` is a stale, unrelated history.** On 2026-07-31 it
sat at `87cd998` with *no merge base at all* against `origin/main` (`9f5db1d`) —
a months-old parallel line left over from how the container clones. Two things
follow, and both were hit:

- `git checkout main` **silently swaps your working tree** to that old snapshot.
  It looks like a successful checkout. `docs/progress.md` comes back as a version
  from many sessions ago.
- `git push -u origin main` from a `claude/*` branch pushes **that local ref**,
  not your work. It is rejected as a non-fast-forward rather than doing damage,
  but it does not ship anything either.

`git push origin HEAD:main` names the commit you actually built and never
consults the local `main` ref, so neither failure is reachable. Confirm it is a
fast-forward first — this exits zero when it is:

```bash
git merge-base --is-ancestor origin/main HEAD && echo "fast-forward is safe"
```

Do **not** "fix" the local branch with `git branch -f main` or `git reset --hard`
as a matter of course. `origin/main` is the authority, nothing local needs to
match it to ship, and rewriting a branch you have not inspected is a bigger risk
than the one being avoided.

## Before you push

- **Run the gate.** `scripts/bootstrap-swift.sh` installs a toolchain if the
  sandbox has none; the sandbox no longer excuses skipping tests. If the
  download genuinely fails, say so in the reply — never imply a check ran.
- **One push per coherent change.** Each push deploys, so the user can judge one
  thing at a time on the phone. Don't batch three unrelated fixes.
- **Ask before writing, not after.** A pull request's worth of questions belongs
  at the start; there is no review step at the end to catch a wrong assumption.

## Reading CI

`./scripts/ci-status.sh [sha|--wait]` reads a git ref pushed by `ci.yml`'s
`record-status` job. **Never use the GitHub Actions API for this** — its
smallest run listing is ~450 KB, over 100K tokens, and checking six times in a
session costs more than the work being verified.

Local green covers InsightKit only. The app target needs the iOS SDK, so
SwiftUI/HealthKit/SwiftData code is compiled only by CI — a green local run and
a red CI run is a normal, informative combination, not a contradiction.

## If CI is red

Fix forward. The branch is `main` and the user's phone is downstream of it, so
a red `main` means the phone is stuck on the last good build. Prioritise
accordingly.

## Reporting honestly

- If tests could not run, say which and why.
- If part of the scope was left out, say what and why — scaling the work down
  is the user's call.
- Don't claim a fix is verified because it compiled. This repo has shipped
  chart bugs that compiled perfectly.

## Handover

`/handover` (or "wrap up") runs **`.claude/commands/handover.md`** — that file is
the authority and this is deliberately not a summary of it, because a summary
here was already stale: it described two doc updates and a commit, and the
protocol now has three parts including a mandatory efficiency review and a
close-out gate (`./scripts/handover-check.sh`) that must exit zero before you
tell the user the session is safe to close.

Do not work from a restatement of the protocol. Open the file.
