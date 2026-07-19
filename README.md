# Proxmox Talos Kubernetes Cluster

Homelab guide: provision Talos Linux VMs on Proxmox with Terraform, then bootstrap Kubernetes with `talosctl`.

This is a learn-by-doing walkthrough. Replace all placeholders (`<...>`) with your own values. **Do not commit secrets** — use `secret.auto.tfvars` (gitignored) and keep Talos credentials outside the repo.

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

Fill a private inventory (not in Git) with your real IPs, MACs, and tokens.

---

## Repository layout

```
proxmox-talos-cluster/
├── README.md
├── .gitignore
├── .cursor/agents/proxmox-talos-gitops.md   # optional playbook agent
└── infrastructure/                         # Terraform (Proxmox VMs)
    ├── versions.tf
    ├── providers.tf
    ├── variables.tf
    ├── images.tf
    ├── vms.tf
    ├── terraform.tfvars.example            # placeholders only — safe to commit
    └── secret.auto.tfvars                  # gitignored — never commit
```

Generated Talos files live **outside** Git (e.g. `~/talos-homelab/`).

---

## Prerequisites

- Terraform >= 1.5
- `talosctl` matching your Talos version
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

## Step 2 — Terraform skeleton + Talos image

### Files

**`versions.tf`** — pin provider (`bpg/proxmox`, not `hashicorp/proxmox`):

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
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

**`variables.tf`** — declare inputs (`proxmox_endpoint`, `proxmox_api_token`, node names, `talos_version`, `talos_schematic_id`, SSH key path, …).

**`secret.auto.tfvars`** — real values (gitignored). `.auto.tfvars` loads automatically. **Save the file to disk** before `plan` or Terraform prompts interactively.

**`terraform.tfvars.example`** — empty/placeholder values only; commit this, not secrets.

### Image Factory schematic

1. [factory.talos.dev](https://factory.talos.dev/) → **Cloud Server** (not Bare-metal) → QEMU / nocloud → amd64  
2. Extensions: **qemu-guest-agent** (and nocloud as applicable)  
3. Copy schematic ID into `talos_schematic_id` (keep in tfvars / private notes, not required in README)  
4. `talos_version` **without** leading `v` (URL path uses `/v${version}/`)

### `images.tf`

Download the nocloud image to **each** Proxmox node that will host VMs:

```hcl
resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.proxmox_datastore_id
  node_name               = var.proxmox_node_name
  url                     = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${var.talos_version}/nocloud-amd64.raw.xz"
  file_name               = "talos-${var.talos_version}-nocloud-amd64.img"
  decompression_algorithm = "zst"
  overwrite               = false
  overwrite_unmanaged     = false
  verify                  = false
  upload_timeout          = 3600
}

# Repeat (or for_each) for additional nodes — each node has its own local storage
```

Prefer **`proxmox_download_file`** (not deprecated `proxmox_virtual_environment_download_file`).

```bash
cd infrastructure
terraform init
terraform validate
terraform plan
terraform apply
```

**Checkpoint:** image visible under ISO/storage on each target node.

**After VMs boot:** the downloaded file is only a seed; running disks live on VM storage (e.g. `local-lvm`). Keep the image for new VMs / Terraform `file_id`; optional to delete later for space.

**`overwrite`:** keep `false` day-to-day. `true` can force image replace (compressed URL size ≠ decompressed datastore size) and **replace VMs** that depend on `file_id`.

---

## Step 3 — Create VMs

### Disk block (concepts)

| Argument | Meaning |
|----------|---------|
| `datastore_id` | Where the **VM disk** lives (e.g. `local-lvm`) |
| `file_id` | Seed from `proxmox_download_file….id` on **that** node |
| `interface = "scsi0"` | Virtio-SCSI disk |
| `size` | Grow disk (GiB) after import |
| `iothread` / `discard` | Performance / thin reclaim |

### Network

- Set **MAC** on `network_device` to match DHCP reservations  
- Talos nocloud **defaults to DHCP**; Proxmox `initialization { dhcp }` is optional  
- Stable IPs come from **MAC + DHCP reservation** (or from Talos machine config later)

### Resource shape

One `proxmox_virtual_environment_vm` per node: name, `node_name`, `vm_id`, CPU/memory/disk, MAC, `file_id` pointing at the image on the **same** Proxmox node.

```bash
terraform plan    # inspect any destroy lines carefully
terraform apply
```

**Checkpoint:**

```bash
ping -c 2 <cp-ip>
ping -c 2 <worker-1-ip>
ping -c 2 <worker-2-ip>

talosctl -n <cp-ip> version --insecure
talosctl -n <worker-1-ip> version --insecure
talosctl -n <worker-2-ip> version --insecure
```

`--insecure` works in maintenance mode. Without it, “failed to determine endpoints” is expected until machine config / `talosconfig` exist.

### Plan hygiene (lessons learned)

| Symptom | Cause | Fix |
|---------|--------|-----|
| Looking for `hashicorp/proxmox` | Missing / unsaved `versions.tf` | `source = "bpg/proxmox"` |
| SSH `user ""` | No `ssh { username }` | Configure SSH block |
| SSH auth fails | Key missing on node / `~` not expanded / empty agent | `pathexpand`, install pubkey on all nodes |
| Unexpected destroy of image + VMs | `overwrite=true` replacing image → `file_id` forces VM replace | `overwrite=false` |
| Worker replaced unexpectedly | Changed `vm_id` on an existing VM | Don’t change `vm_id` on live VMs; IDs are per-node |
| Rename resource address | Destroy + create | `terraform state mv` instead of apply-as-replace |

---

## Step 4 — Generate Talos YAML + bootstrap

Keep secrets **outside** the repo:

```bash
mkdir -p ~/talos-homelab
cd ~/talos-homelab
```

Ensure `.gitignore` excludes (already set in this repo):

```gitignore
**/talosconfig
**/kubeconfig
**/controlplane.yaml
**/worker.yaml
**/secret.auto.tfvars
configs/
```

### 4a — Generate configs

Use the **same** schematic ID and Talos version as the disk image:

```bash
SCHEMATIC="<your-image-factory-schematic-id>"
VERSION="<talos-version>"          # e.g. 1.13.6 — no leading v here; add v in image tag
CLUSTER="<cluster-name>"
ENDPOINT="https://<cp-ip>:6443"

talosctl gen config "$CLUSTER" "$ENDPOINT" \
  --output-dir . \
  --install-image "factory.talos.dev/installer/${SCHEMATIC}:v${VERSION}"
```

Produces:

| File | Purpose |
|------|---------|
| `controlplane.yaml` | Machine config for control plane |
| `worker.yaml` | Machine config for workers |
| `talosconfig` | Client credentials for `talosctl` |

**Never commit these files.**

Optional: patch configs for Cilium (`cni: none`, kube-proxy disabled), hostnames, etc., before apply.

### 4b — Apply configs

```bash
export TALOSCONFIG="$HOME/talos-homelab/talosconfig"

talosctl apply-config --insecure --nodes <cp-ip> --file controlplane.yaml
talosctl apply-config --insecure --nodes <worker-1-ip> --file worker.yaml
talosctl apply-config --insecure --nodes <worker-2-ip> --file worker.yaml
```

Nodes reboot. Wait until they respond again.

```bash
talosctl config endpoint <cp-ip>
talosctl config node <cp-ip>
talosctl -n <cp-ip> version    # without --insecure once PKI is up
```

### 4c — Bootstrap (once)

**Only on one control plane. Do not re-run casually.**

```bash
talosctl bootstrap -n <cp-ip>
```

### 4d — Kubeconfig

```bash
talosctl kubeconfig .
export KUBECONFIG="$HOME/talos-homelab/kubeconfig"
kubectl get nodes
```

Nodes may be **NotReady** until a CNI (e.g. Cilium) is installed — expected if `cluster.network.cni.name` is `none`.

### 4e — Health

```bash
talosctl -n <cp-ip> health \
  --control-plane-nodes <cp-ip> \
  --worker-nodes <worker-1-ip>,<worker-2-ip>
```

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
terraform state show proxmox_virtual_environment_vm.<name>
terraform plan          # always inspect destroy lines before apply
```

---

## Security checklist (before pushing to GitHub)

- [ ] No API tokens, passwords, or private keys in the repo
- [ ] `secret.auto.tfvars` gitignored and never staged
- [ ] No `talosconfig` / `kubeconfig` / machine YAML in Git
- [ ] README and examples use placeholders only
- [ ] `.terraform/` and `*.tfstate` gitignored

---

## References

- [Talos on Proxmox](https://www.talos.dev/latest/talos-guides/install/virtualized-platforms/proxmox/)
- [Talos Image Factory](https://factory.talos.dev/)
- [bpg/proxmox — download_file](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/download_file)
- [bpg/proxmox — virtual_environment_vm](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm)

---

## Status

| Layer | Status |
|-------|--------|
| Design + Proxmox prep | Done (local) |
| Talos image + VMs | Done (local) |
| Talos bootstrap | Documented — run with your private inventory |
| GitOps / Cilium | Not started |
