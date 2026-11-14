#!/bin/bash
#############################################################################
# wsl-setup.sh [git_name] [git_email]
# Bootstraps a DevOps toolchain on WSL/Ubuntu 24.04 using mise (CLI tools),
# uv (python) and rootless podman (containers).
# Run as your normal user from the repo root. sudo is used only for apt.
# Tool versions live in config/mise.toml. Safe to re-run.
#############################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT_DEFAULT="/mnt/c/Program Files/Git"
DEVOPS_CONFIG_DIR="$HOME/.config/devops"

# require_non_root <euid>: abort when running as root.
require_non_root() {
	if [[ "$1" -eq 0 ]]; then
		echo "DO NOT run as root/sudo; the script uses sudo itself where needed" >&2
		exit 1
	fi
}

# add_once <file> <marker> <line>: append line unless marker already in file.
add_once() {
	local file=$1 marker=$2 line=$3
	touch "$file"
	grep -qF -- "$marker" "$file" || printf '%s\n' "$line" >> "$file"
}

# link_config <src> <dest>: symlink src to dest, backing up a real dest file.
link_config() {
	local src=$1 dest=$2
	mkdir -p "$(dirname "$dest")"
	if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then return 0; fi
	if [[ -e "$dest" || -L "$dest" ]]; then mv "$dest" "$dest.bak"; fi
	ln -s "$src" "$dest"
}

# copy_config <src> <dest>: copy src over dest; back up a differing user file.
copy_config() {
	local src=$1 dest=$2
	mkdir -p "$(dirname "$dest")"
	if [[ -L "$dest" ]]; then rm "$dest"
	elif [[ -f "$dest" ]] && ! cmp -s "$src" "$dest" && [[ ! -e "$dest.bak" ]]; then
		mv "$dest" "$dest.bak"
	fi
	cp "$src" "$dest"
}

# install_config <src> <dest>: symlink when the repo lives inside WSL; copy
# when it lives on the Windows drive (/mnt/*) so shells don't depend on the
# Windows clone. Re-run wsl-setup.sh after editing config/ in that case.
install_config() {
	if [[ "$REPO_DIR" == /mnt/* ]]; then copy_config "$1" "$2"; else link_config "$1" "$2"; fi
}

# set_git_identity <name> <email>: only fills in what is empty and given.
set_git_identity() {
	local name=${1:-} email=${2:-}
	if [[ -n "$name" && -z "$(git config --global --get user.name || true)" ]]; then
		git config --global user.name "$name"
	fi
	if [[ -n "$email" && -z "$(git config --global --get user.email || true)" ]]; then
		git config --global user.email "$email"
	fi
	git config --global alias.co checkout
	git config --global alias.ci commit
	git config --global alias.st status
	git config --global alias.ad add
	git config --global alias.br branch
	git config --global alias.pl pull
	git config --global alias.pu push
	git config --global alias.unstage reset HEAD --
	git config --global --add --bool push.autoSetupRemote true
}

# Use the Windows Git credential manager (works with enterprise SSO).
set_credential_helper() {
	local root=${GIT_ROOT:-$GIT_ROOT_DEFAULT} helper="" c
	for c in "$root/mingw64/bin/git-credential-manager.exe" \
		"$root/mingw64/libexec/git-core/git-credential-manager.exe" \
		"$root/mingw64/libexec/git-core/git-credential-manager-core.exe"; do
		if [[ -f "$c" ]]; then helper=$c; break; fi
	done
	if [[ -z "$helper" ]]; then
		echo "WARN: Git for Windows credential manager not found under $root; skipping" >&2
		return 0
	fi
	if [[ -z "$(git config --global --get credential.helper || true)" ]]; then
		# git runs the helper through a shell, so spaces must be escaped
		git config --global credential.helper "${helper// /\\ }"
		git config --global credential.https://dev.azure.com.useHttpPath true
	fi
}

# Point this distro's podman CLI at Podman Desktop's machine so containers
# show up in the GUI. Prefers the rootful socket (Podman Desktop's default).
connect_podman_desktop() {
	local dir=${PODMAN_SOCKET_DIR:-/mnt/wsl/podman-sockets/podman-machine-default}
	local name sock
	if [[ -S "$dir/podman-root.sock" ]]; then
		name=podman-machine-default-root sock="$dir/podman-root.sock"
		# the rootful socket is writable by gid 10 (uucp on Ubuntu)
		# check the group database, not id -G: a fresh add only shows in new sessions
		if ! getent group 10 | cut -d: -f4 | tr ',' '\n' | grep -qx "$(whoami)"; then
			sudo usermod --append --groups 10 "$(whoami)"
			echo "NOTE: added $(whoami) to group 10; open a new WSL session for it to apply"
		fi
	elif [[ -S "$dir/podman-user.sock" ]]; then
		name=podman-machine-default-user sock="$dir/podman-user.sock"
	else
		echo "NOTE: Podman Desktop machine not found at $dir. Create/start it in" \
			"Podman Desktop, then re-run wsl-setup.sh to connect. Using local podman for now."
		return 0
	fi
	if ! podman system connection list --format '{{.Name}}' | grep -qx "$name"; then
		podman system connection add --default "$name" "unix://$sock"
	fi
}

# Azure DevOps commands (az repos/boards/pipelines) ship as an az extension.
add_az_devops_extension() {
	if ! az extension show --name azure-devops >/dev/null 2>&1; then
		az extension add --name azure-devops --only-show-errors
	fi
}

# zsh never reads ~/.profile, so put the mise install dir on PATH for every zsh
# (the `mise bootstrap` activation blocks call `mise` by name).
add_zsh_path() {
	# shellcheck disable=SC2016 # expand at shell startup, not now
	add_once "$HOME/.zshenv" ".local/bin" 'export PATH="$HOME/.local/bin:$PATH"'
}

# zsh: mise activation is managed by `mise bootstrap` ([bootstrap.mise_shell_activate]
# in config/mise.toml). bash: our own line, because bootstrap's bash mode creates
# ~/.bash_profile, which makes Ubuntu login shells skip ~/.profile and ~/.bashrc.
# Global gitignore at git's default XDG path (no config needed). A custom
# core.excludesFile overrides that path, so warn instead of silently doing nothing.
install_git_ignore() {
	install_config "$REPO_DIR/config/gitignore_global" "$HOME/.config/git/ignore"
	local custom
	custom="$(git config --global --get core.excludesFile || true)"
	if [[ -n "$custom" ]]; then
		echo "WARN: core.excludesFile=$custom overrides ~/.config/git/ignore; merge it or unset it" >&2
	fi
}

wire_shell() {
	local rc=$1 shell=$2
	if [[ "$shell" == bash ]]; then
		add_once "$rc" "mise activate" "eval \"\$(\$HOME/.local/bin/mise activate bash)\""
	fi
	add_once "$rc" "direnv hook" "eval \"\$(direnv hook $shell)\""
	add_once "$rc" "STARSHIP_CONFIG" "export STARSHIP_CONFIG=\$HOME/.config/starship.toml"
	add_once "$rc" "starship init" "eval \"\$(starship init $shell)\""
	add_once "$rc" "devops/aliases.sh" "[ -f \"\$HOME/.config/devops/aliases.sh\" ] && . \"\$HOME/.config/devops/aliases.sh\""
}

main() {
	require_non_root "$EUID"

	sudo apt-get update -qq
	sudo apt-get install -y -qq curl git gpg pass vim cowsay fortune-mod podman uidmap

	if ! command -v mise >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/mise" ]]; then
		curl -fsSL https://mise.run | sh
	fi
	export PATH="$HOME/.local/bin:$PATH"

	install_config "$REPO_DIR/config/mise.toml" "$HOME/.config/mise/config.toml"
	install_config "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"
	install_config "$REPO_DIR/config/aliases.sh" "$DEVOPS_CONFIG_DIR/aliases.sh"
	install_git_ignore
	mise install --yes
	eval "$(mise env -s bash)" # put mise-managed tools on PATH for the rest of this script
	uv python install
	add_az_devops_extension

	wire_shell "$HOME/.bashrc" bash
	add_zsh_path
	mise bootstrap --only mise-shell-activate --yes # writes the activate block before ours
	wire_shell "$HOME/.zshrc" zsh

	set_git_identity "${1:-}" "${2:-}"
	set_credential_helper
	connect_podman_desktop

	/usr/games/cowsay "All done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
