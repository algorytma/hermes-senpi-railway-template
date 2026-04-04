#!/usr/bin/env bash
# =============================================================================
# scripts/lib/redact.sh — Secret Redaction Library
# =============================================================================
# Source this file in any script that might log environment context.
#
# Usage:
#   source /app/scripts/lib/redact.sh
#   log "Provider: $(redact_env OPENROUTER_API_KEY)"
#   redact_check  # logs a warning if known secrets are set without redaction
#
# Rules:
#   - Never log the VALUE of a secret env var
#   - Only log the NAME and whether it is set
# =============================================================================

# List of env vars that must NEVER be logged as values
REDACTED_ENV_VARS=(
  OPENROUTER_API_KEY
  OPENAI_API_KEY
  NVIDIA_API_KEY
  DASHSCOPE_API_KEY
  ZAI_API_KEY
  KIMI_API_KEY
  MINIMAX_API_KEY
  SENPI_AUTH_TOKEN
  TELEGRAM_BOT_TOKEN
  ADMIN_SETUP_TOKEN
  BACKUP_ENCRYPTION_PASSPHRASE
  OPENCLAW_GATEWAY_TOKEN
)

# ---------------------------------------------------------------------------
# redact_env VAR_NAME
# Prints "<VAR_NAME>=***SET***" if the var is set, "<VAR_NAME>=<not set>" otherwise.
# Never prints the actual value.
# ---------------------------------------------------------------------------
redact_env() {
  local var_name="${1}"
  if [[ -n "${!var_name:-}" ]]; then
    echo "${var_name}=***SET***"
  else
    echo "${var_name}=<not set>"
  fi
}

# ---------------------------------------------------------------------------
# redact_check
# Checks if any known secret vars are set, and logs their STATUS (not value).
# ---------------------------------------------------------------------------
redact_check() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SECU ] Secret env var status:"
  for var in "${REDACTED_ENV_VARS[@]}"; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SECU ]   $(redact_env "${var}")"
  done
}

# ---------------------------------------------------------------------------
# is_secret_var VAR_NAME
# Returns 0 (true) if the var is in the redact list
# ---------------------------------------------------------------------------
is_secret_var() {
  local var_name="${1}"
  for secret in "${REDACTED_ENV_VARS[@]}"; do
    if [[ "${var_name}" == "${secret}" ]]; then
      return 0
    fi
  done
  return 1
}
