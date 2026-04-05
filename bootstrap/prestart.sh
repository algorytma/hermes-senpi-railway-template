#!/usr/bin/env bash
# =============================================================================
# bootstrap/prestart.sh — Hermes-Senpi Trader Bootstrap Entrypoint
# =============================================================================
# Runs on every container start. Steps:
#   1. Volume mount check
#   2. First-run init (init-volume.sh)
#   3. Schema migrations
#   4. Risk policy validation (execution profile only)
#   5. Config generation (render-config.py)
#   6. Launch hermes runtime
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DATA_DIR="${DATA_DIR:-/data}"
RUNTIME_DIR="${DATA_DIR}/.runtime"
ACTIVE_PROFILE="${ACTIVE_PROFILE:-analysis}"

# Profile-isolated HERMES_HOME
if [[ "${ACTIVE_PROFILE}" == "execution" ]]; then
  export HERMES_HOME="${DATA_DIR}/.hermes/execution"
else
  export HERMES_HOME="${DATA_DIR}/.hermes/analysis"
fi

# ---------------------------------------------------------------------------
# Logging — safe even before /data exists
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN ] $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

log "=========================================="
log " Hermes-Senpi Trader Bootstrap Starting"
log " Profile     : ${ACTIVE_PROFILE}"
log " HERMES_HOME : ${HERMES_HOME}"
log " DATA_DIR    : ${DATA_DIR}"
log "=========================================="

# ---------------------------------------------------------------------------
# 1. Volume mount check
# ---------------------------------------------------------------------------
log "Step 1: Volume mount check..."
if [[ ! -d "${DATA_DIR}" ]]; then
  die "DATA_DIR (${DATA_DIR}) not found. Railway volume may not be mounted."
fi

# Ensure /data is writable
if ! touch "${DATA_DIR}/.write-test" 2>/dev/null; then
  die "DATA_DIR (${DATA_DIR}) is not writable. Check Railway volume permissions."
fi
rm -f "${DATA_DIR}/.write-test"
log "Volume OK: ${DATA_DIR}"

# ---------------------------------------------------------------------------
# 2. First-run init
# ---------------------------------------------------------------------------
log "Step 2: First-run init check..."
if [[ ! -f "${RUNTIME_DIR}/version.json" ]]; then
  log "First start detected — running init-volume.sh..."
  bash "$(dirname "$0")/init-volume.sh" 2>&1
  log "First-run init complete."
else
  log "Existing installation found — skipping init."
fi

# Setup log dir (after init so /data exists)
LOG_DIR="${DATA_DIR}/logs/setup"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/prestart-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# ---------------------------------------------------------------------------
# 3. Schema migrations
# ---------------------------------------------------------------------------
log "Step 3: Schema migration check..."
if [[ -f "$(dirname "$0")/run-migrations.sh" ]]; then
  bash "$(dirname "$0")/run-migrations.sh"
else
  log "No migration script found — skipping."
fi

# ---------------------------------------------------------------------------
# 4. Risk policy validation (execution profile only)
# ---------------------------------------------------------------------------
log "Step 4: Risk policy check (profile: ${ACTIVE_PROFILE})..."
if [[ "${ACTIVE_PROFILE}" == "execution" ]]; then
  bash "$(dirname "$0")/validate-risk.sh"
  log "Risk policy valid — execution may proceed."
else
  log "Analysis profile — risk policy mandatory check skipped."
fi

# ---------------------------------------------------------------------------
# 5. Config generation
# ---------------------------------------------------------------------------
log "Step 5: Generating Hermes config..."
mkdir -p "${HERMES_HOME}"
mkdir -p "${DATA_DIR}/mcp"

# Check that canonical provider files exist before rendering
if [[ ! -f "${DATA_DIR}/providers/provider_registry.yaml" ]]; then
  warn "provider_registry.yaml not found — config render may produce warnings."
fi

python3 /app/scripts/render-config.py \
  --profile "${ACTIVE_PROFILE}" \
  --data-dir "${DATA_DIR}" \
  --hermes-home "${HERMES_HOME}" \
  --output-hermes "${HERMES_HOME}/config.generated.yaml" \
  --output-mcp "${DATA_DIR}/mcp/mcp.generated.yaml" \
  2>&1 || warn "Config render failed — hermes will use its own defaults."

log "Config generation complete."

# ---------------------------------------------------------------------------
# 6. Launch hermes
# ---------------------------------------------------------------------------
log "Step 6: Launching hermes runtime..."
log "=========================================="
log " Bootstrap Complete — Starting Hermes"
log "=========================================="

# Use generated config if it exists, otherwise let hermes use defaults
if [[ -f "${HERMES_HOME}/config.generated.yaml" ]]; then
  exec hermes --config "${HERMES_HOME}/config.generated.yaml" "$@"
else
  warn "No generated config found — starting hermes with default config"
  exec hermes "$@"
fi
