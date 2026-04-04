#!/usr/bin/env bash
# =============================================================================
# bootstrap/prestart.sh — Hermes-Senpi Trader Ana Başlangıç Noktası
# =============================================================================
# Her container başlangıcında çalışır. Aşağıdaki adımları sırasıyla uygular:
#   1. Volume mount kontrolü
#   2. First-run init (sadece ilk açılışta)
#   3. Schema migration kontrolü
#   4. Risk policy doğrulama (execution profile)
#   5. Config üretimi (render-config.py)
#   6. Hermes runtime başlatma
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Sabitler
# ---------------------------------------------------------------------------
DATA_DIR="${DATA_DIR:-/data}"
RUNTIME_DIR="${DATA_DIR}/.runtime"
ACTIVE_PROFILE="${ACTIVE_PROFILE:-analysis}"
LOG_DIR="${DATA_DIR}/logs/setup"
LOG_FILE="${LOG_DIR}/prestart-$(date +%Y%m%d-%H%M%S).log"
SCHEMA_VERSION="1"

# Profil bazlı HERMES_HOME
if [[ "${ACTIVE_PROFILE}" == "execution" ]]; then
  export HERMES_HOME="${DATA_DIR}/.hermes/execution"
else
  export HERMES_HOME="${DATA_DIR}/.hermes/analysis"
fi

# ---------------------------------------------------------------------------
# Yardımcı fonksiyonlar
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN ] $*" | tee -a "${LOG_FILE}"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 0. Log dizinini oluştur (bootstrap çalışmadan önce gerekli)
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

log "=========================================="
log " Hermes-Senpi Trader Bootstrap Başlıyor"
log " Profile : ${ACTIVE_PROFILE}"
log " HERMES_HOME: ${HERMES_HOME}"
log " DATA_DIR: ${DATA_DIR}"
log "=========================================="

# ---------------------------------------------------------------------------
# 1. Volume mount kontrolü
# ---------------------------------------------------------------------------
log "Adım 1: Volume mount kontrolü..."
if [[ ! -d "${DATA_DIR}" ]]; then
  die "DATA_DIR (${DATA_DIR}) bulunamadı. Railway volume mount edilmemiş olabilir."
fi
log "Volume OK: ${DATA_DIR}"

# ---------------------------------------------------------------------------
# 2. First-run init
# ---------------------------------------------------------------------------
log "Adım 2: First-run init kontrolü..."
if [[ ! -f "${RUNTIME_DIR}/version.json" ]]; then
  log "İlk başlangıç algılandı — init-volume.sh çalıştırılıyor..."
  # shellcheck source=bootstrap/init-volume.sh
  bash "$(dirname "$0")/init-volume.sh" 2>&1 | tee -a "${LOG_FILE}"
  log "First-run init tamamlandı."
else
  log "Mevcut kurulum bulundu — init atlanıyor."
fi

# ---------------------------------------------------------------------------
# 3. Schema migration kontrolü
# ---------------------------------------------------------------------------
log "Adım 3: Schema migration kontrolü..."
bash "$(dirname "$0")/run-migrations.sh" 2>&1 | tee -a "${LOG_FILE}"

# ---------------------------------------------------------------------------
# 4. Risk policy doğrulama (sadece execution profile)
# ---------------------------------------------------------------------------
log "Adım 4: Risk policy kontrolü (profile: ${ACTIVE_PROFILE})..."
if [[ "${ACTIVE_PROFILE}" == "execution" ]]; then
  bash "$(dirname "$0")/validate-risk.sh" 2>&1 | tee -a "${LOG_FILE}"
  log "Risk policy geçerli — execution başlatılabilir."
else
  log "Analysis profili — risk policy zorunlu check atlandı."
fi

# ---------------------------------------------------------------------------
# 5. Config üretimi
# ---------------------------------------------------------------------------
log "Adım 5: Config üretimi başlatılıyor..."
mkdir -p "${HERMES_HOME}"
mkdir -p "${DATA_DIR}/mcp"

python3 /app/scripts/render-config.py \
  --profile "${ACTIVE_PROFILE}" \
  --data-dir "${DATA_DIR}" \
  --hermes-home "${HERMES_HOME}" \
  --output-hermes "${HERMES_HOME}/config.generated.yaml" \
  --output-mcp "${DATA_DIR}/mcp/mcp.generated.yaml" \
  2>&1 | tee -a "${LOG_FILE}"

log "Config üretimi tamamlandı."

# ---------------------------------------------------------------------------
# 6. Hermes runtime başlatma
# ---------------------------------------------------------------------------
log "Adım 6: Hermes runtime başlatılıyor..."
log "=========================================="
log " Hermes-Senpi Trader Bootstrap Tamamlandı"
log "=========================================="

exec hermes --config "${HERMES_HOME}/config.generated.yaml" "$@"
