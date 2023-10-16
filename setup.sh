# TOOLS
apt update -y
apt install -y git vim curl

# INSTALLING CHROME (test)
apt install -y libxss1 libappindicator1 libindicator7
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt install -y ./google-chrome*.deb
rm ./google-chrome*.deb

# INSTALLING VSCODE
wget "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
dpkg -i install 'download?build=stable&os=linux-deb-x64'
rm "download?build=stable&os=linux-deb-x64"

# INSTALLING OH-MY-ZSH
apt install -y zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# INSTALLING DOCKER


# INSTALLING KUBECTL

# INSTALLING ONION


# INSTALLING MY-TOOLS
## Raspberry Pi Burros Server Startup
## Joe App Infrastructure

# OTHER SETUPS

apt upgrade -y
