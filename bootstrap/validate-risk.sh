#!/usr/bin/env bash
# =============================================================================
# bootstrap/validate-risk.sh — Risk Policy Zorunlu Doğrulama
# =============================================================================
# Execution profili için risk_policy.yaml'ın varlığını ve
# zorunlu alanlarını kontrol eder. Herhangi bir hata → exit 1
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
RISK_POLICY="${DATA_DIR}/risk/risk_policy.yaml"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RISK ] $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RISK ] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Dosya varlığı
# ---------------------------------------------------------------------------
log "Risk policy doğrulama başlıyor: ${RISK_POLICY}"

if [[ ! -f "${RISK_POLICY}" ]]; then
  die "risk_policy.yaml bulunamadı: ${RISK_POLICY}
  Execution profili bu dosya olmadan başlatılamaz.
  Çözüm: /data/risk/risk_policy.yaml dosyasını oluşturun.
  Örnek: /app/config/risk_policy.example.yaml"
fi

# ---------------------------------------------------------------------------
# 2. Python ile zorunlu alan kontrolü (python3 mevcut olmalı)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import sys
import yaml
import os

risk_path = os.environ.get("DATA_DIR", "/data") + "/risk/risk_policy.yaml"

try:
    with open(risk_path) as f:
        policy = yaml.safe_load(f)
except Exception as e:
    print(f"HATA: risk_policy.yaml okunamadı: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(policy, dict):
    print("HATA: risk_policy.yaml geçerli bir YAML dict değil.", file=sys.stderr)
    sys.exit(1)

errors = []

# Zorunlu üst seviye anahtarlar
required_keys = ["version", "mode", "portfolio", "trading", "symbols", "execution", "audit"]
for key in required_keys:
    if key not in policy:
        errors.append(f"risk_policy.yaml içinde zorunlu alan eksik: '{key}'")

# Portfolio kontrolleri
portfolio = policy.get("portfolio", {})
if portfolio.get("max_daily_loss_usd", 0) <= 0:
    errors.append("portfolio.max_daily_loss_usd pozitif bir değer olmalı")
if portfolio.get("max_open_positions", 0) <= 0:
    errors.append("portfolio.max_open_positions pozitif bir değer olmalı")

# Symbols kontrolü
symbols = policy.get("symbols", {})
allowlist = symbols.get("allowlist", [])
if not allowlist:
    errors.append("symbols.allowlist boş olamaz — en az bir sembol ekleyin")

default_action = symbols.get("default_action", "")
if default_action != "deny":
    errors.append(f"symbols.default_action 'deny' olmalı, şu an: '{default_action}'")

# Execution güvenlik kontrolleri
execution = policy.get("execution", {})
if execution.get("allow_open_new_position", True):
    print("UYARI: execution.allow_open_new_position=true — dikkatli olun!", file=sys.stderr)

# Mode kontrolü
mode = policy.get("mode", "")
valid_modes = ["copilot", "semi-auto", "auto"]
if mode not in valid_modes:
    errors.append(f"mode '{mode}' geçersiz, geçerli değerler: {valid_modes}")

if errors:
    print("\nRisk policy doğrulama BAŞARISIZ:", file=sys.stderr)
    for e in errors:
        print(f"  ✗ {e}", file=sys.stderr)
    sys.exit(1)

print(f"Risk policy OK — mode={mode}, allowlist={allowlist}")
PYEOF

log "Risk policy doğrulama başarılı ✓"
