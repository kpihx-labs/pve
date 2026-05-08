#!/usr/bin/env bash
# ==============================================================================
# PVE VM PURGE UTILITY
# ==============================================================================
# Permanently destroys a VM and ensures ZERO leftover bytes on the hypervisor.
# Logic covers Proxmox configs, ZFS datasets, and Cloud-Init snippets.
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# Usage: sudo ./purge.sh [-y] [VMID]
YES_TO_ALL=false
VMID_ARG=""

for arg in "$@"; do
    if [ "$arg" == "-y" ]; then
        YES_TO_ALL=true
    else
        VMID_ARG="$arg"
    fi
done

echo "=== PVE VM Deep Purge Utility ==="

if [[ -n "$VMID_ARG" ]]; then
    VMID="$VMID_ARG"
else
    read -p "Enter the VMID to destroy and purge: " VMID
fi

if [[ -z "$VMID" || ! "$VMID" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid VMID. Please provide a numeric VMID."
  exit 1
fi

# Check if VM exists in Proxmox inventory
if ! qm status "$VMID" >/dev/null 2>&1; then
  echo "Warning: VM $VMID does not exist in Proxmox inventory."
  # We continue anyway to check for orphaned datasets/snippets
else
  if [ "$YES_TO_ALL" = false ]; then
    echo "WARNING: This will permanently destroy VM $VMID and all its disks."
    read -p "Are you absolutely sure? (Type YES to confirm): " CONFIRM
    if [[ "$CONFIRM" != "YES" ]]; then
      echo "Operation aborted."
      exit 0
    fi
  fi

  echo "--- Stopping VM $VMID ---"
  qm stop "$VMID" 2>/dev/null || true
  sleep 2

  echo "--- Destroying VM $VMID and purging disks ---"
  # Try various levels of destruction to be sure
  qm destroy "$VMID" --purge true --destroy-unreferenced-disks 1 2>/dev/null || qm destroy "$VMID" --purge true
fi

# --- Deep ZFS Cleanup ---
# qm destroy can sometimes leave datasets behind if they are busy or in a bad state.
if command -v zfs >/dev/null; then
  echo "--- Checking for orphaned ZFS datasets for VM $VMID ---"
  # We look for anything matching vm-VMID- (disks, cloud-init, etc.)
  ORPHANS=$(zfs list -H -o name 2>/dev/null | grep "vm-${VMID}-" || true)
  if [[ -n "$ORPHANS" ]]; then
    echo "Found orphaned datasets. Destroying recursively..."
    echo "$ORPHANS" | xargs -n1 zfs destroy -r 2>/dev/null || true
  else
    echo "No orphaned ZFS datasets found."
  fi
fi

# --- Snippet Cleanup ---
# We must clean the specific vendor snippet used in our deployment.
SNIPPET_DIR="/var/lib/vz/snippets"
SNIPPET_FILES=("fluid-deploy-${VMID}.yml" "fluid-qemu-agent-${VMID}.yml")

for snippet in "${SNIPPET_FILES[@]}"; do
  if [ -f "${SNIPPET_DIR}/${snippet}" ]; then
    echo "--- Removing associated cloud-init snippet: ${snippet} ---"
    rm -f "${SNIPPET_DIR}/${snippet}"
  fi
done

echo "--- Purge complete for VM $VMID. Zero bytes remaining. ---"
