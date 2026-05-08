#!/usr/bin/env bash
# ==============================================================================
# PROXMOX DEBIAN VM LIFECYCLE AUTOMATION - NO PASS TEST
# ==============================================================================
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Root only"; exit 1; }

REAL_USER="${SUDO_USER:-$(whoami)}"
VMID="${VMID:-101}"
VMNAME="${VMNAME:-pve-debian}"
STORAGE="${STORAGE:-local-zfs}"
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"
CI_USER="${CI_USER:-${REAL_USER}}"
STATIC_IP="${STATIC_IP:-10.10.10.101}"
GATEWAY="${GATEWAY:-10.10.10.1}"
SNIPPET_DIR="/var/lib/vz/snippets"
USER_SNIPPET_FILE="fluid-user-${VMID}.yml"
META_SNIPPET_FILE="fluid-meta-${VMID}.yml"

mkdir -p "${SNIPPET_DIR}"

cat <<EOF > "${SNIPPET_DIR}/${META_SNIPPET_FILE}"
instance-id: fluid-vm-${VMID}-$(date +%s)
local-hostname: ${VMNAME}
EOF

cat <<EOF > "${SNIPPET_DIR}/${USER_SNIPPET_FILE}"
#cloud-config
hostname: ${VMNAME}
ssh_pwauth: true
users:
  - name: ${CI_USER}
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false

write_files:
  - path: /etc/resolv.conf
    permissions: '0644'
    content: |
      nameserver 10.10.10.10
      nameserver 129.104.30.41

bootcmd:
  - systemctl stop systemd-resolved
  - systemctl disable systemd-resolved

runcmd:
  - "passwd -d ${CI_USER}"
  - "sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config"
  - "systemctl restart ssh"
EOF

echo "--- Rebuilding VM ${VMID} ---"
qm stop "${VMID}" 2>/dev/null || true
qm destroy "${VMID}" --purge true 2>/dev/null || true
qm create "${VMID}" --name "${VMNAME}" --agent enabled=1 --scsihw virtio-scsi-pci --boot order=scsi0 --ostype l26 --cores 2 --memory 8192 --vga serial0 --serial0 socket --net0 virtio,bridge=vmbr1
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"
qm resize "${VMID}" scsi0 300G
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
qm set "${VMID}" --ciuser "${CI_USER}"
qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/24,gw=${GATEWAY}"
qm set "${VMID}" --cicustom "user=local:snippets/${USER_SNIPPET_FILE},meta=local:snippets/${META_SNIPPET_FILE}"
qm start "${VMID}"
echo "--- SUCCESS: VM ${VMID} is booting (PASSLESS) ---"
