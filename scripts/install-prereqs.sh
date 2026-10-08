#!/usr/bin/env bash
# ==============================================================================
# scripts/install-prereqs.sh
# Installs core dependencies for piBot on Debian/Ubuntu Linux (ARM64/x86_64).
# Installs: Go (>=1.24), Python 3, Antigravity CLI (agy), ZeroClaw
# ==============================================================================

set -euo pipefail

ZEROCLAW_VERSION="${ZEROCLAW_VERSION:-0.8.5}"
AGY_VERSION="${AGY_VERSION:-1.2.14}"

echo "=== [1/5] Updating package lists & installing base tools ==="
sudo apt-get update -y
sudo apt-get install -y \
  curl \
  git \
  build-essential \
  python3 \
  python3-pip \
  golang-go \
  ca-certificates

echo "=== [2/5] Enabling systemd user lingering ==="
# User lingering allows the zeroclaw user systemd service to start on boot without an interactive login
loginctl enable-linger "${USER}" || true
echo "[+] User lingering enabled for ${USER}."

echo "=== [3/5] Installing Antigravity CLI (agy ~v${AGY_VERSION}) ==="
if ! command -v agy &>/dev/null && [[ ! -x "${HOME}/.local/bin/agy" ]]; then
  echo "[*] Downloading and installing Antigravity CLI..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
fi

if [[ -f "${HOME}/.local/bin/agy" && ! -L "/usr/local/bin/agy" ]]; then
  echo "[*] Creating /usr/local/bin/agy symlink..."
  sudo ln -sf "${HOME}/.local/bin/agy" /usr/local/bin/agy
fi

echo "=== [4/5] Installing ZeroClaw (pinned v${ZEROCLAW_VERSION}) ==="
if ! command -v zeroclaw &>/dev/null && [[ ! -x "${HOME}/.cargo/bin/zeroclaw" ]]; then
  ARCH="$(uname -m)"
  case "${ARCH}" in
    aarch64|arm64) TARGET_TRIPLE="aarch64-unknown-linux-gnu" ;;
    x86_64|amd64)  TARGET_TRIPLE="x86_64-unknown-linux-gnu" ;;
    *)             TARGET_TRIPLE="" ;;
  esac

  mkdir -p "${HOME}/.cargo/bin"
  if [[ -n "${TARGET_TRIPLE}" ]]; then
    echo "[*] Downloading pinned ZeroClaw v${ZEROCLAW_VERSION} (${TARGET_TRIPLE})..."
    curl -fsSL "https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${ZEROCLAW_VERSION}/zeroclaw-${TARGET_TRIPLE}.tar.gz" | tar -xz -C "${HOME}/.cargo/bin"
    chmod +x "${HOME}/.cargo/bin/zeroclaw"
  else
    echo "[*] Falling back to ZeroClaw installer script..."
    curl -fsSL https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/install.sh | sh -s -- --prebuilt --skip-quickstart
  fi
fi

# Ensure ~/.cargo/bin and ~/.local/bin are in PATH for current and future sessions
if ! grep -q 'cargo/bin' "${HOME}/.bashrc" 2>/dev/null; then
  # shellcheck disable=SC2016
  echo 'export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
fi
export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

echo "=== [5/5] Verification ==="
echo "Go version:        $(go version 2>/dev/null || echo 'not found')"
echo "Antigravity CLI:   $(agy --version 2>/dev/null || echo 'not found')"
echo "ZeroClaw version:  $(zeroclaw --version 2>/dev/null || echo 'not found')"
echo "[+] Prerequisites installation complete!"
