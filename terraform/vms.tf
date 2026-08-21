# Download base Debian 12 Cloud Image on target Proxmox nodes
resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  for_each = toset([var.pve_host_1, var.pve_host_2])

  content_type = "iso"
  datastore_id = var.snippet_datastore
  node_name    = each.key
  url          = var.vm_cloud_image_url
  file_name    = "debian-12-genericcloud-amd64.img"
}

# Provision the 3x Main Vault Cluster Virtual Machines
resource "proxmox_virtual_environment_vm" "vault_nodes" {
  for_each  = local.vm_nodes
  name      = each.key
  node_name = each.value.target_node
  vm_id     = each.value.vmid
  tags      = ["vault", "raft", "production"]

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
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image[each.value.target_node].id
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
