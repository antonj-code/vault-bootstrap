#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Raft Quorum Disaster Recovery Script (Host 1 Outage)
# Use ONLY when Host 1 (pve-01) suffers permanent hardware failure and
# vault-03 (on Host 2) must be promoted to a single-node quorum leader.
# ==============================================================================

echo "=== Vault Raft Single-Node Quorum Recovery Utility ==="
echo "WARNING: This procedure should ONLY be run if Host 1 (vault-01 and vault-02) is unrecoverable."
read -p "Are you sure you want to force single-node recovery on vault-03? (y/N): " confirm

if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborting recovery."
  exit 1
fi

NODE_IP="10.10.10.13"

echo "[1/4] Stopping Vault service on vault-03..."
ssh -o StrictHostKeyChecking=no debian@"${NODE_IP}" "sudo systemctl stop vault"

echo "[2/4] Injecting peers.json recovery definition on vault-03..."
ssh -o StrictHostKeyChecking=no debian@"${NODE_IP}" "sudo bash -c 'cat << \"EOF\" > /opt/vault/data/raft/peers.json
[
  {
    \"id\": \"vault-03\",
    \"address\": \"10.10.10.13:8201\",
    \"non_voter\": false
  }
]
EOF
chown -R vault:vault /opt/vault/data/raft/peers.json
'"

echo "[3/4] Restarting Vault service on vault-03..."
ssh -o StrictHostKeyChecking=no debian@"${NODE_IP}" "sudo systemctl start vault"

echo "[4/4] Verifying recovery status..."
sleep 5
ssh -o StrictHostKeyChecking=no debian@"${NODE_IP}" "VAULT_ADDR=https://127.0.0.1:8200 VAULT_CACERT=/etc/vault.d/tls/ca.crt vault status"

echo "=== Quorum Recovery Completed ==="
