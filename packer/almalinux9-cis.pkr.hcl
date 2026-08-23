packer {
  required_version = ">= 1.9.0"
  required_providers {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "almalinux9_cis" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id                = var.template_vm_id
  vm_name              = var.template_name
  template_description = "AlmaLinux 9 CIS Level 2 Hardened Base Image - Automated Weekly Build"

  iso_file = var.iso_file

  qemu_agent = true
  cores      = 2
  memory     = 2048
  cpu_type   = "host"
  os         = "l26"

  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "20G"
    format       = "raw"
    storage_pool = var.storage_pool
    type         = "scsi"
    io_thread    = true
    discard      = true
  }

  network_adapters {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # Kickstart HTTP Server
  http_directory = "packer/http"

  boot_wait = "5s"
  boot_command = [
    "<tab>",
    " text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<enter>"
  ]

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "20m"
}

build {
  sources = ["source.proxmox-iso.almalinux9_cis"]

  # Step 1: Execute CIS Level 2 OS Hardening & Pre-bake Vault Binary
  provisioner "shell" {
    environment_vars = [
      "VAULT_VERSION=${var.vault_version}"
    ]
    scripts = [
      "packer/scripts/cis-hardening.sh",
      "packer/scripts/cleanup.sh"
    ]
  }
}
