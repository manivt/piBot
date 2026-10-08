<p align="center">
  <img src="../piBot_logo.png" alt="piBot Logo" width="120">
</p>

# piBot: Docker Deployment Guide

This directory provides an optional containerized deployment for `piBot`.

## Prerequisites

- Docker and Docker Compose installed (`docker --version`, `docker compose version`)
- An authenticated `agy` installation on the host (`~/.gemini/`)
- A configured `.env` file in the repository root (see `.env.example`)

## Quickstart

1. Configure `.env` in the repository root:
   ```bash
   cp .env.example .env
   # Edit .env and set TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, and GEMINI_DATA_DIR
   ```
   *Note: `GEMINI_DATA_DIR` must be an absolute path to your host's `~/.gemini` directory (e.g. `/home/pi/.gemini`), as Docker Compose does not expand `~`.*

2. Authenticate `agy` on your host if you haven't already: run `agy` with no arguments, open the sign-in URL it prints, and exit the CLI once signed in.

3. Build and launch. Compose reads `${...}` variables from a `.env` next to the compose file by default, so point it at the repository-root `.env` explicitly:
   ```bash
   cd docker
   docker compose --env-file ../.env build
   docker compose --env-file ../.env up -d
   ```

4. View logs:
   ```bash
   docker compose --env-file ../.env logs -f
   ```

5. Stop container:
   ```bash
   docker compose --env-file ../.env down
   ```

The container user has no sudo rights, and the ZeroClaw ↔ agy-shim secret is generated on first start and kept in the ZeroClaw data volume. Bot output lands in `../workspaces/` by default, which is git-ignored.
