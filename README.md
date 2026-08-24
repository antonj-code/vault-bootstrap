# Vault Bootstrap: 3-Node HA Cluster + Transit Auto-Unseal VM on Proxmox VE

This repository contains the complete Infrastructure-as-Code (Terraform / OpenTofu), Configuration Management (Ansible), and GitOps CI/CD pipeline (`.gitlab-ci.yml`) to deploy a production-grade, highly available **3-Node HashiCorp Vault Cluster** (Raft Integrated Storage) with an isolated **Transit Auto-Unseal Vault VM** across **2x Standalone Proxmox VE physical hosts: `colossus` and `guardian`**.

---

## 🏛️ System Architecture

```mermaid
flowchart TB
    subgraph Host1["Standalone Proxmox Host 1 (colossus)"]
        direction TB
        V1["vm-vault-01 (VM)<br/>IP: 192.168.0.201<br/>Raft Node 1"]
        V2["vm-vault-02 (VM)<br/>IP: 192.168.0.202<br/>Raft Node 2"]
    end

    subgraph Host2["Standalone Proxmox Host 2 (guardian)"]
        direction TB
        V3["vm-vault-03 (VM)<br/>IP: 192.168.0.203<br/>Raft Node 3"]
        VT["vm-vault-transit (VM)<br/>IP: 192.168.0.200<br/>Transit Auto-Unseal Oracle"]
    end

    subgraph Management["GitLab Server (gitbox.jnet.lan)"]
        GL["GitLab VM & CI Runner<br/>(GitOps Controller & Remote State)"]
    end

    V1 <===>|"Raft Consensus (TLS 8201)"| V2
    V2 <===>|"Raft Consensus (TLS 8201)"| V3
    V3 <===>|"Raft Consensus (TLS 8201)"| V1

    V1 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT
    V2 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT
    V3 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT

    GL -->|"Proxmox API (proxmox.pve1)"| Host1
    GL -->|"Proxmox API (proxmox.pve2)"| Host2
    GL -->|"Ansible SSH / TLS"| V1
    GL -->|"Ansible SSH / TLS"| V2
    GL -->|"Ansible SSH / TLS"| V3
    GL -->|"Ansible SSH / TLS"| VT
```

---

## ⚖️ Hardware Distribution & Quorum Logic

In a 3-node Raft consensus cluster, quorum requires a strict majority of **2 nodes** ($Q = \lfloor 3/2 \rfloor + 1 = 2$). Across your 2 standalone physical hosts:

* **Host 1 (`colossus`)**: `vm-vault-01` (`192.168.0.201`), `vm-vault-02` (`192.168.0.202`) — Cloned from AlmaLinux 9 CIS Level 2 template (ID 1000). Holds 2 Raft voting members.
* **Host 2 (`guardian`)**: `vm-vault-03` (`192.168.0.203`) [Cloned from Template 1000], `vm-vault-transit` (`192.168.0.200`) [Cloned from Template 1000] — Holds 1 Raft voting member + Transit Auto-Unseal oracle.
* **Hypervisor Independence**: Because `colossus` and `guardian` are non-clustered standalone hosts, they have complete failure isolation with zero inter-hypervisor dependencies.

### Failure Scenarios & Mitigations

| Failure Scenario | Active Raft Nodes | Quorum State | Cluster Impact | Operational Action |
|---|---|---|---|---|
| **Host 2 (`guardian`) Fails** | 2 / 3 (`vm-vault-01`, `vm-vault-02`) | **QUORUM MAINTAINED** | **Zero downtime.** Cluster continues read/write operations seamlessly. Transit is only required when instances reboot/restart. | Restore `guardian` or restart `vm-vault-transit` VM when convenient. |
| **Host 1 (`colossus`) Fails** | 1 / 3 (`vm-vault-03`) | **QUORUM LOST** | **Cluster halts writes** to protect against split-brain corruption. | If `colossus` is recoverable, power it back on. If permanently destroyed, run [`scripts/raft_recovery.sh`](scripts/raft_recovery.sh) on `vm-vault-03` to promote it to single-node quorum. |
| **Network Partition (colossus vs guardian)** | `colossus` (2 nodes) vs `guardian` (1 node) | `colossus` retains quorum (2/3) | `colossus` continues serving client traffic; `guardian` isolates itself. | Network partition auto-heals when link recovers; Raft log syncs automatically. |
| **Transit VM Fails** | 3 / 3 | **QUORUM MAINTAINED** | **Zero downtime.** Existing unsealed memory state is unaffected. | Restart `vm-vault-transit` VM. |

---

## 📁 Repository Structure

```
vault-bootstrap/
├── .gitlab-ci.yml                  # End-to-end GitOps pipeline (Plan -> Apply -> Ansible -> Verify)
├── README.md                       # Comprehensive operational guide
├── docs/
│   ├── architecture.md             # Deep-dive architecture and threat model
│   ├── security-operations.md      # Post-bootstrap secrets, recovery keys & break-glass runbook
│   ├── gitlab-setup.md             # GitLab CI/CD setup guide on gitbox.jnet.lan
│   ├── template-setup.md           # AlmaLinux 9 CIS Level 2 Proxmox template (ID 1000) setup guide
│   └── packer-repaving.md          # Automated Packer build & rolling repave guide
├── packer/                         # Automated AlmaLinux 9 CIS Level 2 Image Builder
│   ├── almalinux9-cis.pkr.hcl      # Proxmox ISO Packer template
│   ├── variables.pkr.hcl           # Packer variable definitions
│   ├── pkrvars.example.hcl         # Sample build variables
│   ├── http/ks.cfg                 # Automated CIS Kickstart configuration
│   └── scripts/                    # Hardening and image cleanup provisioners
├── terraform/                      # OpenTofu / Terraform Proxmox IaC
│   ├── versions.tf                 # bpg/proxmox provider & GitLab HTTP backend
│   ├── variables.tf                # Dual-host endpoints, node configs, credentials
│   ├── main.tf                     # Standalone provider configurations (proxmox.pve1, proxmox.pve2)
│   ├── vms.tf                      # 4x Vault VMs: 3x Raft Cluster + 1x Transit Auto-Unseal (Template 1000)
│   ├── outputs.tf                  # Outputs & dynamic Ansible inventory generation
│   └── terraform.tfvars.example    # Sample configuration values
├── ansible/                        # Configuration Management & Orchestration
│   ├── ansible.cfg                 # Performance, SSH, and role settings
│   ├── inventory/
│   │   ├── hosts.yaml              # Node inventory mapping (192.168.0.200 - 203)
│   │   └── group_vars/             # Host group variable scoping
│   │       ├── all.yaml            # Global PKI, versions, sentinel marker definition
│   │       ├── vault_cluster.yaml  # Raft cluster variables & recovery keys
│   │       └── vault_transit.yaml  # Transit Auto-Unseal parameters
│   ├── roles/
│   │   ├── vault_common/           # Sentinel discovery, binary install, systemd, user, mlock
│   │   ├── vault_pki/              # Mutual TLS Root CA slurp & SAN certificate issuance
│   │   ├── vault_transit/          # Transit engine init, unseal key & scoped token
│   │   └── vault_cluster/          # Raft configuration, auto-unseal, retry_join, sentinel marker
│   └── playbooks/
│       ├── site.yaml               # Master end-to-end bootstrap playbook
│       ├── rolling_update.yaml     # Zero-downtime rolling repave (Method A)
│       ├── provision_transit.yaml  # Standalone Transit Vault playbook
│       └── provision_cluster.yaml  # Standalone Main Cluster playbook
└── scripts/
    ├── vault_env.sh                # CLI environment configuration helper
    └── raft_recovery.sh            # Disaster recovery single-node quorum recovery
```

---

## 🚀 Deployment Guide

For full instructions on configuring `gitbox.jnet.lan` and Proxmox API tokens, see [docs/gitlab-setup.md](docs/gitlab-setup.md).

### 1. GitLab CI / GitOps Automated Pipeline (Recommended)

1. **Configure CI/CD Variables** in your GitLab project (`Settings` > `CI/CD` > `Variables`):
   * `TF_VAR_pve_host_1_endpoint`: API URL of `colossus` (e.g. `https://colossus.jnet.lan:8006/`).
   * `TF_VAR_pve_host_1_api_token`: API Token on `colossus` (`terraform-ci@pve!gitlab-runner=...`).
   * `TF_VAR_pve_host_2_endpoint`: API URL of `guardian` (e.g. `https://guardian.jnet.lan:8006/`).
   * `TF_VAR_pve_host_2_api_token`: API Token on `guardian` (`terraform-ci@pve!gitlab-runner=...`).
   * `TF_VAR_ssh_public_keys`: Array containing your public SSH key.
   * `SSH_PRIVATE_KEY`: ED25519 private key for Ansible access.
2. **Push to `main`**:
   * Pipeline automatically triggers `terraform:apply`, runs `ansible:configure`, and validates health.

### 2. Manual / Local Execution

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in your colossus and guardian endpoints, tokens, and SSH keys in terraform.tfvars

terraform init
terraform apply

cd ../ansible
ansible-playbook -i inventory/hosts.yaml playbooks/site.yaml
```

### 3. CLI Helper
```bash
source scripts/vault_env.sh 192.168.0.201
vault status
vault operator raft list-peers
```

---

## 🗺️ Roadmap & Future Projects

* **Packer Golden Image CI/CD Pipeline**: Fully automating the creation and synchronization of the AlmaLinux 9 CIS Level 2 base template (ID 1000) across `colossus` and `guardian` via scheduled GitLab CI/CD jobs. *(Planned for future implementation)*
* **L4 Load Balancer Integration**: Fronting the 3-node cluster with a dedicated Layer 4 HAProxy / VIP (`https://vault.jnet.lan:8200`) for seamless client failover.
* **OIDC & AppRole Provisioning**: Automated Terraform provider integration for application secrets and human authentication.

---

## 📚 Documentation Index

* **[Architecture & Quorum Guide](docs/architecture.md)**: Physical host topology, Raft consensus mechanics, and failure domain analysis.
* **[Post-Bootstrap Security & Operations Guide](docs/security-operations.md)**: Recovery keys, artifact security, root token revocation, workstation TLS CA setup, and break-glass procedures.
* **[GitLab CI/CD Setup Guide](docs/gitlab-setup.md)**: Runner installation, CI/CD variables, and pipeline configuration.
* **[Proxmox VM Template Guide](docs/template-setup.md)**: AlmaLinux 9 CIS Level 2 Golden Image creation.
* **[Zero-Downtime Repaving Guide](docs/packer-repaving.md)**: Rolling updates and immutable infrastructure repaving.
