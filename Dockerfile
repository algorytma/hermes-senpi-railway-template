# =============================================================================
# Hermes-Senpi Trader — Dockerfile
# =============================================================================
# Base: ubuntu:22.04
# Hermes-agent is installed from source via official install.sh
# (no official pre-built Docker image exists)
#
# Runtime: stateless container, persistent state in /data (Railway Volume)
# =============================================================================

FROM ubuntu:22.04

ARG BUILD_DATE
ARG GIT_SHA
ARG HERMES_BRANCH=main

LABEL org.opencontainers.image.title="hermes-senpi-trader"
LABEL org.opencontainers.image.description="Hermes AI trading agent with Senpi MCP integration"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/algorytma/hermes-senpi-railway-template"

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    ca-certificates \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    libffi-dev \
    ripgrep \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install uv (fast Python package manager, required by hermes install.sh)
# ---------------------------------------------------------------------------
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:/root/.cargo/bin:${PATH}"

# ---------------------------------------------------------------------------
# Install Hermes-Agent from source (official method)
# --skip-setup  : skip interactive wizard (will be configured via /data/config)
# --no-venv     : use system Python to keep image size down
# HERMES_INSTALL_DIR: pin install location
# ---------------------------------------------------------------------------
ENV HERMES_INSTALL_DIR=/opt/hermes-agent
ENV HERMES_HOME=/root/.hermes

RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --skip-setup --branch "${HERMES_BRANCH}"

# Ensure hermes binary is on PATH
RUN ln -sf /root/.local/bin/hermes /usr/local/bin/hermes 2>/dev/null || \
    ln -sf /opt/hermes-agent/venv/bin/hermes /usr/local/bin/hermes 2>/dev/null || \
    find /root -name hermes -type f -executable 2>/dev/null | head -1 | \
    xargs -I{} ln -sf {} /usr/local/bin/hermes

# ---------------------------------------------------------------------------
# Python deps for our bootstrap scripts
# ---------------------------------------------------------------------------
RUN pip3 install --no-cache-dir pyyaml

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
# Build metadata
# ---------------------------------------------------------------------------
RUN echo "{\"build_date\":\"${BUILD_DATE}\",\"git_sha\":\"${GIT_SHA}\",\"hermes_branch\":\"${HERMES_BRANCH}\"}" \
    > /app/build-info.json

# ---------------------------------------------------------------------------
# Env defaults
# NOTE: /data volume is mounted by Railway at platform level — no VOLUME here.
# ---------------------------------------------------------------------------
ENV DATA_DIR=/data
ENV ACTIVE_PROFILE=analysis

# ---------------------------------------------------------------------------
# Healthcheck
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
    CMD test -f /data/.runtime/version.json || exit 1

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
ENTRYPOINT ["/app/bootstrap/prestart.sh"]
