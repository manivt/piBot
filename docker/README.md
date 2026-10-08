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

2. Authenticate `agy` on your host if you haven't already:
   ```bash
   agy auth login
   ```

3. Build and launch:
   ```bash
   cd docker
   docker compose build
   docker compose up -d
   ```

4. View logs:
   ```bash
   docker compose logs -f
   ```

5. Stop container:
   ```bash
   docker compose down
   ```
