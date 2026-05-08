#!/usr/bin/env bash
# ==============================================================================
# PROXMOX DEBIAN VM LIFECYCLE AUTOMATION
# ==============================================================================
# Non-interactive Debian VM provisioning for Proxmox VE.
# Uses the standard Proxmox Cloud-Init implementation for maximum stability.
# ==============================================================================

set -euo pipefail

# Mandatory root check for Proxmox CLI access.
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# --- Environment & Configuration ----------------------------------------------
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

VMID="${VMID:-101}"
VMNAME="${VMNAME:-pve-debian}"
STORAGE="${STORAGE:-local-zfs}"
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"
CORES="${CORES:-2}"
MEMORY_MIB="${MEMORY_MIB:-8192}"
BRIDGE="${BRIDGE:-vmbr1}"
ROOT_GIB="${ROOT_GIB:-300}"
CI_USER="${CI_USER:-${REAL_USER}}"
CIPASSWORD="${CIPASSWORD:-ivann123}"
STATIC_IP="${STATIC_IP:-10.10.10.101}"
GATEWAY="${GATEWAY:-10.10.10.1}"
NAMESERVER="${NAMESERVER:-10.10.10.10}"

# --- SSH Key Discovery --------------------------------------------------------
TMP_KEYS=$(mktemp)
# Collect keys from multiple potential sources to ensure operator access.
for keyfile in "/root/.ssh/authorized_keys" "${REAL_HOME}/.ssh/authorized_keys" "${REAL_HOME}/.ssh/id_ed25519_pve.pub"; do
  [[ -f "${keyfile}" ]] && cat "${keyfile}" >> "${TMP_KEYS}"
done
# Ensure a unique, clean key file for Proxmox.
sort -u "${TMP_KEYS}" -o "${TMP_KEYS}"
sed -i '/^$/d' "${TMP_KEYS}"

# --- VM Operations ------------------------------------------------------------

echo "--- [1/6] Purging existing VM ${VMID} ---"
qm stop "${VMID}" 2>/dev/null || true
qm destroy "${VMID}" --purge true 2>/dev/null || true

echo "--- [2/6] Creating VM Shell ---"
qm create "${VMID}" \
  --name "${VMNAME}" \
  --agent enabled=1 \
  --scsihw virtio-scsi-pci \
  --boot order=scsi0 \
  --ostype l26 \
  --cores "${CORES}" \
  --memory "${MEMORY_MIB}" \
  --vga serial0 \
  --serial0 socket \
  --net0 virtio,bridge=${BRIDGE}

echo "--- [3/6] Importing Cloud Image ---"
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"
qm resize "${VMID}" scsi0 "${ROOT_GIB}G"

echo "--- [4/6] Configuring Cloud-Init ---"
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --ciuser "${CI_USER}"
qm set "${VMID}" --cipassword "${CIPASSWORD}"
qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/24,gw=${GATEWAY}"
qm set "${VMID}" --nameserver "${NAMESERVER}"
[[ -s "${TMP_KEYS}" ]] && qm set "${VMID}" --sshkeys "${TMP_KEYS}"

echo "--- [5/6] Finalizing Hardware ---"
qm set "${VMID}" --tpmstate0 "${STORAGE}:4,version=v2.0"
qm set "${VMID}" --rng0 source=/dev/urandom

echo "--- [6/6] Launching VM ---"
qm start "${VMID}"

# --- Cleanup ---
rm -f "${TMP_KEYS}"

echo "=============================================================================="
echo " SUCCESS: VM ${VMID} (${VMNAME}) is booting."
echo " Access: ssh ${CI_USER}@${STATIC_IP} (pass: ${CIPASSWORD})"
echo " Console: sudo qm terminal ${VMID}"
echo "=============================================================================="
