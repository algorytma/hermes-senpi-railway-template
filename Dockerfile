# =============================================================================
# Hermes-Senpi Trader — Dockerfile
# =============================================================================
# Multi-stage build based on the pattern from lovexbytes/hermes-railway-template.
# Hermes-agent is installed from source (no public Docker image exists).
#
# Stage 1 (builder): clone + venv + pip install
# Stage 2 (runtime): minimal image + our bootstrap scripts
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Builder — clone hermes-agent and install into venv
# ---------------------------------------------------------------------------
FROM python:3.11-slim AS builder

ARG HERMES_GIT_REF=main

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 --branch "${HERMES_GIT_REF}" --recurse-submodules \
    https://github.com/NousResearch/hermes-agent.git

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir -e "/opt/hermes-agent[messaging,cron,cli,pty]"

# Our Python bootstrap dependencies
RUN pip install --no-cache-dir pyyaml

# ---------------------------------------------------------------------------
# Stage 2: Runtime — lean image with hermes venv + our scripts
# ---------------------------------------------------------------------------
FROM python:3.11-slim

ARG BUILD_DATE
ARG GIT_SHA
ARG HERMES_GIT_REF=main

LABEL org.opencontainers.image.title="hermes-senpi-trader"
LABEL org.opencontainers.image.description="Hermes AI trading agent with Senpi MCP integration"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/algorytma/hermes-senpi-railway-template"

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    tini \
    git \
    jq \
    curl \
  && rm -rf /var/lib/apt/lists/*

# Venv + hermes-agent source from builder
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/hermes-agent /opt/hermes-agent

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    HERMES_HOME=/data/.hermes \
    HOME=/data \
    DATA_DIR=/data \
    ACTIVE_PROFILE=analysis

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
RUN find /app/migrations -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Build metadata
RUN echo "{\"build_date\":\"${BUILD_DATE}\",\"git_sha\":\"${GIT_SHA}\",\"hermes_branch\":\"${HERMES_GIT_REF}\"}" \
    > /app/build-info.json

# ---------------------------------------------------------------------------
# Healthcheck: verify hermes process is running.
# Uses a generous start-period (180s) to allow bootstrap to complete.
# NOTE: No healthcheckPath in railway.toml — Railway uses process health.
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD pgrep -f hermes > /dev/null || test -f /data/.runtime/version.json

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
ENTRYPOINT ["tini", "--"]
CMD ["/app/bootstrap/prestart.sh"]
