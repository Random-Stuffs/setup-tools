#!/bin/bash

# =================================================================
# SCRIPT DE SETUP: PYTHON 3.11 + DOCKER + K3S + VENV
# =================================================================

set -e

echo "--- 1. Atualizando sistema e instalando dependências de compilação ---"
sudo apt update
sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev \
wget curl llvm libncursesw5-dev xz-utils tk-dev libxml2-dev \
libxmlsec1-dev liblzma-dev git python3-pip

echo "--- 2. Instalando Python 3.11.8 (Altinstall) ---"
cd /tmp
wget https://www.python.org/ftp/python/3.11.8/Python-3.11.8.tar.xz
tar -xf Python-3.11.8.tar.xz
cd Python-3.11.8
./configure --enable-optimizations
make -j$(nproc)
sudo make altinstall
sudo ln -sf /usr/local/bin/python3.11 /usr/local/bin/python311
sudo ln -sf /usr/local/bin/pip3.11 /usr/local/bin/pip311

echo "--- 3. Instalando Docker via script oficial ---"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

echo "--- 4. Instalando K3s com Runtime Docker ---"
curl -sfL https://get.k3s.io | sh -s - --docker
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config

echo "--- 5. Criando Ambiente Virtual (.venv) em ~/Documents/lab/ ---"
mkdir -p $HOME/Documents/lab
cd $HOME/Documents/lab
python311 -m venv .venv
echo "Venv criada com sucesso em $(pwd)/.venv"

echo "--- 6. Instalando Docker Compose no Ambiente Virtual (.venv) ---"

source .venv/bin/activate
sudo pip install docker-compose --break-system-packages --quiet

echo "--- 7. Instalando Helm e ARC (Actions Runner Controller) no k3s ---"

# 1. Garante que o Helm está instalado (caso não esteja no PATH)
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 2. Instala o Controller (O "Cérebro" que gerencia a escala)
helm install arc-controller oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
    --version 0.13.1 \
    --namespace github-runners \
    --create-namespace

# 3. Instala o Runner Set (O "Listener" que aguarda jobs para poupar CPU/RAM)
helm install homelab-runner oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
    --version 0.13.1 \
    --namespace github-runners \
    --create-namespace \
    --set githubConfigUrl="https://github.com/Random-Stuffs" \
    --set githubConfigSecret.github_token="token"  # Substitua 'token' pela sua chave PAT válida com escopo admin:org

echo "ARC instalado com sucesso! Verificando pods em 5 segundos..."
sleep 5
kubectl get pods -n github-runners

echo "================================================================="
echo " SETUP COMPLETO! "
echo "================================================================="
echo "IMPORTANTE: Reinicie para aplicar as permissões de grupo:"
echo "sudo reboot"
echo ""
echo "Para ativar seu ambiente lab: source ~/Documents/lab/.venv/bin/activate"
echo "================================================================="
