provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent = true
  }
}

locals {
  vm_nodes = {
    for k, v in var.nodes : k => v if v.type == "vm"
  }
  lxc_nodes = {
    for k, v in var.nodes : k => v if v.type == "lxc"
  }
}
