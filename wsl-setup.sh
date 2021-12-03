#!/bin/bash
#############################################################################
# PROGRAM - wsl-setup.sh
# SYNOPSIS - Install and Setup DevOps Utilities that I routinely need on WSL/Ubuntu Linux based development platform
# NOTES - This Script Assumes that you have installed WSL and setup a UNIX user account on WSL
#       - DO NOT RUN AS SUDO, Script must run within your user profile to work correctly
#############################################################################
if [ "$EUID" -eq 0 ]
  then echo "DO NOT run script as root/sudo" | /usr/games/cowsay -f ren
  exit
fi

git_username=$1
git_email=$2
if [[ -z $(git config --get user.name) ]]; then
	git config --global user.name $git_username
fi
if [[ -z $(git config --get user.email) ]]; then
	git config --global user.email $git_email
fi

# ASDF Install to bash
if [[ -z $(asdf version) && ! -f "$HOME/.asdf/asdf.sh" ]]; then
	echo "install and config ASDF"
	git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.1
	echo ". $HOME/.asdf/asdf.sh" | tee -a $HOME/.bashrc
	echo ". $HOME/.asdf/asdf.sh" | tee -a $HOME/.zshrc
	echo ". $HOME/.asdf/completions/asdf.bash" | tee -a $HOME/.bashrc
	source $HOME/.asdf/asdf.sh
	source $HOME/.asdf/completions/asdf.bash
else
	# need to load asdf into local session ENV or things don't work running this script from Windows passing into WSL
	echo "ASDF already installed"
	source $HOME/.asdf/asdf.sh
	source $HOME/.asdf/completions/asdf.bash
	asdf version
fi

#direnv Install to bash 
if [[ -z $(direnv --version) ]]; then
	echo "Install and config direnv"
	asdf plugin add direnv
	asdf install direnv latest
	asdf global direnv latest
	#https://github.com/direnv/direnv/blob/master/docs/installation.md
	#apt install -y direnv
	#https://github.com/direnv/direnv/blob/master/docs/hook.md 
	echo 'eval "$(asdf exec direnv hook bash)"' | tee -a $HOME/.bashrc
	echo 'eval "$(asdf exec direnv hook zsh)"' | tee -a $HOME/.zshrc
else
	echo "direnv already installed"
fi

#WSL GIT config
if [[ -z $(git config --get credential.helper) ]]; then 
	git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/libexec/git-core/git-credential-manager-core.exe"
	git config --global credential.https://dev.azure.com.useHttpPath true
fi

# main installer block for asdf-vm plugins
# See what is supported here: https://github.com/asdf-vm/asdf-plugins/tree/master/plugins
asdf_install() {
	# $1 == asdf plugin names
	# $2 == asdf plugin version
	# $3 == cowsay graphic
	# $4 == alt binary name*
	# *Some packages have different names than the binary we need to 
	# verify to see if the utility is not already installed
	# golang vs go, dotnet-core vs dotnet
	if [[ -z $4 ]]; then
		util=$1
	else
		util=$4
	fi
	if [[ -z $(which $util) ]]; then
		asdf plugin add $1
		asdf install $1 $2
		full_version=$(asdf list $1 | sort -r | head -n 1)
		asdf global $1 $full_version
		echo "${1} install complete" | cowsay -f $3
	else
		echo "${1} already installed and in path" | cowsay -f $3
	fi
}

#For AWS CLI we want to ensure everyone has the newer v2 cli
if [[ -z $(which aws) && ! -z $(aws --version | grep -v aws-cli/2) ]]; then
	asdf plugin add awscli
	asdf install awscli latest:2
	asdf global awscli latest
	echo "awscli install complete" | cowsay -f duck
else
	echo "awscli already installed and in path" | cowsay -f duck
fi

# Keep in Alphabetical Order Please
asdf_install dotnet-core latest:3.1 tux dotnet
asdf_install golang latest ghostbusters go
asdf_install helm latest turkey
asdf_install kubectl latest flaming-sheep
asdf_install kubectx latest hellokitty
asdf_install k3sup latest bunny
asdf_install packer 1.5.1 kosh
asdf_install saml2aws latest kangaroo
asdf_install starship latest vader
asdf_install terraform latest bud-frogs
asdf_install terraform-docs 0.15.0 www
asdf_install tflint 0.21.0 turtle
asdf_install tfsec 0.58.9 stimpy

#podman rootless config
if [[ ! -f $HOME/.config/containers/libpod.conf ]]; then
	podman info
	sed -i 's/cgroup_manager = "systemd"/cgroup_manager = "cgroupfs"/g' $HOME/.config/containers/libpod.conf
	sed -i 's/# events_logger = "journald"/events_logger = "file/g' $HOME/.config/containers/libpod.conf
fi

# Configure Shells for a beautiful CLI experience
# https://starship.rs/
if [[ -z $(grep starship $HOME/.bashrc) ]]; then
	echo "export STARSHIP_CONFIG=~/.config/starship.toml" | tee -a $HOME/.zshrc
	echo 'eval "$(starship init bash)"' | tee -a $HOME/.bashrc
fi
if [[ -z $(grep starship $HOME/.zshrc) ]]; then
	echo "export STARSHIP_CONFIG=~/.config/starship.toml" | tee -a $HOME/.zshrc
	echo 'eval "$(starship init zsh)"' | tee -a $HOME/.zshrc
	if [[ ! -d $HOME/.oh-my-zsh/ ]]; then
		echo "installing ohmyzsh"
		sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	fi
	echo "Adding the following to .zshrc:"
	cat <<EOF >> $HOME/.zshrc
plugins=(git asdf helm kubectl kubectx aws aliases battery gnu-utils history man python pylint pyenv terraform ubuntu)
eval "$(saml2aws --completion-script-zsh)"
export EDITOR="vim"
alias fdate="sudo ntpdate pool.ntp.org"
alias k="kubectl"
alias kx="kubectx"
alias g="git"
alias ga="git add"
alias gb="git branch"
alias gbd="git branch -D"
alias gci"git commit"
alias gco"git checkout"
alias gp="git push"
alias gt="git tag"
alias docker="podman"
EOF
fi
if [[ ! -f $HOME/.config/starship.toml ]]; then
	cp ./starship.toml $HOME/.config/starship.toml
fi


echo "All done" | cowsay