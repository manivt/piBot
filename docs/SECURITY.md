# piBot Security Guide

piBot is an autonomous agent: it runs shell commands and edits files on the Pi without asking first. This page explains the safeguards that ship with it and how to change them for your setup. Start with the **Security Model** section of the [README](../README.md).

---

## Local network protection

By default the bot is kept off your home network (computers, phones, router, NAS, cameras, smart plugs and so on) by two independent layers:

| Layer | Where | What it does | Can a clever request get around it? |
|---|---|---|---|
| **Persona rule** | `agent/workspace/AGENTS.md` ("Stay on this Pi") | Tells the bot to refuse local-network scans and access, even when asked | Possibly — it guides the model, it doesn't lock anything |
| **LAN guard firewall** | `systemd/pibot-lan-guard.nft`, loaded by `pibot-lan-guard.service` | Blocks the bot's Linux account from opening connections to local-network addresses | No — the operating system enforces it |

The rule gives you a polite explanation instead of an attempt; the firewall is what actually stops it, including when hidden instructions in a web page or file try to talk the bot into it.

### What the LAN guard blocks and allows

It applies only to the bot's user account (the user that runs `agy-shim` and ZeroClaw). For that account:

- **Blocked:** new connections to private and local addresses — `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, link-local `169.254.0.0/16`, CGNAT/Tailscale `100.64.0.0/10`, IPv6 `fc00::/7` and `fe80::/10`, plus multicast/broadcast discovery such as mDNS and SSDP. Attempts fail immediately ("Packet filtered", "No route to host" or "Operation not permitted").
- **Allowed:** the internet (Telegram, Google, GitHub, package downloads), DNS lookups, loopback (`127.0.0.1`, which the bot's own services use), and replies on connections that come *in* — so your SSH session into the Pi is unaffected.
- **Not affected:** other user accounts, and anything run with `sudo`.

**Side effect to know about:** if you log in to the Pi with the same account the bot uses (typical on a one-user Pi), connections *you* start from that account to other local devices are blocked too — for example `ssh` from the Pi to another computer. Use `sudo` for a one-off, allow that device (below), or turn the guard off.

**It only holds if the bot can't use `sudo`.** With passwordless sudo, the bot could remove the firewall itself. If `setup.sh` asked for your password, you're fine.

### Check that it's working

```bash
./scripts/verify.sh                 # check 8 pings your router as the bot's account and expects it to be blocked
sudo nft list table inet pibot_lan_guard    # show the active rules
systemctl status pibot-lan-guard
```

---

## Changing the defaults

### Option A — turn the firewall off

1. Edit `.env` and set:
   ```bash
   LAN_GUARD=off
   ```
2. Apply it:
   ```bash
   ./scripts/setup.sh
   ```
   This stops and removes the firewall service. `verify.sh` then reports check 8 as `SKIPPED`.

To turn it back on, set `LAN_GUARD=on` and rerun `./scripts/setup.sh`.

> The persona rule still makes the bot refuse local-network work. If you want it to actually do such tasks, also change the rule (Option C).

### Option B — allow only specific devices

Safer than turning the guard off: let the bot reach just the device(s) it needs, such as a printer or a home server.

1. Edit `systemd/pibot-lan-guard.nft` in your piBot folder and add an `accept` line for each device **above** the `reject` lines in the `bot` chain:
   ```
   chain bot {
           oifname "lo" accept
           ct state established,related accept
           meta l4proto { tcp, udp } th dport 53 accept
           ip daddr 192.168.1.50 accept          # e.g. home server
           ip daddr 192.168.1.60 tcp dport 631 accept   # e.g. printer, IPP only
           ip daddr @lan4 reject with icmpx admin-prohibited
           ip6 daddr @lan6 reject with icmpx admin-prohibited
   }
   ```
2. Apply it with `./scripts/setup.sh` (it checks the syntax before loading).

Give such devices a fixed IP (a DHCP reservation in your router) so the rule keeps pointing at the right one.

> This file is tracked by git, so a later `git pull` that changes it will conflict with your edit; keep a copy of your lines. If you publish your own fork, don't commit your home IP addresses.

### Option C — change what the bot is told

The rule lives in `agent/workspace/AGENTS.md`. Don't edit that file directly (it's tracked by git and would be overwritten by updates); override it instead:

```bash
mkdir -p agent/local
cp agent/workspace/AGENTS.md agent/local/AGENTS.md
nano agent/local/AGENTS.md      # edit the "Stay on this Pi" line
./scripts/setup.sh              # deploys your version
```

Files in `agent/local/` replace the defaults with the same name and are git-ignored, so your changes stay private. For example, to let the bot use one device you allowed in Option B:

```
- Stay on this Pi: never scan the local network or access other devices on it, except the home server at 192.168.1.50, which you may use when asked. Never look for or reuse credentials. Internet access the task needs is fine.
```

Keep the firewall and the rule consistent: a rule that allows something the firewall blocks just produces errors, and a firewall that allows something the rule forbids just goes unused.
