#!/usr/bin/env bash
set -eu

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# --- identity / sizing ---
# VMID: free integer (see `qm list`). Change if occupied.
VMID="${VMID:-101}"

# VMNAME: label in Proxmox UI only (Fluid keys off Fabric host id, not this string).
VMNAME="${VMNAME:-homelab}"

# STORAGE: exact pool id from Datacenter → Storage (`pvesm status` / UI). Examples: local-lvm, local-zfs.
STORAGE="${STORAGE:-local-zfs}"

# IMAGE: qcow path on THIS node — replace with wherever you staged Generic Cloud amd64.
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"

# CPU/RAM — see header note outside this fence for sizing; single consolidated Debian+Docker VM on one node:
# SOCKETS × CORES = total vcpus for the guest. Alternatives: 2×4 for throughput over simpler scheduling.
SOCKETS="${SOCKETS:-1}"
CORES="${CORES:-2}"
MEMORY_MIB="${MEMORY_MIB:-8192}"

# BRIDGE — must be the vmbr carrying the SAME L2 subnet as STATIC_IP/PREFIX/GW below (see `ip -br addr`, `/etc/network/interfaces`).
# Typical homelab patterns: vmbr1 = LAB / tagged VLAN trunk; vmbr0 = bridged NIC or single flat LAN. Override exported BRIDGE=... if needed.
BRIDGE="${BRIDGE:-vmbr1}"

# Root disk GiB — cloud image arrives small; enlarge before heavy Docker use (example used in homelab Fluid node: 300).
ROOT_GIB="${ROOT_GIB:-300}"

# First login user keys — file on HYPERVISOR with public SSH keys (cloud-init pipes into ~/.ssh/authorized_keys).
CI_USER="${CI_USER:-kpihx}"
SSH_KEYS_FILE="${SSH_KEYS_FILE:-${HOME}/.ssh/authorized_keys}"

# If no password is provided in env, prompt for it
if [ -z "${CIPASSWORD:-}" ]; then
  while true; do
    read -s -p "Enter password for user ${CI_USER} (leave blank to disable password login): " PASS1
    echo
    if [ -z "$PASS1" ]; then
      CIPASSWORD=""
      break
    fi
    read -s -p "Confirm password: " PASS2
    echo
    if [ "$PASS1" = "$PASS2" ]; then
      CIPASSWORD="$PASS1"
      break
    else
      echo "Error: Passwords do not match. Please try again."
    fi
  done
fi

# LAB static NIC config (NOT Tailscale). Replace placeholders with YOUR addressing.
# Omit searchdomain unless you rely on DHCP-style DNS suffix; optional extra flag shown after cloud-init qm set.
# Replace ALL three — no sane default; mismatched GW↔bridge is the usual “VM boots—no ping”.
STATIC_IP="${STATIC_IP:-10.10.10.101}"
PREFIX="${PREFIX:-24}"
GATEWAY="${GATEWAY:-10.10.10.1}"
# Public resolvers as placeholder only — swap for your DHCP/internal DNS IPs if discovery must stay LAN-only during bootstrap.
DNS="${DNS:-1.1.1.1,8.8.8.8}"

SEARCHDOMAIN="${SEARCHDOMAIN:-kpihxlabs.com}"
# SEARCHDOMAIN="lab.example.invalid"    # uncomment if guest needs explicit DNS search suffix

#
# Blow away previous VM same id — REMOVE both lines entirely if risky for your fleet.
qm destroy "${VMID}" --purge true 2>/dev/null || true

#
# Skeleton VM profile: QEMU guest agent, virtio-SCSI, and standard i440fx (pc) chipset.
# We use SeaBIOS (default) as it's more universal for basic cloud images.
qm create "${VMID}" \
  --name "${VMNAME}" \
  --agent enabled=1 \
  --scsihw virtio-scsi-pci \
  --boot order=scsi0 \
  --ostype l26 \
  --machine pc \
  --cores "${CORES}" \
  --sockets "${SOCKETS}" \
  --memory "${MEMORY_MIB}" \
  --vga serial0 \
  --serial0 socket

#
# Inject Generic Cloud qcow → storage pool
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"

#
# Attach root disk virtio-SCSI
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"

#
# Grow block device
qm resize "${VMID}" scsi0 "${ROOT_GIB}G"

#
# Attach Cloud-Init on IDE2 (Proxmox standard for best compatibility)
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"

#
# vTPM (optional extras)
qm set "${VMID}" --tpmstate0 "${STORAGE}:4,version=v2.0"

#
# Bridge attach
qm set "${VMID}" --net0 virtio,bridge="${BRIDGE}"

#
# Cloud-Init configuration
# Pass raw keys and password separately to avoid shell array expansion issues
qm set "${VMID}" --ciuser "${CI_USER}"
qm set "${VMID}" --sshkeys "${SSH_KEYS_FILE}" # Proxmox accepts the file path directly for this field!
qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/${PREFIX},gw=${GATEWAY}"
qm set "${VMID}" --nameserver "${DNS}"

if [ -n "${CIPASSWORD:-}" ]; then
  qm set "${VMID}" --cipassword "${CIPASSWORD}"
fi

# Inject searchdomain if provided
if [[ -n "${SEARCHDOMAIN}" ]]; then
  qm set "${VMID}" --searchdomain "${SEARCHDOMAIN}"
fi

#
# Proxmox cloud-init CDROM channel — REQUIRED so previous cloud-init knobs reach Debian image.
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"

#
# Ensure qemu-guest-agent is installed via cloud-init vendor-data snippet
SNIPPET_DIR="/var/lib/vz/snippets"
SNIPPET_FILE="fluid-qemu-agent-${VMID}.yml"
mkdir -p "${SNIPPET_DIR}"
cat << 'EOF' > "${SNIPPET_DIR}/${SNIPPET_FILE}"
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl start qemu-guest-agent
EOF
qm set "${VMID}" --cicustom "vendor=local:snippets/${SNIPPET_FILE}"

#
# Prefer serial-first headless consoles + virtio RNG speeding crypto during early apt/tls.
qm set "${VMID}" --vga serial0 --serial0 socket
qm set "${VMID}" --rng0 source=/dev/urandom

#
# Launch — attach serial from UI/`qm terminal` if SSH unreachable (wrong BRIDGE/IP).
qm start "${VMID}"
