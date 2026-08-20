# Contributing

Changes land on `main` via pull request, not direct push — for the
maintainer as much as for anyone else.

How you get a branch in front of a PR depends on whether you have write
access to the upstream repo. Pick the route that matches:

- **No write access** (almost everyone) → [Route A: fork](#route-a-fork)
- **Write access** (maintainers) → [Route B: branch directly](#route-b-branch-directly)
- Already cloned instead of forking? → [If you cloned instead of forking](#if-you-cloned-instead-of-forking)

## Route A: fork

Without write access you cannot push a branch to upstream at all — the
push is rejected. Fork instead. A fork is what makes GitHub accept a pull
request from one repo into another, so this is not busywork.

1. **Fork** the upstream repo to your own account/org (once).
2. **Clone your fork**, and add the upstream repo as a second remote:
   ```
   git remote add upstream <upstream-repo-url>
   ```
   Your fork stays `origin`; `upstream` is read-mostly (fetch/pull only).
3. **Branch** off an up-to-date `main` for each change:
   ```
   git fetch upstream
   git switch -c my-change upstream/main
   ```
4. **Push the branch to your fork**, not upstream:
   ```
   git push -u origin my-change
   ```
5. **Open the PR against upstream's `main`**:
   ```
   gh pr create --repo <owner>/<repo> --base main --head <your-account>:my-change
   ```
   (If you've run `gh repo set-default <owner>/<repo>` in the clone, `gh
   pr create` will target upstream automatically.)
6. Once merged, sync your fork's `main` back up before starting the next
   branch:
   ```
   git switch main
   git fetch upstream
   git merge --ff-only upstream/main
   git push origin main
   ```

## Route B: branch directly

With write access, skip the fork. Push the branch to the upstream repo
and open the PR within it — `--head` is a plain branch name, with no
account prefix, because there is only one repo involved:

```
git switch -c my-change main
git push -u origin my-change
gh pr create --repo <owner>/<repo> --base main --head my-change
```

Protecting `main` does not prevent this. Branch protection applies to the
branches its rules name, so a rule on `main` stops pushes to `main` — it
has never stopped you pushing `my-change`. The PR requirement is about
what merges into `main`, not about where feature branches live.

Two things to keep in mind on this route. The branch is visible in the
upstream repo the moment you push, so on a public repo treat the push
itself as publication and check the diff before it, not after. And you
lose the fork's accidental safety net: on Route A a mistake lands in your
own repo first.

## If you cloned instead of forking

Cloning and forking produce identical-looking local checkouts, but only a
fork is registered with GitHub as related to upstream. Push a branch to a
plain clone and the PR will be refused, because GitHub sees two unrelated
repos.

Check which you have:

```
gh repo view <your-account>/<repo> --json isFork,parent
```

`"isFork": false` with `"parent": null` means it is a clone, not a fork.
To fix it, create a real fork and push the branch there:

```
gh repo fork <owner>/<repo> --clone=false
git remote set-url origin <your-fork-url>
git push -u origin my-change
```

If your clone-based repo already occupies the name the fork wants, either
give the fork another name with `--fork-name`, or rename/remove the old
repo first.

## Same hygiene rules apply to PRs

This repo's core discipline — see `CLAUDE.md` and the README's "Repo
hygiene for forks" section — extends to every branch, commit, and PR
description: no real hostnames, usernames, or service/container whitelist
entries in anything tracked or in PR text. Keep `.env` and
`remote/claude-maint` out of every commit; they're gitignored for exactly
this reason.

Worth an explicit scan before you push a branch to a public repo, since a
push cannot be taken back:

```
git diff upstream/main...HEAD
git log upstream/main..HEAD --format='%s%n%b'
```

## Never run the install scripts in a shared/hosted session

`install-local.sh` and `install-remote.sh` configure real SSH connectivity
and passwordless sudo. Reviewing or editing their code in a PR is fine;
running them is only ever done from a private, locally authenticated
terminal or agent session against a host you control. See the warning at
the top of `README.md`.
