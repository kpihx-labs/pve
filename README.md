# PVE VM Debian Infrastructure

This directory contains automation tools for deploying and managing Debian VMs on Proxmox VE within the KpihX-Labs ecosystem.

## Structure

- **`scripts/install.sh`**: Main script to instantiate a new Debian VM. It uses Cloud-Init to inject SSH keys, configure static networking, and install required agents.
- **`scripts/purge.sh`**: Utility script to cleanly stop and destroy a VM via its VMID, while also cleaning up Cloud-Init fragments on the PVE host.

## Usage via Makefile

From the module root:

### Install a VM
```bash
make install VMID=101 STATIC_IP=10.10.10.101
```

### Purge a VM
```bash
make purge VMID=101
```

## Default Parameters

The scripts use environment variables with sensible defaults for the lab:
- `CI_USER`: `kpihx`
- `BRIDGE`: `vmbr1`
- `STORAGE`: `local-lvm`
- `ROOT_GIB`: `300`
- `MEMORY_MIB`: `8192`
