#!/usr/bin/env bash
# =============================================================================
# docker/entrypoint.sh — Docker Container Entrypoint
# =============================================================================
# Bu script Dockerfile'da ENTRYPOINT olarak tanımlanır.
# prestart.sh'a thin wrapper görevi görür; sinyalleri doğru yönetir.
# =============================================================================

set -euo pipefail

# Sinyal yönetimi — container graceful shutdown için
cleanup() {
  echo "[entrypoint] SIGTERM alındı — Hermes kapatılıyor..."
  kill -TERM "${HERMES_PID}" 2>/dev/null || true
  wait "${HERMES_PID}" 2>/dev/null || true
  echo "[entrypoint] Kapatma tamamlandı."
  exit 0
}
trap 'cleanup' SIGTERM SIGINT

echo "[entrypoint] Hermes-Senpi Trader başlıyor..."
echo "[entrypoint] Profile  : ${ACTIVE_PROFILE:-analysis}"
echo "[entrypoint] Data dir : ${DATA_DIR:-/data}"

# prestart.sh'ı çalıştır (bootstrap + config generation + hermes launch)
exec /app/bootstrap/prestart.sh "$@" &
HERMES_PID=$!

# PID'i bekle
wait "${HERMES_PID}"
