# ==============================================================================
# docker/Dockerfile
# Multi-stage container definition for piBot.
# Builds the agy-shim loopback bridge from source and packages ZeroClaw + agy.
# Supports Linux ARM64, ARMv7 and AMD64 architectures.
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build the lightweight agy-shim Go translation bridge
# ------------------------------------------------------------------------------
FROM golang:1.24-bookworm AS shim-builder

WORKDIR /src
COPY agy-shim/go.mod agy-shim/main.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o agy-shim main.go

# ------------------------------------------------------------------------------
# Stage 2: piBot Runtime Container
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG ZEROCLAW_VERSION=0.8.5
ARG PUID=1000
ARG PGID=1000

ENV DEBIAN_FRONTEND=noninteractive

# Install essential runtime tools, libraries, python, and gosu for clean privilege dropping
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    bash \
    procps \
    jq \
    python3 \
    python3-pip \
    tzdata \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Create the unprivileged appliance user. It deliberately gets no sudo rights:
# the agent runs autonomously, so it should not be able to become root.
RUN groupadd -g "${PGID}" zeroclaw && \
    useradd -u "${PUID}" -g "${PGID}" -m -s /bin/bash zeroclaw

# Download and install Antigravity CLI (agy)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin || \
    (curl -fsSL https://antigravity.google/cli/install.sh | bash && mv /root/.local/bin/agy /usr/local/bin/agy)

# Download, checksum-verify and install the pinned ZeroClaw binary
RUN ARCH="$(uname -m)" && \
    case "${ARCH}" in \
      aarch64|arm64) TARGET_TRIPLE="aarch64-unknown-linux-gnu" ;; \
      x86_64|amd64)  TARGET_TRIPLE="x86_64-unknown-linux-gnu" ;; \
      armv7l)        TARGET_TRIPLE="armv7-unknown-linux-gnueabihf" ;; \
      *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    ASSET="zeroclaw-${TARGET_TRIPLE}.tar.gz" && \
    RELEASE_URL="https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${ZEROCLAW_VERSION}" && \
    cd /tmp && \
    curl -fsSL -o "${ASSET}" "${RELEASE_URL}/${ASSET}" && \
    curl -fsSL -o SHA256SUMS "${RELEASE_URL}/SHA256SUMS" && \
    grep -E "[[:space:]]\*?${ASSET}\$" SHA256SUMS | sha256sum -c - && \
    tar -xzf "${ASSET}" -C /usr/local/bin zeroclaw && \
    rm -f "${ASSET}" SHA256SUMS

# Copy compiled agy-shim from builder stage
COPY --from=shim-builder /src/agy-shim /usr/local/bin/agy-shim

# Ensure all core binaries are executable
RUN chmod +x /usr/local/bin/zeroclaw /usr/local/bin/agy /usr/local/bin/agy-shim

# Config template, shared renderer, and agent persona files (defaults + any
# git-ignored personal overrides in agent/local/) for container seeding
COPY config/zeroclaw/config.toml.template /etc/pibot/config.toml.template
COPY scripts/render-config.sh /usr/local/bin/pibot-render-config
COPY agent /etc/pibot/agent

# Copy container entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/pibot-render-config

# Prepare directory structure with proper ownership
RUN mkdir -p /home/zeroclaw/.zeroclaw \
             /home/zeroclaw/.gemini \
             /home/zeroclaw/workspaces && \
    chown -R zeroclaw:zeroclaw /home/zeroclaw

WORKDIR /home/zeroclaw/workspaces

ENV HOME=/home/zeroclaw
# /usr/sbin is needed for gosu, usermod and groupmod in the entrypoint
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/zeroclaw/.local/bin
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["daemon"]
