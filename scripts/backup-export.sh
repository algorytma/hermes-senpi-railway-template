#!/usr/bin/env bash
# =============================================================================
# scripts/backup-export.sh — Volume Export (Backup)
# =============================================================================
# Kullanım: bash backup-export.sh [--output /path/to/output.tar.gz]
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_OUTPUT="${DATA_DIR}/backups/exports/backup-${TIMESTAMP}.tar.gz"
MANIFEST_DIR="${DATA_DIR}/backups/manifests"

OUTPUT="${1:-${DEFAULT_OUTPUT}}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BKUP ] $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BKUP ] ERROR: $*" >&2; }

mkdir -p "$(dirname "${OUTPUT}")"
mkdir -p "${MANIFEST_DIR}"

log "Backup başlıyor: ${OUTPUT}"

# ---------------------------------------------------------------------------
# Dahil edilen dizinler
# ---------------------------------------------------------------------------
INCLUDE_DIRS=(
  ".hermes"
  "workspace"
  "providers"
  "mcp"
  "skills"
  "risk"
)

# Dışlanan pattern'lar
EXCLUDE_PATTERNS=(
  "--exclude=${DATA_DIR}/logs/gateway"
  "--exclude=${DATA_DIR}/tmp"
  "--exclude=${DATA_DIR}/skills/registry-cache"
  "--exclude=${DATA_DIR}/.hermes/*/cache"
  "--exclude=${DATA_DIR}/backups"
)

# ---------------------------------------------------------------------------
# tar ile export
# ---------------------------------------------------------------------------
TAR_ARGS=()
for excl in "${EXCLUDE_PATTERNS[@]}"; do
  TAR_ARGS+=("${excl}")
done

INCLUDE_PATHS=()
for dir in "${INCLUDE_DIRS[@]}"; do
  if [[ -d "${DATA_DIR}/${dir}" ]]; then
    INCLUDE_PATHS+=("${dir}")
  else
    log "  UYARI: Dizin bulunamadı, atlandı: ${dir}"
  fi
done

cd "${DATA_DIR}"
tar -czf "${OUTPUT}" "${TAR_ARGS[@]}" "${INCLUDE_PATHS[@]}" 2>&1
log "Arşiv oluşturuldu: ${OUTPUT}"

# ---------------------------------------------------------------------------
# Manifest yaz
# ---------------------------------------------------------------------------
SIZE=$(stat -c%s "${OUTPUT}" 2>/dev/null || stat -f%z "${OUTPUT}" 2>/dev/null || echo "0")
MANIFEST_FILE="${MANIFEST_DIR}/manifest-${TIMESTAMP}.json"

python3 - << PYEOF
import json, os, datetime

manifest = {
    "created_at": datetime.datetime.utcnow().isoformat() + "Z",
    "hermes_version": os.environ.get("HERMES_VERSION", "unknown"),
    "schema_version": "1",
    "profile": os.environ.get("ACTIVE_PROFILE", "unknown"),
    "output_file": "${OUTPUT}",
    "included_dirs": ${INCLUDE_DIRS[@]@Q},
    "size_bytes": ${SIZE},
}

with open("${MANIFEST_FILE}", "w") as f:
    json.dump(manifest, f, indent=2)
print(f"Manifest yazıldı: ${MANIFEST_FILE}")
PYEOF

log "Backup tamamlandı ✓"
log "  Arşiv : ${OUTPUT}"
log "  Manifest: ${MANIFEST_FILE}"
