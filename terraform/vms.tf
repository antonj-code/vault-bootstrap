# ==============================================================================
# PROXMOX HOST 1 (Standalone pve-01): vault-01, vault-02
# ==============================================================================

# Download base Debian 12 Cloud Image on Host 1
resource "proxmox_virtual_environment_download_file" "debian_cloud_image_host1" {
  provider     = proxmox.pve1
  content_type = "iso"
  datastore_id = var.snippet_datastore
  node_name    = var.pve_host_1_node_name
  url          = var.vm_cloud_image_url
  file_name    = "debian-12-genericcloud-amd64.img"
}

# Provision vault-01 and vault-02 on Host 1
resource "proxmox_virtual_environment_vm" "vault_nodes_host1" {
  provider  = proxmox.pve1
  for_each  = var.host1_vms
  name      = each.key
  node_name = var.pve_host_1_node_name
  vm_id     = each.value.vmid
  tags      = ["vault", "raft", "host1"]

  description = each.value.description

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
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image_host1.id
    interface    = "virtio0"
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
      keys     = var.ssh_public_keys
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
# PROXMOX HOST 2 (Standalone pve-02): vault-03
# ==============================================================================

# Download base Debian 12 Cloud Image on Host 2
resource "proxmox_virtual_environment_download_file" "debian_cloud_image_host2" {
  provider     = proxmox.pve2
  content_type = "iso"
  datastore_id = var.snippet_datastore
  node_name    = var.pve_host_2_node_name
  url          = var.vm_cloud_image_url
  file_name    = "debian-12-genericcloud-amd64.img"
}

# Provision vault-03 on Host 2
resource "proxmox_virtual_environment_vm" "vault_nodes_host2" {
  provider  = proxmox.pve2
  for_each  = var.host2_vms
  name      = each.key
  node_name = var.pve_host_2_node_name
  vm_id     = each.value.vmid
  tags      = ["vault", "raft", "host2"]

  description = each.value.description

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
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image_host2.id
    interface    = "virtio0"
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
      keys     = var.ssh_public_keys
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
