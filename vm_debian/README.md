# PVE Module: Debian VM

Provision and purge Debian Cloud-Init VMs on Proxmox VE.

## Features

- **Environment-driven**: every deployment parameter can be overridden from the shell.
- **Prompt-safe password flow**: `CIPASSWORD` is prompted only when not supplied.
- **Deterministic first boot**: the installer renders both `ifupdown` and `systemd-networkd` static network files, then pins the first nameserver inside the Proxmox Cloud-Init layer.
- **Host-aware DNS default**: when `DNS` is omitted, the installer reuses the current PVE host nameservers from `/etc/resolv.conf`.
- **Deep purge**: VM config, ZFS leftovers, and Cloud-Init snippets are removed together.
- **Virtio-first NIC**: the default guest NIC model is `virtio` because Debian cloud images reliably ship the matching drivers.

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
sudo bash -c "$(curl -sSL https://raw.githubusercontent.com/kpihx-labs/pve/master/vm_debian/scripts/install.sh)"
```

or more complete

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
| `NIC_MODEL` | Proxmox guest NIC model | `virtio` |
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
- **First boot behavior**:
    - **Timing**: ZSH environment installation starts automatically on the first boot but can take **1 to 2 minutes** to complete. Do not be surprised if the shell is still bash or tools are missing for the first few seconds of SSH connectivity.
    - **Boot Logs**: You can monitor the provisioning progress in real-time through the Proxmox console or by running `tail -f /var/log/cloud-init-output.log` inside the guest VM.

## Serial console

Use the serial console when SSH is not available yet:

```bash
sudo qm terminal <VMID>
```

Leave the console with `Ctrl+O`.

## SSH Access & Security Hardening

After the automated setup, follow these steps to establish a secure, key-only connection.

### 1. Client Configuration (on your local PC)

If you are using a ProxyJump (e.g., jumping through your PVE host to reach the VM on `vmbr1`), update your `~/.ssh/config`:

```bash
# Edit your local SSH config
micro ~/.ssh/config
```

Add a block like this:
```ssh
Host pve-debian
    ProxyJump pve
    HostName ${STATIC_IP}
    User ${CI_USER}
    ForwardAgent yes
```

**Note on Host Key Verification**: 
If you have reinstalled the VM, your PC will complain that the "REMOTE HOST IDENTIFICATION HAS CHANGED". Clear the old key with:
```bash
ssh-keygen -f '~/.ssh/known_hosts' -R '${STATIC_IP}'
```

Then connect normally:
```bash
ssh pve-debian
```

### 2. Manual Server Hardening (inside the VM)

Once connected, secure the SSH daemon:

```bash
sudo micro /etc/ssh/sshd_config
```

Apply and verify these settings:

| Parameter | Recommended | Rationale |
| :--- | :--- | :--- |
| `PasswordAuthentication` | `no` | Prevents brute-force attacks by requiring SSH keys. |
| `PubkeyAuthentication` | `yes` | Explicitly enables cryptographic key authentication. |
| `PermitRootLogin` | `no` | Forces the use of a standard user + `sudo`, hiding the root account from SSH. |
| `ChallengeResponseAuthentication` | `no` | Disables keyboard-interactive authentication (OATH, etc.). |

**Restart and test**:
```bash
sudo systemctl restart ssh
```

> [!WARNING]
> Always keep your current SSH session open while testing. Open a **new** terminal and try to `ssh pve-debian` to confirm you can still get in before closing the first one.

## Access Summary & Recovery

| Method | Target | Auth | Context |
| :--- | :--- | :--- | :--- |
| **SSH** | `${CI_USER}@pve-debian` | SSH Key | Standard remote operation. |
| **Console** | `sudo qm terminal <VMID>` | `${CI_USER}` password | Local PVE recovery (serial). |
| **Root Access** | `sudo -i` or `sudo -s` | `${CI_USER}` password | Privilege escalation within a session. |

Direct `root` login is disabled by default (no password set). Always enter as your user and escalate via `sudo`.
