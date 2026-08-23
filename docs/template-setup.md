# AlmaLinux 9 CIS Level 2 Template Setup Guide (Proxmox Template ID 1000)

This guide documents the requirements, hardware settings, security compliance, user account configurations, and image sanitization procedures for creating the **AlmaLinux 9 CIS Level 2 Golden Template (ID 1000)** on `colossus` and `guardian`.

---

## 1. Proxmox VM Hardware Specifications

When creating the base VM in Proxmox before converting it to a template:

| Parameter | Configuration | Technical Rationale |
|---|---|---|
| **VM ID** | `1000` | Matches `var.template_vm_id` in Terraform. |
| **OS Type** | Linux (Kernel 6.x - 2.6) / `l26` | Standard 64-bit Linux kernel. |
| **CPU** | 2 Cores, Type: `host` | Direct CPU flag pass-through for AES-NI cryptographic acceleration. |
| **Memory** | 2048 MB | Sufficient for OS provisioning; Terraform resizes to 4096 MB for Vault nodes. |
| **SCSI Controller** | `VirtIO SCSI single` | Dedicated VirtIO queue per disk; supports TRIM/Discard. |
| **Hard Disk** | Bus: `SCSI 0`, Size: `20 GB`, Discard: `on`, SSD emulation: `on` | High-performance paravirtualized disk interface. |
| **Cloud-Init Drive** | Add Cloud-Init Drive (e.g., on `local-lvm`) | Required for Proxmox to generate and mount the Cloud-Init ISO. |
| **Network Interface** | Model: `VirtIO (paravirtualized)`, Bridge: `vmbr0` | High-throughput paravirtualized network driver. |
| **QEMU Agent** | **Enabled** (`Options` $\rightarrow$ `QEMU Guest Agent`) | **Mandatory.** Terraform relies on the guest agent to detect IP and boot completion. |

---

## 2. User Accounts & Sudo Privileges

### 2.1 Default Cloud-Init User (`almalinux`)
* Cloud-Init injects credentials into the `almalinux` account (`ci_user = "almalinux"`).
* Passwordless sudo must be enabled for Ansible automation.

Create `/etc/sudoers.d/almalinux`:
```bash
echo "almalinux ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/almalinux
chmod 0440 /etc/sudoers.d/almalinux
```

### 2.2 Sudoers `requiretty` Check (CIS Level 2)
* Some CIS Level 2 benchmarks enforce `Defaults requiretty` in `/etc/sudoers`.
* Ensure `requiretty` is **disabled or absent**; otherwise, Ansible SSH pipelining will fail.

### 2.3 Root & Vault Accounts
* **Root**: Password should be locked (`passwd -l root` or `rootpw --lock`). Ansible executes all privileged operations via `sudo` from the `almalinux` user.
* **Vault User**: **Do not pre-create passwords for `vault`.** Ansible automatically creates the dedicated `vault:vault` system user with `/sbin/nologin`.

---

## 3. Mandatory Packages & Services

Ensure the following packages are installed and enabled on the template:

```bash
sudo dnf install -y \
  qemu-guest-agent \
  cloud-init \
  cloud-utils-growpart \
  curl \
  jq \
  libcap \
  unzip \
  tar \
  procps-ng \
  sudo \
  policycoreutils-python-utils \
  firewalld \
  openssh-server
```

Enable core startup services:
```bash
sudo systemctl enable qemu-guest-agent
sudo systemctl enable cloud-init cloud-init-local cloud-config cloud-final
sudo systemctl enable firewalld
sudo systemctl enable sshd
```

---

## 4. SSH & Security Configurations

In `/etc/ssh/sshd_config` (or `/etc/ssh/sshd_config.d/cis.conf`):
* `PubkeyAuthentication yes` (Mandatory for GitLab CI deployment key authentication).
* `PermitRootLogin no` (CIS Level 2 compliant).
* If `AllowUsers` or `AllowGroups` is configured, ensure `almalinux` / `wheel` is included.

---

## 5. Golden Image Sanitization (Pre-Template Checklist)

Before converting the VM into a Proxmox template, execute this sanitization script to prevent duplicate machine IDs, SSH host key conflicts, and stale Cloud-Init data:

```bash
# 1. Clean Cloud-Init state so it runs fresh on each cloned VM
sudo cloud-init clean --logs --seed
sudo rm -rf /var/lib/cloud/instances/*

# 2. Reset Machine ID (Prevents duplicate D-Bus IDs & DHCP collisions)
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# 3. Remove old SSH host keys (Cloud-Init will generate unique host keys per VM)
sudo rm -f /etc/ssh/ssh_host_*

# 4. Clean temporary files and package caches
sudo dnf clean all
sudo rm -rf /tmp/* /var/tmp/*
sudo truncate -s 0 /var/log/audit/audit.log 2>/dev/null || true
```

---

## 6. Convert to Template

1. Power off the VM:
   ```bash
   sudo poweroff
   ```
2. On Proxmox (`colossus` and `guardian`), convert the VM to a template:
   * **Web UI**: Right-click VM `1000` $\rightarrow$ **Convert to template**.
   * **CLI**:
     ```bash
     qm template 1000
     ```

---

## 7. Verification Checklist

```
[ ] VM ID is set to 1000 on colossus and guardian
[ ] QEMU Guest Agent is installed and enabled (systemctl enable qemu-guest-agent)
[ ] Cloud-Init is installed and enabled
[ ] almalinux user has NOPASSWD sudo in /etc/sudoers.d/almalinux
[ ] requiretty is NOT enforced in /etc/sudoers
[ ] PubkeyAuthentication yes is enabled in sshd_config
[ ] Sanitization script executed (machine-id truncated, ssh_host_* removed)
[ ] Cloud-Init drive is present on SCSI/IDE bus
[ ] VM converted to template (qm template 1000)
```
