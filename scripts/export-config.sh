#!/usr/bin/env bash
# =============================================================================
# scripts/export-config.sh — Canonical Config Export
# =============================================================================
# /data altındaki canonical config dosyalarını tek bir ZIP/tar arşivine dışa aktarır.
# State ve log içermez — sadece "davranış config'i" export edilir.
# Yeni ortama taşımak veya versiyon almak için kullanılır.
#
# Kullanım:
#   bash scripts/export-config.sh
#   bash scripts/export-config.sh --output /tmp/myconfig.tar.gz
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT="${2:-${DATA_DIR}/backups/exports/config-${TIMESTAMP}.tar.gz}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CONF ] $*"; }

mkdir -p "$(dirname "${OUTPUT}")"

log "Config export başlıyor: ${OUTPUT}"
log "  Kaynak: ${DATA_DIR}"

# ---------------------------------------------------------------------------
# Sadece canonical config dizinleri dahil edilir (generated, logs, state hariç)
# ---------------------------------------------------------------------------
INCLUDE=(
  "providers"
  "mcp/mcp_registry.yaml"
  "skills/manifests"
  "risk"
)

EXCLUDE=(
  "--exclude=${DATA_DIR}/mcp/mcp.generated.yaml"
  "--exclude=${DATA_DIR}/mcp/generated"
  "--exclude=${DATA_DIR}/.hermes"
  "--exclude=${DATA_DIR}/logs"
  "--exclude=${DATA_DIR}/backups"
  "--exclude=${DATA_DIR}/tmp"
  "--exclude=${DATA_DIR}/skills/installed"
  "--exclude=${DATA_DIR}/skills/registry-cache"
)

# Path'leri kontrol et
EXISTING=()
for item in "${INCLUDE[@]}"; do
  if [[ -e "${DATA_DIR}/${item}" ]]; then
    EXISTING+=("${item}")
    log "  + Dahil: ${item}"
  else
    log "  - Bulunamadı, atlandı: ${item}"
  fi
done

if [[ ${#EXISTING[@]} -eq 0 ]]; then
  log "HATA: Dahil edilecek config dosyası bulunamadı."
  exit 1
fi

cd "${DATA_DIR}"
tar -czf "${OUTPUT}" "${EXCLUDE[@]}" "${EXISTING[@]}" 2>&1

SIZE=$(stat -c%s "${OUTPUT}" 2>/dev/null || stat -f%z "${OUTPUT}" 2>/dev/null || echo "?")
log "Config export tamamlandı ✓"
log "  Çıktı : ${OUTPUT}"
log "  Boyut : ${SIZE} bytes"
log ""
log "NOT: Bu arşiv sadece canonical config içerir."
log "     Tam sistem backup için: bash scripts/backup-export.sh"
