#!/usr/bin/env bash
# ==============================================================================
# scripts/verify.sh
# Diagnostic verification for piBot services.
# Exits non-zero if any check fails.
# ==============================================================================

set -uo pipefail

export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

SHIM_ENV_FILE="${HOME}/.config/pibot/agy-shim.env"
AGY_SHIM_PORT=8088
if [[ -f "${SHIM_ENV_FILE}" ]]; then
  AGY_SHIM_PORT="$(sed -n 's/^AGY_SHIM_PORT=//p' "${SHIM_ENV_FILE}")"
fi
SHIM_URL="http://127.0.0.1:${AGY_SHIM_PORT:-8088}"

echo "============================================================"
echo " piBot Diagnostic Verification"
echo "============================================================"

FAILED=0
fail() { echo "FAILED${1:+ ($1)}"; FAILED=1; }

# 1. Check Antigravity CLI
echo -n "[*] 1. Checking Antigravity CLI (agy)... "
if agy --version &>/dev/null; then
  echo "OK ($(agy --version))"
else
  fail
fi

echo -n "[*] 2. Checking agy answers a test prompt (up to 90s)... "
# Use print mode (-p), exactly like agy-shim does. Other subcommands such as
# `agy models` can open an interactive picker on the terminal and never return.
# Write to a file rather than using $(...): agy can leave helper processes
# holding stdout open, which would make a command substitution wait forever.
AGY_OUT_FILE="$(mktemp)"
(
  cd "${WORKSPACE_ROOT:-${HOME}/workspaces}" 2>/dev/null || cd "${HOME}"
  timeout -k 5 90 agy -p "Reply with exactly: OK" --output-format json </dev/null >"${AGY_OUT_FILE}" 2>&1
)
AGY_RC=$?
AGY_STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "${AGY_OUT_FILE}" 2>/dev/null)"
AGY_OUT="$(cat "${AGY_OUT_FILE}")"
rm -f "${AGY_OUT_FILE}"
if [[ "${AGY_OUT}" == *"Authentication required"* || "${AGY_OUT}" == *"sign in"* ]]; then
  fail "not signed in: run 'agy' once and complete the Google sign-in"
elif [[ "${AGY_RC}" -eq 124 || "${AGY_RC}" -eq 137 ]]; then
  fail "agy did not answer within 90s"
elif [[ "${AGY_STATUS^^}" == "SUCCESS" ]]; then
  echo "OK"
else
  fail "unexpected agy result: $(head -c 200 <<< "${AGY_OUT}")"
fi

# 3. Check agy-shim HTTP health and auth
echo -n "[*] 3. Checking agy-shim health endpoint (${SHIM_URL}/health)... "
HEALTH_RESP=$(curl -s --max-time 3 "${SHIM_URL}/health" || true)
if [[ "${HEALTH_RESP}" == *"status"*"ok"* ]]; then
  echo "OK (${HEALTH_RESP})"
else
  fail "${HEALTH_RESP:-No response}"
fi

echo -n "[*] 4. Checking agy-shim rejects unauthenticated requests... "
UNAUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -X POST \
  -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"ping"}]}' \
  "${SHIM_URL}/v1/chat/completions" || true)
if [[ "${UNAUTH_CODE}" == "401" ]]; then
  echo "OK (401)"
else
  fail "expected 401, got ${UNAUTH_CODE:-no response}"
fi

# 5. Check systemd services
echo -n "[*] 5. Checking agy-shim systemd service... "
if systemctl is-active --quiet agy-shim; then
  echo "ACTIVE (running)"
else
  fail "inactive"
fi

echo -n "[*] 6. Checking zeroclaw user systemd service... "
if systemctl --user is-active --quiet zeroclaw; then
  echo "ACTIVE (running)"
else
  fail "inactive"
fi

echo -n "[*] 7. Checking piBot starts at boot (systemd lingering)... "
if loginctl show-user "${USER}" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
  echo "OK"
else
  fail "run: sudo loginctl enable-linger ${USER}"
fi

# 8. Run ZeroClaw Doctor. It exits 0 even when it reports errors, so check its output.
# "live model listing is not supported" is expected for the custom agy provider.
echo ""
echo "[*] 8. Running ZeroClaw Doctor..."
DOCTOR_OUT="$(zeroclaw doctor 2>&1)"
echo "${DOCTOR_OUT}"
DOCTOR_ERRORS="$(grep '❌' <<< "${DOCTOR_OUT}" | grep -v 'live model listing is not supported' || true)"
if [[ -n "${DOCTOR_ERRORS}" ]]; then
  echo "[-] ZeroClaw Doctor check FAILED:"
  echo "${DOCTOR_ERRORS}"
  FAILED=1
else
  echo "[+] ZeroClaw Doctor check PASSED."
fi

# 9. Run ZeroClaw Channel Doctor (same exit-code caveat)
echo ""
echo "[*] 9. Running ZeroClaw Channel Doctor..."
CHANNEL_OUT="$(zeroclaw channel doctor 2>&1)"
echo "${CHANNEL_OUT}"
if grep -q '❌' <<< "${CHANNEL_OUT}"; then
  echo "[-] ZeroClaw Channel Doctor check FAILED (check TELEGRAM_BOT_TOKEN and network)."
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
