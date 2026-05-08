#!/usr/bin/env bash
# ==============================================================================
# PROXMOX DEBIAN VM LIFECYCLE AUTOMATION - STANDARD PROXMOX METHOD
# ==============================================================================
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Root only"; exit 1; }

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

VMID="${VMID:-101}"
VMNAME="${VMNAME:-pve-debian}"
STORAGE="${STORAGE:-local-zfs}"
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"
CI_USER="${CI_USER:-${REAL_USER}}"
CIPASSWORD="${CIPASSWORD:-ivann123}"
STATIC_IP="${STATIC_IP:-10.10.10.101}"
GATEWAY="${GATEWAY:-10.10.10.1}"

TMP_KEYS=$(mktemp)
[[ -f "${REAL_HOME}/.ssh/id_ed25519_pve.pub" ]] && cat "${REAL_HOME}/.ssh/id_ed25519_pve.pub" > "${TMP_KEYS}"

echo "--- Rebuilding VM ${VMID} ---"
qm stop "${VMID}" 2>/dev/null || true
qm destroy "${VMID}" --purge true 2>/dev/null || true
qm create "${VMID}" --name "${VMNAME}" --agent enabled=1 --scsihw virtio-scsi-pci --boot order=scsi0 --ostype l26 --cores 2 --memory 8192 --vga serial0 --serial0 socket --net0 virtio,bridge=vmbr1
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"
qm resize "${VMID}" scsi0 300G
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --ciuser "${CI_USER}"
qm set "${VMID}" --cipassword "${CIPASSWORD}"
qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/24,gw=${GATEWAY}"
[[ -s "${TMP_KEYS}" ]] && qm set "${VMID}" --sshkeys "${TMP_KEYS}"

qm start "${VMID}"
rm -f "${TMP_KEYS}"
echo "--- SUCCESS: VM ${VMID} is booting (STANDARD METHOD) ---"
