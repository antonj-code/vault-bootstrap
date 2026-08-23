# ==============================================================================
# PROXMOX HOST 1 (Standalone colossus): vm-vault-01, vm-vault-02
# Cloned from AlmaLinux 9 CIS Level 2 Template (ID 1000)
# ==============================================================================

resource "proxmox_virtual_environment_vm" "vault_nodes_host1" {
  provider  = proxmox.pve1
  for_each  = var.host1_vms
  name      = each.key
  node_name = var.pve_host_1_node_name
  vm_id     = each.value.vmid
  tags      = ["vault", "raft", "host1", "almalinux9", "cis2"]

  description = each.value.description

  clone {
    vm_id = var.template_vm_id
  }

  cpu {
    cores = var.vault_vm_config.cores
    type  = "host"
  }

  memory {
    dedicated = var.vault_vm_config.memory
    floating  = var.vault_vm_config.memory
  }

  agent {
    enabled = true
    timeout = "10m"
  }

  disk {
    datastore_id = var.storage_datastore
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.vault_vm_config.disk_size
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.ci_user
      keys     = local.parsed_ssh_keys
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}

# ==============================================================================
# PROXMOX HOST 2 (Standalone guardian): vm-vault-03
# Cloned from AlmaLinux 9 CIS Level 2 Template (ID 1000)
# ==============================================================================

resource "proxmox_virtual_environment_vm" "vault_nodes_host2" {
  provider  = proxmox.pve2
  for_each  = var.host2_vms
  name      = each.key
  node_name = var.pve_host_2_node_name
  vm_id     = each.value.vmid
  tags      = ["vault", "raft", "host2", "almalinux9", "cis2"]

  description = each.value.description

  clone {
    vm_id = var.template_vm_id
  }

  cpu {
    cores = var.vault_vm_config.cores
    type  = "host"
  }

  memory {
    dedicated = var.vault_vm_config.memory
    floating  = var.vault_vm_config.memory
  }

  agent {
    enabled = true
    timeout = "10m"
  }

  disk {
    datastore_id = var.storage_datastore
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.vault_vm_config.disk_size
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.ci_user
      keys     = local.parsed_ssh_keys
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}
