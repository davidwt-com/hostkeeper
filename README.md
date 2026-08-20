# hostkeeper

A template for Claude-Code-driven (or any agent-driven), SSH-multiplexed
maintenance of a remote host. One `.env` holds everything host-specific;
root access on the remote host goes through a single, explicit-whitelist
wrapper script — never a raw passwordless `sudo`.

## Prerequisites

**Local:** `bash`, `ssh`, `scp`, and an agent/terminal environment you
fully control.

**Remote:** `sudo`, `tmux`, a mail transport agent providing a mail
queue/mbox (only needed for the mail-related checks), `docker`/`docker
compose` (only if your own wrapper customization uses the docker-related
actions).

## ⚠️ Security warning — read before running anything

**Never run `install-local.sh`, `install-remote.sh`, or paste this
repository's contents into a public, shared, hosted, or multi-tenant
LLM/agent session.** These scripts configure SSH connectivity and
passwordless sudo access to a real server — treat that authority the same
as an SSH private key. Only run this from a private, locally authenticated
terminal or agent session you control, using your own SSH keys.

`.claude/settings.json` denies Claude Code from ever running
`install-remote.sh` or touching sudoers/`authorized_keys`/key-generation
commands, regardless of confirmation — but that only binds Claude Code.
There is no way for this repo to detect or block other agent frameworks or
hosted assistants from doing something unsafe with it. Outside Claude
Code, this warning is the entire control.

## Quickstart

1. `./install-local.sh` — creates `.env`, checks/prompts for the four
   required values, verifies (or helps you add) the SSH `Host` entry, and
   stages `remote/claude-maint` from the template if you don't have one
   yet.
2. Edit `remote/claude-maint`'s `ALLOWED_SERVICES` / `ALLOWED_CONTAINERS` /
   `COMPOSE_PROJECTS` for your host. This file is gitignored — it's yours,
   never committed.
3. `scp remote/claude-maint remote/install-remote.sh <your-alias>:~/`
4. `ssh <your-alias>`, then on the host: `sudo ./install-remote.sh
   <your-remote-username>` — one-time bootstrap, installs the wrapper and
   a narrowly-scoped sudoers drop-in.
5. Back on your machine: `./verify-install.sh` — read-only end-to-end
   check that everything above actually worked.
6. `./check.sh` for day-to-day use.

## File layout

| Path | Purpose |
|---|---|
| `.env` / `.env.sample` | Host-specific config (gitignored / template) |
| `ssh-lib.sh` | Shared multiplexed-SSH helpers |
| `connect.sh` | Attach to (or create) a persistent remote tmux session |
| `check.sh` / `check-detailed.sh` | Read-only health snapshots |
| `mark-mail-read.sh` | Mark the remote mailbox as read, non-interactively |
| `install-local.sh` | Local prep |
| `verify-install.sh` | Post-install, end-to-end validation |
| `remote/claude-maint` / `.sample` | The root wrapper (gitignored / template) |
| `remote/claude-maint.sudoers.sample` | Sudoers drop-in template |
| `remote/install-remote.sh` | One-time, human-run remote bootstrap |
| `CLAUDE.md` | Ground rules for any Claude Code session in this repo |
| `.claude/settings.json` | Baseline permission allow/deny list |

## `.env` reference

| Var | Meaning |
|---|---|
| `SSH_ALIAS` | Host entry in `~/.ssh/config` to connect through |
| `MAIL_USER` | Remote unix user whose mailbox the mail-related scripts read |
| `TMUX_SESSION` | Remote tmux session name `connect.sh` attaches to/creates |
| `REMOTE_MAINT_PATH` | Absolute path to the installed wrapper on the host |

> `REMOTE_MAINT_PATH` must match `WRAPPER_DEST` in `remote/install-remote.sh`
> if you change it from the default (`/usr/local/sbin/claude-maint`) — that
> script and `remote/claude-maint.sudoers.sample` both hardcode the install
> path, so the two need to agree or `sudo` calls will fail non-interactively.

## Day-to-day usage

- `./check.sh` — quick snapshot (uptime, disk, memory, reboot-required,
  failed units, hardening service status, unread mail count).
- `./check-detailed.sh` — superset: adds pending updates, top processes,
  listening ports, and container/compose status.
- `./connect.sh` — attach to a persistent remote tmux session for
  multi-step or long-running work.
- `./mark-mail-read.sh` — mark the whole mailbox read without the
  interactive `mail` REPL.

## Updating the wrapper

Edit `remote/claude-maint` locally, stage it in the remote home
directory, then install it yourself. Staging is safe to automate — the
copy lands in your own home as an ordinary file and is inert until
installed:

```bash
source ./ssh-lib.sh && hostkeeper_ssh "cat > ~/claude-maint.new" < remote/claude-maint
```

The install is not. Run it yourself, in your own terminal:

```bash
source .env && ssh -t "$SSH_ALIAS" \
  "sudo install -o root -g root -m 755 ~/claude-maint.new '$REMOTE_MAINT_PATH' \
   && rm -f ~/claude-maint.new"
```

Both commands are host-agnostic: `SSH_ALIAS` and `REMOTE_MAINT_PATH`
come from `.env`, and `~` expands to whatever the SSH user's home is.
The `.new` suffix keeps the inbound copy visibly distinct from the
installed wrapper, and the `rm` stops a stale one lingering in the home
directory looking authoritative.

Verify afterwards by comparing checksums — they must match:

```bash
sha256sum remote/claude-maint
source ./ssh-lib.sh && hostkeeper_ssh "sha256sum '$REMOTE_MAINT_PATH'"
```

The install step stays human-run and passworded on purpose — never
automated, and never granted NOPASSWD — so an agent session can never
silently change what the wrapper is allowed to do. Granting NOPASSWD on
the command that writes the wrapper would hand back exactly the
unrestricted root the whitelist exists to prevent.

## Security model

- No NOPASSWD passthrough: `claude-maint` is an explicit whitelist with no
  `eval` and no `sudo "$@"`. The NOPASSWD sudoers grant covers exactly one
  binary — every other `sudo` invocation on the host still needs a
  password an agent doesn't have.
- The install step is intentionally passworded and human-run, both for
  first bootstrap (`install-remote.sh`) and every later update.
- `.env` and the real `remote/claude-maint` are gitignored and never
  committed.
- Nothing in this workflow writes secrets, keys, or credentials to the
  remote host.

## Repo hygiene for forks

If you fork this, keep the same discipline: your own `.env` and
`remote/claude-maint` stay gitignored, and your real hostnames, usernames,
and service/container whitelists shouldn't end up in your fork's tracked
files, commit messages, or PR descriptions either.

`main` on the upstream repo is protected — changes land via pull request
from a fork branch, not direct push. See `CONTRIBUTING.md` for the
fork → branch → PR flow.

## Claude Code

`.claude/settings.json` ships a small `allow` list for this repo's own
entry-point scripts (so routine commands like `./check.sh` don't prompt
every time) plus `deny` rules blocking `install-remote.sh` and anything
touching sudoers, `authorized_keys`, or key/user/password management,
regardless of confirmation. `CLAUDE.md` carries the full ground rules for
any Claude Code session working in this repo.

Once you've used the repo for a while, Claude Code's built-in
permission-prompt-reduction tooling can scan your own session transcripts
and propose further `allow` entries for commands that keep recurring — a
better long-term fit than hand-maintaining a large allowlist up front.

## License

MIT — see `LICENSE`.
