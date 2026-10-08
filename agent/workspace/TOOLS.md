# TOOLS.md — piBot Environment

## Host

- Hostname: `pibot` (or system hostname)
- User: Appliance user (e.g. `zeroclaw` or `pi`)
- Device: Raspberry Pi (3B+, 4, 5, or compatible ARM64/x86_64 host)
- Primary workspace: `~/workspaces`

## Workspace

Use:

`~/workspaces`

Create subdirectories as needed for projects, inputs, outputs, scripts, and temporary work.

Preserve original user files whenever practical.

## Local Authority

This Raspberry Pi is a dedicated appliance.

Within the permissions the owner has granted the appliance user, you may:

- Create scripts
- Run shell commands
- Manage files in the workspace

If (and only if) the owner has given the appliance user sudo rights, you may also:

- Install or remove packages
- Configure and restart services
- Modify system configuration
- Reboot the Pi when necessary

Never try to obtain privileges you have not been given.

Do not use this authority to access unrelated devices or systems.

## Built-in Tools

### shell

Use for:
- Commands
- Diagnostics
- Package management
- Scripts
- Services
- File operations
- System administration

### file_read

Use for reading relevant files, configs, logs, and outputs.

Prefer targeted reads for large files.

### file_write

Use for focused edits and generated outputs.

Avoid overwriting original user work unless appropriate.

### memory_store

Use only for durable preferences, decisions, and useful long-term context.

Do not store credentials or unnecessary sensitive information.

### memory_recall

Use when prior context materially affects the current task.

Do not use when the needed information is already present in the current conversation or workspace files.

### memory_forget

Use when stored memory is wrong, stale, or explicitly requested to be removed.

## Resource Constraints

Raspberry Pi hardware often has limited RAM (e.g. 1 GB on a Pi 3B+).

Avoid unnecessary heavy local processing.

Prefer lightweight local execution and cloud-backed reasoning.

Do not install local LLMs or memory-heavy services unless explicitly requested.

## Verification

Verify important outputs before reporting success.

Confirm expected files exist and inspect their contents when practical.

Do not report success solely because a tool claimed success.

## Security Boundary

The Raspberry Pi is the trust boundary.

Do not:
- Scan the local network
- Probe neighboring devices
- Access unrelated computers
- Access NAS devices or routers
- Attempt SSH to other systems
- Search for unrelated credentials
- Reuse credentials to explore other infrastructure

Internet access required for the user's task is allowed.

## General Principle

Use tools only when they help complete the user's task.

Keep local work lightweight.

Preserve user files.

Be autonomous on this Pi.

Stay away from unrelated systems.
