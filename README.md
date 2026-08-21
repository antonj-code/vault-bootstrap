# Vault Bootstrap: 3-Node HA Cluster + Transit Auto-Unseal LXC on Proxmox VE

This repository contains the complete Infrastructure-as-Code (Terraform / OpenTofu), Configuration Management (Ansible), and GitOps CI/CD pipeline (`.gitlab-ci.yml`) to deploy a production-grade, highly available **3-Node HashiCorp Vault Cluster** (Raft Integrated Storage) with an isolated **Transit Auto-Unseal Vault LXC** across **2x Proxmox VE physical hosts**.

---

## 🏛️ System Architecture

```mermaid
flowchart TB
    subgraph Host1["Proxmox Host 1 (pve-01)"]
        direction TB
        V1["vault-01 (VM)<br/>IP: 10.10.10.11<br/>Raft Node 1"]
        V2["vault-02 (VM)<br/>IP: 10.10.10.12<br/>Raft Node 2"]
    end

    subgraph Host2["Proxmox Host 2 (pve-02)"]
        direction TB
        V3["vault-03 (VM)<br/>IP: 10.10.10.13<br/>Raft Node 3"]
        VT["vault-transit (LXC)<br/>IP: 10.10.10.10<br/>Transit Auto-Unseal Oracle"]
    end

    subgraph Management["GitLab & Witness Environment"]
        GL["GitLab VM / CI Runner<br/>+ Corosync QDevice (Witness)"]
    end

    V1 <===>|"Raft Consensus (TLS 8201)"| V2
    V2 <===>|"Raft Consensus (TLS 8201)"| V3
    V3 <===>|"Raft Consensus (TLS 8201)"| V1

    V1 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT
    V2 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT
    V3 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT

    GL -->|"Proxmox API (bpg/proxmox)"| Host1
    GL -->|"Proxmox API (bpg/proxmox)"| Host2
    GL -->|"Ansible SSH / TLS"| V1
    GL -->|"Ansible SSH / TLS"| V2
    GL -->|"Ansible SSH / TLS"| V3
    GL -->|"Ansible SSH / TLS"| VT
```

---

## ⚖️ Hardware Distribution & Quorum Logic

In a 3-node Raft consensus cluster, quorum requires a strict majority of **2 nodes** ($Q = \lfloor 3/2 \rfloor + 1 = 2$). Across 2 physical hosts, asymmetric distribution is required:

* **Host 1 (`pve-01`)**: `vault-01` (VM), `vault-02` (VM) — Holds 2 Raft voting members.
* **Host 2 (`pve-02`)**: `vault-03` (VM), `vault-transit` (LXC) — Holds 1 Raft voting member + Transit Auto-Unseal oracle.
* **Management Witness**: The existing **GitLab VM** acts as a lightweight external Proxmox Corosync QDevice witness, providing a 3rd vote for the hypervisor cluster to prevent Proxmox split-brain.

### Failure Scenarios & Mitigations

| Failure Scenario | Active Raft Nodes | Quorum State | Cluster Impact | Operational Action |
|---|---|---|---|---|
| **Host 2 (`pve-02`) Fails** | 2 / 3 (`vault-01`, `vault-02`) | **QUORUM MAINTAINED** | **Zero downtime.** Cluster continues read/write operations seamlessly. Transit is only required when instances reboot/restart. | Restore Host 2 or restart `vault-transit` LXC when convenient. |
| **Host 1 (`pve-01`) Fails** | 1 / 3 (`vault-03`) | **QUORUM LOST** | **Cluster halts writes** to protect against split-brain corruption. | If Host 1 is recoverable, power it back on. If permanently destroyed, run `scripts/raft_recovery.sh` on `vault-03` or trigger Proxmox HA failover. |
| **Network Partition (Host 1 vs Host 2)** | Host 1 (2 nodes) vs Host 2 (1 node) | Host 1 retains quorum (2/3) | Host 1 continues serving client traffic; Host 2 isolates itself. | Network partition auto-heals when link recovers; Raft log syncs automatically. |
| **Transit LXC Fails** | 3 / 3 | **QUORUM MAINTAINED** | **Zero downtime.** Existing unsealed memory state is unaffected. | Restart `vault-transit` LXC. |

---

## 📁 Repository Structure

```
vault-bootstrap/
├── .gitlab-ci.yml                  # End-to-end GitOps pipeline (Plan -> Apply -> Ansible -> Verify)
├── README.md                       # Comprehensive operational guide
├── docs/
│   └── architecture.md             # Deep-dive architecture and threat model
├── terraform/                      # OpenTofu / Terraform Proxmox IaC
│   ├── versions.tf                 # bpg/proxmox provider & GitLab HTTP backend
│   ├── variables.tf                # Cluster nodes, IP subnets, credentials
│   ├── main.tf                     # Provider instantiation and local filters
│   ├── vms.tf                      # 3x Main Vault Raft VMs (Cloud-Init)
│   ├── lxc.tf                      # 1x Transit Auto-Unseal LXC
│   ├── outputs.tf                  # Outputs & dynamic Ansible inventory generation
│   └── terraform.tfvars.example    # Sample configuration values
├── ansible/                        # Configuration Management & Orchestration
│   ├── ansible.cfg                 # Performance, SSH, and role settings
│   ├── inventory/
│   │   └── hosts.yaml              # Node inventory mapping
│   ├── group_vars/
│   │   ├── all.yaml                # Global PKI & Vault versions
│   │   ├── vault_cluster.yaml      # Raft cluster variables & recovery keys
│   │   └── vault_transit.yaml      # Transit LXC parameters
│   ├── roles/
│   │   ├── vault_common/           # Binary install, systemd, user, mlock/capabilities
│   │   ├── vault_pki/              # Mutual TLS Root CA & SAN certificates
│   │   ├── vault_transit/          # Transit engine init, unseal key & scoped token
│   │   └── vault_cluster/          # Raft configuration, auto-unseal & auto-join
│   └── playbooks/
│       ├── site.yaml               # Master end-to-end bootstrap playbook
│       ├── provision_transit.yaml  # Standalone Transit Vault playbook
│       └── provision_cluster.yaml  # Standalone Main Cluster playbook
└── scripts/
    ├── vault_env.sh                # CLI environment configuration helper
    └── raft_recovery.sh            # Disaster recovery single-node quorum recovery
```

---

## 🚀 Deployment Guide

### 1. GitLab CI / GitOps Automated Pipeline (Recommended)

1. **Configure CI/CD Variables** in your GitLab project (`Settings` > `CI/CD` > `Variables`):
   * `PROXMOX_ENDPOINT`: URL of Proxmox API (e.g. `https://10.10.10.2:8006/`).
   * `PROXMOX_API_TOKEN`: Proxmox API Token (`USER@REALM!TOKENID=SECRET`).
   * `SSH_PRIVATE_KEY`: ED25519 or RSA private key with root/admin access to provisioned VMs and LXCs.
2. **Commit & Push changes**:
   * Creating a Merge Request runs `terraform:validate`, `ansible:lint`, and `terraform:plan`.
   * Merging to `main` automatically triggers `terraform:apply`, executes `ansible:configure`, and verifies cluster health in `vault:verify`.

### 2. Manual / Local Execution

#### Step A: Infrastructure Provisioning (Terraform / OpenTofu)
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Adjust IP addresses, Proxmox tokens, and SSH keys in terraform.tfvars

terraform init
terraform plan
terraform apply
```

#### Step B: Configuration Management (Ansible)
```bash
cd ../ansible
ansible-playbook -i inventory/hosts.yaml playbooks/site.yaml
```

#### Step C: Interacting with the Cluster
```bash
source ../scripts/vault_env.sh 10.10.10.11
vault status
vault operator raft list-peers
```

---

## 🔒 Security Hardening

* **Transit Auto-Unseal with Least Privilege**: The Main Vault cluster accesses the Transit Vault via an orphan token scoped exclusively to encrypt/decrypt against `transit/keys/vault-unseal-key`.
* **Zero Swap & IPC_LOCK**: `cap_ipc_lock=+ep` is granted to the Vault binary, and system memory locking (`LimitMEMLOCK=infinity`) is enforced via systemd to prevent memory dumping to swap.
* **Mutual TLS (mTLS)**: Cluster peering communication on port `8201` and client API traffic on port `8200` are strictly encrypted via TLS 1.3 with automated internal SAN certificate generation.
* **Unprivileged Transit LXC**: Transit Vault runs in an unprivileged container with nesting enabled and sandboxed file storage.
