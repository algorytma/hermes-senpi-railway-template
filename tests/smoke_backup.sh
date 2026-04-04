#!/usr/bin/env bash
# =============================================================================
# tests/smoke_backup.sh — Backup/Restore Round-trip Smoke Test
# =============================================================================
# Run locally to verify backup + restore works end-to-end.
#
# Usage:
#   bash tests/smoke_backup.sh
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/hermes-smoke-backup-$$"
SOURCE_DIR="${TEST_DIR}/source"
RESTORE_DIR="${TEST_DIR}/restore"
BACKUP_FILE="${TEST_DIR}/test-backup.tar.gz"

log()  { echo "[smoke_backup] $*"; }
pass() { echo "[smoke_backup] PASS: $*"; }
fail() { echo "[smoke_backup] FAIL: $*" >&2; exit 1; }

cleanup() {
  rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

log "Setting up source /data..."
mkdir -p \
  "${SOURCE_DIR}/providers" \
  "${SOURCE_DIR}/mcp" \
  "${SOURCE_DIR}/risk" \
  "${SOURCE_DIR}/workspace" \
  "${SOURCE_DIR}/skills/manifests" \
  "${SOURCE_DIR}/logs/audit" \
  "${SOURCE_DIR}/.hermes/analysis/sessions" \
  "${SOURCE_DIR}/.hermes/execution"

cp "${REPO_ROOT}/config/providers/provider_registry.example.yaml" \
   "${SOURCE_DIR}/providers/provider_registry.yaml"
cp "${REPO_ROOT}/config/mcp_registry.example.yaml" \
   "${SOURCE_DIR}/mcp/mcp_registry.yaml"
cp "${REPO_ROOT}/config/risk_policy.example.yaml" \
   "${SOURCE_DIR}/risk/risk_policy.yaml"

echo "Test workspace content" > "${SOURCE_DIR}/workspace/AGENTS.md"
echo "session-token-abc123" > "${SOURCE_DIR}/.hermes/analysis/sessions/session.json"
echo "# GENERATED" > "${SOURCE_DIR}/.hermes/analysis/config.generated.yaml"
echo "audit-2026-01-01 trade XYZ" > "${SOURCE_DIR}/logs/audit/trades.log"

# --- Create backup ---
log "Creating backup..."
DATA_DIR="${SOURCE_DIR}" \
ACTIVE_PROFILE=analysis \
HERMES_VERSION=v0.6.0-test \
  bash "${REPO_ROOT}/scripts/backup-export.sh" --output "${BACKUP_FILE}"

if [[ ! -f "${BACKUP_FILE}" ]]; then
  fail "Backup file not created: ${BACKUP_FILE}"
fi
pass "Backup file created: ${BACKUP_FILE}"

# --- Verify archive ---
log "Verifying archive..."
tar -tzf "${BACKUP_FILE}" > /dev/null
ENTRY_COUNT=$(tar -tzf "${BACKUP_FILE}" | wc -l)
pass "Archive verified — ${ENTRY_COUNT} entries"

# Security: sessions must NOT be in archive
if tar -tzf "${BACKUP_FILE}" | grep -q "sessions/"; then
  fail "SECURITY: session directory included in backup"
fi
pass "Sessions correctly excluded from backup"

# Security: generated configs must NOT be in archive
if tar -tzf "${BACKUP_FILE}" | grep -q "config.generated.yaml"; then
  fail "SECURITY: generated config included in backup"
fi
pass "Generated configs correctly excluded from backup"

# Audit logs should be included
if ! tar -tzf "${BACKUP_FILE}" | grep -q "logs/audit"; then
  fail "Audit logs NOT in backup — expected to be included"
fi
pass "Audit logs correctly included in backup"

# --- Restore ---
log "Restoring backup to ${RESTORE_DIR}..."
mkdir -p "${RESTORE_DIR}"
DATA_DIR="${RESTORE_DIR}" \
  bash "${REPO_ROOT}/scripts/backup-restore.sh" "${BACKUP_FILE}" --yes

# --- Verify restore ---
if [[ ! -f "${RESTORE_DIR}/providers/provider_registry.yaml" ]]; then
  fail "provider_registry.yaml not restored"
fi
pass "provider_registry.yaml restored"

if [[ ! -f "${RESTORE_DIR}/risk/risk_policy.yaml" ]]; then
  fail "risk_policy.yaml not restored"
fi
pass "risk_policy.yaml restored"

if [[ ! -f "${RESTORE_DIR}/workspace/AGENTS.md" ]]; then
  fail "AGENTS.md not restored"
fi
pass "workspace/AGENTS.md restored"

# Generated configs must have been deleted after restore
if find "${RESTORE_DIR}" -name "config.generated.yaml" -print | grep -q .; then
  fail "Generated config found in restore — should have been deleted"
fi
pass "Generated configs correctly absent after restore"

# Sessions must not be in restore
if find "${RESTORE_DIR}" -name "sessions" -type d | grep -q .; then
  fail "Sessions directory found in restore — should not be present"
fi
pass "Sessions correctly absent in restore"

log ""
log "========================================"
log "All smoke_backup tests passed ✓"
log "========================================"
