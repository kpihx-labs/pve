#!/usr/bin/env bash
# ==============================================================================
# PROXMOX DEBIAN VM LIFECYCLE AUTOMATION
# ==============================================================================
# Non-interactive Debian VM provisioning for Proxmox VE.
# The script keeps the module flexible through environment overrides while
# keeping the first-boot network path deterministic.
# ==============================================================================

set -euo pipefail
# Enable shell tracing only when explicitly requested by the caller.
[ "${DEBUG:-}" = "1" ] && set -x

# The installer is designed around Proxmox CLI calls and snippet writes.
# Running unprivileged would fail late and opaquely, so we stop immediately.
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# --- Runtime context -----------------------------------------------------------
# The invoking user is used for defaults and SSH key discovery.
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

# --- Constants / defaults ------------------------------------------------------
# Every value is overrideable from the environment.
# The goal is to keep the module reusable across nodes and networks without
# editing the file itself for every deployment.
VMID="${VMID:-101}"
VMNAME="${VMNAME:-pve-debian}"
STORAGE="${STORAGE:-local-zfs}"
IMAGE="${IMAGE:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"
SOCKETS="${SOCKETS:-1}"
CORES="${CORES:-2}"
MEMORY_MIB="${MEMORY_MIB:-8192}"
BRIDGE="${BRIDGE:-vmbr1}"
NIC_MODEL="${NIC_MODEL:-virtio}"
ROOT_GIB="${ROOT_GIB:-300}"
CI_USER="${CI_USER:-${REAL_USER}}"
CIPASSWORD="${CIPASSWORD:-}"
STATIC_IP="${STATIC_IP:-10.10.10.101}"
PREFIX="${PREFIX:-24}"
GATEWAY="${GATEWAY:-10.10.10.1}"
DNS="${DNS:-}"
SEARCHDOMAIN="${SEARCHDOMAIN:-kpihxlabs.com}"
NET_DEVICE_PATTERN="${NET_DEVICE_PATTERN:-e*}"
SNIPPET_DIR="${SNIPPET_DIR:-/var/lib/vz/snippets}"
SNIPPET_PREFIX="${SNIPPET_PREFIX:-fluid}"
USER_SNIPPET_FILE="${SNIPPET_PREFIX}-user-${VMID}.yml"
META_SNIPPET_FILE="${SNIPPET_PREFIX}-meta-${VMID}.yml"
SSH_KEYS_FILES=("/root/.ssh/authorized_keys" "${REAL_HOME}/.ssh/authorized_keys")

# Convert a CIDR prefix into a dotted decimal netmask because
# `/etc/network/interfaces` still expects the legacy netmask representation.
prefix_to_netmask() {
  local prefix=$1
  local mask=""
  local octet
  local full_octets=$((prefix / 8))
  local partial_bits=$((prefix % 8))

  for octet in 1 2 3 4; do
    if (( octet <= full_octets )); then
      mask+="${mask:+.}255"
    elif (( octet == full_octets + 1 && partial_bits > 0 )); then
      mask+="${mask:+.}$((256 - 2 ** (8 - partial_bits)))"
    else
      mask+="${mask:+.}0"
    fi
  done

  printf '%s\n' "${mask}"
}

prompt_password_if_needed() {
  # If the caller already provided a password, preserve it exactly.
  if [ -n "${CIPASSWORD}" ]; then
    return
  fi

  # Interactive prompting is only a fallback for local operator usage.
  # Remote curl flows can still inject `CIPASSWORD` from the environment.
  echo "No CIPASSWORD provided in environment."
  while true; do
    local pass1=""
    local pass2=""
    read -rs -p "Enter password for user ${CI_USER} (leave blank to disable password login): " pass1
    echo
    if [ -z "${pass1}" ]; then
      CIPASSWORD=""
      return
    fi
    read -rs -p "Confirm password: " pass2
    echo
    if [ "${pass1}" = "${pass2}" ]; then
      CIPASSWORD="${pass1}"
      return
    fi
    echo "Error: Passwords do not match. Please try again."
  done
}

detect_dns_if_needed() {
  # Preserve explicitly requested DNS settings.
  if [ -n "${DNS}" ]; then
    return
  fi

  # Align with CT 100 (homelab) model: Local DNS + X DNS
  DNS="10.10.10.10,129.104.30.41,129.104.201.51"
}

build_dns_derived_values() {
  # Proxmox Cloud-Init integration accepts only one nameserver in `qm set`,
  # while the guest files can carry the full resolver list.
  PRIMARY_DNS="$(printf '%s' "${DNS}" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}')"
  # `interfaces` wants a space-separated resolver list.
  DNS_INTERFACES="$(printf '%s' "${DNS}" | awk -F',' '{for (i = 1; i <= NF; ++i) {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i); printf "%s%s", (i == 1 ? "" : " "), $i}}')"
  # `systemd-networkd` wants one DNS= line per resolver.
  DNS_SYSTEMD_LINES="$(printf '%s' "${DNS}" | awk -F',' '{for (i = 1; i <= NF; ++i) {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i); printf "      DNS=%s\n", $i}}')"
  # `resolv.conf` wants one `nameserver` entry per resolver.
  DNS_RESOLV_LINES="$(printf '%s' "${DNS}" | awk -F',' '{for (i = 1; i <= NF; ++i) {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i); printf "nameserver %s\n", $i}}')"
  NETMASK="$(prefix_to_netmask "${PREFIX}")"
}

validate_inputs() {
  # Fail before mutating the host if the qcow image is missing.
  if [ ! -f "${IMAGE}" ]; then
    echo "Error: image not found: ${IMAGE}"
    exit 1
  fi

  # VMID must stay numeric because Proxmox CLI subcommands treat it as an ID.
  if [[ ! "${VMID}" =~ ^[0-9]+$ ]]; then
    echo "Error: VMID must be numeric."
    exit 1
  fi
}

build_ssh_key_bundle() {
  # Build a single, deduplicated key file for `qm set --sshkeys`.
  # This lets the hypervisor root account and the invoking user both retain
  # a path into the guest when keys are available.
  TMP_KEYS=$(mktemp)
  for keyfile in "${SSH_KEYS_FILES[@]}"; do
    if [ -f "${keyfile}" ]; then
      cat "${keyfile}" >> "${TMP_KEYS}"
    fi
  done
  sort -u "${TMP_KEYS}" -o "${TMP_KEYS}"
  sed -i '/^$/d' "${TMP_KEYS}"
}

render_meta_snippet() {
  # A changing instance-id forces Cloud-Init to treat the VM as a fresh
  # instance after every destructive rebuild.
  mkdir -p "${SNIPPET_DIR}"
  cat <<EOF > "${SNIPPET_DIR}/${META_SNIPPET_FILE}"
instance-id: fluid-vm-${VMID}-$(date +%s)
local-hostname: ${VMNAME}
EOF
}

render_user_snippet() {
  # Cloud-Init accepts either a locked password or a pre-hashed password.
  # Compute the exact variant before templating the YAML.
  local lock_passwd="true"
  local password_block=""
  local ssh_keys_block=""

  if [ -n "${CIPASSWORD}" ]; then
    lock_passwd="false"
    # Use single quotes around the hash to prevent YAML/shell interpolation issues.
    password_block="    passwd: '$(echo "${CIPASSWORD}" | openssl passwd -6 -stdin)'"
  fi

  if [ -s "${TMP_KEYS}" ]; then
    ssh_keys_block=$'    ssh_authorized_keys:\n'
    ssh_keys_block+="$(awk '{printf "      - %s\n", $0}' "${TMP_KEYS}")"
  fi

  cat <<EOF > "${SNIPPET_DIR}/${USER_SNIPPET_FILE}"
#cloud-config
# Set the visible host identity inside the guest.
hostname: ${VMNAME}
fqdn: ${VMNAME}.${SEARCHDOMAIN}

# Allow password SSH only when a password is intentionally configured.
ssh_pwauth: true

# Create the primary operator account.
users:
  - name: ${CI_USER}
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: ${lock_passwd}
${password_block}
${ssh_keys_block}

# Materialize the network files directly in the guest filesystem.
write_files:
  - path: /etc/network/interfaces
    permissions: '0644'
    content: |
      # Legacy ifupdown view kept for compatibility with images or tools
      # that still read /etc/network/interfaces during first boot.
      auto lo
      iface lo inet loopback

      auto eth0
      iface eth0 inet static
        address ${STATIC_IP}
        netmask ${NETMASK}
        gateway ${GATEWAY}
        dns-nameservers ${DNS_INTERFACES}
  - path: /etc/systemd/network/20-wired.network
    permissions: '0644'
    content: |
      # systemd-networkd view kept because Debian cloud images lean on it.
      [Match]
      Name=${NET_DEVICE_PATTERN}

      [Network]
      Address=${STATIC_IP}/${PREFIX}
      Gateway=${GATEWAY}
${DNS_SYSTEMD_LINES}      DHCP=no
  - path: /etc/resolv.conf
    permissions: '0644'
    content: |
${DNS_RESOLV_LINES}      search ${SEARCHDOMAIN}

# bootcmd runs early, before the late customization phase.
# Use it only for early service state changes that must happen before the
# later Cloud-Init stages. Do not write multiline shell fragments here.
bootcmd:
  - "ip link set ${NET_DEVICE_PATTERN} up || true"
  - systemctl stop systemd-resolved
  - systemctl disable systemd-resolved

# Keep first boot self-sufficient: the guest must be reachable and manageable.
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server

# runcmd runs later, once packages and most Cloud-Init stages have executed.
# Use it only for service restarts and late activation, not for raw network
# shell reconstruction.
runcmd:
  - [ sh, -c, "echo '${CI_USER}:${CIPASSWORD}' | chpasswd" ]
  - "systemctl daemon-reload || true"
  - "systemctl restart systemd-networkd || true"
  - "systemctl enable --now qemu-guest-agent || systemctl start qemu-guest-agent || true"
  - "systemctl enable --now ssh || systemctl restart ssh || true"
EOF
}

deep_purge_existing_vm() {
  # Rebuilds must start from a clean hypervisor state to avoid phantom disks,
  # stale Cloud-Init state, and mis-leading Proxmox inventory leftovers.
  echo "--- Deep purging VM ${VMID} ---"
  qm stop "${VMID}" 2>/dev/null || true
  qm destroy "${VMID}" --purge true 2>/dev/null || true

  if command -v zfs >/dev/null 2>&1; then
    echo "Checking for orphan ZFS datasets..."
    # Proxmox can leave ZFS datasets behind when a destroy was interrupted.
    zfs list -H -o name 2>/dev/null | grep "vm-${VMID}-" | xargs -r -n1 zfs destroy -r 2>/dev/null || true
  fi
}

create_vm_shell() {
  # This creates only the Proxmox shell around the future guest.
  # The OS content itself arrives later through the imported cloud image.
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
    --net0 "${NIC_MODEL},bridge=${BRIDGE}"
}

import_and_resize_disk() {
  # Import the cloud image into the target storage pool, then grow it to the
  # final requested size before first boot.
  echo "--- Importing disk ---"
  qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
  qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1,discard=on"
  qm resize "${VMID}" scsi0 "${ROOT_GIB}G"
}

apply_cloud_init_settings() {
  # Bind the Cloud-Init drive and inject the first-boot network parameters
  # that Proxmox itself knows how to expose to the guest.
  echo "--- Configuring Cloud-Init ---"
  qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"
  qm set "${VMID}" --ciuser "${CI_USER}"
  qm set "${VMID}" --ipconfig0 "ip=${STATIC_IP}/${PREFIX},gw=${GATEWAY}"

  # Proxmox Cloud-Init accepts a single nameserver string here; richer DNS
  # handling is rendered inside the guest snippets below.
  qm set "${VMID}" --nameserver "${PRIMARY_DNS}"
  [ -n "${SEARCHDOMAIN}" ] && qm set "${VMID}" --searchdomain "${SEARCHDOMAIN}"
  [ -n "${CIPASSWORD}" ] && qm set "${VMID}" --cipassword "${CIPASSWORD}"

  if [ -s "${TMP_KEYS}" ]; then
    # Only inject SSH keys when at least one real key exists.
    qm set "${VMID}" --sshkeys "${TMP_KEYS}"
  fi

  # Attach the generated user-data and meta-data snippets.
  qm set "${VMID}" --cicustom "user=local:snippets/${USER_SNIPPET_FILE},meta=local:snippets/${META_SNIPPET_FILE}"
}

launch_vm() {
  # TPM and RNG are optional runtime helpers but cheap to wire in here.
  qm set "${VMID}" --tpmstate0 "${STORAGE}:4,version=v2.0"
  qm set "${VMID}" --rng0 source=/dev/urandom

  echo "--- Launching VM ${VMID} ---"
  qm start "${VMID}"
  echo "--- SUCCESS: VM ${VMID} is booting with Forced Network and Dynamic keys ---"
}

cleanup_local_temp() {
  # The bundle file contains SSH public keys only, but it is still transient
  # installer state and should not remain on disk.
  rm -f "${TMP_KEYS:-}"
}

main() {
  # Surface the effective operator context before any mutation.
  echo "--- Running as root for user ${REAL_USER} (Home: ${REAL_HOME}) ---"

  prompt_password_if_needed
  detect_dns_if_needed
  build_dns_derived_values
  validate_inputs
  build_ssh_key_bundle
  deep_purge_existing_vm
  create_vm_shell
  import_and_resize_disk
  render_meta_snippet
  render_user_snippet
  apply_cloud_init_settings
  launch_vm
  cleanup_local_temp
}

main "$@"
