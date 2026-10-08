#!/usr/bin/env bash
# ==============================================================================
# docker/entrypoint.sh
# Container entrypoint for piBot.
# Supervises the agy-shim loopback translation bridge and the ZeroClaw daemon.
# Handles signal propagation, startup healthchecks, and non-zero exit codes.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Privileged / UID / GID Alignment (if started as root)
# ------------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  TARGET_UID="${PUID:-1000}"
  TARGET_GID="${PGID:-1000}"

  CURRENT_UID="$(id -u zeroclaw 2>/dev/null || echo '')"
  CURRENT_GID="$(id -g zeroclaw 2>/dev/null || echo '')"

  if [ -n "${CURRENT_GID}" ] && [ "${CURRENT_GID}" != "${TARGET_GID}" ]; then
    groupmod -o -g "${TARGET_GID}" zeroclaw 2>/dev/null || true
  fi

  if [ -n "${CURRENT_UID}" ] && [ "${CURRENT_UID}" != "${TARGET_UID}" ]; then
    usermod -o -u "${TARGET_UID}" -g "${TARGET_GID}" zeroclaw 2>/dev/null || true
  fi

  # Ensure ownership of core directories
  mkdir -p /home/zeroclaw/.zeroclaw /home/zeroclaw/.gemini /home/zeroclaw/workspaces
  chown -R zeroclaw:zeroclaw /home/zeroclaw/.zeroclaw /home/zeroclaw/.gemini /home/zeroclaw/workspaces

  # Re-exec this entrypoint as the unprivileged zeroclaw user
  exec gosu zeroclaw /usr/local/bin/entrypoint.sh "$@"
fi

# ------------------------------------------------------------------------------
# 2. Workspace & Configuration Initialization
# ------------------------------------------------------------------------------
AGENT_NAME="${AGENT_NAME:-pibot}"
AGENT_WORKSPACE="${HOME}/.zeroclaw/agents/${AGENT_NAME}/workspace"
CONFIG_FILE="${HOME}/.zeroclaw/config.toml"
SEED_AGENT="/etc/pibot/agent"
SEED_TEMPLATE="/etc/pibot/config.toml.template"
TOKEN_FILE="${HOME}/.zeroclaw/agy-shim.token"

mkdir -p "${AGENT_WORKSPACE}"
mkdir -p "${HOME}/workspaces"

# Seed agent persona prompt files if not already present in the mounted volume.
# Personal overrides from agent/local/ (git-ignored) win over the defaults.
if [ ! -f "${AGENT_WORKSPACE}/AGENTS.md" ]; then
  echo "[piBot] Seeding agent workspace persona files into ${AGENT_WORKSPACE}..."
  cp "${SEED_AGENT}"/workspace/*.md "${AGENT_WORKSPACE}/"
  if compgen -G "${SEED_AGENT}/local/*.md" > /dev/null; then
    cp "${SEED_AGENT}"/local/*.md "${AGENT_WORKSPACE}/"
  fi
fi

# Shared secret between ZeroClaw and agy-shim, persisted in the ~/.zeroclaw volume
if [ ! -s "${TOKEN_FILE}" ]; then
  (umask 077 && python3 -c 'import secrets; print(secrets.token_hex(32))' > "${TOKEN_FILE}")
fi
AGY_SHIM_TOKEN="$(cat "${TOKEN_FILE}")"
AGY_SHIM_PORT=8088
export AGY_SHIM_TOKEN AGY_SHIM_PORT

# Render configuration from the environment on every start, so it always
# matches the current .env and shim token. Without the Telegram variables,
# fall back to a config.toml you mounted yourself.
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
  ENV_FILE=/nonexistent TEMPLATE_FILE="${SEED_TEMPLATE}" WORKSPACE_ROOT="${HOME}/workspaces" \
    pibot-render-config "${CONFIG_FILE}"
elif [ ! -f "${CONFIG_FILE}" ]; then
  echo "[-] Error: ${CONFIG_FILE} not found." >&2
  echo "    Either mount an existing config.toml into ~/.zeroclaw/ or provide" >&2
  echo "    TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USERS environment variables." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 3. Process Supervision & Signal Handling
# ------------------------------------------------------------------------------
SHIM_PID=""
APP_PID=""

# shellcheck disable=SC2317
cleanup() {
  echo "[piBot] Received shutdown signal. Terminating child processes..."
  if [ -n "${APP_PID}" ] && kill -0 "${APP_PID}" 2>/dev/null; then
    kill -TERM "${APP_PID}" 2>/dev/null || true
  fi
  if [ -n "${SHIM_PID}" ] && kill -0 "${SHIM_PID}" 2>/dev/null; then
    kill -TERM "${SHIM_PID}" 2>/dev/null || true
  fi
  wait "${APP_PID}" 2>/dev/null || true
  wait "${SHIM_PID}" 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# ------------------------------------------------------------------------------
# 4. Start agy-shim Loopback Translation Bridge
# ------------------------------------------------------------------------------
echo "[piBot] Starting agy-shim loopback bridge on http://127.0.0.1:8088..."
agy-shim &
SHIM_PID=$!

echo "[piBot] Waiting for agy-shim /health endpoint readiness..."
READY=0
for _ in $(seq 1 30); do
  if ! kill -0 "${SHIM_PID}" 2>/dev/null; then
    echo "[-] Error: agy-shim process died unexpectedly during startup." >&2
    exit 1
  fi
  if curl -s http://127.0.0.1:8088/health >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "${READY}" -ne 1 ]; then
  echo "[-] Error: agy-shim failed to report healthy within 15 seconds." >&2
  kill -TERM "${SHIM_PID}" 2>/dev/null || true
  exit 1
fi
echo "[piBot] agy-shim is healthy and ready."

# ------------------------------------------------------------------------------
# 5. Execute Primary Command (Default: ZeroClaw daemon)
# ------------------------------------------------------------------------------
if [ "$#" -eq 0 ] || [ "$1" = "daemon" ]; then
  echo "[piBot] Launching ZeroClaw daemon..."
  zeroclaw daemon &
  APP_PID=$!
else
  echo "[piBot] Executing command: $*"
  "$@" &
  APP_PID=$!
fi

EXIT_STATUS=0
wait "${APP_PID}" || EXIT_STATUS=$?

echo "[piBot] Primary process exited with status ${EXIT_STATUS}. Stopping agy-shim..."
if [ -n "${SHIM_PID}" ] && kill -0 "${SHIM_PID}" 2>/dev/null; then
  kill -TERM "${SHIM_PID}" 2>/dev/null || true
  wait "${SHIM_PID}" 2>/dev/null || true
fi

exit "${EXIT_STATUS}"
