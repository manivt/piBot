<p align="center">
  <img src="piBot_logo.png" alt="piBot Logo" width="180">
</p>

# piBot 🥧🤖

> **Autonomous "Bot in a Pi" Framework:** Run your own personal AI assistant 24/7 on a Raspberry Pi using ZeroClaw and Google Antigravity CLI (`agy`).

---

## What is piBot?

**piBot** turns an inexpensive Raspberry Pi (even an older 1 GB Pi 3B+) into an always-on, autonomous personal assistant that you chat with directly through **Telegram**.

### Why piBot?
- ⚡ **Lightweight Edge Orchestration:** Local LLMs on a Pi are notoriously slow and memory-hungry. Instead, piBot runs a featherweight local daemon (~50 MB RAM) to manage chat channels, execute safe local tools, and maintain persistent SQLite memory.
- 🧠 **Cloud-Backed Intelligence:** Natural language reasoning, coding, analysis, and planning are handled upstream via Google Antigravity CLI (`agy`).
- 🆓 **Works with Free Google Accounts:** You **do not** need a paid AI Pro or Ultra subscription. Any standard Google account can authenticate `agy` and use Gemini models for free under standard quotas. (Paid plans simply provide higher quotas and rate limits).
- 🔒 **Zero Inbound Open Ports:** Communicates with Telegram via outbound HTTPS long-polling. No port forwarding, no static IP, and no dynamic DNS required.
- 🛡️ **Strict Allowlist Security:** Only Telegram user IDs explicitly listed in your `.env` configuration can interact with the bot. Messages from all other senders are silently ignored.

---

## Architecture Overview

```text
Telegram Client
  │ (Outbound HTTPS Long Polling)
  ▼
ZeroClaw Daemon (:42617) ──► Local Tools (shell, file read/write, SQLite memory)
  │ (Routes model requests to custom endpoint)
  ▼
agy-shim Bridge (:8088)
  │ (Translates OpenAI API calls to CLI arguments)
  ▼
Antigravity CLI (`agy`)
  │ (OAuth authenticated via Google account)
  ▼
Google Cloud AI Models (Gemini 3.8 Flash, Medium, etc.)
```

---

## Hardware Requirements

- **Supported Boards:** Raspberry Pi 3 Model B+, Raspberry Pi 4, Raspberry Pi 5, or any Debian/Ubuntu ARM64/x86_64 host.
- **RAM:** Minimum 1 GB RAM (with a 1 GB swapfile recommended).
- **OS:** Debian GNU/Linux 12/13 (ARM64) or Raspberry Pi OS (64-bit).

For hardware notes and swap setup, see **[docs/HARDWARE.md](docs/HARDWARE.md)**.  
For deep architecture and flow details, see **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Quickstart Guide

### 1. Clone the Repository
```bash
git clone https://github.com/<your-username>/piBot.git
cd piBot
```

### 2. Install Prerequisites
Run the automated installer to install Go, Python 3, ZeroClaw, and the Antigravity CLI (`agy`):
```bash
./scripts/install-prereqs.sh
```

### 3. Authenticate Antigravity CLI (`agy`)
Authenticate with your Google account (works with both free Google accounts and Google AI Pro accounts):
```bash
agy auth login
```
Follow the terminal prompt to open the URL in your browser and complete authentication.

### 4. Configure Your Bot & Telegram Secrets
1. **Create a Telegram Bot:** Message [@BotFather](https://t.me/BotFather) on Telegram, run `/newbot`, and copy your bot token. *(Optional: Use `/setuserpic` in BotFather and upload `piBot_logo.png` to set your bot's icon).*
2. **Find Your Numeric Telegram ID:** Message [@userinfobot](https://t.me/userinfobot) to get your numeric user ID.
3. **Configure `.env`:**
   ```bash
   cp .env.example .env
   nano .env
   ```
   Fill in your token and allowed user ID:
   ```bash
   TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrSTUvwxYZ"
   TELEGRAM_ALLOWED_USERS="987654321"
   ```

### 5. Run the Automated Setup
```bash
./scripts/setup.sh
```
This script will:
- Compile the lightweight `agy-shim` Go binary.
- Deploy your agent's persona prompt files into `~/.zeroclaw/agents/pibot/workspace/`.
- Safely generate the hardened ZeroClaw `config.toml` (mode `0600`).
- Install and start the `agy-shim` (system) and `zeroclaw` (user) systemd services.

### 6. Verify System Health
```bash
./scripts/verify.sh
```
Once all checks pass, open Telegram and send a message to your bot! 🎉

---

## Customizing Your Bot's Persona

All personality and behavioral instructions are stored as plain Markdown files in `agent/workspace/`:

| File | Purpose |
|---|---|
| `AGENTS.md` | Core autonomous operating rules, file handling, and execution style |
| `IDENTITY.md` | Bot name, role, and vibe |
| `SOUL.md` | Core ethical boundaries, autonomy principles, and device focus |
| `TOOLS.md` | Environment documentation and description of available tools |
| `USER.md` | Your name, timezone, communication preferences, and context |
| `MEMORY.md` | Long-term memory template for durable user facts |

After customizing files in `agent/workspace/`, you can redeploy them at any time by rerunning `./scripts/setup.sh` or copying them to `~/.zeroclaw/agents/pibot/workspace/`.

---

## Managing Services

```bash
# View live bot logs
journalctl --user -u zeroclaw -f

# View agy-shim bridge logs
sudo journalctl -u agy-shim -f

# Restart services
sudo systemctl restart agy-shim
systemctl --user restart zeroclaw
```

---

## Optional: Docker Deployment

If you prefer running in Docker rather than systemd services, see the **[docker/README.md](docker/README.md)** guide.

---

## License

[MIT License](LICENSE) © 2026 piBot Contributors
