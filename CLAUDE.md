# hostkeeper

> **Never run `install-local.sh`, `install-remote.sh`, or paste this
> repository's contents into a public, shared, hosted, or multi-tenant
> LLM/agent session.** These scripts configure SSH connectivity and
> passwordless sudo access to a real server — treat that authority the
> same as an SSH private key. Only run this from a private, locally
> authenticated terminal or agent session you control, using your own SSH
> keys.
>
> The `deny` rules in `.claude/settings.json` only bind Claude Code, and
> only for the specific patterns listed there. There is no mechanism in
> this repo that can detect or block *other* agent frameworks, hosted
> assistants, or copy-pasted instructions from doing something unsafe —
> for anything outside Claude Code, this warning is the entire control.

This project exists to maintain a remote host over SSH. The agent runs
locally; no credentials or secrets of its own should ever be written to
the remote host.

## Connection

- `SSH_ALIAS` (from `.env`) is the `Host` entry in `~/.ssh/config` used for
  every connection — key auth, non-root sudoer user.
- `check.sh`, `check-detailed.sh`, `connect.sh`, and `mark-mail-read.sh`
  all source `ssh-lib.sh`, which reuses one multiplexed SSH connection
  (`ControlMaster`/`ControlPath`, socket under `/tmp`,
  `ControlPersist=10m`) instead of opening a fresh connection per command.
  It checks for an existing socket first (`ssh -O check`) and only opens a
  new master connection if none is found. This only changes the
  transport — every remote command behaves the same as a plain
  `ssh "$SSH_ALIAS" "..."` would.
- One-off command from a new script: source `./ssh-lib.sh` and call
  `hostkeeper_ssh "command"` (or `hostkeeper_ssh_tty "command"` when a tty
  is needed, e.g. for `tmux attach`).
- Persistent session (for anything multi-step or long-running):
  `./connect.sh` — attaches to (or creates) a tmux session (named by
  `TMUX_SESSION` in `.env`) on the remote host, so work survives
  disconnects.
- Quick status snapshot: `./check.sh`. Detailed: `./check-detailed.sh`.

## Ground rules

1. **Read before you write.** Run status/diagnostic commands first
   (`systemctl status`, `df -h`, `journalctl`, config file contents, etc.)
   and summarize what you find before proposing changes.
2. **Confirm before anything destructive or hard to reverse.** This includes,
   but isn't limited to: `rm -rf`, package removal, `systemctl stop/disable`
   on anything currently running, database drops/truncates, firewall rule
   changes, disk/partition operations, `reboot`/`shutdown`, editing
   `sshd_config` or `sudoers`, and any command touching `/etc`. State exactly
   what the command will do and wait for an explicit go-ahead — do not infer
   consent from the original request.
3. **Never construct raw `sudo` commands yourself on the remote host.** Any
   action needing root goes through the wrapper, invoked as:
   `sudo "$REMOTE_MAINT_PATH" <action> [args]` — always the full path and
   always via `sudo` (sudoers grants this one command NOPASSWD, but it must
   still be invoked through `sudo` to actually run as root; run without
   `sudo` it just fails). It currently supports:
   - `claude-maint status <service>`
   - `claude-maint restart <service>`
   - `claude-maint logs <service> [lines]`
   - `claude-maint disk`
   - `claude-maint ports`
   - `claude-maint auth-log [lines]`
   - `claude-maint docker-ps`
   - `claude-maint docker-logs <container> [lines]`
   - `claude-maint docker-restart <container>`
   - `claude-maint docker-stats`
   - `claude-maint docker-disk`
   - `claude-maint apt-upgrade`
   - `claude-maint cert-expiry <container>`
   - `claude-maint compose-ps <project>`
   - `claude-maint compose-logs <project> [service] [lines]`
   - `claude-maint compose-restart <project> [service]`
   - `claude-maint compose-images <project>`
   - `claude-maint compose-config <project>` (secret-bearing values masked)
   - `claude-maint compose-backup <project>`
   - `claude-maint compose-update <project> confirm`
   - `claude-maint ufw-status`
   - `claude-maint fail2ban-status`
   - `claude-maint apparmor-status`
   - `claude-maint mail-queue`

   `compose-update` rewrites what is running and takes a backup on the way
   through, so it is destructive by rule 2 — ask before every single run,
   and never pass `confirm` on the user's behalf without an explicit
   go-ahead for that specific run.

   `<service>` and `<container>` must be on the whitelists inside the
   script. `<project>` must be a key in the script's `COMPOSE_PROJECTS` map.
   If a task needs an action, service, or container that isn't listed, stop
   and tell the user what to add rather than finding a workaround — do not
   fall back to plain `sudo`, and do not ask to loosen the wrapper's
   whitelist mid-task.
4. **Never write secrets to the remote host.** No API keys, tokens, or
   credentials of any kind get created, echoed, or stored on the remote
   host as part of this workflow.
5. **Prefer small, verifiable steps** over long chained commands — easier
   to review, easier to roll back.
6. **Summarize, don't narrate every keystroke.** After a task, give a short
   summary of what changed and how to verify it, not a transcript.

## Out of scope

Don't install new SSH keys, add users, or change authentication
configuration on the remote host without explicit, specific approval each
time — this is security-sensitive infrastructure.

## Repo hygiene

`.env` and `remote/claude-maint` hold every host-specific fact (alias,
usernames, service/container whitelists) and are gitignored — never commit
them, and never let a specific hostname, username, or whitelist entry into
a commit message, PR description, or any other tracked file. This applies
to forks too, not just this checkout.
