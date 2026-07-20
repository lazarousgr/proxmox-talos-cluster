# Proxmox Talos Kubernetes Cluster

Homelab guide: provision Talos Linux VMs on Proxmox **and** bootstrap Kubernetes with Terraform (`bpg/proxmox` + `siderolabs/talos`).

Replace placeholders with your own values. **Do not commit secrets** — use `secret.auto.tfvars` (gitignored). Keep `talosconfig` / `kubeconfig` outside Git.

---

## Example topology

Illustrative layout (1 control plane + 2 workers on a 2-node Proxmox cluster):

| Role | Example hostname | Proxmox node | Example VM ID | Notes |
|------|------------------|--------------|---------------|--------|
| Control plane | `talos-cp` | `<pve-node-1>` | `800` | One CP is fine for non-prod |
| Worker | `talos-wrk1` | `<pve-node-1>` | `801` | |
| Worker | `talos-wrk2` | `<pve-node-2>` | `810` | VM IDs are per-node |

| Setting | Example / placeholder |
|---------|------------------------|
| Proxmox API | `https://<pve-api-host>:8006/` |
| Bridge | `vmbr0` |
| Image storage | `local` |
| VM disk storage | `local-lvm` |
| Talos version | Pin a release (e.g. from [Talos releases](https://github.com/siderolabs/talos/releases)) |
| Schematic ID | From [Image Factory](https://factory.talos.dev/) |
| Cluster API (1 CP) | `https://<cp-ip>:6443` (no VIP required) |
| Node IPs | DHCP reservations keyed by VM MAC |

Put real IPs, MACs, VM IDs, schematic ID, and tokens in `secret.auto.tfvars` only.

---

## Repository layout

```
proxmox-talos-cluster/
├── README.md
├── .gitignore
├── proxmox-talos-gitops.md                  # optional playbook notes
└── infrastructure/                         # Terraform (Proxmox + Talos)
    ├── versions.tf                         # bpg/proxmox + siderolabs/talos
    ├── providers.tf
    ├── variables.tf
    ├── images.tf                           # Talos image per Proxmox node
    ├── vms.tf                              # control plane + workers
    ├── talos.tf                            # secrets, config apply, bootstrap
    ├── outputs.tf                          # kubeconfig / talosconfig (sensitive)
    ├── terraform.tfvars.example            # placeholders only — safe to commit
    └── secret.auto.tfvars                  # gitignored — never commit
```

After apply, write client configs locally (gitignored), e.g. `talos-homelab/`.

---

## Prerequisites

- Terraform >= 1.5
- `kubectl` (and optionally `talosctl` matching your Talos version)
- SSH key for a privileged OS user (often `root`) on **every** Proxmox node that will run VMs
- Proxmox API token (prefer token over password)
- DHCP reservations (or a static IP plan) for cluster nodes

---

## Step 0 — Design

Decide before writing Terraform:

- [ ] Control plane count (homelab: **1** is OK; never **2**; prod HA: **3**)
- [ ] Worker count and which Proxmox nodes host them
- [ ] Networking: DHCP reservations by MAC vs static IPs in Talos config
- [ ] API endpoint: single CP IP vs Layer-2 VIP (VIP only if multiple CPs)
- [ ] VM sizing (CPU / RAM / disk)

**Rules:** etcd needs an odd control-plane count; for HA place at most one CP per physical host.

---

## Step 1 — Prepare Proxmox

### API token

```bash
pveum user add tfuser@pam --comment "Terraform"
pveum aclmod / -user tfuser@pam -role Administrator   # tighten ACLs later
pveum user token add tfuser@pam terraform --privsep 0
```

Token format: `user@realm!tokenid=<secret>` — store only in `secret.auto.tfvars`.

### Verify API

```bash
curl -k -H "Authorization: PVEAPIToken=<user@realm!tokenid=secret>" \
  "https://<pve-api-host>:8006/api2/json/nodes"
```

Expect JSON listing your Proxmox node names.

### SSH (required for VM disk import)

```bash
ssh-copy-id -i ~/.ssh/<your-key>.pub root@<pve-node-1-host>
ssh-copy-id -i ~/.ssh/<your-key>.pub root@<pve-node-2-host>
ssh -i ~/.ssh/<your-key> root@<pve-node-1-host>
ssh -i ~/.ssh/<your-key> root@<pve-node-2-host>
```

**Why SSH?** The `bpg/proxmox` provider uses the HTTPS API for most operations, but **importing a disk from `file_id` into LVM** often runs over SSH to that node. API token ≠ SSH user. Authorize the same public key on every node you target.

---

## Step 2 — Configure Terraform

### Providers

**`versions.tf`** — pin providers (`bpg/proxmox`, not `hashicorp/proxmox`):

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}
```

**`providers.tf`** — API + SSH:

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true   # only if using self-signed certs

  ssh {
    username    = "root"
    private_key = file(pathexpand(var.proxmox_ssh_private_key))
  }
}
```

Use `pathexpand()` — Terraform `file()` does **not** expand `~` alone.

### Secrets inventory (`secret.auto.tfvars`)

Copy from the example and fill real values. `.auto.tfvars` loads automatically. **Save the file to disk** before `plan`.

```bash
cd infrastructure
cp terraform.tfvars.example secret.auto.tfvars
# edit secret.auto.tfvars — never commit it
```

Typical private fields:

| Variable | Purpose |
|----------|---------|
| `proxmox_endpoint` / `proxmox_api_token` | Proxmox API |
| `proxmox_node_name` / `proxmox_node_name_pve2` | Target hosts |
| `proxmox_ssh_private_key` | Path to SSH key (`~` OK with `pathexpand`) |
| `talos_version` / `talos_schematic_id` | Image Factory build |
| `talos_controlplane_ip` / `talos_worker_ips` | DHCP-reserved node IPs |
| `talos_cp_mac` / `talos_wrk_mac` | NIC MACs matching those reservations |
| `talos_cp_vm_id` / `talos_wrk_vm_id` | Proxmox VM IDs (per-node) |

**`terraform.tfvars.example`** — empty/placeholder values only; commit this, not secrets.

Committed `.tf` files should not contain real lab IPs, MACs, or tokens.

### Image Factory schematic

1. [factory.talos.dev](https://factory.talos.dev/) → **Cloud Server** (not Bare-metal) → QEMU / nocloud → amd64  
2. Extensions: **qemu-guest-agent** (and nocloud as applicable)  
3. Copy schematic ID into `talos_schematic_id` in `secret.auto.tfvars`  
4. `talos_version` **without** leading `v` (URL path uses `/v${version}/`)

### What Terraform creates

| File | Resources |
|------|-----------|
| `images.tf` | Talos nocloud image on each Proxmox node (`overwrite=false`) |
| `vms.tf` | Control plane + worker VMs (MACs / VM IDs from variables) |
| `talos.tf` | Machine secrets, config apply, bootstrap, kubeconfig |
| `outputs.tf` | Sensitive `kubeconfig` / `talosconfig` |

Hostnames use Talos **`HostnameConfig`** documents (not `machine.network.hostname` — rejected on Talos 1.13+).

---

## Step 3 — Apply (images + VMs + bootstrap)

```bash
cd infrastructure
terraform init
terraform validate
terraform plan          # inspect destroy / replace lines carefully
terraform apply
```

**Checkpoint after apply:**

```bash
mkdir -p ../talos-homelab
terraform output -raw kubeconfig  > ../talos-homelab/kubeconfig
terraform output -raw talosconfig > ../talos-homelab/talosconfig
chmod 600 ../talos-homelab/kubeconfig ../talos-homelab/talosconfig

export KUBECONFIG="$PWD/../talos-homelab/kubeconfig"
export TALOSCONFIG="$PWD/../talos-homelab/talosconfig"

kubectl get nodes
# optional:
talosctl -n <cp-ip> health \
  --control-plane-nodes <cp-ip> \
  --worker-nodes <worker-1-ip>,<worker-2-ip>
```

Nodes may show **NotReady** briefly while kubelet starts; wait a minute and re-check.

### First-apply race (known)

Config apply can fail if VMs are not yet reachable on the Talos maintenance API (`talosctl -n <ip> version --insecure`). Wait until all nodes answer, then run `terraform apply` again — it will finish bootstrap/kubeconfig.

### Destroy

```bash
cd infrastructure
terraform destroy
```

Removes VMs, images, and Terraform-managed Talos state. Local `talos-homelab/` files become obsolete.

---

## Disk / network notes

| Argument | Meaning |
|----------|---------|
| `datastore_id` (disk) | Where the **VM disk** lives (e.g. `local-lvm`) |
| `file_id` | Seed from `proxmox_download_file….id` on **that** node |
| `interface = "scsi0"` | Virtio-SCSI disk |
| `size` | Grow disk (GiB) after import |

- Set **MAC** via variables to match DHCP reservations  
- Talos nocloud **defaults to DHCP**; Proxmox `initialization { dhcp }` is optional  
- Stable IPs come from **MAC + DHCP reservation**

**After VMs boot:** the downloaded file is only a seed; running disks live on VM storage. Keep the image for new VMs / Terraform `file_id`.

**`overwrite`:** keep `false` day-to-day. `true` can force image replace and **replace VMs** that depend on `file_id`.

### Plan hygiene (lessons learned)

| Symptom | Cause | Fix |
|---------|--------|-----|
| Looking for `hashicorp/proxmox` | Missing / unsaved `versions.tf` | `source = "bpg/proxmox"` |
| SSH `user ""` | No `ssh { username }` | Configure SSH block |
| SSH auth fails | Key missing on node / `~` not expanded | `pathexpand`, install pubkey on all nodes |
| Unexpected destroy of image + VMs | `overwrite=true` replacing image → `file_id` forces VM replace | `overwrite=false` |
| Worker replaced unexpectedly | Changed `vm_id` on an existing VM | Don’t change `vm_id` on live VMs; IDs are per-node |
| `static hostname is already set` | `machine.network.hostname` on Talos 1.13+ | Use `HostnameConfig` document |
| Config apply fails right after VM create | Maintenance API not ready yet | Wait + re-apply |
| Rename resource address | Destroy + create | `terraform state mv` instead of apply-as-replace |

---

## Later steps

| Step | Goal |
|------|------|
| 5 | Bootstrap ArgoCD (or Flux) |
| 6 | Platform via GitOps: Cilium → CSI → cert-manager → MetalLB / ingress |
| 7 | Backups, upgrades, rebuild-from-zero docs |

---

## Useful commands

```bash
cd infrastructure
terraform state list
terraform state show proxmox_virtual_environment_vm.cp_1
terraform plan          # always inspect destroy lines before apply
terraform output -raw kubeconfig > ../talos-homelab/kubeconfig
```

---

## Security checklist (before pushing to GitHub)

- [ ] No API tokens, passwords, or private keys in the repo
- [ ] `secret.auto.tfvars` gitignored and never staged
- [ ] No real lab IPs / MACs in committed `.tf` files (use variables + example placeholders)
- [ ] No `talosconfig` / `kubeconfig` / machine YAML in Git
- [ ] README and examples use placeholders only
- [ ] `.terraform/` and `*.tfstate` gitignored

---

## References

- [Talos on Proxmox](https://www.talos.dev/latest/talos-guides/install/virtualized-platforms/proxmox/)
- [Talos Image Factory](https://factory.talos.dev/)
- [siderolabs/talos Terraform provider](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- [bpg/proxmox — download_file](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/download_file)
- [bpg/proxmox — virtual_environment_vm](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm)

---

## Status

| Layer | Status |
|-------|--------|
| Design + Proxmox prep | Done (local) |
| Talos image + VMs (Terraform) | Done |
| Talos bootstrap (Terraform) | Done |
| GitOps / Cilium | Not started |
