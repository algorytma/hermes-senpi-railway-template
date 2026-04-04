#!/usr/bin/env bash
# =============================================================================
# bootstrap/validate-risk.sh — Risk Policy Validation Gate
# =============================================================================
# Validates risk_policy.yaml before the execution profile is allowed to start.
# Any validation failure causes an immediate exit 1, blocking container boot.
#
# Usage:
#   DATA_DIR=/data bash bootstrap/validate-risk.sh
#
# Called by: bootstrap/prestart.sh (execution profile only)
# =============================================================================

set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
RISK_POLICY="${DATA_DIR}/risk/risk_policy.yaml"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RISK ] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RISK ] WARN: $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RISK ] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

log "Risk policy validation starting: ${RISK_POLICY}"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
if [[ ! -f "${RISK_POLICY}" ]]; then
  echo "" >&2
  echo "  ┌─────────────────────────────────────────────────────────────┐" >&2
  echo "  │  EXECUTION PROFILE BLOCKED — risk_policy.yaml not found     │" >&2
  echo "  │                                                             │" >&2
  echo "  │  The execution profile requires a valid risk policy file.   │" >&2
  echo "  │                                                             │" >&2
  echo "  │  Fix:                                                       │" >&2
  echo "  │    cp /app/config/risk_policy.example.yaml \\               │" >&2
  echo "  │       ${DATA_DIR}/risk/risk_policy.yaml          │" >&2
  echo "  │    # Edit the file, then redeploy.                          │" >&2
  echo "  └─────────────────────────────────────────────────────────────┘" >&2
  echo "" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Deep YAML validation via Python
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import sys
import os
import yaml

risk_path = os.environ.get("DATA_DIR", "/data") + "/risk/risk_policy.yaml"

# --- Parse ---
try:
    with open(risk_path) as f:
        policy = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f"  ERROR: risk_policy.yaml is not valid YAML: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"  ERROR: Cannot read risk_policy.yaml: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(policy, dict):
    print("  ERROR: risk_policy.yaml must be a YAML mapping (dict), got: "
          f"{type(policy).__name__}", file=sys.stderr)
    sys.exit(1)

errors   = []
warnings = []

# --- Required top-level keys ---
REQUIRED_KEYS = ["mode", "trading", "symbols", "execution"]
for key in REQUIRED_KEYS:
    if key not in policy:
        errors.append(f"Missing required field: '{key}'")

trading   = policy.get("trading",   {}) or {}
symbols   = policy.get("symbols",   {}) or {}
execution = policy.get("execution", {}) or {}

# --- mode ---
mode = policy.get("mode", "")
VALID_MODES = ["copilot", "semi-auto", "auto"]
if not isinstance(mode, str) or mode not in VALID_MODES:
    errors.append(f"'mode' must be one of {VALID_MODES}, got: {repr(mode)}")

# --- trading.max_leverage ---
max_leverage = trading.get("max_leverage")
if max_leverage is None:
    errors.append("Missing required field: 'trading.max_leverage'")
elif not isinstance(max_leverage, (int, float)) or max_leverage <= 0:
    errors.append(f"'trading.max_leverage' must be a positive number, got: {repr(max_leverage)}")
elif max_leverage > 10:
    errors.append(f"'trading.max_leverage' is dangerously high ({max_leverage}x) — max allowed: 10")
elif max_leverage > 5:
    warnings.append(f"trading.max_leverage={max_leverage}x is high — consider ≤5 for initial deployment")

# --- trading.max_position_size_usd ---
max_pos = trading.get("max_position_size_usd")
if max_pos is None:
    errors.append("Missing required field: 'trading.max_position_size_usd'")
elif not isinstance(max_pos, (int, float)) or max_pos <= 0:
    errors.append(f"'trading.max_position_size_usd' must be a positive number, got: {repr(max_pos)}")

# --- trading.max_daily_loss_usd ---
max_loss = trading.get("max_daily_loss_usd")
if max_loss is None:
    errors.append("Missing required field: 'trading.max_daily_loss_usd'")
elif not isinstance(max_loss, (int, float)) or max_loss <= 0:
    errors.append(f"'trading.max_daily_loss_usd' must be a positive number, got: {repr(max_loss)}")

# --- execution.dry_run_default ---
dry_run = execution.get("dry_run_default")
if dry_run is None:
    errors.append("Missing required field: 'execution.dry_run_default'")
elif not isinstance(dry_run, bool):
    errors.append(
        f"'execution.dry_run_default' must be a boolean (true/false), got: {repr(dry_run)}"
    )

# --- execution.allow_open_new_position ---
allow_open = execution.get("allow_open_new_position")
if allow_open is None:
    errors.append("Missing required field: 'execution.allow_open_new_position'")
elif not isinstance(allow_open, bool):
    errors.append(
        f"'execution.allow_open_new_position' must be a boolean, got: {repr(allow_open)}"
    )
elif allow_open is True:
    warnings.append(
        "execution.allow_open_new_position=true — the agent can open new positions. "
        "Ensure this is intentional and risk limits are reviewed."
    )

# --- symbols.allowlist ---
allowlist = symbols.get("allowlist")
if not allowlist:
    errors.append(
        "'symbols.allowlist' must be a non-empty list — at least one symbol required. "
        "Example: [\"BTC\", \"ETH\"]"
    )
elif not isinstance(allowlist, list):
    errors.append(f"'symbols.allowlist' must be a list, got: {type(allowlist).__name__}")

# --- symbols.default_action ---
default_action = symbols.get("default_action", "")
if default_action != "deny":
    errors.append(
        f"'symbols.default_action' MUST be 'deny' (got: {repr(default_action)}). "
        "This is a hard safety requirement — all non-allowlist symbols must be denied."
    )

# --- Print warnings ---
for w in warnings:
    print(f"  [WARN] {w}", file=sys.stderr)

# --- Print errors and exit ---
if errors:
    print("", file=sys.stderr)
    print("  ╔══════════════════════════════════════════════════════════════╗", file=sys.stderr)
    print("  ║   RISK POLICY VALIDATION FAILED — Execution blocked         ║", file=sys.stderr)
    print("  ╠══════════════════════════════════════════════════════════════╣", file=sys.stderr)
    for e in errors:
        print(f"  ║  ✗ {e:<58}║", file=sys.stderr)
    print("  ╠══════════════════════════════════════════════════════════════╣", file=sys.stderr)
    print(f"  ║  File: {risk_path:<54}║", file=sys.stderr)
    print("  ║  Fix the above errors and redeploy.                         ║", file=sys.stderr)
    print("  ╚══════════════════════════════════════════════════════════════╝", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

# --- Summary ---
print(f"  Risk policy OK")
print(f"    mode                     = {mode}")
print(f"    dry_run_default          = {dry_run}")
print(f"    allow_open_new_position  = {allow_open}")
print(f"    max_leverage             = {max_leverage}x")
print(f"    max_position_size_usd    = ${max_pos}")
print(f"    max_daily_loss_usd       = ${max_loss}")
print(f"    allowlist                = {allowlist}")
print(f"    default_action           = {default_action}")
PYEOF

log "Risk policy validation passed ✓"
