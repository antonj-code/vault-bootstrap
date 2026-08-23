#!/usr/bin/env bash
set -euo pipefail

echo "=== Starting AlmaLinux 9 CIS Level 2 Hardening Provisioner ==="

# 1. Update OS packages with latest security errata
echo "[1/6] Applying latest security patches..."
dnf upgrade -y --security

# 2. Pre-install HashiCorp Vault Binary
echo "[2/6] Pre-baking HashiCorp Vault v${VAULT_VERSION}..."
curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip
unzip -q -o /tmp/vault.zip -d /usr/local/bin/
rm -f /tmp/vault.zip
chmod 0755 /usr/local/bin/vault
setcap cap_ipc_lock=+ep /usr/local/bin/vault

# 3. Create Vault User and Directories
echo "[3/6] Setting up vault system user and directories..."
groupadd -r vault || true
useradd -r -g vault -d /opt/vault -s /sbin/nologin -c "HashiCorp Vault Service Account" vault || true
mkdir -p /etc/vault.d/tls /opt/vault/data /var/log/vault
chown -R vault:vault /etc/vault.d /opt/vault /var/log/vault
chmod 0750 /etc/vault.d /opt/vault /var/log/vault

# 4. Kernel and Core Dump Hardening
echo "[4/6] Applying kernel sysctl hardening..."
cat << 'EOF' > /etc/sysctl.d/99-cis-vault.conf
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
vm.swappiness = 1
vm.max_map_count = 262144
EOF
sysctl --system || true

# 5. Core Dumps & Limits
echo "[5/6] Restricting core dumps and setting limits..."
cat << 'EOF' > /etc/security/limits.d/99-cis-vault.conf
* hard core 0
* soft core 0
vault hard memlock unlimited
vault soft memlock unlimited
vault hard nofile 65536
vault soft nofile 65536
EOF

# 6. SELinux File Contexts
echo "[6/6] Applying SELinux contexts..."
semanage fcontext -a -t bin_t '/usr/local/bin/vault' || true
semanage fcontext -a -t var_lib_t '/opt/vault(/.*)?' || true
semanage fcontext -a -t etc_t '/etc/vault.d(/.*)?' || true
restorecon -Rv /usr/local/bin/vault /opt/vault /etc/vault.d || true

echo "=== CIS Level 2 Hardening Provisioner Completed ==="
