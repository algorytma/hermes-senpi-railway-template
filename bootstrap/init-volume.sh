#!/usr/bin/env bash
# =============================================================================
# bootstrap/init-volume.sh — First-Run Volume Başlatma
# =============================================================================
# Sadece ilk başlangıçta çalışır (/data/.runtime/version.json yoksa).
# /data altındaki tüm klasör yapısını oluşturur ve
# default canonical config dosyalarını kopyalar.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
DEFAULTS_DIR="/app/defaults"
SCHEMA_VERSION="1"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INIT ] $*"; }

log "Volume dizin yapısı oluşturuluyor..."

# ---------------------------------------------------------------------------
# Klasör ağacı oluştur
# ---------------------------------------------------------------------------
dirs=(
  "${DATA_DIR}/.runtime/migrations"
  "${DATA_DIR}/.hermes/analysis/sessions"
  "${DATA_DIR}/.hermes/analysis/auth"
  "${DATA_DIR}/.hermes/analysis/cache"
  "${DATA_DIR}/.hermes/execution/sessions"
  "${DATA_DIR}/.hermes/execution/auth"
  "${DATA_DIR}/.hermes/execution/cache"
  "${DATA_DIR}/workspace/skills"
  "${DATA_DIR}/workspace/prompts"
  "${DATA_DIR}/workspace/journals"
  "${DATA_DIR}/providers"
  "${DATA_DIR}/mcp"
  "${DATA_DIR}/skills/manifests"
  "${DATA_DIR}/skills/installed"
  "${DATA_DIR}/skills/registry-cache"
  "${DATA_DIR}/risk"
  "${DATA_DIR}/logs/gateway"
  "${DATA_DIR}/logs/audit"
  "${DATA_DIR}/logs/trades"
  "${DATA_DIR}/logs/setup"
  "${DATA_DIR}/backups/manifests"
  "${DATA_DIR}/backups/exports"
  "${DATA_DIR}/backups/snapshots"
  "${DATA_DIR}/tmp"
)

for dir in "${dirs[@]}"; do
  mkdir -p "${dir}"
  log "  ✓ ${dir}"
done

# ---------------------------------------------------------------------------
# Default canonical config dosyalarını kopyala (zaten varsa dokunma)
# ---------------------------------------------------------------------------
log "Default canonical config dosyaları kopyalanıyor..."

copy_default() {
  local src="$1"
  local dst="$2"
  if [[ ! -f "${dst}" ]]; then
    if [[ -f "${src}" ]]; then
      cp "${src}" "${dst}"
      log "  ✓ ${dst}"
    else
      log "  ! Kaynak bulunamadı: ${src} — atlandı"
    fi
  else
    log "  ~ Mevcut, atlandı: ${dst}"
  fi
}

copy_default "${DEFAULTS_DIR}/providers/provider_registry.yaml" \
             "${DATA_DIR}/providers/provider_registry.yaml"

copy_default "${DEFAULTS_DIR}/providers/model_aliases.yaml" \
             "${DATA_DIR}/providers/model_aliases.yaml"

copy_default "${DEFAULTS_DIR}/mcp/mcp_registry.yaml" \
             "${DATA_DIR}/mcp/mcp_registry.yaml"

copy_default "${DEFAULTS_DIR}/risk/risk_policy.yaml" \
             "${DATA_DIR}/risk/risk_policy.yaml"

copy_default "${DEFAULTS_DIR}/risk/symbol_policy.yaml" \
             "${DATA_DIR}/risk/symbol_policy.yaml"

copy_default "${DEFAULTS_DIR}/skills/manifests/wolf-strategy.yaml" \
             "${DATA_DIR}/skills/manifests/wolf-strategy.yaml"

copy_default "${DEFAULTS_DIR}/workspace/AGENTS.md" \
             "${DATA_DIR}/workspace/AGENTS.md"

copy_default "${DEFAULTS_DIR}/workspace/BOOTSTRAP.md" \
             "${DATA_DIR}/workspace/BOOTSTRAP.md"

copy_default "${DEFAULTS_DIR}/workspace/USER.md" \
             "${DATA_DIR}/workspace/USER.md"

# ---------------------------------------------------------------------------
# version.json yaz
# ---------------------------------------------------------------------------
HERMES_VERSION="${HERMES_VERSION:-unknown}"
cat > "${DATA_DIR}/.runtime/version.json" << EOF
{
  "schema": "${SCHEMA_VERSION}",
  "hermes_version": "${HERMES_VERSION}",
  "initialized_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "data_dir": "${DATA_DIR}"
}
EOF

log "version.json yazıldı: ${DATA_DIR}/.runtime/version.json"

# Migration log başlat
touch "${DATA_DIR}/.runtime/migrations/applied.log"
log "Migration log başlatıldı."

log "First-run init tamamlandı ✓"
