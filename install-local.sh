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
  trap 'rm -f "${tmp:-}"' RETURN

  current="$(grep -E "^${var}=" .env | head -1 | cut -d= -f2- || true)"
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
  if grep -qE "^${var}=" .env; then
    awk -F= -v var="$var" -v val="$value" \
      'BEGIN{OFS="="} $1==var {$0=var"="val} {print}' .env > "$tmp"
  else
    cp .env "$tmp"
    printf '%s=%s\n' "$var" "$value" >> "$tmp"
  fi
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
