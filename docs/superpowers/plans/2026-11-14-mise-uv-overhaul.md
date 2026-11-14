# mise + uv WSL Setup Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the asdf/pipenv/scoop-based setup with a declarative `mise.toml` plus a single idempotent WSL bootstrap, with uv for Python and rootless podman for containers.

**Architecture:** `config/mise.toml` is the only place tool versions live. `wsl-setup.sh` (user-level, `sudo` only for apt) installs mise, links configs from `config/`, runs `mise install`, and wires shells idempotently. `windows-setup.ps1` shrinks to WSL + GUI bootstrap and then invokes the WSL script.

**Tech Stack:** bash, mise, uv, podman (Ubuntu 24.04 apt), PowerShell, winget, shellcheck (verification).

**Spec:** `docs/superpowers/specs/2026-11-14-mise-uv-overhaul-design.md`

## Global Constraints

- WSL distro is `Ubuntu-24.04`; WSL is the only home for DevOps CLIs (no scoop tool list on Windows).
- Tool versions live only in `config/mise.toml`; no versions in script logic.
- Container runtime is rootless podman from Ubuntu apt; `docker` is aliased to `podman`. No Docker Desktop, no Rancher Desktop.
- `wsl-setup.sh` refuses to run as root and uses `sudo` only for apt.
- Scripts are idempotent: re-running never duplicates shell lines or fails on already-installed things.
- One cowsay at the end only; no per-tool cowsay theming; oh-my-zsh dropped.
- Line endings handled by `.gitattributes` (`eol=lf` for `*.sh`, `*.toml`), not dos2unix.
- No chezmoi/Ansible/new frameworks.
- Files: `config/mise.toml`, `config/aliases.sh`, `config/starship.toml` (moved), `wsl-setup.sh` (replaces both old WSL scripts), `windows-setup.ps1`, `.vscode/extensions.json` (kept), `README.md` (rewritten).

## Review Focus

- Re-run on an already-configured machine: shell rc files must not gain duplicate lines (marker-guarded).
- Missing `~/.zshrc` (zsh not installed or never launched): script must not fail; create or skip cleanly.
- Run with no git name/email args and none configured: must skip git identity without writing empty values.
- Windows Git credential helper path absent (Git for Windows not at the default path): skip helper config, warn, don't set a dead path.
- `~/.config/mise/config.toml` already exists as a user's own file: back it up before linking, never silently destroy it.

---

### Task 1: Tool config (`config/mise.toml`, `config/aliases.sh`, `config/starship.toml`)

**Files:**
- Create: `config/mise.toml`, `config/aliases.sh`
- Move: `starship.toml` -> `config/starship.toml` (`git mv`)
- Modify: `.gitattributes` (add `*.sh text eol=lf`, `*.toml text eol=lf`)

**Interfaces:**
- Produces: `config/mise.toml` with a `[tools]` table; `config/aliases.sh` is POSIX-sh sourceable by bash and zsh and defines aliases `k kx g ga gb gbd gci gco gp gt docker` plus `export EDITOR=vim`. Consumed by Task 2.

- [ ] **Step 1: Verify registry names.** Run `mise registry` (install mise locally or in a throwaway Ubuntu 24.04 container) and confirm a backend exists for each: terraform, terraform-docs, tflint, tfsec, kubectl, kubectx, helm, awscli, go, dotnet, packer, saml2aws, k3sup, starship, direnv, uv, jq. Record any whose registry name differs from the tool name.
- [ ] **Step 2: Write `config/mise.toml`** with one `[tools]` entry per tool above; `latest` everywhere except `dotnet = "lts"` (3.1 is EOL, per spec). Keep alphabetical.
- [ ] **Step 3: Write `config/aliases.sh`** with the aliases above (fixing the old missing-`=` on `gci`/`gco`) and `alias docker=podman`.
- [ ] **Step 4: Move starship config and update `.gitattributes`.**
- [ ] **Step 5: Verify.** In a fresh `ubuntu:24.04` container: install mise, `cp config/mise.toml ~/.config/mise/config.toml`, run `mise install`. Expected: exit 0 and `mise ls` lists every tool as installed. Also `sh -n config/aliases.sh` exits 0.
- [ ] **Step 6: Commit** `feat: add declarative mise tool config and aliases`.

### Task 2: Unified WSL bootstrap (`wsl-setup.sh`)

**Files:**
- Rewrite: `wsl-setup.sh`
- Delete: `wsl-setup-sudo.sh`

**Interfaces:**
- Consumes: `config/mise.toml`, `config/aliases.sh`, `config/starship.toml` (Task 1).
- Produces: `wsl-setup.sh [git_name] [git_email]` run from the repo root as a normal user; exits 0 on success. Task 3 invokes it with exactly these two optional args.
- Internal helpers (signatures fixed so tests can source them): `add_once <file> <marker> <line>` appends `<line>` to `<file>` only if `<marker>` is absent (creates the file if missing); `link_config <src> <dest>` symlinks `<src>` to `<dest>`, moving an existing non-symlink `<dest>` to `<dest>.bak` first. Script must be sourceable without executing `main` (guard with `[[ "${BASH_SOURCE[0]}" == "$0" ]]`).

- [ ] **Step 1: Write failing tests** in `tests/wsl-setup.test.sh` (plain bash, sources the script, uses a temp `$HOME`): `add_once` called twice yields one line; `add_once` on a nonexistent file creates it; `link_config` with an existing regular file produces `dest.bak` and a symlink; running `main` with no args and no existing git config leaves `git config --global user.name` unset; root refusal (stub `EUID`) exits non-zero.
- [ ] **Step 2: Run** `bash tests/wsl-setup.test.sh`. Expected: FAIL (functions undefined).
- [ ] **Step 3: Implement `wsl-setup.sh`** with `set -euo pipefail` and steps in spec order: root refusal; `sudo apt-get install -y curl git gpg pass vim cowsay fortune-mod podman uidmap`; install mise via its official installer if `command -v mise` fails; `link_config` for mise.toml and starship.toml; `mise install`; `mise exec -- uv python install`; `add_once` for bash and zsh (mise activate, direnv hook, starship init with `STARSHIP_CONFIG`, `source <repo>/config/aliases.sh`) each with its own marker string; git identity only if args non-empty and config unset; credential helper only if the Git for Windows helper file exists under `/mnt/c/Program Files/Git/mingw64/libexec/git-core/`, otherwise print a warning; final `cowsay "All done"`.
- [ ] **Step 4: Run** `bash tests/wsl-setup.test.sh`. Expected: all PASS. Run `shellcheck wsl-setup.sh tests/wsl-setup.test.sh config/aliases.sh`. Expected: no errors.
- [ ] **Step 5: End-to-end in a container.** In a fresh `ubuntu:24.04` container with a non-root sudo user and the repo mounted, run `./wsl-setup.sh` twice. Expected: both exit 0; `grep -c "mise activate" ~/.bashrc` prints `1`; `terraform version`, `kubectl version --client`, `uv --version`, `podman --version` all succeed in a new `bash -lc`. (Credential-helper branch expected to warn; podman running a container is not expected inside the container.)
- [ ] **Step 6: Commit** `feat: replace asdf scripts with unified mise-based wsl-setup.sh`.

### Task 3: Windows bootstrap (`windows-setup.ps1`)

**Files:**
- Rewrite: `windows-setup.ps1`

**Interfaces:**
- Consumes: `wsl-setup.sh [git_name] [git_email]` (Task 2), `.vscode/extensions.json`.
- Produces: `windows-setup.ps1`, run from the repo root, user-level PowerShell.

- [ ] **Step 1: Rewrite** with these functions and nothing else: `Install-Wsl` (build >= 19041 check with message otherwise; `wsl --install -d Ubuntu-24.04` only when `wsl -l -q` does not list it; write `~\.wslconfig` with `memory=4GB`/`processors=2` only if absent, then `wsl --shutdown`); `Install-GuiApps` (`winget install --id Microsoft.VisualStudioCode`, `Microsoft.WindowsTerminal`, each skipped if `winget list --id` finds it); `Install-VscodeExtensions` (loop over `.vscode/extensions.json` recommendations, `code --install-extension $e`, skip if in `code --list-extensions`); `Set-GitIdentity` (`Read-Host` only when `git config --get user.name`/`user.email` is empty); final `wsl -d Ubuntu-24.04 bash wsl-setup.sh $name $email` with arguments passed only when non-empty. No dos2unix, no scoop, no cowsay dependency.
- [ ] **Step 2: Static review.** PowerShell cannot be run here: run `pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('windows-setup.ps1',[ref]\$null,[ref]\$e); \$e"` if `pwsh` is available (expected: no errors); otherwise read the file once for the fixed bugs (distro comparison, `$d` variable) and say in the commit/PR that it is unexecuted.
- [ ] **Step 3: Commit** `feat: slim windows-setup.ps1 to WSL and GUI bootstrap`.

### Task 4: README rewrite

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite** README: synopsis, prerequisites (Git for Windows), run instructions for `windows-setup.ps1`, and a short "Changing tool versions" section pointing at `config/mise.toml` with `mise install` / `mise upgrade`; a "Python with uv" snippet (`uv init`, `uv sync`); a "Containers" note (rootless podman, `docker` aliased). Remove all asdf, scoop, pipenv, Docker/Rancher Desktop mentions.
- [ ] **Step 2: Verify** `grep -riE "asdf|scoop|pipenv|rancher|20\.04" README.md windows-setup.ps1 wsl-setup.sh config/` returns nothing.
- [ ] **Step 3: Commit** `docs: rewrite README for mise/uv setup`.
