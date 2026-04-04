#!/usr/bin/env bash
# =============================================================================
# tests/validate_risk_test.sh — Risk Policy Validation Unit Tests
# =============================================================================
# Tests validate-risk.sh against various risk policy configurations.
#
# Usage:
#   bash tests/validate_risk_test.sh
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BASE="/tmp/hermes-risk-tests-$$"
PASS=0
FAIL=0

log()  { echo "[risk_test ] $*"; }
pass() { echo "[risk_test ] PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "[risk_test ] FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

cleanup() { rm -rf "${TEST_BASE}"; }
trap cleanup EXIT

make_data_dir() {
  local name="${1}"
  local dir="${TEST_BASE}/${name}"
  mkdir -p "${dir}/risk"
  echo "${dir}"
}

write_policy() {
  local dir="${1}"
  shift
  cat > "${dir}/risk/risk_policy.yaml" << EOF
$*
EOF
}

run_validate() {
  local dir="${1}"
  DATA_DIR="${dir}" bash "${REPO_ROOT}/bootstrap/validate-risk.sh" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Test 1: Valid policy — should pass
# ---------------------------------------------------------------------------
D=$(make_data_dir "valid")
write_policy "${D}" "
version: '1'
mode: copilot
trading:
  max_leverage: 3
  max_position_size_usd: 300
  max_daily_loss_usd: 100
symbols:
  allowlist: ['BTC', 'ETH']
  default_action: deny
execution:
  dry_run_default: true
  allow_open_new_position: false
"
if run_validate "${D}"; then
  pass "Valid policy accepted"
else
  fail "Valid policy was rejected"
fi

# ---------------------------------------------------------------------------
# Test 2: default_action=allow — must fail
# ---------------------------------------------------------------------------
D=$(make_data_dir "allow_action")
write_policy "${D}" "
mode: copilot
trading:
  max_leverage: 3
  max_position_size_usd: 100
  max_daily_loss_usd: 50
symbols:
  allowlist: ['BTC']
  default_action: allow
execution:
  dry_run_default: true
  allow_open_new_position: false
"
if run_validate "${D}"; then
  fail "default_action=allow should have been rejected"
else
  pass "default_action=allow correctly rejected"
fi

# ---------------------------------------------------------------------------
# Test 3: Empty allowlist — must fail
# ---------------------------------------------------------------------------
D=$(make_data_dir "empty_allowlist")
write_policy "${D}" "
mode: copilot
trading:
  max_leverage: 3
  max_position_size_usd: 100
  max_daily_loss_usd: 50
symbols:
  allowlist: []
  default_action: deny
execution:
  dry_run_default: true
  allow_open_new_position: false
"
if run_validate "${D}"; then
  fail "Empty allowlist should have been rejected"
else
  pass "Empty allowlist correctly rejected"
fi

# ---------------------------------------------------------------------------
# Test 4: Leverage > 10 — must fail
# ---------------------------------------------------------------------------
D=$(make_data_dir "high_leverage")
write_policy "${D}" "
mode: copilot
trading:
  max_leverage: 11
  max_position_size_usd: 100
  max_daily_loss_usd: 50
symbols:
  allowlist: ['BTC']
  default_action: deny
execution:
  dry_run_default: true
  allow_open_new_position: false
"
if run_validate "${D}"; then
  fail "Leverage > 10 should have been rejected"
else
  pass "Leverage > 10 correctly rejected"
fi

# ---------------------------------------------------------------------------
# Test 5: Invalid mode — must fail
# ---------------------------------------------------------------------------
D=$(make_data_dir "invalid_mode")
write_policy "${D}" "
mode: yolo
trading:
  max_leverage: 3
  max_position_size_usd: 100
  max_daily_loss_usd: 50
symbols:
  allowlist: ['BTC']
  default_action: deny
execution:
  dry_run_default: true
  allow_open_new_position: false
"
if run_validate "${D}"; then
  fail "Invalid mode 'yolo' should have been rejected"
else
  pass "Invalid mode correctly rejected"
fi

# ---------------------------------------------------------------------------
# Test 6: dry_run_default as string instead of bool — must fail
# ---------------------------------------------------------------------------
D=$(make_data_dir "string_bool")
write_policy "${D}" "
mode: copilot
trading:
  max_leverage: 3
  max_position_size_usd: 100
  max_daily_loss_usd: 50
symbols:
  allowlist: ['BTC']
  default_action: deny
execution:
  dry_run_default: \"true\"
  allow_open_new_position: false
"
if run_validate "${D}"; then
  fail "String 'true' for dry_run_default should have been rejected (must be YAML bool)"
else
  pass "String 'true' for dry_run_default correctly rejected"
fi

# ---------------------------------------------------------------------------
# Test 7: Missing file — must fail
# ---------------------------------------------------------------------------
D=$(make_data_dir "missing")
# Don't write a policy file
if run_validate "${D}"; then
  fail "Missing risk_policy.yaml should have been rejected"
else
  pass "Missing risk_policy.yaml correctly rejected"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Risk validation tests: ${PASS} passed, ${FAIL} failed"
echo "========================================"

[[ ${FAIL} -eq 0 ]] || exit 1
