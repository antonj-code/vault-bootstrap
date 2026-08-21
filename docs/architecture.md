# Vault High Availability Architecture & Proxmox Distribution Guide

This document outlines the architecture, distribution logic, quorum behavior, network topology, and security hardening for a high-availability **3-Node HashiCorp Vault Cluster** with an isolated **Transit Auto-Unseal Vault LXC** running across **2x Standalone (Non-Clustered) Proxmox VE physical hosts**.

---

## 1. Executive Architecture Overview

```mermaid
flowchart TB
    subgraph Physical_Host_1["Standalone Proxmox Host 1 (pve-01)"]
        direction TB
        V1["vault-01 (VM)<br/>Role: Raft Node 1<br/>Port: 8200 / 8201"]
        V2["vault-02 (VM)<br/>Role: Raft Node 2<br/>Port: 8200 / 8201"]
    end

    subgraph Physical_Host_2["Standalone Proxmox Host 2 (pve-02)"]
        direction TB
        V3["vault-03 (VM)<br/>Role: Raft Node 3<br/>Port: 8200 / 8201"]
        VT["vault-transit (LXC)<br/>Role: Auto-Unseal Engine<br/>Port: 8200"]
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
    GL -->|"Proxmox API (pve1)"| Physical_Host_1
    GL -->|"Proxmox API (pve2)"| Physical_Host_2
    GL -->|"Ansible SSH / TLS"| V1
    GL -->|"Ansible SSH / TLS"| V2
    GL -->|"Ansible SSH / TLS"| V3
    GL -->|"Ansible SSH / TLS"| VT
```

---

## 2. Standalone Hypervisors & Vault Quorum Analysis

### 2.1 Hypervisor Fault Isolation

Because `pve-01` and `pve-02` are **independent standalone hypervisors**:
* They do not share a cluster filesystem (`pmxcfs`) or Corosync ring.
* Hypervisor-level split-brain is completely eliminated: an issue on `pve-01` will never cause `pve-02` to enter a read-only lock or fencing state.
* Terraform targets each host independently via provider aliases (`proxmox.pve1` and `proxmox.pve2`).

### 2.2 Application-Level Raft Quorum

In HashiCorp Vault's Raft consensus algorithm:
$$Q = \left\lfloor \frac{N}{2} \right\rfloor + 1$$
For a 3-node cluster ($N=3$), minimum quorum requires **2 active nodes**.

* **Host 1 (`pve-01`)**: `vault-01` (VM), `vault-02` (VM) — Holds 2 voting members.
* **Host 2 (`pve-02`)**: `vault-03` (VM), `vault-transit` (LXC) — Holds 1 voting member + Transit Auto-Unseal oracle.

```mermaid
graph TD
    subgraph Host1["Host 1 (pve-01) - 2 Raft Votes"]
        n1["vault-01"]
        n2["vault-02"]
    end
    subgraph Host2["Host 2 (pve-02) - 1 Raft Vote + Transit"]
        n3["vault-03"]
        tr["vault-transit"]
    end

    n1 --- n2
    n2 --- n3
    n3 --- n1
```

### 2.3 Failure Domain & Recovery Matrix

| Failure Event | Available Raft Nodes | Raft Quorum Status | Transit Status | Cluster Impact & Recovery Action |
|---|---|---|---|---|
| **Host 2 (`pve-02`) Dies** | 2 / 3 (`vault-01`, `vault-02`) | **MAINTAINED** (2 $\ge$ 2) | Offline | **Zero disruption on active cluster operations.** Cluster remains fully read/write on Host 1. Transit is only queried during node restarts. |
| **Host 1 (`pve-01`) Dies** | 1 / 3 (`vault-03`) | **LOST** (1 < 2) | Online | **Cluster enters safe read-only/halt state** to prevent split-brain. If Host 1 is unrecoverable, run [`scripts/raft_recovery.sh`](file:///home/ajensen/Repos/vault-bootstrap/scripts/raft_recovery.sh) on `vault-03` to force single-node quorum. |
| **Inter-Host Network Split** | Host 1 (2 nodes) vs Host 2 (1 node) | Host 1 retains quorum (2/3); Host 2 is isolated (1/3) | Host 1 cannot reach Transit; Host 2 has Transit | Host 1 continues serving clients. Host 2 steps down. Split-brain is prevented because Raft leader election strictly requires $\ge 2$ votes. |
| **Transit LXC Fails** | 3 / 3 | **MAINTAINED** | Offline | **Zero runtime read/write disruption.** Existing in-memory barrier keys are unaffected. Restart `vault-transit` LXC when convenient. |

---

## 3. Transit Auto-Unseal Architecture

Instead of manual shamir unseal keys entered by human key custodians after every reboot, HashiCorp Vault supports automated unsealing via the **Transit Secrets Engine**.

```mermaid
sequenceDiagram
    autonumber
    participant V as Main Vault Node (vault-01/02/03)
    participant T as Transit Vault (vault-transit)
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
| **Vault Node 1** | `vault-01` | `10.10.10.11` | `8200/tcp` (API), `8201/tcp` (Cluster) | `pve-01` (Standalone) |
| **Vault Node 2** | `vault-02` | `10.10.10.12` | `8200/tcp` (API), `8201/tcp` (Cluster) | `pve-01` (Standalone) |
| **Vault Node 3** | `vault-03` | `10.10.10.13` | `8200/tcp` (API), `8201/tcp` (Cluster) | `pve-02` (Standalone) |
| **Transit Vault** | `vault-transit` | `10.10.10.10` | `8200/tcp` (API) | `pve-02` (Standalone) |
