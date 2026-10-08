#!/usr/bin/env bash
# ==============================================================================
# scripts/verify.sh
# Diagnostic verification for piBot services.
# Exits non-zero if any check fails.
# ==============================================================================

set -uo pipefail

export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAN_GUARD="$(sed -n 's/^LAN_GUARD=//p' "${REPO_ROOT}/.env" 2>/dev/null | tr -d '"')"

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

# 2. Check agy-shim HTTP health and auth
echo -n "[*] 2. Checking agy-shim health endpoint (${SHIM_URL}/health)... "
HEALTH_RESP=$(curl -s --max-time 3 "${SHIM_URL}/health" || true)
if [[ "${HEALTH_RESP}" == *"status"*"ok"* ]]; then
  echo "OK (${HEALTH_RESP})"
else
  fail "${HEALTH_RESP:-No response}"
fi

echo -n "[*] 3. Checking agy-shim rejects unauthenticated requests... "
UNAUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -X POST \
  -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"ping"}]}' \
  "${SHIM_URL}/v1/chat/completions" || true)
if [[ "${UNAUTH_CODE}" == "401" ]]; then
  echo "OK (401)"
else
  fail "expected 401, got ${UNAUTH_CODE:-no response}"
fi

# 4. End-to-end: send a tiny prompt through agy-shim, the same path a Telegram
# message takes. This checks the shim token, agy, your Google sign-in and the
# model name together. (Running `agy` directly from a terminal is not a good
# test: with a terminal attached it may wait for interactive input.)
echo -n "[*] 4. Checking a test prompt through agy-shim -> agy (up to 120s)... "
SHIM_TOKEN="$(sed -n 's/^AGY_SHIM_TOKEN=//p' "${SHIM_ENV_FILE}" 2>/dev/null)"
if [[ -z "${SHIM_TOKEN}" ]]; then
  fail "no token in ${SHIM_ENV_FILE}; run ./scripts/setup.sh"
else
  E2E_DIR="$(mktemp -d)"
  # Pass the token via a private header file so it never shows up in `ps`
  (umask 077 && printf 'Authorization: Bearer %s\n' "${SHIM_TOKEN}" > "${E2E_DIR}/auth")
  E2E_CODE=$(curl -s -o "${E2E_DIR}/body" -w '%{http_code}' --max-time 120 -X POST \
    -H @"${E2E_DIR}/auth" -H 'Content-Type: application/json' \
    -d '{"model":"agy-gemini-medium","messages":[{"role":"user","content":"Reply with exactly: OK"}]}' \
    "${SHIM_URL}/v1/chat/completions" || true)
  E2E_REPLY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["choices"][0]["message"]["content"].strip()[:40])' "${E2E_DIR}/body" 2>/dev/null)"
  rm -rf "${E2E_DIR}"
  if [[ "${E2E_CODE}" == "200" && -n "${E2E_REPLY}" ]]; then
    echo "OK (agy replied: ${E2E_REPLY})"
  elif [[ "${E2E_CODE}" == "000" ]]; then
    fail "no answer within 120s. Is agy signed in? Run 'agy' once to sign in. Details: sudo journalctl -u agy-shim -n 20"
  else
    fail "agy-shim returned HTTP ${E2E_CODE}. Is agy signed in? Run 'agy' once to sign in. Details: sudo journalctl -u agy-shim -n 20"
  fi
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

# 8. LAN guard: the bot's account must not be able to reach other local devices.
# A ping to the router is rejected by the firewall with "Packet filtered" (or
# "not permitted"); any real reply or timeout means the packet got out.
echo -n "[*] 8. Checking the LAN guard blocks other local-network devices... "
if [[ "${LAN_GUARD:-on}" == "off" ]]; then
  echo "SKIPPED (LAN_GUARD=off in .env)"
elif ! systemctl is-active --quiet pibot-lan-guard; then
  fail "pibot-lan-guard service not active; rerun ./scripts/setup.sh (see docs/SECURITY.md)"
else
  GATEWAY="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  if [[ -z "${GATEWAY}" ]]; then
    echo "OK (service active; no default gateway to test against)"
  else
    PING_OUT="$(ping -c1 -W2 "${GATEWAY}" 2>&1)"
    if [[ "${PING_OUT}" == *"Packet filtered"* || "${PING_OUT}" == *"not permitted"* ]]; then
      echo "OK (router ${GATEWAY} is unreachable for the bot)"
    else
      fail "the bot's account can still reach ${GATEWAY}; rerun ./scripts/setup.sh"
    fi
  fi
fi

# Right after setup.sh restarts ZeroClaw, its channels have not reported in yet
# and the doctor would flag them as "stale". Give a fresh start time to settle.
SETTLE_SECS=60
START_US="$(systemctl --user show zeroclaw -p ActiveEnterTimestampMonotonic --value 2>/dev/null)"
NOW_US="$(awk '{printf "%d", $1 * 1000000}' /proc/uptime)"
if [[ "${START_US:-0}" =~ ^[0-9]+$ && "${START_US:-0}" -gt 0 ]]; then
  UP_SECS=$(( (NOW_US - START_US) / 1000000 ))
  if (( UP_SECS < SETTLE_SECS )); then
    echo ""
    echo "[*] ZeroClaw started ${UP_SECS}s ago; waiting $(( SETTLE_SECS - UP_SECS ))s for it to finish connecting..."
    sleep $(( SETTLE_SECS - UP_SECS ))
  fi
fi

# 9. Run ZeroClaw Doctor. It exits 0 even when it reports errors, so check its output.
# "live model listing is not supported" is expected for the custom agy provider.
echo ""
echo "[*] 9. Running ZeroClaw Doctor..."
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

# 10. Run ZeroClaw Channel Doctor (same exit-code caveat)
echo ""
echo "[*] 10. Running ZeroClaw Channel Doctor..."
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
