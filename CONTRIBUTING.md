# Contributing

`main` on the upstream repo is protected: changes land via pull request,
not direct push (this applies to the maintainer too — there's no admin
bypass). The flow is the standard fork-and-PR pattern:

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

## Same hygiene rules apply to PRs

This repo's core discipline — see `CLAUDE.md` and the README's "Repo
hygiene for forks" section — extends to every branch, commit, and PR
description: no real hostnames, usernames, or service/container whitelist
entries in anything tracked or in PR text. Keep `.env` and
`remote/claude-maint` out of every commit; they're gitignored for exactly
this reason.

## Never run the install scripts in a shared/hosted session

`install-local.sh` and `install-remote.sh` configure real SSH connectivity
and passwordless sudo. Reviewing or editing their code in a PR is fine;
running them is only ever done from a private, locally authenticated
terminal or agent session against a host you control. See the warning at
the top of `README.md`.
