#!/usr/bin/env bash
# ==============================================================================
# scripts/verify.sh
# Diagnostic verification for piBot services.
# ==============================================================================

set -euo pipefail

export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

echo "============================================================"
echo " piBot Diagnostic Verification"
echo "============================================================"

FAILED=0

# 1. Check Antigravity CLI
echo -n "[*] 1. Checking Antigravity CLI (agy)... "
if agy --version &>/dev/null; then
  echo "OK ($(agy --version))"
else
  echo "FAILED"
  FAILED=1
fi

# 2. Check agy-shim HTTP health
echo -n "[*] 2. Checking agy-shim health endpoint (http://127.0.0.1:8088/health)... "
HEALTH_RESP=$(curl -s --max-time 3 http://127.0.0.1:8088/health || true)
if [[ "${HEALTH_RESP}" == *"status"*"ok"* ]]; then
  echo "OK (${HEALTH_RESP})"
else
  echo "FAILED (${HEALTH_RESP:-No response})"
  FAILED=1
fi

# 3. Check systemd services
echo -n "[*] 3. Checking agy-shim systemd service... "
if systemctl is-active --quiet agy-shim; then
  echo "ACTIVE (running)"
else
  echo "INACTIVE or FAILED"
  FAILED=1
fi

echo -n "[*] 4. Checking zeroclaw user systemd service... "
if systemctl --user is-active --quiet zeroclaw; then
  echo "ACTIVE (running)"
else
  echo "INACTIVE or FAILED"
  FAILED=1
fi

# 4. Run ZeroClaw Doctor
echo ""
echo "[*] 5. Running ZeroClaw Doctor..."
if ! zeroclaw doctor; then
  echo "[-] ZeroClaw Doctor check FAILED."
  FAILED=1
else
  echo "[+] ZeroClaw Doctor check PASSED."
fi

# 5. Run ZeroClaw Channel Doctor
echo ""
echo "[*] 6. Running ZeroClaw Channel Doctor..."
if ! zeroclaw channel doctor; then
  echo "[-] ZeroClaw Channel Doctor check FAILED."
  FAILED=1
else
  echo "[+] ZeroClaw Channel Doctor check PASSED."
fi

echo ""
echo "============================================================"
if [[ "${FAILED}" -eq 0 ]]; then
  echo " [✓] All core piBot health checks PASSED!"
else
  echo " [✗] One or more health checks FAILED. Review output above."
fi
echo "============================================================"
exit "${FAILED}"
