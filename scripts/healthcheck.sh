#!/usr/bin/env bash
# =============================================================================
# scripts/healthcheck.sh — Sistem Sağlık Kontrolü
# =============================================================================
# Container health check olarak veya elle çalıştırılabilir.
# Çıktı: 0 = healthy, 1 = unhealthy
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
ACTIVE_PROFILE="${ACTIVE_PROFILE:-analysis}"
FAILED=0

ok()   { echo "  [OK]  $*"; }
warn() { echo "  [WARN] $*" >&2; }
fail() { echo "  [FAIL] $*" >&2; FAILED=$((FAILED + 1)); }

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Healthcheck başlıyor (profile=${ACTIVE_PROFILE})..."

# ---------------------------------------------------------------------------
# 1. Volume mount
# ---------------------------------------------------------------------------
if [[ -d "${DATA_DIR}" ]]; then
  ok "Volume mount: ${DATA_DIR}"
else
  fail "Volume mount yok: ${DATA_DIR}"
fi

# ---------------------------------------------------------------------------
# 2. Runtime version dosyası
# ---------------------------------------------------------------------------
if [[ -f "${DATA_DIR}/.runtime/version.json" ]]; then
  ok "Runtime version.json mevcut"
else
  fail "Runtime version.json bulunamadı — bootstrap çalışmamış olabilir"
fi

# ---------------------------------------------------------------------------
# 3. HERMES_HOME ve generated config
# ---------------------------------------------------------------------------
if [[ "${ACTIVE_PROFILE}" == "execution" ]]; then
  HERMES_HOME="${DATA_DIR}/.hermes/execution"
else
  HERMES_HOME="${DATA_DIR}/.hermes/analysis"
fi

if [[ -d "${HERMES_HOME}" ]]; then
  ok "HERMES_HOME mevcut: ${HERMES_HOME}"
else
  warn "HERMES_HOME henüz oluşturulmamış: ${HERMES_HOME}"
fi

CONFIG_GENERATED="${HERMES_HOME}/config.generated.yaml"
if [[ -f "${CONFIG_GENERATED}" ]]; then
  ok "Generated config mevcut: ${CONFIG_GENERATED}"
else
  fail "Generated config bulunamadı: ${CONFIG_GENERATED} — render-config.py çalışmamış olabilir"
fi

# ---------------------------------------------------------------------------
# 4. MCP generated config
# ---------------------------------------------------------------------------
MCP_GENERATED="${DATA_DIR}/mcp/mcp.generated.yaml"
if [[ -f "${MCP_GENERATED}" ]]; then
  ok "MCP generated config mevcut"
else
  warn "MCP generated config yok: ${MCP_GENERATED}"
fi

# ---------------------------------------------------------------------------
# 5. Workspace
# ---------------------------------------------------------------------------
if [[ -f "${DATA_DIR}/workspace/AGENTS.md" ]]; then
  ok "Workspace AGENTS.md mevcut"
else
  fail "workspace/AGENTS.md bulunamadı"
fi

# ---------------------------------------------------------------------------
# 6. Risk policy (execution'da zorunlu)
# ---------------------------------------------------------------------------
if [[ "${ACTIVE_PROFILE}" == "execution" ]]; then
  if [[ -f "${DATA_DIR}/risk/risk_policy.yaml" ]]; then
    ok "Risk policy mevcut (execution profili)"
  else
    fail "Risk policy bulunamadı — execution profili için zorunlu"
  fi
else
  if [[ -f "${DATA_DIR}/risk/risk_policy.yaml" ]]; then
    ok "Risk policy mevcut (analysis profili)"
  else
    warn "Risk policy yok — execution açılmadan önce oluşturun"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Canonical config dosyaları
# ---------------------------------------------------------------------------
declare -a CANONICAL_FILES=(
  "${DATA_DIR}/providers/provider_registry.yaml"
  "${DATA_DIR}/providers/model_aliases.yaml"
  "${DATA_DIR}/mcp/mcp_registry.yaml"
)

for f in "${CANONICAL_FILES[@]}"; do
  if [[ -f "${f}" ]]; then
    ok "Canonical config: $(basename ${f})"
  else
    warn "Canonical config eksik: ${f}"
  fi
done

# ---------------------------------------------------------------------------
# Sonuç
# ---------------------------------------------------------------------------
echo ""
if [[ "${FAILED}" -eq 0 ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Healthcheck PASSED ✓"
  exit 0
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Healthcheck FAILED — ${FAILED} hata"
  exit 1
fi
