# PVE Module: Debian VM

Provision and purge Debian Cloud-Init VMs on Proxmox VE.

## Features

- **Environment-driven**: every deployment parameter can be overridden from the shell.
- **Prompt-safe password flow**: `CIPASSWORD` is prompted only when not supplied.
- **Deterministic first boot**: the installer renders both `ifupdown` and `systemd-networkd` static network files, then pins the first nameserver inside the Proxmox Cloud-Init layer.
- **Host-aware DNS default**: when `DNS` is omitted, the installer reuses the current PVE host nameservers from `/etc/resolv.conf`.
- **Deep purge**: VM config, ZFS leftovers, and Cloud-Init snippets are removed together.

## Usage

### Local module targets

```bash
make help
make install
make purge
```

### Root repository dispatch

Use the root `PVE/Makefile` when you want module dispatch or repo-wide sync:

```bash
make vm_debian_install VMID=102 STATIC_IP=10.10.10.102
make vm_debian_purge VMID=102
```

### Remote execution from the PVE host

This module is designed to be consumed directly from the repository source:

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

### Purge one-liner

```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/kpihx-labs/pve/master/vm_debian/scripts/purge.sh)"
```

## Main variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `VMID` | Proxmox VM identifier | `101` |
| `VMNAME` | Label shown in the Proxmox UI | `homelab` |
| `STORAGE` | Proxmox storage target | `local-zfs` |
| `IMAGE` | Local qcow2 path on the PVE host | `/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2` |
| `SOCKETS` | CPU sockets | `1` |
| `CORES` | CPU cores per socket | `2` |
| `MEMORY_MIB` | RAM size in MiB | `8192` |
| `ROOT_GIB` | Root disk size in GiB | `300` |
| `BRIDGE` | Proxmox bridge carrying the target subnet | `vmbr1` |
| `CI_USER` | Cloud-Init login user | invoking sudo user |
| `CIPASSWORD` | Password for `CI_USER` | prompted if empty |
| `STATIC_IP` | Guest static IPv4 address | `10.10.10.101` |
| `PREFIX` | CIDR prefix length | `24` |
| `GATEWAY` | Default gateway | `10.10.10.1` |
| `DNS` | Comma-separated DNS servers | PVE host `/etc/resolv.conf` or `1.1.1.1,8.8.8.8` |
| `SEARCHDOMAIN` | DNS search domain | `kpihxlabs.com` |
| `NET_DEVICE_PATTERN` | Guest NIC match pattern for first-boot network forcing | `e*` |
| `SNIPPET_PREFIX` | Prefix for generated Cloud-Init snippets | `fluid` |

## Notes

- Proxmox `qm set --nameserver` is fed with only the first DNS entry because its Cloud-Init integration expects a single address there.
- The richer DNS list still exists inside the generated guest files.
- `purge.sh` removes both current and legacy snippet names to keep old hosts clean.

## Serial console

Use the serial console when SSH is not available yet:

```bash
sudo qm terminal <VMID>
```

Leave the console with `Ctrl+O`.
