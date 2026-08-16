#!/usr/bin/env bash
# Open or reattach to a persistent maintenance session on the remote host.
# Survives SSH disconnects, laptop sleep, etc. via tmux on the remote side.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./ssh-lib.sh

: "${TMUX_SESSION:?TMUX_SESSION is empty in .env}"

# -A: attach if the session exists, otherwise create it.
hostkeeper_ssh_tty "tmux new-session -A -s ${TMUX_SESSION}"
