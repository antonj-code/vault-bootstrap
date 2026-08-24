# ==============================================================================
# PROXMOX HOST 2 (Standalone pve-02): vault-transit LXC
# ==============================================================================

resource "proxmox_virtual_environment_container" "vault_transit" {
  provider  = proxmox.pve2
  for_each  = var.host2_lxcs
  node_name = var.pve_host_2_node_name
  vm_id     = each.value.vmid
  tags      = ["vault", "transit", "auto-unseal", "host2"]

  description = each.value.description

  cpu {
    cores = var.vault_lxc_config.cores
  }

  memory {
    dedicated = var.vault_lxc_config.memory
    swap      = 0
  }

  disk {
    datastore_id = var.storage_datastore
    size         = var.vault_lxc_config.disk_size
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = var.network_gateway
      }
    }

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    user_account {
      keys = local.parsed_ssh_keys
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_path
    type             = "centos"
  }

  unprivileged = true

  features {
    nesting = true
  }
}
