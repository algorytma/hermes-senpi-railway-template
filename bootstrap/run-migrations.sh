#!/usr/bin/env bash
# =============================================================================
# bootstrap/run-migrations.sh — Schema Migration Runner
# =============================================================================
# /data/.runtime/migrations/applied.log dosyasını okur ve
# henüz uygulanmamış migration script'lerini sırayla çalıştırır.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MIGRATIONS_DIR="/app/migrations"
APPLIED_LOG="${DATA_DIR}/.runtime/migrations/applied.log"
VERSION_JSON="${DATA_DIR}/.runtime/version.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MIGR ] $*"; }
err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MIGR ] ERROR: $*" >&2; }

# Applied log yoksa oluştur
mkdir -p "$(dirname "${APPLIED_LOG}")"
touch "${APPLIED_LOG}"

log "Migration runner başlıyor..."
log "Migrations dizini: ${MIGRATIONS_DIR}"

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  log "Migrations dizini bulunamadı — atlanıyor."
  exit 0
fi

# Tüm migration script'lerini sıralı şekilde bul
applied=0
skipped=0
failed=0

while IFS= read -r -d '' migration_file; do
  migration_name="$(basename "${migration_file}")"

  # Zaten uygulanmış mı?
  if grep -qF "${migration_name}" "${APPLIED_LOG}" 2>/dev/null; then
    log "  ~ Atlandı (zaten uygulandı): ${migration_name}"
    ((skipped++)) || true
    continue
  fi

  log "  → Uygulanıyor: ${migration_name}"
  if bash "${migration_file}" 2>&1; then
    echo "${migration_name} applied_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${APPLIED_LOG}"
    log "  ✓ Tamamlandı: ${migration_name}"
    ((applied++)) || true
  else
    err "Migration başarısız: ${migration_name}"
    ((failed++)) || true
    exit 1
  fi
done < <(find "${MIGRATIONS_DIR}" -maxdepth 1 -name "*.sh" ! -name "runner.sh" -print0 | sort -z)

log "Migration özeti: ${applied} uygulandı, ${skipped} atlandı, ${failed} başarısız"

# version.json'u güncelle
if command -v python3 &>/dev/null && [[ -f "${VERSION_JSON}" ]]; then
  python3 - << PYEOF
import json, os
path = "${VERSION_JSON}"
with open(path) as f:
    v = json.load(f)
v["last_migration_at"] = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
with open(path, "w") as f:
    json.dump(v, f, indent=2)
PYEOF
fi

log "Migration runner tamamlandı ✓"
