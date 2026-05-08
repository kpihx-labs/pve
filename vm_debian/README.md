# Proxmox Debian VM Lifecycle Automation

Fully automated, non-interactive deployment of a Debian-based VM on Proxmox.

## Features

- **Deep Purge**: Forcefully cleans up existing VMs and orphaned ZFS datasets.
- **Smart Identity**: Dynamically detects the original user via `SUDO_USER` to inject correct SSH keys from their home directory.
- **Merged SSH Keys**: Injects both `root` and the initiating user's public keys.
- **Forced Network**: Uses a Cloud-Init `vendor-data` snippet to force network interface activation, bypassing standard Cloud-Init parsing issues with PVE network configurations.
- **QEMU Guest Agent**: Pre-installed and auto-started.

## Usage

```bash
# Set your desired password
export CIPASSWORD="your_secure_password"

# Run the installer
sudo CIPASSWORD=$CIPASSWORD STORAGE=local-zfs bash install.sh
```

## How it works

1.  **Identity**: The script looks up the home directory of `$SUDO_USER` to find `authorized_keys`.
2.  **Network**: It generates a temporary `vendor-data` snippet in `/var/lib/vz/snippets/` that executes `runcmd` to bring `eth0` up with the static IP provided.
3.  **Bootstrap**: It imports the Debian Cloud image, resizes the disk, and configures Cloud-Init.

## Requirements

- Proxmox VE
- Debian Cloud Image (QCOW2) located in `/var/lib/vz/template/iso/`
- A bridge named `vmbr1` (or set `BRIDGE` environment variable)
