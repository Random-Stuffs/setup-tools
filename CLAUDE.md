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
│   ├── 07_gitea_runner.sh      # Creates ci namespace + PVC; runner deployment applied after Gitea is up
│   └── 08_k9s.sh               # k9s TUI binary (ARM64, auto-detects arch)
├── homelab_essential_setup.sh  # Orchestrator: sources components 01–04
├── homelab_cluster_setup.sh    # Orchestrator: sources components 05–08
└── deploy_gitea.sh             # Deploys Gitea end-to-end: secret → manifests → admin user
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
├── namespaces.yaml             # Apply first: docs | apps | dev | mcp | ci | infra | prd | data
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
│   └── trycloudflare.yaml      # Quick tunnels manuais (docs/*, writing); CI usa .k8s/trycloudflare.yaml
├── prd/                        # Túneis nomeados Cloudflare — namespace: prd
│   └── cloudflared/            # (reservado para túnel global; per-app vai em .k8s/ de cada repo)
├── mcp/mempalace/              # StatefulSet + headless Service + local-path PVC (2Gi)
├── ci/
│   ├── arc/                    # Kept for reference (legacy GitHub Actions runner)
│   └── gitea-runner/           # Gitea act_runner — namespace: ci
│       ├── pvc.yaml            # 1Gi PVC para /data (config persiste restarts)
│       ├── secret.yaml         # Template: GITEA_RUNNER_REGISTRATION_TOKEN
│       └── deployment.yaml     # gitea/act_runner:latest + docker.sock mount
├── infra/cloudflared/          # Secrets de infra (tokens, credentials) — namespace: infra
├── templates/
│   ├── app/
│   │   ├── cloudflare-tunnel.yaml  # Template: túnel nomeado prd (copie para .k8s/ do app)
│   │   └── trycloudflare.yaml      # Template: túnel ephemeral dev (copie para .k8s/ do app)
│   └── docusaurus/             # Templates específicos para sites Docusaurus
└── data/                       # postgres | mongodb | redis | elasticsearch | kibana | pgadmin
```

All manifests include `namespace:` explicitly. All passwords and tokens are in `Secret` resources — files containing `<REPLACE_ME>` are templates and must be populated before applying.

### Apply order

```bash
kubectl apply -f deployments/namespaces.yaml
kubectl apply -f deployments/data/
kubectl apply -f deployments/mcp/mempalace/
kubectl apply -f deployments/docs/

# Gitea (cria secret, aplica manifestos e cria usuário admin em um comando):
bash scripts/deploy_gitea.sh

# Após Gitea estar up, registrar o runner:
# Token: Admin → Site Administration → Actions → Runners
kubectl create secret generic gitea-runner-secret --from-literal=GITEA_RUNNER_REGISTRATION_TOKEN=<token> -n ci
kubectl apply -f deployments/ci/gitea-runner/deployment.yaml

# Dev tunnels (opcional):
kubectl apply -f deployments/dev/trycloudflare.yaml
kubectl logs -n dev deployment/cloudflared-dev-docs-main | grep trycloudflare.com
kubectl delete -f deployments/dev/trycloudflare.yaml

# Writing editor — deploy via CI (DEPLOY_NAMESPACE=apps no Gitea).
# O PVC está em .k8s/pvc.yaml no repo do app e é aplicado junto com o deploy.
# Seed inicial dos arquivos .md (após o primeiro deploy):
#   kubectl cp ./writing/. apps/<pod>:/data/writing/
# Auth (opcional — sem secret o serviço sobe sem autenticação):
#   kubectl create secret generic writing-editor-secret \
#     --from-literal=AUTH_USER=usuario --from-literal=AUTH_PASS=senha -n apps
```

### Key design decisions in manifests

- **Docusaurus** — lives in namespace `docs`; served via `docusaurus serve` on port 3000 (no nginx needed). Traefik `IngressRoute` routes by hostname (`${APP_NAME}.homelab.local`). App manifests live in `.k8s/` inside each app repo — not here.
- **trycloudflare (dev)** — namespace `dev`; URL aleatória gerada no startup, muda a cada restart. Aplicado pelo CI na branch `develop` (APP_NAME com sufixo `-ephemeral`). URL exibida no log do job. Para testes manuais de serviços existentes, use `deployments/dev/trycloudflare.yaml`.
- **cloudflared nomeado (prd)** — namespace `prd`; túnel permanente com token. Um Deployment por app, Secret `cloudflare-tunnel-<APP_NAME>` no namespace `prd`. Rotas configuradas no Cloudflare Zero Trust dashboard. Template em `deployments/templates/app/cloudflare-tunnel.yaml`. Aplicado pelo CI apenas em `master`/`main`/tags.
- **Mempalace** — `StatefulSet` (not Deployment) so the PVC identity is preserved across restarts. Headless service gives stable DNS `mempalace-0.mempalace.mcp`. Backup: `kubectl cp mcp/mempalace-0:/data ./backup`.
- **Elasticsearch / Kibana** — heavy (1 GiB limit each); treat as optional on a 4 GB Pi. Requires `vm.max_map_count=262144` on the host.
- **Gitea** — namespace `apps`; SQLite backend (fully self-contained in 5Gi PVC). SSH git available via NodePort 30022. Container Registry built-in (Gitea Packages, OCI-compatible). `strategy: Recreate` prevents dual-pod PVC conflict.
  - **Backup automático**: `bash scripts/setup_backup_cron.sh` instala cron diário às 05:00 em `~/backups/gitea/`. Teste manual: `bash scripts/backup_gitea.sh`. Retenção configurável via `BACKUP_RETAIN_COUNT` em `config.sh` (padrão: 4 dias).
  - **Recuperação após reinstall do k3s**:
    ```bash
    sudo bash scripts/homelab_cluster_setup.sh && bash scripts/deploy_gitea.sh
    kubectl scale deployment gitea -n apps --replicas=0
    kubectl wait --for=delete pod -l app=gitea -n apps --timeout=60s
    kubectl scale deployment gitea -n apps --replicas=1
    kubectl wait --for=condition=ready pod -l app=gitea -n apps --timeout=120s
    BACKUP=$(ls -1dt ~/backups/gitea/[0-9]* | head -1)
    POD=$(kubectl get pod -n apps -l app=gitea -o name | cut -d/ -f2)
    kubectl cp "$BACKUP/." "apps/$POD:/data"
    kubectl rollout restart deployment/gitea -n apps
    ```
  - PVC contents: `/data/gitea/gitea.db` (DB), `/data/gitea/repositories/` (repos), `/data/gitea/packages/` (registry).
- **Gitea Runner** — `gitea/act_runner` in namespace `ci`. Registers automatically via `GITEA_RUNNER_REGISTRATION_TOKEN` env var. Config persists in 1Gi PVC. Mounts `/var/run/docker.sock`. Gitea Actions uses GitHub Actions YAML syntax.

---

## CI/CD Workflow

CI/CD é feito pelo Gitea Actions (`.gitea/workflows/*.yml` em cada repo), executado pelo `act_runner` no namespace `ci`. Sintaxe compatível com GitHub Actions.

Runner label: `homelab`. Use `runs-on: [homelab]` nos jobs.

O template canônico está em `workflows/github/build-and-deploy.yaml`. Copie para `.gitea/workflows/deploy.yml` no repo da aplicação e ajuste `PORT`.

**Padrão de deploy por branch:**

| Branch | Trigger | APP_NAME | NAMESPACE | Túnel |
|--------|---------|----------|-----------|-------|
| `master`/`main`/tag | push automático | `<repo>` | `DEPLOY_NAMESPACE` | nomeado em `prd` |
| `develop` | `workflow_dispatch` manual | `<repo>-ephemeral` | `dev` | trycloudflare (URL no log) |

**Para adicionar um novo app ao padrão:**
1. Copie `templates/app/cloudflare-tunnel.yaml` → `.k8s/cloudflare-tunnel.yaml` do repo
2. Copie `templates/app/trycloudflare.yaml` → `.k8s/trycloudflare.yaml` do repo (ajuste `${PORT}` no workflow)
3. Crie o Secret do túnel nomeado: `kubectl create secret generic cloudflare-tunnel-<app> --from-literal=token="<token>" -n prd`
4. Configure a rota no Cloudflare Zero Trust dashboard

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
| writing-editor | 64 MiB | 128 MiB |
| **Idle total** | **~1008 MiB** | — |

~2.7 GiB free for CI/CD job peaks and other workloads.
Elasticsearch + Kibana add up to 2 GiB of limits — deploy only if the Pi has 8 GB RAM.
