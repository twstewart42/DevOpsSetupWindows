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
GCM_DIR="${GCM_DIR:-/mnt/c/Program Files/Git/mingw64/libexec/git-core}"

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

# set_git_identity <name> <email>: only fills in what is empty and given.
set_git_identity() {
	local name=${1:-} email=${2:-}
	if [[ -n "$name" && -z "$(git config --global --get user.name || true)" ]]; then
		git config --global user.name "$name"
	fi
	if [[ -n "$email" && -z "$(git config --global --get user.email || true)" ]]; then
		git config --global user.email "$email"
	fi
}

# Use the Windows Git credential manager (works with enterprise SSO).
set_credential_helper() {
	local helper="$GCM_DIR/git-credential-manager.exe"
	[[ -f "$helper" ]] || helper="$GCM_DIR/git-credential-manager-core.exe"
	if [[ ! -f "$helper" ]]; then
		echo "WARN: Git for Windows credential manager not found in $GCM_DIR; skipping" >&2
		return 0
	fi
	if [[ -z "$(git config --global --get credential.helper || true)" ]]; then
		git config --global credential.helper "$helper"
		git config --global credential.https://dev.azure.com.useHttpPath true
	fi
}

wire_shell() {
	local rc=$1 shell=$2
	add_once "$rc" "mise activate" "eval \"\$(\$HOME/.local/bin/mise activate $shell)\""
	add_once "$rc" "direnv hook" "eval \"\$(direnv hook $shell)\""
	add_once "$rc" "STARSHIP_CONFIG" "export STARSHIP_CONFIG=\$HOME/.config/starship.toml"
	add_once "$rc" "starship init" "eval \"\$(starship init $shell)\""
	add_once "$rc" "config/aliases.sh" ". \"$REPO_DIR/config/aliases.sh\""
}

main() {
	if [[ "${EUID_OVERRIDE:-$EUID}" -eq 0 ]]; then
		echo "DO NOT run as root/sudo; the script uses sudo itself where needed" >&2
		exit 1
	fi

	sudo apt-get update -qq
	sudo apt-get install -y -qq curl git gpg pass vim cowsay fortune-mod podman uidmap

	if ! command -v mise >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/mise" ]]; then
		curl -fsSL https://mise.run | sh
	fi
	export PATH="$HOME/.local/bin:$PATH"

	link_config "$REPO_DIR/config/mise.toml" "$HOME/.config/mise/config.toml"
	link_config "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"
	mise install --yes
	mise exec -- uv python install

	wire_shell "$HOME/.bashrc" bash
	wire_shell "$HOME/.zshrc" zsh

	set_git_identity "${1:-}" "${2:-}"
	set_credential_helper

	/usr/games/cowsay "All done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
