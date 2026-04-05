# =============================================================================
# Hermes-Senpi Trader — Dockerfile
# =============================================================================
# Base: NousResearch/hermes-agent (pinned release)
# Runtime: ephemeral container, persistent state /data volume
#
# HERMES_VERSION build arg ile version pinlenir.
# Örnek: docker build --build-arg HERMES_VERSION=v0.6.0 .
# =============================================================================

ARG HERMES_VERSION=v0.6.0

# ---------------------------------------------------------------------------
# Stage 1: Hermes base image
# ---------------------------------------------------------------------------
FROM ghcr.io/nousresearch/hermes-agent:${HERMES_VERSION}

# Build zamanı metadata
ARG HERMES_VERSION
ARG BUILD_DATE
ARG GIT_SHA

LABEL org.opencontainers.image.title="hermes-senpi-trader"
LABEL org.opencontainers.image.description="Hermes AI trading agent with Senpi MCP integration"
LABEL org.opencontainers.image.version="${HERMES_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/YOUR_ORG/hermes-senpi-trader"

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    git \
    python3 \
    python3-pip \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies (render-config.py için)
RUN pip3 install --no-cache-dir pyyaml==6.0.2

# ---------------------------------------------------------------------------
# Uygulama dosyaları
# ---------------------------------------------------------------------------
WORKDIR /app

# Bootstrap script'leri
COPY bootstrap/ /app/bootstrap/
RUN chmod +x /app/bootstrap/*.sh

# Python scripts
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh 2>/dev/null || true

# Default config templates (first-run init için)
COPY defaults/ /app/defaults/

# Config examples (kullanıcı referansı için - /app/config altında kalır)
COPY config/ /app/config/

# Migration scripts
COPY migrations/ /app/migrations/
RUN chmod +x /app/migrations/*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# Runtime version bilgisi (image içine göm)
# ---------------------------------------------------------------------------
RUN echo "{\"hermes_version\":\"${HERMES_VERSION}\",\"build_date\":\"${BUILD_DATE}\",\"git_sha\":\"${GIT_SHA}\"}" \
    > /app/build-info.json

# ---------------------------------------------------------------------------
# Volume ve env ayarları
# ---------------------------------------------------------------------------
# VOLUME ["/data"]

ENV DATA_DIR=/data
ENV ACTIVE_PROFILE=analysis
ENV HERMES_VERSION=${HERMES_VERSION}

# ---------------------------------------------------------------------------
# Sağlık kontrolü
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD test -f /data/.runtime/version.json || exit 1

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
ENTRYPOINT ["/app/bootstrap/prestart.sh"]
