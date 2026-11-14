#!/bin/bash
# shellcheck disable=SC2016,SC2034,SC1091,SC2329,SC2086,SC2317
# Plain-bash tests for helpers in wsl-setup.sh. Run: bash tests/wsl-setup.test.sh
set -u
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"
# shellcheck source=../wsl-setup.sh
source "$repo/wsl-setup.sh"; set +e

# add_once: idempotent
add_once "$tmp/rc" "MARK" 'echo MARK hi'; add_once "$tmp/rc" "MARK" 'echo MARK hi'
check "add_once appends once"        '[[ $(grep -c MARK "$tmp/rc") == 1 ]]'
# add_once: creates missing file
check "add_once creates missing file" '[[ -f "$tmp/rc" ]]'
# link_config: backs up an existing regular file
echo mine > "$tmp/dest"; echo new > "$tmp/src"
link_config "$tmp/src" "$tmp/dest"
check "link_config backs up file"    '[[ $(cat "$tmp/dest.bak") == mine ]]'
check "link_config creates symlink"  '[[ -L "$tmp/dest" && $(cat "$tmp/dest") == new ]]'
link_config "$tmp/src" "$tmp/dest"
check "link_config idempotent"       '[[ -L "$tmp/dest" && $(cat "$tmp/dest.bak") == mine ]]'
# no git args + no config => identity untouched
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
set_git_identity "" ""
check "git identity skipped on empty" '[[ -z $(git config --global user.name) ]]'
set_git_identity "Ann" "a@x.io"
check "git identity set from args"   '[[ $(git config --global user.name) == Ann ]]'
# root refusal (function only, in a subshell: never runs the real installer)
( require_non_root 0 ) 2>/dev/null; rc=$?
check "refuses root"                 '[[ $rc -ne 0 ]]'
( require_non_root 1000 ); rc=$?
check "allows normal user"           '[[ $rc -eq 0 ]]'
# credential helper skipped when path missing
GIT_ROOT="$tmp/nope" set_credential_helper 2>/dev/null
check "no dead credential helper"    '[[ -z $(git config --global credential.helper) ]]'
# credential helper: current Git for Windows location, spaces escaped
GIT_ROOT="$tmp/Program Files/Git"; mkdir -p "$GIT_ROOT/mingw64/bin"
touch "$GIT_ROOT/mingw64/bin/git-credential-manager.exe"
set_credential_helper
check "helper found in mingw64/bin"  '[[ $(git config --global credential.helper) == *mingw64/bin/git-credential-manager.exe ]]'
check "helper spaces escaped"        '[[ $(git config --global credential.helper) == *"Program\ Files"* ]]'
unset GIT_ROOT

# install_config: repo inside WSL => symlink
REPO_DIR="$tmp/repo"; mkdir -p "$REPO_DIR"; echo v1 > "$REPO_DIR/a"
install_config "$REPO_DIR/a" "$tmp/linkdest"
check "linux repo => symlink"        '[[ -L "$tmp/linkdest" ]]'
# install_config: repo on Windows drive => copy, replacing an old symlink without backup
REPO_DIR="/mnt/c/fake"
install_config "$tmp/repo/a" "$tmp/linkdest"
check "/mnt repo => regular file"    '[[ -f "$tmp/linkdest" && ! -L "$tmp/linkdest" && $(cat "$tmp/linkdest") == v1 ]]'
check "symlink replaced w/o backup"  '[[ ! -e "$tmp/linkdest.bak" ]]'
# copy mode: differing user file backed up; identical rerun leaves backup alone
echo mine > "$tmp/cp"; install_config "$tmp/repo/a" "$tmp/cp"
check "copy backs up differing file" '[[ $(cat "$tmp/cp.bak") == mine && $(cat "$tmp/cp") == v1 ]]'
install_config "$tmp/repo/a" "$tmp/cp"
check "copy rerun keeps backup"      '[[ $(cat "$tmp/cp.bak") == mine ]]'
echo v2 > "$tmp/repo/a"; install_config "$tmp/repo/a" "$tmp/cp"
check "copy rerun picks up edits"    '[[ $(cat "$tmp/cp") == v2 && $(cat "$tmp/cp.bak") == mine ]]'

# connect_podman_desktop: stub podman/sudo/id and record calls
calls="$tmp/calls"; conns=""
podman() { echo "podman $*" >> "$calls"; [[ "$*" == "system connection list"* ]] && printf '%s\n' $conns; return 0; }
sudo() { echo "sudo $*" >> "$calls"; }
groupmembers=""
getent() { echo "uucp:x:10:$groupmembers"; }
export PODMAN_SOCKET_DIR="$tmp/sockets"; mkdir -p "$PODMAN_SOCKET_DIR"
mksock() { python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"; }

: > "$calls"; connect_podman_desktop >/dev/null 2>&1
check "podman: no socket => no changes"   '! grep -q "connection add" "$calls"'

: > "$calls"; touch "$PODMAN_SOCKET_DIR/podman-root.sock"; connect_podman_desktop >/dev/null 2>&1
check "podman: plain file is not a socket" '! grep -q "connection add" "$calls"'
rm "$PODMAN_SOCKET_DIR/podman-root.sock"; mksock "$PODMAN_SOCKET_DIR/podman-root.sock"; mksock "$PODMAN_SOCKET_DIR/podman-user.sock"
connect_podman_desktop >/dev/null
check "podman: rootful socket preferred"  'grep -qF "podman system connection add --default podman-machine-default-root unix://$PODMAN_SOCKET_DIR/podman-root.sock" "$calls"'
check "podman: added to gid 10"           'grep -qF "sudo usermod --append --groups 10" "$calls"'
: > "$calls"; groupmembers="other,$(whoami)"; connect_podman_desktop >/dev/null
check "podman: no re-add when in group"   '! grep -q usermod "$calls"'
groupmembers=""

: > "$calls"; rm "$PODMAN_SOCKET_DIR/podman-root.sock"; connect_podman_desktop >/dev/null
check "podman: rootless fallback"         'grep -qF "connection add --default podman-machine-default-user unix://$PODMAN_SOCKET_DIR/podman-user.sock" "$calls"'
check "podman: no group change rootless"  '! grep -q usermod "$calls"'

: > "$calls"; conns="podman-machine-default-user"; connect_podman_desktop >/dev/null
check "podman: existing connection kept"  '! grep -q "connection add" "$calls"'
unset -f podman sudo getent

# add_az_devops_extension: installs azure-devops extension once
azcalls="$tmp/azcalls"; have_ext=1
az() { echo "az $*" >> "$azcalls"; [[ "$1 $2" == "extension show" ]] && return $have_ext; return 0; }
: > "$azcalls"; add_az_devops_extension >/dev/null
check "az: adds azure-devops extension"   'grep -qF "az extension add --name azure-devops" "$azcalls"'
: > "$azcalls"; have_ext=0; add_az_devops_extension >/dev/null
check "az: skips when already installed"  '! grep -q "extension add" "$azcalls"'
unset -f az

# wire_shell: zsh activation is owned by `mise bootstrap`; bash keeps our line
wire_shell "$HOME/.zshrc" zsh; wire_shell "$HOME/.bashrc" bash
check "zsh: no hand-written mise activate" '! grep -q "mise activate" "$HOME/.zshrc"'
check "bash: mise activate line present"   'grep -q "mise activate bash" "$HOME/.bashrc"'
check "zsh: still wires starship"          'grep -q "starship init zsh" "$HOME/.zshrc"'
add_zsh_path; add_zsh_path
check "zshenv puts ~/.local/bin on PATH"   '[[ $(grep -c "\.local/bin" "$HOME/.zshenv") == 1 ]]'
check "no ~/.bash_profile created"         '[[ ! -e "$HOME/.bash_profile" ]]'

# install_git_ignore: global ignore at git's default XDG path, warn if overridden
REPO_DIR="$tmp/repo"; mkdir -p "$REPO_DIR/config"; echo "node_modules/" > "$REPO_DIR/config/gitignore_global"
: > "$GIT_CONFIG_GLOBAL"
out="$(install_git_ignore 2>&1)"
check "git ignore installed at XDG path"   '[[ $(cat "$HOME/.config/git/ignore") == "node_modules/" ]]'
check "git ignore: no warning by default"  '[[ -z "$out" ]]'
git config --global core.excludesFile "$tmp/other"
out="$(install_git_ignore 2>&1)"
check "git ignore: warns on excludesFile"  '[[ "$out" == *core.excludesFile* ]]'
check "real git honors the global ignore"  '(git config --global --unset core.excludesFile; cd "$tmp" && git init -q gi && mkdir -p gi/node_modules && touch gi/node_modules/x && cd gi && [[ -z $(git status --porcelain) ]])'

exit $fails
