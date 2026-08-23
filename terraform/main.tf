# Proxmox Host 1 Provider (Standalone)
provider "proxmox" {
  alias     = "pve1"
  endpoint  = var.pve_host_1_endpoint
  api_token = var.pve_host_1_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent = true
  }
}

# Proxmox Host 2 Provider (Standalone)
provider "proxmox" {
  alias     = "pve2"
  endpoint  = var.pve_host_2_endpoint
  api_token = var.pve_host_2_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent = true
  }
}

locals {
  parsed_ssh_keys = can(tolist(var.ssh_public_keys)) ? tolist(var.ssh_public_keys) : [tostring(var.ssh_public_keys)]
}
