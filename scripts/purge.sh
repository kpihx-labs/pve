#!/usr/bin/env bash
set -e

echo "=== PVE VM Purge Utility ==="
read -p "Enter the VMID to destroy and purge: " VMID

if [[ -z "$VMID" || ! "$VMID" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid VMID. Please provide a numeric VMID."
  exit 1
fi

# Check if VM exists
if ! qm status "$VMID" >/dev/null 2>&1; then
  echo "Error: VM $VMID does not exist on this node."
  exit 1
fi

echo "WARNING: This will permanently destroy VM $VMID and all its disks."
read -p "Are you absolutely sure? (Type YES to confirm): " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "Operation aborted."
  exit 0
fi

echo "Stopping VM $VMID..."
qm stop "$VMID" || true

# Wait a moment for the VM to fully stop
sleep 2

echo "Destroying VM $VMID and purging disks..."
qm destroy "$VMID" --purge true --destroy-unreferenced-disks 1 || qm destroy "$VMID" --purge true

# Clean up cloud-init snippet if it exists
SNIPPET_FILE="/var/lib/vz/snippets/fluid-qemu-agent-${VMID}.yml"
if [ -f "$SNIPPET_FILE" ]; then
  echo "Removing associated cloud-init snippet..."
  rm -f "$SNIPPET_FILE"
fi

echo "Purge complete for VM $VMID."
