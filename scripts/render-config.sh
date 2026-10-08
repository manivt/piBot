#!/usr/bin/env bash
# ==============================================================================
# scripts/render-config.sh
# Safely renders ~/.zeroclaw/config.toml from the template.
# Values come from the .env file if it exists, otherwise from the environment
# (useful for automation).
# Note: ZeroClaw enforces 0600 permissions on config.toml.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
TEMPLATE_FILE="${TEMPLATE_FILE:-${REPO_ROOT}/config/zeroclaw/config.toml.template}"
TARGET_FILE="${1:-${HOME}/.zeroclaw/config.toml}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
elif [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "[-] Error: .env file not found at ${ENV_FILE}"
  echo "    Please copy ${REPO_ROOT}/.env.example to ${REPO_ROOT}/.env and fill in your values."
  exit 1
fi

if [[ ! -f "${TEMPLATE_FILE}" ]]; then
  echo "[-] Error: Template file not found at ${TEMPLATE_FILE}"
  exit 1
fi

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "[-] Error: TELEGRAM_BOT_TOKEN is not set"
  exit 1
fi

if [[ -z "${TELEGRAM_ALLOWED_USERS:-}" ]]; then
  echo "[-] Error: TELEGRAM_ALLOWED_USERS is not set"
  echo "    Please provide at least one authorized Telegram numeric user ID."
  exit 1
fi

if [[ -z "${AGY_SHIM_TOKEN:-}" ]]; then
  echo "[-] Error: AGY_SHIM_TOKEN is not set (scripts/setup.sh generates it)"
  exit 1
fi

WORKSPACE_ROOT="${WORKSPACE_ROOT:-${HOME}/workspaces}"

# Ensure destination directory exists
mkdir -p "$(dirname "${TARGET_FILE}")"

echo "[+] Rendering ${TARGET_FILE} from template..."

export RENDER_TEMPLATE_FILE="${TEMPLATE_FILE}"
export RENDER_TARGET_FILE="${TARGET_FILE}"
export RENDER_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
export RENDER_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS}"
export RENDER_WORKSPACE_ROOT="${WORKSPACE_ROOT}"
export RENDER_SHIM_PORT="${AGY_SHIM_PORT:-8088}"
export RENDER_SHIM_TOKEN="${AGY_SHIM_TOKEN}"

# Create the file with 0600 before any secret is written to it
umask 077

# Use python to perform safe literal JSON replacement
python3 - << 'EOF'
import json
import os
import re
import sys

template_path = os.environ["RENDER_TEMPLATE_FILE"]
target_path = os.environ["RENDER_TARGET_FILE"]
bot_token = os.environ["RENDER_BOT_TOKEN"].strip()
raw_users = os.environ["RENDER_ALLOWED_USERS"]
workspace_root = os.environ["RENDER_WORKSPACE_ROOT"].strip()
shim_port = os.environ["RENDER_SHIM_PORT"].strip()
shim_token = os.environ["RENDER_SHIM_TOKEN"].strip()

# Validate allowed users
user_tokens = [u.strip() for u in raw_users.split(",") if u.strip()]
if not user_tokens:
    sys.stderr.write("[-] Error: No valid user IDs found in TELEGRAM_ALLOWED_USERS\n")
    sys.exit(1)

for uid in user_tokens:
    if not uid.isdigit():
        sys.stderr.write(f"[-] Error: Invalid Telegram user ID '{uid}'. Telegram user IDs must be numeric digits.\n")
        sys.exit(1)

if not shim_port.isdigit() or not 1 <= int(shim_port) <= 65535:
    sys.stderr.write(f"[-] Error: Invalid AGY_SHIM_PORT '{shim_port}'.\n")
    sys.exit(1)

if not re.fullmatch(r"[A-Za-z0-9]{32,}", shim_token):
    sys.stderr.write("[-] Error: AGY_SHIM_TOKEN must be at least 32 alphanumeric characters.\n")
    sys.exit(1)

with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace placeholders safely
content = content.replace('"__TELEGRAM_BOT_TOKEN__"', json.dumps(bot_token))
content = content.replace('"__TELEGRAM_USER_ID__"', json.dumps(user_tokens)[1:-1])
content = content.replace('"__WORKSPACE_ROOT__"', json.dumps(workspace_root))
content = content.replace('"__AGY_SHIM_URI__"', json.dumps(f"http://127.0.0.1:{shim_port}/v1"))
content = content.replace('"__AGY_SHIM_TOKEN__"', json.dumps(shim_token))

with open(target_path, "w", encoding="utf-8") as f:
    f.write(content)
EOF

# Set strict permissions (ZeroClaw enforces 0600)
chmod 600 "${TARGET_FILE}"

echo "[+] Configuration successfully generated at ${TARGET_FILE} (mode 0600)."
