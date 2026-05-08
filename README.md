# PVE Infrastructure Automation

Central repository for Proxmox VE (PVE) automation tools in the KpihX-Labs ecosystem.

## Modules

- **[vm_debian](vm_debian/)**: Automation for Debian Cloud-Init VMs.

## Quick Start

You can run targets globally from this root using the `<module>_<target>` pattern, or use the shortcuts below.

### 🚀 Install Debian VM
```bash
make vm_debian_install VMID=102 STATIC_IP=10.10.10.102
```

### 🧹 Purge Debian VM
```bash
make vm_debian_purge VMID=102
```

## Global Management

| Target | Description |
| :--- | :--- |
| `make help` | Show all available global and sub-module targets |
| `make status`| Show git status (short) |
| `make push` | Push current branch to all remotes (GitHub/GitLab) |

---
*For detailed configuration options, see the [vm_debian/README.md](vm_debian/README.md).*
