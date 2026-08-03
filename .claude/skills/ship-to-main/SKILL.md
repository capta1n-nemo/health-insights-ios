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
./scripts/ci-status.sh --wait      # does it compile?  0 passed / 1 failed / 2 none
./scripts/deploy-status.sh --wait    # is it on the phone? 0 installed / 1 failed / 2 none
./scripts/deploy-status.sh --errors  # on a red: signing/install lines, not a guess
```

**Both, and in that order.** They answer different questions and the second is
the one the user cares about. `ci.yml` runs on GitHub's runners; `deploy.yml`
runs on the user's own Mac and is the only thing that installs anything. Three
deploys in a row once failed on an unreachable iPhone while CI was green for all
three, and each was reported as "deployment triggered" — because nothing was
checking. A push is not an install.

Then report what `deploy-status.sh` actually said, and **end the turn**. If it
failed, **read `--errors` before naming a cause.** The phone is the usual
answer — unlock it, same Wi-Fi as the Mac, no VPN — but since the app gained an
App Group entitlement a deploy can also be refused at signing, and those two
need completely different fixes. Re-running the workflow installs the same
commit — no new push needed.
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

## Commit signing: removed. Do not raise it, do not re-enable it.

A `Stop` hook used to report every commit as "Unverified" and ask for two
`git config` commands and a `--amend --reset-author`. **It is gone** — the hook
registration was deleted from the launcher settings, the script was deleted, and
`commit.gpgsign` is off.

The user's instruction, on 2026-08-03, in their words: *"STOP TRYING TO SIGN
COMMITS I DONT CARE, remove from code and project that idea, stop suggesting
it."* Before that it had been settled once already, on 2026-07-31, and was
raised again in four consecutive replies in one session.

So: **do not mention signing, verification status, or amending for signature in
any reply.** If a settings sync ever restores that hook, delete it again and say
nothing. If some future tooling offers to sign, decline silently.

Why it was never worth a word anyway: the identity it asked for is already set,
no signing key exists in the container, and by the time it fires you have pushed
to `main` — so amending means force-pushing the branch the user's phone is
downstream of, orphaning the `refs/deploy/*` and `refs/ci/*` entries keyed to
those shas, and re-deploying byte-identical code.

## Reading CI

`./scripts/ci-status.sh [sha|--wait]` reads a git ref pushed by `ci.yml`'s
`record-status` job, and `./scripts/ci-status.sh --errors` reads the compile
errors from `refs/ci/errors/<sha>`. **Never use the GitHub Actions API for
either** — its smallest run listing is ~450 KB, over 100K tokens, and checking
six times in a session costs more than the work being verified. The errors ref
has existed the whole time; on 2026-08-02 a session paid the 446 KB anyway to
read one line of it.

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
