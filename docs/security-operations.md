# Vault Post-Bootstrap Security & Operations Guide

This guide details the post-bootstrap operational lifecycle, artifact security, recovery key management, root token revocation, and workstation certificate configuration for the 3-node HashiCorp Vault Raft cluster.

---

## 1. Bootstrap Artifacts & Secrets Management

When the `ansible:configure` pipeline stage executes, it generates and stores the cluster encryption keys and certificates under the `${CI_PROJECT_DIR}/credentials/` directory.

```
credentials/
├── cluster_credentials.json     # Main Vault 5-share recovery keys & initial root token
├── transit_credentials.json     # Transit Vault unseal key & root token
├── autounseal_token.txt         # Auto-Unseal client token used by Main Cluster
└── tls/
    ├── ca.crt                   # Internal Root CA Certificate
    ├── ca.key                   # Root CA Private Key
    ├── vm-vault-01.crt / .key   # Node 1 TLS Certificate & Private Key
    ├── vm-vault-02.crt / .key   # Node 2 TLS Certificate & Private Key
    ├── vm-vault-03.crt / .key   # Node 3 TLS Certificate & Private Key
    └── vm-vault-transit.crt/.key# Transit VM TLS Certificate & Private Key
```

### 1.1 Artifact Lifecycle & Retention Policy

* **Artifact Expiration**: The credentials artifact in GitLab CI is configured with `expire_in: 30 days`. After 30 days, GitLab automatically purges the artifact from the server.
* **Security Requirement**: You **must download and store the recovery keys and transit keys in an external password manager** (e.g., 1Password, Bitwarden, KeePassXC) before the artifact expires.

### 1.2 How to Download Bootstrap Artifacts

1. Navigate to **`https://gitbox.jnet.lan/jnet-labs/vault-bootstrap/-/pipelines`**.
2. Click on the latest successful pipeline.
3. Click on the **`ansible:configure`** job.
4. In the right-hand sidebar under **Job Artifacts**, click **Download** (or **Browse**).
5. Extract and securely store `cluster_credentials.json` and `transit_credentials.json`.

---

## 2. Emergency Recovery Keys & Break-Glass Procedures

The Main Vault Cluster uses **Transit Auto-Unseal** backed by a 5-share Shamir recovery key ring ($N=5, K=3$).

* **Transit Auto-Unseal**: Normal reboots, node repaves, and service restarts unseal automatically via `vm-vault-transit` without human intervention.
* **Recovery Keys**: Used strictly for emergency operations (e.g., generating a new root token, rekeying the cluster, or disaster recovery).

### 2.1 Generating a Temporary Emergency Root Token

If the initial root token is revoked and all administrative accounts are lost or locked out, any **3 key custodians** can generate a new temporary root token:

1. Initiate root token generation:
   ```bash
   vault operator generate-root -init
   ```
   *Vault will output a `Nonce` (e.g., `d8f24a1b-...`) and `Encoded Token`.*

2. Have 3 key holders submit their recovery keys:
   ```bash
   vault operator generate-root -nonce="<NONCE>"
   # Enter Recovery Key 1
   
   vault operator generate-root -nonce="<NONCE>"
   # Enter Recovery Key 2

   vault operator generate-root -nonce="<NONCE>"
   # Enter Recovery Key 3
   ```

3. Decode the new root token using the OTP:
   ```bash
   vault operator generate-root \
     -decode="<ENCODED_TOKEN>" \
     -otp="<INITIAL_OTP>"
   ```

---

## 3. Workstation TLS CA Certificate Installation

Because the cluster uses internal enterprise TLS certificates issued during deployment, installing `ca.crt` on your workstation allows your browser and CLI to verify the TLS certificates without security warnings.

### 3.1 Linux (AlmaLinux / Fedora / RHEL)
```bash
sudo cp credentials/tls/ca.crt /etc/pki/ca-trust/source/anchors/vault-internal-ca.crt
sudo update-ca-trust extract
```

### 3.2 Linux (Debian / Ubuntu)
```bash
sudo cp credentials/tls/ca.crt /usr/local/share/ca-certificates/vault-internal-ca.crt
sudo update-ca-certificates
```

### 3.3 macOS
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain credentials/tls/ca.crt
```

### 3.4 Windows (PowerShell Administrator)
```powershell
Import-Certificate -FilePath "credentials\tls\ca.crt" -CertStoreLocation "Cert:\LocalMachine\Root"
```

---

## 4. Day-2 Hardening: Root Token Revocation

In accordance with HashiCorp CIS Security Benchmarks, the initial bootstrap `root_token` should **never be used for daily operations**.

### Step 1: Create an Administrator Policy
Save as `admin-policy.hcl`:
```hcl
# Full administrative control across all paths
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
```

Write the policy to Vault:
```bash
vault policy write admin admin-policy.hcl
```

### Step 2: Enable an Authentication Method (e.g., Userpass)
```bash
# Enable username/password authentication
vault auth enable userpass

# Create your personal admin account
vault write auth/userpass/users/ajensen \
  password="<STRONG_PASSWORD>" \
  policies="admin" \
  ttl="8h"
```

### Step 3: Verify Login with Named Account
```bash
vault login -method=userpass username=ajensen
```

### Step 4: Revoke the Initial Root Token
Once you verify that your named administrative account works:
```bash
vault token revoke <INITIAL_ROOT_TOKEN>
```

---

## 5. Daily CLI Usage with Helper Scripts

We provide [`scripts/vault_env.sh`](../scripts/vault_env.sh) for quick workstation access:

```bash
# Source the cluster environment
source scripts/vault_env.sh

# Log into the cluster
vault login -method=userpass username=ajensen

# Check Raft peer status
vault operator raft list-peers

# Check unseal and HA state
vault status
```

---

## 6. Zero-Trace Artifact Hygiene (Optional)

Once your recovery keys and certificates are safely backed up in your enterprise vault:

1. Navigate to the **`ansible:configure`** job in GitLab.
2. Click **"Erase job log and artifacts"** in the top-right corner.
3. This ensures no unseal or recovery credentials remain on the GitLab runner disk or GitLab web server.
