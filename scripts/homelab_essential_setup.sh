#!/bin/bash

# =================================================================
# RASPBERRY PI OS - ULTIMATE INITIAL SETUP SCRIPT
# Instala: Python 3.6, 3.8, 3.11 | Node.js (NVM) | Docker
# =================================================================

set -e

echo "--- 1. Atualizando Sistema e Instalando Dependências de Compilação ---"
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
sudo apt install -y \
  portaudio19-dev \
  python3-pyaudio \
  python3-dev \
  build-essential \
  libasound2-dev \
  flac \
  mpg123
libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev \
wget curl llvm libncursesw5-dev xz-utils tk-dev libxml2-dev \
libxmlsec1-dev liblzma-dev git

# Função para instalar Python via código-fonte (Segurança para coexistência)
install_python() {
    VERSION=$1
    FULL_VER=$2
    echo "--- Instalando Python $FULL_VER ---"
    cd /tmp
    wget "https://www.python.org/ftp/python/$FULL_VER/Python-$FULL_VER.tar.xz"
    tar -xf "Python-$FULL_VER.tar.xz"
    cd "Python-$FULL_VER"
    ./configure --enable-optimizations
    make -j$(nproc)
    sudo make altinstall
    # Cria atalho como python36, python38, python311
    sudo ln -sf "/usr/local/bin/python$VERSION" "/usr/local/bin/python${VERSION//./}"
}

# --- 2. Instalando Versões do Python ---
install_python "3.6" "3.6.15"
install_python "3.8" "3.8.18"
install_python "3.11" "3.11.8"

echo "--- 3. Instalando NVM e Node.js (LTS) ---"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
# Carregar NVM para a sessão atual do script
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts

echo "--- 4. Instalando Docker e Configurações Essenciais ---"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Configurar logs do Docker para não encher o cartão SD (Essencial em Pi)
sudo mkdir -p /etc/docker
echo '{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

echo "--- 5. Criando Ambiente Virtual (.venv) em ~/Documents/lab/ ---"
mkdir -p $HOME/Documents/lab
cd $HOME/Documents/lab
python311 -m venv .venv
echo "Venv criada com sucesso em $(pwd)/.venv"

echo "--- 6. Instalando Docker Compose no Ambiente Virtual (.venv) ---"

source .venv/bin/activate
sudo pip install docker-compose --break-system-packages --quiet

echo "================================================================="
echo " SETUP FINALIZADO COM SUCESSO! "
echo "================================================================="
echo "Comandos disponíveis agora:"
echo " - python36, python38, python311"
echo " - node, npm, nvm"
echo " - docker, docker-compose"
echo ""
echo "POR FAVOR, REINICIE O RASPBERRY PI: sudo reboot"
echo "================================================================="
