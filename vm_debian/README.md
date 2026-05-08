# Proxmox Debian VM Lifecycle Automation

> 🏛️ **Sovereign Infrastructure**: Fully automated, non-interactive deployment of Debian Cloud instances on Proxmox VE. 0 Hardcoding · 100% Control.

This suite provides a robust, repeatable pattern for bootstrapping Debian VMs with accurate Cloud-Init provisioning, hardened security, and deep lifecycle management.

## 🚀 Key Features

- **Smart Identity Injection**: Dynamically detects the initiating user via `SUDO_USER` to merge their personal SSH keys (from their local home) with the hypervisor's root keys.
- **Forced Network Layer**: Implements a dedicated `vendor-data` snippet to guarantee network interface activation on the first boot, bypassing common Cloud-Init V1 parsing failures in Debian Cloud images.
- **Deep Purge Invariant**: A specialized utility that ensures zero configuration drift by forcefully removing VMs, recursive ZFS datasets, and orphaned snippets.
- **Premium Documentation**: Every script is richly documented in English, detailing the rationale behind each architectural decision.

## 🛠️ Usage

### Installation

The installer supports both interactive prompts and environment variable overrides for automated pipelines.

```bash
# Optional: Set your desired password in env to bypass prompt
export CIPASSWORD="your_secure_password"

# Run the deployment (requires sudo)
sudo -E ./install.sh
```

### Deep Purge

Clean up everything related to a VMID to restore a pristine state.

```bash
# Interactive mode
sudo ./purge.sh

# Automated mode
sudo ./purge.sh -y 101
```

## 🏗️ Architecture

1.  **Fabric Identification**: The script anchors the VM identity based on the PVE host's `SUDO_USER`.
2.  **Storage Agnosticism**: Compatible with `local-zfs` and `local-lvm` backends with automatic ZFS orphan detection.
3.  **Networking**: Defaults to `vmbr1` for lab isolation, using VirtIO for maximum throughput.

---
**KπX — Global Agent Kernel Compliance**
*Exploration: Problem First → Why before How → Visualization*
