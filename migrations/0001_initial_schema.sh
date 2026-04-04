#!/usr/bin/env bash
# =============================================================================
# migrations/0001_initial_schema.sh — İlk Schema Migrasyonu
# =============================================================================
# Bu migration ilk kurulumda çalışır ve temel schema version'u yazar.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
log() { echo "[MIGR:0001] $*"; }

log "Initial schema migration başlıyor..."

# version.json'da schema alanı yoksa ekle
VERSION_JSON="${DATA_DIR}/.runtime/version.json"
if [[ -f "${VERSION_JSON}" ]]; then
    python3 - << 'PYEOF'
import json, os
path = os.environ.get("DATA_DIR", "/data") + "/.runtime/version.json"
with open(path) as f:
    v = json.load(f)
if "schema" not in v:
    v["schema"] = "1"
    print("[MIGR:0001] schema alanı eklendi")
else:
    print(f"[MIGR:0001] schema zaten mevcut: {v['schema']}")
with open(path, "w") as f:
    json.dump(v, f, indent=2)
PYEOF
fi

# Temel log dizinlerini garantiye al
mkdir -p "${DATA_DIR}/logs/gateway"
mkdir -p "${DATA_DIR}/logs/audit"
mkdir -p "${DATA_DIR}/logs/trades"
mkdir -p "${DATA_DIR}/logs/setup"

log "Initial schema migration tamamlandı ✓"
