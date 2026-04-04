#!/usr/bin/env bash
# =============================================================================
# scripts/backup-restore.sh — Volume Restore from Backup Archive
# =============================================================================
# Restores /data from a previously created backup-export.sh archive.
#
# Usage:
#   bash scripts/backup-restore.sh <backup.tar.gz>
#   bash scripts/backup-restore.sh <backup.tar.gz> --yes   # skip confirmation
#
# BEHAVIOR:
#   - Sessions are NOT restored (cleared before extraction for security)
#   - Generated configs are deleted after restore (regenerated on next boot)
#   - Migrations run on next container start (run-migrations.sh)
#   - The restore is idempotent: running twice gives the same result
#
# SECURITY:
#   - Archive entries starting with '/' or containing '..' are rejected
#   - API keys are not in the archive — they come from env vars
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
BACKUP_FILE="${1:-}"
SKIP_CONFIRM="${2:-}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REST ] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REST ] WARN: $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REST ] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Parameter validation
# ---------------------------------------------------------------------------
if [[ -z "${BACKUP_FILE}" ]]; then
  echo "Usage: backup-restore.sh <backup.tar.gz> [--yes]" >&2
  exit 1
fi

if [[ ! -f "${BACKUP_FILE}" ]]; then
  die "Backup file not found: ${BACKUP_FILE}"
fi

# ---------------------------------------------------------------------------
# SECURITY: Path traversal check — reject entries with absolute paths or '..'
# ---------------------------------------------------------------------------
log "Checking archive for unsafe paths..."
UNSAFE_ENTRIES=$(tar -tzf "${BACKUP_FILE}" 2>/dev/null | grep -E '^/|^\.\./|\.\./') || true
if [[ -n "${UNSAFE_ENTRIES}" ]]; then
  err "Archive contains unsafe paths (path traversal attempt rejected):"
  echo "${UNSAFE_ENTRIES}" | head -10 >&2
  die "Restore aborted for security."
fi
log "  Archive path check passed ✓"

# ---------------------------------------------------------------------------
# Verify archive integrity
# ---------------------------------------------------------------------------
log "Verifying archive integrity..."
if ! tar -tzf "${BACKUP_FILE}" > /dev/null 2>&1; then
  die "Archive integrity check FAILED — the file may be corrupt: ${BACKUP_FILE}"
fi
ENTRY_COUNT=$(tar -tzf "${BACKUP_FILE}" | wc -l)
log "  Archive OK — ${ENTRY_COUNT} entries"

# ---------------------------------------------------------------------------
# Confirmation (skip with --yes)
# ---------------------------------------------------------------------------
if [[ "${SKIP_CONFIRM}" != "--yes" ]] && [[ -t 0 ]]; then
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  RESTORE CONFIRMATION                                        │"
  echo "  │                                                              │"
  echo "  │  Source  : ${BACKUP_FILE}"
  echo "  │  Target  : ${DATA_DIR}"
  echo "  │  Entries : ${ENTRY_COUNT}"
  echo "  │                                                              │"
  echo "  │  This will overwrite files in ${DATA_DIR}.                   │"
  echo "  │  Sessions will be cleared. Generated configs will be reset. │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo ""
  read -rp "  Proceed? Type 'yes' to confirm: " confirm
  if [[ "${confirm}" != "yes" ]]; then
    log "Restore cancelled by user."
    exit 0
  fi
fi

log "Restore starting..."
log "  Source  : ${BACKUP_FILE}"
log "  Target  : ${DATA_DIR}"

# ---------------------------------------------------------------------------
# Pre-restore: clear sessions and cache
# ---------------------------------------------------------------------------
log "Clearing sessions and cache (not restored from backup)..."
rm -rf "${DATA_DIR}/.hermes/analysis/sessions/"   2>/dev/null || true
rm -rf "${DATA_DIR}/.hermes/execution/sessions/"  2>/dev/null || true
rm -rf "${DATA_DIR}/.hermes/analysis/cache/"      2>/dev/null || true
rm -rf "${DATA_DIR}/.hermes/execution/cache/"     2>/dev/null || true
log "  Sessions cleared ✓"

# ---------------------------------------------------------------------------
# Extract archive
# ---------------------------------------------------------------------------
log "Extracting archive..."
tar -xzf "${BACKUP_FILE}" -C "${DATA_DIR}" 2>&1
log "  Extraction complete ✓"

# ---------------------------------------------------------------------------
# Post-restore: delete generated configs (will be regenerated on next boot)
# ---------------------------------------------------------------------------
log "Removing generated configs (will regenerate from canonical + env on next boot)..."
find "${DATA_DIR}/.hermes" -name "config.generated.yaml" -delete 2>/dev/null || true
find "${DATA_DIR}/mcp"     -name "mcp.generated.yaml"    -delete 2>/dev/null || true
find "${DATA_DIR}/mcp/generated" -type f                  -delete 2>/dev/null || true
log "  Generated configs cleared ✓"

# ---------------------------------------------------------------------------
# Post-restore: write restore record
# ---------------------------------------------------------------------------
mkdir -p "${DATA_DIR}/.runtime"
python3 - "${BACKUP_FILE}" "${ENTRY_COUNT}" << 'PYEOF'
import json, sys, os, datetime
record = {
    "restored_at":   datetime.datetime.utcnow().isoformat() + "Z",
    "source_file":   sys.argv[1],
    "entry_count":   int(sys.argv[2]),
    "restored_by":   "backup-restore.sh",
    "hermes_version": os.environ.get("HERMES_VERSION", "unknown"),
}
path = os.environ.get("DATA_DIR", "/data") + "/.runtime/last-restore.json"
with open(path, "w") as f:
    json.dump(record, f, indent=2)
print(f"  Restore record written: {path}")
PYEOF

log "========================================"
log " Restore complete ✓"
log ""
log " WHAT WAS RESTORED:"
log "   - Canonical config files (providers, mcp, risk, skills)"
log "   - Workspace content (AGENTS.md, MEMORY.md, journals)"
log "   - Audit logs"
log ""
log " WHAT WAS NOT RESTORED:"
log "   - Sessions (cleared for security)"
log "   - Generated configs (will regenerate on next boot)"
log "   - API keys (come from env vars, not backup)"
log ""
log " NEXT STEPS:"
log "   1. Verify env vars are set in Railway Variables (API keys)"
log "   2. Restart the container (redeploy)"
log "   3. Bootstrap will run migrations + regenerate config"
log "   4. Run: bash scripts/healthcheck.sh"
log "   5. Test with ACTIVE_PROFILE=analysis before enabling execution"
log ""
log " SMOKE TEST:"
log "   DATA_DIR=${DATA_DIR} bash scripts/healthcheck.sh"
log "========================================"
