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
  resolved="$(ssh -G "${SSH_ALIAS:-}" 2>/dev/null | awk '$1=="hostname"{print $2}')"
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
  hostkeeper_ssh "sudo -n '$REMOTE_MAINT_PATH' mail-queue" >/dev/null 2>&1
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
