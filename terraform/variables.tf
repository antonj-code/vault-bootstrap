# --- Proxmox Host 1 Connection ---
variable "pve_host_1_endpoint" {
  description = "The Proxmox VE API endpoint for Host 1 (e.g., https://10.10.10.2:8006/)"
  type        = string
}

variable "pve_host_1_api_token" {
  description = "Proxmox API token for Host 1 (USER@REALM!TOKENID=SECRET)"
  type        = string
  sensitive   = true
}

variable "pve_host_1_node_name" {
  description = "Proxmox internal node name for Host 1"
  type        = string
  default     = "colossus"
}

# --- Proxmox Host 2 Connection ---
variable "pve_host_2_endpoint" {
  description = "The Proxmox VE API endpoint for Host 2 (e.g., https://guardian.jnet.lan:8006/)"
  type        = string
}

variable "pve_host_2_api_token" {
  description = "Proxmox API token for Host 2 (USER@REALM!TOKENID=SECRET)"
  type        = string
  sensitive   = true
}

variable "pve_host_2_node_name" {
  description = "Proxmox internal node name for Host 2"
  type        = string
  default     = "guardian"
}

variable "proxmox_insecure" {
  description = "Set to true to ignore self-signed SSL certificate warnings from Proxmox"
  type        = bool
  default     = true
}

# --- Storage & Network Configuration ---
variable "storage_datastore" {
  description = "Storage datastore for VM and LXC root disks (e.g. local-lvm, local-zfs, ceph-pool)"
  type        = string
  default     = "local-lvm"
}

variable "snippet_datastore" {
  description = "Datastore storing Cloud-Init snippets or download files (e.g. local)"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Proxmox virtual network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default IPv4 Gateway for VMs and Containers"
  type        = string
  default     = "192.169.0.1"
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_public_keys" {
  description = "SSH public keys (accepts JSON list of strings or single raw string) injected into VMs and LXC"
  type        = any
  default     = []
}

variable "template_vm_id" {
  description = "Proxmox VM ID of the CIS Level 2 AlmaLinux 9 template on colossus and guardian"
  type        = number
  default     = 1000
}

variable "ci_user" {
  description = "Cloud-Init default administrator username"
  type        = string
  default     = "almalinux"
}

# --- Sizing ---
variable "vault_vm_config" {
  description = "Configuration parameters for Main Vault VMs"
  type = object({
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    cores     = 2
    memory    = 4096
    disk_size = 32
  }
}

variable "vault_lxc_config" {
  description = "Configuration parameters for Transit Vault LXC"
  type = object({
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    cores     = 1
    memory    = 1024
    disk_size = 8
  }
}

variable "lxc_template_path" {
  description = "Volume ID / Path of the AlmaLinux 9 LXC OS template on guardian (e.g. local:vztmpl/almalinux-9-default_latest.tar.xz)"
  type        = string
  default     = "local:vztmpl/almalinux-9-default_latest.tar.xz"
}

# --- Host 1 Node Allocations (colossus) ---
variable "host1_vms" {
  description = "VMs to deploy on standalone Host 1 (colossus)"
  type = map(object({
    vmid        = number
    ip_cidr     = string
    description = string
  }))
  default = {
    "vm-vault-01" = {
      vmid        = 501
      ip_cidr     = "192.169.0.201/24"
      description = "Main Vault Cluster Node 01 (Raft - colossus)"
    }
    "vm-vault-02" = {
      vmid        = 502
      ip_cidr     = "192.169.0.202/24"
      description = "Main Vault Cluster Node 02 (Raft - colossus)"
    }
  }
}

# --- Host 2 Node Allocations (guardian) ---
variable "host2_vms" {
  description = "VMs to deploy on standalone Host 2 (guardian)"
  type = map(object({
    vmid        = number
    ip_cidr     = string
    description = string
  }))
  default = {
    "vm-vault-03" = {
      vmid        = 503
      ip_cidr     = "192.169.0.203/24"
      description = "Main Vault Cluster Node 03 (Raft - guardian)"
    }
  }
}

variable "host2_lxcs" {
  description = "LXCs to deploy on standalone Host 2 (guardian)"
  type = map(object({
    vmid        = number
    ip_cidr     = string
    description = string
  }))
  default = {
    "vm-vault-transit" = {
      vmid        = 500
      ip_cidr     = "192.169.0.200/24"
      description = "Isolated Transit Vault LXC (Auto-Unseal Engine - guardian)"
    }
  }
}
