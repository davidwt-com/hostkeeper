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
