output "cluster_vms" {
  description = "Provisioned Main Vault cluster virtual machines"
  value = {
    for k, v in proxmox_virtual_environment_vm.vault_nodes : k => {
      id        = v.id
      vm_id     = v.vm_id
      node_name = v.node_name
      ipv4      = split("/", var.nodes[k].ip_cidr)[0]
    }
  }
}

output "transit_lxc" {
  description = "Provisioned Transit Vault LXC container"
  value = {
    for k, v in proxmox_virtual_environment_container.vault_transit : k => {
      id        = v.id
      vm_id     = v.vm_id
      node_name = v.node_name
      ipv4      = split("/", var.nodes[k].ip_cidr)[0]
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
%{for k, v in local.vm_nodes~}
        ${k}:
          ansible_host: ${split("/", v.ip_cidr)[0]}
          vault_node_id: ${v.vmid}
          pve_host: ${v.target_node}
%{endfor~}
    vault_transit:
      hosts:
%{for k, v in local.lxc_nodes~}
        ${k}:
          ansible_host: ${split("/", v.ip_cidr)[0]}
          vault_node_id: ${v.vmid}
          pve_host: ${v.target_node}
          ansible_user: root
%{endfor~}
EOT
}
