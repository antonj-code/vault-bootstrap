# GitLab CI/CD Pipeline Setup on gitbox.jnet.lan

This guide provides the exact configuration steps required to connect **`gitbox.jnet.lan`** to your **two standalone Proxmox VE hosts** (`pve-01` and `pve-02`) for automated Vault deployment.

---

## 1. Proxmox CI/CD Service Accounts & API Tokens

Because `pve-01` and `pve-02` are independent, standalone hosts (not in a Corosync cluster), create the service user and API token on **both hosts**:

### Run on BOTH `pve-01` AND `pve-02`:

```bash
# 1. Create a dedicated role with required VM/LXC and storage privileges
pveum role add TerraformAdmin -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Audit VM.PowerMgmt VM.Monitor Datastore.AllocateSpace Datastore.Audit SDN.Use"

# 2. Create the automation service user
pveum user add terraform-ci@pve -comment "GitLab CI Terraform Automation"

# 3. Grant permissions to the role
pveum acl modify / -user terraform-ci@pve -role TerraformAdmin

# 4. Generate the non-expiring API token
pveum user token add terraform-ci@pve gitlab-runner -privsep 0
```

> **Save the token secrets**: Output format will be `terraform-ci@pve!gitlab-runner=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.

---

## 2. Deployment SSH Key Pair Generation

Generate a dedicated SSH key pair on your workstation or management node:

```bash
ssh-keygen -t ed25519 -f ./vault_deploy_key -N "" -C "gitlab-runner@gitbox.jnet.lan"
```

* `vault_deploy_key`: Private key configured in GitLab CI/CD variables (`SSH_PRIVATE_KEY`).
* `vault_deploy_key.pub`: Public key injected into VMs and LXC container via `TF_VAR_ssh_public_keys`.

---

## 3. GitLab CI/CD Variables Configuration

In GitLab (`https://gitbox.jnet.lan/jnet-labs/vault-bootstrap`):
Navigate to **Settings** $\rightarrow$ **CI/CD** $\rightarrow$ **Variables** $\rightarrow$ **Add variable**:

| Variable Name | Type | Masked | Value Description / Example |
|---|---|---|---|
| `TF_VAR_pve_host_1_endpoint` | Variable | No | `https://10.10.10.2:8006/` |
| `TF_VAR_pve_host_1_api_token` | Variable | **Yes** | `terraform-ci@pve!gitlab-runner=xxxxxxxx-...` (Host 1 token) |
| `TF_VAR_pve_host_2_endpoint` | Variable | No | `https://10.10.10.3:8006/` |
| `TF_VAR_pve_host_2_api_token` | Variable | **Yes** | `terraform-ci@pve!gitlab-runner=yyyyyyyy-...` (Host 2 token) |
| `TF_VAR_ssh_public_keys` | Variable | No | `["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... gitlab-runner@gitbox.jnet.lan"]` |
| `SSH_PRIVATE_KEY` | Variable | **Yes** | Entire content of `vault_deploy_key` (including headers) |

---

## 4. Pipeline Stages Overview

When code is committed or merged to `main`:
1. **`validate`**: Runs `terraform fmt` and `ansible-lint`.
2. **`plan`**: Creates a deterministic execution plan against GitLab HTTP backend.
3. **`apply`**: Deploys `vault-01` and `vault-02` on `pve-01`, and `vault-03` + `vault-transit` on `pve-02`.
4. **`configure`**: Executes Ansible roles (`vault_common`, `vault_pki`, `vault_transit`, `vault_cluster`).
5. **`verify`**: Runs automated `/v1/sys/health` probes across all 4 instances.
