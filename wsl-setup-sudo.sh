#!/bin/bash
#############################################################################
# PROGRAM - wsl-setup-sudo.sh
# SYNOPSIS - Install and Setup DevOps Utilities that I routinely need on WSL/Ubuntu Linux based development platform
# NOTES - This Script Assumes that you have installed WSL and setup your user account and  can run as SUDO/Root
#
#############################################################################

if [ "$EUID" != 0 ]; then 
	echo "Run scipt as root/sudo"
	exit
fi

sudo apt-get -y update
sudo apt-get -y upgrade
sudo apt-get install -qq -y vim pass gpg
sudo apt-get install -qq -y curl git jq cowsay fortune
sudo apt-get install -qq -y python3-pip 

# flux install
# curl -s https://fluxcd.io/install.sh | sudo bash
if [ ! -f "/usr/local/bin/flux" ]; then
	curl -s https://toolkit.fluxcd.io/install.sh | sudo bash
fi

# eksctl Install
if [[ -z $(which eksctl) ]]; then
	ARCH=amd64
	PLATFORM=$(uname -s)_$ARCH
	curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
	tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
	sudo mv /tmp/eksctl /usr/local/bin
	sudo chmod +x /usr/local/bin/eksctl
else
	echo "eksctl already installed and in path"
fi

# just use rancher-desktop with docker api support for reducded complexity
# #use podman as docker cli replacement
# if [[ -z $(which podman) ]]; then
# 	. /etc/os-release
# 	sudo sh -c "echo 'deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/x${NAME}_${VERSION_ID}/ /' > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list"
# 	wget -nv https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/x${NAME}_${VERSION_ID}/Release.key -O Release.key
# 	sudo apt-key add - < Release.key
# 	sudo apt-get update -qq
# 	sudo apt-get -qq -y install podman
# 	sudo mkdir -p /etc/containers
# 	echo -e "[registries.search]\nregistries = ['docker.io', 'quay.io']" | sudo tee /etc/containers/registries.conf
# 	sudo cp /usr/share/containers/libpod.conf /etc/container
# 	podman info
# 	sed -i 's/cgroup_manager = "systemd"/cgroup_manager = "cgroupfs"/g' /etc/container/libpod.conf
# 	sed -i 's/# events_logger = "journald"/events_logger = "file/g' /etc/container/libpod.conf
# fi
