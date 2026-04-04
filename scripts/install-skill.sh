#!/usr/bin/env bash
# =============================================================================
# scripts/install-skill.sh — Skill Installer
# =============================================================================
# Reads a skill manifest YAML and installs the skill at the pinned commit.
#
# Usage:
#   bash scripts/install-skill.sh /data/skills/manifests/wolf-strategy.yaml
#   bash scripts/install-skill.sh /data/skills/manifests/wolf-strategy.yaml --force
#
# SECURITY requirements:
#   - pinned_commit MUST be a real git SHA (no placeholders, no branch names)
#   - After checkout, HEAD is verified to match pinned_commit exactly
#   - Workspace symlink target must be within DATA_DIR (no escape)
#   - eval is NOT used — manifest values pass through Python to a temp file
#
# INTEGRITY:
#   - A 40-char hex SHA is required for pinned_commit
#   - The actual checked-out HEAD is verified after clone + checkout
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MANIFEST_FILE="${1:-}"
FORCE="${2:-}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SKILL] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SKILL] WARN: $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SKILL] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Parameter validation
# ---------------------------------------------------------------------------
if [[ -z "${MANIFEST_FILE}" ]]; then
  echo "Usage: install-skill.sh <manifest.yaml> [--force]" >&2
  exit 1
fi

if [[ ! -f "${MANIFEST_FILE}" ]]; then
  die "Manifest file not found: ${MANIFEST_FILE}"
fi

log "Skill install starting: ${MANIFEST_FILE}"

# ---------------------------------------------------------------------------
# Parse manifest into a temp shell env file (no eval — safe approach)
# ---------------------------------------------------------------------------
SKILL_ENV_FILE=$(mktemp)
trap 'rm -f "${SKILL_ENV_FILE}"' EXIT

python3 - "${MANIFEST_FILE}" "${DATA_DIR}" "${SKILL_ENV_FILE}" << 'PYEOF'
import sys
import os
import re
import yaml

manifest_path = sys.argv[1]
data_dir      = sys.argv[2]
env_file      = sys.argv[3]

try:
    with open(manifest_path) as f:
        m = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Cannot parse manifest YAML: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(m, dict):
    print("ERROR: Manifest must be a YAML dict", file=sys.stderr)
    sys.exit(1)

# --- Extract and validate fields ---
name         = str(m.get("name", "")).strip()
source       = m.get("source", {}) or {}
repo_url     = str(source.get("repo_url", "")).strip()
branch       = str(source.get("branch", "main")).strip()
pinned       = str(source.get("pinned_commit", "")).strip()
subpath      = str(source.get("subpath", "")).strip()
install      = m.get("install", {}) or {}
target_dir   = str(install.get("target_dir", "")).strip()
ws_link      = str(install.get("link_into_workspace", "")).strip()
entry_point  = str(install.get("entry_point", "skill.md")).strip()
policy       = m.get("policy", {}) or {}
enabled      = str(policy.get("enabled", False)).lower()

errors = []

if not name:
    errors.append("manifest.name is empty")

if not repo_url:
    errors.append("source.repo_url is empty")
elif not repo_url.startswith(("https://", "git@", "ssh://")):
    errors.append(f"source.repo_url has unexpected scheme: {repo_url!r}")

if not target_dir:
    errors.append("install.target_dir is empty")
elif not target_dir.startswith("/"):
    errors.append(f"install.target_dir must be an absolute path, got: {target_dir!r}")

# Validate pinned_commit: must be 40-char hex SHA, no placeholders
SHA_RE = re.compile(r'^[0-9a-f]{40}$', re.I)
if not pinned:
    errors.append("source.pinned_commit is empty — branch-only installs are rejected")
elif "REPLACE" in pinned.upper() or "PLACEHOLDER" in pinned.upper():
    errors.append(f"source.pinned_commit contains a placeholder: {pinned!r}")
elif not SHA_RE.match(pinned):
    errors.append(
        f"source.pinned_commit must be a 40-character hex git SHA, got: {pinned!r} "
        "(run 'git rev-parse <ref>' to get the full SHA)"
    )

# Validate workspace symlink is within DATA_DIR
if ws_link and not ws_link.startswith(data_dir):
    errors.append(
        f"install.link_into_workspace must be under DATA_DIR ({data_dir!r}), "
        f"got: {ws_link!r}"
    )

if errors:
    print("Manifest validation FAILED:", file=sys.stderr)
    for e in errors:
        print(f"  ✗ {e}", file=sys.stderr)
    sys.exit(1)

# Write shell-safe env file (values are quoted with shlex)
import shlex
lines = [
    f"SKILL_NAME={shlex.quote(name)}",
    f"SKILL_REPO={shlex.quote(repo_url)}",
    f"SKILL_BRANCH={shlex.quote(branch)}",
    f"SKILL_COMMIT={shlex.quote(pinned)}",
    f"SKILL_SUBPATH={shlex.quote(subpath)}",
    f"SKILL_TARGET={shlex.quote(target_dir)}",
    f"SKILL_WS_LINK={shlex.quote(ws_link)}",
    f"SKILL_ENTRY={shlex.quote(entry_point)}",
    f"SKILL_ENABLED={shlex.quote(enabled)}",
]

with open(env_file, "w") as f:
    f.write("\n".join(lines) + "\n")

print("Manifest validated OK")
PYEOF

# Source the safe env file (no eval of manifest content)
# shellcheck source=/dev/null
source "${SKILL_ENV_FILE}"

log "  Skill   : ${SKILL_NAME}"
log "  Repo    : ${SKILL_REPO}"
log "  Commit  : ${SKILL_COMMIT}"
log "  Target  : ${SKILL_TARGET}"

# ---------------------------------------------------------------------------
# Already installed check
# ---------------------------------------------------------------------------
if [[ -d "${SKILL_TARGET}" ]] && [[ "${FORCE}" != "--force" ]]; then
  log "Skill already installed: ${SKILL_TARGET}"
  log "To reinstall: pass --force"
  exit 0
fi

if [[ -d "${SKILL_TARGET}" ]] && [[ "${FORCE}" == "--force" ]]; then
  log "Removing previous installation (--force)..."
  rm -rf "${SKILL_TARGET}"
fi

# ---------------------------------------------------------------------------
# Git clone with pinned commit
# ---------------------------------------------------------------------------
TMP_BASE="${DATA_DIR}/tmp"
mkdir -p "${TMP_BASE}"
TMP_DIR=$(mktemp -d "${TMP_BASE}/skill-install-XXXXXX")
trap 'rm -rf "${TMP_DIR}"' EXIT

log "Cloning repository..."
git clone --no-checkout --depth 200 \
    --branch "${SKILL_BRANCH}" "${SKILL_REPO}" "${TMP_DIR}/repo" 2>&1

log "Checking out pinned commit: ${SKILL_COMMIT}..."
(
  cd "${TMP_DIR}/repo"
  # Try direct fetch of the pinned commit first (faster for known SHAs)
  git fetch --depth 1 origin "${SKILL_COMMIT}" 2>&1 || true
  git checkout "${SKILL_COMMIT}" 2>&1
)

# ---------------------------------------------------------------------------
# INTEGRITY: Verify HEAD matches pinned_commit
# ---------------------------------------------------------------------------
log "Verifying commit integrity..."
ACTUAL_HEAD=$(cd "${TMP_DIR}/repo" && git rev-parse HEAD)

if [[ "${ACTUAL_HEAD}" != "${SKILL_COMMIT}" ]]; then
  err "========================================================"
  err "INTEGRITY CHECK FAILED"
  err "  Expected : ${SKILL_COMMIT}"
  err "  Actual   : ${ACTUAL_HEAD}"
  err ""
  err "The checked-out commit does not match pinned_commit."
  err "Possible causes:"
  err "  - pinned_commit is a short SHA (must be 40 chars)"
  err "  - Git history was rewritten (force-push)"
  err "  - Network/MITM tampering"
  err ""
  err "Skill installation ABORTED for security."
  err "========================================================"
  exit 1
fi

log "  Commit integrity verified ✓ (${SKILL_COMMIT:0:12}...)"

# ---------------------------------------------------------------------------
# Copy files to target
# ---------------------------------------------------------------------------
mkdir -p "${SKILL_TARGET}"

if [[ -n "${SKILL_SUBPATH}" ]]; then
  SRC_PATH="${TMP_DIR}/repo/${SKILL_SUBPATH}"
  if [[ ! -d "${SRC_PATH}" ]]; then
    die "Subpath not found in repo: '${SKILL_SUBPATH}'"
  fi
  cp -r "${SRC_PATH}/." "${SKILL_TARGET}/"
else
  cp -r "${TMP_DIR}/repo/." "${SKILL_TARGET}/"
fi
log "Files copied to: ${SKILL_TARGET}"

# ---------------------------------------------------------------------------
# Workspace symlink (with path validation)
# ---------------------------------------------------------------------------
if [[ -n "${SKILL_WS_LINK}" ]]; then
  # Path validation — must be under DATA_DIR (already checked in Python)
  LINK_PARENT=$(dirname "${SKILL_WS_LINK}")
  mkdir -p "${LINK_PARENT}"
  rm -f "${SKILL_WS_LINK}" 2>/dev/null || true

  ENTRY_FILE="${SKILL_TARGET}/${SKILL_ENTRY}"
  if [[ -f "${ENTRY_FILE}" ]]; then
    ln -sf "${ENTRY_FILE}" "${SKILL_WS_LINK}"
    log "Workspace symlink: ${SKILL_WS_LINK} → ${ENTRY_FILE}"
  else
    ln -sf "${SKILL_TARGET}" "${SKILL_WS_LINK}"
    log "Workspace symlink (dir): ${SKILL_WS_LINK} → ${SKILL_TARGET}"
  fi
fi

# ---------------------------------------------------------------------------
# Write install record to manifest
# ---------------------------------------------------------------------------
python3 - "${MANIFEST_FILE}" "${SKILL_COMMIT}" "${ACTUAL_HEAD}" << 'PYEOF'
import yaml, datetime, sys

path        = sys.argv[1]
expected_sha = sys.argv[2]
actual_sha   = sys.argv[3]

with open(path) as f:
    m = yaml.safe_load(f)

m.setdefault("metadata", {}).update({
    "installed_at":    datetime.datetime.utcnow().isoformat() + "Z",
    "installed_sha":   actual_sha,
    "integrity_check": "passed",
})

with open(path, "w") as f:
    yaml.dump(m, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
print(f"Manifest updated: installed_at + integrity_check=passed")
PYEOF

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "========================================"
log " Skill installation complete ✓"
log "   ${SKILL_NAME}"
log "   Commit  : ${SKILL_COMMIT}"
log "   Target  : ${SKILL_TARGET}"
if [[ "${SKILL_ENABLED}" == "false" ]]; then
  warn "policy.enabled=false — this skill is installed but inactive."
  warn "To activate: set enabled: true in the manifest."
fi
log "========================================"
