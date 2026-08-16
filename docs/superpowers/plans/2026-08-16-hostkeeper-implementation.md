# hostkeeper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure this folder into hostkeeper — a generic, publishable
template for Claude-Code-driven, SSH-multiplexed remote host maintenance,
with all host-specific facts isolated to gitignored files.

**Architecture:** A local `.env` (gitignored) supplies every host-specific
value to a shared `ssh-lib.sh` (multiplexed SSH helpers) that the local
scripts (`check.sh`, `check-detailed.sh`, `connect.sh`, `mark-mail-read.sh`)
source. Root access on the remote host goes through one whitelist-only
wrapper (`remote/claude-maint`, gitignored — tracked template is
`remote/claude-maint.sample`), installed via a human-run, sudo bootstrap
script (`remote/install-remote.sh`) that also writes a narrowly-scoped
sudoers drop-in. `install-local.sh` handles local prep; `verify-install.sh`
is a read-only smoke test proving the whole chain works end to end.

**Tech Stack:** bash, ssh (ControlMaster multiplexing), sudo, systemd/apt
tooling on the remote side. No package manager, no test framework — bash
scripts are verified with `shellcheck -S warning` plus direct functional
runs (`bash -n` only for `.env.sample`, which isn't a standalone script —
shellcheck's unused-variable check produces false positives on it).

**Spec:** `docs/superpowers/specs/2026-08-16-hostkeeper-design.md`

## Global Constraints

- No secrets, hostnames, usernames, or service/container whitelists appear
  in any tracked (non-gitignored) file — not in scripts, not in docs, not
  in commit messages or PR descriptions. This applies to this repo and to
  anyone's fork of it.
- Single host per checkout — no multi-host config, no `--host` flags.
- `.env` holds exactly four variables: `SSH_ALIAS`, `MAIL_USER`,
  `TMUX_SESSION`, `REMOTE_MAINT_PATH`. `.env.sample` ships them all empty.
- `remote/claude-maint` (the real, customized wrapper) and `.env` are
  gitignored and never committed. `remote/claude-maint.sample` (empty
  whitelists) is the only tracked wrapper template.
- The wrapper (`claude-maint`) is never a passthrough: no `sudo "$@"`, no
  `eval`. Every action is an explicit, whitelisted case branch.
- `remote/install-remote.sh` is run by a human, directly on the target
  host, with `sudo` — never invoked by an agent. This is enforced both by
  documentation and by a `deny` rule in `.claude/settings.json`.
- The NOPASSWD sudoers grant is scoped to exactly one binary
  (`REMOTE_MAINT_PATH`). No other command is ever passwordless.
- License is MIT.
- Every script keeps `set -euo pipefail` except `verify-install.sh`, which
  intentionally omits `-e` so one failing check doesn't abort the rest (its
  `cd` therefore needs its own `|| exit 1` guard — `set -e` isn't there to
  catch it).
- Every script is checked with `shellcheck -S warning` (not `bash -n`) —
  confirmed clean at `warning` severity for the exact script content in
  this plan. `SC1091` (can't follow a sourced file), `SC2016` (single
  quotes don't expand), and `SC2029` (ssh argument expands client-side) are
  expected at `info` severity on the `hostkeeper_ssh` call sites — that's
  the intentional local/remote quoting split (see Task 4's caller
  scripts), not a bug; `-S warning` filters those out so a clean run means
  "no real issues," not "no output at all."

---

### Task 1: Repo scaffolding

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `remote/` (directory, populated by later tasks)
- Create: `.claude/` (directory, populated by Task 9)

**Interfaces:**
- Produces: the `.gitignore` patterns every later task relies on to keep
  `.env` and `remote/claude-maint` out of git.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Host-specific config — never commit.
.env
remote/claude-maint

# Personal / machine-local Claude Code settings.
.claude/settings.local.json

# Runtime state, not config.
*.sock

# Pre-existing local clutter from before this repo was templated.
archive/
resume
```

- [ ] **Step 2: Write `LICENSE`**

Standard MIT text. `[fullname]` is intentionally left for the publishing
human to fill in — a solo maintainer's real name is their call, not
something to infer or invent:

```
MIT License

Copyright (c) 2026 [fullname]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Before this repo is ever made public, ask the user what name (if any) to
put in `[fullname]` — don't guess or fill it in silently.

- [ ] **Step 3: Create the `remote/` and `.claude/` directories**

```bash
mkdir -p remote .claude
```

- [ ] **Step 4: Verify**

```bash
test -f .gitignore && test -f LICENSE && test -d remote && test -d .claude && echo OK
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add .gitignore LICENSE
git commit -m "Add .gitignore and LICENSE"
```

---

### Task 2: `.env.sample`

**Files:**
- Create: `.env.sample`

**Interfaces:**
- Produces: the four-variable contract (`SSH_ALIAS`, `MAIL_USER`,
  `TMUX_SESSION`, `REMOTE_MAINT_PATH`) every later task's scripts source.

- [ ] **Step 1: Write `.env.sample`**

```bash
# Copy this file to .env and fill in the values below — or just run
# ./install-local.sh, which does this and prompts for anything left empty.

# Host entry in ~/.ssh/config to connect through.
SSH_ALIAS=

# Remote unix user whose mailbox check.sh / check-detailed.sh /
# mark-mail-read.sh read.
MAIL_USER=

# Remote tmux session name connect.sh attaches to (or creates).
TMUX_SESSION=

# Absolute path to the installed wrapper on the remote host.
REMOTE_MAINT_PATH=
```

- [ ] **Step 2: Verify it's valid, sourceable shell**

```bash
bash -n .env.sample && echo OK
set -a; source .env.sample; set +a
echo "SSH_ALIAS is empty: $([[ -z "$SSH_ALIAS" ]] && echo yes || echo no)"
```
Expected: `OK` then `SSH_ALIAS is empty: yes`

- [ ] **Step 3: Commit**

```bash
git add .env.sample
git commit -m "Add .env.sample"
```

---

### Task 3: Rewrite `ssh-lib.sh`

**Files:**
- Modify: `ssh-lib.sh`

**Interfaces:**
- Consumes: `.env` (via `SSH_ALIAS`), sourced relative to `ssh-lib.sh`'s
  own location so it works regardless of the caller's cwd.
- Produces: `hostkeeper_ensure_session()`, `hostkeeper_ssh "<cmd>"`,
  `hostkeeper_ssh_tty "<cmd>"`, and the array `HOSTKEEPER_SSH_OPTS` (used
  directly by `verify-install.sh` in Task 8).

- [ ] **Step 1: Replace `ssh-lib.sh` in full**

```bash
#!/usr/bin/env bash
# Shared SSH ControlMaster helpers.
# Reuses one multiplexed connection to the configured host across check.sh /
# check-detailed.sh / connect.sh / mark-mail-read.sh instead of paying a
# fresh SSH handshake (and re-auth) on every invocation. Socket lives
# outside the repo and outside ~/.ssh so it's pure runtime state, not config.

HOSTKEEPER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${HOSTKEEPER_LIB_DIR}/.env" 2>/dev/null || {
  echo "error: ${HOSTKEEPER_LIB_DIR}/.env not found. Run ./install-local.sh first." >&2
  exit 1
}

: "${SSH_ALIAS:?SSH_ALIAS is empty in .env — run ./install-local.sh}"

HOSTKEEPER_CONTROL_PATH="${HOSTKEEPER_CONTROL_PATH:-/tmp/hostkeeper-ssh-%r@%h:%p.sock}"
HOSTKEEPER_SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=${HOSTKEEPER_CONTROL_PATH}" -o "ControlPersist=10m")

# Ensure a multiplexed master connection is open, starting one if needed.
hostkeeper_ensure_session() {
  if ! ssh "${HOSTKEEPER_SSH_OPTS[@]}" -O check "$SSH_ALIAS" >/dev/null 2>&1; then
    echo "Opening SSH session to ${SSH_ALIAS}..." >&2
    ssh "${HOSTKEEPER_SSH_OPTS[@]}" -MNf "$SSH_ALIAS"
  fi
}

# Run a command over the shared session (opening it first if needed).
hostkeeper_ssh() {
  hostkeeper_ensure_session
  ssh "${HOSTKEEPER_SSH_OPTS[@]}" "$SSH_ALIAS" "$@"
}

# Same, but with a tty allocated (needed for e.g. tmux attach).
hostkeeper_ssh_tty() {
  hostkeeper_ensure_session
  ssh "${HOSTKEEPER_SSH_OPTS[@]}" -t "$SSH_ALIAS" "$@"
}
```

- [ ] **Step 2: Lint check**

```bash
shellcheck -S warning ssh-lib.sh; echo "exit: $?"
```
Expected: `exit: 0` (an `SC2029` info note on the `hostkeeper_ssh`/
`hostkeeper_ssh_tty` lines is expected and filtered out at this severity —
see Global Constraints).

- [ ] **Step 3: Verify the missing-`.env` error path (no live host needed)**

```bash
( cd /tmp && cp "$OLDPWD/ssh-lib.sh" . && bash -c 'source ssh-lib.sh' 2>&1 )
```
Expected: prints `error: ... .env not found. Run ./install-local.sh first.`
and exits non-zero (no `.env` exists in `/tmp`).

- [ ] **Step 4: Verify the empty-`SSH_ALIAS` error path**

```bash
( cd /tmp && cp "$OLDPWD/ssh-lib.sh" . && cp "$OLDPWD/.env.sample" .env && bash -c 'source ssh-lib.sh' 2>&1 )
```
Expected: prints something containing `SSH_ALIAS is empty` and exits
non-zero.

- [ ] **Step 5: Commit**

```bash
git add ssh-lib.sh
git commit -m "Make ssh-lib.sh read the connection alias from .env"
```

---

### Task 4: Update the caller scripts

**Files:**
- Modify: `connect.sh`
- Modify: `check.sh`
- Modify: `check-detailed.sh`
- Modify: `mark-mail-read.sh`

**Interfaces:**
- Consumes: `hostkeeper_ssh`, `hostkeeper_ssh_tty` from Task 3; `.env`
  variables `MAIL_USER`, `TMUX_SESSION`, `REMOTE_MAINT_PATH`.

- [ ] **Step 1: Replace `connect.sh` in full**

```bash
#!/usr/bin/env bash
# Open or reattach to a persistent maintenance session on the remote host.
# Survives SSH disconnects, laptop sleep, etc. via tmux on the remote side.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./ssh-lib.sh

: "${TMUX_SESSION:?TMUX_SESSION is empty in .env}"

# -A: attach if the session exists, otherwise create it.
hostkeeper_ssh_tty "tmux new-session -A -s ${TMUX_SESSION}"
```

- [ ] **Step 2: Replace `check.sh` in full**

```bash
#!/usr/bin/env bash
# Quick, read-only health snapshot of the remote host. Safe to run anytime.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./ssh-lib.sh

: "${MAIL_USER:?MAIL_USER is empty in .env}"
: "${REMOTE_MAINT_PATH:?REMOTE_MAINT_PATH is empty in .env}"

hostkeeper_ssh '
  echo "== uptime =="; uptime
  echo; echo "== reboot required? =="
  test -f /var/run/reboot-required \
    && { echo "YES"; cat /var/run/reboot-required.pkgs 2>/dev/null | sed "s/^/  /"; } \
    || echo "no"
  echo; echo "== disk =="; df -h --output=source,size,used,pcent,target | grep -v tmpfs
  echo; echo "== memory =="; free -h
  echo; echo "== failed units =="; systemctl --failed --no-legend || true
  echo; echo "== hardening services (ufw/fail2ban/apparmor) =="
  systemctl is-active ufw fail2ban apparmor 2>&1 | paste -sd" " -
  echo; echo "== auto-update timers (should be active) =="
  systemctl is-active apt-daily.timer apt-daily-upgrade.timer 2>&1 | paste -sd" " -
  echo; echo "== rkhunter daily cron enabled? =="
  grep -q "^CRON_DAILY_RUN=\"\(yes\|true\)\"" /etc/default/rkhunter 2>/dev/null \
    && echo "yes" || echo "NO - CRON_DAILY_RUN not set to yes in /etc/default/rkhunter"
  echo; echo "== chkrootkit last run (INFECTED markers only) =="
  grep -i "infected" /var/log/chkrootkit/log.today 2>/dev/null | grep -vi "not infected" || echo "(none)"
  echo; echo "== unread mail for '"$MAIL_USER"' =="
  awk "
    /^From / { if (started) { if (hasR==0) c++ }; started=1; hasR=0; next }
    /^Status:/ { if (\$0 ~ /R/) hasR=1 }
    END { if (started) { if (hasR==0) c++ }; print c+0 }
  " /var/mail/'"$MAIL_USER"' 2>/dev/null || echo 0
  echo; echo "== last 5 auth log lines =="; sudo '"$REMOTE_MAINT_PATH"' auth-log 5
'
```

- [ ] **Step 3: Replace `check-detailed.sh` in full**

```bash
#!/usr/bin/env bash
# Detailed, read-only health snapshot of the remote host. Safe to run anytime.
# Superset of check.sh — more sections, more depth per section.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./ssh-lib.sh

: "${MAIL_USER:?MAIL_USER is empty in .env}"
: "${REMOTE_MAINT_PATH:?REMOTE_MAINT_PATH is empty in .env}"

hostkeeper_ssh '
  echo "== system =="
  echo "OS:      $(grep PRETTY_NAME /etc/os-release | cut -d\" -f2)"
  echo "Kernel:  $(uname -r)"
  echo "Uptime:  $(uptime -p) (since $(uptime -s))"
  echo "Load:    $(uptime | grep -o "load average.*")"

  echo; echo "== reboot required? =="
  test -f /var/run/reboot-required \
    && { echo "YES"; cat /var/run/reboot-required.pkgs 2>/dev/null | sed "s/^/  /"; } \
    || echo "no"

  echo; echo "== disk (all mounts) =="
  df -hT | grep -v "^tmpfs\|^udev"

  echo; echo "== memory =="; free -h

  echo; echo "== pending package updates =="
  apt list --upgradable 2>/dev/null | tail -n +2 | sed "s/^/  /" || echo "  (none)"

  echo; echo "== top processes by memory =="
  ps aux --sort=-%mem --no-headers | head -6 | awk "{printf \"  %-12s %-6s %5s%% %5s%% %s\n\", \$1,\$2,\$3,\$4,\$11}"

  echo; echo "== top processes by cpu =="
  ps aux --sort=-%cpu --no-headers | head -6 | awk "{printf \"  %-12s %-6s %5s%% %5s%% %s\n\", \$1,\$2,\$3,\$4,\$11}"

  echo; echo "== listening ports =="
  ss -tulnp 2>/dev/null | awk "NR==1 || \$1!=\"\""

  echo; echo "== failed units =="; systemctl --failed --no-legend || true

  echo; echo "== hardening services (ufw/fail2ban/apparmor) =="
  systemctl is-active ufw fail2ban apparmor 2>&1 | paste -sd" " -

  echo; echo "== auto-update timers (should be active) =="
  systemctl is-active apt-daily.timer apt-daily-upgrade.timer 2>&1 | paste -sd" " -

  echo; echo "== rkhunter daily cron enabled? =="
  grep -q "^CRON_DAILY_RUN=\"\(yes\|true\)\"" /etc/default/rkhunter 2>/dev/null \
    && echo "yes" || echo "NO - CRON_DAILY_RUN not set to yes in /etc/default/rkhunter"

  echo; echo "== chkrootkit last run (INFECTED markers only) =="
  grep -i "infected" /var/log/chkrootkit/log.today 2>/dev/null | grep -vi "not infected" || echo "(none)"

  echo; echo "== unread mail for '"$MAIL_USER"' =="
  awk "
    /^From / { if (started) { if (hasR==0) c++ }; started=1; hasR=0; next }
    /^Status:/ { if (\$0 ~ /R/) hasR=1 }
    END { if (started) { if (hasR==0) c++ }; print c+0 }
  " /var/mail/'"$MAIL_USER"' 2>/dev/null || echo 0

  echo; echo "== last 10 auth log lines =="; sudo '"$REMOTE_MAINT_PATH"' auth-log 10
'

echo
echo "== docker containers =="
hostkeeper_ssh "sudo $REMOTE_MAINT_PATH docker-ps"

# If you've populated COMPOSE_PROJECTS in remote/claude-maint, add a line
# here for your own project key, e.g.:
#   echo; echo "== <project> compose stack =="
#   hostkeeper_ssh "sudo $REMOTE_MAINT_PATH compose-ps <project>"
```

Note: the original version of this script had a hardcoded
`compose-ps <project>` line for one specific deployment's compose project.
That's exactly the kind of host-specific fact that can't live in a tracked
file, so it's replaced with a comment showing how to add it back locally —
uncommitted, in the same spirit as `remote/claude-maint`.

- [ ] **Step 4: Replace `mark-mail-read.sh` in full**

```bash
#!/usr/bin/env bash
# Mark every message in the configured mail user's mailbox as read, in place.
# Inserts a "Status: RO" header into any message block that doesn't already
# have one — no interactive `mail` REPL involved. Safe to re-run; messages
# that are already marked read are left untouched.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./ssh-lib.sh

: "${MAIL_USER:?MAIL_USER is empty in .env}"

hostkeeper_ssh '
  tmp="$(mktemp)"
  awk "
    /^From / { print; inhdr=1; hasstatus=0; next }
    inhdr && /^Status:/ { hasstatus=1; print; next }
    inhdr && /^\$/ { if (!hasstatus) print \"Status: RO\"; inhdr=0; print; next }
    { print }
  " /var/mail/'"$MAIL_USER"' > "$tmp" && cat "$tmp" > /var/mail/'"$MAIL_USER"' && rm -f "$tmp"
'
echo "Marked all messages in the mailbox as read."
```

- [ ] **Step 5: Lint check all four**

```bash
for f in connect.sh check.sh check-detailed.sh mark-mail-read.sh; do
  shellcheck -S warning "$f"; echo "$f exit: $?"
done
```
Expected: four `exit: 0` lines. `SC1091` (can't follow `./ssh-lib.sh`) and
`SC2016` (single quotes don't expand, on the lines that splice in
`'"$MAIL_USER"'`) are expected `info`-level notes, filtered out at this
severity. (Full functional verification against a live host happens in
Task 12.)

- [ ] **Step 6: Commit**

```bash
git add connect.sh check.sh check-detailed.sh mark-mail-read.sh
git commit -m "Drive caller scripts from .env instead of hardcoded values"
```

---

### Task 5: Generic wrapper template

**Files:**
- Create: `remote/claude-maint.sample`
- Create: `remote/claude-maint.sudoers.sample`

**Interfaces:**
- Produces: the wrapper's action surface (`status`, `restart`, `logs`,
  `disk`, `auth-log`, `docker-ps`, `docker-logs`, `docker-restart`,
  `docker-stats`, `apt-upgrade`, `ufw-status`, `fail2ban-status`,
  `apparmor-status`, `mail-queue`, `compose-ps`, `compose-logs`,
  `compose-restart`) — CLAUDE.md (Task 10) and README.md (Task 11) both
  document this exact list, so keep it in sync if it changes later.

- [ ] **Step 1: Write `remote/claude-maint.sample` in full**

```bash
#!/usr/bin/env bash
# /usr/local/sbin/claude-maint
#
# Single controlled entry point for the passwordless-sudo maintenance
# workflow. This is the ONLY command that should ever appear in a NOPASSWD
# sudoers line for this purpose.
#
# CRITICAL: never make this a passthrough (no `sudo "$@"`, no `bash -c "$*"`,
# no `eval`). Every action must be an explicit case below with its own
# whitelist. Anything not listed here is refused.
#
# Ownership/perms this file MUST have (install-remote.sh sets these):
#   chown root:root /usr/local/sbin/claude-maint
#   chmod 755 /usr/local/sbin/claude-maint
# If the user calling this can write to this file, the whole design is void.

set -euo pipefail

LOG=/var/log/claude-maint.log
CALLER="$(logname 2>/dev/null || whoami)"

log() {
  echo "$(date -Is) [${CALLER}] $*" >> "$LOG"
}

# Services this script is allowed to touch at all. Add to this list
# deliberately, one at a time, not with a wildcard.
# e.g. ALLOWED_SERVICES=(nginx docker)
ALLOWED_SERVICES=()

# Docker containers this script is allowed to touch. Same rule: add
# deliberately, by exact name, never a wildcard.
# e.g. ALLOWED_CONTAINERS=(web worker)
ALLOWED_CONTAINERS=()

is_allowed_service() {
  local svc="$1"
  for s in "${ALLOWED_SERVICES[@]}"; do
    [[ "$svc" == "$s" ]] && return 0
  done
  return 1
}

is_allowed_container() {
  local c="$1"
  for x in "${ALLOWED_CONTAINERS[@]}"; do
    [[ "$c" == "$x" ]] && return 0
  done
  return 1
}

# Compose projects this script is allowed to touch, mapped to their fixed
# directory (must contain the docker-compose.yml). Only the key is ever
# taken from user input — the path is never user-supplied, so there's no
# way to point this at an arbitrary directory.
# e.g. COMPOSE_PROJECTS=([app]="/srv/app")
declare -A COMPOSE_PROJECTS=()

is_allowed_compose_project() {
  [[ -n "${COMPOSE_PROJECTS[$1]+x}" ]]
}

# For any optional service-name argument passed into docker/compose: must be
# a plain token, and specifically must not start with "-", so it can never
# be interpreted as a flag by docker/docker compose.
is_safe_token() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] && [[ "$1" != -* ]]
}

ACTION="${1:-}"
shift || true

case "$ACTION" in

  status)
    svc="${1:-}"
    is_allowed_service "$svc" || { echo "refused: unlisted service '$svc'" >&2; exit 1; }
    log "status $svc"
    systemctl status "$svc" --no-pager
    ;;

  restart)
    svc="${1:-}"
    is_allowed_service "$svc" || { echo "refused: unlisted service '$svc'" >&2; exit 1; }
    log "restart $svc"
    systemctl restart "$svc"
    ;;

  logs)
    svc="${1:-}"
    is_allowed_service "$svc" || { echo "refused: unlisted service '$svc'" >&2; exit 1; }
    lines="${2:-100}"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=100
    log "logs $svc ($lines lines)"
    journalctl -u "$svc" -n "$lines" --no-pager
    ;;

  disk)
    log "disk"
    df -h
    ;;

  auth-log)
    lines="${1:-20}"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=20
    log "auth-log ($lines lines)"
    # Auth events (sshd, sudo, su, login, PAM) live in the journal under the
    # authpriv facility (SYSLOG_FACILITY=10) on systems with no auth.log.
    journalctl SYSLOG_FACILITY=10 -n "$lines" --no-pager
    ;;

  docker-ps)
    log "docker-ps"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    ;;

  docker-logs)
    c="${1:-}"
    is_allowed_container "$c" || { echo "refused: unlisted container '$c'" >&2; exit 1; }
    lines="${2:-100}"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=100
    log "docker-logs $c ($lines lines)"
    docker logs --tail "$lines" "$c"
    ;;

  docker-restart)
    c="${1:-}"
    is_allowed_container "$c" || { echo "refused: unlisted container '$c'" >&2; exit 1; }
    log "docker-restart $c"
    docker restart "$c"
    ;;

  docker-stats)
    log "docker-stats"
    docker stats --no-stream
    ;;

  apt-upgrade)
    log "apt-upgrade"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
    ;;

  ufw-status)
    log "ufw-status"
    ufw status verbose
    ;;

  fail2ban-status)
    log "fail2ban-status"
    for jail in $(fail2ban-client status | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' '); do
      fail2ban-client status "$jail"
    done
    ;;

  apparmor-status)
    log "apparmor-status"
    aa-status
    ;;

  mail-queue)
    log "mail-queue"
    mailq
    ;;

  compose-ps)
    proj="${1:-}"
    is_allowed_compose_project "$proj" || { echo "refused: unlisted compose project '$proj'" >&2; exit 1; }
    log "compose-ps $proj"
    (cd "${COMPOSE_PROJECTS[$proj]}" && docker compose ps)
    ;;

  compose-logs)
    proj="${1:-}"
    is_allowed_compose_project "$proj" || { echo "refused: unlisted compose project '$proj'" >&2; exit 1; }
    svc="${2:-}"
    lines="${3:-100}"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=100
    if [[ -n "$svc" ]]; then
      is_safe_token "$svc" || { echo "refused: bad service token" >&2; exit 1; }
      log "compose-logs $proj $svc ($lines lines)"
      (cd "${COMPOSE_PROJECTS[$proj]}" && docker compose logs --tail "$lines" "$svc")
    else
      log "compose-logs $proj (all services, $lines lines)"
      (cd "${COMPOSE_PROJECTS[$proj]}" && docker compose logs --tail "$lines")
    fi
    ;;

  compose-restart)
    proj="${1:-}"
    is_allowed_compose_project "$proj" || { echo "refused: unlisted compose project '$proj'" >&2; exit 1; }
    svc="${2:-}"
    if [[ -n "$svc" ]]; then
      is_safe_token "$svc" || { echo "refused: bad service token" >&2; exit 1; }
      log "compose-restart $proj $svc"
      (cd "${COMPOSE_PROJECTS[$proj]}" && docker compose restart "$svc")
    else
      log "compose-restart $proj (whole stack)"
      (cd "${COMPOSE_PROJECTS[$proj]}" && docker compose restart)
    fi
    ;;

  *)
    echo "refused: unknown action '$ACTION'" >&2
    echo "allowed actions: status|restart|logs|disk|auth-log|docker-ps|docker-logs|docker-restart|docker-stats|apt-upgrade|compose-ps|compose-logs|compose-restart|ufw-status|fail2ban-status|apparmor-status|mail-queue" >&2
    log "REFUSED unknown action: $ACTION $*"
    exit 1
    ;;
esac
```

- [ ] **Step 2: Write `remote/claude-maint.sudoers.sample`**

```
# Installed by install-remote.sh to /etc/sudoers.d/claude-maint
# Replace __USER__ with the actual sudoer account before installing.
__USER__ ALL=(root) NOPASSWD: /usr/local/sbin/claude-maint
```

- [ ] **Step 3: Lint check the wrapper template**

```bash
shellcheck -S warning remote/claude-maint.sample; echo "exit: $?"
```
Expected: `exit: 0`

- [ ] **Step 4: Verify the whitelists are empty (no leaked host specifics)**

```bash
grep -E '^(ALLOWED_SERVICES|ALLOWED_CONTAINERS)=\(\)|^declare -A COMPOSE_PROJECTS=\(\)' remote/claude-maint.sample
```
Expected: three matching lines (all three whitelists declared empty).

- [ ] **Step 5: Verify the refusal path works locally (no live host needed)**

```bash
chmod +x remote/claude-maint.sample
./remote/claude-maint.sample status anything; echo "exit: $?"
```
Expected: `refused: unlisted service 'anything'` on stderr, `exit: 1`
(confirms the whitelist check runs and correctly refuses since
`ALLOWED_SERVICES` is empty).

- [ ] **Step 6: Commit**

```bash
git add remote/claude-maint.sample remote/claude-maint.sudoers.sample
git commit -m "Add generic wrapper and sudoers templates"
```

---

### Task 6: `remote/install-remote.sh`

**Files:**
- Create: `remote/install-remote.sh`

**Interfaces:**
- Consumes: `remote/claude-maint` (staged alongside this script on the
  remote host — the human's customized copy, not the `.sample`) and
  `remote/claude-maint.sudoers.sample` from Task 5.

- [ ] **Step 1: Write `remote/install-remote.sh` in full**

```bash
#!/usr/bin/env bash
# One-time bootstrap for the maintenance wrapper on the remote host.
# Run this directly on the target host, with sudo, as a human — never from
# an agent session:
#
#   sudo ./install-remote.sh <username>
#
# <username> is the account that will be allowed to run the wrapper
# passwordlessly via sudo (typically the account you SSH in as).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="${SCRIPT_DIR}/claude-maint"
SUDOERS_TEMPLATE="${SCRIPT_DIR}/claude-maint.sudoers.sample"
WRAPPER_DEST="/usr/local/sbin/claude-maint"
SUDOERS_DEST="/etc/sudoers.d/claude-maint"
LOG_FILE="/var/log/claude-maint.log"

if [[ "${EUID}" -ne 0 ]]; then
  echo "error: run this with sudo (sudo $0 <username>)" >&2
  exit 1
fi

USERNAME="${1:-}"
if [[ -z "$USERNAME" ]]; then
  echo "usage: sudo $0 <username>" >&2
  exit 1
fi

if [[ ! -f "$WRAPPER_SRC" ]]; then
  echo "error: ${WRAPPER_SRC} not found." >&2
  echo "Copy claude-maint.sample to claude-maint, edit its whitelists, then" >&2
  echo "scp both claude-maint and this script here before running it." >&2
  exit 1
fi

echo "Installing wrapper: ${WRAPPER_SRC} -> ${WRAPPER_DEST}"
install -o root -g root -m 755 "$WRAPPER_SRC" "$WRAPPER_DEST"

echo "Writing sudoers drop-in for user '${USERNAME}'..."
TMP_SUDOERS="$(mktemp)"
trap 'rm -f "$TMP_SUDOERS"' EXIT
sed "s/__USER__/${USERNAME}/" "$SUDOERS_TEMPLATE" > "$TMP_SUDOERS"

if ! visudo -c -f "$TMP_SUDOERS" >/dev/null; then
  echo "error: generated sudoers file failed validation, aborting install" >&2
  exit 1
fi

install -o root -g root -m 440 "$TMP_SUDOERS" "$SUDOERS_DEST"

echo "Preparing log file: ${LOG_FILE}"
touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 644 "$LOG_FILE"

echo
echo "Done."
echo "  Wrapper:  ${WRAPPER_DEST} (root:root 755)"
echo "  Sudoers:  ${SUDOERS_DEST} (NOPASSWD for ${USERNAME} on this one command)"
echo "  Log:      ${LOG_FILE}"
echo
echo "Verify from your local checkout with: ./verify-install.sh"
```

Note: `TMP_SUDOERS` cleanup uses `trap 'rm -f "$TMP_SUDOERS"' EXIT` right after the
`mktemp` call, rather than two manual `rm -f` calls on the validation-failure and
success paths. The manual-calls version misses one exit path: if `install`-ing
the validated file to `SUDOERS_DEST` itself fails (disk full, unexpected
permission issue), `set -e` would exit the script before a trailing `rm -f`
runs, leaving the rendered sudoers content (with the real username substituted
in) sitting in `/tmp`. The trap fires on every exit path, so this can't happen.

- [ ] **Step 2: Lint check**

```bash
shellcheck -S warning remote/install-remote.sh; echo "exit: $?"
```
Expected: `exit: 0`

- [ ] **Step 3: Verify the guard clauses locally (no root, no live host needed)**

```bash
chmod +x remote/install-remote.sh
./remote/install-remote.sh someuser; echo "no-sudo exit: $?"
sudo -n true 2>/dev/null && echo "(skip root-but-no-username check: passwordless sudo available in this shell)" \
  || echo "(skip root-but-no-username check: no passwordless sudo in this shell, expected in most dev environments)"
```
Expected: first command prints `error: run this with sudo ...` and
`no-sudo exit: 1`, since it's not running as root.

- [ ] **Step 4: Commit**

```bash
git add remote/install-remote.sh
git commit -m "Add remote bootstrap script"
```

---

### Task 7: `install-local.sh`

**Files:**
- Create: `install-local.sh`

**Interfaces:**
- Consumes: `.env.sample` (Task 2).
- Produces: a populated `.env` and, if missing, `remote/claude-maint`
  (copied from `remote/claude-maint.sample`).

- [ ] **Step 1: Write `install-local.sh` in full**

```bash
#!/usr/bin/env bash
# Local prep: creates .env, checks local prerequisites, verifies (or helps
# set up) the SSH alias, and stages a working copy of the wrapper script.
# Safe to re-run.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

for bin in ssh scp; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' not found on PATH" >&2; exit 1; }
done

if [[ ! -f .env ]]; then
  echo "Creating .env from .env.sample..."
  cp .env.sample .env
fi

prompt_if_empty() {
  local var="$1" prompt="$2" default="${3:-}"
  local current
  local tmp=""
  trap 'rm -f "$tmp"' RETURN

  current="$(grep -E "^${var}=" .env | head -1 | cut -d= -f2-)"
  if [[ -n "$current" ]]; then
    return
  fi
  local value
  if [[ -n "$default" ]]; then
    read -r -p "${prompt} [${default}]: " value
    value="${value:-$default}"
  else
    read -r -p "${prompt}: " value
  fi
  tmp="$(mktemp ./.env.XXXXXX)"
  awk -F= -v var="$var" -v val="$value" \
    'BEGIN{OFS="="} $1==var {$0=var"="val} {print}' .env > "$tmp"
  mv "$tmp" .env
}

prompt_if_empty SSH_ALIAS "SSH alias (Host entry in ~/.ssh/config)"
prompt_if_empty MAIL_USER "Remote unix user whose mailbox to check"
prompt_if_empty TMUX_SESSION "Remote tmux session name" "maint"
prompt_if_empty REMOTE_MAINT_PATH "Remote wrapper path" "/usr/local/sbin/claude-maint"

# shellcheck source=/dev/null
source .env

RESOLVED_HOST=""
if ssh -G "$SSH_ALIAS" 2>/dev/null | grep -q "^hostname "; then
  RESOLVED_HOST="$(ssh -G "$SSH_ALIAS" | awk '$1=="hostname"{print $2}')"
fi

if [[ -z "$RESOLVED_HOST" || "$RESOLVED_HOST" == "$SSH_ALIAS" ]]; then
  echo
  echo "No usable Host block for '${SSH_ALIAS}' found in ~/.ssh/config."
  read -r -p "Remote hostname or IP: " REMOTE_HOST
  read -r -p "Remote user: " REMOTE_USER
  read -r -p "Identity file [~/.ssh/id_ed25519]: " REMOTE_IDENTITY
  REMOTE_IDENTITY="${REMOTE_IDENTITY:-~/.ssh/id_ed25519}"
  read -r -p "Port [22]: " REMOTE_PORT
  REMOTE_PORT="${REMOTE_PORT:-22}"

  BLOCK="$(cat <<EOF

Host ${SSH_ALIAS}
    HostName ${REMOTE_HOST}
    User ${REMOTE_USER}
    IdentityFile ${REMOTE_IDENTITY}
    Port ${REMOTE_PORT}
EOF
)"
  echo
  echo "About to append this block to ~/.ssh/config:"
  echo "${BLOCK}"
  read -r -p "Append it? [y/N] " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "${BLOCK}" >> ~/.ssh/config
    echo "Appended."
  else
    echo "Skipped — add it yourself before continuing."
    exit 1
  fi
fi

echo
echo "Testing connectivity to '${SSH_ALIAS}'..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_ALIAS" true; then
  echo "OK — connected."
else
  echo "Could not connect. Check the Host block in ~/.ssh/config and try again." >&2
  exit 1
fi

if [[ ! -f remote/claude-maint ]]; then
  echo
  echo "Copying remote/claude-maint.sample -> remote/claude-maint"
  cp remote/claude-maint.sample remote/claude-maint
  echo "Edit remote/claude-maint's ALLOWED_SERVICES / ALLOWED_CONTAINERS /"
  echo "COMPOSE_PROJECTS before bootstrapping the remote host."
fi

echo
echo "Local prep done. Next steps:"
echo "  1. Edit remote/claude-maint's whitelists if you haven't already."
echo "  2. scp remote/claude-maint remote/install-remote.sh ${SSH_ALIAS}:~/"
echo "  3. ssh ${SSH_ALIAS}, then: sudo ./install-remote.sh <your-remote-username>"
echo "  4. ./verify-install.sh"
```

Note: `prompt_if_empty`'s temp file is created via `mktemp ./.env.XXXXXX` — in the
same directory as `.env`, not the default `/tmp` — so the final `mv "$tmp" .env`
is guaranteed to be a same-filesystem, atomic rename. `/tmp` and the project
directory can be on different filesystems/devices depending on environment,
which makes a cross-device `mv` a non-atomic stream-copy: an interruption
mid-copy would leave `.env` truncated. The `trap 'rm -f "$tmp"' RETURN` cleans
up the temp file on the function's early `return` (already-populated var) and
on normal completion; it does not cover a `set -e`-triggered abort between the
`mktemp` and `mv` lines (e.g. if `awk` itself failed) — that would leave a
stray `./.env.XXXXXX` file behind, but never touches `.env` itself, so it's
litter, not data loss.

- [ ] **Step 2: Lint check**

```bash
shellcheck -S warning install-local.sh; echo "exit: $?"
```
Expected: `exit: 0`

- [ ] **Step 3: Verify the prompt/write logic in isolation (no live host needed)**

```bash
mkdir -p /tmp/hostkeeper-test && cd /tmp/hostkeeper-test
cp "$OLDPWD/.env.sample" .
awk -F= -v var="SSH_ALIAS" -v val="test-alias" \
  'BEGIN{OFS="="} $1==var {$0=var"="val} {print}' .env.sample > .env
cat .env | grep SSH_ALIAS
cd "$OLDPWD"
rm -rf /tmp/hostkeeper-test
```
Expected: `SSH_ALIAS=test-alias` — confirms the same awk rewrite pattern
`prompt_if_empty` uses correctly updates a single `VAR=` line in place.
(The interactive prompts and the live `ssh -G`/connectivity checks are
exercised for real in Task 12, against your actual configured host.)

- [ ] **Step 4: Commit**

```bash
git add install-local.sh
git commit -m "Add local install script"
```

---

### Task 8: `verify-install.sh`

**Files:**
- Create: `verify-install.sh`

**Interfaces:**
- Consumes: `.env`, `ssh-lib.sh` (`hostkeeper_ssh`, `HOSTKEEPER_SSH_OPTS`),
  `check.sh`.

- [ ] **Step 1: Write `verify-install.sh` in full**

```bash
#!/usr/bin/env bash
# One-time (or repeatable) post-install validation. Read-only — touches
# nothing. Run this after both install-local.sh and remote/install-remote.sh
# have completed.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if [[ ! -f .env ]]; then
  echo "FAIL  .env exists"
  echo "  .env not found — run ./install-local.sh first."
  exit 1
fi
# shellcheck source=/dev/null
source .env

PASS=0
FAIL=0

check() {
  local name="$1"; shift
  if "$@"; then
    echo "PASS  $name"
    PASS=$((PASS+1))
  else
    echo "FAIL  $name"
    FAIL=$((FAIL+1))
  fi
}

env_populated() {
  [[ -n "${SSH_ALIAS:-}" && -n "${MAIL_USER:-}" && -n "${TMUX_SESSION:-}" && -n "${REMOTE_MAINT_PATH:-}" ]]
}
check ".env fully populated" env_populated

alias_resolves() {
  local resolved
  resolved="$(ssh -G "$SSH_ALIAS" 2>/dev/null | awk '$1=="hostname"{print $2}')"
  [[ -n "$resolved" && "$resolved" != "$SSH_ALIAS" ]]
}
check "SSH alias resolves" alias_resolves

ssh_lib_sources_cleanly() {
  ( source ./ssh-lib.sh ) >/dev/null 2>&1
}
check "ssh-lib.sh sources cleanly (SSH_ALIAS set)" ssh_lib_sources_cleanly

if [[ "$FAIL" -gt 0 ]]; then
  echo
  echo "$FAIL check(s) failed ($PASS/$((PASS+FAIL)) passed) — fix .env and re-run before continuing."
  exit 1
fi

source ./ssh-lib.sh

fresh_connection() {
  hostkeeper_ssh true
}
check "fresh SSH connection works" fresh_connection

socket_reused() {
  ssh "${HOSTKEEPER_SSH_OPTS[@]}" -O check "$SSH_ALIAS" 2>&1 | grep -q "Master running"
}
check "control socket is reused" socket_reused

wrapper_installed() {
  local owner_mode
  owner_mode="$(hostkeeper_ssh "stat -c '%U:%G %a' '$REMOTE_MAINT_PATH'" 2>/dev/null)"
  [[ "$owner_mode" == "root:root 755" ]]
}
check "wrapper installed as root:root 755" wrapper_installed

sudo_passwordless() {
  hostkeeper_ssh "sudo -n '$REMOTE_MAINT_PATH' disk" >/dev/null 2>&1
}
check "wrapper runs passwordlessly via sudo" sudo_passwordless

second_action() {
  hostkeeper_ssh "sudo '$REMOTE_MAINT_PATH' mail-queue" >/dev/null 2>&1
}
check "a second wrapper action works" second_action

check_sh_runs() {
  ./check.sh >/dev/null 2>&1
}
check "check.sh runs and produces output" check_sh_runs

mail_count_runs() {
  hostkeeper_ssh '
    awk "
      /^From / { if (started) { if (hasR==0) c++ }; started=1; hasR=0; next }
      /^Status:/ { if (\$0 ~ /R/) hasR=1 }
      END { if (started) { if (hasR==0) c++ }; print c+0 }
    " /var/mail/'"$MAIL_USER"' 2>/dev/null
  ' | grep -qE '^[0-9]+$'
}
check "mail unread-count check runs cleanly" mail_count_runs

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "All checks passed ($PASS/$((PASS+FAIL))) — hostkeeper is ready."
  exit 0
else
  echo "$FAIL check(s) failed ($PASS/$((PASS+FAIL)) passed) — see above."
  exit 1
fi
```

Two things in the checks above are easy to get wrong, so they're called out
explicitly:

- `alias_resolves` cannot just grep for a `hostname` line in `ssh -G`'s
  output — `ssh -G` always prints one, even for a completely bogus or
  unconfigured alias, by echoing the argument back. The check has to
  compare the *resolved* hostname against the alias itself; if they're
  still equal, nothing real was resolved.
- `source ./ssh-lib.sh` cannot run directly as a `check()`-wrapped or
  unwrapped step: ssh-lib.sh's own `${SSH_ALIAS:?...}` guard calls `exit`
  unconditionally on an empty `SSH_ALIAS`, and that `exit` is NOT something
  `if`/`check()` can catch — it terminates the whole script outright.
  Testing it inside a subshell (`( source ./ssh-lib.sh )`) contains the
  `exit` to the subshell, so it can be treated as a normal pass/fail check;
  only once that's confirmed safe does the real, unguarded `source` run at
  top level for the remaining checks to use.

- [ ] **Step 2: Lint check**

```bash
shellcheck -S warning verify-install.sh; echo "exit: $?"
```
Expected: `exit: 0`. (An earlier draft of this script omitted the `|| exit
1` guard on the `cd` above — `shellcheck` caught it as `SC2164` at
`warning` severity, since without `set -e` a failed `cd` would otherwise
be silently ignored and the rest of the script would run from the wrong
directory. The guard above is already fixed; this step just confirms it.)

- [ ] **Step 3: Verify the no-`.env` guard**

```bash
( cd /tmp && mkdir -p hostkeeper-verify-test && cd hostkeeper-verify-test && cp "$OLDPWD/verify-install.sh" . && ./verify-install.sh; echo "exit: $?" )
rm -rf /tmp/hostkeeper-verify-test
```
Expected: `FAIL  .env exists` and `exit: 1` (no `.env` present in the
scratch dir — everything else short-circuits correctly).

Full functional verification (all 10 checks against a live, bootstrapped
host) happens in Task 12.

- [ ] **Step 4: Commit**

```bash
git add verify-install.sh
git commit -m "Add post-install validation script"
```

---

### Task 9: `.claude/settings.json`

**Files:**
- Create: `.claude/settings.json`

- [ ] **Step 1: Write `.claude/settings.json` in full**

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

- [ ] **Step 2: Verify it's valid JSON**

```bash
python3 -c "import json; json.load(open('.claude/settings.json'))" && echo OK
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json
git commit -m "Add baseline Claude Code permission allow/deny list"
```

---

### Task 10: `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace `CLAUDE.md` in full**

```markdown
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
   - `claude-maint auth-log [lines]`
   - `claude-maint docker-ps`
   - `claude-maint docker-logs <container> [lines]`
   - `claude-maint docker-restart <container>`
   - `claude-maint docker-stats`
   - `claude-maint apt-upgrade`
   - `claude-maint compose-ps <project>`
   - `claude-maint compose-logs <project> [service] [lines]`
   - `claude-maint compose-restart <project> [service]`
   - `claude-maint ufw-status`
   - `claude-maint fail2ban-status`
   - `claude-maint apparmor-status`
   - `claude-maint mail-queue`

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
```

- [ ] **Step 2: Verify the action list matches the wrapper**

```bash
diff <(grep -oE '^\s+[a-z][a-z-]+\)' remote/claude-maint.sample | tr -d ') ' | sort -u) \
     <(grep -oE 'claude-maint [a-z][a-z-]+' CLAUDE.md | awk '{print $2}' | sort -u)
```
Expected: no output beyond harmless extras like `esac`/`*` artifacts from
the first command's pattern — eyeball it to confirm every real action name
in `claude-maint.sample`'s case statement appears in CLAUDE.md's list, and
vice versa.

(A leaked-specifics check belongs in Task 13, not here — a per-task step in
a *committed* plan file must never hardcode anyone's real host details as
a literal search pattern, since that would itself commit those details.
Task 13's audit builds its search pattern from whatever's actually in
`.env` at run time instead.)

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Rewrite CLAUDE.md to be host-agnostic and add the public-LLM warning"
```

---

### Task 11: `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md` in full**

```markdown
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

Edit `remote/claude-maint` locally → `scp` it to the remote home
directory → on the host, run `sudo install -o root -g root -m 755
~/claude-maint <REMOTE_MAINT_PATH>` yourself. This step stays
human-run and passworded on purpose — never automated — so an agent
session can never silently change what the wrapper is allowed to do.

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
```

- [ ] **Step 2: Proofread against the file layout**

Confirm every path README.md references (`.env`, `ssh-lib.sh`, `connect.sh`,
`check.sh`, `check-detailed.sh`, `mark-mail-read.sh`, `install-local.sh`,
`verify-install.sh`, `remote/claude-maint`, `remote/claude-maint.sudoers.sample`,
`remote/install-remote.sh`, `CLAUDE.md`, `.claude/settings.json`) exists or
will exist by the end of this plan. (Leaked-specifics scanning happens once,
generically, in Task 13 — not hardcoded here; see Task 10 Step 2's note.)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README"
```

---

### Task 12: Local adoption against the real host

**Files:**
- Modify (gitignored, not committed): `.env`
- Modify (gitignored, not committed): `remote/claude-maint`

**Interfaces:**
- Consumes: every script from Tasks 1–9, against the already-bootstrapped
  real host from prior work in this project (the wrapper and sudoers
  drop-in are already installed there from earlier sessions — this task
  only needs to reproduce the equivalent local config and confirm it
  still all lines up, not repeat `install-remote.sh`).

- [ ] **Step 1: Populate `.env` with your real connection details**

Fill in the four values for your actual target host — the SSH alias
already configured in `~/.ssh/config`, the remote unix user whose mail you
check, your preferred tmux session name, and the wrapper's remote path.
This file is gitignored; do not add it to git.

- [ ] **Step 2: Populate `remote/claude-maint` to match what's already live**

Copy `remote/claude-maint.sample` to `remote/claude-maint` and fill in
`ALLOWED_SERVICES`, `ALLOWED_CONTAINERS`, and `COMPOSE_PROJECTS` to match
whatever is already installed and whitelisted on the real host from prior
work. This file is gitignored; do not add it to git.

- [ ] **Step 3: Run the full validator**

```bash
./verify-install.sh
```
Expected: all 10 checks `PASS`, ending in `All checks passed (10/10) —
hostkeeper is ready.`

- [ ] **Step 4: Spot-check the day-to-day scripts still behave the same as before the restructuring**

```bash
./check.sh
./check-detailed.sh
```
Expected: same sections/content shape as before this restructuring, now
sourced from `.env` instead of hardcoded values — no errors, no missing
sections.

- [ ] **Step 5: No commit** — both files touched in this task are gitignored
  by design (Task 1). Confirm they're not staged:

```bash
git status --short | grep -E "^\?\? \.env$|^\?\? remote/claude-maint$" || true
git status --short -- .env remote/claude-maint
```
Expected: either no output from the second command, or `??` (untracked) —
never `A` (staged) or `M` (modified-and-tracked).

---

### Task 13: Final audit and wrap-up

**Files:** none created — verification only.

This task touches the real values in `.env`, so — like Task 12 — it must be
run by whoever holds those values directly, never dispatched to a fresh
subagent: sourcing `.env` (Step 1) puts real host details into that
subagent's context and transcript, which is exactly what's being audited
against. Nothing here is committed, and none of the commands below hardcode
any specific host's details — the search pattern is built from `.env` at
run time, so this step works unchanged for anyone's fork.

- [ ] **Step 1: Grep the entire tracked tree for leaked specifics, built from your own `.env`**

```bash
# shellcheck disable=SC1091
source .env
PATTERN=""
for v in "$SSH_ALIAS" "$MAIL_USER"; do
  [[ -n "$v" ]] && PATTERN="${PATTERN:+$PATTERN|}$(printf '%s' "$v" | sed 's/[.[\*^$()+?{|]/\\&/g')"
done
if [[ -n "$PATTERN" ]]; then
  git ls-files -z | xargs -0 grep -liE "$PATTERN" || echo "clean"
else
  echo "clean (no .env values set to check against)"
fi
```
Expected: `clean` (no tracked file matches your own alias or mail user).

- [ ] **Step 2: Confirm the gitignored files are actually ignored**

```bash
git check-ignore -v .env remote/claude-maint
```
Expected: two lines, each showing `.gitignore` as the matching rule.

- [ ] **Step 3: Confirm every tracked script passes lint at warning severity**

```bash
for f in $(git ls-files '*.sh'); do
  shellcheck -S warning "$f" && echo "OK: $f"
done
```
Expected: an `OK:` line for every tracked `.sh` file, no errors.

- [ ] **Step 4: Review the full commit history for leaks (not just the working tree)**

```bash
git log -p | grep -iE "$PATTERN" || echo "history clean"
```
(Reuses `$PATTERN` from Step 1 — same shell session.) Expected: `history
clean`. If this finds anything, stop and fix history (rebase/amend) before
this repo is ever pushed anywhere — don't just fix the working tree and
move on. Also worth a manual skim of `git log -p` for anything the pattern
wouldn't catch (a service or container name unrelated to `SSH_ALIAS`/
`MAIL_USER` — e.g. from an earlier draft of `remote/claude-maint` before it
was genericized).

- [ ] **Step 5: Final status check**

```bash
git status
git log --oneline
```
Confirm a clean working tree (aside from the gitignored `.env` and
`remote/claude-maint`) and a commit history that reads as a normal,
generic project history with no task referencing a specific deployment.
