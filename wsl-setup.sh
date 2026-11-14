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

# require_non_root [euid]: abort when running as root.
require_non_root() {
	if [[ "${1:-$EUID}" -eq 0 ]]; then
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

wire_shell() {
	local rc=$1 shell=$2
	add_once "$rc" "mise activate" "eval \"\$(\$HOME/.local/bin/mise activate $shell)\""
	add_once "$rc" "direnv hook" "eval \"\$(direnv hook $shell)\""
	add_once "$rc" "STARSHIP_CONFIG" "export STARSHIP_CONFIG=\$HOME/.config/starship.toml"
	add_once "$rc" "starship init" "eval \"\$(starship init $shell)\""
	add_once "$rc" "devops/aliases.sh" "[ -f \"\$HOME/.config/devops/aliases.sh\" ] && . \"\$HOME/.config/devops/aliases.sh\""
}

main() {
	require_non_root

	sudo apt-get update -qq
	sudo apt-get install -y -qq curl git gpg pass vim cowsay fortune-mod podman uidmap

	if ! command -v mise >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/mise" ]]; then
		curl -fsSL https://mise.run | sh
	fi
	export PATH="$HOME/.local/bin:$PATH"

	install_config "$REPO_DIR/config/mise.toml" "$HOME/.config/mise/config.toml"
	install_config "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"
	install_config "$REPO_DIR/config/aliases.sh" "$DEVOPS_CONFIG_DIR/aliases.sh"
	mise install --yes
	mise exec -- uv python install

	wire_shell "$HOME/.bashrc" bash
	wire_shell "$HOME/.zshrc" zsh

	set_git_identity "${1:-}" "${2:-}"
	set_credential_helper

	/usr/games/cowsay "All done"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
