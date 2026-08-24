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

# Optional, personal, gitignored: source ./check.local.sh if you've created
# one, e.g. to append a one-line summary for a compose project you run.
# See check.local.sh.sample for the pattern.
if [[ -f ./check.local.sh ]]; then
  source ./check.local.sh
fi
