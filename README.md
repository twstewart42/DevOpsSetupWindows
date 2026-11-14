# SYNOPSIS
Set up a Windows + WSL2 DevOps workstation in minutes, with a little help from Cowsay.

Tooling lives **only inside WSL (Ubuntu 24.04)**. Tool versions are declared in one file, [`config/mise.toml`](config/mise.toml), managed by [mise](https://mise.jdx.dev/). Python uses [uv](https://docs.astral.sh/uv/), containers use rootless [podman](https://podman.io/).

# Prerequisite
1. Install [Git for Windows](https://gitforwindows.org/)
2. Clone this repo

# Run
From the repo root in a user-level PowerShell:
```pwsh
PS> .\windows-setup.ps1
```
This installs WSL2 + Ubuntu 24.04, VS Code (with recommended extensions) and Windows Terminal via winget, then runs `wsl-setup.sh` inside WSL. Re-running is safe.

On a machine without WSL, the first run installs it and stops: reboot if prompted, launch Ubuntu 24.04 once to create your Linux user, then run `.\windows-setup.ps1` again.

Inside an existing WSL Ubuntu you can run just `./wsl-setup.sh [git_name] [git_email]` as your normal user.

# Changing tool versions
Edit `config/mise.toml`, then:
```sh
mise install     # apply pinned versions
mise upgrade     # bump anything set to "latest"
```
If the repo is cloned inside WSL, `config/` files are symlinked into `~/.config`, so edits apply immediately.
If it lives on the Windows drive (`/mnt/c/...`), they are copied instead; re-run `./wsl-setup.sh` after editing them.

# Python with uv
```sh
uv init myproj && cd myproj
uv add requests
uv sync          # create/refresh .venv
uv run python main.py
```

# Containers
`windows-setup.ps1` installs Podman and [Podman Desktop](https://podman-desktop.io/) via winget, then creates and
starts a rootful Podman machine (`podman-machine-default`). `wsl-setup.sh` points Ubuntu's `podman` CLI at that
machine (`/mnt/wsl/podman-sockets/podman-machine-default/`), so containers you run from WSL show up in Podman Desktop.
If the machine isn't running when `wsl-setup.sh` runs, Ubuntu falls back to its own local podman; start the machine
and re-run `./wsl-setup.sh` to connect. `docker` is aliased to `podman` (see `config/aliases.sh`).

If the machine is rootful (Podman Desktop's default), the script adds you to group 10 (`uucp`); open a new
WSL session afterwards. Check with `podman system connection list` and `podman run quay.io/podman/hello`.
