# PVE Infrastructure Automation

This repository contains automation tools for Proxmox VE (PVE) within the KpihX-Labs ecosystem.

## Modules

### Debian VM (`vm_debian/`)
Tools for deploying and managing Debian Cloud-Init VMs.

## Usage

### 🚀 Install a Debian VM
Run `make install` (alias for `make install-vm-debian`) with any environment variable overrides.

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
```bash
make purge VMID=102
```

## Configurable Options

| Variable | Description | Default |
| :--- | :--- | :--- |
| `VMID` | Unique Proxmox VM ID | `101` |
| `VMNAME` | Display name in Proxmox UI | `fluid-pve-debian` |
| `STORAGE` | Proxmox storage pool ID | `local-lvm` |
| `IMAGE` | Path to the Debian Cloud-Init qcow2 image | `/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2` |
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
| `SSH_KEYS_FILE`| Path to public keys on host | `~/.ssh/authorized_keys` |
| `CIPASSWORD` | Password for CI_USER | *(Prompted if empty)* |
