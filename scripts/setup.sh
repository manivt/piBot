#!/usr/bin/env bash
# ==============================================================================
# scripts/setup.sh
# End-to-end setup script for piBot.
# Builds agy-shim, configures ZeroClaw, sets up agent workspace files, and starts systemd services.
# Safe to re-run: it rebuilds, re-renders config and restarts the services.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

echo "============================================================"
echo " piBot Setup"
echo "============================================================"

# Step 1: Pre-flight checks
echo "[*] Step 1: Checking required CLI tools and .env..."
for cmd in go agy zeroclaw python3; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "[-] Error: Required command '${cmd}' not found in PATH."
    echo "    Please run '${REPO_ROOT}/scripts/install-prereqs.sh' first."
    exit 1
  fi
done

ENV_FILE="${REPO_ROOT}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[-] Error: ${ENV_FILE} does not exist."
  echo "    Run: cp ${REPO_ROOT}/.env.example ${ENV_FILE}"
  echo "    then set TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USERS and re-run this script."
  exit 1
fi
chmod 600 "${ENV_FILE}"
# shellcheck disable=SC1090
source "${ENV_FILE}"
echo "[+] All required tools found."

APPLIANCE_USER="${APPLIANCE_USER:-${USER}}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${HOME}/workspaces}"
AGENT_NAME="${AGENT_NAME:-pibot}"
AGY_SHIM_PORT="${AGY_SHIM_PORT:-8088}"
AGENT_WORKSPACE="${HOME}/.zeroclaw/agents/${AGENT_NAME}/workspace"
SHIM_ENV_FILE="${HOME}/.config/pibot/agy-shim.env"

# Step 2: Ensure workspace directories exist
echo "[*] Step 2: Preparing directory layout..."
mkdir -p "${WORKSPACE_ROOT}/agy-shim"
mkdir -p "${AGENT_WORKSPACE}"
mkdir -p "${HOME}/.config/systemd/user"
mkdir -p "$(dirname "${SHIM_ENV_FILE}")"

# Step 3: Build agy-shim
echo "[*] Step 3: Compiling agy-shim bridge..."
cp "${REPO_ROOT}/agy-shim/main.go" "${WORKSPACE_ROOT}/agy-shim/main.go"
cp "${REPO_ROOT}/agy-shim/go.mod" "${WORKSPACE_ROOT}/agy-shim/go.mod"
(
  cd "${WORKSPACE_ROOT}/agy-shim"
  go build -o agy-shim main.go
)
echo "[+] agy-shim compiled successfully at ${WORKSPACE_ROOT}/agy-shim/agy-shim"

# Step 4: Generate (once) the shared secret between ZeroClaw and agy-shim
echo "[*] Step 4: Preparing agy-shim credentials..."
AGY_SHIM_TOKEN=""
if [[ -f "${SHIM_ENV_FILE}" ]]; then
  AGY_SHIM_TOKEN="$(sed -n 's/^AGY_SHIM_TOKEN=//p' "${SHIM_ENV_FILE}")"
fi
if [[ -z "${AGY_SHIM_TOKEN}" ]]; then
  AGY_SHIM_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  echo "[+] Generated a new agy-shim token."
fi
(
  umask 077
  printf 'AGY_SHIM_TOKEN=%s\nAGY_SHIM_PORT=%s\n' "${AGY_SHIM_TOKEN}" "${AGY_SHIM_PORT}" > "${SHIM_ENV_FILE}"
)
export AGY_SHIM_TOKEN AGY_SHIM_PORT
echo "[+] agy-shim credentials stored in ${SHIM_ENV_FILE} (mode 0600)."

# Step 5: Deploy Agent prompt files
# Defaults come from agent/workspace/; your personal versions in agent/local/
# (git-ignored, so they never get committed) override them file by file.
echo "[*] Step 5: Deploying piBot workspace prompt files..."
cp "${REPO_ROOT}/agent/workspace/"*.md "${AGENT_WORKSPACE}/"
if compgen -G "${REPO_ROOT}/agent/local/*.md" > /dev/null; then
  cp "${REPO_ROOT}/agent/local/"*.md "${AGENT_WORKSPACE}/"
  echo "[+] Applied personal overrides from agent/local/."
fi
# The persona files say "piBot"; BOT_NAME lets the bot use the name you gave it
# in BotFather instead. Only the deployed copies are changed, not the repo.
BOT_NAME="${BOT_NAME:-piBot}"
if [[ ! "${BOT_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._\'-]{0,39}$ ]]; then
  echo "[-] Error: BOT_NAME '${BOT_NAME}' is not valid. Use up to 40 letters, digits, spaces, . _ - or '."
  exit 1
fi
if [[ "${BOT_NAME}" != "piBot" ]]; then
  sed -i "s/piBot/${BOT_NAME}/g" "${AGENT_WORKSPACE}/"*.md
  echo "[+] Bot will introduce itself as '${BOT_NAME}'."
fi
echo "[+] Workspace files deployed to ${AGENT_WORKSPACE}/"

# Step 6: Render ZeroClaw configuration
echo "[*] Step 6: Configuring ZeroClaw..."
"${REPO_ROOT}/scripts/render-config.sh" "${HOME}/.zeroclaw/config.toml"

# Step 7: LAN guard — firewall the bot's account away from other devices on
# the local network (internet, DNS and inbound SSH keep working).
LAN_GUARD="${LAN_GUARD:-on}"
if [[ "${LAN_GUARD}" == "off" ]]; then
  echo "[*] Step 7: LAN guard disabled (LAN_GUARD=off in .env)."
  if [[ -f /etc/systemd/system/pibot-lan-guard.service ]]; then
    sudo systemctl disable --now pibot-lan-guard || true
    sudo rm -f /etc/systemd/system/pibot-lan-guard.service
    sudo systemctl daemon-reload
  fi
else
  echo "[*] Step 7: Installing the LAN guard firewall..."
  if [[ ! -x /usr/sbin/nft ]]; then
    echo "[-] Error: nftables is not installed. Run: sudo apt-get install -y nftables"
    echo "    (or set LAN_GUARD=off in .env to skip the firewall)."
    exit 1
  fi
  BOT_UIDS="$(printf '%s\n' "$(id -u "${APPLIANCE_USER}")" "$(id -u)" | sort -u | paste -sd, - | sed 's/,/, /g')"
  sudo mkdir -p /etc/pibot
  sed "s|__BOT_UIDS__|${BOT_UIDS}|g" "${REPO_ROOT}/systemd/pibot-lan-guard.nft" | sudo tee /etc/pibot/lan-guard.nft > /dev/null
  sudo nft -c -f /etc/pibot/lan-guard.nft
  sudo cp "${REPO_ROOT}/systemd/pibot-lan-guard.service" /etc/systemd/system/pibot-lan-guard.service
  sudo systemctl daemon-reload
  sudo systemctl enable pibot-lan-guard
  sudo systemctl restart pibot-lan-guard
  echo "[+] LAN guard active for UID(s) ${BOT_UIDS}: no access to other local-network devices."
fi

# Step 8: Install systemd units
echo "[*] Step 8: Installing and (re)starting systemd services..."

# System service for agy-shim
sed -e "s|__APPLIANCE_USER__|${APPLIANCE_USER}|g" \
    -e "s|__WORKSPACE_ROOT__|${WORKSPACE_ROOT}|g" \
    -e "s|__HOME__|${HOME}|g" \
    -e "s|__SHIM_ENV_FILE__|${SHIM_ENV_FILE}|g" \
    "${REPO_ROOT}/systemd/agy-shim.service" | sudo tee /etc/systemd/system/agy-shim.service > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable agy-shim
sudo systemctl restart agy-shim
echo "[+] agy-shim system service configured and started."

# User service for zeroclaw
cp "${REPO_ROOT}/systemd/zeroclaw.service" "${HOME}/.config/systemd/user/zeroclaw.service"
systemctl --user daemon-reload
systemctl --user enable zeroclaw
systemctl --user restart zeroclaw
echo "[+] zeroclaw user service enabled and started."

# Without lingering, the user service only runs while someone is logged in.
if ! loginctl show-user "${USER}" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
  sudo loginctl enable-linger "${USER}"
  echo "[+] Enabled systemd lingering so piBot starts at boot."
fi

echo "============================================================"
echo " Setup complete! Run '${REPO_ROOT}/scripts/verify.sh' to verify."
echo "============================================================"
