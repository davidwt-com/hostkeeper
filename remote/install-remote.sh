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
