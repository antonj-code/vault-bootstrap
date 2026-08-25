# Vault High Availability Architecture & Proxmox Distribution Guide

This document outlines the architecture, distribution logic, quorum behavior, network topology, and security hardening for a high-availability **3-Node HashiCorp Vault Cluster** with an isolated **Transit Auto-Unseal Vault VM** running across **2x Standalone Proxmox VE physical hosts: `colossus` and `guardian`**.

---

## 1. Executive Architecture Overview

```mermaid
flowchart TB
    subgraph Physical_Host_1["Standalone Proxmox Host 1 (colossus)"]
        direction TB
        V1["vm-vault-01 (VM)<br/>Role: Raft Node 1<br/>IP: 192.168.0.201<br/>Port: 8200 / 8201"]
        V2["vm-vault-02 (VM)<br/>Role: Raft Node 2<br/>IP: 192.168.0.202<br/>Port: 8200 / 8201"]
    end

    subgraph Physical_Host_2["Standalone Proxmox Host 2 (guardian)"]
        direction TB
        V3["vm-vault-03 (VM)<br/>Role: Raft Node 3<br/>IP: 192.168.0.203<br/>Port: 8200 / 8201"]
        VT["vm-vault-transit (VM)<br/>Role: Auto-Unseal Engine<br/>IP: 192.168.0.200<br/>Port: 8200"]
    end

    subgraph Management_Host["GitLab Server (gitbox.jnet.lan)"]
        GL["GitLab VM & Runner<br/>(GitOps Controller & Terraform State)"]
    end

    %% Raft Consensus
    V1 <===>|"Raft Consensus (TLS 8201)"| V2
    V2 <===>|"Raft Consensus (TLS 8201)"| V3
    V3 <===>|"Raft Consensus (TLS 8201)"| V1

    %% Auto Unseal
    V1 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT
    V2 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT
    V3 -.->|"Auto-Unseal Decrypt (TLS 8200)"| VT

    %% Pipeline deployment
    GL -->|"Proxmox API (proxmox.pve1)"| Physical_Host_1
    GL -->|"Proxmox API (proxmox.pve2)"| Physical_Host_2
    GL -->|"Ansible SSH / TLS"| V1
    GL -->|"Ansible SSH / TLS"| V2
    GL -->|"Ansible SSH / TLS"| V3
    GL -->|"Ansible SSH / TLS"| VT
```

---

## 2. Standalone Hypervisors & Vault Quorum Analysis

### 2.1 Hypervisor Fault Isolation

Because `colossus` and `guardian` are **independent standalone hypervisors**:
* They do not share a cluster filesystem (`pmxcfs`) or Corosync ring.
* Hypervisor-level split-brain is completely eliminated: an issue on `colossus` will never cause `guardian` to enter a read-only lock or fencing state.
* Terraform targets each host independently via provider aliases (`proxmox.pve1` for `colossus` and `proxmox.pve2` for `guardian`).

### 2.2 Application-Level Raft Quorum

In HashiCorp Vault's Raft consensus algorithm:
$$Q = \left\lfloor \frac{N}{2} \right\rfloor + 1$$
For a 3-node cluster ($N=3$), minimum quorum requires **2 active nodes**.

* **Host 1 (`colossus`)**: `vm-vault-01` (VM), `vm-vault-02` (VM) — Holds 2 voting members.
* **Host 2 (`guardian`)**: `vm-vault-03` (VM), `vm-vault-transit` (VM) — Holds 1 voting member + Transit Auto-Unseal oracle.

```mermaid
graph TD
    subgraph Host1["Host 1 (colossus) - 2 Raft Votes"]
        n1["vm-vault-01 (192.168.0.201)"]
        n2["vm-vault-02 (192.168.0.202)"]
    end
    subgraph Host2["Host 2 (guardian) - 1 Raft Vote + Transit"]
        n3["vm-vault-03 (192.168.0.203)"]
        tr["vm-vault-transit (192.168.0.200)"]
    end

    n1 --- n2
    n2 --- n3
    n3 --- n1
```

### 2.3 Failure Domain & Recovery Matrix

| Failure Event | Available Raft Nodes | Raft Quorum Status | Transit Status | Cluster Impact & Recovery Action |
|---|---|---|---|---|
| **Host 2 (`guardian`) Dies** | 2 / 3 (`vm-vault-01`, `vm-vault-02`) | **MAINTAINED** (2 $\ge$ 2) | Offline | **Zero disruption on active cluster operations.** Cluster remains fully read/write on `colossus`. Transit is only queried during node restarts. |
| **Host 1 (`colossus`) Dies** | 1 / 3 (`vm-vault-03`) | **LOST** (1 < 2) | Online | **Cluster enters safe read-only/halt state** to prevent split-brain. If `colossus` is unrecoverable, run [`scripts/raft_recovery.sh`](../scripts/raft_recovery.sh) on `vm-vault-03` to force single-node quorum. |
| **Inter-Host Network Split** | Host 1 (2 nodes) vs Host 2 (1 node) | Host 1 retains quorum (2/3); Host 2 is isolated (1/3) | Host 1 cannot reach Transit; Host 2 has Transit | Host 1 continues serving clients. Host 2 steps down. Split-brain is prevented because Raft leader election strictly requires $\ge 2$ votes. |
| **Transit VM Fails** | 3 / 3 | **MAINTAINED** | Offline | **Zero runtime read/write disruption.** Existing in-memory barrier keys are unaffected. Restart `vm-vault-transit` VM when convenient. |

### 2.4 The 2-Physical-Server Quorum Constraint & Scaling to 3 Domains

A fundamental law of Raft consensus ($Q = \lfloor N/2 \rfloor + 1$) across **only 2 physical hypervisors** is the **Majority Host Asymmetry**:

* **Why increasing node count from 3 to 5 does not eliminate this**:
  * In a 5-node cluster across 2 hosts, nodes must be split unevenly (3 on one host, 2 on the other).
  * 5-node quorum requires **3 votes**. If the host holding 3 nodes dies, only 2 nodes survive on the other host ($2 < 3$), causing quorum to be lost.
* **The Operational Reality**: With 2 physical hosts, the cluster can always survive the failure of the *minority* host (`guardian`), but the loss of the *majority* host (`colossus`) will require bringing Host 1 back online or executing [`scripts/raft_recovery.sh`](../scripts/raft_recovery.sh) to force single-node quorum.
* **Path to 100% Symmetrical Failure Tolerance (3rd Failure Domain)**:
  * To survive the loss of **either** physical host automatically, a **3rd failure domain** is required (e.g., adding a 3rd Proxmox host, or deploying a lightweight 1-core voting witness node in a cloud VPC / Raspberry Pi):
    * `colossus` (Host 1): 2 voting nodes
    * `guardian` (Host 2): 2 voting nodes
    * `witness` (Domain 3): 1 tie-breaker voter node
    * *Result*: If either `colossus` or `guardian` suffers a complete power loss, the surviving host (2 votes) + witness (1 vote) = **3 of 5 votes** $\rightarrow$ **Quorum holds 100% of the time with zero downtime.**

---

## 3. Transit Auto-Unseal Architecture

Instead of manual shamir unseal keys entered by human key custodians after every reboot, HashiCorp Vault supports automated unsealing via the **Transit Secrets Engine**.

```mermaid
sequenceDiagram
    autonumber
    participant V as Main Vault Node (vm-vault-01/02/03)
    participant T as Transit Vault (vm-vault-transit)
    participant S as Local Encrypted Storage (Raft)

    Note over V: Node reboots / restarts service
    V->>S: Read encrypted cluster key ring
    V->>T: POST /v1/transit/decrypt/vault-unseal-key (ciphertext)
    Note over T: Verify Vault Token / AppRole permissions
    T-->>V: Return plaintext root unseal key
    Note over V: Unseal in-memory storage engine
    V->>V: State: ACTIVE or STANDBY (Unsealed)
```

---

## 4. Network and Port Allocation

| Component | Hostname | IP Address | Listening Ports | Target Physical Host |
|---|---|---|---|---|
| **Vault Node 1** | `vm-vault-01` | `192.168.0.201` | `8200/tcp` (API), `8201/tcp` (Cluster) | `colossus` (Standalone) |
| **Vault Node 2** | `vm-vault-02` | `192.168.0.202` | `8200/tcp` (API), `8201/tcp` (Cluster) | `colossus` (Standalone) |
| **Vault Node 3** | `vm-vault-03` | `192.168.0.203` | `8200/tcp` (API), `8201/tcp` (Cluster) | `guardian` (Standalone) |
| **Transit Vault** | `vm-vault-transit` | `192.168.0.200` | `8200/tcp` (API) | `guardian` (Standalone) |

---

## 5. Security Hardening & CIS Level 2 Compliance

The 3 Main Vault cluster VMs are provisioned by cloning an **AlmaLinux 9 CIS Level 2 hardened template (ID 1000)** with automated Ansible compliance adaptations:

1. **SELinux in Enforcing Mode**:
   * Proper file contexts (`bin_t`, `etc_t`, `var_lib_t`) applied via `community.general.sefcontext` and `restorecon`.
   * Restricts unauthorized process memory inspection or unexpected filesystem writes.
2. **Firewalld Hardening**:
   * Host firewall enforces default-deny ingress policy.
   * Scoped ports explicitly allowed: `8200/tcp` (Vault API) and `8201/tcp` (Vault Raft Cluster Communication).
3. **Memory Locking & Anti-Swap (`mlock` / `cap_ipc_lock`)**:
   * Linux capability `cap_ipc_lock=+ep` granted to `/usr/local/bin/vault`.
   * Systemd service configured with `LimitMEMLOCK=infinity` to guarantee secrets in memory are never paged to disk.
4. **Sandboxed Dedicated System User**:
   * Unprivileged `vault:vault` service account configured with a non-interactive shell (`/sbin/nologin`).
   * Sandboxed systemd directives: `ProtectSystem=full`, `PrivateTmp=yes`, `NoNewPrivileges=yes`.
5. **Mutual TLS (mTLS) & CA Trust Integration**:
   * Root CA automatically installed into AlmaLinux trust store (`/etc/pki/ca-trust/source/anchors/`) and compiled via `update-ca-trust extract`.
   * Strict TLS 1.3 enforced on API and Raft replication listeners.
