# GitLab CI/CD Pipeline Setup on gitbox.jnet.lan

This guide provides the exact configuration steps required to connect **`gitbox.jnet.lan`** to your Proxmox VE cluster for automated Vault deployment.

---

## 1. Proxmox CI/CD Service Account & API Token

Execute these commands on Proxmox VE (`pve-01` or `pve-02`):

```bash
# 1. Create a dedicated role with required VM/LXC and storage privileges
pveum role add TerraformAdmin -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Audit VM.PowerMgmt VM.Monitor Datastore.AllocateSpace Datastore.Audit SDN.Use"

# 2. Create the automation service user
pveum user add terraform-ci@pve -comment "GitLab CI Terraform Automation"

# 3. Grant cluster-wide permissions to the role
pveum acl modify / -user terraform-ci@pve -role TerraformAdmin

# 4. Generate the non-expiring API token
pveum user token add terraform-ci@pve gitlab-runner -privsep 0
```

> **Save the token secret**: Output will look like `terraform-ci@pve!gitlab-runner=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.

---

## 2. Deployment SSH Key Pair Generation

Generate a dedicated key pair on your workstation or management node:

```bash
ssh-keygen -t ed25519 -f ./vault_deploy_key -N "" -C "gitlab-runner@gitbox.jnet.lan"
```

* `vault_deploy_key`: The private key configured in GitLab CI/CD variables (`SSH_PRIVATE_KEY`).
* `vault_deploy_key.pub`: The public key injected into VMs and LXC containers via `TF_VAR_ssh_public_keys`.

---

## 3. GitLab CI/CD Variables Configuration

In GitLab (`https://gitbox.jnet.lan/jnet-labs/vault-bootstrap`):
Navigate to **Settings** $\rightarrow$ **CI/CD** $\rightarrow$ **Variables** $\rightarrow$ **Add variable**:

| Variable Name | Type | Masked | Value Description / Example |
|---|---|---|---|
| `TF_VAR_proxmox_endpoint` | Variable | No | `https://10.10.10.2:8006/` |
| `TF_VAR_proxmox_api_token` | Variable | **Yes** | `terraform-ci@pve!gitlab-runner=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `TF_VAR_ssh_public_keys` | Variable | No | `["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... gitlab-runner@gitbox.jnet.lan"]` |
| `SSH_PRIVATE_KEY` | Variable | **Yes** | Entire content of `vault_deploy_key` (including headers) |

---

## 4. Corosync QDevice Setup (Witness on gitbox.jnet.lan)

To provide an external tie-breaker vote for Proxmox HA across 2 physical hosts:

### On `gitbox.jnet.lan`:
```bash
sudo apt-get update && sudo apt-get install -y corosync-qnetd
```

### On `pve-01`:
```bash
apt-get install -y corosync-qdevice
pvecm qdevice setup gitbox.jnet.lan
```

### Check Cluster Quorum:
```bash
pvecm status
```

---

## 5. Pipeline Stages Overview

When code is committed or merged to `main`:
1. **`validate`**: Runs `terraform fmt` and `ansible-lint`.
2. **`plan`**: Creates a deterministic execution plan against GitLab HTTP backend.
3. **`apply`**: Deploys 3x VMs and 1x LXC on Proxmox hosts.
4. **`configure`**: Executes Ansible roles (`vault_common`, `vault_pki`, `vault_transit`, `vault_cluster`).
5. **`verify`**: Runs automated `/v1/sys/health` probes across all 4 instances.
