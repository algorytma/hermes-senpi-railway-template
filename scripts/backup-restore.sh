#!/usr/bin/env bash
# =============================================================================
# scripts/backup-restore.sh — Volume Restore
# =============================================================================
# Kullanım: bash backup-restore.sh <backup.tar.gz>
#
# DİKKAT: Bu işlem /data volume içeriğini değiştirir.
#         Önce yeni bir backup almayı düşünün.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
BACKUP_FILE="${1:-}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REST ] $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REST ] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Parametre kontrolü
# ---------------------------------------------------------------------------
if [[ -z "${BACKUP_FILE}" ]]; then
  die "Kullanım: backup-restore.sh <backup.tar.gz>"
fi

if [[ ! -f "${BACKUP_FILE}" ]]; then
  die "Backup dosyası bulunamadı: ${BACKUP_FILE}"
fi

log "Restore başlıyor..."
log "  Kaynak  : ${BACKUP_FILE}"
log "  Hedef   : ${DATA_DIR}"

# ---------------------------------------------------------------------------
# Onay (interaktif modda)
# ---------------------------------------------------------------------------
if [[ -t 0 ]]; then
  echo ""
  echo "  ⚠️  UYARI: Bu işlem mevcut /data içeriğini değiştirebilir."
  read -rp "  Devam etmek istiyor musunuz? (evet/hayır): " confirm
  if [[ "${confirm}" != "evet" ]]; then
    log "Restore iptal edildi."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Restore öncesi session'ları temizle
# ---------------------------------------------------------------------------
log "Eski session'lar temizleniyor..."
rm -rf "${DATA_DIR}/.hermes/analysis/sessions/"* 2>/dev/null || true
rm -rf "${DATA_DIR}/.hermes/execution/sessions/"* 2>/dev/null || true
rm -rf "${DATA_DIR}/.hermes/analysis/cache/"* 2>/dev/null || true
rm -rf "${DATA_DIR}/.hermes/execution/cache/"* 2>/dev/null || true

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
log "Arşiv açılıyor..."
tar -xzf "${BACKUP_FILE}" -C "${DATA_DIR}" 2>&1
log "Arşiv açma tamamlandı."

# ---------------------------------------------------------------------------
# Restore sonrası: generated config'leri temizle (env farklı olabilir)
# ---------------------------------------------------------------------------
log "Generated config dosyaları temizleniyor (yeni env için yeniden üretilecek)..."
rm -f "${DATA_DIR}/.hermes/analysis/config.generated.yaml" 2>/dev/null || true
rm -f "${DATA_DIR}/.hermes/execution/config.generated.yaml" 2>/dev/null || true
rm -f "${DATA_DIR}/mcp/mcp.generated.yaml" 2>/dev/null || true

log "NOT: Bir sonraki container başlangıcında config otomatik yeniden üretilecek."

# ---------------------------------------------------------------------------
# Migration check (eski backup yeni schema'ya uygun olmayabilir)
# ---------------------------------------------------------------------------
log "Migration kontrolü yapılacak (sonraki prestart'ta çalışacak)..."

log "========================================"
log " Restore tamamlandı ✓"
log " Sonraki adımlar:"
log "   1. Env var'larınızı kontrol edin (API keys yeni host'ta geçerli mi?)"
log "   2. Container'ı yeniden başlatın"
log "   3. Prestart, migration ve config generation otomatik çalışacak"
log "   4. ACTIVE_PROFILE=analysis ile test edin"
log "========================================"
