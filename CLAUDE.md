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
│   ├── 07_gitea_runner.sh      # Creates ci namespace + PVC; runner deployment is applied after Gitea is up
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
sudo bash scripts/homelab_cluster_setup.sh
```

`03_nvm_node.sh` must not run as root — the orchestrator invokes it via `sudo -u $REAL_USER`.

---

## Manifest Architecture

```
deployments/
├── namespaces.yaml             # Apply first: docs | apps | dev | mcp | ci | infra | data
├── docs/                       # Docusaurus sites — namespace: docs
│   ├── docs-main/              # nginx:alpine, Traefik IngressRoute (docs.homelab.local)
│   └── docs-internal/          # nginx:alpine, Traefik IngressRoute (internal.homelab.local)
├── apps/
│   └── gitea/                  # Gitea — namespace: apps (gitea.homelab.local)
│       ├── pvc.yaml            # 5Gi local-path PVC (SQLite DB + repos + packages/registry)
│       ├── secret.yaml         # Template: GITEA_ADMIN_PASSWORD (populate before apply)
│       ├── deployment.yaml     # gitea/gitea:latest, 512Mi limit, SQLite bundled
│       ├── service.yaml        # ClusterIP :3000 (HTTP) + NodePort 30022 (SSH git)
│       └── ingress.yaml        # IngressRoute Traefik (traefik.io/v1alpha1)
├── dev/                        # Dev/test tooling — namespace: dev
│   └── trycloudflare.yaml      # Quick tunnels (no account) pointing to docs/* services
├── mcp/mempalace/              # StatefulSet + headless Service + local-path PVC (2Gi)
├── ci/
│   ├── arc/                    # Kept for reference (legacy GitHub Actions runner)
│   └── gitea-runner/           # Gitea act_runner — namespace: ci
│       ├── pvc.yaml            # 1Gi PVC para /data (config persiste restarts)
│       ├── secret.yaml         # Template: GITEA_RUNNER_REGISTRATION_TOKEN
│       └── deployment.yaml     # gitea/act_runner:latest + docker.sock mount
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

# Gitea (aplicar secret manualmente para não commitar senha):
kubectl apply -f deployments/apps/gitea/pvc.yaml
kubectl create secret generic gitea-secret --from-literal=GITEA_ADMIN_PASSWORD=<sua-senha> -n apps
kubectl apply -f deployments/apps/gitea/deployment.yaml
kubectl apply -f deployments/apps/gitea/service.yaml
kubectl apply -f deployments/apps/gitea/ingress.yaml

# Após Gitea estar up (~30s), registrar o runner:
# Token: Admin → Site Administration → Actions → Runners
kubectl create secret generic gitea-runner-secret --from-literal=GITEA_RUNNER_REGISTRATION_TOKEN=<token> -n ci
kubectl apply -f deployments/ci/gitea-runner/deployment.yaml

# Dev tunnels (opcional):
kubectl apply -f deployments/dev/trycloudflare.yaml
kubectl logs -n dev deployment/cloudflared-dev-docs-main | grep trycloudflare.com
kubectl delete -f deployments/dev/trycloudflare.yaml
```

### Key design decisions in manifests

- **Docusaurus** — lives in namespace `docs`; served via `docusaurus serve` on port 3000 (no nginx needed). Traefik `IngressRoute` routes by hostname (`${APP_NAME}.homelab.local`). App manifests live in `.k8s/` inside each app repo — not here.
- **trycloudflare (dev)** — namespace `dev`; one Deployment per service; each pod connects to the app Service via `<svc>.<namespace>.svc.cluster.local:3000`. URL rotates on restart — production uses the named tunnel in `infra/cloudflared/`.
- **Mempalace** — `StatefulSet` (not Deployment) so the PVC identity is preserved across restarts. Headless service gives stable DNS `mempalace-0.mempalace.mcp`. Backup: `kubectl cp mcp/mempalace-0:/data ./backup`.
- **cloudflared** — named tunnel token stored in a Secret; routing rules live in the Cloudflare dashboard pointing to `<service>.<namespace>.svc.cluster.local`.
- **Elasticsearch / Kibana** — heavy (1 GiB limit each); treat as optional on a 4 GB Pi. Requires `vm.max_map_count=262144` on the host.
- **Gitea** — namespace `apps`; SQLite backend (fully self-contained in 5Gi PVC). SSH git available via NodePort 30022. Container Registry built-in (Gitea Packages, OCI-compatible). `strategy: Recreate` prevents dual-pod PVC conflict.
- **Gitea Runner** — `gitea/act_runner` in namespace `ci`. Registers automatically via `GITEA_RUNNER_REGISTRATION_TOKEN` env var. Config persists in 1Gi PVC. Mounts `/var/run/docker.sock`. Gitea Actions uses GitHub Actions YAML syntax.

---

## CI/CD Workflow

CI/CD is handled by Gitea Actions (`.gitea/workflows/*.yml` in each app repo), executed by the `act_runner` in namespace `ci`. Syntax is compatible with GitHub Actions.

Runner labels: `pi`, `docker`, `homelab`. Use `runs-on: [pi]` in workflow jobs to target this runner.

The `workflows/github/` directory contains legacy GitHub Actions templates kept for reference.

---

## Resource Budget (Pi 4B, 4 GB)

| Workload | Request | Limit |
|---|---|---|
| k3s system | ~300 MiB | — |
| cloudflared | 64 MiB | 128 MiB |
| Docusaurus | 64 MiB | 128 MiB |
| Mempalace | 128 MiB | 512 MiB |
| Gitea (SQLite) | 128 MiB | 512 MiB |
| Gitea Runner (idle) | 128 MiB | 512 MiB |
| Postgres | 128 MiB | 512 MiB |
| Redis | 32 MiB | 128 MiB |
| **Idle total** | **~944 MiB** | — |

~2.7 GiB free for CI/CD job peaks and other workloads.
Elasticsearch + Kibana add up to 2 GiB of limits — deploy only if the Pi has 8 GB RAM.
