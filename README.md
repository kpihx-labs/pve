# PVE Infrastructure Automation

Central repository for Proxmox VE automation modules in the KpihX-Labs ecosystem.

## Modules

- **[vm_debian](vm_debian/)**: Automation for Debian Cloud-Init VMs.

## Quick Start

Use the root `Makefile` to dispatch into module `Makefile`s with the
`<module>_<target>` pattern.

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
| `make status` | Show git status (short) |
| `make push` | Push current branch to all remotes (GitHub/GitLab) |
| `make sync M="..."` | Add, commit, and push the whole repository |

---
For module-specific behavior and variables, read the module README directly.
