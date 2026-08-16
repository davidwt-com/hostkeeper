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
