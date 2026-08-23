# AlmaLinux 9 CIS Level 2 Template Setup Guide (Proxmox Template ID 1000)

This guide documents the exact step-by-step requirements, Proxmox hardware settings, OS installer choices, user accounts, security compliance, and image sanitization procedures for creating the **AlmaLinux 9 CIS Level 2 Golden Template (ID 1000)** on `colossus` and `guardian`.

---

## 1. Proxmox Base VM Hardware Specifications

When creating the base VM in the Proxmox Web UI before converting it to a template:

| Hardware Option | Setting | Why It Is Configured This Way |
|---|---|---|
| **VM ID** | **`1000`** | Matches `var.template_vm_id` in Terraform. |
| **Name** | **`almalinux-9-cis2-template`** | Clean, descriptive naming matching Packer automation. |
| **BIOS** | **`Default (SeaBIOS)`** | Faster boot, zero EFI disk overhead, simpler cloning across standalone hosts. |
| **TPM** | **`Disabled / None`** | Not needed for Open-Source Vault (Transit Auto-Unseal handles keys). |
| **CPU** | **2 Cores**, Type: **`host`** | Direct CPU flag pass-through (enables hardware AES-NI encryption). |
| **Memory** | **2048 MB** | Minimal footprint for base template; Terraform resizes VMs to 4096 MB. |
| **SCSI Controller** | **`VirtIO SCSI single`** | Dedicated I/O queue per disk; enables TRIM/Discard. |
| **Hard Disk (`scsi0`)** | **64 GB**, Bus: `SCSI 0` | Paravirtualized VirtIO drive (matches CIS Level 2 storage requirements). |
| **SSD Emulation** | **`Checked (Yes)`** | Disables spinning-disk scheduler; enables multi-queue SSD scheduling for fast Raft writes. |
| **Discard** | **`Checked (Yes)`** | Returns freed blocks to Proxmox thin storage (`local-lvm`/`local-zfs`). |
| **IO Thread** | **`Checked (Yes)`** | Dedicates an emulated thread for disk I/O to maximize throughput. |
| **Cloud-Init Drive** | **Add Cloud-Init Drive** | Required for Proxmox to inject IP, gateway, hostname, and SSH keys. |
| **Network Device** | Model: **`VirtIO (paravirtualized)`**, Bridge: `vmbr0` | High-throughput paravirtualized network driver. |
| **QEMU Guest Agent** | **`Enabled`** (`Options` $\rightarrow$ `QEMU Guest Agent`) | **Mandatory.** Terraform relies on this to detect VM boot and IP status. |

---

## 2. AlmaLinux 9 Installer (Anaconda) Walkthrough

When booting from the AlmaLinux 9 ISO:

### 2.1 Software Selection & Security Profile
* **Software Selection**: **`Minimal Install`** (keeps attack surface minimal).
* **Security Profile**: Select **`CIS AlmaLinux OS 9 Benchmark for Level 2 - Server`**.

### 2.2 User Creation Screen
* **Full Name**: `AlmaLinux Admin`
* **User Name**: **`almalinux`**
* **Make this user administrator**: **`Checked (Yes)`** *(Adds user to `wheel` group)*
* **Password**: Set a temporary password (e.g. `TempPass123!`). Cloud-Init will enforce SSH public keys on cloned VMs.

### 2.3 Root Password Screen
* Set **Root Password** or click **Lock root account** (recommended for CIS Level 2).
* All administrative tasks will be executed via `sudo` from the `almalinux` user.

### 2.4 Installation Destination (64 GB CIS Level 2 Partitioning)
Under **Manual Partitioning (LVM)**, configure the 64 GB disk as follows:

| Mount Point | Volume / Device | Size | Filesystem | Mount Options (CIS Benchmark) |
|---|---|---|---|---|
| `/boot` | Standard Partition (`sda1`) | `1 GB` | `xfs` | default |
| `/` | LVM `almalinux-root` | `15 GB` | `xfs` | default |
| `[SWAP]` | LVM `almalinux-swap` | `2 GB` | `swap` | default |
| `/var` | LVM `almalinux-var` | `15 GB` | `xfs` | `nodev` |
| `/var/tmp` | LVM `almalinux-var_tmp` | `4 GB` | `xfs` | `nodev,nosuid,noexec` |
| `/var/log` | LVM `almalinux-var_log` | `9 GB` | `xfs` | `nodev,nosuid,noexec` |
| `/home` | LVM `almalinux-home` | `5 GB` | `xfs` | `nodev,nosuid` |
| `/var/log/audit` | LVM `almalinux-var_log_audit` | `9 GB` | `xfs` | `nodev,nosuid,noexec` |
| `/tmp` | LVM `almalinux-tmp` | `4 GB` | `xfs` | `nodev,nosuid,noexec` |

#### Resulting `lsblk` Layout on Installed VM:
```
NAME                        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                           8:0    0   64G  0 disk 
├─sda1                        8:1    0    1G  0 part /boot
└─sda2                        8:2    0   63G  0 part 
  ├─almalinux-root          253:0    0   15G  0 lvm  /
  ├─almalinux-swap          253:1    0    2G  0 lvm  [SWAP]
  ├─almalinux-var           253:2    0   15G  0 lvm  /var
  ├─almalinux-var_tmp       253:3    0    4G  0 lvm  /var/tmp
  ├─almalinux-var_log       253:4    0    9G  0 lvm  /var/log
  ├─almalinux-home          253:5    0    5G  0 lvm  /home
  ├─almalinux-var_log_audit 253:6    0    9G  0 lvm  /var/log/audit
  └─almalinux-tmp           253:7    0    4G  0 lvm  /tmp
```

---

## 3. Post-Install OS Configuration & Sudo Setup

Log in as `almalinux` and configure the administrative environment:

### 3.1 Configure Passwordless Sudo
Ansible connects as `almalinux` and uses `become: true` (sudo) to configure Vault:

```bash
echo "almalinux ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/almalinux
sudo chmod 0440 /etc/sudoers.d/almalinux
```

### 3.2 Verify Sudoers `requiretty` (CIS Level 2 Check)
Check if `requiretty` is present in `/etc/sudoers` or `/etc/sudoers.d/`:
```bash
sudo grep -ri "requiretty" /etc/sudoers /etc/sudoers.d/ || true
```
> **Important**: If `Defaults requiretty` is enabled, comment it out or remove it. Sudoers TTY requirement prevents Ansible SSH pipelining from running.

---

## 4. Install Mandatory Packages & Enable Services

Install the guest agents, Cloud-Init utilities, and firewall tools:

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

Enable all required services:
```bash
sudo systemctl enable qemu-guest-agent
sudo systemctl enable cloud-init cloud-init-local cloud-config cloud-final
sudo systemctl enable firewalld
sudo systemctl enable sshd
```

---

## 5. SSH Configuration (`sshd_config`)

Ensure `/etc/ssh/sshd_config` permits public key authentication:

```bash
# Verify Public Key Authentication is enabled
sudo grep "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config.d/vault.conf
```

---

## 6. Golden Image Sanitization (Pre-Template Checklist)

Before converting the VM into a Proxmox template, run this sanitization script to ensure cloned VMs do not share duplicate machine IDs, SSH host keys, or stale Cloud-Init caches:

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

# 4. Clean temporary files, audit logs, and DNF caches
sudo dnf clean all
sudo rm -rf /tmp/* /var/tmp/*
sudo truncate -s 0 /var/log/audit/audit.log 2>/dev/null || true
```

---

## 7. Convert to Proxmox Template

1. Shut down the template VM:
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

## 8. Verification Checklist

```
[ ] VM ID is set to 1000 on colossus and guardian
[ ] BIOS is Default (SeaBIOS) and TPM is Disabled
[ ] Hard Disk has SSD Emulation, Discard, and IO Thread enabled
[ ] QEMU Guest Agent is enabled in Proxmox Options and systemd
[ ] Cloud-Init Drive is added to VM hardware
[ ] almalinux user created with Administrator (wheel) access
[ ] Passwordless sudo configured in /etc/sudoers.d/almalinux
[ ] requiretty is NOT enforced in /etc/sudoers
[ ] Sanitization script executed (machine-id truncated, ssh_host_* removed)
[ ] VM successfully converted to template (qm template 1000)
```
