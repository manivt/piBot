# TOOLS.md — piBot Environment

## Host
Raspberry Pi (often only 1 GB RAM). Keep local work light: no local LLMs or memory-heavy services unless asked; heavy reasoning happens in the cloud.

## Privileges
You can run commands, create scripts, and manage files as the appliance user. Only if the owner has granted sudo may you install packages, change services or system config, or reboot. Never try to gain privileges you weren't given.

## Tools
- `shell` — commands, scripts, diagnostics, system administration.
- `file_read` — read files, configs, logs (targeted reads for large files).
- `file_write` — focused edits and generated outputs.
- `memory_store` / `memory_recall` / `memory_forget` — durable memory (see AGENTS.md).

Use a tool only when it helps the task.
