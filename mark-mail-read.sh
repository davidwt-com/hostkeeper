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
