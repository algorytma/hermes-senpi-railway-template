#!/usr/bin/env bash
# =============================================================================
# scripts/backup-export.sh — Volume Export (Backup)
# =============================================================================
# Creates a portable .tar.gz archive of canonical config + workspace + logs.
#
# Usage:
#   bash scripts/backup-export.sh
#   bash scripts/backup-export.sh --output /tmp/mybackup.tar.gz
#
# SECURITY:
#   - Generated configs are excluded (they contain resolved env references).
#   - Session directories are excluded (may contain session tokens).
#   - API keys are never on disk — nothing secret is included.
#
# After backup completes, the archive is verified with tar -tzf.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_OUTPUT="${DATA_DIR}/backups/exports/backup-${TIMESTAMP}.tar.gz"
MANIFEST_DIR="${DATA_DIR}/backups/manifests"

# Allow --output flag
OUTPUT="${DEFAULT_OUTPUT}"
for arg in "$@"; do
  case "${arg}" in
    --output) shift; OUTPUT="${1}" ;;
    --output=*) OUTPUT="${arg#*=}" ;;
  esac
done

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BKUP ] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BKUP ] WARN: $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BKUP ] ERROR: $*" >&2; }

mkdir -p "$(dirname "${OUTPUT}")"
mkdir -p "${MANIFEST_DIR}"

log "Backup starting: ${OUTPUT}"

# ---------------------------------------------------------------------------
# Include list — canonical config + workspace + important state
# ---------------------------------------------------------------------------
INCLUDE_DIRS=(
  "providers"
  "mcp"
  "skills"
  "risk"
  "workspace"
  "logs/audit"
  "logs/trades"
)

# ---------------------------------------------------------------------------
# Exclude patterns (security + size)
# ---------------------------------------------------------------------------
EXCLUDE_PATTERNS=(
  # Security: generated configs contain env var references
  "--exclude=**/config.generated.yaml"
  "--exclude=**/mcp.generated.yaml"
  "--exclude=**/mcp/generated"
  # Security: session dirs may contain session tokens
  "--exclude=${DATA_DIR}/.hermes/*/sessions"
  "--exclude=${DATA_DIR}/.hermes/*/cache"
  # Housekeeping
  "--exclude=${DATA_DIR}/backups"
  "--exclude=${DATA_DIR}/tmp"
  "--exclude=${DATA_DIR}/skills/registry-cache"
  "--exclude=${DATA_DIR}/skills/installed"
  "--exclude=${DATA_DIR}/.runtime/install.lock"
)

# ---------------------------------------------------------------------------
# Build include list (only existing dirs)
# ---------------------------------------------------------------------------
INCLUDE_PATHS=()
for dir in "${INCLUDE_DIRS[@]}"; do
  if [[ -d "${DATA_DIR}/${dir}" ]]; then
    INCLUDE_PATHS+=("${dir}")
    log "  + Include: ${dir}"
  else
    warn "  Directory not found, skipped: ${dir}"
  fi
done

if [[ ${#INCLUDE_PATHS[@]} -eq 0 ]]; then
  err "Nothing to backup — no expected directories found under ${DATA_DIR}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Create archive
# ---------------------------------------------------------------------------
cd "${DATA_DIR}"
tar -czf "${OUTPUT}" "${EXCLUDE_PATTERNS[@]}" "${INCLUDE_PATHS[@]}" 2>&1

# ---------------------------------------------------------------------------
# Verify archive integrity
# ---------------------------------------------------------------------------
log "Verifying archive integrity..."
if ! tar -tzf "${OUTPUT}" > /dev/null 2>&1; then
  err "Archive integrity check FAILED — the backup may be corrupt: ${OUTPUT}"
  exit 1
fi
ENTRY_COUNT=$(tar -tzf "${OUTPUT}" | wc -l)
log "  Archive OK — ${ENTRY_COUNT} entries"

# ---------------------------------------------------------------------------
# Write JSON manifest (using Python for safe JSON serialisation)
# ---------------------------------------------------------------------------
SIZE=$(stat -c%s "${OUTPUT}" 2>/dev/null || stat -f%z "${OUTPUT}" 2>/dev/null || echo "0")
MANIFEST_FILE="${MANIFEST_DIR}/manifest-${TIMESTAMP}.json"

INCLUDE_DIRS_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" \
  "${INCLUDE_DIRS[@]}")

python3 - "${OUTPUT}" "${MANIFEST_FILE}" "${SIZE}" "${ENTRY_COUNT}" \
         "${INCLUDE_DIRS_JSON}" << 'PYEOF'
import json, sys, os, datetime

output_file   = sys.argv[1]
manifest_file = sys.argv[2]
size_bytes    = int(sys.argv[3])
entry_count   = int(sys.argv[4])
included_dirs = json.loads(sys.argv[5])

manifest = {
    "schema_version":  "2",
    "created_at":      datetime.datetime.utcnow().isoformat() + "Z",
    "hermes_version":  os.environ.get("HERMES_VERSION", "unknown"),
    "active_profile":  os.environ.get("ACTIVE_PROFILE", "unknown"),
    "output_file":     output_file,
    "size_bytes":      size_bytes,
    "entry_count":     entry_count,
    "included_dirs":   included_dirs,
    "excludes": [
        "*.generated.yaml",
        ".hermes/*/sessions",
        ".hermes/*/cache",
        "skills/installed",
        "skills/registry-cache",
        "backups/",
        "tmp/",
    ],
    "notes": (
        "API keys and secrets are NOT included — they live in env vars only. "
        "Sessions are NOT included and will be cleared on restore. "
        "Generated configs are NOT included and will be regenerated on next boot."
    ),
}

with open(manifest_file, "w") as f:
    json.dump(manifest, f, indent=2)
print(f"  Manifest written: {manifest_file}")
PYEOF

log "========================================"
log " Backup complete ✓"
log "   Archive  : ${OUTPUT}"
log "   Manifest : ${MANIFEST_FILE}"
log "   Size     : ${SIZE} bytes"
log ""
log " To restore:"
log "   bash scripts/backup-restore.sh ${OUTPUT}"
log "========================================"
