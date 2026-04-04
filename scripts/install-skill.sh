#!/usr/bin/env bash
# =============================================================================
# scripts/install-skill.sh — Skill Kurulum Scripti
# =============================================================================
# Bir skill manifest dosyasını okuyarak ilgili skill'i git clone ile kurar,
# workspace'e sembolik bağ oluşturur.
#
# Kullanım:
#   bash scripts/install-skill.sh /data/skills/manifests/wolf-strategy.yaml
#   bash scripts/install-skill.sh /data/skills/manifests/wolf-strategy.yaml --force
#
# ZORUNLU: pinned_commit dolu olmalı — "REPLACE_WITH_REAL_COMMIT_HASH" kabul edilmez.
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MANIFEST_FILE="${1:-}"
FORCE="${2:-}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SKILL] $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SKILL] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Parametre kontrolü
# ---------------------------------------------------------------------------
[[ -z "${MANIFEST_FILE}" ]] && die "Kullanım: install-skill.sh <manifest.yaml> [--force]"
[[ ! -f "${MANIFEST_FILE}" ]] && die "Manifest dosyası bulunamadı: ${MANIFEST_FILE}"

log "Skill kurulumu başlıyor: ${MANIFEST_FILE}"

# ---------------------------------------------------------------------------
# Manifest'i oku (Python ile)
# ---------------------------------------------------------------------------
eval "$(python3 - << PYEOF
import yaml, sys, os

with open("${MANIFEST_FILE}") as f:
    m = yaml.safe_load(f)

name         = m.get("name", "")
repo_url     = m.get("source", {}).get("repo_url", "")
branch       = m.get("source", {}).get("branch", "main")
pinned       = m.get("source", {}).get("pinned_commit", "")
subpath      = m.get("source", {}).get("subpath", "")
target_dir   = m.get("install", {}).get("target_dir", "")
ws_link      = m.get("install", {}).get("link_into_workspace", "")
entry_point  = m.get("install", {}).get("entry_point", "skill.md")
enabled      = str(m.get("policy", {}).get("enabled", False)).lower()

if not name:      print("echo 'HATA: manifest.name boş'; exit 1"); sys.exit(0)
if not repo_url:  print("echo 'HATA: source.repo_url boş'; exit 1"); sys.exit(0)
if not target_dir: print("echo 'HATA: install.target_dir boş'; exit 1"); sys.exit(0)
if not pinned or "REPLACE_WITH" in pinned:
    print("echo 'HATA: pinned_commit doldurulmamış — branch-only kurulum reddedildi'; exit 1")
    sys.exit(0)

print(f'SKILL_NAME="{name}"')
print(f'SKILL_REPO="{repo_url}"')
print(f'SKILL_BRANCH="{branch}"')
print(f'SKILL_COMMIT="{pinned}"')
print(f'SKILL_SUBPATH="{subpath}"')
print(f'SKILL_TARGET="{target_dir}"')
print(f'SKILL_WS_LINK="{ws_link}"')
print(f'SKILL_ENTRY="{entry_point}"')
print(f'SKILL_ENABLED="{enabled}"')
PYEOF
)"

log "  Skill     : ${SKILL_NAME}"
log "  Repo      : ${SKILL_REPO}"
log "  Commit    : ${SKILL_COMMIT}"
log "  Hedef     : ${SKILL_TARGET}"

# ---------------------------------------------------------------------------
# Zaten kurulu mu?
# ---------------------------------------------------------------------------
if [[ -d "${SKILL_TARGET}" ]] && [[ "${FORCE}" != "--force" ]]; then
  log "Skill zaten kurulu: ${SKILL_TARGET}"
  log "Yeniden kurmak için --force kullanın."
  exit 0
fi

if [[ -d "${SKILL_TARGET}" ]] && [[ "${FORCE}" == "--force" ]]; then
  log "Mevcut kurulum siliniyor (--force)..."
  rm -rf "${SKILL_TARGET}"
fi

# ---------------------------------------------------------------------------
# Git clone (sparse checkout — sadece subpath varsa)
# ---------------------------------------------------------------------------
TMP_DIR="${DATA_DIR}/tmp/skill-install-${SKILL_NAME}-$$"
mkdir -p "${TMP_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

log "Repo klonlanıyor..."
git clone --no-checkout --depth 1 --branch "${SKILL_BRANCH}" "${SKILL_REPO}" "${TMP_DIR}/repo" 2>&1

# Pinned commit'e geç
(
  cd "${TMP_DIR}/repo"
  git fetch --depth 1 origin "${SKILL_COMMIT}" 2>&1 || true
  git checkout "${SKILL_COMMIT}" 2>&1
)
log "Pinned commit checkout: ${SKILL_COMMIT}"

# Subpath varsa sadece onu kopyala
mkdir -p "${SKILL_TARGET}"
if [[ -n "${SKILL_SUBPATH}" ]]; then
  SRC_PATH="${TMP_DIR}/repo/${SKILL_SUBPATH}"
  if [[ ! -d "${SRC_PATH}" ]]; then
    die "Subpath bulunamadı: ${SKILL_SUBPATH} (repo içinde)"
  fi
  cp -r "${SRC_PATH}/." "${SKILL_TARGET}/"
else
  cp -r "${TMP_DIR}/repo/." "${SKILL_TARGET}/"
fi

log "Dosyalar kopyalandı: ${SKILL_TARGET}"

# ---------------------------------------------------------------------------
# Workspace symlink (isteğe bağlı)
# ---------------------------------------------------------------------------
if [[ -n "${SKILL_WS_LINK}" ]]; then
  mkdir -p "$(dirname "${SKILL_WS_LINK}")"
  rm -f "${SKILL_WS_LINK}" 2>/dev/null || true

  ENTRY_FILE="${SKILL_TARGET}/${SKILL_ENTRY}"
  if [[ -f "${ENTRY_FILE}" ]]; then
    ln -sf "${ENTRY_FILE}" "${SKILL_WS_LINK}"
    log "Workspace symlink: ${SKILL_WS_LINK} → ${ENTRY_FILE}"
  else
    ln -sf "${SKILL_TARGET}" "${SKILL_WS_LINK}"
    log "Workspace symlink (klasör): ${SKILL_WS_LINK} → ${SKILL_TARGET}"
  fi
fi

# ---------------------------------------------------------------------------
# Manifest'e installed_at yaz
# ---------------------------------------------------------------------------
python3 - << PYEOF
import yaml, datetime, sys

path = "${MANIFEST_FILE}"
with open(path) as f:
    m = yaml.safe_load(f)

m.setdefault("metadata", {})["installed_at"] = datetime.datetime.utcnow().isoformat() + "Z"

with open(path, "w") as f:
    yaml.dump(m, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
print("[SKILL] Manifest güncellendi: installed_at")
PYEOF

# ---------------------------------------------------------------------------
# Sonuç
# ---------------------------------------------------------------------------
log "========================================"
log " Skill kurulumu tamamlandı ✓"
log "   ${SKILL_NAME} @ ${SKILL_COMMIT}"
if [[ "${SKILL_ENABLED}" == "false" ]]; then
  log " UYARI: policy.enabled=false — bu skill varsayılan pasif."
  log " Aktifleştirmek için manifest'te enabled: true yapın."
fi
log "========================================"
