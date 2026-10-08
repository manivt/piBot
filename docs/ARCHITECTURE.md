<p align="center">
  <img src="../piBot_logo.png" alt="piBot Logo" width="120">
</p>

# piBot Architecture

`piBot` is designed around a single core insight: **low-power edge hardware (like a Raspberry Pi) makes a fantastic local orchestrator, but a poor LLM host.**

Instead of struggling to run small, quantized 4-bit local LLMs that melt the CPU and exhaust memory, `piBot` separates orchestration from inference:

```
+-------------------------------------------------------------+
|                      Telegram User                          |
+------------------------------+------------------------------+
                               |
                               v (HTTPS / Telegram Long Polling)
+-------------------------------------------------------------+
| piBot Appliance (Raspberry Pi)                              |
|                                                             |
|  [zeroclaw.service] (Systemd User Unit / port 42617)        |
|    - Channel manager: Telegram HTTPS long-polling           |
|    - Allowlist security: strictly ignores unlisted senders   |
|    - Local tool execution: shell, file read/write, memory   |
|    - Memory backend: SQLite BM25 long-term search           |
|    - Model client: OpenAI-compatible custom endpoint        |
|                                                             |
|                    | (HTTP POST /v1/chat/completions)       |
|                    v                                        |
|  [agy-shim.service] (Systemd System Unit / port 8088)       |
|    - Loopback HTTP Bridge (127.0.0.1:8088)                  |
|    - Translates OpenAI chat completions into `agy` CLI calls|
|    - Supervises CLI execution, timeouts, JSON parsing       |
|                                                             |
|                    | (Executes child CLI process)           |
|                    v                                        |
|  [Antigravity CLI (agy)]                                    |
|    - Headless agentic CLI worker                            |
|    - Free Google account or Google AI Pro                   |
|    - Secure OAuth token exchange                            |
+------------------------------+------------------------------+
                               |
                               v (HTTPS / gRPC)
+-------------------------------------------------------------+
|               Google Cloud AI Infrastructure                |
|              (Gemini 3.8 Flash, Pro, etc.)                  |
+-------------------------------------------------------------+
```

## Component Breakdown

1. **Telegram Client**:
   * Uses outbound HTTPS long polling.
   * No static public IP, no dynamic DNS, and no inbound router port forwarding required.
   * Secure by design behind NAT / firewalls.

2. **ZeroClaw Daemon**:
   * Lightweight Rust-based personal agent runtime.
   * Consumes ~30-50 MB RAM at idle.
   * Manages user authorization (`external_peers`), session history, and local tool execution (`shell`, `file_read`, `file_write`, `memory_*`).
   * Evaluates prompts and tool calls in a conversational loop.

3. **`agy-shim`**:
   * Ultra-lightweight Go microservice (<10 MB RAM).
   * Exposes standard `/v1/chat/completions` and `/health` endpoints on `127.0.0.1:8088`.
   * Formats the conversation messages and system prompts into `agy` CLI invocations.
   * Translates JSON response envelopes back into OpenAI format for ZeroClaw.

4. **Antigravity CLI (`agy`)**:
   * Google's developer CLI for AI agents.
   * Authenticates with Google accounts (both free tier and paid Google AI Pro plans).
   * Provides access to frontier models (Gemini Flash, etc.) without paying per-token API billing on credit cards.
