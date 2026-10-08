# Supported & Validated Hardware

`piBot` is designed to be lean enough to run 24/7 on low-power, inexpensive edge devices.

## Hardware Matrix

| Hardware | RAM | Status | Notes |
|---|---|---|---|
| **Raspberry Pi 3 Model B+** | 1 GB | **Verified Reference Baseline** | Minimum recommended. Requires ~1 GB swapfile. Idles around ~300 MB RAM usage. |
| **Raspberry Pi 4 Model B** | 2 GB / 4 GB / 8 GB | **Supported** | Plenty of headroom. Docker or bare-metal setup runs smoothly. |
| **Raspberry Pi 5** | 4 GB / 8 GB | **Supported** | Fast compilation and script execution. |
| **Raspberry Pi Zero 2 W** | 512 MB | Experimental | Tight RAM; recommend at least 1.5 GB swap. Bare-metal systemd only (no Docker). |
| **x86_64 / ARM64 Linux VM** | Any | **Supported** | Debian 12/13, Ubuntu 22.04/24.04, or similar modern Linux distributions. |

## Recommended Operating System

- **Debian GNU/Linux 12/13 (ARM64 / aarch64)** or **Raspberry Pi OS (64-bit)**.
- 64-bit OS is required because `agy` and `zeroclaw` release precompiled binaries for `aarch64`.

## Swap Configuration (Essential for 1 GB Boards)

If running on a 1 GB board (like the Pi 3B+), ensure a 1 GB swapfile is configured to prevent memory pressure during binary builds or compilation:

```bash
# Check current swap
free -h

# If swap is small (< 1 GB), adjust dphys-swapfile on Raspberry Pi OS:
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
```
