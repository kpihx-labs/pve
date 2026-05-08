# PVE Module: Debian VM

Automation tools for deploying and managing Debian Cloud-Init VMs on Proxmox VE.

## 🚀 Key Features

- **Smart Identity Injection**: Dynamically detects the initiating user via `SUDO_USER` to merge their personal SSH keys with the hypervisor's root keys.
- **Forced Network Layer**: Implements a dedicated `vendor-data` snippet to guarantee network interface activation on the first boot, bypassing common Cloud-Init V1 parsing failures.
- **Deep Purge Invariant**: A specialized utility that ensures zero configuration drift by forcefully removing VMs, recursive ZFS datasets, and orphaned snippets.

## ## Usage

### 🚀 Install a VM
Run `make install` from this directory.

#### Basic Example
```bash
make install VMID=102 STATIC_IP=10.10.10.102
```

#### Full Customization Example
```bash
make install \
  VMID=200 \
  VMNAME=fluid-pve-debian \
  STORAGE=local-zfs \
  CORES=8 \
  MEMORY_MIB=16384 \
  ROOT_GIB=300 \
  STATIC_IP=10.10.10.200 \
  GATEWAY=10.10.10.1 \
  DNS=1.1.1.1,1.0.0.1
```

### 🧹 Purge a VM
Clean up everything related to a VMID to restore a pristine state.

#### Remote Purge (One-Liner):
```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/kpihx-labs/pve/master/vm_debian/scripts/purge.sh)"
```

#### Local Purge:
```bash
# Interactive mode
sudo ./purge.sh

# Automated mode
sudo ./purge.sh -y 101
```

### 🌐 Remote Execution (One-Liner)
Ideal for bootstrapping new PVE nodes without cloning the entire repository. This method ensures you have the latest version of the scripts directly from the source.

> [!IMPORTANT]
> Use `sudo bash -c "$(curl ...)"` to ensure environment variables are correctly passed to the sub-shell and that the script has the necessary privileges to execute `qm` commands.

```bash
sudo VMID=110 \
  VMNAME=homelab \
  STORAGE=local-zfs \
  CORES=4 \
  MEMORY_MIB=8192 \
  ROOT_GIB=300 \
  STATIC_IP=10.10.10.110 \
  GATEWAY=10.10.10.1 \
  BRIDGE=vmbr1 \
  CI_USER=kpihx \
  bash -c "$(curl -sSL https://raw.githubusercontent.com/kpihx-labs/pve/master/vm_debian/scripts/install.sh)"
```

## ## Configurable Options

| Variable | Description | Default |
| :--- | :--- | :--- |
| `VMID` | Unique Proxmox VM ID | `101` |
| `VMNAME` | Display name in Proxmox UI | `fluid-pve-debian` |
| `STORAGE` | Proxmox storage pool ID | `local-lvm` |
| `IMAGE` | Path to the Debian Cloud-Init qcow2 image | `/var/lib/vz/template/iso/debian-12-generic...` |
| `CORES` | Number of CPU cores | `4` |
| `SOCKETS` | Number of CPU sockets | `1` |
| `MEMORY_MIB` | RAM allocation in MiB | `8192` |
| `ROOT_GIB` | Disk size in GiB | `300` |
| `BRIDGE` | Network bridge on host | `vmbr1` |
| `STATIC_IP` | Static IP for the VM | `10.10.10.101` |
| `PREFIX` | Network mask prefix | `24` |
| `GATEWAY` | Default gateway IP | `10.10.10.1` |
| `DNS` | DNS servers (comma-separated) | `1.1.1.1,8.8.8.8` |
| `SEARCHDOMAIN` | DNS search domain | `kpihxlabs.com` |
| `CI_USER` | Cloud-Init username | `kpihx` |
| `SSH_KEYS_FILE` | Path to public keys on host | `~/.ssh/authorized_keys` |
| `CIPASSWORD` | Password for CI_USER | *(Prompted if empty)* |

> [!IMPORTANT]
> **Network Alignment**: Ensure the `BRIDGE` selected on the host matches the subnet defined by `STATIC_IP`, `PREFIX`, and `GATEWAY`.

## 🔑 Post-Installation: Access & Operations

### 1. SSH Access (Public Key Only)
By default, password login is disabled if no `CIPASSWORD` was provided. You must use a matching private key.

**From your workspace:**
```bash
ssh <CI_USER>@<STATIC_IP>
```

**If you get `Permission denied (publickey)`:**
Ensure your initiating host (PVE) has an SSH identity. If not, generate one:
`ssh-keygen -t ed25519` and redeploy.

### 2. Emergency / Debug Access (Serial Console)
If the network is unreachable or SSH fails, use the Proxmox serial terminal:

```bash
sudo qm terminal <VMID>
# Use Ctrl+O to exit the terminal
```

### 3. Monitoring
Check the status and configuration from the PVE host:
```bash
sudo qm status <VMID>
sudo qm config <VMID>
```

## 🏗️ Architecture

1.  **Fabric Identification**: The script anchors the VM identity based on the PVE host's `SUDO_USER`.
2.  **Storage Agnosticism**: Compatible with `local-zfs` and `local-lvm` backends with automatic ZFS orphan detection.
3.  **Networking**: Defaults to `vmbr1` for lab isolation, using VirtIO for maximum throughput.

---
**KπX — Global Agent Kernel Compliance**
*Exploration: Problem First → Why before How → Visualization*
