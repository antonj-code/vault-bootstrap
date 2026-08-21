output "cluster_vms_host1" {
  description = "Provisioned Main Vault cluster virtual machines on Host 1"
  value = {
    for k, v in proxmox_virtual_environment_vm.vault_nodes_host1 : k => {
      id        = v.id
      vm_id     = v.vm_id
      node_name = v.node_name
      ipv4      = split("/", var.host1_vms[k].ip_cidr)[0]
    }
  }
}

output "cluster_vms_host2" {
  description = "Provisioned Main Vault cluster virtual machines on Host 2"
  value = {
    for k, v in proxmox_virtual_environment_vm.vault_nodes_host2 : k => {
      id        = v.id
      vm_id     = v.vm_id
      node_name = v.node_name
      ipv4      = split("/", var.host2_vms[k].ip_cidr)[0]
    }
  }
}

output "transit_lxc_host2" {
  description = "Provisioned Transit Vault LXC container on Host 2"
  value = {
    for k, v in proxmox_virtual_environment_container.vault_transit : k => {
      id        = v.id
      vm_id     = v.vm_id
      node_name = v.node_name
      ipv4      = split("/", var.host2_lxcs[k].ip_cidr)[0]
    }
  }
}

# Generate Ansible dynamic inventory file
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.yaml"
  content  = <<-EOT
all:
  vars:
    ansible_user: ${var.ci_user}
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
  children:
    vault_cluster:
      hosts:
%{for k, v in var.host1_vms~}
        ${k}:
          ansible_host: ${split("/", v.ip_cidr)[0]}
          vault_node_id: ${v.vmid}
          pve_host: ${var.pve_host_1_node_name}
%{endfor~}
%{for k, v in var.host2_vms~}
        ${k}:
          ansible_host: ${split("/", v.ip_cidr)[0]}
          vault_node_id: ${v.vmid}
          pve_host: ${var.pve_host_2_node_name}
%{endfor~}
    vault_transit:
      hosts:
%{for k, v in var.host2_lxcs~}
        ${k}:
          ansible_host: ${split("/", v.ip_cidr)[0]}
          vault_node_id: ${v.vmid}
          pve_host: ${var.pve_host_2_node_name}
          ansible_user: root
%{endfor~}
EOT
}
