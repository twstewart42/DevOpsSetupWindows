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

sudo apt -y update
sudo apt -y upgrade
sudo apt install -qq -y vim pass gpg
sudo apt install -qq -y curl git jq cowsay fortune
sudo apt install -qq -y python3-pip 
if [ ! -f "/usr/local/bin/pipenv" ]; then
	pip3 install -U pip
	pip3 install -U pipenv
fi

#use podman as docker cli replacement
if [[ -z $(which podman) ]]; then
	. /etc/os-release
	sudo sh -c "echo 'deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/x${NAME}_${VERSION_ID}/ /' > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list"
	wget -nv https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/x${NAME}_${VERSION_ID}/Release.key -O Release.key
	sudo apt-key add - < Release.key
	sudo apt-get update -qq
	sudo apt-get -qq -y install podman
	sudo mkdir -p /etc/containers
	echo -e "[registries.search]\nregistries = ['docker.io', 'quay.io']" | sudo tee /etc/containers/registries.conf
	sudo cp /usr/share/containers/libpod.conf /etc/container
	podman info
	sed -i 's/cgroup_manager = "systemd"/cgroup_manager = "cgroupfs"/g' /etc/container/libpod.conf
	sed -i 's/# events_logger = "journald"/events_logger = "file/g' /etc/container/libpod.conf
fi