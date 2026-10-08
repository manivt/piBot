#!/usr/bin/env bash
# ==============================================================================
# scripts/setup.sh
# End-to-end setup script for piBot.
# Builds agy-shim, configures ZeroClaw, sets up agent workspace files, and starts systemd services.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

echo "============================================================"
echo " piBot Setup"
echo "============================================================"

# Step 1: Pre-flight checks
echo "[*] Step 1: Checking required CLI tools..."
for cmd in go agy zeroclaw python3; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "[-] Error: Required command '${cmd}' not found in PATH."
    echo "    Please run '${REPO_ROOT}/scripts/install-prereqs.sh' first."
    exit 1
  fi
done
echo "[+] All required tools found."

# Load configuration if present
ENV_FILE="${REPO_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

APPLIANCE_USER="${APPLIANCE_USER:-${USER}}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${HOME}/workspaces}"
AGENT_NAME="${AGENT_NAME:-pibot}"

# Step 2: Ensure workspace directories exist
echo "[*] Step 2: Preparing directory layout..."
mkdir -p "${WORKSPACE_ROOT}/agy-shim"
mkdir -p "${HOME}/.zeroclaw/agents/${AGENT_NAME}/workspace"
mkdir -p "${HOME}/.config/systemd/user"

# Step 3: Build agy-shim
echo "[*] Step 3: Compiling agy-shim bridge..."
cp "${REPO_ROOT}/agy-shim/main.go" "${WORKSPACE_ROOT}/agy-shim/main.go"
cp "${REPO_ROOT}/agy-shim/go.mod" "${WORKSPACE_ROOT}/agy-shim/go.mod"
(
  cd "${WORKSPACE_ROOT}/agy-shim"
  go build -o agy-shim main.go
)
echo "[+] agy-shim compiled successfully at ${WORKSPACE_ROOT}/agy-shim/agy-shim"

# Step 4: Deploy Agent prompt files
echo "[*] Step 4: Deploying piBot workspace prompt files..."
cp "${REPO_ROOT}/agent/workspace/"*.md "${HOME}/.zeroclaw/agents/${AGENT_NAME}/workspace/"
echo "[+] Workspace files deployed to ${HOME}/.zeroclaw/agents/${AGENT_NAME}/workspace/"

# Step 5: Render ZeroClaw configuration
echo "[*] Step 5: Configuring ZeroClaw..."
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[-] Warning: ${ENV_FILE} does not exist."
  echo "    Creating ${ENV_FILE} from .env.example..."
  cp "${REPO_ROOT}/.env.example" "${ENV_FILE}"
  echo "    PLEASE EDIT ${ENV_FILE} and set your TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USERS before continuing."
  exit 1
fi

"${REPO_ROOT}/scripts/render-config.sh" "${HOME}/.zeroclaw/config.toml"

# Step 6: Install systemd units
echo "[*] Step 6: Installing and starting systemd services..."

# System service for agy-shim
sed -e "s|__APPLIANCE_USER__|${APPLIANCE_USER}|g" \
    -e "s|__WORKSPACE_ROOT__|${WORKSPACE_ROOT}|g" \
    -e "s|__HOME__|${HOME}|g" \
    "${REPO_ROOT}/systemd/agy-shim.service" | sudo tee /etc/systemd/system/agy-shim.service > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now agy-shim
echo "[+] agy-shim system service configured and started."

# User service for zeroclaw
cp "${REPO_ROOT}/systemd/zeroclaw.service" "${HOME}/.config/systemd/user/zeroclaw.service"
systemctl --user daemon-reload
systemctl --user enable --now zeroclaw
echo "[+] zeroclaw user service enabled and started."

echo "============================================================"
echo " Setup complete! Run '${REPO_ROOT}/scripts/verify.sh' to verify."
echo "============================================================"
