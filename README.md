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

Inside an existing WSL Ubuntu you can run just `./wsl-setup.sh [git_name] [git_email]` as your normal user.

# Changing tool versions
Edit `config/mise.toml`, then:
```sh
mise install     # apply pinned versions
mise upgrade     # bump anything set to "latest"
```
`config/mise.toml` is symlinked to `~/.config/mise/config.toml`.

# Python with uv
```sh
uv init myproj && cd myproj
uv add requests
uv sync          # create/refresh .venv
uv run python main.py
```

# Containers
`podman` runs rootless and `docker` is aliased to it (see `config/aliases.sh`).
