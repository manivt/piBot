# ==============================================================================
# docker/Dockerfile
# Multi-stage container definition for piBot.
# Builds the agy-shim loopback bridge from source and packages ZeroClaw + agy.
# Supports Linux ARM64 and AMD64 architectures.
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
    sudo \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Create appliance user and group matching host permissions
RUN groupadd -g "${PGID}" zeroclaw && \
    useradd -u "${PUID}" -g "${PGID}" -m -s /bin/bash zeroclaw && \
    echo "zeroclaw ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Download and install Antigravity CLI (agy)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin || \
    (curl -fsSL https://antigravity.google/cli/install.sh | bash && mv /root/.local/bin/agy /usr/local/bin/agy)

# Download and install ZeroClaw binary (pinned version)
RUN ARCH="$(uname -m)" && \
    case "${ARCH}" in \
      aarch64|arm64) TARGET_TRIPLE="aarch64-unknown-linux-gnu" ;; \
      x86_64|amd64)  TARGET_TRIPLE="x86_64-unknown-linux-gnu" ;; \
      *)             TARGET_TRIPLE="" ;; \
    esac && \
    if [ -n "${TARGET_TRIPLE}" ]; then \
      curl -fsSL "https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${ZEROCLAW_VERSION}/zeroclaw-${TARGET_TRIPLE}.tar.gz" | tar -xz -C /usr/local/bin && \
      chmod +x /usr/local/bin/zeroclaw; \
    else \
      curl -fsSL https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/install.sh | sh -s -- --prebuilt --skip-quickstart && \
      mv /root/.cargo/bin/zeroclaw /usr/local/bin/zeroclaw; \
    fi

# Copy compiled agy-shim from builder stage
COPY --from=shim-builder /src/agy-shim /usr/local/bin/agy-shim

# Ensure all core binaries are executable
RUN chmod +x /usr/local/bin/zeroclaw /usr/local/bin/agy /usr/local/bin/agy-shim

# Copy canonical config template and agent workspace persona files for container seeding
COPY config/zeroclaw/config.toml.template /etc/pibot/config.toml.template
COPY agent/workspace /etc/pibot/workspace

# Copy container entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prepare directory structure with proper ownership
RUN mkdir -p /home/zeroclaw/.zeroclaw \
             /home/zeroclaw/.gemini \
             /home/zeroclaw/workspaces && \
    chown -R zeroclaw:zeroclaw /home/zeroclaw

WORKDIR /home/zeroclaw/workspaces

ENV HOME=/home/zeroclaw
ENV PATH=/usr/local/bin:/usr/bin:/bin:/home/zeroclaw/.local/bin
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["daemon"]
