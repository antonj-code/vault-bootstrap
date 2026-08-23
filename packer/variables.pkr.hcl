variable "proxmox_url" {
  type        = string
  description = "The Proxmox VE API endpoint (e.g. https://colossus.jnet.lan:8006/api2/json)"
}

variable "proxmox_token_id" {
  type        = string
  description = "Proxmox API Token ID (e.g. terraform-ci@pve!gitlab-runner)"
}

variable "proxmox_token_secret" {
  type        = string
  description = "Proxmox API Token Secret"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  description = "Target Proxmox node name where the template will be built"
  default     = "colossus"
}

variable "template_vm_id" {
  type        = number
  description = "VM ID for the generated AlmaLinux 9 CIS Level 2 template"
  default     = 1000
}

variable "template_name" {
  type        = string
  description = "Name for the Proxmox template"
  default     = "almalinux-9-cis2-template"
}

variable "iso_file" {
  type        = string
  description = "Proxmox storage volume ID of the AlmaLinux 9 Boot/DVD ISO"
  default     = "local:iso/AlmaLinux-9-latest-x86_64-boot.iso"
}

variable "storage_pool" {
  type        = string
  description = "Target storage pool for the template disk"
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Network bridge for the build VM"
  default     = "vmbr0"
}

variable "ssh_username" {
  type        = string
  description = "Temporary SSH username for Packer provisioning"
  default     = "almalinux"
}

variable "ssh_password" {
  type        = string
  description = "Temporary SSH password for Packer provisioning"
  sensitive   = true
  default     = "PackerBuildTempPass123!"
}

variable "vault_version" {
  type        = string
  description = "HashiCorp Vault binary version to bake into the image"
  default     = "1.18.3"
}
