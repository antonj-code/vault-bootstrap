# Rolling Updates Guide

Vault nodes are updated in place, one at a time, so 2 of the 3 Raft voters stay online and quorum holds throughout. There are two ways to do this: version upgrades through the GitOps pipeline, and a manual rolling update playbook.

---

## 1. Upgrading Vault via GitOps

Vault version upgrades need no manual steps. Change `vault_version` in `ansible/inventory/group_vars/all.yaml` (keep `roles/vault_common/defaults/main.yaml` in sync), commit, and push to `main`. The `ansible:configure` job then:

1. **Installs the new binary** on every node whose installed version differs, verified against HashiCorp's `SHA256SUMS`. The binary is swapped atomically, so running nodes keep serving on the old version.
2. **Restarts nodes one at a time** (`playbooks/rolling_restart.yaml`, imported by `site.yaml`), only where the running version differs:
   * `vm-vault-transit` first, re-unsealed via `vault-transit-unseal.service`. The cluster stays unsealed meanwhile.
   * Then each standby, then the active leader last, so leadership moves to an already-upgraded node.
   * Each node must come back unsealed on the new version before the next one starts; any failure stops the rollout.
3. **Refuses to start** if any cluster node is sealed or unhealthy before the rollout.

When versions already match (including a fresh bootstrap), the restart step does nothing. Downgrades work the same way, but check HashiCorp's upgrade notes first: not every version jump is reversible.

VMs cloned from Template 1000 carry whatever Vault version was installed in the template; the pipeline upgrades them to `vault_version` on their first run.

Take a Raft snapshot before pushing a version change (see `docs/security-operations.md`).

---

## 2. Manual Rolling Update

The `rolling_update.yaml` playbook re-applies the `vault_common`, `vault_pki`, and `vault_cluster` roles to each node in `vault_cluster` in place and restarts Vault, one node at a time. It does not rebuild VMs and does not touch `vm-vault-transit`.

```bash
cd ansible
ansible-playbook -i inventory/hosts.yaml playbooks/rolling_update.yaml
```

### Safety Features Built-In:
1. **Pre-flight Snapshot**: Automatically saves a timestamped snapshot to `credentials/backups/raft-pre-repave-<timestamp>.snap`.
2. **Graceful Leader Step-Down**: If the node being cycled is the current active leader, Ansible calls `vault operator step-down` to transfer leadership before restarting.
3. **Quorum Gate**: Ansible polls `vault operator raft list-peers` and **will not proceed** to the next node until the restarted node has unsealed and rejoined the Raft consensus ring.
