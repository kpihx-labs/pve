#!/usr/bin/env bash
# ==============================================================================
# PROXMOX DEBIAN VM LIFECYCLE AUTOMATION
# ==============================================================================
# Non-interactive Debian VM provisioning for Proxmox VE.
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

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
SEARCHDOMAIN="${SEARCHDOMAIN:-kpihxlabs.com}"
SNIPPET_DIR="/var/lib/vz/snippets"
USER_SNIPPET_FILE="fluid-user-${VMID}.yml"
META_SNIPPET_FILE="fluid-meta-${VMID}.yml"

# --- Cloud-Init Rendering ---

mkdir -p "${SNIPPET_DIR}"

# Meta-data
cat <<EOF > "${SNIPPET_DIR}/${META_SNIPPET_FILE}"
instance-id: fluid-vm-${VMID}-$(date +%s)
local-hostname: ${VMNAME}
EOF

# User-data (The critical part)
cat <<EOF > "${SNIPPET_DIR}/${USER_SNIPPET_FILE}"
#cloud-config
hostname: ${VMNAME}
fqdn: ${VMNAME}.${SEARCHDOMAIN}
ssh_pwauth: true
users:
  - name: ${CI_USER}
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    passwd: ${CIPASSWORD}

write_files:
  - path: /etc/resolv.conf
    permissions: '0644'
    content: |
      nameserver 10.10.10.10
      nameserver 129.104.30.41
      search ${SEARCHDOMAIN}

bootcmd:
  - systemctl stop systemd-resolved
  - systemctl disable systemd-resolved

package_update: true
packages:
  - qemu-guest-agent
  - openssh-server

runcmd:
  - "systemctl enable --now qemu-guest-agent || true"
  - "systemctl restart ssh || true"
EOF

# --- VM Operations ---

echo "--- Purging VM ${VMID} ---"
qm stop "${VMID}" 2>/dev/null || true
qm destroy "${VMID}" --purge true 2>/dev/null || true

echo "--- Creating VM ${VMID} ---"
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

echo "--- Importing disk ---"
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"
qm resize "${VMID}" scsi0 "${ROOT_GIB}G"

echo "--- Configuring Cloud-Init ---"
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --ciuser "${CI_USER}"
qm set "${VMID}" --cipassword "${CIPASSWORD}"
qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/24,gw=${GATEWAY}"
qm set "${VMID}" --nameserver "10.10.10.10"
qm set "${VMID}" --cicustom "user=local:snippets/${USER_SNIPPET_FILE},meta=local:snippets/${META_SNIPPET_FILE}"

echo "--- Launching VM ${VMID} ---"
qm start "${VMID}"
echo "--- SUCCESS: VM ${VMID} is booting ---"
