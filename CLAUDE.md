# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Infrastructure-as-code and setup automation for a Raspberry Pi 4B homelab running k3s. Three concerns:

1. **Bootstrap scripts** (`scripts/`) — shell scripts to install the base system and k3s cluster on the Pi.
2. **Kubernetes manifests** (`deployments/`) — k3s workload definitions organised by namespace/concern.
3. **GitHub Actions workflows** (`workflows/github/`) — CI/CD templates for application repos.

---

## Script Architecture

Scripts are split into a config layer, shared helpers, individual component scripts, and orchestrators.

```
scripts/
├── config.sh                   # All configurable variables — edit here first
├── lib/common.sh               # log_info / log_error / die / require_root / command_exists
├── components/
│   ├── 01_system_deps.sh       # apt packages (build tools + audio libs)
│   ├── 02_python.sh            # Python from source — parameterizable (see below)
│   ├── 03_nvm_node.sh          # NVM + Node.js LTS (must run as non-root user)
│   ├── 04_docker.sh            # Docker CE + Compose v2 plugin + log rotation
│   ├── 05_k3s.sh               # k3s with default containerd runtime
│   ├── 06_helm.sh              # Helm 3
│   ├── 07_arc.sh               # ARC scale-set controller + runner (reads GITHUB_PAT)
│   └── 08_k9s.sh               # k9s TUI binary (ARM64, auto-detects arch)
├── homelab_essential_setup.sh  # Orchestrator: sources components 01–04
└── homelab_cluster_setup.sh    # Orchestrator: sources components 05–08
```

### `02_python.sh` — parameterizable Python install

```bash
# Uses versions from config.sh PYTHON_VERSIONS array:
sudo bash components/02_python.sh

# Or pass one or more versions explicitly:
sudo bash components/02_python.sh 3.13.2
sudo bash components/02_python.sh 3.12.9 3.11.9
```

Each version installs to `/usr/local/bin/python3.XX` with a short alias `python3XX`.

### Running the orchestrators

```bash
# Step 1 — base system (then reboot)
sudo bash scripts/homelab_essential_setup.sh

# Step 2 — cluster
export GITHUB_PAT="ghp_..."
sudo -E bash scripts/homelab_cluster_setup.sh
```

`03_nvm_node.sh` must not run as root — the orchestrator invokes it via `sudo -u $REAL_USER`.  
`07_arc.sh` requires `GITHUB_PAT` to be set before running; the cluster orchestrator enforces this.

---

## Manifest Architecture

```
deployments/
├── namespaces.yaml             # Apply first: docs | apps | dev | mcp | ci | infra | data
├── docs/                       # Docusaurus sites — namespace: docs
│   ├── docs-main/              # nginx:alpine, Traefik IngressRoute (docs.homelab.local)
│   └── docs-internal/          # nginx:alpine, Traefik IngressRoute (internal.homelab.local)
├── apps/                       # General applications — namespace: apps
├── dev/                        # Dev/test tooling — namespace: dev
│   └── trycloudflare.yaml      # Quick tunnels (no account) pointing to docs/* services
├── mcp/mempalace/              # StatefulSet + headless Service + local-path PVC (2Gi)
├── ci/arc/                     # Helm values files for ARC controller + runner scale-set
├── infra/cloudflared/          # Named tunnel Deployment + secret template (token via Secret)
└── data/                       # postgres | mongodb | redis | elasticsearch | kibana | pgadmin
```

All manifests include `namespace:` explicitly. All passwords and tokens are in `Secret` resources — files containing `<REPLACE_ME>` are templates and must be populated before applying.

### Apply order

```bash
kubectl apply -f deployments/namespaces.yaml
kubectl apply -f deployments/data/
kubectl apply -f deployments/infra/cloudflared/
kubectl apply -f deployments/mcp/mempalace/
kubectl apply -f deployments/docs/
# ARC is installed via Helm (see 07_arc.sh), not kubectl apply

# Dev tunnels (optional — para testes):
kubectl apply -f deployments/dev/trycloudflare.yaml
# Ver URLs geradas:
kubectl logs -n dev deployment/cloudflared-dev-docs-main | grep trycloudflare.com
# Remover tunnels de dev:
kubectl delete -f deployments/dev/trycloudflare.yaml
```

### Key design decisions in manifests

- **Docusaurus** — lives in namespace `docs`; served via `docusaurus serve` on port 3000 (no nginx needed). Traefik `IngressRoute` routes by hostname (`${APP_NAME}.homelab.local`). App manifests live in `.k8s/` inside each app repo — not here.
- **trycloudflare (dev)** — namespace `dev`; one Deployment per service; each pod connects to the app Service via `<svc>.<namespace>.svc.cluster.local:3000`. URL rotates on restart — production uses the named tunnel in `infra/cloudflared/`.
- **Mempalace** — `StatefulSet` (not Deployment) so the PVC identity is preserved across restarts. Headless service gives stable DNS `mempalace-0.mempalace.mcp`. Backup: `kubectl cp mcp/mempalace-0:/data ./backup`.
- **cloudflared** — named tunnel token stored in a Secret; routing rules live in the Cloudflare dashboard pointing to `<service>.<namespace>.svc.cluster.local`.
- **Elasticsearch / Kibana** — heavy (1 GiB limit each); treat as optional on a 4 GB Pi. Requires `vm.max_map_count=262144` on the host.
- **ARC runner scale-set** — `minRunners: 0` (scale-to-zero when idle). Mounts `/var/run/docker.sock` so runners can execute `docker build` against the host Docker daemon. Runner is registered at repo level (`gresas/carlos-geo-hub`) — label: `homelab-runner`.

---

## CI/CD Workflow

`workflows/github/build-and-deploy.yaml` is the per-repo template. Copy it to `.github/workflows/deploy.yaml` in each application repo — no edits needed.

Pipeline: checkout → GHCR login → `docker/build-push-action` (SHA + `latest` tags, build cache) → `envsubst` on `.k8s/*.yaml` → `kubectl apply` → `kubectl rollout status --timeout=120s` → `docker image prune -f`.

**Variables resolved at runtime:**
- `APP_NAME` — `github.event.repository.name` (repo name, no org prefix)
- `NAMESPACE` — `vars.DEPLOY_NAMESPACE` (set in repo Settings → Variables → Actions)
- `IMAGE` — `ghcr.io/<org>/<repo>:<sha>` (lowercased)

The runner is `homelab-runner` (registered for `gresas/carlos-geo-hub`; scale-set controller in namespace `ci`).

Legacy files (`build-local-legacy.yaml`, `runner-legacy.yaml`) are kept for reference only.

---

## Resource Budget (Pi 4B, 4 GB)

| Workload | Request | Limit |
|---|---|---|
| k3s system | ~300 MiB | — |
| cloudflared | 64 MiB | 128 MiB |
| Docusaurus | 64 MiB | 128 MiB |
| Mempalace | 128 MiB | 512 MiB |
| ARC runner idle | 0 MiB | — (scale-to-zero) |
| ARC runner active | 256 MiB | 512 MiB |
| Postgres | 128 MiB | 512 MiB |
| Redis | 32 MiB | 128 MiB |
| **Idle total** | **~780 MiB** | — |

Elasticsearch + Kibana add up to 2 GiB of limits — deploy only if the Pi has headroom.
