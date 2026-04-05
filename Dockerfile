# =============================================================================
# Hermes-Senpi Trader — Dockerfile
# =============================================================================
# Base: nousresearch/hermes-agent (Docker Hub, official image)
# Runtime: ephemeral container, persistent state at /data (Railway Volume)
#
# Build:
#   docker build --build-arg HERMES_VERSION=latest -t hermes-senpi-trader .
#
# Run locally:
#   docker run --rm -e ACTIVE_PROFILE=analysis -e DATA_DIR=/data \
#     -e OPENROUTER_API_KEY=sk-... \
#     -v $(pwd)/.tmpdata:/data \
#     hermes-senpi-trader
# =============================================================================

ARG HERMES_VERSION=latest

# ---------------------------------------------------------------------------
# Base: official Docker Hub image (nousresearch/hermes-agent)
# NOTE: ghcr.io/nousresearch/hermes-agent is NOT publicly available.
#       The official public image is on Docker Hub.
# ---------------------------------------------------------------------------
FROM nousresearch/hermes-agent:${HERMES_VERSION}

ARG HERMES_VERSION
ARG BUILD_DATE
ARG GIT_SHA

LABEL org.opencontainers.image.title="hermes-senpi-trader"
LABEL org.opencontainers.image.description="Hermes AI trading agent with Senpi MCP integration"
LABEL org.opencontainers.image.version="${HERMES_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/algorytma/hermes-senpi-railway-template"

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    git \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies (render-config.py)
RUN pip3 install --no-cache-dir --break-system-packages pyyaml 2>/dev/null \
    || pip3 install --no-cache-dir pyyaml

# ---------------------------------------------------------------------------
# Application files
# ---------------------------------------------------------------------------
WORKDIR /app

COPY bootstrap/ /app/bootstrap/
RUN chmod +x /app/bootstrap/*.sh

COPY scripts/ /app/scripts/
RUN find /app/scripts -name "*.sh" -exec chmod +x {} \;

COPY defaults/ /app/defaults/
COPY config/   /app/config/

COPY migrations/ /app/migrations/
RUN find /app/migrations -name "*.sh" -exec chmod +x {} \;

# ---------------------------------------------------------------------------
# Build metadata baked into image
# ---------------------------------------------------------------------------
RUN echo "{\"hermes_version\":\"${HERMES_VERSION}\",\"build_date\":\"${BUILD_DATE}\",\"git_sha\":\"${GIT_SHA}\"}" \
    > /app/build-info.json

# ---------------------------------------------------------------------------
# Env defaults
# NOTE: Volume is mounted by Railway at /data — do NOT declare VOLUME here.
#       See: https://docs.railway.com/volumes/overview
# ---------------------------------------------------------------------------
ENV DATA_DIR=/data
ENV ACTIVE_PROFILE=analysis
ENV HERMES_VERSION=${HERMES_VERSION}

# ---------------------------------------------------------------------------
# Healthcheck
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
    CMD test -f /data/.runtime/version.json || exit 1

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
ENTRYPOINT ["/app/bootstrap/prestart.sh"]
