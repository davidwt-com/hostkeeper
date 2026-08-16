# hostkeeper — design spec

Date: 2026-08-16
Status: approved

## 1. Purpose

A generic, publishable pattern for Claude-Code-driven, SSH-multiplexed
maintenance of a remote host: one `.env` holds everything host-specific
(connection alias, mail user, session name, wrapper path); the wrapper
script (`claude-maint`) enforces an explicit action whitelist server-side
so the controlling agent never gets raw root; and CLAUDE.md encodes the
ground rules (confirm before anything destructive, no raw sudo, no secrets
to the remote host).

This is deliberately a *template* project: someone clones it, fills in
their own `.env` and their own `remote/claude-maint` whitelist, and neither
of those files is ever committed — to their fork or anyone else's.

## 2. Goals / non-goals

**Goals:**
- No secrets, hostnames, usernames, or service/container whitelists in any
  tracked file, in this repo or in anyone's fork of it.
- A generic, whitelist-based root wrapper (`claude-maint`) pattern, shipped
  as an empty template others customize per host.
- Two install scripts — one local, one remote — plus a post-install
  validator, so a new user can go from clone to verified working setup
  without guesswork.
- Clear documentation of the Claude Code side: what CLAUDE.md governs, what
  permissions make day-to-day use low-friction, and what's explicitly
  denied regardless of confirmation.
- An explicit, prominent warning against ever running the install/setup
  flow from a public, shared, or multi-tenant LLM/agent session.

**Non-goals:**
- Multi-host support in one checkout (single host per checkout — clone
  again for a second host).
- Automating the sudoers/install step from an agent — that stays a human-
  run, passworded action, both for initial bootstrap (`install-remote.sh`,
  run directly on the host by a human) and for updates (a human-run
  `sudo install ...`).
- This design doc does not describe anyone's specific deployment. Any
  values shown (aliases, usernames, service names) are illustrative
  placeholders only.

## 3. Directory layout

```
hostkeeper/
├── .env.sample                   # tracked — placeholders + comments
├── .env                          # gitignored — real values, never committed
├── .gitignore
├── LICENSE                       # MIT
├── README.md
├── CLAUDE.md                     # ground rules, env-driven, host-agnostic
├── install-local.sh              # local prep
├── verify-install.sh             # one-time post-install validation
├── ssh-lib.sh                    # multiplexed ssh helpers, reads .env
├── connect.sh
├── check.sh
├── check-detailed.sh
├── mark-mail-read.sh
├── .claude/
│   └── settings.json             # tracked — baseline permission allow/deny
└── remote/
    ├── install-remote.sh         # one-time human-run bootstrap (sudo), on host
    ├── claude-maint.sample       # tracked — generic wrapper template
    ├── claude-maint              # gitignored — real customized wrapper, never committed
    └── claude-maint.sudoers.sample  # tracked — sudoers drop-in template
```

## 4. `.env` / `.env.sample`

Variables, all consumed by `ssh-lib.sh` and the scripts that source it:

| Var | Meaning |
|---|---|
| `SSH_ALIAS` | Host entry in `~/.ssh/config` to connect through |
| `MAIL_USER` | Remote unix user whose mbox `check.sh`/`check-detailed.sh`/`mark-mail-read.sh` read |
| `TMUX_SESSION` | Remote tmux session name `connect.sh` attaches/creates |
| `REMOTE_MAINT_PATH` | Absolute path to the installed wrapper on the remote host |

`.env.sample` ships all four keys with **empty values** and a comment above
each explaining it. Empty is the unambiguous "needs a value" signal
`install-local.sh` checks for. `.gitignore` excludes `.env`.

## 5. `ssh-lib.sh`

Provides three functions, all reading `SSH_ALIAS` from `.env`:
`hostkeeper_ensure_session` (checks for an existing multiplexed control
socket, opens one if absent), `hostkeeper_ssh "<cmd>"` (runs a command over
the shared session), and `hostkeeper_ssh_tty "<cmd>"` (same, with a tty
allocated — needed for e.g. a `tmux attach`). Socket path is a repo-neutral
temp file (`/tmp/hostkeeper-ssh-%r@%h:%p.sock`), outside the repo and
outside `~/.ssh`, so it's pure runtime state.

`connect.sh`, `check.sh`, `check-detailed.sh`, and `mark-mail-read.sh` all
source `ssh-lib.sh` and call these functions instead of invoking `ssh`
directly.

## 6. `install-local.sh`

Idempotent — safe to re-run. Steps:

1. Verify `ssh` and `scp` are on `PATH`; fail with a clear message if not.
2. If `.env` doesn't exist, copy it from `.env.sample`.
3. For each var in `.env` that's still empty, prompt for a value and write
   it back into `.env`.
4. Check whether `SSH_ALIAS` already resolves: `ssh -G "$SSH_ALIAS"`. If it
   fails to resolve to a real `hostname`, prompt for Hostname, remote User,
   IdentityFile, and Port, show the exact `Host` block that will be
   appended to `~/.ssh/config`, and append it only after an explicit
   yes/no confirmation.
5. Run a live connectivity check (`ssh "$SSH_ALIAS" true`) and report
   success/failure plainly.
6. If `remote/claude-maint` doesn't exist yet, copy it from
   `remote/claude-maint.sample` and print a reminder to edit its
   whitelist arrays before bootstrapping the remote host.
7. Print the next steps (stage + run `remote/install-remote.sh`, then run
   `verify-install.sh`).

No sudo, no remote writes beyond the plain SSH connectivity check.

## 7. `remote/` contents

### `remote/claude-maint.sample`

A whitelist-only wrapper: explicit case-statement actions, each logged, no
passthrough (no `sudo "$@"`, no `eval`). Whitelists ship empty:

```bash
ALLOWED_SERVICES=()      # e.g. ALLOWED_SERVICES=(nginx docker)
ALLOWED_CONTAINERS=()    # e.g. ALLOWED_CONTAINERS=(web worker)
declare -A COMPOSE_PROJECTS=()   # e.g. COMPOSE_PROJECTS=([app]="/srv/app")
```

Actions that don't depend on a whitelist (`disk`, `auth-log`, `docker-ps`,
`docker-stats`, `apt-upgrade`, `ufw-status`, `fail2ban-status`,
`apparmor-status`, `mail-queue`) ship ready to use — they're already
host-agnostic.

### `remote/claude-maint.sudoers.sample`

```
# Installed by install-remote.sh to /etc/sudoers.d/claude-maint
# Replace __USER__ with the actual sudoer account before installing.
__USER__ ALL=(root) NOPASSWD: /usr/local/sbin/claude-maint
```

The NOPASSWD grant is scoped to exactly one binary. Any other `sudo`
invocation on the host still prompts for a password an agent doesn't
have — that scoping, not any client-side setting, is the actual backstop
against an agent (or a compromised session) doing anything beyond the
wrapper's whitelist.

### `remote/install-remote.sh`

Run by a **human**, directly on the target host, with `sudo` — never
invoked by an agent. Usage: `sudo ./install-remote.sh <username>`.

1. Confirm running as root; confirm a username argument was given.
2. Install `./claude-maint` (staged alongside this script) to
   `/usr/local/sbin/claude-maint`: `chown root:root`, `chmod 755`.
3. Render `claude-maint.sudoers.sample` with `__USER__` replaced, validate
   with `visudo -c -f <tempfile>`, install to `/etc/sudoers.d/claude-maint`
   at `chmod 440`. Abort (no install) if validation fails.
4. `touch /var/log/claude-maint.log` with appropriate ownership.
5. Print a summary of what was installed and where.

Ongoing wrapper updates keep a human-run workflow: edit
`remote/claude-maint` locally → `scp` to the remote home directory → user
runs `sudo install -o root -g root -m 755 ~/claude-maint <path>` themselves.

## 8. `verify-install.sh`

Root-level, run manually after both install scripts have completed.
Read-only end-to-end smoke test; prints pass/fail per check plus a summary;
non-zero exit if anything fails.

1. `.env` present and populated.
2. SSH alias resolves (`ssh -G`).
3. Fresh connection works (`hostkeeper_ssh true`).
4. Control socket is actually reused (`ssh -O check` reports master
   running right after step 3 — proves multiplexing is active, not just
   that ssh works).
5. Wrapper installed correctly (`root:root`, mode `755`).
6. Sudoers drop-in active and passwordless: `sudo -n <wrapper> disk`
   succeeds non-interactively (`-n` fails fast rather than hang if a
   password would be required).
7. A second whitelisted action round-trips (`sudo <wrapper> mail-queue`).
8. `check.sh` runs clean (exit 0, non-empty output).
9. The mail unread-count logic runs without error against `/var/mail/$MAIL_USER`.

## 9. Claude Code permissions, and the public-LLM warning

### Tracked baseline: `.claude/settings.json`

```json
{
  "permissions": {
    "allow": [
      "Bash(./check.sh)",
      "Bash(./check-detailed.sh)",
      "Bash(./mark-mail-read.sh)",
      "Bash(./install-local.sh)",
      "Bash(./verify-install.sh)",
      "Bash(./connect.sh)"
    ],
    "deny": [
      "Bash(*install-remote.sh*)",
      "Bash(*visudo*)",
      "Bash(*/etc/sudoers*)",
      "Bash(*authorized_keys*)",
      "Bash(*ssh-keygen*)",
      "Bash(*useradd*)",
      "Bash(*passwd*)"
    ]
  }
}
```

The `allow` list pre-approves running the repo's own read-only/gated entry
points — it does not pre-approve what a script does internally, and it
does not weaken any CLAUDE.md confirmation rule for ad hoc commands.

The `deny` list is defense-in-depth, enforced regardless of confirmation:
`install-remote.sh` is denied outright (it's designed to be run by a human
on the host directly, never by an agent), and the sensitive tokens
(`visudo`, sudoers, `authorized_keys`, key generation, user/password
management) are denied everywhere they'd appear in a Bash command — local
or embedded in a remote command string. This is **defense-in-depth, not a
guarantee**: a remote command is an opaque string to local pattern
matching, and a sufficiently different phrasing could slip past a glob.
The reliable backstop stays the sudoers scoping in §7 — the wrapper is the
only thing that can run without a password, and it can't do anything
outside its own whitelist.

`.claude/settings.local.json` (personal, machine-specific, gitignored) is
where a user's own broader allowances accumulate — never shipped by the
project.

### Public-LLM warning

Stated prominently in both README.md and the top of CLAUDE.md:

> **Never run `install-local.sh`, `install-remote.sh`, or paste this
> repository's contents into a public, shared, hosted, or multi-tenant
> LLM/agent session.** These scripts configure SSH connectivity and
> passwordless sudo access to a real server — treat that authority the
> same as an SSH private key. Only run this from a private, locally
> authenticated terminal or agent session you control, using your own SSH
> keys.
>
> The `deny` rules above only bind Claude Code, and only for the specific
> patterns listed. There is no mechanism in this repo that can detect or
> block *other* agent frameworks, hosted assistants, or copy-pasted
> instructions from doing something unsafe — for anything outside Claude
> Code, this warning is the entire control. Don't rely on tooling to catch
> what a shared/public session shouldn't be doing in the first place.

### Recommended follow-up

README notes, as an optional later step once the setup is in daily use,
that Claude Code's built-in permission-prompt-reduction tooling can scan a
user's own session transcripts and propose additional `allow` entries for
commands that keep recurring — a better long-term fit than hand-maintaining
a large allowlist up front.

### Prerequisites

- Local: `bash`, `ssh`, `scp`, an agent/terminal environment the user
  fully controls.
- Remote: `sudo`, `tmux`, a mail transport agent providing a queue/mbox
  (only if using the mail-related checks), `docker`/`docker compose` only
  if the customized wrapper uses the docker-related actions.

## 10. README.md outline

1. What this is / who it's for.
2. Prerequisites.
3. **Security warning** (public-LLM warning, from §9) — placed early,
   before the quickstart.
4. Quickstart: `install-local.sh` → edit `remote/claude-maint` whitelist →
   stage + run `install-remote.sh` on the host → `verify-install.sh` →
   `check.sh`.
5. File layout table (mirrors §3).
6. `.env` variable reference (mirrors §4 table).
7. Day-to-day usage.
8. Updating the wrapper (stage → scp → human-run passworded install).
9. Security model: no NOPASSWD passthrough, wrapper is an explicit
   whitelist with no `eval`, install step is intentionally passworded and
   human-run, `.env`/real `claude-maint` never committed.
10. **Repo hygiene for forks**: if you fork this, your own `.env` and
    `remote/claude-maint` stay gitignored the same way — don't commit your
    real hostnames, usernames, or service/container whitelists back into
    your fork's tracked files, commit messages, or PR descriptions either.
11. Claude Code section (from §9): baseline `settings.json`, deny rules,
    permission-prompt-reduction follow-up.
12. License note (MIT).

## 11. CLAUDE.md

Ground rules stay the same in substance (read before write, confirm before
anything destructive, all root access through the wrapper only, no secrets
to the remote host, don't touch auth config without explicit approval) —
they're already host-agnostic. Two additions: the public-LLM warning from
§9, placed at the top, and a Connection section describing `SSH_ALIAS`
(from `.env`) and the `hostkeeper_ssh`/`hostkeeper_ssh_tty` helpers rather
than any specific alias name.

## 12. Adoption notes (generic)

Turning an existing ad hoc "I ssh into my server and run commands by hand"
setup into this structure is a mechanical process, not specific to any one
deployment: move whatever's currently hardcoded (connection alias, remote
username, session name, wrapper path) into `.env`; move any existing
privileged wrapper script's real whitelist into the gitignored
`remote/claude-maint`, leaving only the empty-array template tracked;
double check no tracked file still contains a real hostname, username, or
service/container name; then run `verify-install.sh` to confirm nothing
broke in the move.

## 13. Acceptance criteria

- `verify-install.sh` passes all checks against a real, already-bootstrapped
  target host.
- `check.sh` / `check-detailed.sh` / `connect.sh` / `mark-mail-read.sh`
  work unchanged in behavior, driven by `.env` instead of hardcoded values.
- No secrets, hostnames, usernames, or the real service/container
  whitelist appear in any tracked (non-gitignored) file.
- A fresh clone, with no prior `.env`, can reach a working state by
  following the README quickstart alone.
