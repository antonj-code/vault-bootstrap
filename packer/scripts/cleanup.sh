#!/usr/bin/env bash
set -euo pipefail

echo "=== Cleaning up Template Image for Cloning ==="

# Clean package manager cache
dnf clean all
rm -rf /var/cache/dnf /var/cache/yum

# Clean Cloud-Init state
cloud-init clean --logs --seed || true
rm -rf /var/lib/cloud/instances/*

# Clean Machine ID so cloned VMs generate unique IDs and MAC/DHCP leases
truncate -s 0 /etc/machine-id
mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Clean temporary SSH keys and logs
rm -f /etc/ssh/ssh_host_*
rm -rf /tmp/* /var/tmp/*
truncate -s 0 /var/log/wtmp /var/log/lastlog /var/log/audit/audit.log 2>/dev/null || true

# Zero out disk to optimize template size
sync
echo "=== Cleanup Completed ==="
