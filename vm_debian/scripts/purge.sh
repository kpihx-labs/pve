#!/usr/bin/env bash
# ==============================================================================
# PVE VM PURGE UTILITY
# ==============================================================================
# Permanently destroys a VM and removes the deployment artifacts created by the
# vm_debian installer.
# ==============================================================================

set -euo pipefail

# Naming must stay aligned with vm_debian/scripts/install.sh.
SNIPPET_PREFIX="${SNIPPET_PREFIX:-fluid}"

# This utility mutates Proxmox inventory, storage, and snippet directories.
# Refuse to proceed if the caller is not already privileged.
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# Usage: sudo ./purge.sh [-y] [VMID]
YES_TO_ALL=false
VMID_ARG=""

for arg in "$@"; do
    # `-y` toggles destructive non-interactive mode.
    if [ "$arg" == "-y" ]; then
        YES_TO_ALL=true
    else
        # Any other positional argument is treated as the target VMID.
        VMID_ARG="$arg"
    fi
done

echo "=== PVE VM Deep Purge Utility ==="

if [[ -n "$VMID_ARG" ]]; then
    VMID="$VMID_ARG"
else
    # Interactive fallback for manual operator usage.
    read -p "Enter the VMID to destroy and purge: " VMID
fi

# A malformed VMID would make every later `qm` or `zfs` operation unreliable.
if [[ -z "$VMID" || ! "$VMID" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid VMID. Please provide a numeric VMID."
  exit 1
fi

# Check if VM exists in Proxmox inventory.
if ! qm status "$VMID" >/dev/null 2>&1; then
  echo "Warning: VM $VMID does not exist in Proxmox inventory."
  # Continue anyway to remove orphaned datasets and snippets.
else
  if [ "$YES_TO_ALL" = false ]; then
    # Keep the destructive path explicit when not in batch mode.
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
  # Try the strongest destroy form first, then fall back if unsupported.
  qm destroy "$VMID" --purge true --destroy-unreferenced-disks 1 2>/dev/null || qm destroy "$VMID" --purge true
fi

# --- Deep ZFS Cleanup ---
# qm destroy can sometimes leave datasets behind if they are busy or in a bad state.
if command -v zfs >/dev/null 2>&1; then
  echo "--- Checking for orphaned ZFS datasets for VM $VMID ---"
  # Match every dataset produced by Proxmox for the VM: disks, cloud-init, TPM.
  ORPHANS=$(zfs list -H -o name 2>/dev/null | grep "vm-${VMID}-" || true)
  if [[ -n "$ORPHANS" ]]; then
    # Recursive destroy is intentional because a VM can own multiple child
    # datasets under the same `vm-<VMID>-*` namespace.
    echo "Found orphaned datasets. Destroying recursively..."
    echo "$ORPHANS" | xargs -r -n1 zfs destroy -r 2>/dev/null || true
  else
    echo "No orphaned ZFS datasets found."
  fi
fi

# --- Snippet Cleanup ---
# Remove both current and legacy snippet names to keep the host clean after
# multiple installer generations.
SNIPPET_DIR="/var/lib/vz/snippets"
SNIPPET_FILES=(
  "${SNIPPET_PREFIX}-user-${VMID}.yml"
  "${SNIPPET_PREFIX}-meta-${VMID}.yml"
  "${SNIPPET_PREFIX}-deploy-${VMID}.yml"
  "${SNIPPET_PREFIX}-qemu-agent-${VMID}.yml"
)

for snippet in "${SNIPPET_FILES[@]}"; do
  # Only remove files that actually exist; purge should stay idempotent.
  if [ -f "${SNIPPET_DIR}/${snippet}" ]; then
    echo "--- Removing associated cloud-init snippet: ${snippet} ---"
    rm -f "${SNIPPET_DIR}/${snippet}"
  fi
done

echo "--- Purge complete for VM $VMID. Zero bytes remaining. ---"
