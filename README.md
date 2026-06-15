# Homelab Setup Tools

Infrastructure-as-code for a Raspberry Pi 4B homelab running **k3s** with GitHub Actions CI/CD.

## What's in here

| Directory | Purpose |
|---|---|
| `scripts/` | Bootstrap scripts — install the OS baseline and k3s cluster |
| `deployments/` | Kubernetes manifests organised by namespace |
| `workflows/github/` | GitHub Actions workflow templates |

---

## Prerequisites

- Raspberry Pi 4B (4 GB or 8 GB RAM recommended)
- Raspberry Pi OS (64-bit, Bookworm or later) installed and SSH accessible
- Static local IP assigned to the Pi
- This repo cloned onto the Pi: `git clone <repo-url> && cd setup-tools`

---

## Step 1 — Essential system setup

Installs system packages, Python (from source), Node.js via NVM, and Docker with Compose v2.

```bash
sudo bash scripts/homelab_essential_setup.sh
```

Expected duration: **20–40 minutes** (Python builds from source — the Pi is slow at compilation).

After it completes, **reboot** before continuing:

```bash
sudo reboot
```

### Customising Python versions

Edit `scripts/config.sh` and change the `PYTHON_VERSIONS` array before running the script.  
Or install a single version directly:

```bash
sudo bash scripts/components/02_python.sh 3.13.2
```

---

## Step 2 — Cluster setup

Installs k3s (containerd runtime), Helm, the ARC runner controller, and k9s.

```bash
export GITHUB_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"   # needs admin:org or repo scope
sudo -E bash scripts/homelab_cluster_setup.sh
```

The `-E` flag passes `GITHUB_PAT` through to the sudo environment.

Verify the cluster is up:

```bash
kubectl get nodes       # should show Ready
k9s                     # interactive TUI for the cluster
```

### PAT scopes

| Scope | Purpose |
|---|---|
| `admin:org` | Register runners at the organisation level (all repos share one runner pool) |
| `repo` | Register a runner for a single repository only |

---

## Step 3 — Apply manifests

Apply in this order so namespace dependencies are satisfied:

```bash
# 1. Create all namespaces first
kubectl apply -f deployments/namespaces.yaml

# 2. Data services (fill in secrets first — see below)
kubectl apply -f deployments/data/

# 3. Cloudflare tunnel (fill in secret first — see below)
kubectl apply -f deployments/infra/cloudflared/

# 4. MCP Mempalace
kubectl apply -f deployments/mcp/mempalace/

# 5. Docusaurus (update image tag after first CI build)
kubectl apply -f deployments/apps/docusaurus/
```

### Filling in secrets

Every manifest that contains `<REPLACE_ME>` must have a real secret before applying.  
Use `kubectl create secret` (recommended — keeps secrets out of git) or edit in-place:

```bash
# Postgres example
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_PASSWORD="your-strong-password" \
  --namespace data

# Cloudflare tunnel token
kubectl create secret generic cloudflared-secret \
  --from-literal=TUNNEL_TOKEN="your-tunnel-token" \
  --namespace infra
```

---

## Step 4 — Configure Cloudflare named tunnel

1. Log into the Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels**.
2. Create a new tunnel named `homelab`. Copy the **tunnel token**.
3. Create the k8s secret (see above).
4. In the tunnel's **Public Hostnames** tab, add routes:

   | Public hostname | Service |
   |---|---|
   | `docs.example.com` | `http://docusaurus.apps.svc.cluster.local:80` |
   | `mcp.example.com` | `http://mempalace.mcp.svc.cluster.local:3000` |

5. Apply the deployment: `kubectl apply -f deployments/infra/cloudflared/deployment.yaml`

---

## Step 5 — Wire up per-repo CI/CD

Copy `workflows/github/build-and-deploy.yaml` to `.github/workflows/deploy.yaml` in each application repo.

Edit the two `env` vars at the top:

```yaml
env:
  DEPLOYMENT_NAME: my-app      # name of the k8s Deployment to roll out
  DEPLOY_NAMESPACE: apps       # namespace of that Deployment
```

On every push to `main`, the workflow will:
1. Build and push the Docker image to GHCR (tagged with the commit SHA).
2. Update the Deployment image via `kubectl set image`.
3. Wait for rollout to complete (`kubectl rollout status --timeout=120s`).

---

## Maintenance

### Backup / restore Mempalace data

```bash
# Backup
kubectl cp mcp/mempalace-0:/data ./mempalace-backup

# Restore
kubectl cp ./mempalace-backup mcp/mempalace-0:/data
```

### Elasticsearch — virtual memory fix

If Elasticsearch pods crash-loop with `max virtual memory areas` errors:

```bash
sudo sysctl -w vm.max_map_count=262144
```

To persist across reboots, add to `/etc/sysctl.conf`:

```
vm.max_map_count=262144
```

### Storage performance note

SD cards are a bottleneck for Postgres and Elasticsearch write-heavy workloads. If you have an external USB SSD, mount it at `/data` and reconfigure the k3s `local-path-provisioner` to use it:

```bash
kubectl edit configmap local-path-config -n kube-system
# Change: paths: ["/var/lib/rancher/k3s/storage"]
# To:     paths: ["/data/k3s-storage"]
```

Then create `/data/k3s-storage` on the Pi: `sudo mkdir -p /data/k3s-storage`.

### Update ARC

```bash
helm upgrade arc-controller \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version <new-version> --namespace ci

helm upgrade homelab-runner \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version <new-version> --namespace ci \
  --reuse-values
```

---

## Resource budget (Pi 4B, 4 GB RAM)

| Workload | Memory request | Memory limit |
|---|---|---|
| k3s system | ~300 MiB | — |
| cloudflared | 64 MiB | 128 MiB |
| Docusaurus | 64 MiB | 128 MiB |
| Mempalace | 128 MiB | 512 MiB |
| ARC runner (idle) | 0 MiB | — (scale-to-zero) |
| ARC runner (active) | 256 MiB | 512 MiB |
| Postgres | 128 MiB | 512 MiB |
| Redis | 32 MiB | 128 MiB |
| **Total at idle** | **~780 MiB** | — |

Elasticsearch + Kibana consume up to 2 GiB of limits combined — deploy only when needed.
