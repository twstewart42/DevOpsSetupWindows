#!/bin/bash
# shellcheck disable=SC2016,SC2034,SC1091
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
# root refusal
out="$(EUID_OVERRIDE=0 bash "$repo/wsl-setup.sh" 2>&1)"; rc=$?
check "refuses root"                 '[[ $rc -ne 0 ]]'
# credential helper skipped when path missing
GCM_DIR="$tmp/nope" set_credential_helper 2>/dev/null
check "no dead credential helper"    '[[ -z $(git config --global credential.helper) ]]'

exit $fails
