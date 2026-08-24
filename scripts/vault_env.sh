#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Vault Environment Setup Helper
# Sourcing this script sets up Vault CLI environment pointing to the cluster
# Usage: source scripts/vault_env.sh [node_ip]
# ==============================================================================

TARGET_IP="${1:-192.168.0.201}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_CERT="${REPO_ROOT}/credentials/tls/ca.crt"
CREDS_FILE="${REPO_ROOT}/credentials/cluster_credentials.json"

export VAULT_ADDR="https://${TARGET_IP}:8200"

if [[ -f "${CA_CERT}" ]]; then
  export VAULT_CACERT="${CA_CERT}"
  echo "[✓] Configured VAULT_CACERT=${VAULT_CACERT}"
else
  export VAULT_SKIP_VERIFY="true"
  echo "[!] Warning: CA cert not found locally, set VAULT_SKIP_VERIFY=true"
fi

if [[ -f "${CREDS_FILE}" ]]; then
  ROOT_TOKEN=$(jq -r '.root_token' "${CREDS_FILE}")
  export VAULT_TOKEN="${ROOT_TOKEN}"
  echo "[✓] Configured VAULT_TOKEN from credentials file"
fi

echo "[✓] Configured VAULT_ADDR=${VAULT_ADDR}"
echo "Current Cluster Status:"
vault status || true
