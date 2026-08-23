proxmox_url          = "https://colossus.jnet.lan:8006/api2/json"
proxmox_token_id     = "terraform-ci@pve!gitlab-runner"
proxmox_token_secret = "00000000-0000-0000-0000-000000000000"
proxmox_node         = "colossus"

template_vm_id = 1000
template_name  = "almalinux-9-cis2-template"
iso_file       = "local:iso/AlmaLinux-9-latest-x86_64-boot.iso"
storage_pool   = "local-lvm"
network_bridge = "vmbr0"

ssh_username = "almalinux"
ssh_password = "PackerBuildTempPasswordChangeMe!"
vault_version = "1.18.3"
