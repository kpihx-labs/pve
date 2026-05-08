#!/usr/bin/env bash
# ==============================================================================
# PROMOX DEBIAN VM LIFECYCLE AUTOMATION
# ==============================================================================
# Non-interactive, hardened deployment for Debian-based VMs on Proxmox.
# Problem First -> Why before How -> Visualization.
# Architecture: 0 Trust · 100% Control | 0 Magic · 100% Transparency
# ==============================================================================

set -euo pipefail
[ "${DEBUG:-}" = "1" ] && set -x

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# --- Smart User Detection ---
# Identify the original user who invoked sudo to correctly locate SSH keys and HOME.
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
echo "--- Running as root for user ${REAL_USER} (Home: ${REAL_HOME}) ---"

# --- identity / sizing ---
# VMID: free integer (see `qm list`). Change if occupied.
VMID="${VMID:-101}"

# VMNAME: label in Proxmox UI only (Fluid keys off Fabric host id, not this string).
VMNAME="${VMNAME:-homelab}"

# STORAGE: exact pool id from Datacenter -> Storage (`pvesm status -v 01`). Examples: local-lvm, local-zfs.
STORAGE="${STORAGE:-local-zfs}"

# IMAGE: qcow path on THIS node — replace with wherever you staged Generic Cloud amd64.
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"

# CPU/RAM — single consolidated Debian+Docker VM sizing.
# SOCKETS x CORES = total vcpus for the guest.
SOCKETS="${SOCKETS:-1}"
CORES="${CORES:-2}"
MEMORY_MIB="${MEMORY_MIB:-8192}"

# BRIDGE — must be the vmbr carrying the SAME L2 subnet as STATIC_IP/PREFIX/GW below.
# Typical homelab patterns: vmbr1 = LAB / tagged VLAN trunk; vmbr0 = bridged NIC or single flat network.
BRIDGE="${BRIDGE:-vmbr1}"

# Root disk GiB — cloud image arrives small; enlarge before heavy Docker use.
ROOT_GIB="${ROOT_GIB:-300}"

# First login user keys — file on HYPERVISOR with public SSH keys (cloud-init pipes into ~/.ssh/authorized_keys).
CI_USER="${CI_USER:-${REAL_USER}}"

# Password Handling
if [ -z "${CIPASSWORD:-}" ]; then
  echo "No CIPASSWORD provided in environment."
  while true; do
    read -rs -p "Enter password for user ${CI_USER} (leave blank to disable password login): " PASS1
    echo
    if [ -z "$PASS1" ]; then
      CIPASSWORD=""
      break
    fi
    read -rs -p "Confirm password: " PASS2
    echo
    if [ "$PASS1" == "$PASS2" ]; then
      CIPASSWORD="$PASS1"
      break
    else
      echo "Error: Passwords do not match. Please try again."
    fi
  done
fi

# SSH Keys: We merge root and the initiating user's authorized_keys for maximum flexibility.
# This ensures that both the PVE host (root) and the user's workspace (via their key) can access the VM.
SSH_KEYS_FILES=("/root/.ssh/authorized_keys" "${REAL_HOME}/.ssh/authorized_keys")

# Static IP config
# Replace placeholders with YOUR addressing.
STATIC_IP="${STATIC_IP:-10.10.10.101}"
PREFIX="${PREFIX:-24}"
GATEWAY="${GATEWAY:-10.10.10.1}"
DNS="${DNS:-1.1.1.1,8.8.8.8}"
SEARCHDOMAIN="${SEARCHDOMAIN:-kpihxlabs.com}"

# --- Deep Purge ---
# Blow away previous VM same id — ensure no orphaned locks or datasets remain.
echo "--- Deep purging VM ${VMID} ---"
qm stop "${VMID}" 2>/dev/null || true
qm destroy "${VMID}" --purge true 2>/dev/null || true

# Explicitly check for orphan ZFS datasets if on a ZFS-backed pool.
if command -v zfs >/dev/null; then
  echo "Checking for orphan ZFS datasets..."
  zfs list -H -o name 2>/dev/null | grep "vm-${VMID}-" | xargs -n1 zfs destroy -r 2>/dev/null || true
fi

# --- Installation ---
# Skeleton VM profile: QEMU guest agent (shutdown cooperation), virtio-SCSI plumbing.
echo "--- Creating VM ${VMID} ---"
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
  --serial0 socket \
  --net0 virtio,bridge="${BRIDGE}"

# Inject Generic Cloud qcow -> storage pool creates `vm-${VMID}-disk-0` by default.
echo "--- Importing disk ---"
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"

# Attach root disk virtio-SCSI (+ iothread + discard/TRIM hints for thin backends).
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"

# Grow block device BEFORE heavy first-boot usage (guest FS may auto-grow via cloud-init).
qm resize "${VMID}" scsi0 "${ROOT_GIB}G"

# --- Cloud-Init Configuration ---
echo "--- Configuring Cloud-Init ---"
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --ciuser "${CI_USER}"

# Merge SSH keys from both sources into a clean, unique file for injection.
TMP_KEYS=$(mktemp)
for keyfile in "${SSH_KEYS_FILES[@]}"; do
  if [ -f "${keyfile}" ]; then
    cat "${keyfile}" >> "${TMP_KEYS}"
  fi
done
sort -u "${TMP_KEYS}" -o "${TMP_KEYS}"
sed -i '/^$/d' "${TMP_KEYS}"

qm set "${VMID}" --sshkeys "${TMP_KEYS}"
rm -f "${TMP_KEYS}"

# Network and Password settings
qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/${PREFIX},gw=${GATEWAY}"
qm set "${VMID}" --nameserver "${DNS}"
[ -n "${SEARCHDOMAIN}" ] && qm set "${VMID}" --searchdomain "${SEARCHDOMAIN}"
[ -n "${CIPASSWORD}" ] && qm set "${VMID}" --cipassword "${CIPASSWORD}"

# --- FORCED NETWORK SNIPPET (Vendor Layer) ---
# Debian Cloud images often fail to parse PVE network-config V1 correctly.
# This vendor-data snippet forces the interface UP and applies the static IP on first boot.
# We also mask systemd-networkd-wait-online to prevent the 2-minute boot hang.
SNIPPET_DIR="/var/lib/vz/snippets"
SNIPPET_FILE="fluid-deploy-${VMID}.yml"
mkdir -p "${SNIPPET_DIR}"

cat << EOF > "${SNIPPET_DIR}/${SNIPPET_FILE}"
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
bootcmd:
  - systemctl mask systemd-networkd-wait-online.service
runcmd:
  - [ ip, link, set, eth0, up ]
  - [ ip, addr, add, "${STATIC_IP}/${PREFIX}", dev, eth0 ]
  - [ ip, route, add, default, via, "${GATEWAY}" ]
  - echo "nameserver ${DNS%%,*}" > /etc/resolv.conf
  - [ systemctl, start, qemu-guest-agent ]
EOF

qm set "${VMID}" --cicustom "vendor=local:snippets/${SNIPPET_FILE}"

# Security and Acceleration extras.
qm set "${VMID}" --tpmstate0 "${STORAGE}:4,version=v2.0"
qm set "${VMID}" --rng0 source=/dev/urandom

# --- Launch ---
# Attach serial from UI / `qm terminal` if SSH unreachable.
echo "--- Launching VM ${VMID} ---"
qm start "${VMID}"
echo "--- SUCCESS: VM ${VMID} is booting with Forced Network and Dynamic keys ---"
