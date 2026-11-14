# Design: Modernize WSL DevOps setup with mise + uv

Date: 2026-11-14 · Status: awaiting approval

## Intent
Tool versions should live in one declarative file, separate from install
mechanics. Bumping a version is a one-line diff; teammates can re-run
`mise install` without re-running the whole setup. Remove legacy code written
for asdf/pipenv/Ubuntu 20.04 and anything already broken.

## Goals
- `config/mise.toml` is the single source of truth for CLI tool versions.
- uv replaces pip/pipenv for Python (interpreter + project envs).
- WSL (Ubuntu 24.04) is the only home for DevOps tooling.
- Podman is the container runtime: Podman + Podman Desktop on Windows (winget) run a rootful
  `podman-machine-default`; Ubuntu's apt podman CLI connects to that machine's socket under
  `/mnt/wsl/podman-sockets/` (falls back to local podman if absent). `docker` aliased to podman.
  (Revised 2026-11-14 at user request.)
- Scripts are idempotent and much shorter than today (~590 lines -> well under half).

## Non-goals / anti-goals
- No Windows-native installs of DevOps CLIs (scoop tool list removed).
- No Docker Desktop or Rancher Desktop.
- No chezmoi/Ansible; no new framework for teammates to learn.
- Don't hide versions inside script logic again.

## Approaches considered
- **A. mise.toml + single bootstrap script (chosen).**
- B. chezmoi/Ansible: too heavy for ~15 tools.
- C. Swap asdf for mise inline in both scripts: leaves versions tangled in code.

## Design

### Layout
```
config/mise.toml       tool versions (terraform, kubectl, helm, awscli, go, dotnet,
                       packer, saml2aws, tflint, terraform-docs, tfsec, k3sup,
                       kubectx, starship, direnv, uv, jq ...)
config/aliases.sh      sourced by shells; fixed aliases (k, kx, g, ga, ..., docker=podman)
config/starship.toml   moved from repo root
wsl-setup.sh           single bootstrap (replaces wsl-setup.sh + wsl-setup-sudo.sh)
windows-setup.ps1      WSL + GUI bootstrap only
.vscode/extensions.json  kept
README.md              rewritten
```

### wsl-setup.sh (runs as normal user, uses sudo only for apt)
1. Refuse to run as root.
2. `sudo apt install`: curl git gpg pass vim cowsay fortune-mod podman uidmap (and
   build basics mise plugins may need).
3. Install mise via official installer if absent.
4. Link `config/mise.toml` to `~/.config/mise/config.toml`; link starship config.
5. `mise install` (idempotent). uv is installed via mise; `uv python install` for a
   default interpreter.
6. Shell wiring, each guarded by a marker so reruns don't duplicate: mise activate,
   direnv hook, starship init, source `config/aliases.sh`, for bash and zsh.
7. Git config: user.name/email from args if unset; Windows credential-manager helper
   (path checked for existence, current Git for Windows location).
8. One cowsay at the end.

### windows-setup.ps1
Check Windows build supports WSL2; `wsl --install -d Ubuntu-24.04` if missing
(fixing the always-false comparison); write `.wslconfig` if absent; `winget install`
for Git (prereq check), VS Code, Windows Terminal; install VS Code extensions from
`.vscode/extensions.json` (fixing the `$d` bug); prompt for git name/email; run
`wsl-setup.sh` (line endings handled via `.gitattributes` `eol=lf` instead of dos2unix).

### Deleted
asdf code, per-tool cowsay theming, `github_latest_install`/`download_install`,
scoop tool list, pipenv, podman kubic-repo + libpod.conf seds, oh-my-zsh
(unless requested), the broken alias lines.

## Builder's calls (marked as my decisions, not yours)
- Ubuntu 24.04; merged sudo/non-sudo scripts; single cowsay; oh-my-zsh dropped.
- Configs are symlinked when the repo is inside WSL, copied when it is on `/mnt/*` (user chose).
- Pin only where an old pin was deliberate (dotnet 3.1 is EOL: use a current LTS
  unless told otherwise); `latest` elsewhere.
- Verification: `shellcheck` on scripts, and a run in a fresh Ubuntu 24.04
  container (podman/docker) where feasible; PowerShell can't be run here, only reviewed.

## Left to the builder
Exact mise registry names per tool (verify with `mise registry`), alias contents,
README wording.
