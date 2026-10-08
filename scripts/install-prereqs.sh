#!/usr/bin/env bash
# ==============================================================================
# scripts/install-prereqs.sh
# Installs core dependencies for piBot on Debian/Ubuntu Linux (ARM64/x86_64).
# Installs: Go, Python 3, Antigravity CLI (agy), ZeroClaw (checksum-verified)
# ==============================================================================

set -euo pipefail

ZEROCLAW_VERSION="${ZEROCLAW_VERSION:-0.8.5}"

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
# (needs root: without sudo, polkit denies it in non-interactive sessions)
if sudo loginctl enable-linger "${USER}"; then
  echo "[+] User lingering enabled for ${USER}."
else
  echo "[-] Warning: could not enable lingering; piBot will only run while ${USER} is logged in."
fi

echo "=== [3/5] Installing Antigravity CLI (agy, latest release) ==="
# Google's installer always fetches the latest release (it verifies the
# download checksum itself); it does not support pinning a version.
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
    armv7l)        TARGET_TRIPLE="armv7-unknown-linux-gnueabihf" ;;
    *)
      echo "[-] Error: unsupported architecture '${ARCH}'. Use a 64-bit OS (see docs/HARDWARE.md)."
      exit 1
      ;;
  esac

  RELEASE_URL="https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${ZEROCLAW_VERSION}"
  ASSET="zeroclaw-${TARGET_TRIPLE}.tar.gz"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT

  echo "[*] Downloading pinned ZeroClaw v${ZEROCLAW_VERSION} (${TARGET_TRIPLE})..."
  curl -fsSL -o "${TMP_DIR}/${ASSET}" "${RELEASE_URL}/${ASSET}"
  curl -fsSL -o "${TMP_DIR}/SHA256SUMS" "${RELEASE_URL}/SHA256SUMS"

  echo "[*] Verifying SHA-256 checksum..."
  if ! (cd "${TMP_DIR}" && grep -E "[[:space:]]\*?${ASSET}\$" SHA256SUMS | sha256sum -c --status -); then
    echo "[-] Error: checksum verification failed for ${ASSET}. Aborting."
    exit 1
  fi

  mkdir -p "${HOME}/.cargo/bin"
  tar -xzf "${TMP_DIR}/${ASSET}" -C "${HOME}/.cargo/bin" zeroclaw
  chmod +x "${HOME}/.cargo/bin/zeroclaw"
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
