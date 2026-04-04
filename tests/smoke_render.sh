#!/usr/bin/env bash
# =============================================================================
# tests/smoke_render.sh — Config Render Smoke Test
# =============================================================================
# Run locally to test that render-config.py works with fixture data.
#
# Usage:
#   bash tests/smoke_render.sh
#   OPENROUTER_API_KEY=sk-test bash tests/smoke_render.sh
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${REPO_ROOT}/tests/fixtures"
TEST_DATA_DIR="${FIXTURE_DIR}/data"

log()  { echo "[smoke_render] $*"; }
pass() { echo "[smoke_render] PASS: $*"; }
fail() { echo "[smoke_render] FAIL: $*" >&2; exit 1; }

log "Setting up test data directory..."
mkdir -p "${TEST_DATA_DIR}/providers"
mkdir -p "${TEST_DATA_DIR}/mcp"
mkdir -p "${TEST_DATA_DIR}/risk"
mkdir -p "${TEST_DATA_DIR}/workspace"

cp "${REPO_ROOT}/config/providers/provider_registry.example.yaml" \
   "${TEST_DATA_DIR}/providers/provider_registry.yaml"
cp "${REPO_ROOT}/config/providers/model_aliases.example.yaml" \
   "${TEST_DATA_DIR}/providers/model_aliases.yaml"
cp "${REPO_ROOT}/config/mcp_registry.example.yaml" \
   "${TEST_DATA_DIR}/mcp/mcp_registry.yaml"

echo "# Test workspace" > "${TEST_DATA_DIR}/workspace/AGENTS.md"

# --- Test 1: Validate-only ---
log "Test 1: --validate-only..."
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-test-key-smoke}" \
DATA_DIR="${TEST_DATA_DIR}" \
  python3 "${REPO_ROOT}/scripts/render-config.py" \
    --validate-only \
    --data-dir "${TEST_DATA_DIR}"
pass "validate-only passed"

# --- Test 2: Analysis dry-run ---
log "Test 2: analysis profile dry-run..."
OUTPUT=$(
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-test-key-smoke}" \
  DATA_DIR="${TEST_DATA_DIR}" \
    python3 "${REPO_ROOT}/scripts/render-config.py" \
      --profile analysis \
      --data-dir "${TEST_DATA_DIR}" \
      --dry-run 2>&1
)

# Security: API key value must NOT appear in output
if echo "${OUTPUT}" | grep -q "${OPENROUTER_API_KEY:-test-key-smoke}"; then
  fail "SECURITY: API key value leaked into rendered output"
fi
pass "analysis dry-run — no API key value in output"

# Senpi must be blocked in analysis
if echo "${OUTPUT}" | grep -q "senpi.*command\|command.*senpi"; then
  fail "SECURITY: Senpi MCP appears active in analysis profile output"
fi
pass "analysis profile: Senpi MCP correctly excluded"

# --- Test 3: Execution dry-run ---
log "Test 3: execution profile dry-run..."
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-test-key-smoke}" \
SENPI_AUTH_TOKEN="${SENPI_AUTH_TOKEN:-senpi-test}" \
DATA_DIR="${TEST_DATA_DIR}" \
  python3 "${REPO_ROOT}/scripts/render-config.py" \
    --profile execution \
    --data-dir "${TEST_DATA_DIR}" \
    --dry-run > /dev/null 2>&1
pass "execution profile dry-run completed"

# --- Cleanup ---
rm -rf "${TEST_DATA_DIR}"

log ""
log "========================================"
log "All smoke_render tests passed ✓"
log "========================================"
