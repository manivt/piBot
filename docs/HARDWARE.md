# Hardware & OS

`piBot` is designed to be lean enough to run 24/7 on low-power, inexpensive devices. So far it has been tested end to end on one setup; others are expected to work but haven't been verified yet.

## Hardware Matrix

| Hardware | RAM | Status | Notes |
|---|---|---|---|
| **Raspberry Pi 3 Model B+** | 1 GB | **Tested** | Reference setup. Needs ~1 GB of swap (see below). |
| **Raspberry Pi 4 Model B** | 2 GB / 4 GB / 8 GB | Should work, untested | Same 64-bit OS and software as the Pi 3B+, with more headroom. |
| **Raspberry Pi 5** | 4 GB / 8 GB | Should work, untested | As above. |
| **Raspberry Pi Zero 2 W** | 512 MB | Untested | Very tight on RAM; would need at least 1.5 GB of swap. |
| **x86_64 Debian 13 machine or VM** | Any | Partly tested | Install, setup and `verify.sh` ran successfully; a full Telegram + `agy` run hasn't been done. |
| **Other 64-bit Linux (Debian 12, Ubuntu, …)** | Any | Untested | Likely to work if it's Debian-based with systemd. |

Tried it on something else? It's a use-at-your-own-risk project, but if `./scripts/verify.sh` passes and the bot answers on Telegram, that's a good sign it works.

## Operating System

- **Tested:** Raspberry Pi OS Lite (64-bit), based on Debian 13 "Trixie".
- A **64-bit** OS is required: `agy` and `zeroclaw` ship precompiled 64-bit binaries.

## Swap Configuration (Essential for 1 GB Boards)

If running on a 1 GB board (like the Pi 3B+), make sure roughly 1 GB of swap is available to prevent memory pressure while building `agy-shim`:

```bash
free -h
```

If the `Swap` line already shows about 900 MB or more, you're done — recent Raspberry Pi OS releases set this up automatically (often as compressed RAM swap; `swapon --show` tells you which).

Only on older images that still use `dphys-swapfile` (check with `which dphys-swapfile`) and show less than 1 GB of swap:

```bash
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
```
