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

# 5. ARC RBAC (runner needs permission to deploy to docs/apps namespaces)
kubectl apply -f deployments/ci/arc/rbac.yaml
```

Application workloads (Docusaurus sites, APIs, etc.) are built automatically on every push and deployed manually via `workflow_dispatch` — **do not apply them manually**. See Step 5.

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

Each application repo needs two things:

**1. Workflow** — copy `workflows/github/build-and-deploy.yaml` to `.github/workflows/deploy.yaml` in the app repo. No edits needed — it reads everything from git context and GitHub variables.

The workflow has two jobs: **`build`** runs automatically on every push/tag and validates the image compiles. **`deploy`** runs automatically on push to `master`, `main`, or `develop` — re-running the workflow manually serves as a redeploy without a new push.

**2. Manifests** — create a `.k8s/` directory in the app repo with four files (use `deployments/templates/docusaurus/` as reference):

```
.k8s/
├── deployment.yaml       # uses ${APP_NAME}, ${NAMESPACE}, ${IMAGE} placeholders
├── service.yaml
├── ingress.yaml          # Traefik IngressRoute — Host(`${APP_NAME}.homelab.local`)
└── trycloudflare.yaml    # ephemeral public URL via cloudflared
```

**3. GitHub variables** — in the repo's Settings → Variables → Actions, add:

```
DEPLOY_NAMESPACE = docs   # (or apps, or whichever namespace this app goes into)
```

Optional:

```
CLOUDFLARE_TUNNEL = false  # omit or set "true" to expose via Cloudflare (default)
                           # set "false" for internal-only deploy (homelab.local, no cloudflared)
```

On `develop`, the tunnel is a temporary trycloudflare URL. On `master`/`main`, it uses a named Cloudflare tunnel (requires the token secret — see Step 4).

On every push to `master`/`main`/`develop`, both jobs run: `build` validates the image and `deploy` applies the `.k8s/` manifests and waits for rollout (`kubectl rollout status --timeout=120s`). Tags trigger only `build`. To redeploy without a new push, re-run the workflow manually.

`APP_NAME` is derived from `github.event.repository.name` — no manual config needed.

---

## Maintenance

### Backup / restore Gitea data

Gitea uses SQLite — everything (DB, repos, packages) lives in a single 5Gi PVC mounted at `/data`.

#### Backup automático (recomendado)

Instala um cron diário às 05:00 que salva em `~/backups/gitea/` e mantém os últimos 4 backups:

```bash
# Instalar (como usuário regular, sem sudo):
bash scripts/setup_backup_cron.sh

# Testar manualmente:
bash scripts/backup_gitea.sh

# Ver backups e log:
ls -lh ~/backups/gitea/
tail -f ~/backups/gitea/backup.log
```

Configuração em `scripts/config.sh`: `BACKUP_DIR` e `BACKUP_RETAIN_COUNT`.

#### Recuperação após reinstall do k3s

```bash
# 1. Reinstalar cluster e subir Gitea do zero:
sudo bash scripts/homelab_cluster_setup.sh
bash scripts/deploy_gitea.sh

# 2. Parar o Gitea para restaurar sem conflito de escrita:
kubectl scale deployment gitea -n apps --replicas=0
kubectl wait --for=delete pod -l app=gitea -n apps --timeout=60s

# 3. Subir o pod para montar o PVC vazio, depois restaurar:
kubectl scale deployment gitea -n apps --replicas=1
kubectl wait --for=condition=ready pod -l app=gitea -n apps --timeout=120s
BACKUP=$(ls -1dt ~/backups/gitea/[0-9]* | head -1)
POD=$(kubectl get pod -n apps -l app=gitea -o name | cut -d/ -f2)
kubectl cp "$BACKUP/." "apps/$POD:/data"

# 4. Reiniciar para carregar o estado restaurado:
kubectl rollout restart deployment/gitea -n apps
kubectl rollout status deployment/gitea -n apps --timeout=120s
```

> Após a restauração, usuários, repos e tokens voltam ao estado do backup — o admin criado pelo `deploy_gitea.sh` é sobrescrito.

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
  --version <new-version> \
  --namespace ci \
  --set githubConfigUrl="https://github.com/gresas/carlos-geo-hub" \
  --set githubConfigSecret=personal-runner-secret \
  --values deployments/ci/arc/runner-values.yaml
```

### Troubleshoot stuck runner (EphemeralRunner `InvalidPod`)

If runner pods fail with `spec.containers[0].image: Required value`, the runner image is missing from `runner-values.yaml`. Ensure `template.spec.containers[0].image` is set and re-run the helm upgrade above.

If jobs stay **Queued** after the runner shows Online:

```bash
# 1. CoreDNS must be Running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Listener logs should show "Getting next message"
kubectl logs -n ci -l app.kubernetes.io/component=listener \
  -l actions.github.com/scale-set-name=homelab-runner --tail=20

# 3. Check ephemeral runner pod status
kubectl describe ephemeralrunners -n ci
```

Flannel CNI failure (`subnet.env: no such file`) is fixed by restarting k3s:
```bash
sudo systemctl restart k3s
kubectl delete pod -n kube-system -l k8s-app=kube-dns   # recreate if still ContainerCreating
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
