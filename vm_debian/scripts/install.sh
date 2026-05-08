#!/usr/bin/env bash
set -euo pipefail
[ "${DEBUG:-}" = "1" ] && set -x

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# --- identity / sizing ---
VMID="${VMID:-101}"
VMNAME="${VMNAME:-homelab}"
STORAGE="${STORAGE:-local-zfs}"
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"
SOCKETS="${SOCKETS:-1}"
CORES="${CORES:-2}"
MEMORY_MIB="${MEMORY_MIB:-8192}"
BRIDGE="${BRIDGE:-vmbr1}"
ROOT_GIB="${ROOT_GIB:-300}"
CI_USER="${CI_USER:-kpihx}"

# SOURCE DE VERITE POUR LES CLES : On prend celles de kpihx@pve car elles contiennent Ubuntu
SSH_KEYS_FILE="/home/kpihx/.ssh/authorized_keys"

# Static IP config
STATIC_IP="${STATIC_IP:-10.10.10.101}"
PREFIX="${PREFIX:-24}"
GATEWAY="${GATEWAY:-10.10.10.1}"
DNS="${DNS:-1.1.1.1,8.8.8.8}"
SEARCHDOMAIN="${SEARCHDOMAIN:-kpihxlabs.com}"

# --- Deep Purge ---
echo "--- Deep purging VM ${VMID} ---"
qm stop "${VMID}" 2>/dev/null || true
qm destroy "${VMID}" --purge true 2>/dev/null || true

if command -v zfs >/dev/null; then
  echo "Checking for orphan ZFS datasets..."
  zfs list -H -o name 2>/dev/null | grep "vm-${VMID}-" | xargs -n1 zfs destroy -r 2>/dev/null || true
fi

# --- Installation ---
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

echo "--- Importing disk ---"
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"
qm resize "${VMID}" scsi0 "${ROOT_GIB}G"

echo "--- Configuring Cloud-Init ---"
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --ciuser "${CI_USER}"

# Injection SSH propre via fichier temporaire
TMP_KEYS=$(mktemp)
# On fusionne les clés de root@pve et kpihx@pve pour être sûr
cat /root/.ssh/authorized_keys /home/kpihx/.ssh/authorized_keys 2>/dev/null | grep -v "^$" | sort -u > "${TMP_KEYS}"
qm set "${VMID}" --sshkeys "${TMP_KEYS}"
rm -f "${TMP_KEYS}"

qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/${PREFIX},gw=${GATEWAY}"
qm set "${VMID}" --nameserver "${DNS}"
[ -n "${SEARCHDOMAIN}" ] && qm set "${VMID}" --searchdomain "${SEARCHDOMAIN}"
[ -n "${CIPASSWORD:-}" ] && qm set "${VMID}" --cipassword "${CIPASSWORD}"

# --- SNIPPET DE FORCE (Network + Guest Agent) ---
SNIPPET_DIR="/var/lib/vz/snippets"
SNIPPET_FILE="fluid-deploy-${VMID}.yml"
mkdir -p "${SNIPPET_DIR}"

cat << EOF > "${SNIPPET_DIR}/${SNIPPET_FILE}"
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - [ ip, link, set, eth0, up ]
  - [ ip, addr, add, "${STATIC_IP}/${PREFIX}", dev, eth0 ]
  - [ ip, route, add, default, via, "${GATEWAY}" ]
  - [ systemctl, start, qemu-guest-agent ]
EOF

qm set "${VMID}" --cicustom "vendor=local:snippets/${SNIPPET_FILE}"
qm set "${VMID}" --tpmstate0 "${STORAGE}:4,version=v2.0"
qm set "${VMID}" --rng0 source=/dev/urandom

echo "--- Launching VM ${VMID} ---"
qm start "${VMID}"
echo "--- SUCCESS: VM ${VMID} is booting with Forced Network and Merged SSH keys ---"
