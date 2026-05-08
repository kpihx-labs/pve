# PVE Module: Debian VM

Automation tools for deploying and managing Debian Cloud-Init VMs on Proxmox VE.

## Usage

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
```bash
make purge VMID=102
```

**Remote Purge (One-Liner):**
```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/kpihx-labs/pve/master/vm_debian/scripts/purge.sh)"
```

### 🌐 Remote Execution (One-Liner)
Ideal for bootstrapping new PVE nodes without cloning the entire repository. This method ensures you always use the latest version of the scripts directly from the source.

> [!IMPORTANT]
> Use `sudo bash -c "$(curl ...)"` to ensure environment variables are correctly passed to the sub-shell and that the script has the necessary privileges to execute `qm` commands.

```bash
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/kpihx-labs/pve/master/vm_debian/scripts/install.sh)"
```

#### Full Variable Example
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

> [!IMPORTANT]
> **Network Alignment**: Ensure the `BRIDGE` selected on the host matches the subnet defined by `STATIC_IP`, `PREFIX`, and `GATEWAY`.
